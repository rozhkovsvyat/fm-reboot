# SessionStart housekeeping: помечает старые @all broadcasts как ✅ во ВСЕХ inbox/*.md.
# Broadcast = строка с "(broadcast @all)" или "(broadcast". Личные сообщения не трогаем.
# Порог: 5 дней. Идемпотентно. Без LLM.

param(
    [string]$EventName = 'SessionStart'
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$vaultRoot = Split-Path -Parent $PSScriptRoot
$logPath = Join-Path $PSScriptRoot 'archive-broadcasts-hook.log'

function Write-Diag($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "[$ts] [$EventName] $msg" -Encoding UTF8
}

Write-Diag "fired"

$inboxDir = Join-Path $vaultRoot 'inbox'
if (-not (Test-Path $inboxDir)) { Write-Diag "no inbox/ — skip"; exit 0 }

$today = Get-Date
$threshold = 5
$totalArchived = 0

$inboxFiles = Get-ChildItem -Path $inboxDir -Filter '*.md' -File

foreach ($f in $inboxFiles) {
    $content = Get-Content $f.FullName -Raw -Encoding UTF8
    if (-not $content) { continue }

    $lines = $content -split "`r?`n"
    $changed = $false
    $archived = 0

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]

        # Ищем строки с 🟡 + broadcast
        if ($line -match '^\s*-\s*🟡' -and $line -match '\(broadcast') {
            # Извлекаем дату из формата **YYYY-MM-DD
            if ($line -match '\*\*(\d{4}-\d{2}-\d{2})') {
                try {
                    $msgDate = [DateTime]::ParseExact($matches[1], 'yyyy-MM-dd', $null)
                    $daysOld = [int]($today - $msgDate).TotalDays
                    if ($daysOld -gt $threshold) {
                        $lines[$i] = $line -replace '🟡', '✅'
                        $changed = $true
                        $archived++
                    }
                } catch {
                    Write-Diag "parse error in $($f.Name) line $i"
                }
            }
        }
    }

    if ($changed) {
        $newContent = $lines -join "`r`n"
        Set-Content -Path $f.FullName -Value $newContent -Encoding UTF8 -NoNewline
        Write-Diag "$($f.Name): archived $archived broadcast(s)"
        $totalArchived += $archived
    }
}

Write-Diag "total archived: $totalArchived across $($inboxFiles.Count) inbox files"
exit 0
