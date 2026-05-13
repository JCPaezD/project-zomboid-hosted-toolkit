param(
    [Parameter(Mandatory=$true)][string]$BackupPath,
    [string]$TargetProfileName,
    [string]$ZomboidRoot,
    [string]$BackupRoot,
    [switch]$Overwrite,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\PZToolkit.Common.ps1"

Write-PZTTitle "PZ Hosted Toolkit - Restore Profile" "pz-restore-profile"

function Get-SourceProfileName {
    param([Parameter(Mandatory=$true)][string]$BackupPath)

    $manifest = Join-Path $BackupPath "MANIFEST.txt"
    if (Test-Path -LiteralPath $manifest) {
        $line = Get-Content -LiteralPath $manifest | Where-Object { $_ -like "ProfileName:*" } | Select-Object -First 1
        if ($line) { return ($line -replace "^ProfileName:\s*", "").Trim() }
    }

    $serverDir = Join-Path $BackupPath "Server"
    $ini = Get-ChildItem -LiteralPath $serverDir -File -Filter *.ini -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ini) { return [System.IO.Path]::GetFileNameWithoutExtension($ini.Name) }

    throw "Could not determine source profile name from backup: $BackupPath"
}

function Get-SourceSaveName {
    param(
        [Parameter(Mandatory=$true)][string]$BackupPath,
        [Parameter(Mandatory=$true)][string]$SourceProfileName
    )

    $manifest = Join-Path $BackupPath "MANIFEST.txt"
    if (Test-Path -LiteralPath $manifest) {
        $line = Get-Content -LiteralPath $manifest | Where-Object { $_ -like "SaveName:*" } | Select-Object -First 1
        if ($line) { return ($line -replace "^SaveName:\s*", "").Trim() }
    }

    $savesDir = Join-Path $BackupPath "Saves\Multiplayer"
    if (Test-Path -LiteralPath (Join-Path $savesDir $SourceProfileName)) { return $SourceProfileName }
    $normalized = Convert-PZTProfileNameToSaveName -ProfileName $SourceProfileName
    if (Test-Path -LiteralPath (Join-Path $savesDir $normalized)) { return $normalized }
    return $SourceProfileName
}

function Update-IniPublicName {
    param(
        [Parameter(Mandatory=$true)][string]$IniPath,
        [Parameter(Mandatory=$true)][string]$SourceProfileName,
        [Parameter(Mandatory=$true)][string]$TargetProfileName
    )
    if ($SourceProfileName -eq $TargetProfileName) { return }
    if (-not (Test-Path -LiteralPath $IniPath)) { return }

    $lines = Get-Content -LiteralPath $IniPath
    $changed = $false
    $updated = foreach ($line in $lines) {
        if ($line -like "PublicName=*") {
            $value = $line -replace "^PublicName=", ""
            if ($value -eq $SourceProfileName) {
                $changed = $true
                "PublicName=$TargetProfileName"
                continue
            }
        }
        $line
    }

    if ($changed) {
        Set-PZTTextNoBom -Path $IniPath -Content ($updated -join [Environment]::NewLine)
        Write-PZTStep "Updated PublicName from '$SourceProfileName' to '$TargetProfileName'." "pz-restore-profile"
    }
}

function Copy-DirectoryReplacing {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination
    )
    if (-not (Test-Path -LiteralPath $Source)) { return }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
}

