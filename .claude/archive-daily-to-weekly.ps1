# SessionStart house-keeping: собирает структурный weekly-rollup из daily-файлов предыдущей ISO-недели.
#
# Триггер: если weekly/YYYY-Www.md предыдущей недели пуст/заглушка И есть daily-файлы за ту неделю.
# НЕ AI-синтез — детерминированная конкатенация с подзаголовками по дням.
# Семантическое заполнение шаблона (Что закрыли / Решения / ...) — задача /daily skill'а.
#
# 🔴 DRAFT — не зарегистрирован в settings.json/SessionStart; подключить после ревью.

param(
    [string]$EventName = 'SessionStart',
    [switch]$DryRun
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$vaultRoot = Split-Path -Parent $PSScriptRoot
$logPath   = Join-Path $PSScriptRoot 'archive-daily-to-weekly-hook.log'

function Write-Diag($msg) {
    $ts     = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $prefix = if ($DryRun) { '[DRY-RUN]' } else { '' }
    Add-Content -Path $logPath -Value "[$ts] [$EventName]$prefix $msg" -Encoding UTF8
}

Write-Diag "fired (dryRun=$DryRun)"

$dailyDir  = Join-Path $vaultRoot 'state/daily'
$weeklyDir = Join-Path $vaultRoot 'state/weekly'

if (-not (Test-Path $dailyDir)) { Write-Diag "state/daily/ not found - skip"; exit 0 }

$today       = Get-Date
$isoCalendar = [System.Globalization.ISOWeek]

# Определяем предыдущую ISO-неделю
$prevWeekDate = $today.AddDays(-7)
$prevYear     = $isoCalendar::GetYear($prevWeekDate)
$prevWeek     = $isoCalendar::GetWeekOfYear($prevWeekDate)
$prevWeekStr  = "$prevYear-W$($prevWeek.ToString('00'))"

# Первый и последний день предыдущей ISO-недели (Mon–Sun)
$prevWeekStart = $isoCalendar::ToDateTime($prevYear, $prevWeek, [DayOfWeek]::Monday)
$prevWeekEnd   = $prevWeekStart.AddDays(6)

Write-Diag "targeting week $prevWeekStr ($($prevWeekStart.ToString('yyyy-MM-dd')) – $($prevWeekEnd.ToString('yyyy-MM-dd')))"

# Ищем daily-файлы за эту неделю
$dailyFiles = @()
$d = $prevWeekStart
while ($d -le $prevWeekEnd) {
    $candidate = Join-Path $dailyDir "$($d.ToString('yyyy-MM-dd')).md"
    if (Test-Path $candidate) { $dailyFiles += $candidate }
    $d = $d.AddDays(1)
}

if ($dailyFiles.Count -eq 0) {
    Write-Diag "no daily files found for $prevWeekStr - skip"
    exit 0
}

# Проверяем weekly-файл: если уже содержит секцию «## Ежедневные логи» — пропустить (idempotent)
$weeklyPath = Join-Path $weeklyDir "$prevWeekStr.md"
if (Test-Path $weeklyPath) {
    $weeklyContent = Get-Content $weeklyPath -Raw -Encoding UTF8
    if ($weeklyContent -match '##\s+Ежедневные логи') {
        Write-Diag "weekly $prevWeekStr already has rollup section - skip (idempotent)"
        exit 0
    }
}

if ($DryRun) {
    Write-Host "[DRY-RUN] would rollup $($dailyFiles.Count) daily file(s) into state/weekly/$prevWeekStr.md"
    foreach ($f in $dailyFiles) { Write-Host "  $f" }
    Write-Diag "dry-run: would rollup $($dailyFiles.Count) file(s)"
    exit 0
}

# Создаём weekly-файл если нет
if (-not (Test-Path $weeklyDir)) {
    New-Item -ItemType Directory -Path $weeklyDir | Out-Null
}
if (-not (Test-Path $weeklyPath)) {
    $weekLabel = "Week $prevWeekStr ($($prevWeekStart.ToString('dd MMM')) – $($prevWeekEnd.ToString('dd MMM')))"
    $stub      = "# $weekLabel`n`n> Еженедельная сводка. Секции ниже — структурный rollup из state/daily/ (автоматически). Семантические секции (Что закрыли / Решения / ...) заполняются /daily skill'ом.`n"
    Set-Content -Path $weeklyPath -Value $stub -Encoding UTF8
    Write-Diag "created weekly stub: $weeklyPath"
}

# Формируем секцию «## Ежедневные логи»
$rollupLines = [System.Collections.ArrayList]@()
[void]$rollupLines.Add('')
[void]$rollupLines.Add('## Ежедневные логи')
[void]$rollupLines.Add('')
[void]$rollupLines.Add("> Автоматически собрано ``archive-daily-to-weekly.ps1`` (структурный rollup из state/daily/). Дата сборки: $(Get-Date -Format 'yyyy-MM-dd').")

foreach ($dailyPath in $dailyFiles | Sort-Object) {
    $dateStr = [IO.Path]::GetFileNameWithoutExtension($dailyPath)
    [void]$rollupLines.Add('')
    [void]$rollupLines.Add("### $dateStr")
    [void]$rollupLines.Add('')

    $dailyContent = Get-Content $dailyPath -Raw -Encoding UTF8
    # Убираем H1-заголовок (первую строку вида "# YYYY-MM-DD") чтобы не дублировать
    $dailyLines = ($dailyContent -split "`r?`n") | Where-Object { $_ -notmatch '^#\s+\d{4}-\d{2}-\d{2}\s*$' }
    foreach ($dline in $dailyLines) { [void]$rollupLines.Add($dline) }
}

# Атомарная запись: appending к weekly-файлу
$weeklyRaw  = Get-Content $weeklyPath -Raw -Encoding UTF8
$newContent = $weeklyRaw.TrimEnd() + ($rollupLines -join "`n") + "`n"
$tmpPath    = "$weeklyPath.tmp"
Set-Content -Path $tmpPath -Value $newContent -Encoding UTF8
Move-Item -Path $tmpPath -Destination $weeklyPath -Force

Write-Diag "rollup complete: $($dailyFiles.Count) daily file(s) → $prevWeekStr"
exit 0
