# UserPromptSubmit hook: ежедневный пересмотр накопленных mistakes/.
#
# Раз в день (по date-bucket) при первом UserPromptSubmit смотрит:
#   - сколько в mistakes/ записей создано/обновлено за последние 24 часа
#   - есть ли в них severity major/critical (читает frontmatter-like поле)
#   - есть ли 2+ записи с похожим Signal-блоком (по keyword overlap, грубая эвристика)
#
# Если что-то накопилось — emit reminder: "пересмотри mistakes/, возможно пора
# поднять в ADR/правило". Soft reminder, не блокер.
#
# Каденс — daily (не weekly) по решению rozhkov 2026-05-22: fresh signal горячий,
# через 7 дней теряет половину контекста.
#
# СТАТУС: DRAFT — не зарегистрирован в settings.json. Активировать после
# 2-3 mistakes-записей в папке (иначе нечего ревьюить). Лог — .claude/mistakes-review-hook.log

param(
    [string]$EventName = 'UserPromptSubmit'
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$vaultRoot = Split-Path -Parent $PSScriptRoot
$logPath = Join-Path $PSScriptRoot 'mistakes-review-hook.log'

function Write-Diag($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "[$ts] [$EventName] $msg" -Encoding UTF8
}

Write-Diag "fired"

$mistakesDir = Join-Path $vaultRoot 'mistakes'
if (-not (Test-Path $mistakesDir)) { Write-Diag "mistakes/ не существует — skip"; exit 0 }

# Дедуп по date-bucket: один раз в день
$dateBucket = (Get-Date).ToString('yyyy-MM-dd')
$announcedPath = Join-Path $PSScriptRoot 'mistakes-review-announced.txt'
$lastBucket = ''
if (Test-Path $announcedPath) {
    $lastBucket = (Get-Content $announcedPath -Raw -Encoding UTF8).Trim()
}
if ($dateBucket -eq $lastBucket) {
    Write-Diag "dedup: bucket=$dateBucket совпал — silent"
    exit 0
}

# Сканируем mistakes/*.md (исключая _template и README)
$files = Get-ChildItem -Path $mistakesDir -Filter '*.md' -File |
         Where-Object { $_.Name -notin @('_template.md', 'README.md') }

if ($files.Count -eq 0) {
    Write-Diag "mistakes/ пуст — skip"
    Set-Content -Path $announcedPath -Value $dateBucket -Encoding UTF8
    exit 0
}

# Метрики
$now = Get-Date
$last24h = $now.AddHours(-24)
$last7d = $now.AddDays(-7)

$recentCount = 0
$majorCount = 0
$severityList = @()
$titles = @()

foreach ($file in $files) {
    if ($file.LastWriteTime -ge $last24h) { $recentCount++ }
    if ($file.LastWriteTime -lt $last7d) { continue }

    $content = Get-Content $file.FullName -Raw -Encoding UTF8
    # Парсим строку **Severity:** в первых 30 строках
    $severityMatch = [regex]::Match($content, '\*\*Severity:\*\*\s*(\w+)')
    if ($severityMatch.Success) {
        $severity = $severityMatch.Groups[1].Value.ToLower()
        $severityList += $severity
        if ($severity -in @('major', 'critical')) {
            $majorCount++
            $titleMatch = [regex]::Match($content, '^#\s+(.+)$', 'Multiline')
            $title = if ($titleMatch.Success) { $titleMatch.Groups[1].Value } else { $file.BaseName }
            $titles += "$($file.Name) ($severity): $title"
        }
    }
}

Write-Diag "total=$($files.Count) recent24h=$recentCount major7d=$majorCount"

# Условия для emit
$shouldEmit = $false
$reasons = @()

if ($recentCount -ge 1 -and $files.Count -ge 2) {
    $shouldEmit = $true
    $reasons += "за 24ч добавлена $recentCount запись, всего в папке $($files.Count) — пора посмотреть на накопленное"
}
if ($majorCount -ge 1) {
    $shouldEmit = $true
    $reasons += "за 7 дней $majorCount запись с severity major/critical — кандидат на ADR немедленно"
}

if (-not $shouldEmit) {
    Write-Diag "ничего критичного не накопилось — skip (mark bucket)"
    Set-Content -Path $announcedPath -Value $dateBucket -Encoding UTF8
    exit 0
}

$reasonText = $reasons -join '; '
$topTitles = ($titles | Select-Object -First 3) -join "; "
$titleSection = if ($topTitles) { " Топ по severity: $topTitles." } else { '' }

$msg = "MISTAKES-REVIEW: $reasonText.$titleSection Открой ``mistakes/`` и оцени: (1) есть ли 2-3 однотипных записи с похожим Signal → поднять паттерн в ``rules/*.md`` или новый ADR; (2) есть ли одна с severity major/critical → поднять в ADR сразу. Не авто-генерь ADR — твоя задача предложить пользователю с готовым черновиком в ``drafts/<slug>.md`` если уместно. Soft reminder, не блокер. Правила — в ``meta/CLAUDE.md`` §«Журнал ошибок: фиксация и daily-ревью»."

$payload = @{
    hookSpecificOutput = @{
        hookEventName     = $EventName
        additionalContext = $msg
    }
} | ConvertTo-Json -Compress

Write-Output $payload
Set-Content -Path $announcedPath -Value $dateBucket -Encoding UTF8
Write-Diag "emitted; bucket=$dateBucket"

exit 0