function Copy-FileReplacing {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination
    )
    if (-not (Test-Path -LiteralPath $Source)) { return }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Force }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Update-PlayersWorldName {
    param(
        [Parameter(Mandatory=$true)][string]$PlayersDb,
        [Parameter(Mandatory=$true)][string]$SourceProfileName,
        [Parameter(Mandatory=$true)][string]$TargetProfileName
    )
    if ($SourceProfileName -eq $TargetProfileName) { return }
    if (-not (Test-Path -LiteralPath $PlayersDb)) { return }

    $dbLiteral = $PlayersDb.Replace("\", "\\").Replace("'", "''")
    $sourceLiteral = $SourceProfileName.Replace("\", "\\").Replace("'", "''")
    $targetLiteral = $TargetProfileName.Replace("\", "\\").Replace("'", "''")
    $code = @"
import sqlite3

db = r'$dbLiteral'
source = r'$sourceLiteral'
target = r'$targetLiteral'

con = sqlite3.connect(db)
cur = con.cursor()
cur.execute("update networkPlayers set world=? where world=?", (target, source))
print("Updated players.db world rows:", cur.rowcount)
con.commit()
con.close()
"@
    Invoke-PZTPython -Code $code
}

Assert-PZTNoGameProcesses

if (-not (Test-Path -LiteralPath $BackupPath)) {
    Write-PZTStep "Backup folder not found: $BackupPath" "pz-restore-profile"
    Write-PZTStep "Choose a folder created by pz-backup-profile, such as backups\profile-MyHostedServer-20260101-120000." "pz-restore-profile"
    exit 1
}
$resolvedBackup = (Resolve-Path -LiteralPath $BackupPath).Path
$paths = Get-PZTPaths -ZomboidRoot $ZomboidRoot -BackupRoot $BackupRoot
$sourceProfile = Get-SourceProfileName -BackupPath $resolvedBackup
$sourceSaveName = Get-SourceSaveName -BackupPath $resolvedBackup -SourceProfileName $sourceProfile
if (-not $TargetProfileName) { $TargetProfileName = $sourceProfile }
$targetSaveName = Convert-PZTProfileNameToSaveName -ProfileName $TargetProfileName

$backupServerDir = Join-Path $resolvedBackup "Server"
$backupSavesDir = Join-Path $resolvedBackup "Saves\Multiplayer"
$backupDbDir = Join-Path $resolvedBackup "db"

$targetFiles = Get-PZTProfileFilePaths -ServerDir $paths.ServerDir -ProfileName $TargetProfileName
$targetSaveDir = Join-Path $paths.SavesDir $targetSaveName
$targetPlayerDir = Join-Path $paths.SavesDir "${targetSaveName}_player"
$targetDb = Join-Path $paths.DbDir "$TargetProfileName.db"

$existingTargets = @()
$existingTargets += @($targetFiles | Where-Object { Test-Path -LiteralPath $_ })
if (Test-Path -LiteralPath $targetSaveDir) { $existingTargets += $targetSaveDir }
if (Test-Path -LiteralPath $targetPlayerDir) { $existingTargets += $targetPlayerDir }
if (Test-Path -LiteralPath $targetDb) { $existingTargets += $targetDb }

Write-PZTStep "Backup: $resolvedBackup" "pz-restore-profile"
Write-PZTStep "Source profile: $sourceProfile" "pz-restore-profile"
if ($sourceProfile -ne $sourceSaveName) { Write-PZTStep "Source save name: $sourceSaveName" "pz-restore-profile" }
Write-PZTStep "Target profile: $TargetProfileName" "pz-restore-profile"
if ($TargetProfileName -ne $targetSaveName) { Write-PZTStep "Target save name: $targetSaveName" "pz-restore-profile" }
if ($existingTargets.Count -gt 0) {
    Write-PZTStep "Existing target paths: $($existingTargets.Count)" "pz-restore-profile"
    if (-not $Overwrite) {
        Write-PZTStep "Refusing to overwrite existing target. Add -Overwrite after reviewing -WhatIf output." "pz-restore-profile"
        exit 1
    }
}

if ($WhatIf) {
    Write-PZTStep "WhatIf: no files will be copied, removed, or rewritten." "pz-restore-profile"
    Write-PZTStep "Would restore/copy Server files, save folder, optional _player folder, and optional db file." "pz-restore-profile"
    if ($sourceProfile -ne $TargetProfileName) {
        Write-PZTStep "Would rename restored files/folders and update players.db world rows from '$sourceSaveName' to '$targetSaveName'." "pz-restore-profile"
    }
    exit 0
}

if ($existingTargets.Count -gt 0) {
    $safety = New-PZTBackupDir -BackupRoot $paths.BackupRoot -Name "$TargetProfileName-before-restore"
    New-Item -ItemType Directory -Path (Join-Path $safety "Server") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $safety "Saves\Multiplayer") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $safety "db") -Force | Out-Null
    foreach ($file in $targetFiles) {
        Copy-PZTFileIfExists -Path $file -Destination (Join-Path $safety "Server") | Out-Null
    }
    Copy-PZTDirectory -Source $targetSaveDir -DestinationParent (Join-Path $safety "Saves\Multiplayer") | Out-Null
    Copy-PZTDirectory -Source $targetPlayerDir -DestinationParent (Join-Path $safety "Saves\Multiplayer") | Out-Null
    Copy-PZTFileIfExists -Path $targetDb -Destination (Join-Path $safety "db") | Out-Null
    Write-PZTStep "Safety backup of existing target: $safety" "pz-restore-profile"
}

foreach ($sourceFile in Get-PZTProfileFilePaths -ServerDir $backupServerDir -ProfileName $sourceProfile) {
    if (-not (Test-Path -LiteralPath $sourceFile)) { continue }
    $leaf = Split-Path -Leaf $sourceFile
    $targetLeaf = if ($sourceProfile -eq $TargetProfileName) {
        $leaf
    }
    else {
        $leaf -replace ("^" + [regex]::Escape($sourceProfile)), $TargetProfileName
    }
    Copy-FileReplacing -Source $sourceFile -Destination (Join-Path $paths.ServerDir $targetLeaf)
}

Update-IniPublicName -IniPath (Join-Path $paths.ServerDir "$TargetProfileName.ini") -SourceProfileName $sourceProfile -TargetProfileName $TargetProfileName

Copy-DirectoryReplacing -Source (Join-Path $backupSavesDir $sourceSaveName) -Destination $targetSaveDir
Copy-DirectoryReplacing -Source (Join-Path $backupSavesDir "${sourceSaveName}_player") -Destination $targetPlayerDir
Copy-FileReplacing -Source (Join-Path $backupDbDir "$sourceProfile.db") -Destination $targetDb

Update-PlayersWorldName -PlayersDb (Join-Path $targetSaveDir "players.db") -SourceProfileName $sourceSaveName -TargetProfileName $targetSaveName

Write-PZTStep "Restore/copy complete." "pz-restore-profile"
