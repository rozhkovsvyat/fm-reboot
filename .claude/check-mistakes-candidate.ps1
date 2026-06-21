# Stop hook: детектор кандидатов в mistakes/.
#
# Анализирует git-активность за последний час на признаки "реверса рассуждения":
#   - git revert / git reset --hard в reflog
#   - коммиты с маркерами разворота в message (revert, pivot, развернул, оказалось,
#     неверно, не подходит, переключаем)
#   - в state/daily/<today>.md появились те же маркеры
#   - в decisions/ создан НОВЫЙ ADR за последний час (часто след ошибки)
#   - один и тот же файл редактировался >5 раз в разных коммитах за час (ходьба по кругу)
#
# Если хоть один сигнал триггернулся И mistakes/<today>-*.md за последний час НЕ
# создавался — emit reminder агенту: "возможно, в сессии был реверс — проверь
# порог в mistakes/README §«Когда писать запись», и если подходит — зафиксируй".
#
# Soft reminder, не блокер. Дедуп — by hour-bucket.
#
# СТАТУС: DRAFT — не зарегистрирован в settings.json. Активировать после теста
# на 2-3 сессиях с ручным запуском:
#   pwsh .claude/check-mistakes-candidate.ps1
# Лог — .claude/mistakes-candidate-hook.log

