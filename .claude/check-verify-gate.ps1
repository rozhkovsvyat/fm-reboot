# Stop hook: verify-гейт (DoD = runtime smoke, не напоминание).
#
# Правило — rules/verify-gate.md. Ловит доминирующий mistake-класс:
# claim завершения («готово/работает/задеплоено/READY») БЕЗ runtime-доказательства
# и без явного escape-hatch-дисклеймера.
#
# Сканирует СВЕЖИЕ добавления в state/daily/<today>.md:
#   - committed за последний час (git log -p --since=1.hours.ago)
#   - uncommitted working-tree (git diff -- <daily>) — daily часто ещё не закоммичен на Stop
# Группирует добавленные строки по записям (### / #### заголовки). Для каждой записи:
#   claim && !evidence && !disclaimer  → сигнал.
#
# Bias: ВЫСОКАЯ ТОЧНОСТЬ (мало фолс-позитивов) > полнота. Если агент реально проверял —
# в записи будет evidence-лексика и гейт молчит. Шумный гейт игнорируют (как игнорировали
# напоминание) — это анти-цель. Дедуп by hour-bucket.
#
# СТАТУС: активирован в settings.json (Stop) 2026-06-19. Ручной прогон:
#   pwsh .claude/check-verify-gate.ps1
# Лог — .claude/verify-gate-hook.log

param(
    [string]$EventName = 'Stop'
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$vaultRoot = Split-Path -Parent $PSScriptRoot
$logPath = Join-Path $PSScriptRoot 'verify-gate-hook.log'

function Write-Diag($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "[$ts] [$EventName] $msg" -Encoding UTF8
}

Write-Diag "fired"

$today = (Get-Date).ToString('yyyy-MM-dd')
$dailyRel = "state/daily/$today.md"

# claim завершения: что-то ФУНКЦИОНИРУЕТ / закрыто (не просто «код написан/запушен»)
$claimKw = @(
    'готово', 'работает', 'задеплоен', 'ready', 'выполнено', 'доведен', 'доведён',
    'фикс применён', 'фикс применен', 'работают e2e', 'works', 'закрыт', 'починен'
)
# runtime-доказательство (whitelist из rules/verify-gate.md)
$evidenceKw = @(
    'kubectl', ' logs', 'прогон', 'smoke', 'на стенде', 'на деве', 'на dev', 'live',
    'verif', 'verify', 'getcomputedstyle', 'браузер', 'скриншот', 'playwright', 'e2e',
    'integration', 'интеграцион', 'реальн', 'проверено', 'проверил', 'подтвержд', 'подтверд',
    'трасса', 'correlationid', 'pod ', 'healthy', 'running', '201', ' 200', '2xx',
    'psql', 'kubectl logs', 'in-cluster', 'наживую', 'живьём', 'живьем', 'живой прогон',
    # generic runtime-доказательства (не только инфра): тесты зелёные на реальном прогоне,
    # запуск приложения, curl/http, скриншот, локальный прогон
    'тесты прош', 'тест прош', 'passed', 'pytest', 'npm test', 'npm run', 'jest', 'go test',
    'cargo test', 'dotnet test', 'запустил', 'запущен', 'локальный прогон', 'локально проверил',
    'curl', 'http 200', 'exit 0', 'скрин', 'вывод команды', 'консоль показала', 'воспроизвёл'
)
# escape hatch — честно обозначенная граница (снимает гейт)
$disclaimerKw = @(
    'не верифицир', 'не проверял', 'не прогон', 'runtime не', 'не верифиц',
    'ждёт smoke', 'ждет smoke', 'прошу smoke', 'build-only', 'статич',
    'не запушено', 'локально не', 'жду commit', 'ждёт deploy', 'ждет deploy',
    'не верифицировал', 'смоук не', 'smoke не'
)

# --- собрать свежие добавленные строки (committed за час + uncommitted) ---
$addedRaw = @()

$committed = & git -C $vaultRoot log --since=1.hours.ago --pretty=format: -p -- $dailyRel 2>$null
if ($committed) {
    $addedRaw += ($committed -split "`r?`n" | Where-Object { $_.StartsWith('+') -and -not $_.StartsWith('+++') })
}
$uncommitted = & git -C $vaultRoot diff -- $dailyRel 2>$null
if ($uncommitted) {
    $addedRaw += ($uncommitted -split "`r?`n" | Where-Object { $_.StartsWith('+') -and -not $_.StartsWith('+++') })
}

if ($addedRaw.Count -eq 0) { Write-Diag "нет свежих добавлений в $dailyRel — skip"; exit 0 }

# strip ведущий '+' для анализа
$added = $addedRaw | ForEach-Object { $_.Substring(1) }

# --- сгруппировать по записям (### / #### заголовки) ---
$chunks = @()
$current = New-Object System.Collections.Generic.List[string]
foreach ($line in $added) {
    if ($line -match '^\s*#{2,4}\s') {
        if ($current.Count -gt 0) { $chunks += ,@($current.ToArray()) }
        $current = New-Object System.Collections.Generic.List[string]
    }
    $current.Add($line)
}
if ($current.Count -gt 0) { $chunks += ,@($current.ToArray()) }

function Test-Any($text, $keywords) {
    $lower = $text.ToLower()
    foreach ($kw in $keywords) {
        if ($lower.Contains($kw.ToLower())) { return $true }
    }
    return $false
}

$flagged = @()
foreach ($chunk in $chunks) {
    $text = ($chunk -join "`n")
    if (-not (Test-Any $text $claimKw)) { continue }
    if (Test-Any $text $evidenceKw) { continue }
    if (Test-Any $text $disclaimerKw) { continue }
    # заголовок записи для диагностики
    $header = ($chunk | Where-Object { $_ -match '^\s*#{2,4}\s' } | Select-Object -First 1)
    if (-not $header) { $header = ($chunk | Select-Object -First 1) }
    $header = $header.Trim() -replace '^#+\s*', ''
    if ($header.Length -gt 80) { $header = $header.Substring(0, 80) + '…' }
    $flagged += $header
}

Write-Diag "chunks=$($chunks.Count) flagged=$($flagged.Count): $($flagged -join ' | ')"

if ($flagged.Count -eq 0) { exit 0 }

# --- дедуп by hour-bucket ---
$hourBucket = (Get-Date).ToString('yyyy-MM-dd-HH')
$announcedPath = Join-Path $PSScriptRoot 'verify-gate-announced.txt'
$lastBucket = ''
if (Test-Path $announcedPath) {
    $lastBucket = (Get-Content $announcedPath -Raw -Encoding UTF8).Trim()
}
if ($hourBucket -eq $lastBucket) { Write-Diag "dedup: bucket=$hourBucket — silent"; exit 0 }

$list = ($flagged | Select-Object -First 3) -join '; '
$msg = "VERIFY-GATE: в ``$dailyRel`` есть claim завершения без runtime-доказательства ($list). По ``rules/verify-gate.md`` (DoD = runtime smoke): ДО финального ответа либо приложи факт живого прогона (запустил приложение / тесты зелёные на реальном прогоне / curl 2xx / скриншот / e2e), либо переформулируй через escape hatch («реализовано, build+unit зелёные, runtime НЕ верифицировал — причина X, прошу smoke»). Не выдавай 'рассудил, что работает' за 'проверил'. Обязательство уровня INBOX, не мягкий совет."

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
Set-Content -Path $announcedPath -Value $hourBucket -Encoding UTF8
Write-Diag "emitted; bucket=$hourBucket"

exit 0
