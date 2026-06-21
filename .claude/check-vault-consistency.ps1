# Stop hook: регрессионный тест на консистентность vault'а (LLM-free).
# По запросу [[team/rozhkov]] 2026-05-12 (см. inbox/kuznetsov), вариант 2 из трёх:
# pilot-аудит (1) сделан вручную, cron-агент (3) у marchuk через /schedule, этот хук — превентив на Stop.
#
# Что ловит:
#   (A) ADR создан/изменён в этом часу, но не упомянут в state/now.md «Готово к ревью» / «Активные ADR»
#       или в meta/index.md «Архитектурные решения» — флаг.
#   (B) Новые [[wikilink]] в diff последнего часа, цель которых не существует — флаг.
#   (C) Roadmap-агенты в process/patterns/* — известный whitelist, пропускаются.
#
# Чего НЕ ловит (это для cron-агента marchuk через LLM):
#   - Семантические расхождения (ADR говорит X, services/Y говорит Y — нужен LLM)
#   - Orphan service cards (нужен полный обход vault, не diff — это для periodic-аудита)
#   - Расхождения owner'ов (нужен LLM для контекста)
#
# Дедуп: по хешу findings, announced-файл стирается на SessionStart (как у других хуков).
# Идемпотентность: хук смотрит на git log, не на состояние процесса.

