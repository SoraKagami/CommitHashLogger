#Requires -Version 5.1
<#
.SYNOPSIS
    Records the commit history of a git repo into a log file that never loses entries.

.DESCRIPTION
    Reads every commit reachable from HEAD, local branches, tags and remote branches
    of the Target repo and keeps one line per commit in the log file:

        Status <TAB> Date-Time (UTC, YYYYMMDD-HHMM) <TAB> Full hash <TAB> Summary <LF>

    Status characters:
        +  commit is in the repo history
        ~  commit was changed: it was amended/rebased and a new commit replaces it
           (the replacement has its own "+" line)
        -  commit was removed from the history, but git still holds the old commit
        ?  commit disappeared: it cannot be found in the repo at all

    Lines are never deleted. When a commit goes away, only its status character changes.
    New commits are appended to the end of the file.

.PARAMETER ConfigPath
    Path to a .psd1 config file holding the three settings Target, Output and
    LogFileName. See Example.psd1. Relative Target/Output paths in the config
    are taken relative to the folder the config file is in.

.PARAMETER Force
    Skip the safety check that stops the script when none of the commits already in
    the log can be found in Target (which normally means the wrong repo or log file).

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File CommitHashLogger.ps1 MyRepo.psd1
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ConfigPath,

    [switch]$Force
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

# ------------------------------ load config ------------------------------
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Config file not found: $ConfigPath"
}
$ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).ProviderPath
$configDir  = Split-Path -Parent $ConfigPath

# Import-PowerShellDataFile only reads data; it cannot run code from the file.
$config = Import-PowerShellDataFile -LiteralPath $ConfigPath

foreach ($key in 'Target', 'Output', 'LogFileName') {
    if (-not $config.ContainsKey($key) -or [string]::IsNullOrWhiteSpace([string]$config[$key])) {
        throw "Config file '$ConfigPath' is missing a value for '$key'."
    }
}

$Target      = [string]$config['Target']
$Output      = [string]$config['Output']
$LogFileName = [string]$config['LogFileName']

if (-not [IO.Path]::IsPathRooted($Target)) { $Target = Join-Path $configDir $Target }
if (-not [IO.Path]::IsPathRooted($Output)) { $Output = Join-Path $configDir $Output }
if ($LogFileName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
    throw "LogFileName must be a file name only, without a folder path: $LogFileName"
}

Write-Host "Config: $ConfigPath"

$Tab = "`t"

function Invoke-Git {
    # Runs git against the Target repo. Error preference is relaxed here so that
    # text git writes to its error stream does not abort the script by itself;
    # callers check $LASTEXITCODE instead.
    $ErrorActionPreference = 'Continue'
    & git -C $Target -c i18n.logOutputEncoding=UTF-8 @args
}

# Make PowerShell read git's output as UTF-8 so non-English summaries survive.
$previousEncoding = [Console]::OutputEncoding
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }

