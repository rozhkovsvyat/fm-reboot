# Б3 — Pre-commit hook: ищет сломанные wikilinks [[...]] в staged-файлах.
# Вызывается из UserPromptSubmit (как warning, не блокер) или можно подключить в git pre-commit.
# Парсит [[target]] и [[target|alias]] — проверяет существование target.md в vault'е.
# Исключения: внешние ссылки (http), anchors (#), _template, _handles,
# memory/* (указатели на agent-memory — живут в ~/.claude/, не в vault by design).

param(
    [string]$EventName = 'UserPromptSubmit'
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$vaultRoot = Split-Path -Parent $PSScriptRoot
$logPath = Join-Path $PSScriptRoot 'broken-wikilinks-hook.log'

function Write-Diag($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "[$ts] [$EventName] $msg" -Encoding UTF8
}

Write-Diag "fired"

# Собираем все .md файлы, изменённые за последний час (approximation для pre-commit)
$changedFiles = git -C $vaultRoot diff --name-only HEAD~1 HEAD -- '*.md' 2>$null
if (-not $changedFiles) {
    $changedFiles = git -C $vaultRoot diff --name-only --cached -- '*.md' 2>$null
}
if (-not $changedFiles) {
    Write-Diag "no changed md files — skip"
    exit 0
}

$broken = @()

foreach ($relFile in $changedFiles) {
    $fullPath = Join-Path $vaultRoot $relFile
    if (-not (Test-Path $fullPath)) { continue }

    # Append-only журналы и историчные снимки — ссылки в них не чиним (шум, а не actionable):
    # daily/weekly/activity/inbox + датированные mistakes + личный broker-tooling (плейсхолдеры).
    # Хук фокусируется на живых доках (decisions/product/rules/team/meta/now.md/drafts).
    if ($relFile -match '^state/(daily|weekly)/') { continue }
    if ($relFile -eq 'state/activity.md') { continue }
    if ($relFile -match '^inbox/') { continue }
    if ($relFile -match '^mistakes/\d{4}-\d{2}-\d{2}-') { continue }
    if ($relFile -match '^broker/') { continue }

    $content = Get-Content $fullPath -Raw -Encoding UTF8
    if (-not $content) { continue }

    # Извлекаем все [[...]] (но не внутри code blocks)
    $codeBlockPattern = '(?s)```.*?```'
    $cleanContent = $content -replace $codeBlockPattern, ''

    $wikiMatches = [regex]::Matches($cleanContent, '\[\[([^\]]+)\]\]')
    foreach ($m in $wikiMatches) {
        $target = $m.Groups[1].Value

        # [[target|alias]] → берём target. В markdown-таблицах Obsidian escape'ит pipe: [[link\|alias]]
        if ($target -match '\|') {
            $target = ($target -split '\|')[0]
        }
        # Убираем trailing backslash от escape-pipe ([[link\|alias]] → target = "link\")
        $target = $target -replace '\\$', ''

        # Пропускаем anchors, http, шаблоны
        if ($target -match '^https?://') { continue }
        if ($target -match '^#') { continue }
        if ($target -match '_template') { continue }
        # agent-memory pointers ([[memory/...]]) — by design не vault-ноты (живут в ~/.claude/).
        if ($target -match '^memory/') { continue }
        # memory-имена без префикса memory/ (reference_/feedback_/project_/user_ snake_case) — те же указатели.
        if ($target -match '^(reference|feedback|project|user)_[a-z0-9_]+$') { continue }
        # template-плейсхолдеры из инструкций, не настоящие ссылки:
        # [[team/<handle>]], [[state/features/<f>/...]], [[moderate:deny]], [[:space:]], [[*]], [[...]]
        if ($target -match '[:<>*]') { continue }
        if ($target -match '\.\.\.') { continue }

        # Убираем anchor-часть: [[page#section]] → page
        if ($target -match '#') {
            $target = ($target -split '#')[0]
        }

        $target = $target.Trim()
        if (-not $target) { continue }

        # Проверяем существование файла
        $candidates = @(
            (Join-Path $vaultRoot "$target.md"),
            (Join-Path $vaultRoot $target),
            (Join-Path $vaultRoot "$target.yml")
        )

        $found = $false
        foreach ($c in $candidates) {
            if (Test-Path $c) { $found = $true; break }
        }

        if (-not $found) {
            $broken += "$relFile → [[$($m.Groups[1].Value)]]"
        }
    }
}

Write-Diag "broken-count=$($broken.Count)"

if ($broken.Count -eq 0) { exit 0 }

# Дедуп
$contentToHash = ($broken | Sort-Object) -join "`n"
$md5 = [System.Security.Cryptography.MD5]::Create()
$contentHash = [System.BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($contentToHash))).Replace('-','')

$announcedPath = Join-Path $PSScriptRoot 'broken-wikilinks-announced.txt'
$lastAnnounced = ''
if (Test-Path $announcedPath) {
    $lastAnnounced = (Get-Content $announcedPath -Raw -Encoding UTF8).Trim()
}

if ($contentHash -eq $lastAnnounced) {
    Write-Diag "dedup: hash match, silent"
    exit 0
}

$summary = ($broken | Select-Object -First 5) -join '; '
if ($broken.Count -gt 5) { $summary += "; ...ещё $($broken.Count - 5)" }

$msg = "BROKEN-LINKS: $($broken.Count) сломанных wikilinks в недавно изменённых файлах: $summary. Проверь: файл переименован/удалён? Исправь ссылки или создай целевой файл."

$payload = @{
    hookSpecificOutput = @{
        hookEventName     = $EventName
        additionalContext = $msg
    }
} | ConvertTo-Json -Compress

Write-Output $payload
Set-Content -Path $announcedPath -Value $contentHash -Encoding UTF8
Write-Diag "emitted; hash=$contentHash; broken=$($broken.Count)"

exit 0
