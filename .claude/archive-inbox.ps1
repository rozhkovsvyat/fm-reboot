# SessionStart house-keeping: архивирует ✅-личные сообщения старше 30 дней
# из inbox/<handle>.md в inbox/archive/<handle>-YYYY-MM.md (по месяцу даты сообщения).
#
# Источник: drafts/memory-archival-automation.md, адаптировано из _system/tools/archive-inbox.ps1.
# НЕ трогает: 🟡 (непрочитанные), 📤/📨, @all broadcasts (их ведёт archive-old-broadcasts.ps1),
# строку легенды, H1-заголовок.
#
# Скрипт детерминированный (без LLM), идемпотентный, безопасный для повторных запусков.
# 🔴 DRAFT — не зарегистрирован в settings.json/SessionStart; подключить вручную после ревью.

param(
    [string]$EventName = 'SessionStart',
    [switch]$DryRun,         # -DryRun: показать что будет перенесено, без правок
    [int]$ThresholdDays = 30 # дней после ✅-маркировки
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$vaultRoot  = Split-Path -Parent $PSScriptRoot
$logPath    = Join-Path $PSScriptRoot 'archive-inbox-hook.log'
$threshold  = $ThresholdDays

function Write-Diag($msg) {
    $ts     = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $prefix = if ($DryRun) { '[DRY-RUN]' } else { '' }
    Add-Content -Path $logPath -Value "[$ts] [$EventName]$prefix $msg" -Encoding UTF8
}

Write-Diag "fired (threshold=${threshold}d, dryRun=$DryRun)"

$inboxDir   = Join-Path $vaultRoot 'inbox'
$archiveDir = Join-Path $inboxDir  'archive'
$today      = Get-Date

if (-not (Test-Path $inboxDir)) { Write-Diag "inbox/ not found - skip"; exit 0 }

# Получаем все handle-файлы (не archive/, не вспомогательные)
$handles = Get-ChildItem -Path $inboxDir -Filter '*.md' -File |
           Where-Object { $_.DirectoryName -eq $inboxDir } |
           Select-Object -ExpandProperty FullName

if ($handles.Count -eq 0) { Write-Diag "no inbox files found"; exit 0 }

# Создаём archive/ если нет
if (-not $DryRun -and -not (Test-Path $archiveDir)) {
    New-Item -ItemType Directory -Path $archiveDir | Out-Null
    Write-Diag "created inbox/archive/"
}

foreach ($filePath in $handles) {
    $handle = [IO.Path]::GetFileNameWithoutExtension($filePath)
    Write-Diag "processing inbox/$handle.md"

    $raw   = Get-Content $filePath -Raw -Encoding UTF8
    $lines = $raw -split "`r?`n"

    # Разбиваем контент на шапку и блоки сообщений (разделитель '---')
    $blocks   = @()
    $current  = [System.Collections.ArrayList]@()
    $header   = [System.Collections.ArrayList]@()
    $inHeader = $true

    foreach ($line in $lines) {
        if ($inHeader) {
            if ($line -match '^\s*###\s+\d{4}-\d{2}-\d{2}' -or
                $line -match '^\*\*From:\*\*' -or
                $line -match '^\s*-\s+(🟡|✅|📤|📨)') {
                $inHeader = $false
                [void]$current.Add($line)
            } else {
                [void]$header.Add($line)
            }
            continue
        }

        if ($line -match '^---\s*$') {
            if ($current.Count -gt 0) { $blocks += ,($current.ToArray()) }
            $current = [System.Collections.ArrayList]@()
        } else {
            [void]$current.Add($line)
        }
    }
    if ($current.Count -gt 0) { $blocks += ,($current.ToArray()) }

    # Классифицируем блоки
    $toKeep    = [System.Collections.ArrayList]@()
    $toArchive = @{}  # ключ = 'YYYY-MM', значение = список блоков

    foreach ($block in $blocks) {
        $blockText = $block -join "`n"
        if ($blockText.Trim() -eq '') { continue }

        $hasUnread   = $blockText -match '🟡'
        $hasDone     = $blockText -match '✅'
        $isBroadcast = $blockText -match '@all\b'

        if ($hasUnread -or -not $hasDone -or $isBroadcast) {
            [void]$toKeep.Add($block)
            continue
        }

        # Извлекаем дату блока из первых строк
        $blockDate = $null
        foreach ($bline in $block[0..([Math]::Min(5, $block.Length - 1))]) {
            if ($bline -match '(\d{4}-\d{2}-\d{2})') {
                try {
                    $blockDate = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd', $null)
                    break
                } catch {}
            }
        }

        if ($null -eq $blockDate) { [void]$toKeep.Add($block); continue }

        $ageDays = ($today - $blockDate).Days
        if ($ageDays -lt $threshold) { [void]$toKeep.Add($block); continue }

        $monthKey = $blockDate.ToString('yyyy-MM')
        if (-not $toArchive.ContainsKey($monthKey)) {
            $toArchive[$monthKey] = [System.Collections.ArrayList]@()
        }
        [void]$toArchive[$monthKey].Add($block)
    }

    $archiveCount = ($toArchive.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
    if ($null -eq $archiveCount) { $archiveCount = 0 }

    if ($archiveCount -eq 0) { Write-Diag "  ${handle}: nothing to archive"; continue }

    Write-Diag "  ${handle}: archiving $archiveCount block(s) ($($toArchive.Keys -join ', '))"

    if ($DryRun) {
        foreach ($monthKey in $toArchive.Keys | Sort-Object) {
            $cnt = $toArchive[$monthKey].Count
            Write-Host "  [DRY-RUN] ${handle}: would archive $cnt block(s) → inbox/archive/${handle}-$monthKey.md"
        }
        continue
    }

    # Записываем блоки в архивные файлы
    foreach ($monthKey in $toArchive.Keys | Sort-Object) {
        $archivePath   = Join-Path $archiveDir "${handle}-$monthKey.md"
        $blocksToWrite = $toArchive[$monthKey]

        $appendLines = [System.Collections.ArrayList]@()
        if (-not (Test-Path $archivePath)) {
            [void]$appendLines.Add("# inbox/$handle — архив $monthKey")
            [void]$appendLines.Add("")
            [void]$appendLines.Add("> Перенесено автоматически ``.claude/archive-inbox.ps1`` (✅-записи старше ${threshold} дней).")
            [void]$appendLines.Add("")
        }

        foreach ($block in $blocksToWrite) {
            foreach ($bline in $block) { [void]$appendLines.Add($bline) }
            [void]$appendLines.Add('---')
        }

        $tmpPath      = "$archivePath.tmp"
        $existingRaw  = if (Test-Path $archivePath) { Get-Content $archivePath -Raw -Encoding UTF8 } else { '' }
        $newContent   = $existingRaw.TrimEnd() + "`n" + ($appendLines -join "`n") + "`n"
        Set-Content -Path $tmpPath -Value $newContent -Encoding UTF8
        Move-Item -Path $tmpPath -Destination $archivePath -Force
        Write-Diag "  ${handle}: wrote $($blocksToWrite.Count) block(s) to inbox/archive/$handle-$monthKey.md"
    }

    # Перезаписываем inbox/<handle>.md без архивированных блоков
    $newLines = [System.Collections.ArrayList]@()
    foreach ($hline in $header) { [void]$newLines.Add($hline) }
    foreach ($block in $toKeep) {
        foreach ($bline in $block) { [void]$newLines.Add($bline) }
        [void]$newLines.Add('---')
    }

    $newContent = ($newLines -join "`n").TrimEnd() + "`n"
    $tmpPath    = "$filePath.tmp"
    Set-Content -Path $tmpPath -Value $newContent -Encoding UTF8
    Move-Item -Path $tmpPath -Destination $filePath -Force
    Write-Diag "  ${handle}: inbox updated (kept $($toKeep.Count) block(s))"
}

Write-Diag "done"
exit 0
