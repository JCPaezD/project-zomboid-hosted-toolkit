param(
    [Parameter(Mandatory=$true)][string]$SourceProfileName,
    [Parameter(Mandatory=$true)][string]$TargetProfileName,
    [string]$ZomboidRoot,
    [string]$BackupRoot,
    [switch]$IncludePlayerFolder = $true,
    [switch]$Overwrite,
    [switch]$ConfirmCopy,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\PZToolkit.Common.ps1"

Write-PZTTitle "PZ Hosted Toolkit - Copy Players" "pz-copy-players"
Assert-PZTNoGameProcesses

$paths = Get-PZTPaths -ZomboidRoot $ZomboidRoot -BackupRoot $BackupRoot
Assert-PZTProfilePathsContained -Paths $paths -ProfileName $SourceProfileName
Assert-PZTProfilePathsContained -Paths $paths -ProfileName $TargetProfileName
$sourceSaveName = Get-PZTProfileSaveName -SavesDir $paths.SavesDir -ProfileName $SourceProfileName
$targetSaveName = Get-PZTProfileSaveName -SavesDir $paths.SavesDir -ProfileName $TargetProfileName
$sourceSaveDir = Join-Path $paths.SavesDir $sourceSaveName
$targetSaveDir = Join-Path $paths.SavesDir $targetSaveName
$sourcePlayersDb = Join-Path $sourceSaveDir "players.db"
$targetPlayersDb = Join-Path $targetSaveDir "players.db"
$sourcePlayerDir = Join-Path $paths.SavesDir "${sourceSaveName}_player"
$targetPlayerDir = Join-Path $paths.SavesDir "${targetSaveName}_player"

if (-not (Test-Path -LiteralPath $sourcePlayersDb)) { throw "Source players.db not found: $sourcePlayersDb" }
if (-not (Test-Path -LiteralPath $targetSaveDir)) { throw "Target save folder not found: $targetSaveDir" }

$lang = Get-PZTLanguage
if ($lang -eq "es") {
    Write-PZTStep "Perfil origen: $SourceProfileName ($sourceSaveName)" "pz-copy-players"
    Write-PZTStep "Perfil destino: $TargetProfileName ($targetSaveName)" "pz-copy-players"
}
else {
    Write-PZTStep "Source profile: $SourceProfileName ($sourceSaveName)" "pz-copy-players"
    Write-PZTStep "Target profile: $TargetProfileName ($targetSaveName)" "pz-copy-players"
}
$sourcePlayers = @(Get-PZTPlayersInfo -PlayersDb $sourcePlayersDb)
$targetPlayers = @(Get-PZTPlayersInfo -PlayersDb $targetPlayersDb)
Write-Host ""
if ($lang -eq "es") { Write-Host "=== Impacto en jugadores ===" } else { Write-Host "=== Player impact ===" }
Write-Host ($(if ($lang -eq "es") { "Jugadores origen: {0}" } else { "Source players: {0}" }) -f $sourcePlayers.Count)
if ($sourcePlayers.Count -gt 0) { $sourcePlayers | Select-Object username, playerIndex, name, steamid, isDead, x, y, z | Format-Table -AutoSize }
Write-Host ($(if ($lang -eq "es") { "Jugadores destino antes de copiar: {0}" } else { "Target players before copy: {0}" }) -f $targetPlayers.Count)
if ($targetPlayers.Count -gt 0) { $targetPlayers | Select-Object username, playerIndex, name, steamid, isDead, x, y, z | Format-Table -AutoSize }
if (Test-Path -LiteralPath $targetPlayersDb) {
    Write-Host ($(if ($lang -eq "es") { "Fecha players.db destino: {0}" } else { "Target players.db LastWriteTime: {0}" }) -f (Get-Item -LiteralPath $targetPlayersDb).LastWriteTime)
}
if ($WhatIf) {
    if ($lang -eq "es") { Write-PZTStep "WhatIf: no se copiara players.db ni carpeta _player." "pz-copy-players" }
    else { Write-PZTStep "WhatIf: no player database or _player folder will be copied." "pz-copy-players" }
    exit 0
}
if (-not $ConfirmCopy) {
    Write-PZTStep "Refusing real player copy without -ConfirmCopy. Run with -WhatIf first, then add -ConfirmCopy when source and target are correct." "pz-copy-players"
    exit 1
}
if ((Test-Path -LiteralPath $targetPlayersDb) -and -not $Overwrite) {
    if ($lang -eq "es") {
        Write-PZTStep "El destino ya tiene players.db. Anade -Overwrite despues de revisar la salida -WhatIf." "pz-copy-players"
    }
    else {
        Write-PZTStep "Target players.db already exists. Add -Overwrite after reviewing -WhatIf output." "pz-copy-players"
    }
    exit 1
}

$safety = New-PZTBackupDir -BackupRoot $paths.BackupRoot -Name "$TargetProfileName-players-before-copy"
New-Item -ItemType Directory -Path $safety -Force | Out-Null
Copy-PZTFileIfExists -Path $targetPlayersDb -Destination $safety | Out-Null
Copy-PZTDirectory -Source $targetPlayerDir -DestinationParent $safety | Out-Null
Write-PZTStep "Safety backup: $safety" "pz-copy-players"

Copy-Item -LiteralPath $sourcePlayersDb -Destination $targetPlayersDb -Force
if ($IncludePlayerFolder -and (Test-Path -LiteralPath $sourcePlayerDir)) {
    if (Test-Path -LiteralPath $targetPlayerDir) { Remove-Item -LiteralPath $targetPlayerDir -Recurse -Force }
    Copy-Item -LiteralPath $sourcePlayerDir -Destination $targetPlayerDir -Recurse -Force
}

Invoke-PZTPythonJson -InputObject @{ db = $targetPlayersDb; source = $sourceSaveName; target = $targetSaveName } -Code @"
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
if ($lang -eq "es") { Write-PZTStep "Copia de jugadores completada." "pz-copy-players" }
else { Write-PZTStep "Player copy complete." "pz-copy-players" }
