# Б1 — Расширенный stale-check: services (14 дней), decisions на ревью (7 дней), drafts (7 дней).
# Дополняет check-now-stale.ps1 (который проверяет только state/now.md).
# Запускается на UserPromptSubmit. Дедуп через .claude/stale-extended-announced.txt.

param(
    [string]$EventName = 'UserPromptSubmit'
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$vaultRoot = Split-Path -Parent $PSScriptRoot
$logPath = Join-Path $PSScriptRoot 'stale-extended-hook.log'

function Write-Diag($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "[$ts] [$EventName] $msg" -Encoding UTF8
}

Write-Diag "fired"

$today = Get-Date
$stale = @()

# --- 1. Services: файлы в product/services/ не обновлявшиеся >14 дней (по git log) ---
$servicesDir = Join-Path $vaultRoot 'product/services'
if (Test-Path $servicesDir) {
    $serviceFiles = Get-ChildItem -Path $servicesDir -Filter '*.md' -File | Where-Object { $_.Name -ne '_template.md' }
    foreach ($f in $serviceFiles) {
        $relPath = "product/services/$($f.Name)"
        $lastCommitDate = git -C $vaultRoot log -1 --format='%aI' -- $relPath 2>$null
        if ($lastCommitDate) {
            try {
                $commitDate = [DateTimeOffset]::Parse($lastCommitDate).DateTime
                $daysOld = [int]($today - $commitDate).TotalDays
                if ($daysOld -gt 14) {
                    $stale += "service|$relPath|$daysOld"
                }
            } catch {}
        }
    }
}

# --- 2. Decisions на ревью: frontmatter status содержит "на ревью" и не обновлялись >7 дней ---
$decisionsDir = Join-Path $vaultRoot 'decisions'
if (Test-Path $decisionsDir) {
    $adrFiles = Get-ChildItem -Path $decisionsDir -Filter '*.md' -File | Where-Object { $_.Name -ne '_template.md' }
    foreach ($f in $adrFiles) {
        $content = Get-Content $f.FullName -Raw -Encoding UTF8
        if ($content -match '(?i)статус.*на ревью') {
            $relPath = "decisions/$($f.Name)"
            $lastCommitDate = git -C $vaultRoot log -1 --format='%aI' -- $relPath 2>$null
            if ($lastCommitDate) {
                try {
                    $commitDate = [DateTimeOffset]::Parse($lastCommitDate).DateTime
                    $daysOld = [int]($today - $commitDate).TotalDays
                    if ($daysOld -gt 7) {
                        $stale += "adr-review|$relPath|$daysOld"
                    }
                } catch {}
            }
        }
    }
}

# --- 3. Drafts: не обновлялись >7 дней ---
$draftsDir = Join-Path $vaultRoot 'drafts'
if (Test-Path $draftsDir) {
    $draftFiles = Get-ChildItem -Path $draftsDir -Filter '*.md' -File | Where-Object { $_.Name -ne '_template.md' }
    foreach ($f in $draftFiles) {
        $relPath = "drafts/$($f.Name)"
        $lastCommitDate = git -C $vaultRoot log -1 --format='%aI' -- $relPath 2>$null
        if ($lastCommitDate) {
            try {
                $commitDate = [DateTimeOffset]::Parse($lastCommitDate).DateTime
                $daysOld = [int]($today - $commitDate).TotalDays
                if ($daysOld -gt 7) {
                    $stale += "draft|$relPath|$daysOld"
                }
            } catch {}
        }
    }
}

Write-Diag "stale-extended count=$($stale.Count)"

if ($stale.Count -eq 0) { exit 0 }

# Дедуп
$contentToHash = ($stale | Sort-Object) -join "`n"
$md5 = [System.Security.Cryptography.MD5]::Create()
$contentHash = [System.BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($contentToHash))).Replace('-','')

$announcedPath = Join-Path $PSScriptRoot 'stale-extended-announced.txt'
$lastAnnounced = ''
if (Test-Path $announcedPath) {
    $lastAnnounced = (Get-Content $announcedPath -Raw -Encoding UTF8).Trim()
}

if ($contentHash -eq $lastAnnounced) {
    Write-Diag "dedup: hash match, silent"
    exit 0
}

# Формируем сообщение
$serviceStale = @($stale | Where-Object { $_ -match '^service\|' })
$adrStale = @($stale | Where-Object { $_ -match '^adr-review\|' })
$draftStale = @($stale | Where-Object { $_ -match '^draft\|' })

$parts = @()
if ($serviceStale.Count -gt 0) {
    $names = ($serviceStale | ForEach-Object { ($_ -split '\|')[1] }) -join ', '
    $parts += "$($serviceStale.Count) карточек сервисов >14 дней ($names)"
}
if ($adrStale.Count -gt 0) {
    $names = ($adrStale | ForEach-Object { ($_ -split '\|')[1] }) -join ', '
    $parts += "$($adrStale.Count) ADR на ревью >7 дней ($names)"
}
if ($draftStale.Count -gt 0) {
    $names = ($draftStale | ForEach-Object { ($_ -split '\|')[1] }) -join ', '
    $parts += "$($draftStale.Count) черновиков >7 дней ($names)"
}

$msg = "STALE-EXT: " + ($parts -join '; ') + ". Упомяни пользователю одной строкой. Для ADR на ревью — предложи эскалацию через /msg @<коллега> или подними напрямую с пользователем. Для черновиков — спроси у owner'а: принять как ADR / удалить / продлить."

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
