# Единый runner для vault-проверок. Для IDE без hook-системы (Cursor, Codex, Cline)
# и для ручного запуска. Claude Code вызывает каждый хук отдельно через settings.json;
# этот скрипт объединяет все проверки в одну точку входа.
#
# Использование:
#   pwsh _system/tools/run-vault-checks.ps1 -Phase SessionStart
#   pwsh _system/tools/run-vault-checks.ps1 -Phase PromptCheck
#   pwsh _system/tools/run-vault-checks.ps1 -Phase EndOfWork

param(
    [Parameter(Mandatory)]
    [ValidateSet('SessionStart', 'PromptCheck', 'EndOfWork')]
    [string]$Phase
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$vaultRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$claudeDir = Join-Path $vaultRoot '.claude'

function Run-Hook($scriptName, $eventName) {
    $path = Join-Path $claudeDir $scriptName
    if (Test-Path $path) {
        $output = & pwsh -NoProfile -ExecutionPolicy Bypass -File $path -EventName $eventName 2>&1
        if ($output) { Write-Output $output }
    }
}

switch ($Phase) {
    'SessionStart' {
        # 1. setup (git pull + kb.author + housekeeping + BOM + announced reset)
        $setup = Join-Path $vaultRoot '_system/tools/setup.ps1'
        if (Test-Path $setup) {
            $out = & pwsh -NoProfile -ExecutionPolicy Bypass -File $setup 2>&1
            if ($out) { Write-Output $out }
        }
        Run-Hook 'check-vault-integrity.ps1' 'SessionStart'
        Run-Hook 'check-vault-bloat.ps1' 'SessionStart'
        # сразу прогоняем PromptCheck — чтобы при старте увидеть накопленные напоминания
        Run-Hook 'check-inbox.ps1' 'SessionStart'
        Run-Hook 'check-overview-stale.ps1' 'SessionStart'
        Run-Hook 'check-now-stale.ps1' 'SessionStart'
        Run-Hook 'check-stale-extended.ps1' 'SessionStart'
        Run-Hook 'check-broken-wikilinks.ps1' 'SessionStart'
        Run-Hook 'check-draft-lifecycle.ps1' 'SessionStart'
        Run-Hook 'check-yougile-tasks.ps1' 'SessionStart'
    }

    'PromptCheck' {
        Run-Hook 'check-inbox.ps1' 'UserPromptSubmit'
        Run-Hook 'check-overview-stale.ps1' 'UserPromptSubmit'
        Run-Hook 'check-now-stale.ps1' 'UserPromptSubmit'
        Run-Hook 'check-stale-extended.ps1' 'UserPromptSubmit'
        Run-Hook 'check-broken-wikilinks.ps1' 'UserPromptSubmit'
        Run-Hook 'check-draft-lifecycle.ps1' 'UserPromptSubmit'
        Run-Hook 'check-mistakes-daily-review.ps1' 'UserPromptSubmit'
        Run-Hook 'check-inbox-adequacy-due.ps1' 'UserPromptSubmit'
        Run-Hook 'check-yougile-tasks.ps1' 'UserPromptSubmit'
    }

    'EndOfWork' {
        Run-Hook 'check-vault-discipline.ps1' 'Stop'
        Run-Hook 'check-inbox-on-stop.ps1' 'Stop'
        Run-Hook 'check-vault-consistency.ps1' 'Stop'
        Run-Hook 'check-mistakes-candidate.ps1' 'Stop'
        Run-Hook 'check-verify-gate.ps1' 'Stop'
        Run-Hook 'check-yougile-tasks.ps1' 'Stop'
    }
}
