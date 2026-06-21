# SessionStart + Stop house-keeping: переносит самые старые события из state/activity.md
# в state/weekly/<current-ISO-week>.md, если total > 100.
#
# Источник правила — шапка state/activity.md:
#   "Лента ограничена 100 записями: при превышении старые записи переезжают в weekly/"
#
# Порог 50 -> 100 и Stop-триггер добавлены 2026-06-16 (под темп ~27 событий/день +
# долгоживущие loop-сессии: SessionStart-only триггер давал 4-дневные окна без среза,
# из-за чего файл разрастался до ~385 событий / ~88k токенов).
#
# Формат activity.md: header + разделитель '---' + plain event-строки (newest first),
# каждое событие = строка, начинающаяся с даты YYYY-MM-DD, БЕЗ обёртки в code-fence.
# Сверху — самое свежее (по конвенции файла). Архивируем хвост (самые старые).
#
# (До 2026-05-27 хук искал события внутри ```-блока под «## События» — но реальный
#  формат feed'а fence-less, из-за чего overflow никогда не архивировался. Fix — см.
#  state/daily/2026-05-27 «Аудит памяти».)

param(
    [string]$EventName = 'SessionStart'
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$vaultRoot = Split-Path -Parent $PSScriptRoot
$logPath = Join-Path $PSScriptRoot 'archive-activity-hook.log'
$LIMIT = 100

function Write-Diag($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "[$ts] [$EventName] $msg" -Encoding UTF8
}

Write-Diag "fired"

$activityPath = Join-Path $vaultRoot 'state/activity.md'
if (-not (Test-Path $activityPath)) { Write-Diag "activity.md not found - skip"; exit 0 }

# ISO week (2026-W20-style)
$date = Get-Date
$isoYear = [System.Globalization.ISOWeek]::GetYear($date)
$isoWeek = [System.Globalization.ISOWeek]::GetWeekOfYear($date)
$weekStr = "$isoYear-W$($isoWeek.ToString('00'))"
$weeklyPath = Join-Path $vaultRoot "state/weekly/$weekStr.md"

$content = Get-Content $activityPath -Raw -Encoding UTF8
$lines = $content -split "`r?`n"

# Граница header'а — первый разделитель '---'. События ищем после него,
# чтобы не зацепить пример формата в шапке. Если '---' нет — ищем во всём файле.
$sepIdx = -1
for ($i = 0; $i -lt $lines.Length; $i++) {
    if ($lines[$i] -match '^---\s*$') { $sepIdx = $i; break }
}
$searchStart = if ($sepIdx -ge 0) { $sepIdx + 1 } else { 0 }

# Собираем индексы event-строк (начинаются с YYYY-MM-DD)
$eventIndices = @()
for ($i = $searchStart; $i -lt $lines.Length; $i++) {
    if ($lines[$i] -match '^\d{4}-\d{2}-\d{2}') { $eventIndices += $i }
}

$count = $eventIndices.Count
Write-Diag "events count = $count, limit = $LIMIT"
if ($count -le $LIMIT) { Write-Diag "no overflow"; exit 0 }

# Архивируем хвост (индексы с $LIMIT и далее = самые старые)
$overflowIndices = $eventIndices[$LIMIT..($count - 1)]
$toArchiveLines = @()
foreach ($idx in $overflowIndices) { $toArchiveLines += $lines[$idx] }

Write-Diag "archiving $($toArchiveLines.Count) event(s) -> $weekStr"

# Удаляем только сами overflow event-строки; осиротевшие пустые строки схлопнём ниже
$removeSet = @{}
foreach ($idx in $overflowIndices) { $removeSet[$idx] = $true }
$newLines = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt $lines.Length; $i++) {
    if ($removeSet.ContainsKey($i)) { continue }
    [void]$newLines.Add($lines[$i])
}
# Косметика: схлопнуть 3+ подряд пустых строки в одну
$joined = ($newLines -join "`n") -replace "(`n){3,}", "`n`n"
Set-Content -Path $activityPath -Value $joined -Encoding UTF8

# Готовим weekly-файл
if (-not (Test-Path $weeklyPath)) {
    $stub = "# Week $weekStr`n`n> Еженедельная сводка. Собирается из ``state/daily/`` + получает архив из ``state/activity.md`` при overflow.`n"
    Set-Content -Path $weeklyPath -Value $stub -Encoding UTF8
    Write-Diag "created weekly stub: $weeklyPath"
}

# Weekly держим как ОДНУ секцию «## Архив из activity.md» с ОДНИМ ```-блоком.
# Новые события вставляем в начало блока (newest сверху). Не плодим dated подсекции —
# это давало десятки фрагментированных «### Архивировано» + дубли (вычищено 2026-05-27).
$weeklyRaw = Get-Content $weeklyPath -Raw -Encoding UTF8
$fence = '```'

if ($weeklyRaw -match '##\s+Архив из activity\.md') {
    # Секция есть — найдём первый ```-fence после её заголовка и вставим события сразу после него
    $wlines = $weeklyRaw -split "`r?`n"
    $secIdx = -1; $fenceIdx = -1
    for ($i = 0; $i -lt $wlines.Length; $i++) {
        if ($secIdx -lt 0 -and $wlines[$i] -match '##\s+Архив из activity\.md') { $secIdx = $i; continue }
        if ($secIdx -ge 0 -and $wlines[$i] -match '^```') { $fenceIdx = $i; break }
    }
    if ($fenceIdx -ge 0) {
        $before = $wlines[0..$fenceIdx]
        $after = if (($fenceIdx + 1) -le ($wlines.Length - 1)) { $wlines[($fenceIdx + 1)..($wlines.Length - 1)] } else { @() }
        $merged = @($before) + $toArchiveLines + @($after)
        $weeklyRaw = ($merged -join "`n")
    } else {
        # секция без fence (аномалия) — добавим fence с событиями в конец
        $weeklyRaw += "`n$fence`n$($toArchiveLines -join "`n")`n$fence`n"
    }
} else {
    # Секции нет — создаём целиком
    $note = "> Автоматически перенесено хуком ``.claude/archive-activity-overflow.ps1`` (>50 событий в ``state/activity.md``). Самые свежие — сверху."
    $weeklyRaw = $weeklyRaw.TrimEnd() + "`n`n## Архив из activity.md`n`n$note`n`n$fence`n$($toArchiveLines -join "`n")`n$fence`n"
}

Set-Content -Path $weeklyPath -Value $weeklyRaw -Encoding UTF8

Write-Diag "archived $($toArchiveLines.Count) event(s) to $weekStr"
exit 0
