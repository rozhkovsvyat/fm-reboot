# Overview staleness checker — runs on SessionStart (after setup.ps1 has done git pull).
# Сравнивает commit'ы триггер-путей с последним апдейтом meta/project-overview.md.
# Если триггер-путь обновлялся после overview — выводит JSON с additionalContext-напоминанием.
# Сам по себе не тратит токены агента: запускается как PowerShell-скрипт; токены тратятся
# только когда агент решит запустить /update-overview по этому напоминанию.

param(
    [string]$EventName = 'SessionStart'
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$vaultRoot = Split-Path -Parent $PSScriptRoot
$logPath = Join-Path $PSScriptRoot 'overview-hook.log'

function Write-Diag($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "[$ts] [$EventName] $msg" -Encoding UTF8
}

Write-Diag "fired; vault=$vaultRoot"

$overviewPath = 'meta/project-overview.md'
$triggers = @('decisions/', 'product/', 'rules/', 'state/now.md', 'team/', 'meta/CLAUDE.md')

# Last commit that touched the overview itself.
$overviewCommit = (& git -C $vaultRoot log -1 --format=%H -- $overviewPath) 2>$null
if (-not $overviewCommit) {
    Write-Diag "overview never committed (или нет git-истории) — skip"
    exit 0
}
$overviewCommit = $overviewCommit.Trim()

# Commits since overview that touched any trigger path.
$range = "${overviewCommit}..HEAD"
$gitArgs = @('-C', $vaultRoot, 'log', '--oneline', $range, '--') + $triggers
$staleOutput = (& git @gitArgs) 2>$null
if (-not $staleOutput) {
    Write-Diag "overview актуален; overviewCommit=$overviewCommit"
    exit 0
}

$staleCount = ($staleOutput -split "`r?`n" | Where-Object { $_ -ne '' }).Count
Write-Diag "stale; overviewCommit=$overviewCommit staleCount=$staleCount"

# Дедуп: считаем хеш от (overviewCommit + список stale-коммитов). Если в текущей сессии уже сообщали
# про ту же конфигурацию — молчим. Announced-файл затирается setup.ps1 на SessionStart.
$contentToHash = "$overviewCommit||$staleOutput"
$md5 = [System.Security.Cryptography.MD5]::Create()
$contentHash = [System.BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($contentToHash))).Replace('-','')

$announcedPath = Join-Path $PSScriptRoot 'overview-announced.txt'
$lastAnnounced = ''
if (Test-Path $announcedPath) {
    $lastAnnounced = (Get-Content $announcedPath -Raw -Encoding UTF8).Trim()
}

if ($contentHash -eq $lastAnnounced) {
    Write-Diag "dedup: hash=$contentHash совпал с last-announced — silent"
    exit 0
}

$msg = "OVERVIEW: ``meta/project-overview.md`` возможно устарел — после его последнего апдейта было $staleCount коммит(ов), затронувших триггер-пути (decisions/, product/, rules/, state/now.md, team/, meta/CLAUDE.md). Это мягкое напоминание, не блокер. В конце ответа на основной запрос предложи пользователю запустить ``/update-overview`` (или вызови сам, если по контексту разговора это уместно сделать сразу)."

$payload = @{
    hookSpecificOutput = @{
        hookEventName     = $EventName
        additionalContext = $msg
    }
} | ConvertTo-Json -Compress

Write-Output $payload

Set-Content -Path $announcedPath -Value $contentHash -Encoding UTF8
Write-Diag "emitted; hash=$contentHash recorded"

exit 0
