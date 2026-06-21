# fm-reboot vault — idempotent install + per-session sync.
# Запускается:
#   1. Один раз вручную при первой настройке: pwsh <vault>/_system/tools/setup.ps1
#   2. Автоматически на каждом SessionStart — через <vault>/.claude/settings.json
#
# Что делает (всё идемпотентно):
#   - git pull --ff-only в vault
#   - Если kb.author не задан в репо — определяет handle из git user.email
#     через team/_handles.yml и выставляет ЛОКАЛЬНО в репо (git -C <vault> config kb.author).
#     Локально, а не --global — чтобы не пачкать глобальный конфиг и не конфликтовать
#     с другими vault'ами на этой же машине.
#   - Затирает announced-файлы хуков (новая сессия = снова показать накопленные напоминания).
#   - BOM auto-fix для .ps1 (Windows PowerShell 5.1 требует UTF-8 BOM для кириллицы).
#   - Housekeeping: архив ✅-записей now.md, overflow activity.md, старых broadcast'ов.
#   - Если CWD — linked-проект (есть .claude/vault-link.json) — refresh хуков через vault-link.ps1.
#
# Сознательно НЕ делает (в отличие от корпоративного прародителя):
#   - НЕ трогает глобальный ~/.claude/CLAUDE.md (он user-owned; контракт живёт в файлах vault'а).
#   - НЕ регистрирует Task Scheduler / LaunchAgent (нет обязательного дневного чекпоинта у соло-команды).
#
# Требования: PowerShell 7.0+ (Windows: winget install Microsoft.PowerShell;
# macOS: brew install powershell; на Mac нужен pwsh 7.6.2+ — у 7.6.1 регрессия stack overflow на arm64).

# --- pwsh 7+ guard (ASCII-safe, чтобы PS 5.1 смог прочитать и сообщить) ---
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "ERROR: vault setup.ps1 requires PowerShell 7.0+ (you have $($PSVersionTable.PSVersion))." -ForegroundColor Red
    Write-Host "Install pwsh 7:" -ForegroundColor Yellow
    Write-Host "  Windows: winget install Microsoft.PowerShell" -ForegroundColor Yellow
    Write-Host "  macOS:   brew install powershell  (нужен 7.6.2+)" -ForegroundColor Yellow
    Write-Host "Then re-run via 'pwsh' (not 'powershell'):" -ForegroundColor Yellow
    Write-Host "  pwsh -NoProfile -File $PSCommandPath" -ForegroundColor Yellow
    exit 1
}

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$vaultRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$claudeUserDir = Join-Path $userHome '.claude'
$logPath = Join-Path $claudeUserDir 'fm-reboot-setup.log'

if (-not (Test-Path $claudeUserDir)) {
    New-Item -ItemType Directory -Force -Path $claudeUserDir | Out-Null
}

function Write-Log($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "[$ts] $msg" -Encoding UTF8
}

Write-Log "setup fired; vault=$vaultRoot"

# 0. Затереть announced-файлы хуков (новая сессия = снова показать накопленные напоминания).
#    inbox-adequacy-due / verify-gate / mistakes-* НЕ трогаем — у них своя каденция (дни/часы).
$announcedFiles = @(
    'inbox-announced.txt', 'overview-announced.txt', 'now-announced.txt',
    'discipline-announced.txt', 'stale-extended-announced.txt',
    'broken-wikilinks-announced.txt', 'draft-lifecycle-announced.txt',
    'yougile-announced.txt', 'yougile-last-state.json'
)
foreach ($af in $announcedFiles) {
    $afPath = Join-Path $vaultRoot ".claude/$af"
    if (Test-Path $afPath) { Remove-Item $afPath -Force; Write-Log "cleared $af" }
}

