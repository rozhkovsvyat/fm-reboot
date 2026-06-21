# vault-link.ps1 — opt-in per-project vault hooks.
# Подключает/отключает проект к хукам vault'а (INBOX/STALE/DISCIPLINE/...).
#
# Использование:
#   pwsh vault-link.ps1                              # link текущий cwd
#   pwsh vault-link.ps1 -Action link -ProjectDir /path/to/project
#   pwsh vault-link.ps1 -Action unlink
#   pwsh vault-link.ps1 -Action status
#   pwsh vault-link.ps1 -Action list
#   pwsh vault-link.ps1 -Action update               # refresh все linked проекты

param(
    [ValidateSet('link', 'unlink', 'status', 'list', 'update')]
    [string]$Action = 'link',
    [string]$ProjectDir
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$vaultRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$claudeUserDir = Join-Path $userHome '.claude'

if (-not $ProjectDir) { $ProjectDir = $PWD.Path }
$ProjectDir = (Resolve-Path $ProjectDir -ErrorAction Stop).Path

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------

function Merge-HookBlocks {
    param(
        [object[]]$Existing,
        $NewVaultBlock
    )
    $external = @()
    if ($Existing) {
        foreach ($block in $Existing) {
            $isVault = $false
            if ($block -and $block.hooks) {
                foreach ($cmd in $block.hooks) {
                    if ($cmd -and $cmd.command -and ($cmd.command -match 'vault-memory-core')) {
                        $isVault = $true
                        break
                    }
                }
            }
            if (-not $isVault) { $external += $block }
        }
    }
    if ($null -eq $NewVaultBlock) { return ,$external }
    $result = $external + @($NewVaultBlock)
    return ,$result
}

function Read-SettingsJson {
    param([string]$Path)
    $settings = $null
    if (Test-Path $Path) {
        $raw = Get-Content $Path -Raw -Encoding UTF8
        if ($raw -and $raw.Trim()) {
            try {
                $settings = $raw | ConvertFrom-Json -AsHashtable
            } catch {
                Write-Warning "settings.json parse error ($_): rebuilding as empty"
                $settings = $null
            }
        }
    }
    if ($null -eq $settings -or -not ($settings -is [System.Collections.IDictionary])) {
        $settings = [ordered]@{}
    }
    return $settings
}

function Write-SettingsJson {
    param([string]$Path, $Settings)
    if ($null -eq $Settings -or -not ($Settings -is [System.Collections.IDictionary])) {
        Write-Warning "Settings lost Dictionary type — skipping write to $Path"
        return $false
    }
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $tmpPath = "$Path.tmp-$(Get-Random)"
    $Settings | ConvertTo-Json -Depth 10 | Set-Content -Path $tmpPath -Encoding UTF8
    Move-Item -Path $tmpPath -Destination $Path -Force
    return $true
}

function Build-VaultHooks {
    param([string]$VaultRoot)

    $setupPath          = Join-Path $VaultRoot '_system/tools/setup.ps1'
    $checkInboxPath     = Join-Path $VaultRoot '.claude/check-inbox.ps1'
    $checkOverviewPath  = Join-Path $VaultRoot '.claude/check-overview-stale.ps1'
    $checkNowStalePath  = Join-Path $VaultRoot '.claude/check-now-stale.ps1'
    $checkStaleExtPath  = Join-Path $VaultRoot '.claude/check-stale-extended.ps1'
    $checkBrokenLinks   = Join-Path $VaultRoot '.claude/check-broken-wikilinks.ps1'
    $checkDraftLifecycle = Join-Path $VaultRoot '.claude/check-draft-lifecycle.ps1'
    $checkDisciplinePath = Join-Path $VaultRoot '.claude/check-vault-discipline.ps1'
    $checkInboxOnStop   = Join-Path $VaultRoot '.claude/check-inbox-on-stop.ps1'
    $checkConsistency   = Join-Path $VaultRoot '.claude/check-vault-consistency.ps1'

    $sessionStart = [ordered]@{
        hooks = @(
            [ordered]@{
                type          = 'command'
                command       = "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$setupPath`""
                timeout       = 30
                statusMessage = 'Portal 5 vault sync...'
            }
        )
    }

    $userPrompt = [ordered]@{
        hooks = @(
            [ordered]@{
                type    = 'command'
                command = "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$checkInboxPath`" -EventName UserPromptSubmit"
                timeout = 5
            },
            [ordered]@{
                type    = 'command'
                command = "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$checkOverviewPath`" -EventName UserPromptSubmit"
                timeout = 10
            },
            [ordered]@{
                type    = 'command'
                command = "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$checkNowStalePath`" -EventName UserPromptSubmit"
                timeout = 5
            },
            [ordered]@{
                type    = 'command'
                command = "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$checkStaleExtPath`" -EventName UserPromptSubmit"
                timeout = 15
            },
            [ordered]@{
                type    = 'command'
                command = "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$checkBrokenLinks`" -EventName UserPromptSubmit"
                timeout = 10
            },
            [ordered]@{
                type    = 'command'
                command = "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$checkDraftLifecycle`" -EventName UserPromptSubmit"
                timeout = 10
            }
        )
    }

    $stop = [ordered]@{
        hooks = @(
            [ordered]@{
                type    = 'command'
                command = "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$checkDisciplinePath`" -EventName Stop"
                timeout = 10
            },
            [ordered]@{
                type    = 'command'
                command = "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$checkInboxOnStop`" -EventName Stop"
                timeout = 5
            },
            [ordered]@{
                type    = 'command'
                command = "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$checkConsistency`" -EventName Stop"
                timeout = 15
            }
        )
    }

    return @{
        SessionStart     = $sessionStart
        UserPromptSubmit = $userPrompt
        Stop             = $stop
    }
}

function Register-LinkedProject {
    param([string]$ProjDir)
    $registryPath = Join-Path $vaultRoot '.claude/linked-projects.json'
    $registry = @()
    if (Test-Path $registryPath) {
        try { $registry = @(Get-Content $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json) }
        catch { $registry = @() }
    }
    $registry = @($registry | Where-Object { $_ -ne $ProjDir })
    $registry += $ProjDir
    $registry | ConvertTo-Json -Depth 5 | Set-Content -Path $registryPath -Encoding UTF8
}

function Unregister-LinkedProject {
    param([string]$ProjDir)
    $registryPath = Join-Path $vaultRoot '.claude/linked-projects.json'
    if (-not (Test-Path $registryPath)) { return }
    try {
        $registry = @(Get-Content $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json)
        $registry = @($registry | Where-Object { $_ -ne $ProjDir })
        if ($registry.Count -eq 0) {
            Remove-Item $registryPath -Force
        } else {
            $registry | ConvertTo-Json -Depth 5 | Set-Content -Path $registryPath -Encoding UTF8
        }
    } catch { }
}

function Clean-GlobalVaultHooks {
    $globalSettingsPath = Join-Path $claudeUserDir 'settings.json'
    if (-not (Test-Path $globalSettingsPath)) { return }
    $globalSettings = Read-SettingsJson -Path $globalSettingsPath
    if (-not $globalSettings.Contains('hooks')) { return }

    $changed = $false
    foreach ($event in @('SessionStart', 'UserPromptSubmit', 'Stop')) {
        if (-not $globalSettings['hooks'].Contains($event)) { continue }
        $before = @($globalSettings['hooks'][$event])
        $after = Merge-HookBlocks -Existing $before -NewVaultBlock $null
        if ($after.Count -ne $before.Count) {
            $changed = $true
            if ($after.Count -eq 0) {
                $globalSettings['hooks'].Remove($event)
            } else {
                $globalSettings['hooks'][$event] = $after
            }
        }
    }
    if ($globalSettings['hooks'] -is [System.Collections.IDictionary] -and $globalSettings['hooks'].Count -eq 0) {
        $globalSettings.Remove('hooks')
    }
    if ($changed) {
        Write-SettingsJson -Path $globalSettingsPath -Settings $globalSettings | Out-Null
        Write-Output "VAULT-LINK: cleaned vault hooks from global ~/.claude/settings.json"
    }
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

switch ($Action) {

    'link' {
        # Guard: vault is self-managed
        if ($ProjectDir -eq $vaultRoot) {
            Write-Output "VAULT-LINK: this IS the vault ($vaultRoot) — hooks are already managed via project-level settings.json, skipping."
            exit 0
        }

        $projectClaudeDir = Join-Path $ProjectDir '.claude'
        $settingsPath = Join-Path $projectClaudeDir 'settings.json'
        $markerPath = Join-Path $projectClaudeDir 'vault-link.json'

        $vaultBlocks = Build-VaultHooks -VaultRoot $vaultRoot

        $settings = Read-SettingsJson -Path $settingsPath
        if (-not $settings.Contains('hooks')) { $settings['hooks'] = [ordered]@{} }

        foreach ($event in @('SessionStart', 'UserPromptSubmit', 'Stop')) {
            $existing = if ($settings['hooks'].Contains($event)) { @($settings['hooks'][$event]) } else { @() }
            $settings['hooks'][$event] = Merge-HookBlocks -Existing $existing -NewVaultBlock $vaultBlocks[$event]
        }

        Write-SettingsJson -Path $settingsPath -Settings $settings | Out-Null

        $marker = [ordered]@{
            schemaVersion = 1
            vaultRoot     = $vaultRoot
            linkedAt      = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        }
        $marker | ConvertTo-Json -Depth 5 | Set-Content -Path $markerPath -Encoding UTF8

        Register-LinkedProject -ProjDir $ProjectDir
        Clean-GlobalVaultHooks

        Write-Output "VAULT-LINK: linked $ProjectDir -> $vaultRoot (10 hooks)"
    }

    'unlink' {
        $projectClaudeDir = Join-Path $ProjectDir '.claude'
        $settingsPath = Join-Path $projectClaudeDir 'settings.json'
        $markerPath = Join-Path $projectClaudeDir 'vault-link.json'

        if (-not (Test-Path $settingsPath)) {
            Write-Output "VAULT-LINK: $ProjectDir has no .claude/settings.json — nothing to unlink"
            exit 0
        }

        $settings = Read-SettingsJson -Path $settingsPath
        if ($settings.Contains('hooks')) {
            foreach ($event in @('SessionStart', 'UserPromptSubmit', 'Stop')) {
                if (-not $settings['hooks'].Contains($event)) { continue }
                $remaining = Merge-HookBlocks -Existing @($settings['hooks'][$event]) -NewVaultBlock $null
                if ($remaining.Count -eq 0) {
                    $settings['hooks'].Remove($event)
                } else {
                    $settings['hooks'][$event] = $remaining
                }
            }
            if ($settings['hooks'] -is [System.Collections.IDictionary] -and $settings['hooks'].Count -eq 0) {
                $settings.Remove('hooks')
            }
        }

        Write-SettingsJson -Path $settingsPath -Settings $settings | Out-Null

        if (Test-Path $markerPath) { Remove-Item $markerPath -Force }
        Unregister-LinkedProject -ProjDir $ProjectDir

        Write-Output "VAULT-LINK: unlinked $ProjectDir"
    }

    'status' {
        $markerPath = Join-Path $ProjectDir '.claude/vault-link.json'
        if (-not (Test-Path $markerPath)) {
            Write-Output "VAULT-LINK: $ProjectDir is NOT linked to any vault"
            exit 0
        }
        try {
            $marker = Get-Content $markerPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
        } catch {
            Write-Output "VAULT-LINK: $ProjectDir has corrupted vault-link.json"
            exit 1
        }
        $vaultExists = Test-Path $marker.vaultRoot

        $settingsPath = Join-Path $ProjectDir '.claude/settings.json'
        $hookCount = 0
        if (Test-Path $settingsPath) {
            $s = Read-SettingsJson -Path $settingsPath
            if ($s.Contains('hooks')) {
                foreach ($event in @('SessionStart', 'UserPromptSubmit', 'Stop')) {
                    if (-not $s['hooks'].Contains($event)) { continue }
                    foreach ($block in @($s['hooks'][$event])) {
                        if ($block -and $block.hooks) {
                            foreach ($h in $block.hooks) {
                                if ($h.command -match 'vault-memory-core') { $hookCount++ }
                            }
                        }
                    }
                }
            }
        }

        Write-Output "VAULT-LINK: $ProjectDir"
        Write-Output "  vault:  $($marker.vaultRoot) (exists=$vaultExists)"
        Write-Output "  linked: $($marker.linkedAt)"
        Write-Output "  hooks:  $hookCount vault hook(s) in settings.json"
    }

    'list' {
        $registryPath = Join-Path $vaultRoot '.claude/linked-projects.json'
        if (-not (Test-Path $registryPath)) {
            Write-Output "VAULT-LINK: no linked projects"
            exit 0
        }
        try {
            $registry = @(Get-Content $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json)
        } catch {
            Write-Output "VAULT-LINK: linked-projects.json is corrupted"
            exit 1
        }

        $cleanRegistry = @()
        Write-Output "VAULT-LINK: $($registry.Count) linked project(s)"
        foreach ($p in $registry) {
            $marker = Join-Path $p '.claude/vault-link.json'
            $dirExists = Test-Path $p
            $markerExists = Test-Path $marker
            if ($dirExists -and $markerExists) {
                $status = 'OK'
                $cleanRegistry += $p
            } elseif ($dirExists) {
                $status = 'STALE (marker missing)'
            } else {
                $status = 'STALE (directory missing)'
            }
            Write-Output "  $p  [$status]"
        }

        if ($cleanRegistry.Count -ne $registry.Count) {
            if ($cleanRegistry.Count -eq 0) {
                Remove-Item $registryPath -Force
            } else {
                $cleanRegistry | ConvertTo-Json -Depth 5 | Set-Content -Path $registryPath -Encoding UTF8
            }
            $removed = $registry.Count - $cleanRegistry.Count
            Write-Output "  (cleaned $removed stale entries from registry)"
        }
    }

    'update' {
        $registryPath = Join-Path $vaultRoot '.claude/linked-projects.json'
        if (-not (Test-Path $registryPath)) {
            Write-Output "VAULT-LINK: no linked projects to update"
            exit 0
        }
        try {
            $registry = @(Get-Content $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json)
        } catch {
            Write-Output "VAULT-LINK: linked-projects.json is corrupted"
            exit 1
        }

        foreach ($p in $registry) {
            if (Test-Path $p) {
                Write-Output "VAULT-LINK: refreshing $p ..."
                & $PSCommandPath -Action link -ProjectDir $p
            } else {
                Write-Output "VAULT-LINK: SKIP $p (directory not found)"
            }
        }
    }
}
