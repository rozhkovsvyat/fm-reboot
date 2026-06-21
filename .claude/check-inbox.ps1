# Inbox checker hook — works for both SessionStart and UserPromptSubmit.
# Reads inbox/<author>.md, counts 🟡 lines, emits additionalContext when unread > 0.
# Author handle from `git config kb.author`.

param(
    [string]$EventName = 'SessionStart'
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$logPath = Join-Path $PSScriptRoot 'inbox-hook.log'
function Write-Diag($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "[$ts] [$EventName] $msg" -Encoding UTF8
}

Write-Diag "fired; cwd=$(Get-Location); script=$PSCommandPath"

$vaultRoot = Split-Path -Parent $PSScriptRoot

# kb.author: try local config first (in case user runs from another repo), then global.
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

# Inbox-loop suppression: если на машине активен inbox-loop (свежий heartbeat) —
# молчим, его агент сам обработает inbox. Heartbeat = /tmp/fm-reboot-inbox-loop-heartbeat,
# mtime = время последнего тика. TTL = current_interval × 2.5.
# Current interval — adaptive (2026-05-29): читаем из /tmp/fm-reboot-inbox-loop-state
# (формат "empty_ticks:N interval:M"). Legacy fallback — content heartbeat файла.
# Final fallback — 60 мин (max possible adaptive interval, safe upper bound TTL 150min).
# После остановки лупа (вкладка закрыта → cron мёртв) heartbeat протухает → hook снова работает.
# LOCAL PATCH 2026-05-27: путь перенесён из .claude/ в /tmp/ т.к. .claude/ — hardcoded
# sensitive directory в Claude Code, "always allow" не персистится, prompts на каждый тик.
$heartbeatPath = '/tmp/fm-reboot-inbox-loop-heartbeat'
$statePath = '/tmp/fm-reboot-inbox-loop-state'
if (Test-Path $heartbeatPath) {
    $intervalMin = 60   # safe upper-bound default (max adaptive grow)
    $intervalSource = 'default-fallback'
    # 1. Adaptive: read interval from state file
    if (Test-Path $statePath) {
        try {
            $stateContent = (Get-Content $statePath -Raw -ErrorAction SilentlyContinue).Trim()
            if ($stateContent -match 'interval:(\d+)') {
                $intervalMin = [int]$Matches[1]
                $intervalSource = 'state-file'
            }
        } catch {}
    }
    # 2. Legacy: heartbeat content (if state file absent/invalid)
    if ($intervalSource -eq 'default-fallback') {
        try {
            $hbContent = (Get-Content $heartbeatPath -Raw -ErrorAction SilentlyContinue).Trim()
            if ($hbContent -match '^\d+$') {
                $intervalMin = [int]$hbContent
                $intervalSource = 'heartbeat-content'
            }
        } catch {}
    }
    if ($intervalMin -lt 1) { $intervalMin = 60 }
    $ttlMin = $intervalMin * 2.5
    $ageMin = ((Get-Date) - (Get-Item $heartbeatPath).LastWriteTime).TotalMinutes
    if ($ageMin -lt $ttlMin) {
        Write-Diag "inbox-loop active (heartbeat age=$([math]::Round($ageMin,1))min < ttl=$ttlMin min, interval=$intervalMin from $intervalSource) — suppressing INBOX reminder"
        exit 0
    }
    Write-Diag "inbox-loop heartbeat stale (age=$([math]::Round($ageMin,1))min >= ttl=$ttlMin min, interval=$intervalMin from $intervalSource) — proceeding normally"
}

$unreadLines = Select-String -Path $inboxPath -Pattern '^\s*-\s*🟡' -Encoding UTF8 | ForEach-Object { $_.Line.Trim() }
$unread = $unreadLines.Count
Write-Diag "unread=$unread"

if ($unread -le 0) { exit 0 }

# Дедуп: если хеш текущих 🟡-строк совпадает с last-announced — молчим (юзер уже видел это в текущей сессии).
# Announced-файл затирается setup.ps1 на SessionStart, так что новая сессия = снова показать.
$contentToHash = ($unreadLines | Sort-Object) -join "`n"
$md5 = [System.Security.Cryptography.MD5]::Create()
$contentHash = [System.BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($contentToHash))).Replace('-','')

$announcedPath = Join-Path $PSScriptRoot 'inbox-announced.txt'
$lastAnnounced = ''
if (Test-Path $announcedPath) {
    $lastAnnounced = (Get-Content $announcedPath -Raw -Encoding UTF8).Trim()
}

if ($contentHash -eq $lastAnnounced) {
    Write-Diag "dedup: hash=$contentHash совпал с last-announced — silent"
    exit 0
}

$relPath = "inbox/$author.md"
$msg = "INBOX: $unread непрочитанных уведомлений в ``$relPath``. **Сам прочитай и обработай**, без AskUserQuestion. Алгоритм: (1) Прочитай каждое 🟡-сообщение целиком. (2) Классифицируй по типу: информационное / вопрос / запрос на ревью / запрос на разрушительное действие / срочное (🆕 или «срочно»). (3) Срочные — обработай ДО основной задачи; несрочные — ПОСЛЕ. (4) Действия: информационные → упомянуть строкой в финальном ответе; вопрос → ответить через /msg @<sender>; ревью → прочитать документ, написать ревью в state/daily/<today>.md, отправить /msg @<sender> со ссылкой; разрушительное действие → ТОЛЬКО тут спросить пользователя через AskUserQuestion. (5) После каждой обработки замени 🟡 на ✅ через Edit. (6) В конце финального ответа добавь строку «Inbox: обработано N сообщений (✅), действия: <короткий список>». Полные правила — в meta/CLAUDE.md и _system/inbox-protocol.md."
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