try {
    # ----------------------------- checks -----------------------------
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'git was not found. Install Git for Windows or add it to PATH.'
    }
    if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
        throw "Target folder not found: $Target"
    }
    $Target = (Resolve-Path -LiteralPath $Target).ProviderPath

    $topLevel = Invoke-Git rev-parse --show-toplevel
    if ($LASTEXITCODE -ne 0) {
        throw "Target is not a git repository (or git refused to open it): $Target"
    }
    if (($topLevel -replace '/', '\').TrimEnd('\') -ne $Target.TrimEnd('\')) {
        Write-Warning "Target does not look like the repo root. Git reports the root as: $topLevel"
    }

    if (-not (Test-Path -LiteralPath $Output -PathType Container)) {
        New-Item -ItemType Directory -Path $Output -Force | Out-Null
    }
    $Output  = (Resolve-Path -LiteralPath $Output).ProviderPath
    $logPath = Join-Path $Output $LogFileName

    # ------------------- read current commits from git -------------------
    $revisions = @('--branches', '--tags', '--remotes')
    $null = Invoke-Git rev-parse --verify --quiet 'HEAD^{commit}'
    if ($LASTEXITCODE -eq 0) { $revisions = @('HEAD') + $revisions }

    # Fields: hash, committer time (unix), author time (unix), author email, summary
    $rawCommits = @(Invoke-Git log --reverse '--format=%H%x09%ct%x09%at%x09%ae%x09%s' @revisions)
    if ($LASTEXITCODE -ne 0) {
        throw 'git log failed. The log file was not touched.'
    }

    $epoch       = New-Object DateTime 1970, 1, 1, 0, 0, 0, ([DateTimeKind]::Utc)
    $invariant   = [Globalization.CultureInfo]::InvariantCulture
    $current     = @{}     # hash -> finished log line (with "+" status)
    $order       = New-Object System.Collections.Generic.List[string]   # hashes, oldest first
    $authorKeys  = @{}     # "author time + author email" of every current commit

    foreach ($raw in $rawCommits) {
        $parts = $raw.Split([char[]]$Tab, 5)
        if ($parts.Count -lt 5) {
            throw "Unexpected line from git log: $raw"
        }
        $hash    = $parts[0]
        $date    = $epoch.AddSeconds([long]$parts[1]).ToString('yyyyMMdd-HHmm', $invariant)
        $summary = ($parts[4] -replace '[\x00-\x1f\x7f]', ' ').TrimEnd()

        if (-not $current.ContainsKey($hash)) {
            $current[$hash] = '+' + $Tab + $date + $Tab + $hash + $Tab + $summary
            $order.Add($hash)
        }
        $authorKeys[$parts[2] + ' ' + $parts[3]] = $true
    }

    # ------------------------ read the existing log ------------------------
    $utf8NoBom    = New-Object System.Text.UTF8Encoding $false
    $lines        = New-Object System.Collections.Generic.List[string]
    $originalText = $null

    if (Test-Path -LiteralPath $logPath -PathType Leaf) {
        $originalText = [IO.File]::ReadAllText($logPath, $utf8NoBom)
        foreach ($line in ($originalText -split "`n")) {
            $lines.Add($line.TrimEnd("`r"))
        }
        while ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') {
            $lines.RemoveAt($lines.Count - 1)
        }
    }
    else {
        $lines.Add('# Columns (tab-separated): Status, Commit date-time in UTC (YYYYMMDD-HHMM), Commit hash, Commit summary')
        $lines.Add('# Status: + = commit is in the repo history, ~ = commit was changed (amended/rebased; replaced by a newer commit),')
        $lines.Add('#         - = commit was removed from the history, ? = commit disappeared (no longer found in the repo)')
    }

    # ------------------ update the status of logged commits ------------------
    $linePattern  = [regex]'^([+\-~?])\t(\d{8}-\d{4})\t([0-9a-f]{40,64})\t(.*)$'
    $logged       = @{}    # hashes that already have a line
    $entryCount   = 0
    $foundCount   = 0      # logged commits that git still knows about in any form
    $unreadable   = 0
    $changes      = @{ '+' = 0; '~' = 0; '-' = 0; '?' = 0 }

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line  = $lines[$i]
        $match = $linePattern.Match($line)
        if (-not $match.Success) {
            if ($line.Trim() -ne '' -and -not $line.StartsWith('#')) { $unreadable++ }
            continue
        }

        $entryCount++
        $oldStatus = $match.Groups[1].Value
        $hash      = $match.Groups[3].Value
        $logged[$hash] = $true

        if ($current.ContainsKey($hash)) {
            $newStatus = '+'
            $foundCount++
        }
        else {
            $null = Invoke-Git rev-parse --verify --quiet "$hash^{commit}"
            if ($LASTEXITCODE -eq 0) {
                # Git still has the old commit, it is just not part of the history any more.
                # If a current commit has the same author time and author email, the old
                # commit was rewritten (amend/rebase keep those two values).
                $foundCount++
                $authorKey = Invoke-Git log --no-walk --max-count=1 '--format=%at %ae' $hash
                if ($LASTEXITCODE -eq 0 -and $authorKey -and $authorKeys.ContainsKey([string]$authorKey)) {
                    $newStatus = '~'
                }
                else {
                    $newStatus = '-'
                }
            }
            elseif ($oldStatus -eq '+') {
                $newStatus = '?'
            }
            else {
                # Already marked ~, - or ? on an earlier run: keep what was observed then.
                $newStatus = $oldStatus
            }
        }

        if ($newStatus -ne $oldStatus) {
            $lines[$i] = $newStatus + $line.Substring(1)
            $changes[$newStatus]++
        }
    }

    if ($entryCount -gt 0 -and $foundCount -eq 0 -and -not $Force) {
        throw ("None of the $entryCount commits already in '$logPath' exist in '$Target'. " +
               'This usually means Target or LogFileName points at the wrong repo. ' +
               'The log file was not touched. Run again with -Force if this is intended.')
    }

    # --------------------------- append new commits ---------------------------
    $added = 0
    foreach ($hash in $order) {
        if (-not $logged.ContainsKey($hash)) {
            $lines.Add($current[$hash])
            $added++
        }
    }

    # ------------------------------- write -------------------------------
    $newText = ($lines -join "`n") + "`n"

    if ($null -ne $originalText -and $newText -ceq $originalText) {
        Write-Host "No changes. $entryCount commits in $logPath"
    }
    else {
        # Write to a temporary file first so a failure cannot leave a half-written log.
        $tempPath = $logPath + '.tmp'
        [IO.File]::WriteAllText($tempPath, $newText, $utf8NoBom)
        Move-Item -LiteralPath $tempPath -Destination $logPath -Force

        Write-Host "Updated $logPath"
        Write-Host ("  New commits added      : {0}" -f $added)
        Write-Host ("  Marked ~ (changed)     : {0}" -f $changes['~'])
        Write-Host ("  Marked - (removed)     : {0}" -f $changes['-'])
        Write-Host ("  Marked ? (disappeared) : {0}" -f $changes['?'])
        Write-Host ("  Restored to +          : {0}" -f $changes['+'])
        Write-Host ("  Total commits in log   : {0}" -f ($entryCount + $added))
    }

    if ($unreadable -gt 0) {
        Write-Warning "$unreadable line(s) in the log did not match the expected format. They were kept unchanged."
    }
}
finally {
    try { [Console]::OutputEncoding = $previousEncoding } catch { }
}
