# Stop hook: дисциплина пост-работы.
# Если в последний час были коммиты в продуктовые папки vault'а (product/, decisions/,
# team/, state/now.md), но state/daily/<today>.md за этот час не трогался —
# emit reminder агенту: "обнови daily перед закрытием задачи".
#
# Логика грубая (по git log, не по transcript), но дёшево и работает с Obsidian Git
# auto-commit. Дедуп — by hour-bucket чтобы не дёргать на каждом Stop в одной "волне".

param(
    [string]$EventName = 'Stop'
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$vaultRoot = Split-Path -Parent $PSScriptRoot
$logPath = Join-Path $PSScriptRoot 'discipline-hook.log'

function Write-Diag($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "[$ts] [$EventName] $msg" -Encoding UTF8
}

Write-Diag "fired"

$today = (Get-Date).ToString('yyyy-MM-dd')
$dailyRel = "state/daily/$today.md"
$disciplinePaths = @('product/', 'decisions/', 'team/', 'state/now.md')

# Коммиты за последний час
$gitArgs = @('-C', $vaultRoot, 'log', '--since=1.hours.ago', '--name-only', '--pretty=format:__COMMIT__%H')
$rawLog = (& git @gitArgs) 2>$null
if (-not $rawLog) { Write-Diag "нет коммитов за час — skip"; exit 0 }

$lines = $rawLog -split "`r?`n" | Where-Object { $_ -ne '' -and -not $_.StartsWith('__COMMIT__') }
$touchedPaths = $lines | Sort-Object -Unique

# Был ли touched daily-файл сегодня?
$dailyTouched = $touchedPaths | Where-Object { $_ -eq $dailyRel -or $_ -eq "state/activity.md" }

# Был ли touched discipline-путь?
$disciplineTouched = $touchedPaths | Where-Object {
    $p = $_
    $disciplinePaths | Where-Object {
        if ($_.EndsWith('/')) { $p.StartsWith($_) } else { $p -eq $_ }
    }
}

Write-Diag "discipline=$($disciplineTouched.Count) daily/activity=$($dailyTouched.Count) total=$($touchedPaths.Count)"

if (-not $disciplineTouched -or $disciplineTouched.Count -eq 0) { exit 0 }
if ($dailyTouched -and $dailyTouched.Count -gt 0) { exit 0 }

# Дедуп по hour-bucket
$hourBucket = (Get-Date).ToString('yyyy-MM-dd-HH')
$announcedPath = Join-Path $PSScriptRoot 'discipline-announced.txt'
$lastBucket = ''
if (Test-Path $announcedPath) {
    $lastBucket = (Get-Content $announcedPath -Raw -Encoding UTF8).Trim()
}
if ($hourBucket -eq $lastBucket) {
    Write-Diag "dedup: bucket=$hourBucket совпал — silent"
    exit 0
}

$paths = ($disciplineTouched | Select-Object -First 4) -join ', '
$msg = "DISCIPLINE: за последний час были коммиты в $paths, но ``state/daily/$today.md`` или ``state/activity.md`` не обновлялись. По правилу из ``meta/CLAUDE.md`` (обязательный чек-лист) — после значимой работы дописать запись в ``state/daily/$today.md`` (создай файл, если нет, по формату последнего существующего) и/или строку в ``state/activity.md``. Сделай это до отправки финального ответа пользователю."

# LOCAL PATCH 2026-05-27 (savchuk): Stop event не поддерживает hookSpecificOutput.
$payload = @{
    systemMessage = $msg
} | ConvertTo-Json -Compress

Write-Output $payload
Set-Content -Path $announcedPath -Value $hourBucket -Encoding UTF8
Write-Diag "emitted; bucket=$hourBucket"

exit 0
