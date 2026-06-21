# Stale-check для state/now.md.
# Парсит markdown-таблицы, ищет cells с датой формата YYYY-MM-DD в колонке "Обновлено".
# Если хоть одна запись старше 5 дней — emit reminder агенту.
# Дедуп через .claude/now-announced.txt (затирается setup.ps1 на SessionStart).

param(
    [string]$EventName = 'UserPromptSubmit'
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$vaultRoot = Split-Path -Parent $PSScriptRoot
$logPath = Join-Path $PSScriptRoot 'now-stale-hook.log'

function Write-Diag($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "[$ts] [$EventName] $msg" -Encoding UTF8
}

Write-Diag "fired"

$nowPath = Join-Path $vaultRoot 'state/now.md'
if (-not (Test-Path $nowPath)) { Write-Diag "no state/now.md — skip"; exit 0 }

$today = Get-Date
$threshold = 5
$stale = @()

foreach ($line in (Get-Content $nowPath -Encoding UTF8)) {
    # Строки markdown-таблицы с датой YYYY-MM-DD в последней ячейке.
    if ($line -match '^\s*\|.*\|\s*(\d{4}-\d{2}-\d{2})\s*\|\s*$') {
        try {
            $lineDate = [DateTime]::ParseExact($matches[1], 'yyyy-MM-dd', $null)
            $daysOld = [int]($today - $lineDate).TotalDays
            if ($daysOld -gt $threshold) {
                # Сохраним укороченный фрагмент для diagnostic
                $snippet = $line.Trim()
                if ($snippet.Length -gt 100) { $snippet = $snippet.Substring(0, 100) + '...' }
                $stale += "$($matches[1]) ($daysOld дн): $snippet"
            }
        } catch {
            Write-Diag "не смог распарсить дату из: $line"
        }
    }
}

Write-Diag "stale-count=$($stale.Count)"

if ($stale.Count -eq 0) { exit 0 }

# Дедуп: хеш списка stale entries
$contentToHash = ($stale | Sort-Object) -join "`n"
$md5 = [System.Security.Cryptography.MD5]::Create()
$contentHash = [System.BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($contentToHash))).Replace('-','')

$announcedPath = Join-Path $PSScriptRoot 'now-announced.txt'
$lastAnnounced = ''
if (Test-Path $announcedPath) {
    $lastAnnounced = (Get-Content $announcedPath -Raw -Encoding UTF8).Trim()
}

if ($contentHash -eq $lastAnnounced) {
    Write-Diag "dedup: hash совпал, silent"
    exit 0
}

$count = $stale.Count
$msg = "STALE: в ``state/now.md`` $count записей с полем «Обновлено» старше $threshold дней. Перед опорой на эти записи — упомяни пользователю одной строкой что они потенциально устарели и предложи проверить/обновить. Не удаляй сам без подтверждения. Сводка: " + (($stale | Select-Object -First 3) -join '; ')
if ($count -gt 3) { $msg += "; ...ещё $($count - 3)" }

$payload = @{
    hookSpecificOutput = @{
        hookEventName     = $EventName
        additionalContext = $msg
    }
} | ConvertTo-Json -Compress

Write-Output $payload
Set-Content -Path $announcedPath -Value $contentHash -Encoding UTF8
Write-Diag "emitted; hash=$contentHash"

exit 0
