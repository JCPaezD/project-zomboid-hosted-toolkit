param(
    [Parameter(Mandatory=$true)][string]$SourceProfileName,
    [Parameter(Mandatory=$true)][string]$TargetProfileName,
    [string]$ZomboidRoot,
    [string]$BackupRoot,
    [switch]$IncludePlayerFolder = $true,
    [switch]$IncludeProfileDb = $true,
    [switch]$Overwrite,
    [switch]$ConfirmCopy,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\PZToolkit.Common.ps1"

Write-PZTTitle "PZ Hosted Toolkit - Copy World" "pz-copy-world"
Assert-PZTNoGameProcesses

$paths = Get-PZTPaths -ZomboidRoot $ZomboidRoot -BackupRoot $BackupRoot
Assert-PZTProfilePathsContained -Paths $paths -ProfileName $SourceProfileName
Assert-PZTProfilePathsContained -Paths $paths -ProfileName $TargetProfileName
$sourceSaveName = Get-PZTProfileSaveName -SavesDir $paths.SavesDir -ProfileName $SourceProfileName
$targetSaveName = Convert-PZTProfileNameToSaveName -ProfileName $TargetProfileName
$sourceSaveDir = Join-Path $paths.SavesDir $sourceSaveName
$targetSaveDir = Join-Path $paths.SavesDir $targetSaveName
$sourcePlayerDir = Join-Path $paths.SavesDir "${sourceSaveName}_player"
$targetPlayerDir = Join-Path $paths.SavesDir "${targetSaveName}_player"
$sourceDb = Join-Path $paths.DbDir "$SourceProfileName.db"
$targetDb = Join-Path $paths.DbDir "$TargetProfileName.db"
$targetIni = Join-Path $paths.ServerDir "$TargetProfileName.ini"

if (-not (Test-Path -LiteralPath $sourceSaveDir)) { throw "Source save folder not found: $sourceSaveDir" }
if (-not (Test-Path -LiteralPath $targetIni)) { throw "Target profile INI not found: $targetIni. Create the target hosted profile first." }

$existing = @()
if (Test-Path -LiteralPath $targetSaveDir) { $existing += $targetSaveDir }
if ($IncludePlayerFolder -and (Test-Path -LiteralPath $targetPlayerDir)) { $existing += $targetPlayerDir }
if ($IncludeProfileDb -and (Test-Path -LiteralPath $targetDb)) { $existing += $targetDb }

Write-PZTStep "Source profile: $SourceProfileName ($sourceSaveName)" "pz-copy-world"
Write-PZTStep "Target profile: $TargetProfileName ($targetSaveName)" "pz-copy-world"
Write-PZTStep "Copy includes: save folder, players.db, map files$(if($IncludePlayerFolder){', _player folder'}else{''})$(if($IncludeProfileDb){', profile db'}else{''})" "pz-copy-world"
Write-Host ""
Write-Host "=== Profile identity warning ==="
Write-PZTProfileIdentityWarning "pz-copy-world"
$sourcePlayersDb = Join-Path $sourceSaveDir "players.db"
$targetPlayersDb = Join-Path $targetSaveDir "players.db"
$sourcePlayers = @(Get-PZTPlayersInfo -PlayersDb $sourcePlayersDb)
$targetPlayers = @(Get-PZTPlayersInfo -PlayersDb $targetPlayersDb)
Write-Host ""
Write-Host "=== World/player impact ==="
Write-Host ("Source save: files={0}, sizeMB={1}, lastWrite={2}" -f (Get-PZTTreeSummary -Path $sourceSaveDir).Files, (Get-PZTTreeSummary -Path $sourceSaveDir).SizeMB, (Get-PZTTreeSummary -Path $sourceSaveDir).LastWrite)
if (Test-Path -LiteralPath $targetSaveDir) {
    $targetSummary = Get-PZTTreeSummary -Path $targetSaveDir
    Write-Host ("Target save before copy: files={0}, sizeMB={1}, lastWrite={2}" -f $targetSummary.Files, $targetSummary.SizeMB, $targetSummary.LastWrite)
}
else {
    Write-Host "Target save before copy: missing"
}
Write-Host ("Source players: {0}" -f $sourcePlayers.Count)
if ($sourcePlayers.Count -gt 0) { $sourcePlayers | Select-Object username, playerIndex, name, steamid, isDead, x, y, z | Format-Table -AutoSize }
Write-Host ("Target players before copy: {0}" -f $targetPlayers.Count)
if ($targetPlayers.Count -gt 0) { $targetPlayers | Select-Object username, playerIndex, name, steamid, isDead, x, y, z | Format-Table -AutoSize }
if ($existing.Count -gt 0 -and -not $Overwrite) {
    Write-PZTStep "Target world data already exists. Add -Overwrite after reviewing -WhatIf output." "pz-copy-world"
    exit 1
}
if ($WhatIf) {
    Write-PZTStep "WhatIf: no files will be copied, removed, or rewritten." "pz-copy-world"
    exit 0
}

if (-not $ConfirmCopy) {
    Write-PZTStep "Refusing real world copy without -ConfirmCopy. Run with -WhatIf first, then add -ConfirmCopy when source and target are correct." "pz-copy-world"
    exit 1
}

if ($existing.Count -gt 0) {
    $safety = New-PZTBackupDir -BackupRoot $paths.BackupRoot -Name "$TargetProfileName-world-before-copy"
    New-Item -ItemType Directory -Path (Join-Path $safety "Saves\Multiplayer") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $safety "db") -Force | Out-Null
    Copy-PZTDirectory -Source $targetSaveDir -DestinationParent (Join-Path $safety "Saves\Multiplayer") | Out-Null
    Copy-PZTDirectory -Source $targetPlayerDir -DestinationParent (Join-Path $safety "Saves\Multiplayer") | Out-Null
    Copy-PZTFileIfExists -Path $targetDb -Destination (Join-Path $safety "db") | Out-Null
    Write-PZTStep "Safety backup: $safety" "pz-copy-world"
}

if (Test-Path -LiteralPath $targetSaveDir) { Remove-Item -LiteralPath $targetSaveDir -Recurse -Force }
Copy-Item -LiteralPath $sourceSaveDir -Destination $targetSaveDir -Recurse -Force
if ($IncludePlayerFolder -and (Test-Path -LiteralPath $sourcePlayerDir)) {
    if (Test-Path -LiteralPath $targetPlayerDir) { Remove-Item -LiteralPath $targetPlayerDir -Recurse -Force }
    Copy-Item -LiteralPath $sourcePlayerDir -Destination $targetPlayerDir -Recurse -Force
}
if ($IncludeProfileDb -and (Test-Path -LiteralPath $sourceDb)) {
    Copy-Item -LiteralPath $sourceDb -Destination $targetDb -Force
}

$playersDb = Join-Path $targetSaveDir "players.db"
if (Test-Path -LiteralPath $playersDb) {
    Invoke-PZTPythonJson -InputObject @{ db = $playersDb; source = $sourceSaveName; target = $targetSaveName } -Code @"
import json, sqlite3, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    args = json.load(f)
con = sqlite3.connect(args["db"])
cur = con.cursor()
cur.execute("update networkPlayers set world=? where world=?", (args["target"], args["source"]))
print("Updated players.db world rows:", cur.rowcount)
con.commit()
con.close()
"@
}
Write-PZTStep "World copy complete." "pz-copy-world"
