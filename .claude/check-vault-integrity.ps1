#!/usr/bin/env pwsh
# SessionStart hook: лёгкий smoke-тест целостности vault'а (LLM-free).
# Ловит грубые аварии: кто-то/что-то занулил core-файл vault'а, или сломал XML диаграммы.
# Семантику (битые wikilinks, расхождения now.md ↔ ADR) ловят отдельные хуки
# (check-broken-wikilinks.ps1, check-vault-consistency.ps1) — здесь НЕ дублируем.
#
# Регистрация: SessionStart hook в .claude/settings.json.

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$VaultRoot = Split-Path -Parent $PSScriptRoot
$issues = @()

# ── 1. Core-файлы vault'а: существуют и не занулены ──
# Минимальный размер ловит «файл случайно затёрли до пустого», а не «файл маленький».
$coreFiles = @{
    "meta/CLAUDE.md"    = 200
    "state/now.md"      = 50
    "state/activity.md" = 50
    "meta/index.md"     = 50
}
foreach ($file in $coreFiles.Keys) {
    $fullPath = Join-Path $VaultRoot $file
    if (Test-Path $fullPath) {
        $size = (Get-Item $fullPath).Length
        $minSize = $coreFiles[$file]
        if ($size -lt $minSize) {
            $issues += "INTEGRITY-SIZE: $file is ${size}B (expected >= ${minSize}B) — возможно случайно затёрли"
        }
    } else {
        $issues += "INTEGRITY-MISSING: core-файл $file отсутствует"
    }
}

# ── 2. XML-валидность .drawio (если в vault'е есть диаграммы) ──
Get-ChildItem -Path $VaultRoot -Filter "*.drawio" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        [xml](Get-Content $_.FullName -Raw -ErrorAction Stop) | Out-Null
    } catch {
        $rel = $_.FullName.Substring($VaultRoot.Length).TrimStart('/', '\')
        $issues += "INTEGRITY-XML: $rel — невалидный XML"
    }
}

# ── Вывод ──
if ($issues.Count -gt 0) {
    $summary = $issues -join "`n  "
    Write-Output "INTEGRITY: $($issues.Count) issue(s) found:`n  $summary"
}
