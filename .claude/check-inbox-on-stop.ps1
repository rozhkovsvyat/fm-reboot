# Stop hook — повторная проверка inbox перед финальным ответом агента.
#
# Use case: marchuk написал промпт, агент работает, во время работы Obsidian Git
# подтянул новое сообщение от rozhkov. Агент должен УВИДЕТЬ его до закрытия
# сессии, обдумать как влияет на только что сделанное, и при необходимости
# внести правки перед финальным ответом пользователю.
#
# Логика: считает текущие 🟡 в inbox, сравнивает хеш с .claude/inbox-announced.txt
# (который писал check-inbox.ps1 на UserPromptSubmit). Если хеш не совпал —
# значит появились новые сообщения за время работы. Эмитит INBOX-EOT с
# инструкцией обработать ДО финального ответа.
#
# Если хеш совпал (никаких новых не пришло) — молчит.

param(
    [string]$EventName = 'Stop'
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$logPath = Join-Path $PSScriptRoot 'inbox-stop-hook.log'
function Write-Diag($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "[$ts] [$EventName] $msg" -Encoding UTF8
}

Write-Diag "fired"

$vaultRoot = Split-Path -Parent $PSScriptRoot

# kb.author: try local config first, then global.
$author = (& git -C $vaultRoot config kb.author) 2>$null
if ($LASTEXITCODE -ne 0 -or -not $author) {
    $author = (& git config --global kb.author) 2>$null
}
if (-not $author) {
    Write-Diag "kb.author not set — exiting"
    exit 0
}
$author = $author.Trim()

$inboxPath = Join-Path $vaultRoot "inbox/$author.md"
Write-Diag "author=$author inbox=$inboxPath exists=$(Test-Path $inboxPath)"

if (-not (Test-Path $inboxPath)) { exit 0 }

# Inbox-loop suppression: если активен inbox-loop (свежий heartbeat) — молчим,
# его агент сам обрабатывает inbox в реальном времени. См. check-inbox.ps1.
# Adaptive interval (2026-05-29): читаем current_interval из /tmp/fm-reboot-inbox-loop-state,
# legacy fallback — heartbeat content, final fallback — 60 мин.
# LOCAL PATCH 2026-05-27: путь перенесён в /tmp/ — см. check-inbox.ps1.
$heartbeatPath = '/tmp/fm-reboot-inbox-loop-heartbeat'
$statePath = '/tmp/fm-reboot-inbox-loop-state'
if (Test-Path $heartbeatPath) {
    $intervalMin = 60   # safe upper-bound default
    if (Test-Path $statePath) {
        try {
            $stateContent = (Get-Content $statePath -Raw -ErrorAction SilentlyContinue).Trim()
            if ($stateContent -match 'interval:(\d+)') { $intervalMin = [int]$Matches[1] }
        } catch {}
    } else {
        try {
            $hbContent = (Get-Content $heartbeatPath -Raw -ErrorAction SilentlyContinue).Trim()
            if ($hbContent -match '^\d+$') { $intervalMin = [int]$hbContent }
        } catch {}
    }
    if ($intervalMin -lt 1) { $intervalMin = 60 }
    $ttlMin = $intervalMin * 2.5
    $ageMin = ((Get-Date) - (Get-Item $heartbeatPath).LastWriteTime).TotalMinutes
    if ($ageMin -lt $ttlMin) {
        Write-Diag "inbox-loop active (heartbeat age=$([math]::Round($ageMin,1))min < ttl=$ttlMin min, interval=$intervalMin) — suppressing INBOX-EOT"
        exit 0
    }
}

$unreadLines = Select-String -Path $inboxPath -Pattern '^\s*-\s*🟡' -Encoding UTF8 | ForEach-Object { $_.Line.Trim() }
$unread = $unreadLines.Count
Write-Diag "unread=$unread"

if ($unread -le 0) { exit 0 }

# Считаем хеш текущих 🟡-строк.
$contentToHash = ($unreadLines | Sort-Object) -join "`n"
$md5 = [System.Security.Cryptography.MD5]::Create()
$contentHash = [System.BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($contentToHash))).Replace('-','')

# Сравниваем с тем что объявлено на UserPromptSubmit. Если совпало — пользователь
# уже видел эти сообщения, агент должен был их обработать в основной обработке,
# и Stop-хук молчит. Если не совпало — за время работы появилось что-то новое.
$announcedPath = Join-Path $PSScriptRoot 'inbox-announced.txt'
$lastAnnounced = ''
if (Test-Path $announcedPath) {
    $lastAnnounced = (Get-Content $announcedPath -Raw -Encoding UTF8).Trim()
}

if ($contentHash -eq $lastAnnounced) {
    Write-Diag "dedup: hash=$contentHash совпал с announced — никаких новых сообщений за время работы"
    exit 0
}

$relPath = "inbox/$author.md"
$msg = "INBOX-EOT: $unread непрочитанных в ``$relPath`` — хеш отличается от announced на UserPromptSubmit. Это значит, что **за время твоей работы пришли новые сообщения** (мид-сессионный Obsidian Git pull). **ОБЯЗАТЕЛЬНО** обработай их ДО финального ответа пользователю: (1) Прочитай каждое 🟡 — определи, какие СВЕЖИЕ (отсутствовали в начале работы, теперь есть). (2) Оцени: влияют ли они на только что выполненную работу? Если да — внеси правки в свою работу (отменить/доделать/уточнить). (3) Обнови ``state/daily/$([DateTime]::Now.ToString('yyyy-MM-dd')).md`` если правки внёс. (4) Действия по сообщениям — как в основном INBOX-протоколе (см. ``meta/CLAUDE.md``): информационные → строкой в ответе; вопросы → ``/msg @sender``; ревью → запись в daily + ``/msg @sender``; разрушительные → ``AskUserQuestion``. (5) Замени 🟡 → ✅ через Edit. (6) В финальном ответе строкой: «Inbox-EOT: обработано N свежих сообщений, влияние на работу: <да/нет/детали>». Только после этого — финальный ответ пользователю."

# LOCAL PATCH 2026-05-27 (savchuk): Stop event не поддерживает hookSpecificOutput.
# Используем верхнеуровневый systemMessage (валидно для Stop/SessionEnd).
$payload = @{
    systemMessage = $msg
} | ConvertTo-Json -Compress

Write-Output $payload

# Обновляем announced-хеш — после Stop эти сообщения считаются «увиденными».
Set-Content -Path $announcedPath -Value $contentHash -Encoding UTF8
Write-Diag "emitted; hash=$contentHash recorded"

exit 0
