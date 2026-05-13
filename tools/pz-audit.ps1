param(
    [string]$ZomboidRoot,
    [string]$WorkshopRoot,
    [string]$InstallRoot,
    [string]$BackupRoot,
    [switch]$IncludeWorkshop,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\PZToolkit.Common.ps1"

if (-not $Json) { Write-PZTTitle "PZ Hosted Toolkit - Audit" "pz-audit" }

$paths = Get-PZTPaths -ZomboidRoot $ZomboidRoot -WorkshopRoot $WorkshopRoot -InstallRoot $InstallRoot -BackupRoot $BackupRoot

$profiles = @()
if (Test-Path -LiteralPath $paths.ServerDir) {
    $profiles = Get-ChildItem -LiteralPath $paths.ServerDir -File -Filter *.ini -Force |
        Sort-Object Name |
        ForEach-Object {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            $mods = @((Read-PZTIniValue -IniPath $_.FullName -Key "Mods") -split ";" | Where-Object { $_ })
            $workshopItems = @((Read-PZTIniValue -IniPath $_.FullName -Key "WorkshopItems") -split ";" | Where-Object { $_ })
            [pscustomobject]@{
                Profile = $name
                Ini = $_.FullName
                ModsCount = $mods.Count
                WorkshopItemsCount = $workshopItems.Count
                Map = Read-PZTIniValue -IniPath $_.FullName -Key "Map"
                PublicName = Read-PZTIniValue -IniPath $_.FullName -Key "PublicName"
                HasIniBom = Test-PZTUtf8Bom -Path $_.FullName
                HasSandboxBom = Test-PZTUtf8Bom -Path (Join-Path $paths.ServerDir "${name}_SandboxVars.lua")
            }
        }
}

$defaultTxt = Join-Path $paths.ClientModsDir "default.txt"
$activeModMatches = @()
if (Test-Path -LiteralPath $defaultTxt) {
    $activeModMatches = @(Select-String -LiteralPath $defaultTxt -Pattern '^\s*mod\s*=' -AllMatches)
}
$clientModsSummary = [pscustomobject]@{
    Path = $defaultTxt
    Exists = Test-Path -LiteralPath $defaultTxt
    ActiveModLines = ($activeModMatches | ForEach-Object { $_.Matches.Count } | Measure-Object -Sum).Sum
    HasBom = if (Test-Path -LiteralPath $defaultTxt) { Test-PZTUtf8Bom -Path $defaultTxt } else { $false }
}

$workshopSummary = $null
if ($IncludeWorkshop -and $paths.WorkshopRoot -and (Test-Path -LiteralPath (Join-Path $paths.WorkshopRoot "content\108600"))) {
    $workshopSummary = Get-ChildItem -LiteralPath (Join-Path $paths.WorkshopRoot "content\108600") -Directory -Force |
        ForEach-Object {
            [pscustomobject]@{
                WorkshopID = $_.Name
                LastWriteTime = $_.LastWriteTime
                Path = $_.FullName
            }
        } |
        Sort-Object WorkshopID
}

$result = [pscustomobject]@{
    Time = Get-Date
    Paths = $paths
    Processes = @(Get-PZTGameProcesses | Select-Object ProcessId, Name, CommandLine)
    Tree = @(
        Get-PZTTreeSummary -Path $paths.ServerDir
        Get-PZTTreeSummary -Path $paths.SavesDir
        Get-PZTTreeSummary -Path $paths.DbDir
        Get-PZTTreeSummary -Path $paths.LogsDir
    )
    ClientMods = $clientModsSummary
    Profiles = @($profiles)
    Workshop = @($workshopSummary)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6
}
else {
    Write-Host "=== PZ Hosted Toolkit Audit ==="
    Write-Host "Time: $($result.Time)"
    Write-Host ""
    Write-Host "=== Paths ==="
    $paths | Format-List
    Write-Host "=== Game/Java processes ==="
    $result.Processes | Format-Table -AutoSize
    Write-Host "=== Tree summary ==="
    $result.Tree | Format-Table -AutoSize
    Write-Host "=== Client global mods ==="
    $result.ClientMods | Format-List
    Write-Host "=== Hosted profiles ==="
    $result.Profiles | Format-Table Profile,ModsCount,WorkshopItemsCount,PublicName,HasIniBom,HasSandboxBom -AutoSize
}
