# check-vault-bloat.ps1 - SessionStart MAX-size guard.
# Counterpart to check-vault-file-sizes.ps1 (which guards MIN size / data loss).
# Emits a BLOAT: reminder when append-only files exceed their token budget,
# so monoliths (inbox/broker/now/activity) get noticed before they reach ~1MB.
# Registration: SessionStart hook in .claude/settings.json
# See: MEMORY vault-token-drain-append-logs; rotation via archive-inbox.ps1 etc.

$VaultRoot = Split-Path -Parent $PSScriptRoot

# Per-glob byte budgets for files that get READ into agent context.
$budgets = @(
    @{ Glob = "inbox/*.md";           Max = 150KB },
    @{ Glob = "state/now.md";         Max = 30KB  },
    @{ Glob = "state/activity.md";    Max = 80KB  }
)

$warnings = @()
foreach ($b in $budgets) {
    $files = Get-ChildItem -Path (Join-Path $VaultRoot $b.Glob) -File -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        if ($f.Length -gt $b.Max) {
            $rel   = $f.FullName.Substring($VaultRoot.Length + 1).Replace('\', '/')
            $kb    = [math]::Round($f.Length / 1KB)
            $maxKb = [math]::Round($b.Max / 1KB)
            $warnings += "  ${rel}: ${kb}KB (budget ${maxKb}KB)"
        }
    }
}

if ($warnings.Count -gt 0) {
    $list = $warnings -join "; "
    Write-Output "BLOAT: $($warnings.Count) file(s) over size budget (token risk when read in full): $list. Rotate via archive-inbox.ps1 / archive-completed-now.ps1."
}
