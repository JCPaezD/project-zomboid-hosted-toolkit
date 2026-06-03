param(
    [string]$ProfileName,
    [string]$ZomboidRoot,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\PZToolkit.Common.ps1"

if (-not $Json) { Write-PZTTitle "PZ Hosted Toolkit - Quick Diagnosis" "pz-quick-diagnosis" }

$paths = Get-PZTPaths -ZomboidRoot $ZomboidRoot
$profiles = @(Get-PZTHostedProfileNames -ServerDir $paths.ServerDir)
if ($ProfileName) {
    Assert-PZTProfilePathsContained -Paths $paths -ProfileName $ProfileName
    $profilesToCheck = @($ProfileName)
}
else {
    $profilesToCheck = @($profiles)
}

$clientDefault = Join-Path $paths.ClientModsDir "default.txt"
$activeClientMods = 0
if (Test-Path -LiteralPath $clientDefault) {
    $activeClientMods = @((Select-String -LiteralPath $clientDefault -Pattern '^\s*mod\s*=' -AllMatches -ErrorAction SilentlyContinue) | ForEach-Object { $_.Matches }).Count
}

$logItems = @()
$latestDebug = $null
$latestDebugText = ""
if (Test-Path -LiteralPath $paths.LogsDir) {
    $latestDebug = Get-ChildItem -LiteralPath $paths.LogsDir -Filter "*DebugLog-server.txt" -Recurse -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($latestDebug) {
        $latestDebugText = Get-Content -LiteralPath $latestDebug.FullName -Raw
        $knownPatterns = "ERROR|Exception|UI_ServerStatus_Terminated|Installed\|NeedsUpdate|Installed status but timeUpdated|DownloadPending|onItemNotDownloaded|onItemNotSubscribed|SubscribePending\s+->\s+Fail|GetItemState\(\)=None|CRC mismatch|SANITY CHECK FAIL|Error loading chunk|WorldStreamer|requestLargeAreaZip|Received\s+\d+\s*/\s*\d+\s+chunks|map download|OutOfMemoryError|ReceiveModData|ObjectModDataPacket|MalformedInputException|FileSystemException|being used by another process|está siendo utilizado por otro proceso|El proceso no tiene acceso al archivo"
        $logItems = @(Select-String -LiteralPath $latestDebug.FullName -Pattern $knownPatterns -ErrorAction SilentlyContinue | Select-Object -Last 8)
    }
}

$health = @()
foreach ($profile in $profilesToCheck) {
    if ($profile) { $health += @(Get-PZTProfileHealth -Paths $paths -ProfileName $profile) }
}

$blamFiles = @()
if (Test-Path -LiteralPath $paths.SavesDir) {
    $saveNamesToCheck = @($profilesToCheck | ForEach-Object {
        if ($_) { Get-PZTProfileSaveName -SavesDir $paths.SavesDir -ProfileName $_ }
    })
    $blamFiles = @(Get-ChildItem -LiteralPath $paths.SavesDir -Filter "*_error.txt" -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "\\blam\\" } |
        Where-Object {
            if ($saveNamesToCheck.Count -eq 0) { $true }
            else {
                $insideCheckedSave = $false
                foreach ($saveName in $saveNamesToCheck) {
                    $saveRoot = (Join-Path $paths.SavesDir $saveName).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
                    $saveRootWithSeparator = $saveRoot + [System.IO.Path]::DirectorySeparatorChar
                    if ($_.FullName.StartsWith($saveRootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $insideCheckedSave = $true
                        break
                    }
                }
                $insideCheckedSave
            }
        } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 10)
}

$findings = New-Object System.Collections.Generic.List[object]
function Add-PZTDiagFinding {
    param([string]$Status, [string]$Area, [string]$Message)
    $findings.Add([pscustomobject]@{ Status = $Status; Area = $Area; Message = $Message }) | Out-Null
}

function Get-PZTLatestWorkshopIdFromText {
    param([string]$Text)
    if (-not $Text) { return $null }

    $matches = [regex]::Matches($Text, "(?:ID=|itemID=)(\d+)")
    if ($matches.Count -eq 0) { return $null }

    return $matches[$matches.Count - 1].Groups[1].Value
}

function Get-PZTLatestWorkshopUpdateIssueFromText {
    param([string]$Text)
    if (-not $Text) { return $null }

    $matches = [regex]::Matches($Text, "ID=(\d+).*?(Installed\|NeedsUpdate|DownloadPending|result=33)|Installed\|NeedsUpdate.*?ID=(\d+)|onItemNotDownloaded itemID=(\d+) result=33")
    if ($matches.Count -eq 0) { return $null }

    $match = $matches[$matches.Count - 1]
    $id = $null
    foreach ($groupIndex in @(1,3,4)) {
        if ($match.Groups[$groupIndex].Success -and $match.Groups[$groupIndex].Value) {
            $id = $match.Groups[$groupIndex].Value
            break
        }
    }
    if (-not $id) { return $null }

    [pscustomobject]@{
        WorkshopId = $id
        Index = $match.Index
    }
}

function Get-PZTWorkshopRootsForDiagnosis {
    param($Paths)

    $roots = New-Object System.Collections.Generic.List[string]
    if ($Paths.WorkshopRoot) { $roots.Add($Paths.WorkshopRoot) | Out-Null }
    if ($Paths.InstallRoot) {
        $embedded = Join-Path $Paths.InstallRoot "steamapps\workshop"
        if (Test-Path -LiteralPath $embedded) { $roots.Add($embedded) | Out-Null }
    }

    return @($roots.ToArray() | Select-Object -Unique)
}

function Test-PZTWorkshopDownloadFolder {
    param(
        [string]$WorkshopId,
        $Paths
    )
    if (-not $WorkshopId) { return $false }

    foreach ($root in @(Get-PZTWorkshopRootsForDiagnosis -Paths $Paths)) {
        $candidate = Join-Path $root "downloads\108600\$WorkshopId"
        if (Test-Path -LiteralPath $candidate) { return $true }
    }

    return $false
}

if (-not (Test-Path -LiteralPath $paths.ZomboidRoot)) {
    Add-PZTDiagFinding "Needs attention" "Paths" "Zomboid root was not found: $($paths.ZomboidRoot)"
}
elseif ($profiles.Count -eq 0) {
    Add-PZTDiagFinding "Warning" "Profiles" "No hosted profiles were found under Server."
}
else {
    Add-PZTDiagFinding "OK" "Profiles" "$($profiles.Count) hosted profile(s) found."
}

if ($activeClientMods -gt 0) {
    Add-PZTDiagFinding "Warning" "Client global mods" "$activeClientMods active mod line(s) found in mods/default.txt. This can block hosted-server Workshop updates; clear it before hosting modded servers."
}
else {
    Add-PZTDiagFinding "OK" "Client global mods" "No active client global mod lines found."
}

$processes = @(Get-PZTGameProcesses)
if ($processes.Count -gt 0) {
    Add-PZTDiagFinding "Warning" "Processes" "$($processes.Count) PZ/ZombieBuddy/Java-related process(es) are running. Close the game before write-capable operations."
}
else {
    Add-PZTDiagFinding "OK" "Processes" "No PZ/ZombieBuddy/Java-related process detected."
}

$badHealth = @($health | Where-Object { $_.Status -ne "OK" })
if ($badHealth.Count -gt 0) {
    Add-PZTDiagFinding "Warning" "Profile health" "$($badHealth.Count) checked profile(s) have warnings or errors."
}
elseif ($health.Count -gt 0) {
    Add-PZTDiagFinding "OK" "Profile health" "$($health.Count) checked profile(s) look consistent."
}

if ($blamFiles.Count -gt 0) {
    Add-PZTDiagFinding "Warning" "Problem chunks" "$($blamFiles.Count) recent blam error file(s) found. Use inspect-blam before attempting any save repair."
}
else {
    Add-PZTDiagFinding "OK" "Problem chunks" "No blam error files found in Saves/Multiplayer."
}

$hasMapChunkDownloadSignal = $false
if ($latestDebugText) {
    $hasMapChunkDownloadSignal = $latestDebugText -match "WorldStreamer|requestLargeAreaZip|Received\s+\d+\s*/\s*\d+\s+chunks|map download|download.*map|chunk.*download|CRC mismatch|SANITY CHECK FAIL|Error loading chunk"
}
if (-not $hasMapChunkDownloadSignal -and $blamFiles.Count -gt 0) {
    $hasMapChunkDownloadSignal = $true
}

if ($hasMapChunkDownloadSignal) {
    $profilesWithCache = New-Object System.Collections.Generic.List[string]
    foreach ($profile in $profilesToCheck) {
        if (-not $profile) { continue }
        $saveName = Get-PZTProfileSaveName -SavesDir $paths.SavesDir -ProfileName $profile
        $cacheDir = Join-Path $paths.SavesDir "${saveName}_player"
        if (Test-Path -LiteralPath $cacheDir) {
            $profilesWithCache.Add($profile) | Out-Null
        }
    }
    if ($profilesWithCache.Count -gt 0) {
        Add-PZTDiagFinding "Warning" "Hosted client cache" "Map/chunk download or problem-chunk signals were found. If the server save was just restored and hosting still hangs while loading/downloading map chunks, run reset-client-cache -WhatIf for the affected profile."
    }
}

$latestWorkshopUpdateIssue = Get-PZTLatestWorkshopUpdateIssueFromText -Text $latestDebugText
$latestWorkshopId = if ($latestWorkshopUpdateIssue) { $latestWorkshopUpdateIssue.WorkshopId } else { $null }
$subscriptionFailure = Get-PZTWorkshopSubscriptionFailure -Text $latestDebugText
$hasWorkshopUpdateSignal = $false
$hasLockedWorkshopSignal = $false
$hasStagedDownload = $false
if ($latestDebugText) {
    $hasWorkshopUpdateSignal = $latestDebugText -match "Installed status but timeUpdated|Installed\|NeedsUpdate|DownloadPending|onItemNotDownloaded.*result=33"
    $hasLockedWorkshopSignal = $latestDebugText -match "FileSystemException|being used by another process|está siendo utilizado por otro proceso|El proceso no tiene acceso al archivo|AccessDeniedException"
    $hasStagedDownload = Test-PZTWorkshopDownloadFolder -WorkshopId $latestWorkshopId -Paths $paths
}

if ($hasWorkshopUpdateSignal -and $hasLockedWorkshopSignal) {
    $idText = if ($latestWorkshopId) { " Workshop ID $latestWorkshopId." } else { "" }
    $downloadText = if ($hasStagedDownload) { " A staged download folder exists, so repair-workshop may be able to swap it after PZ/ZombieBuddy/Java are closed." } else { " No staged download folder is present; close PZ/ZombieBuddy/Java, wait for Steam to finish, then retry hosting before using repair-workshop." }
    Add-PZTDiagFinding "Warning" "Workshop update lock" "The latest server log shows a Workshop update blocked by a locked file/JAR.$idText$downloadText"
}
elseif ($hasWorkshopUpdateSignal) {
    $idText = if ($latestWorkshopId) { " Last Workshop ID seen: $latestWorkshopId." } else { "" }
    Add-PZTDiagFinding "Warning" "Workshop update/cache" "The latest server log shows Workshop update/cache signals.$idText Use latest-error, then repair-workshop only if a staged download folder exists."
}

if ($subscriptionFailure) {
    $codeText = if ($subscriptionFailure.ResultCode) { " Steam/PZ result code $($subscriptionFailure.ResultCode)." } else { "" }
    Add-PZTDiagFinding "Warning" "Workshop subscription failure" "A client failed to subscribe/access Workshop ID $($subscriptionFailure.WorkshopId).$codeText Check $($subscriptionFailure.Url). If the item is removed/private/unavailable, remove or replace it in the hosted profile after backup; repair-workshop does not apply."
}

if ($logItems.Count -gt 0) {
    Add-PZTDiagFinding "Warning" "Latest server log" "$($logItems.Count) relevant recent line(s) found. Run latest-error for classified details."
}
else {
    Add-PZTDiagFinding "OK" "Latest server log" "No known high-level error patterns found in the latest server log."
}

$overall = "OK"
if (@($findings | Where-Object { $_.Status -eq "Warning" }).Count -gt 0) { $overall = "Warning" }
if (@($findings | Where-Object { $_.Status -eq "Needs attention" }).Count -gt 0) { $overall = "Needs attention" }

$result = [pscustomobject]@{
    Time = (Get-Date)
    Overall = $overall
    Paths = $paths
    ProfileFilter = $ProfileName
    Findings = @($findings.ToArray())
    ProfileHealth = @($health)
    RecentBlamErrors = @($blamFiles | Select-Object FullName, LastWriteTime, Length)
    LatestLogMatches = @($logItems | Select-Object Path, LineNumber, Line)
    LatestWorkshopIssue = [pscustomobject]@{
        WorkshopId = $latestWorkshopId
        UpdateSignal = $hasWorkshopUpdateSignal
        LockedFileSignal = $hasLockedWorkshopSignal
        StagedDownloadFolder = $hasStagedDownload
        LogPath = if ($latestDebug) { $latestDebug.FullName } else { $null }
    }
    LatestWorkshopSubscriptionFailure = $subscriptionFailure
    MapChunkDownloadSignal = $hasMapChunkDownloadSignal
}

if ($Json) {
    $result | ConvertTo-Json -Depth 7
    exit 0
}

Write-PZTStep "Overall: $overall" "pz-quick-diagnosis"
Write-Host ""
$lang = Get-PZTLanguage
if ($lang -eq "es") { Write-Host "=== Hallazgos ===" } else { Write-Host "=== Findings ===" }
Write-Host (($result.Findings | Format-Table Status, Area, Message -AutoSize -Wrap | Out-String).TrimEnd())

if ($badHealth.Count -gt 0) {
    Write-Host ""
    if ($lang -eq "es") { Write-Host "=== Problemas de salud del perfil ===" } else { Write-Host "=== Profile health issues ===" }
    foreach ($profileHealth in $badHealth) {
        Write-Host ""
        Write-Host ("[{0}] {1}" -f $profileHealth.Status, $profileHealth.Profile)
        foreach ($issue in $profileHealth.Issues) {
            Write-Host ("- {0}: {1} - {2}" -f $issue.Severity, $issue.Code, $issue.Message)
        }
    }
}

Write-Host ""
if ($lang -eq "es") {
    Write-Host "Siguientes comprobaciones sugeridas:"
    Write-Host "- Si Client global mods aparece como Warning, ejecuta clear-client-mods antes de alojar."
    Write-Host "- Si Workshop subscription failure aparece como Warning, abre la URL del item, comprueba si fue retirado/privado y no uses repair-workshop; haz backup antes de quitar/reemplazar mods."
    Write-Host "- Si Workshop update lock aparece como Warning, cierra PZ/ZombieBuddy/Java, espera a Steam y reintenta una vez."
    Write-Host "- Si Workshop update lock se repite y existe carpeta staged download, ejecuta primero repair-workshop -WhatIf."
    Write-Host "- Si Latest server log aparece como Warning, ejecuta latest-error incluyendo map logs."
    Write-Host "- Si Problem chunks aparece como Warning, ejecuta inspect-blam y prueba reparaciones solo en una copia."
    Write-Host "- Si Hosted client cache aparece como Warning despues de restaurar un backup auto, prueba reset-client-cache -WhatIf antes de tocar el save servidor."
    Write-Host "- Si Profile health aparece como Warning, ejecuta health-check sobre el perfil afectado."
}
else {
    Write-Host "Suggested next checks:"
    Write-Host "- If Client global mods is Warning, run clear-client-mods before hosting."
    Write-Host "- If Workshop subscription failure is Warning, open the item URL, check whether it was removed/private, and do not use repair-workshop; back up before removing/replacing mods."
    Write-Host "- If Workshop update lock is Warning, close PZ/ZombieBuddy/Java, wait for Steam downloads to finish, then retry once."
    Write-Host "- If Workshop update lock still repeats and a staged download folder exists, run repair-workshop -WhatIf first."
    Write-Host "- If Latest server log is Warning, run latest-error with map logs enabled."
    Write-Host "- If Problem chunks is Warning, run inspect-blam and test repairs only on a copied profile."
    Write-Host "- If Hosted client cache is Warning after restoring a native auto-backup, try reset-client-cache -WhatIf before changing the server save."
    Write-Host "- If Profile health is Warning, run health-check for the affected profile."
}
