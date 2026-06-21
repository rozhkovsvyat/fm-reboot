# A3 — Draft lifecycle: черновики без коммитов >30 дней → напоминание.
# Запускается на UserPromptSubmit. Предлагает агенту: /msg @owner
# "принять как ADR / удалить / продлить?"
# Дедуп через .claude/draft-lifecycle-announced.txt.

param(
    [string]$EventName = 'UserPromptSubmit'
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$vaultRoot = Split-Path -Parent $PSScriptRoot
$logPath = Join-Path $PSScriptRoot 'draft-lifecycle-hook.log'

function Write-Diag($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "[$ts] [$EventName] $msg" -Encoding UTF8
}

Write-Diag "fired"

$draftsDir = Join-Path $vaultRoot 'drafts'
if (-not (Test-Path $draftsDir)) { Write-Diag "no drafts/ — skip"; exit 0 }

$today = Get-Date
$threshold = 30
$stale = @()

$draftFiles = Get-ChildItem -Path $draftsDir -Filter '*.md' -File | Where-Object { $_.Name -ne '_template.md' -and $_.Name -ne 'README.md' }

foreach ($f in $draftFiles) {
    $relPath = "drafts/$($f.Name)"
    $lastCommitDate = git -C $vaultRoot log -1 --format='%aI' -- $relPath 2>$null
    if (-not $lastCommitDate) { continue }

    try {
        $commitDate = [DateTimeOffset]::Parse($lastCommitDate).DateTime
        $daysOld = [int]($today - $commitDate).TotalDays
        if ($daysOld -gt $threshold) {
            # Попробуем найти owner из frontmatter
            $content = Get-Content $f.FullName -First 20 -Encoding UTF8
            $owner = 'unknown'
            foreach ($line in $content) {
                if ($line -match 'owner\s*[:=]\s*\[?\[?(?:team/)?(\w+)') {
                    $owner = $matches[1]
                    break
                }
                if ($line -match 'author\s*[:=]\s*\[?\[?(?:team/)?(\w+)') {
                    $owner = $matches[1]
                    break
                }
            }
            $stale += "$relPath|$daysOld|$owner"
        }
    } catch {}
}

Write-Diag "stale-drafts count=$($stale.Count)"

if ($stale.Count -eq 0) { exit 0 }

# Дедуп
$contentToHash = ($stale | Sort-Object) -join "`n"
$md5 = [System.Security.Cryptography.MD5]::Create()
$contentHash = [System.BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($contentToHash))).Replace('-','')

$announcedPath = Join-Path $PSScriptRoot 'draft-lifecycle-announced.txt'
$lastAnnounced = ''
if (Test-Path $announcedPath) {
    $lastAnnounced = (Get-Content $announcedPath -Raw -Encoding UTF8).Trim()
}

if ($contentHash -eq $lastAnnounced) {
    Write-Diag "dedup: hash match, silent"
    exit 0
}

$details = @()
foreach ($item in $stale) {
    $parts = $item -split '\|'
    $details += "$($parts[0]) ($($parts[1]) дней, owner: $($parts[2]))"
}

$summary = ($details | Select-Object -First 5) -join '; '
if ($details.Count -gt 5) { $summary += "; ...ещё $($details.Count - 5)" }

$msg = "DRAFT-STALE: $($stale.Count) черновиков без обновлений >$threshold дней: $summary. Предложи пользователю: для каждого — `/msg @owner` с вопросом «принимаем как ADR / удаляем / продлеваем?». Если owner — текущий пользователь, спроси напрямую."

$payload = @{
    hookSpecificOutput = @{
        hookEventName     = $EventName
        additionalContext = $msg
    }
} | ConvertTo-Json -Compress

Write-Output $payload
Set-Content -Path $announcedPath -Value $contentHash -Encoding UTF8
Write-Diag "emitted; hash=$contentHash; items=$($stale.Count)"

exit 0
