param(
    [Parameter(Mandatory=$true)][string]$ProfileName,
    [string]$ZomboidRoot,
    [string]$WorkshopRoot,
    [string]$OutputDir
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\PZToolkit.Common.ps1"

Write-PZTTitle "PZ Hosted Toolkit - Export Profile" "pz-export-profile"

$paths = Get-PZTPaths -ZomboidRoot $ZomboidRoot -WorkshopRoot $WorkshopRoot
Assert-PZTProfilePathsContained -Paths $paths -ProfileName $ProfileName
$lang = Get-PZTLanguage
$ini = Join-Path $paths.ServerDir "$ProfileName.ini"
if (-not (Test-Path -LiteralPath $ini)) { throw "Profile INI not found: $ini" }

function Resolve-PZTExportDirectory {
    param(
        [Parameter(Mandatory=$true)][string]$ProfileName,
        [string]$RequestedOutputDir
    )

    $toolkitRoot = Split-Path -Parent $PSScriptRoot
    $exportsRoot = Join-Path $toolkitRoot "exports"

    if (-not $RequestedOutputDir) {
        return (Join-Path $exportsRoot $ProfileName)
    }

    $hasSeparator = ($RequestedOutputDir -match '[\\/]')
    if ([System.IO.Path]::IsPathRooted($RequestedOutputDir) -or $hasSeparator) {
        return $RequestedOutputDir
    }

    return (Join-Path $exportsRoot $RequestedOutputDir)
}

$OutputDir = Resolve-PZTExportDirectory -ProfileName $ProfileName -RequestedOutputDir $OutputDir
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$mods = (Read-PZTIniValue -IniPath $ini -Key "Mods") -split ";" | Where-Object { $_ }
$workshop = (Read-PZTIniValue -IniPath $ini -Key "WorkshopItems") -split ";" | Where-Object { $_ }
$map = (Read-PZTIniValue -IniPath $ini -Key "Map") -split ";" | Where-Object { $_ }
$saveName = Get-PZTProfileSaveName -SavesDir $paths.SavesDir -ProfileName $ProfileName
$saveDir = Join-Path $paths.SavesDir $saveName
$playersDb = Join-Path $saveDir "players.db"
$sandbox = Join-Path $paths.ServerDir "${ProfileName}_SandboxVars.lua"

Set-PZTTextNoBom -Path (Join-Path $OutputDir "$ProfileName-mods.txt") -Content ($mods -join ";")
Set-PZTTextNoBom -Path (Join-Path $OutputDir "$ProfileName-workshopitems.txt") -Content ($workshop -join ";")
Set-PZTTextNoBom -Path (Join-Path $OutputDir "$ProfileName-map.txt") -Content ($map -join ";")

$serverSettings = Get-Content -LiteralPath $ini | Where-Object {
    $_ -match '^(PublicName|Mods|WorkshopItems|Map|PauseEmpty|Public|Open|ServerPlayerID|MaxPlayers|PVP|SafetySystem|SpawnPoint|SaveWorldEveryMinutes)='
}
Set-PZTTextNoBom -Path (Join-Path $OutputDir "$ProfileName-server-settings.txt") -Content ($serverSettings -join [Environment]::NewLine)

if (Test-Path -LiteralPath $sandbox) {
    # Raw copy of the profile SandboxVars file. Text inside comes from PZ/mods.
    Copy-Item -LiteralPath $sandbox -Destination (Join-Path $OutputDir "$ProfileName-SandboxVars.lua") -Force
}

$players = @(Get-PZTPlayersInfo -PlayersDb $playersDb)
if ($players.Count -gt 0) {
    $players | Export-Csv -LiteralPath (Join-Path $OutputDir "$ProfileName-players.csv") -NoTypeInformation -Encoding UTF8
}

$csv = Join-Path $OutputDir "$ProfileName-workshop-checklist.csv"
$rows = New-Object System.Collections.Generic.List[object]
$contentRoot = if ($paths.WorkshopRoot) { Join-Path $paths.WorkshopRoot "content\108600" } else { $null }

for ($i = 0; $i -lt $workshop.Count; $i++) {
    $wid = $workshop[$i]
    $localNames = @()
    $localModIds = @()
    if ($contentRoot) {
        $itemRoot = Join-Path $contentRoot $wid
        if (Test-Path -LiteralPath $itemRoot) {
            Get-ChildItem -LiteralPath $itemRoot -Filter mod.info -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                $content = Get-Content -LiteralPath $_.FullName -ErrorAction SilentlyContinue
                $name = (($content | Where-Object { $_ -match '^name=' } | Select-Object -First 1) -replace '^name=', '')
                $id = (($content | Where-Object { $_ -match '^id=' } | Select-Object -First 1) -replace '^id=', '')
                if ($name) { $localNames += $name }
                if ($id) { $localModIds += $id }
            }
        }
    }
    $rows.Add([pscustomobject]@{
        order = $i + 1
        workshop_id = $wid
        url = "https://steamcommunity.com/sharedfiles/filedetails/?id=$wid"
        local_names = (($localNames | Select-Object -Unique) -join " | ")
        local_modids = (($localModIds | Select-Object -Unique) -join ";")
    })
}

$rows | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8

$summary = @(
    "# $ProfileName export"
    ""
    "ModsCount: $($mods.Count)"
    "WorkshopItemsCount: $($workshop.Count)"
    "MapCount: $($map.Count)"
    "PlayersCount: $($players.Count)"
    "SaveName: $saveName"
    "OutputDir: $OutputDir"
    "SandboxVarsExport: raw copy from $sandbox"
    ""
    "Generated: $(Get-Date -Format o)"
    ""
    "Files:"
    "- $ProfileName-mods.txt"
    "- $ProfileName-workshopitems.txt"
    "- $ProfileName-map.txt"
    "- $ProfileName-workshop-checklist.csv"
    "- $ProfileName-server-settings.txt"
    "- $ProfileName-SandboxVars.lua (when present)"
    "- $ProfileName-players.csv (when players.db is readable)"
)
Set-PZTTextNoBom -Path (Join-Path $OutputDir "$ProfileName-summary.md") -Content ($summary -join [Environment]::NewLine)

Write-PZTStep ($(if ($lang -eq "es") { "Export completado: $OutputDir" } else { "Export complete: $OutputDir" })) "pz-export-profile"