param(
    [string]$EventName = 'Stop'
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$vaultRoot = Split-Path -Parent $PSScriptRoot
$logPath = Join-Path $PSScriptRoot 'consistency-hook.log'

function Write-Diag($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "[$ts] [$EventName] $msg" -Encoding UTF8
}

Write-Diag "fired"

# Коммиты за последний час (name-status: A/M/D + path)
$gitArgs = @('-C', $vaultRoot, 'log', '--since=1.hours.ago', '--name-status', '--pretty=format:__COMMIT__%H')
$rawLog = (& git @gitArgs) 2>$null
if (-not $rawLog) {
    Write-Diag "нет коммитов за час — skip"
    exit 0
}

$findings = @()

# ===== Сценарий A: ADR без upstream-ссылок =====

$adrFiles = @{}
foreach ($line in ($rawLog -split "`r?`n")) {
    if ($line -match '^[AM]\s+(decisions/(\d{4})-[^.]+\.md)$') {
        $adrFiles[$matches[2]] = $matches[1]
    }
}

if ($adrFiles.Count -gt 0) {
    $nowPath = Join-Path $vaultRoot 'state/now.md'
    $indexPath = Join-Path $vaultRoot 'meta/index.md'
    $nowContent = if (Test-Path $nowPath) { Get-Content $nowPath -Raw -Encoding UTF8 } else { '' }
    $indexContent = if (Test-Path $indexPath) { Get-Content $indexPath -Raw -Encoding UTF8 } else { '' }

    foreach ($num in $adrFiles.Keys) {
        $adrPath = $adrFiles[$num]
        $pattern = "(decisions/$num|ADR\s*$num|0$num)"
        $missing = @()
        if ($nowContent -notmatch $pattern) { $missing += 'state/now.md' }
        if ($indexContent -notmatch $pattern) { $missing += 'meta/index.md' }
        if ($missing.Count -gt 0) {
            $findings += "ADR $num ($adrPath) изменён/создан в этом часу, но НЕ упомянут в: $($missing -join ', '). Добавь в «Готово к ревью» (now.md) и «Архитектурные решения» (index.md)."
        }
    }
}

# ===== Сценарий B: Dangling wikilinks среди новых =====

# Roadmap-whitelist: согласованная целевая структура, не баги
$roadmapWhitelist = @(
    'process/agents/backend-agent',
    'process/agents/frontend-agent',
    'process/agents/test-writer-agent',
    'process/agents/pr-review-agent',
    'process/agents/a11y-checker-agent',
    'process/agents/skeptic-agent',
    'process/agents/incident-agent',
    'process/agents/release-agent',
    'process/agents/security-agent',
    'process/agents/graphify-agent',
    'process/skills/playwright-pro'
)

# Path-filter: проверяем dangling wikilinks ТОЛЬКО в production-файлах vault'а.
# Игнорируем state/, inbox/, drafts/, _system/, presentations/ — там по дизайну
# много исторических/мета-упоминаний (отчёты, history, hypotheticals) которые
# ловятся как false positives.
$productionPathRegex = '^(decisions|product|process|rules|meta)/'

# Diff за последний час с указанием файла для каждого блока
$diffArgs = @('-C', $vaultRoot, 'log', '--since=1.hours.ago', '-p', '--no-color', '--', '*.md')
$diffOutput = (& git @diffArgs) 2>$null

if ($diffOutput) {
    $candidates = @{}
    $currentFile = $null
    foreach ($line in ($diffOutput -split "`r?`n")) {
        # отслеживаем какой файл сейчас diff'ится (для path-filter'а)
        if ($line -match '^diff --git a/(\S+)') {
            $currentFile = $matches[1]
            continue
        }
        # пропускаем строки если файл не production
        if (-not $currentFile -or $currentFile -notmatch $productionPathRegex) { continue }
        # only added lines (+ but not +++)
        if ($line -match '^\+[^+]') {
            $matches2 = [regex]::Matches($line, '\[\[([^\]|#]+?)(?:\|[^\]]+)?(?:#[^\]]+)?\]\]')
            foreach ($m in $matches2) {
                $link = $m.Groups[1].Value.Trim()
                # фильтры: placeholder-templates, anchors, wildcards, non-md extensions, single-token russian words
                if ($link -match '^X$|^_template$|<.*>|\.\.\.|images?/|\.(png|html|pptx|sh|json|yml|yaml)$|^[A-Z]$|^[А-Яа-яёЁ]+$') { continue }
                # whitelist — roadmap, согласованная структура
                if ($roadmapWhitelist -contains $link) { continue }
                # уже фиксили? — store unique
                $candidates[$link] = $true
            }
        }
    }

    foreach ($link in $candidates.Keys) {
        # Проверка существования: .md, папка, .html (presentations), .yml/.yaml (configs)
        $exists = $false
        foreach ($ext in @('.md', '.html', '.yml', '.yaml', '')) {
            $tryPath = if ($ext) { Join-Path $vaultRoot "$link$ext" } else { Join-Path $vaultRoot $link }
            if (Test-Path $tryPath) { $exists = $true; break }
        }
        # короткие имена без / — попытаться найти в vault recursively
        if (-not $exists -and $link -notmatch '/') {
            $candPath = Get-ChildItem -Path $vaultRoot -Filter "$link.md" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($candPath) { $exists = $true }
        }
        if (-not $exists) {
            $findings += "Dangling wikilink: [[$link]] добавлена в production-файл за последний час, но цели нет. Создай файл или сними ссылку."
        }
    }
}

# ===== Сценарий C: ADR status sync (по критерию (a) rozhkov'а) =====
# ADR в decisions/<NNNN>-*.md имеет поле «- **Статус:** ...» в шапке.
# now.md в «Готово к ревью» / «Активные ADR» отображает статус через 🟡 / эмодзи / текст.
# Сверяем — если в ADR статус «🟡 на ревью», в now.md тоже должно быть 🟡 / «на ревью» рядом со ссылкой;
# если в ADR «принято»/«отложено» — в now.md не должно быть 🟡.

if ($adrFiles.Count -gt 0 -and (Test-Path $nowPath)) {
    foreach ($num in $adrFiles.Keys) {
        $adrPath = Join-Path $vaultRoot $adrFiles[$num]
        if (-not (Test-Path $adrPath)) { continue }
        $adrContent = Get-Content $adrPath -Raw -Encoding UTF8
        # статус из шапки ADR
        $adrStatus = $null
        if ($adrContent -match '(?im)^\s*[-*]\s*\*\*Статус:\*\*\s*(.+?)\s*$') {
            $adrStatus = $matches[1].Trim()
        }
        if (-not $adrStatus) { continue }
        $isReview = $adrStatus -match '🟡|на ревью|на review'
        $isAccepted = $adrStatus -match 'принят|accepted'
        $isDeferred = $adrStatus -match 'отложен|deferred|on hold'

        # упоминание в now.md в одной строке со ссылкой
        $nowLines = $nowContent -split "`r?`n"
        foreach ($nowLine in $nowLines) {
            if ($nowLine -notmatch "decisions/$num") { continue }
            $nowMarker = if ($nowLine -match '🟡') { 'review' } elseif ($nowLine -match '✅') { 'accepted' } elseif ($nowLine -match '⚪') { 'deferred' } else { 'unmarked' }
            if ($isReview -and $nowMarker -eq 'accepted') {
                $findings += "ADR $num status mismatch: в ADR-файле «$adrStatus» (на ревью), в state/now.md помечен ✅ (принят). Синхронизируй."
            } elseif ($isAccepted -and $nowMarker -eq 'review') {
                $findings += "ADR $num status mismatch: в ADR-файле «$adrStatus» (принят), в state/now.md помечен 🟡 (на ревью). Перемести в «Активные ADR» / убери 🟡."
            } elseif ($isDeferred -and $nowMarker -eq 'review') {
                $findings += "ADR $num status mismatch: в ADR-файле «$adrStatus» (отложен), в state/now.md помечен 🟡. Перенеси."
            }
        }
    }
}

# ===== Сценарий D: orphan MS references (по критерию (b) rozhkov'а) =====
# Если в meta/index.md или product/microfrontends.md упомянут <name>-service,
# но product/services/<name>.md не существует — orphan reference.

if (Test-Path (Join-Path $vaultRoot 'product/microfrontends.md')) {
    $servicesDir = Join-Path $vaultRoot 'product/services'
    $existingServices = @{}
    Get-ChildItem -Path $servicesDir -Filter '*.md' -ErrorAction SilentlyContinue | ForEach-Object {
        $existingServices[$_.BaseName] = $true
    }
    # ищем все упоминания вида `<name>-service` в index/microfrontends/architecture
    $upstreamFiles = @('meta/index.md', 'product/microfrontends.md', 'product/architecture.md')
    $referencedServices = @{}
    foreach ($uf in $upstreamFiles) {
        $upath = Join-Path $vaultRoot $uf
        if (-not (Test-Path $upath)) { continue }
        $ucontent = Get-Content $upath -Raw -Encoding UTF8
        $svcMatches = [regex]::Matches($ucontent, '\bproduct/services/([a-z][a-z0-9-]*)\b')
        foreach ($sm in $svcMatches) {
            $svcName = $sm.Groups[1].Value
            if (-not $referencedServices.ContainsKey($svcName)) {
                $referencedServices[$svcName] = $uf
            }
        }
    }
    foreach ($svcName in $referencedServices.Keys) {
        if (-not $existingServices.ContainsKey($svcName)) {
            $findings += "Orphan MS reference: `product/services/$svcName.md` упомянут в $($referencedServices[$svcName]), но карточки нет. Создай карточку или убери ссылку."
        }
    }
}

if (-not $findings -or $findings.Count -eq 0) {
    Write-Diag "no findings"
    exit 0
}

# Дедуп по хешу findings
$hashSource = ($findings -join '|')
$hashBytes = [System.Text.Encoding]::UTF8.GetBytes($hashSource)
$md5 = [System.Security.Cryptography.MD5]::Create()
$hash = [System.BitConverter]::ToString($md5.ComputeHash($hashBytes)).Replace('-', '').Substring(0, 12)
$md5.Dispose()

$announcedPath = Join-Path $PSScriptRoot 'consistency-announced.txt'
$lastHash = ''
if (Test-Path $announcedPath) {
    $lastHash = (Get-Content $announcedPath -Raw -Encoding UTF8).Trim()
}
if ($hash -eq $lastHash) {
    Write-Diag "dedup: hash=$hash совпал"
    exit 0
}

$msg = "CONSISTENCY: vault audit hook нашёл $($findings.Count) расхождений в коммитах последнего часа:`n - " + ($findings -join "`n - ") + "`n`nПо `meta/CLAUDE.md` чек-листу — проверь и исправь до отправки финального ответа пользователю. Если ссылка — roadmap (планируется позже), добавь в whitelist хука в `.claude/check-vault-consistency.ps1`."

# LOCAL PATCH 2026-05-27 (savchuk): Stop event не поддерживает hookSpecificOutput.
$payload = @{
    systemMessage = $msg
} | ConvertTo-Json -Compress -Depth 3

Write-Output $payload
Set-Content -Path $announcedPath -Value $hash -Encoding UTF8
Write-Diag "emitted; findings=$($findings.Count); hash=$hash"

exit 0
