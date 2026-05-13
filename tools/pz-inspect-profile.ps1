param(
    [string]$ProfileName,
    [string]$ZomboidRoot,
    [string]$WorkshopRoot,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\PZToolkit.Common.ps1"

if (-not $Json) { Write-PZTTitle "PZ Hosted Toolkit - Inspect Profile" "pz-inspect-profile" }

$paths = Get-PZTPaths -ZomboidRoot $ZomboidRoot -WorkshopRoot $WorkshopRoot
$lang = Get-PZTLanguage
if (-not $ProfileName) {
    $ProfileName = Read-PZTMenuChoice -Prompt $(if ($lang -eq "es") { "Elige perfil hosted para inspeccionar" } else { "Choose hosted profile to inspect" }) -Items (Get-PZTHostedProfileNames -ServerDir $paths.ServerDir) -AllowCancel
    if (-not $ProfileName) { exit 0 }
}
Assert-PZTProfilePathsContained -Paths $paths -ProfileName $ProfileName

$ini = Join-Path $paths.ServerDir "$ProfileName.ini"
$sandbox = Join-Path $paths.ServerDir "${ProfileName}_SandboxVars.lua"
$spawnpoints = Join-Path $paths.ServerDir "${ProfileName}_spawnpoints.lua"
$spawnregions = Join-Path $paths.ServerDir "${ProfileName}_spawnregions.lua"
$saveName = Get-PZTProfileSaveName -SavesDir $paths.SavesDir -ProfileName $ProfileName
$saveDir = Join-Path $paths.SavesDir $saveName
$playerDir = Join-Path $paths.SavesDir "${saveName}_player"
$profileDb = Join-Path $paths.DbDir "$ProfileName.db"
$playersDb = Join-Path $saveDir "players.db"

$mods = @()
$workshop = @()
$maps = @()
if (Test-Path -LiteralPath $ini) {
    $mods = @((Read-PZTIniValue -IniPath $ini -Key "Mods") -split ";" | Where-Object { $_ })
    $workshop = @((Read-PZTIniValue -IniPath $ini -Key "WorkshopItems") -split ";" | Where-Object { $_ })
    $maps = @((Read-PZTIniValue -IniPath $ini -Key "Map") -split ";" | Where-Object { $_ })
}

$players = @()
if (Test-Path -LiteralPath $playersDb) {
    $players = @(Get-PZTPlayersInfo -PlayersDb $playersDb)
}

$workshopInstalled = 0
if ($paths.WorkshopRoot) {
    $contentRoot = Join-Path $paths.WorkshopRoot "content\108600"
    foreach ($wid in $workshop) {
        if (Test-Path -LiteralPath (Join-Path $contentRoot $wid)) { $workshopInstalled++ }
    }
}

$result = [pscustomobject]@{
    Profile = $ProfileName
    SaveName = $saveName
    PublicName = if (Test-Path -LiteralPath $ini) { Read-PZTIniValue -IniPath $ini -Key "PublicName" } else { $null }
    Files = [pscustomobject]@{
        Ini = [pscustomobject]@{ Path = $ini; Exists = Test-Path -LiteralPath $ini; HasBom = if (Test-Path -LiteralPath $ini) { Test-PZTUtf8Bom -Path $ini } else { $false } }
        Sandbox = [pscustomobject]@{ Path = $sandbox; Exists = Test-Path -LiteralPath $sandbox; HasBom = if (Test-Path -LiteralPath $sandbox) { Test-PZTUtf8Bom -Path $sandbox } else { $false } }
        Spawnpoints = [pscustomobject]@{ Path = $spawnpoints; Exists = Test-Path -LiteralPath $spawnpoints }
        Spawnregions = [pscustomobject]@{ Path = $spawnregions; Exists = Test-Path -LiteralPath $spawnregions }
    }
    Counts = [pscustomobject]@{
        Mods = $mods.Count
        WorkshopItems = $workshop.Count
        WorkshopInstalled = $workshopInstalled
        Maps = $maps.Count
        Players = @($players).Count
    }
    Save = Get-PZTTreeSummary -Path $saveDir
    PlayerFolder = Get-PZTTreeSummary -Path $playerDir
    ProfileDb = Get-PZTTreeSummary -Path $profileDb
    ModsPreview = @($mods | Select-Object -First 12)
    MapsPreview = @($maps | Select-Object -First 12)
    Players = @($players)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6
    exit 0
}

Write-PZTStep ($(if ($lang -eq "es") { "Perfil: $($result.Profile)" } else { "Profile: $($result.Profile)" })) "pz-inspect-profile"
if ($result.Profile -ne $result.SaveName) { Write-PZTStep ($(if ($lang -eq "es") { "Nombre carpeta save: $($result.SaveName)" } else { "Save folder name: $($result.SaveName)" })) "pz-inspect-profile" }
Write-PZTStep "PublicName: $($result.PublicName)" "pz-inspect-profile"
Write-Host ""
if ($lang -eq "es") { Write-Host "=== Archivos ===" } else { Write-Host "=== Files ===" }
$result.Files.PSObject.Properties | ForEach-Object {
    $v = $_.Value
    $bom = if ($v.PSObject.Properties.Name -contains "HasBom") { ", BOM=$($v.HasBom)" } else { "" }
    Write-Host ("{0,-12} Exists={1}{2}" -f $_.Name, $v.Exists, $bom)
}
Write-Host ""
if ($lang -eq "es") { Write-Host "=== Conteos ===" } else { Write-Host "=== Counts ===" }
Write-Host ("Mods:             {0}" -f $result.Counts.Mods)
Write-Host ("Workshop items:   {0} ({1} installed locally)" -f $result.Counts.WorkshopItems, $result.Counts.WorkshopInstalled)
Write-Host ("Map entries:      {0}" -f $result.Counts.Maps)
Write-Host ("Player rows:      {0}" -f $result.Counts.Players)
Write-Host ""
if ($lang -eq "es") { Write-Host "=== Almacenamiento ===" } else { Write-Host "=== Storage ===" }
Write-Host ("Save:          Exists={0}, Files={1}, SizeMB={2}" -f $result.Save.Exists, $result.Save.Files, $result.Save.SizeMB)
Write-Host ("Player folder: Exists={0}, Files={1}, SizeMB={2}" -f $result.PlayerFolder.Exists, $result.PlayerFolder.Files, $result.PlayerFolder.SizeMB)
Write-Host ("Profile DB:    Exists={0}, Files={1}, SizeMB={2}" -f $result.ProfileDb.Exists, $result.ProfileDb.Files, $result.ProfileDb.SizeMB)

if ($result.ModsPreview.Count -gt 0) {
    Write-Host ""
    if ($lang -eq "es") { Write-Host "=== Vista previa mods ===" } else { Write-Host "=== Mods preview ===" }
    $result.ModsPreview | ForEach-Object { Write-Host ("- {0}" -f $_) }
    if ($result.Counts.Mods -gt $result.ModsPreview.Count) { Write-PZTStep ($(if ($lang -eq "es") { "Mostrando primeros $($result.ModsPreview.Count) mods." } else { "Showing first $($result.ModsPreview.Count) mods." })) "pz-inspect-profile" }
}

if ($result.MapsPreview.Count -gt 0) {
    Write-Host ""
    if ($lang -eq "es") { Write-Host "=== Vista previa mapa ===" } else { Write-Host "=== Map preview ===" }
    $result.MapsPreview | ForEach-Object { Write-Host ("- {0}" -f $_) }
    if ($result.Counts.Maps -gt $result.MapsPreview.Count) { Write-PZTStep ($(if ($lang -eq "es") { "Mostrando primeras $($result.MapsPreview.Count) entradas de mapa." } else { "Showing first $($result.MapsPreview.Count) map entries." })) "pz-inspect-profile" }
}

if (@($players).Count -gt 0) {
    Write-Host ""
    if ($lang -eq "es") { Write-Host "=== Jugadores ===" } else { Write-Host "=== Players ===" }
    $players | Select-Object id, world, username, playerIndex, name, steamid, isDead, x, y, z | Format-Table -AutoSize
    Write-Host ""
    Write-PZTStep ($(if ($lang -eq "es") { "Las coordenadas son coordenadas de mundo. PZ no siempre expone un nombre fiable de mapa/interior en players.db." } else { "Player coordinates are world coordinates. PZ does not always expose a reliable human map/interior name in players.db." })) "pz-inspect-profile"
}