param(
    [string]$EventName = 'Stop'
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$vaultRoot = Split-Path -Parent $PSScriptRoot
$logPath = Join-Path $PSScriptRoot 'mistakes-candidate-hook.log'

function Write-Diag($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "[$ts] [$EventName] $msg" -Encoding UTF8
}

Write-Diag "fired"

$today = (Get-Date).ToString('yyyy-MM-dd')
$pivotKeywords = @(
    'revert', 'pivot', 'разверн', 'оказалось', 'неверно',
    'не подходит', 'переключаем', 'откат', 'отказались', 'переделали'
)

# 1. Коммиты за последний час: messages + name-only
$gitLogArgs = @('-C', $vaultRoot, 'log', '--since=1.hours.ago', '--name-only',
                '--pretty=format:__COMMIT__%H%n__MSG__%s')
$rawLog = (& git @gitLogArgs) 2>$null
if (-not $rawLog) { Write-Diag "нет коммитов за час — skip"; exit 0 }

$lines = $rawLog -split "`r?`n"
$commitMessages = @()
$touchedPaths = @{}
$fileCounts = @{}
foreach ($line in $lines) {
    if ($line.StartsWith('__COMMIT__')) { continue }
    if ($line.StartsWith('__MSG__')) {
        $commitMessages += $line.Substring(7)
        continue
    }
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $touchedPaths[$line] = $true
    if ($fileCounts.ContainsKey($line)) { $fileCounts[$line]++ } else { $fileCounts[$line] = 1 }
}

# 2. Сигналы

$signals = @()

# 2a. Маркеры разворота в commit messages
foreach ($msg in $commitMessages) {
    $msgLower = $msg.ToLower()
    foreach ($kw in $pivotKeywords) {
        if ($msgLower.Contains($kw.ToLower())) {
            $signals += "commit message содержит '$kw': '$msg'"
            break
        }
    }
}

# 2b. git revert / git reset --hard в reflog за последний час
$reflog = & git -C $vaultRoot reflog --since=1.hours.ago --pretty=format:'%gs' 2>$null
if ($reflog) {
    foreach ($entry in $reflog) {
        if ($entry -match 'revert|reset:.*hard') {
            $signals += "reflog: $entry"
        }
    }
}

# 2c. В diff-добавлениях state/daily/<today>.md за последний час есть маркеры разворота.
# Важно: НЕ во всём файле — иначе любая запись в mistakes/ про прошлые разворот'ы
# навсегда триггерит хук (false positive). Смотрим только на свежие правки.
$dailyRel = "state/daily/$today.md"
$dailyDiff = & git -C $vaultRoot log --since=1.hours.ago --pretty=format: -p -- $dailyRel 2>$null
if ($dailyDiff) {
    $addedLines = ($dailyDiff -split "`r?`n" | Where-Object { $_.StartsWith('+') -and -not $_.StartsWith('+++') }) -join "`n"
    $addedLower = $addedLines.ToLower()
    foreach ($kw in $pivotKeywords) {
        if ($addedLower.Contains($kw.ToLower())) {
            $signals += "daily/$today.md свеже-добавленные строки содержат '$kw'"
            break
        }
    }
}

# 2d. Новый ADR за последний час
$newAdrs = $touchedPaths.Keys | Where-Object {
    $_ -match '^decisions/\d{4}-' -and -not (& git -C $vaultRoot log --since=2.hours.ago --until=1.hours.ago --name-only --pretty=format: -- $_ 2>$null)
}
foreach ($adr in $newAdrs) {
    if ($adr) { $signals += "новый ADR: $adr" }
}

# 2e. Файл редактировался >5 раз в разных коммитах — потенциальная ходьба по кругу.
# Исключаем инфра-файлы, которые правятся итеративно по природе:
#   - .claude/settings.json — конфиг хуков
#   - mistakes/_template.md / mistakes/README.md — мета-файлы раздела
#   - product/diagrams/*.drawio — диаграммы синкаются subagent'ами по N итераций
#   - state/now.md — снимок состояния, часто обновляется по ходу работы
#   - state/activity.md — лента событий, append-only по своей природе
#   - inbox/*.md — переписка с коллегами, естественные множественные правки
$infraExclude = @(
    '.claude/settings.json',
    'mistakes/_template.md',
    'mistakes/README.md',
    'state/now.md',
    'state/activity.md'
)
foreach ($file in $fileCounts.Keys) {
    if ($fileCounts[$file] -le 5) { continue }
    if ($file -in $infraExclude) { continue }
    if ($file -match '^product/diagrams/.+\.drawio$') { continue }
    if ($file -match '^inbox/[^/]+\.md$') { continue }
    $signals += "$file редактировался $($fileCounts[$file]) раз — ходьба по кругу?"
}

Write-Diag "signals=$($signals.Count): $($signals -join ' | ')"

if ($signals.Count -eq 0) { exit 0 }

# 3. Уже есть mistakes/<today>-*.md созданный за последний час?
$mistakesToday = $touchedPaths.Keys | Where-Object { $_ -match "^mistakes/$today-" }
if ($mistakesToday) {
    Write-Diag "mistakes/$today-* уже создан — skip"
    exit 0
}

# 4. Дедуп по hour-bucket
$hourBucket = (Get-Date).ToString('yyyy-MM-dd-HH')
$announcedPath = Join-Path $PSScriptRoot 'mistakes-candidate-announced.txt'
$lastBucket = ''
if (Test-Path $announcedPath) {
    $lastBucket = (Get-Content $announcedPath -Raw -Encoding UTF8).Trim()
}
if ($hourBucket -eq $lastBucket) {
    Write-Diag "dedup: bucket=$hourBucket совпал — silent"
    exit 0
}

$signalSummary = ($signals | Select-Object -First 3) -join '; '
$msg = "MISTAKE-CANDIDATE: за последний час обнаружены признаки реверса рассуждения ($signalSummary). Проверь порог в ``mistakes/README.md`` §«Когда писать запись» — если хотя бы одно условие выполняется (стоимость >30 мин ИЛИ повторяемый паттерн ИЛИ развернулись после уже сделанной работы ИЛИ подняли в правило/ADR) — создай ``mistakes/$today-<slug>.md`` по шаблону ``mistakes/_template.md`` с обязательным полем **Signal**. Если ниже порога — игнорируй это напоминание, не пиши 'для галочки'. Soft reminder, не блокирует финальный ответ."

# LOCAL PATCH 2026-05-27 (savchuk): Stop event в текущем Claude Code НЕ поддерживает
# hookSpecificOutput.additionalContext — это вызывает "Hook JSON output validation failed".
# Используем верхнеуровневый systemMessage (валидный на всех событиях), либо silent если
# событие — Stop. UserPromptSubmit / SessionStart всё ещё используют старый формат.
if ($EventName -eq 'Stop' -or $EventName -eq 'SessionEnd') {
    $payload = @{
        systemMessage = $msg
    } | ConvertTo-Json -Compress
} else {
    $payload = @{
        hookSpecificOutput = @{
            hookEventName     = $EventName
            additionalContext = $msg
        }
    } | ConvertTo-Json -Compress
}

Write-Output $payload
Set-Content -Path $announcedPath -Value $hourBucket -Encoding UTF8
Write-Diag "emitted; bucket=$hourBucket"

exit 0
