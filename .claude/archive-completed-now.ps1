# SessionStart house-keeping: архивирует ✅-записи из таблицы «В работе» в state/now.md
# в state/daily/<today>.md, если поле «Обновлено» строки < сегодня.
#
# Источник правила — легенда статусов в самом state/now.md:
#   "✅ готово — закрыто (живёт здесь не дольше 1 дня, потом уходит в daily/)"
#
# Скрипт детерминированный (без LLM), идемпотентный, безопасный для повторных запусков.
# Никогда не трогает строки со статусами 🟢 / 🟡 / 🔴 / ⚪.

param(
    [string]$EventName = 'SessionStart'
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$vaultRoot = Split-Path -Parent $PSScriptRoot
$logPath = Join-Path $PSScriptRoot 'archive-now-hook.log'

function Write-Diag($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "[$ts] [$EventName] $msg" -Encoding UTF8
}

Write-Diag "fired"

$nowPath = Join-Path $vaultRoot 'state/now.md'
$today = (Get-Date).ToString('yyyy-MM-dd')
$dailyPath = Join-Path $vaultRoot "state/daily/$today.md"

if (-not (Test-Path $nowPath)) { Write-Diag "now.md not found - skip"; exit 0 }

$content = Get-Content $nowPath -Raw -Encoding UTF8
$lines = $content -split "`r?`n"

# Локализуем секцию «## В работе»
$startIdx = -1
$endIdx = $lines.Length - 1
for ($i = 0; $i -lt $lines.Length; $i++) {
    if ($lines[$i] -match '^##\s+В\s+работе\s*$') { $startIdx = $i; continue }
    if ($startIdx -ge 0 -and $lines[$i] -match '^##\s+\S') { $endIdx = $i - 1; break }
}
if ($startIdx -lt 0) { Write-Diag "section «В работе» not found - skip"; exit 0 }

# Ищем строки таблицы в этой секции, идентифицируем ✅-строки с устаревшей датой
$todayDate = [datetime]::ParseExact($today, 'yyyy-MM-dd', $null)
$toArchive = New-Object System.Collections.ArrayList
$indicesToRemove = New-Object System.Collections.Generic.HashSet[int]
$headerCount = 0  # | Кто | ... | (1), |---|---| (2)

for ($i = $startIdx + 1; $i -le $endIdx; $i++) {
    $line = $lines[$i]
    if ($line -notmatch '^\s*\|') { continue }
    if ($headerCount -lt 2) { $headerCount++; continue }

    # Разбираем ячейки. Пайпы внутри [[wikilinks]] не страшны: ссылки используют ]], не |.
    $cells = $line -split '\|' | ForEach-Object { $_.Trim() }
    # cells[0] = "" (до первого |), cells[Length-1] = "" (после последнего |)
    # Структура: | Кто | Что | Сервис | Ветка/PR | Статус | Обновлено |
    # → cells[1..6] значимы. Дата = cells[6].
    if ($cells.Length -lt 8) { continue }

    $status = $cells[5]
    $updated = $cells[6]
    if ($status -notmatch '✅') { continue }

    if ($updated -notmatch '(\d{4}-\d{2}-\d{2})') { continue }
    $rowDate = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd', $null)
    if ($rowDate -ge $todayDate) { continue }  # сегодня или будущее — оставляем

    [void]$toArchive.Add($line)
    [void]$indicesToRemove.Add($i)
}

if ($toArchive.Count -eq 0) { Write-Diag "no rows to archive"; exit 0 }

# Готовим daily-файл
if (-not (Test-Path $dailyPath)) {
    $stub = "# $today`n`n> Дневной лог команды. Каждый дописывает свою секцию. AI-агенты добавляют записи от имени пользователя, под которым работают.`n"
    Set-Content -Path $dailyPath -Value $stub -Encoding UTF8
    Write-Diag "created daily stub: $dailyPath"
}

$dailyRaw = Get-Content $dailyPath -Raw -Encoding UTF8
$archiveHeader = '## Архив из now.md'
if ($dailyRaw -notmatch [regex]::Escape($archiveHeader)) {
    $dailyRaw += "`n`n$archiveHeader`n`n> Автоматически перенесено хуком ``.claude/archive-completed-now.ps1`` (✅-записи из ``state/now.md`` с датой «Обновлено» старше сегодня).`n`n| Кто | Что | Сервис | Ветка/PR | Статус | Обновлено |`n|---|---|---|---|---|---|`n"
}
foreach ($row in $toArchive) {
    $dailyRaw += "$row`n"
}
Set-Content -Path $dailyPath -Value $dailyRaw -Encoding UTF8

# Удаляем строки из now.md
$newLines = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt $lines.Length; $i++) {
    if (-not $indicesToRemove.Contains($i)) { [void]$newLines.Add($lines[$i]) }
}
Set-Content -Path $nowPath -Value ($newLines -join "`r`n") -Encoding UTF8

Write-Diag "archived $($toArchive.Count) row(s) to $today"
exit 0
