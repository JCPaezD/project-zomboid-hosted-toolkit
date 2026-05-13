param(
    [string]$WorkshopRoot,
    [string]$ZomboidRoot,
    [string]$BackupRoot,
    [string]$ItemId,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\PZToolkit.Common.ps1"

Write-PZTTitle "PZ Hosted Toolkit - Repair Workshop Redownload" "pz-repair-workshop"

function Get-LatestServerLog {
    param([string]$LogsDir)
    Get-ChildItem -LiteralPath $LogsDir -Filter "*DebugLog-server.txt" -Recurse -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Get-ItemIdFromLog {
    param([string]$LogPath)
    $text = Get-Content -LiteralPath $LogPath -Raw
    $matches = [regex]::Matches($text, "ID=(\d+).*?(Installed\|NeedsUpdate|DownloadPending|result=33)|Installed\|NeedsUpdate.*?ID=(\d+)|onItemNotDownloaded itemID=(\d+) result=33")
    if ($matches.Count -eq 0) {
        return $null
    }
    $match = $matches[$matches.Count - 1]
    foreach ($groupIndex in @(1,3,4)) {
        if ($match.Groups[$groupIndex].Success -and $match.Groups[$groupIndex].Value) {
            return $match.Groups[$groupIndex].Value
        }
    }
    return $null
}

function Get-WorkshopRootCandidates {
    param(
        [Parameter(Mandatory=$true)]$Paths,
        [string]$LogPath,
        [string]$ItemId
    )

    $candidates = New-Object System.Collections.Generic.List[string]
    if ($Paths.WorkshopRoot) { $candidates.Add($Paths.WorkshopRoot) | Out-Null }
    if ($Paths.InstallRoot) {
        $embedded = Join-Path $Paths.InstallRoot "steamapps\workshop"
        if (Test-Path -LiteralPath $embedded) { $candidates.Add($embedded) | Out-Null }
    }
    if ($LogPath -and (Test-Path -LiteralPath $LogPath)) {
        $text = Get-Content -LiteralPath $LogPath -Raw
        $escaped = [regex]::Escape($ItemId)
        $pathMatches = [regex]::Matches($text, "([A-Z]:\\[^\r\n]*?steamapps\\workshop)\\content\\108600\\$escaped", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        foreach ($m in $pathMatches) {
            $path = $m.Groups[1].Value
            if (Test-Path -LiteralPath $path) { $candidates.Add($path) | Out-Null }
        }
    }

    return @($candidates | Select-Object -Unique)
}

function Test-ExclusiveAccess {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $fs.Close()
        return $true
    }
    catch {
        Write-PZTStep "Locked file: $Path" "pz-repair-workshop"
        Write-PZTStep $_.Exception.Message "pz-repair-workshop"
        return $false
    }
}

$paths = Get-PZTPaths -ZomboidRoot $ZomboidRoot -WorkshopRoot $WorkshopRoot -BackupRoot $BackupRoot
if (-not $paths.WorkshopRoot) { throw "Workshop root not found. Pass -WorkshopRoot." }

$latest = $null
if (-not $ItemId) {
    $latest = Get-LatestServerLog -LogsDir $paths.LogsDir
    if (-not $latest) { throw "No server logs found under $($paths.LogsDir)" }
    $ItemId = Get-ItemIdFromLog -LogPath $latest.FullName
    Write-PZTStep "Latest server log: $($latest.FullName)" "pz-repair-workshop"
    if (-not $ItemId) {
        Write-PZTStep "No Installed|NeedsUpdate Workshop item was found." "pz-repair-workshop"
        Write-PZTStep "Nothing to repair with this tool." "pz-repair-workshop"
        Write-PZTStep "Use pz-find-latest-error.ps1 -ServerOnly to inspect other failure patterns." "pz-repair-workshop"
        exit 0
    }
    Write-PZTStep "Detected Workshop ID from log: $ItemId ($($latest.FullName))" "pz-repair-workshop"
}

Assert-PZTNoGameProcesses

$logPath = if ($latest) { $latest.FullName } else { $null }
$rootCandidates = @(Get-WorkshopRootCandidates -Paths $paths -LogPath $logPath -ItemId $ItemId)
$selectedRoot = $null
$selectedContentRoot = $null
$selectedDownloadRoot = $null
foreach ($root in $rootCandidates) {
    $candidateContent = Join-Path (Join-Path $root "content\108600") $ItemId
    $candidateDownload = Join-Path (Join-Path $root "downloads\108600") $ItemId
    if ((Test-Path -LiteralPath $candidateContent) -or (Test-Path -LiteralPath $candidateDownload)) {
        $selectedRoot = $root
        $selectedContentRoot = $candidateContent
        $selectedDownloadRoot = $candidateDownload
        if (Test-Path -LiteralPath $candidateDownload) { break }
    }
}

if (-not $selectedRoot) {
    Write-PZTStep "No installed or prepared download folder was found for Workshop ID $ItemId in known Workshop roots." "pz-repair-workshop"
    Write-PZTStep "This usually means Steam cleaned the staged download, the item is unsubscribed, or the item lives in a different Steam library." "pz-repair-workshop"
    Write-PZTStep "Nothing was changed. Try opening Steam downloads, verify the subscription, or pass -WorkshopRoot if needed." "pz-repair-workshop"
    exit 0
}

$contentBase = Join-Path $selectedRoot "content\108600"
$downloadBase = Join-Path $selectedRoot "downloads\108600"
$contentRoot = $selectedContentRoot
$downloadRoot = $selectedDownloadRoot

if (-not (Test-Path -LiteralPath $contentRoot)) {
    Write-PZTStep "Installed Workshop folder not found: $contentRoot." "pz-repair-workshop"
    Write-PZTStep "Nothing was changed. The item may need to be downloaded by Steam first." "pz-repair-workshop"
    exit 0
}
if (-not (Test-Path -LiteralPath $downloadRoot)) {
    Write-PZTStep "Prepared download folder not found: $downloadRoot." "pz-repair-workshop"
    Write-PZTStep "This repair can only swap a staged download while workshop\downloads\108600\<id> exists." "pz-repair-workshop"
    Write-PZTStep "The installed folder exists and will be checked for locked JARs. If no locks are found, close PZ and retry hosting; Steam/PZ may have already applied or cleaned the download." "pz-repair-workshop"
    $locked = $false
    Get-ChildItem -LiteralPath $contentRoot -Recurse -File -Filter *.jar -ErrorAction SilentlyContinue | ForEach-Object {
        if (-not (Test-ExclusiveAccess -Path $_.FullName)) { $locked = $true }
    }
    if ($locked) {
        Write-PZTStep "At least one JAR is still locked. Close PZ/ZombieBuddy/Java processes and retry." "pz-repair-workshop"
    }
    else {
        Write-PZTStep "No locked JAR was detected in the installed Workshop folder." "pz-repair-workshop"
    }
    exit 0
}

$resolvedBase = (Resolve-Path -LiteralPath $contentBase).Path
$resolvedContent = (Resolve-Path -LiteralPath $contentRoot).Path
if (-not $resolvedContent.StartsWith($resolvedBase, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing unexpected installed path: $resolvedContent"
}

Get-ChildItem -LiteralPath $contentRoot -Recurse -File -Filter *.jar -ErrorAction SilentlyContinue | ForEach-Object {
    if (-not (Test-ExclusiveAccess -Path $_.FullName)) {
        throw "The item is still locked. Close the process using the JAR and retry."
    }
}

$backupName = "workshop-$ItemId-before-redownload-repair"
$backupDir = if ($WhatIf) {
    Join-Path $paths.BackupRoot "$backupName-<timestamp>"
}
else {
    New-PZTBackupDir -BackupRoot $paths.BackupRoot -Name $backupName
}
Write-PZTStep "Installed: $contentRoot" "pz-repair-workshop"
Write-PZTStep "Download:  $downloadRoot" "pz-repair-workshop"
Write-PZTStep "Backup:    $backupDir" "pz-repair-workshop"

if ($WhatIf) {
    Write-PZTStep "WhatIf: no folders will be moved or copied." "pz-repair-workshop"
    exit 0
}

Move-Item -LiteralPath $contentRoot -Destination $backupDir -Force
Copy-Item -LiteralPath $downloadRoot -Destination $contentRoot -Recurse
Write-PZTStep "Repair applied. Relaunch the hosted server." "pz-repair-workshop"