# 0.5. BOM auto-fix: PowerShell 5.1 требует UTF-8 BOM для кириллицы. Idempotent.
$claudeScriptsDir = Join-Path $vaultRoot '.claude'
foreach ($ps1 in Get-ChildItem -Path $claudeScriptsDir -Filter '*.ps1' -File) {
    $raw = [System.IO.File]::ReadAllBytes($ps1.FullName)
    if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) { continue }
    $content = [System.IO.File]::ReadAllText($ps1.FullName, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($ps1.FullName, $content, [System.Text.UTF8Encoding]::new($true))
    Write-Log "BOM added: $($ps1.Name)"
}

# 1. git pull --ff-only в vault (silent on success).
$pullResult = & git -C $vaultRoot pull --ff-only 2>&1
Write-Log "git pull: $pullResult"

# 1.5. Авто-выставление kb.author из user.email через team/_handles.yml (ЛОКАЛЬНО в репо).
$existingAuthor = (& git -C $vaultRoot config kb.author) 2>$null
if (-not $existingAuthor) {
    $userEmail = (& git -C $vaultRoot config user.email) 2>$null
    if (-not $userEmail) { $userEmail = (& git config --global user.email) 2>$null }
    if ($userEmail) {
        $handlesPath = Join-Path $vaultRoot 'team/_handles.yml'
        if (Test-Path $handlesPath) {
            $matched = $null
            $inHandles = $false
            foreach ($line in Get-Content $handlesPath -Encoding UTF8) {
                if ($line -match '^handles:\s*$')      { $inHandles = $true;  continue }
                if ($line -match '^[A-Za-z_]\w*:\s*$') { $inHandles = $false; continue }
                if (-not $inHandles) { continue }
                if ($line -match '^\s+"([^"]+)":\s*([A-Za-z0-9_-]+)') {
                    if ($matches[1] -ieq $userEmail) { $matched = $matches[2]; break }
                }
            }
            if ($matched) {
                & git -C $vaultRoot config kb.author $matched
                Write-Log "kb.author auto-set (local): $matched (email=$userEmail)"
            } else {
                Write-Log "kb.author auto-detect skipped: email=$userEmail не в _handles.yml — выставь: git -C <vault> config kb.author <handle>"
            }
        } else {
            Write-Log "kb.author auto-detect skipped: $handlesPath не найден"
        }
    } else {
        Write-Log "kb.author auto-detect skipped: git user.email не задан"
    }
} else {
    Write-Log "kb.author уже задан: $existingAuthor"
}

# 1.7. Housekeeping (LLM-free, идемпотентно).
$housekeeping = @('archive-completed-now.ps1', 'archive-activity-overflow.ps1', 'archive-old-broadcasts.ps1')
foreach ($script in $housekeeping) {
    $path = Join-Path $vaultRoot ".claude/$script"
    if (Test-Path $path) {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $path -EventName SessionStart 2>&1 | Out-Null
        Write-Log "$script executed"
    }
}

# 1.8. YouGile task reminder (если хук есть и токен сконфигурирован — иначе тихо пропускаем).
$checkYougilePath = Join-Path $vaultRoot '.claude/check-yougile-tasks.ps1'
if (Test-Path $checkYougilePath) {
    $ygOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File $checkYougilePath -EventName SessionStart 2>&1
    if ($ygOutput) { Write-Output $ygOutput }
    Write-Log "check-yougile-tasks executed"
}

# 2. Refresh vault hooks в linked-проекте (idempotent). Для самого vault'а (CWD = vaultRoot) — skip.
$vaultLinkScript = Join-Path $vaultRoot '_system/tools/vault-link.ps1'
$markerPath = Join-Path $PWD.Path '.claude/vault-link.json'
if ((Test-Path $vaultLinkScript) -and (Test-Path $markerPath)) {
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $vaultLinkScript -Action link -ProjectDir $PWD.Path 2>&1 | Out-Null
    Write-Log "vault-link refresh for $($PWD.Path)"
} else {
    Write-Log "vault-link: skip (no marker or script not found)"
}

Write-Log "setup done"
exit 0
