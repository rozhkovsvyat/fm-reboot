# UserPromptSubmit hook: периодический нудж запустить inbox-adequacy аудит.
#
# Закрывает дефект «агент никогда не предлагает проверить инбоксы на адекватность»:
# скилл /inbox-adequacy существует, но ничто его не триггерит. Memory/правило не
# заставят проактивно предлагать (automated behavior = hook, не memory). Этот хук
# раз в INTERVAL_DAYS эмитит INBOX-ADEQUACY-DUE, чтобы агент предложил аудит.
#
# НЕ сбрасывается на SessionStart (в отличие от *-announced.txt) — каденция должна
# переживать рестарты. Состояние — .claude/inbox-adequacy-due.txt (дата последнего эмита).
# Soft reminder, не блокер. Дедуп — by дата + интервал.
#
# СТАТУС: активирован в settings.json (UserPromptSubmit) 2026-06-19. Ручной прогон:
#   pwsh .claude/check-inbox-adequacy-due.ps1
# Лог — .claude/inbox-adequacy-due-hook.log

param(
    [string]$EventName = 'UserPromptSubmit'
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$logPath = Join-Path $PSScriptRoot 'inbox-adequacy-due-hook.log'
function Write-Diag($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "[$ts] [$EventName] $msg" -Encoding UTF8
}

Write-Diag "fired"

$INTERVAL_DAYS = 14
$duePath = Join-Path $PSScriptRoot 'inbox-adequacy-due.txt'
$today = Get-Date

$last = $null
if (Test-Path $duePath) {
    $raw = (Get-Content $duePath -Raw -Encoding UTF8).Trim()
    try { $last = [datetime]::ParseExact($raw, 'yyyy-MM-dd', $null) } catch { $last = $null }
}

if ($null -ne $last -and ($today - $last).Days -lt $INTERVAL_DAYS) {
    Write-Diag "not due (last=$($last.ToString('yyyy-MM-dd')), $(($today-$last).Days)d < $INTERVAL_DAYS) — silent"
    exit 0
}

$msg = "INBOX-ADEQUACY-DUE: inbox-файлы давно (≥$INTERVAL_DAYS дн) не проверялись на адекватность. Предложи пользователю ``/inbox-adequacy --all`` — read-only аудит: просроченные 🟡, 🟡-инфляция (🟡 в прозе вместо message-header), ошибки имён/glossary, PII/секреты, осиротевшие вопросы. Soft reminder, не блокер; запускается раз в $INTERVAL_DAYS дн."

if ($EventName -eq 'Stop' -or $EventName -eq 'SessionEnd') {
    $payload = @{ systemMessage = $msg } | ConvertTo-Json -Compress
} else {
    $payload = @{
        hookSpecificOutput = @{
            hookEventName     = $EventName
            additionalContext = $msg
        }
    } | ConvertTo-Json -Compress
}

Write-Output $payload
Set-Content -Path $duePath -Value $today.ToString('yyyy-MM-dd') -Encoding UTF8
Write-Diag "emitted; due-date set to $($today.ToString('yyyy-MM-dd'))"

exit 0
