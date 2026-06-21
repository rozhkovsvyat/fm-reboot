# SessionStart house-keeping: перемещает старые daily-файлы (>30 дней) в state/daily/archive/YYYY/.
#
# Держит state/daily/ чистой (только активные 30 дней), более старые файлы переезжают в archive/.
# Минимальный буфер: текущая + предыдущая неделя (14 дней) никогда не архивируются.
#
# 🔴 DRAFT — не зарегистрирован в settings.json/SessionStart; подключить после ревью.

param(
    [string]$EventName    = 'SessionStart',
    [int]$DailyAgeDays    = 30,   # файлы старше этого порога переезжают в archive/
    [switch]$DryRun
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$vaultRoot = Split-Path -Parent $PSScriptRoot
$logPath   = Join-Path $PSScriptRoot 'archive-old-daily-hook.log'

function Write-Diag($msg) {
    $ts     = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $prefix = if ($DryRun) { '[DRY-RUN]' } else { '' }
    Add-Content -Path $logPath -Value "[$ts] [$EventName]$prefix $msg" -Encoding UTF8
}

Write-Diag "fired (ageDays=${DailyAgeDays}, dryRun=$DryRun)"

$dailyDir   = Join-Path $vaultRoot 'state/daily'
$archiveDir = Join-Path $dailyDir  'archive'

if (-not (Test-Path $dailyDir)) { Write-Diag "state/daily/ not found - skip"; exit 0 }

$today      = Get-Date
$cutoffDt   = $today.AddDays(-$DailyAgeDays)
$safeBuffer = $today.AddDays(-14)  # жёсткий минимальный буфер (2 недели)
$effectiveCutoff = if ($cutoffDt -lt $safeBuffer) { $cutoffDt } else { $safeBuffer }

Write-Diag "effective cutoff: $($effectiveCutoff.ToString('yyyy-MM-dd')) (threshold=${DailyAgeDays}d, buffer=14d)"

# Собираем daily-файлы для архивирования (исключаем archive/ и _template.md)
$dailyFiles = Get-ChildItem -Path $dailyDir -Filter '*.md' -File |
              Where-Object { $_.DirectoryName -eq $dailyDir -and $_.Name -ne '_template.md' }

$toMove    = [System.Collections.ArrayList]@()
$skipped   = 0

foreach ($f in $dailyFiles) {
    $name = $f.BaseName
    if ($name -notmatch '^\d{4}-\d{2}-\d{2}$') { $skipped++; continue }
    try {
        $fileDate = [datetime]::ParseExact($name, 'yyyy-MM-dd', $null)
    } catch { $skipped++; continue }

    if ($fileDate -ge $effectiveCutoff) { $skipped++; continue }
    [void]$toMove.Add($f)
}

Write-Diag "found $($toMove.Count) file(s) to archive, $skipped kept/skipped"

if ($toMove.Count -eq 0) { Write-Diag "nothing to archive"; exit 0 }

if ($DryRun) {
    foreach ($f in $toMove) {
        $yr          = $f.BaseName.Substring(0, 4)
        $destDir     = Join-Path $archiveDir $yr
        Write-Host "[DRY-RUN] would move $($f.Name) → state/daily/archive/$yr/"
    }
    Write-Diag "dry-run: $($toMove.Count) file(s) would be moved"
    exit 0
}

$moved = 0
foreach ($f in $toMove) {
    $yr      = $f.BaseName.Substring(0, 4)
    $destDir = Join-Path $archiveDir $yr
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir | Out-Null
        Write-Diag "created archive dir: state/daily/archive/$yr/"
    }
    $dest = Join-Path $destDir $f.Name
    if (Test-Path $dest) {
        Write-Diag "  skip (already exists): $($f.Name)"
        continue
    }
    Move-Item -Path $f.FullName -Destination $dest
    Write-Diag "  moved: $($f.Name) → archive/$yr/"
    $moved++
}

Write-Diag "done: moved $moved file(s)"
exit 0
