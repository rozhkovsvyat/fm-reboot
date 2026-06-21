# Хук слежения за задачами YouGile (замена корпоративного check-repka-tasks).
# SessionStart  → полная сводка открытых задач.
# UserPromptSubmit/Stop → дельта (новые / закрытые) vs .claude/yougile-last-state.json.
#
# ГРЕЙСФУЛ: нет токена (~/.claude/yougile-token или env YOUGILE_TOKEN) / нет python3 /
# сеть недоступна — хук МОЛЧА выходит (exit 0). Не ломает промпты на свежеклонированном vault'е.
#
# Маркеры (по аналогии с inbox):
#   YOUGILE:     полная сводка (SessionStart)
#   YOUGILE-UPD: дельта (UserPromptSubmit)
#   YOUGILE-EOT: дельта (Stop)

param([string]$EventName = 'UserPromptSubmit')

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$vaultRoot = Split-Path -Parent $PSScriptRoot
$logPath = Join-Path $PSScriptRoot 'yougile-hook.log'
function Write-Diag($m) { Add-Content -Path $logPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$EventName] $m" -Encoding UTF8 }

# --- грейсфул-гейты ---
$tokenFile = Join-Path $HOME '.claude/yougile-token'
if (-not $env:YOUGILE_TOKEN -and -not (Test-Path $tokenFile)) { Write-Diag "нет токена — skip"; exit 0 }

$python = (Get-Command python3 -ErrorAction SilentlyContinue).Source
if (-not $python) { $python = (Get-Command python -ErrorAction SilentlyContinue).Source }
if (-not $python) { Write-Diag "нет python — skip"; exit 0 }

$cli = Join-Path $vaultRoot '_system/tools/yougile-sync/yougile-cli.py'
if (-not (Test-Path $cli)) { Write-Diag "нет CLI — skip"; exit 0 }

# --- запрос списка задач (короткий таймаут через сам urllib внутри CLI) ---
$raw = & $python $cli --json list 2>$null
if (-not $raw) { Write-Diag "пустой ответ CLI — skip"; exit 0 }
try { $data = $raw | ConvertFrom-Json } catch { Write-Diag "не JSON — skip"; exit 0 }
if (-not $data.ok) { Write-Diag "CLI error: $($data.error) — skip"; exit 0 }

$tasks = @($data.tasks)
$count = $tasks.Count

# текущее состояние: id → title
$curState = @{}
foreach ($t in $tasks) { $curState[[string]$t.id] = $t.title }

$statePath = Join-Path $PSScriptRoot 'yougile-last-state.json'

if ($EventName -eq 'SessionStart') {
    # полная сводка + записать состояние
    $curState | ConvertTo-Json -Compress | Set-Content -Path $statePath -Encoding UTF8
    if ($count -eq 0) { Write-Diag "0 задач"; exit 0 }
    $top = ($tasks | Select-Object -First 5 | ForEach-Object {
        $dl = if ($_.deadline) { " (⏰ $($_.deadline))" } else { "" }
        "• $($_.title)$dl"
    }) -join "; "
    $msg = "YOUGILE: $count открытых задач на доске reboot. Top: $top. Покажи пользователю и спроси, что берём в работу. Управление — ``/create-task`` / ``yougile-cli.py``."
    $payload = @{ hookSpecificOutput = @{ hookEventName = $EventName; additionalContext = $msg } } | ConvertTo-Json -Compress
    Write-Output $payload
    Write-Diag "session summary; count=$count"
    exit 0
}

# дельта vs прошлого состояния
$prev = @{}
if (Test-Path $statePath) {
    try {
        $obj = (Get-Content $statePath -Raw -Encoding UTF8) | ConvertFrom-Json
        $obj.PSObject.Properties | ForEach-Object { $prev[$_.Name] = $_.Value }
    } catch {}
}

$newIds = @($curState.Keys | Where-Object { -not $prev.ContainsKey($_) })
$goneIds = @($prev.Keys | Where-Object { -not $curState.ContainsKey($_) })

# записать актуальное состояние всегда
$curState | ConvertTo-Json -Compress | Set-Content -Path $statePath -Encoding UTF8

if ($newIds.Count -eq 0 -and $goneIds.Count -eq 0) { Write-Diag "без изменений"; exit 0 }

$parts = @()
if ($newIds.Count -gt 0) {
    $names = ($newIds | ForEach-Object { $curState[$_] } | Select-Object -First 3) -join "; "
    $parts += "новые ($($newIds.Count)): $names"
}
if ($goneIds.Count -gt 0) {
    $names = ($goneIds | ForEach-Object { $prev[$_] } | Select-Object -First 3) -join "; "
    $parts += "закрыты/убраны ($($goneIds.Count)): $names"
}
$marker = if ($EventName -eq 'Stop') { 'YOUGILE-EOT' } else { 'YOUGILE-UPD' }
$msg = "${marker}: изменения в задачах reboot — " + ($parts -join ' | ') + ". Упомяни пользователю одной строкой; если влияет на текущую работу — учти."

if ($EventName -eq 'Stop' -or $EventName -eq 'SessionEnd') {
    $payload = @{ systemMessage = $msg } | ConvertTo-Json -Compress
} else {
    $payload = @{ hookSpecificOutput = @{ hookEventName = $EventName; additionalContext = $msg } } | ConvertTo-Json -Compress
}
Write-Output $payload
Write-Diag "delta new=$($newIds.Count) gone=$($goneIds.Count)"
exit 0
