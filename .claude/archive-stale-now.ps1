# SessionStart house-keeping: архивирует STALE (не-✅) строки из таблицы «В работе» в state/now.md
# в state/daily/<today>.md, если поле «Обновлено» строки не обновлялось более $StaleDays дней.
#
# Дополняет archive-completed-now.ps1 (тот ведёт только ✅-строки).
# Этот скрипт ведёт 🟢/🟡/🔴/⚪ строки которые «забыли» обновить или закрыть.
#
# Скрипт детерминированный (без LLM), идемпотентный.
# 🔴 DRAFT — не зарегистрирован в settings.json/SessionStart; подключить после ревью.

param(
    [string]$EventName = 'SessionStart',
    [int]$StaleDays    = 14,   # порог устаревания для не-✅ строк
    [switch]$DryRun
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$vaultRoot = Split-Path -Parent $PSScriptRoot
$logPath   = Join-Path $PSScriptRoot 'archive-stale-now-hook.log'

function Write-Diag($msg) {
    $ts     = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $prefix = if ($DryRun) { '[DRY-RUN]' } else { '' }
    Add-Content -Path $logPath -Value "[$ts] [$EventName]$prefix $msg" -Encoding UTF8
}

Write-Diag "fired (staleDays=${StaleDays}, dryRun=$DryRun)"

$nowPath   = Join-Path $vaultRoot 'state/now.md'
$today     = (Get-Date).ToString('yyyy-MM-dd')
$dailyPath = Join-Path $vaultRoot "state/daily/$today.md"

if (-not (Test-Path $nowPath)) { Write-Diag "now.md not found - skip"; exit 0 }

$content  = Get-Content $nowPath -Raw -Encoding UTF8
$lines    = $content -split "`r?`n"
$todayDt  = [datetime]::ParseExact($today, 'yyyy-MM-dd', $null)
$cutoffDt = $todayDt.AddDays(-$StaleDays)

# Локализуем секцию «## В работе»
$startIdx = -1
$endIdx   = $lines.Length - 1
for ($i = 0; $i -lt $lines.Length; $i++) {
    if ($lines[$i] -match '^##\s+В\s+работе\s*$') { $startIdx = $i; continue }
    if ($startIdx -ge 0 -and $lines[$i] -match '^##\s+\S') { $endIdx = $i - 1; break }
}
if ($startIdx -lt 0) { Write-Diag "section «В работе» not found - skip"; exit 0 }

$toArchive       = New-Object System.Collections.ArrayList
$indicesToRemove = New-Object System.Collections.Generic.HashSet[int]
$headerCount     = 0

for ($i = $startIdx + 1; $i -le $endIdx; $i++) {
    $line = $lines[$i]
    if ($line -notmatch '^\s*\|') { continue }
    if ($headerCount -lt 2) { $headerCount++; continue }

    $cells = $line -split '\|' | ForEach-Object { $_.Trim() }
    if ($cells.Length -lt 8) { continue }

    $status  = $cells[5]
    $updated = $cells[6]

    # Пропускаем ✅ — их ведёт archive-completed-now.ps1
    if ($status -match '✅') { continue }

    if ($updated -notmatch '(\d{4}-\d{2}-\d{2})') { continue }
    try {
        $rowDate = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd', $null)
    } catch { continue }

    if ($rowDate -ge $cutoffDt) { continue }  # свежее порога — оставляем

    [void]$toArchive.Add($line)
    [void]$indicesToRemove.Add($i)
}

if ($toArchive.Count -eq 0) { Write-Diag "no stale rows to archive"; exit 0 }

if ($DryRun) {
    Write-Host "[DRY-RUN] would archive $($toArchive.Count) stale row(s) from now.md to $today"
    foreach ($row in $toArchive) { Write-Host "  $row" }
    Write-Diag "dry-run: $($toArchive.Count) row(s) would be archived"
    exit 0
}

# Готовим daily-файл
if (-not (Test-Path $dailyPath)) {
    $stub = "# $today`n`n> Дневной лог команды.`n"
    Set-Content -Path $dailyPath -Value $stub -Encoding UTF8
    Write-Diag "created daily stub: $dailyPath"
}

$dailyRaw      = Get-Content $dailyPath -Raw -Encoding UTF8
$archiveHeader = '## Архив из now.md (stale)'
if ($dailyRaw -notmatch [regex]::Escape($archiveHeader)) {
    $note      = "> Автоматически перенесено ``archive-stale-now.ps1`` (не-✅ строки, «Обновлено» > ${StaleDays} дней)."
    $tableHead = "| Кто | Что | Сервис | Ветка/PR | Статус | Обновлено |`n|---|---|---|---|---|---|"
    $dailyRaw  += "`n`n$archiveHeader`n`n$note`n`n$tableHead`n"
}
foreach ($row in $toArchive) { $dailyRaw += "$row`n" }
Set-Content -Path $dailyPath -Value $dailyRaw -Encoding UTF8

# Удаляем строки из now.md
$newLines = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt $lines.Length; $i++) {
    if (-not $indicesToRemove.Contains($i)) { [void]$newLines.Add($lines[$i]) }
}
Set-Content -Path $nowPath -Value ($newLines -join "`r`n") -Encoding UTF8

Write-Diag "archived $($toArchive.Count) stale row(s) to $today"
exit 0
