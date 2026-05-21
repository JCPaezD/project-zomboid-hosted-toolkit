param(
    [switch]$KeepTemp
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$tmp = Join-Path $PSScriptRoot "tmp"
$zRoot = Join-Path $tmp "Zomboid"
$workshopRoot = Join-Path $tmp "SteamWorkshop"
$backupRoot = Join-Path $tmp "backups"
$exportRoot = Join-Path $tmp "exports"
$pass = 0
$fail = 0

function Write-TestResult {
    param([string]$Name, [bool]$Ok, [string]$Message = "")
    if ($Ok) {
        $script:pass++
        Write-Host "[PASS] $Name"
    }
    else {
        $script:fail++
        Write-Host "[FAIL] $Name"
        if ($Message) { Write-Host "       $Message" }
    }
}

function Invoke-Checked {
    param(
        [string]$Name,
        [scriptblock]$Script,
        [scriptblock]$Assert
    )
    try {
        $output = & $Script 2>&1
        $text = ($output | Out-String)
        $ok = if ($Assert) { & $Assert $text } else { $true }
        Write-TestResult -Name $Name -Ok $ok -Message $text.Trim()
    }
    catch {
        Write-TestResult -Name $Name -Ok $false -Message $_.Exception.Message
    }
}

function Set-TestText {
    param([string]$Path, [string]$Content)
    $encoding = [System.Text.UTF8Encoding]::new($false)
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

$profile = "TestProfile"
$otherProfile = "OtherProfile"
$spaceProfile = "Profile With Spaces"
$serverDir = Join-Path $zRoot "Server"
$savesDir = Join-Path $zRoot "Saves\Multiplayer"
$logsDir = Join-Path $zRoot "Logs\2026-01"
$modsDir = Join-Path $zRoot "mods"
$dbDir = Join-Path $zRoot "db"

Set-TestText -Path (Join-Path $serverDir "$profile.ini") -Content @"
PublicName=TestProfile
Mods=ExampleMod;SecondMod
WorkshopItems=123;456
Map=ExampleMap;Muldraugh, KY
"@
Set-TestText -Path (Join-Path $serverDir "${profile}_SandboxVars.lua") -Content @"
SandboxVars = {
    World = {
        CarSpawnRate = 5,
        DayLength = 3,
    },
    ExampleModSandbox = {
        Enabled = true,
        Amount = 10,
    },
}
"@
Set-TestText -Path (Join-Path $serverDir "$otherProfile.ini") -Content @"
PublicName=Other Server
Mods=ExampleMod
WorkshopItems=123
Map=Muldraugh, KY
"@
Set-TestText -Path (Join-Path $serverDir "${otherProfile}_SandboxVars.lua") -Content @"
SandboxVars = {
    World = {
        CarSpawnRate = 3,
        DayLength = 3,
    },
}
"@
Set-TestText -Path (Join-Path $serverDir "$spaceProfile.ini") -Content @"
PublicName=Profile With Spaces
Mods=
WorkshopItems=
Map=Muldraugh, KY
"@
Set-TestText -Path (Join-Path $serverDir "${spaceProfile}_SandboxVars.lua") -Content @"
SandboxVars = {
    World = {
        DayLength = 3,
    },
}
"@
Set-TestText -Path (Join-Path $serverDir "${spaceProfile}_spawnregions.lua") -Content "function SpawnRegions() return {} end"
Set-TestText -Path (Join-Path $modsDir "default.txt") -Content @"
mod = ExampleClientMod
"@

New-Item -ItemType Directory -Path (Join-Path $savesDir $profile) -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $savesDir "${profile}_player") -Force | Out-Null
Set-TestText -Path (Join-Path $savesDir "$profile\map_t.bin") -Content "fake map"
Set-TestText -Path (Join-Path $savesDir "$profile\map\10\20.bin") -Content "active chunk"
Set-TestText -Path (Join-Path $savesDir "$profile\blam\10\20.bin") -Content "bad chunk"
Set-TestText -Path (Join-Path $savesDir "$profile\blam\10\20_error.txt") -Content @"
java.lang.RuntimeException: SANITY CHECK FAIL! thread="LoadChunk"
CRC mismatch save=1 load=2
"@
Set-TestText -Path (Join-Path $savesDir "${profile}_player\player.bin") -Content "fake player"
New-Item -ItemType Directory -Path $dbDir -Force | Out-Null
Set-TestText -Path (Join-Path $dbDir "$profile.db") -Content "fake db placeholder"

Set-TestText -Path (Join-Path $logsDir "2026-01-01_12-00_DebugLog-server.txt") -Content @"
LOG  : Workshop: GetItemState()=Installed|NeedsUpdate ID=123
ERROR: ItemPicker ERROR: SuburbsDistributions["all"]["inventorymale"] is broken
java.lang.NullPointerException: fixture
LOG  : UI_ServerStatus_Terminated
"@
Set-TestText -Path (Join-Path $logsDir "2026-01-01_12-00_map.txt") -Content @"
[01-01-26 12:00:00.000] Error loading chunk 10,20.
java.lang.RuntimeException: SANITY CHECK FAIL! thread="LoadChunk"
CRC mismatch save=1 load=2
"@

$contentRoot = Join-Path $workshopRoot "content\108600\123\mods\ExampleMod"
$downloadRoot = Join-Path $workshopRoot "downloads\108600\123\mods\ExampleMod"
Set-TestText -Path (Join-Path $contentRoot "mod.info") -Content @"
name=Example Mod
id=ExampleMod
"@
Set-TestText -Path (Join-Path $downloadRoot "mod.info") -Content @"
name=Example Mod
id=ExampleMod
"@

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command py -ErrorAction SilentlyContinue }
if ($python) {
    $playersDb = Join-Path $savesDir "$profile\players.db"
    $py = @"
import sqlite3
db = r'''$playersDb'''
con = sqlite3.connect(db)
cur = con.cursor()
cur.execute('create table networkPlayers (id integer primary key, world text, username text, playerIndex integer, name text, steamid text, x real, y real, z real, isDead integer)')
cur.execute('insert into networkPlayers values (1, ?, ?, 0, ?, ?, 10, 20, 0, 0)', ('$profile', 'FixtureUser', 'Fixture Character', '123456'))
con.commit()
con.close()
"@
    $pyPath = Join-Path $tmp "create-fixture-db.py"
    Set-TestText -Path $pyPath -Content $py
    & $python.Source $pyPath
    if ($LASTEXITCODE -ne 0) { throw "Failed to create fixture SQLite DB." }
}

Invoke-Checked -Name "PowerShell scripts parse" -Script {
    Get-ChildItem -Path (Join-Path $root "tools") -Filter *.ps1 -Recurse |
        ForEach-Object { $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$null) }
    $null = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root "pz-toolkit.ps1"), [ref]$null, [ref]$null)
    "parsed"
} -Assert { param($text) $text -match "parsed" }

Invoke-Checked -Name "audit reports fixture profile" -Script {
    & (Join-Path $root "tools\pz-audit.ps1") -ZomboidRoot $zRoot -WorkshopRoot $workshopRoot -BackupRoot $backupRoot -Json
} -Assert { param($text) $text -match $profile -and $text -match "ActiveModLines" }

Invoke-Checked -Name "inspect profile reports players and counts" -Script {
    & (Join-Path $root "tools\pz-inspect-profile.ps1") -ProfileName $profile -ZomboidRoot $zRoot -WorkshopRoot $workshopRoot -Json
} -Assert { param($text) $text -match '"Profile":\s+"TestProfile"' -and $text -match '"Players":\s+1' -and $text -match "FixtureUser" }

Invoke-Checked -Name "hub dispatches audit" -Script {
    & (Join-Path $root "pz-toolkit.ps1") audit -ZomboidRoot $zRoot -WorkshopRoot $workshopRoot -BackupRoot $backupRoot -Json
} -Assert { param($text) $text -match $profile }

Invoke-Checked -Name "find latest error summarizes categories" -Script {
    & (Join-Path $root "tools\pz-find-latest-error.ps1") -ZomboidRoot $zRoot -ServerOnly -Json
} -Assert { param($text) $text -match "WorkshopUpdate" -and $text -match "BrokenDistribution" -and $text -match "JavaException" }

Invoke-Checked -Name "find latest error suggests next checks" -Script {
    $ps = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\pz-find-latest-error.ps1") -ZomboidRoot $zRoot -ServerOnly -IncludeMapLogs
} -Assert { param($text) $text -match "Suggested next checks" -and $text -match "Workshop update/cache" -and $text -match "Problem chunk" }

Invoke-Checked -Name "repair workshop what-if detects item" -Script {
    $before = @(Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue).Count
    & (Join-Path $root "tools\pz-repair-workshop-redownload.ps1") -ZomboidRoot $zRoot -WorkshopRoot $workshopRoot -BackupRoot $backupRoot -WhatIf
    $after = @(Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue).Count
    "$(Test-Path -LiteralPath (Join-Path $workshopRoot "content\108600\123")) $before $after"
} -Assert { param($text) $text -match "True 0 0" }

Set-TestText -Path (Join-Path $logsDir "2026-01-01_13-00_DebugLog-server.txt") -Content @"
LOG  : Server started
ERROR: unrelated fixture error
"@

Invoke-Checked -Name "repair workshop no-match exits cleanly" -Script {
    & (Join-Path $root "tools\pz-repair-workshop-redownload.ps1") -ZomboidRoot $zRoot -WorkshopRoot $workshopRoot -BackupRoot $backupRoot -WhatIf
    "clean"
} -Assert { param($text) $text -match "clean" }

Set-TestText -Path (Join-Path $logsDir "2026-01-01_14-00_DebugLog-server.txt") -Content @"
LOG  : Workshop: GetItemState()=Installed|NeedsUpdate ID=123
ERROR: java.nio.file.FileSystemException: fixture.jar: being used by another process
LOG  : Workshop: onItemNotDownloaded itemID=123 result=33
"@
if (Test-Path -LiteralPath (Join-Path $workshopRoot "downloads\108600\123")) {
    Remove-Item -LiteralPath (Join-Path $workshopRoot "downloads\108600\123") -Recurse -Force
}

Invoke-Checked -Name "repair workshop missing staged download exits cleanly" -Script {
    & (Join-Path $root "tools\pz-repair-workshop-redownload.ps1") -ZomboidRoot $zRoot -WorkshopRoot $workshopRoot -BackupRoot $backupRoot -WhatIf
    "clean"
} -Assert { param($text) $text -match "clean" }

Set-TestText -Path (Join-Path $downloadRoot "mod.info") -Content @"
name=Example Mod
id=ExampleMod
"@

Invoke-Checked -Name "repair workshop rejects unsafe item id" -Script {
    $ps = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    try {
        $output = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\pz-repair-workshop-redownload.ps1") -ZomboidRoot $zRoot -WorkshopRoot $workshopRoot -BackupRoot $backupRoot -ItemId "..\123" -WhatIf 2>&1 | Out-String
        "exit=$LASTEXITCODE`n$output"
    }
    catch {
        "caught=$($_.Exception.Message)"
    }
} -Assert { param($text) $text -match "digits only" }

Invoke-Checked -Name "repair workshop requires confirm for real repair" -Script {
    $ps = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\pz-repair-workshop-redownload.ps1") -ZomboidRoot $zRoot -WorkshopRoot $workshopRoot -BackupRoot $backupRoot -ItemId "123" 2>&1
} -Assert { param($text) $text -match "without -ConfirmRepair" }

Invoke-Checked -Name "clear client mods what-if keeps file" -Script {
    & (Join-Path $root "tools\pz-clear-client-mods.ps1") -ZomboidRoot $zRoot -BackupRoot $backupRoot -WhatIf
    Get-Content -LiteralPath (Join-Path $modsDir "default.txt") -Raw
} -Assert { param($text) $text -match "ExampleClientMod" }

Invoke-Checked -Name "clear client mods requires confirm for real clear" -Script {
    $ps = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\pz-clear-client-mods.ps1") -ZomboidRoot $zRoot -BackupRoot $backupRoot 2>&1
} -Assert { param($text) $text -match "without -ConfirmClear" -and (Get-Content -LiteralPath (Join-Path $modsDir "default.txt") -Raw) -match "ExampleClientMod" }

Invoke-Checked -Name "export profile writes checklist" -Script {
    & (Join-Path $root "tools\pz-export-profile.ps1") -ProfileName $profile -ZomboidRoot $zRoot -WorkshopRoot $workshopRoot -OutputDir $exportRoot
    Test-Path -LiteralPath (Join-Path $exportRoot "$profile-workshop-checklist.csv")
    Test-Path -LiteralPath (Join-Path $exportRoot "$profile-server-settings.txt")
    Test-Path -LiteralPath (Join-Path $exportRoot "$profile-players.csv")
} -Assert { param($text) ($text -split "\r?\n" | Where-Object { $_ -match "True" }).Count -eq 3 }

Invoke-Checked -Name "export profile simple name stays under exports" -Script {
    $named = Join-Path $root "exports\SmokeNamedExport"
    if (Test-Path -LiteralPath $named) { Remove-Item -LiteralPath $named -Recurse -Force }
    & (Join-Path $root "tools\pz-export-profile.ps1") -ProfileName $profile -ZomboidRoot $zRoot -WorkshopRoot $workshopRoot -OutputDir "SmokeNamedExport"
    Test-Path -LiteralPath (Join-Path $named "$profile-summary.md")
    Remove-Item -LiteralPath $named -Recurse -Force
} -Assert { param($text) $text -match "True" }

Invoke-Checked -Name "compare mods shows removed and added lists" -Script {
    & (Join-Path $root "tools\pz-compare-mods.ps1") -LeftProfile $profile -RightProfile $otherProfile -ZomboidRoot $zRoot -WorkshopRoot $workshopRoot
} -Assert { param($text) $text -match "456" -and $text -match "steamcommunity" }

Invoke-Checked -Name "compare mods handles empty lists and compact output" -Script {
    & (Join-Path $root "tools\pz-compare-mods.ps1") -LeftProfile $spaceProfile -RightProfile $profile -ZomboidRoot $zRoot -WorkshopRoot $workshopRoot -Json
} -Assert { param($text) $s = ($text | Out-String); $s.Contains('"LeftCount":  0') -and $s.Contains('"RightCount":  2') }

Invoke-Checked -Name "profile health-check reports fixture status" -Script {
    & (Join-Path $root "tools\pz-health-check.ps1") -ProfileName $profile -ZomboidRoot $zRoot -Json
} -Assert { param($text) $s = ($text | Out-String); $s.Contains('"Status":  "Warning"') -and $s.Contains('"MissingSpawnregions"') }

Invoke-Checked -Name "profile health-check supports names with spaces" -Script {
    & (Join-Path $root "tools\pz-health-check.ps1") -ProfileName $spaceProfile -ZomboidRoot $zRoot -Json
} -Assert { param($text) $s = ($text | Out-String); ($s -match '"Profile":\s+"Profile With Spaces"') -and ($s -match '"Status":\s+"OK|Warning"') }

Invoke-Checked -Name "quick diagnosis summarizes actionable warnings" -Script {
    & (Join-Path $root "tools\pz-quick-diagnosis.ps1") -ProfileName $profile -ZomboidRoot $zRoot -Json
} -Assert { param($text) $s = ($text | Out-String); $s.Contains('"Overall":  "Warning"') -and $s.Contains('"Client global mods"') -and $s.Contains('"Problem chunks"') }

Invoke-Checked -Name "quick diagnosis detects workshop update lock" -Script {
    & (Join-Path $root "tools\pz-quick-diagnosis.ps1") -ProfileName $profile -ZomboidRoot $zRoot -Json
} -Assert { param($text) $text -match '"Area":\s+"Workshop update lock"' -and $text -match '"WorkshopId":\s+"123"' -and $text -match '"StagedDownloadFolder":\s+false' }

Set-TestText -Path (Join-Path $logsDir "2026-01-01_15-00_DebugLog-server.txt") -Content @"
LOG  : ConnectToServerState: GetItemState()=None ID=3724831368
LOG  : ConnectToServerState: item state CheckItemState -> SubscribePending ID=3724831368
LOG  : ConnectToServerState: onItemNotSubscribed itemID=3724831368 result=15
LOG  : ConnectToServerState: item state SubscribePending -> Fail ID=3724831368
"@

Invoke-Checked -Name "find latest error detects workshop subscription failure" -Script {
    & (Join-Path $root "tools\pz-find-latest-error.ps1") -ZomboidRoot $zRoot -ServerOnly -Json
} -Assert { param($text) $text -match "WorkshopSubscriptionFailure" -and $text -notmatch "WorkshopUpdate" }

Invoke-Checked -Name "quick diagnosis detects workshop subscription failure" -Script {
    & (Join-Path $root "tools\pz-quick-diagnosis.ps1") -ProfileName $profile -ZomboidRoot $zRoot -Json
} -Assert { param($text) $text -match '"Area":\s+"Workshop subscription failure"' -and $text -match '"WorkshopId":\s+"3724831368"' -and $text -match '"ResultCode":\s+"15"' }

Invoke-Checked -Name "repair workshop does not repair subscription failure" -Script {
    $ps = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\pz-repair-workshop-redownload.ps1") -ZomboidRoot $zRoot -WorkshopRoot $workshopRoot -BackupRoot $backupRoot -WhatIf 2>&1 | Out-String
} -Assert { param($text) $text -match "Workshop subscription failure detected" -and $text -match "not a staged redownload/cache repair case" -and $text -match "Nothing was changed" }

Set-TestText -Path (Join-Path $logsDir "2026-01-01_16-00_DebugLog-server.txt") -Content @"
LOG  : Workshop: GetItemState()=Installed|NeedsUpdate ID=123
LOG  : Workshop: onItemNotDownloaded itemID=123 result=33
LOG  : ConnectToServerState: GetItemState()=None ID=3724831368
LOG  : ConnectToServerState: onItemNotSubscribed itemID=3724831368 result=15
LOG  : ConnectToServerState: item state SubscribePending -> Fail ID=3724831368
"@

Invoke-Checked -Name "quick diagnosis separates mixed workshop update and subscription IDs" -Script {
    & (Join-Path $root "tools\pz-quick-diagnosis.ps1") -ProfileName $profile -ZomboidRoot $zRoot -Json
} -Assert { param($text) $text -match '"WorkshopId":\s+"123"' -and $text -match '"UpdateSignal":\s+true' -and $text -match '"LatestWorkshopSubscriptionFailure"' -and $text -match '"WorkshopId":\s+"3724831368"' }

Invoke-Checked -Name "repair workshop blocks mixed log when latest issue is subscription failure" -Script {
    $ps = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\pz-repair-workshop-redownload.ps1") -ZomboidRoot $zRoot -WorkshopRoot $workshopRoot -BackupRoot $backupRoot -WhatIf 2>&1 | Out-String
} -Assert { param($text) $text -match "Workshop subscription failure detected" -and $text -match "3724831368" -and $text -notmatch "Detected Workshop ID from log: 123" }

Invoke-Checked -Name "inspect blam reports problem chunk" -Script {
    & (Join-Path $root "tools\pz-inspect-blam.ps1") -ProfileName $profile -ZomboidRoot $zRoot
} -Assert { param($text) $text -match "TestProfile" -and $text -match "10" -and $text -match "20" }

Invoke-Checked -Name "backup and restore profile as copy" -Script {
    & (Join-Path $root "tools\pz-backup-profile.ps1") -ProfileName $profile -ZomboidRoot $zRoot -BackupRoot $backupRoot
    $backup = Get-ChildItem -LiteralPath $backupRoot -Directory -Filter "profile-$profile-*" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    $status = Get-Content -LiteralPath (Join-Path $backup.FullName "BACKUP_STATUS.txt") -First 1
    & (Join-Path $root "tools\pz-restore-profile.ps1") -BackupPath $backup.FullName -TargetProfileName "RestoredProfile" -ZomboidRoot $zRoot -BackupRoot $backupRoot -ConfirmRestore
    "Status: $status"
    Select-String -LiteralPath (Join-Path $serverDir "RestoredProfile.ini") -Pattern "PublicName=RestoredProfile" -SimpleMatch
    Test-Path -LiteralPath (Join-Path $serverDir "RestoredProfile.ini")
} -Assert { param($text) $text -match "Status: COMPLETE" -and $text -match "PublicName=RestoredProfile" -and $text -match "True" }

Invoke-Checked -Name "restore copy warns about profile identity" -Script {
    $backup = Get-ChildItem -LiteralPath $backupRoot -Directory -Filter "profile-$profile-*" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    $ps = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\pz-restore-profile.ps1") -BackupPath $backup.FullName -TargetProfileName "IdentityWarningCopy" -ZomboidRoot $zRoot -BackupRoot $backupRoot -WhatIf 2>&1
} -Assert { param($text) $text -match "Profile identity warning" -and $text -match "client-local state" -and $text -match "lab/fork" }

Invoke-Checked -Name "restore refuses incomplete backup by default" -Script {
    $backup = Get-ChildItem -LiteralPath $backupRoot -Directory -Filter "profile-$profile-*" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    Set-TestText -Path (Join-Path $backup.FullName "BACKUP_STATUS.txt") -Content "INCOMPLETE`nFixture"
    $ps = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\pz-restore-profile.ps1") -BackupPath $backup.FullName -TargetProfileName "ShouldNotRestore" -ZomboidRoot $zRoot -BackupRoot $backupRoot -ConfirmRestore 2>&1
    Set-TestText -Path (Join-Path $backup.FullName "BACKUP_STATUS.txt") -Content "COMPLETE`nFixture restored"
} -Assert { param($text) $text -match "not COMPLETE" -and -not (Test-Path -LiteralPath (Join-Path $serverDir "ShouldNotRestore.ini")) }

Invoke-Checked -Name "unsafe profile names are rejected" -Script {
    . (Join-Path $root "tools\lib\PZToolkit.Common.ps1")
    try {
        Assert-PZTProfileNameSafe -ProfileName "..\BadProfile"
        "not rejected"
    }
    catch {
        $_.Exception.Message
    }
} -Assert { param($text) $text -match "not safe|cannot contain|characters|ProfileName" }

Invoke-Checked -Name "verify backup reports complete status" -Script {
    $backup = Get-ChildItem -LiteralPath $backupRoot -Directory -Filter "profile-$profile-*" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    $ps = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\pz-verify-backup.ps1") -BackupPath $backup.FullName
} -Assert { param($text) $text -match "Status: COMPLETE" -and $text -match "Manifest: present" }

Invoke-Checked -Name "compare sandbox finds vehicle difference" -Script {
    $csv = Join-Path $tmp "sandbox-diff.csv"
    & (Join-Path $root "tools\pz-compare-sandbox.ps1") -LeftProfile $profile -RightProfile $otherProfile -ZomboidRoot $zRoot -OutputCsv $csv
    Get-Content -LiteralPath $csv -Raw
} -Assert { param($text) $text -match "CarSpawnRate" }

Invoke-Checked -Name "compare sandbox summarizes profile-only sections" -Script {
    $ps = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\pz-compare-sandbox.ps1") -LeftProfile $profile -RightProfile $otherProfile -ZomboidRoot $zRoot
} -Assert { param($text) $text -match "Profile-only / mod sections" -and $text -match "ExampleModSandbox" -and $text -match "CarSpawnRate" }

Invoke-Checked -Name "copy world what-if describes transfer" -Script {
    $ps = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\pz-copy-world.ps1") -SourceProfileName $profile -TargetProfileName $otherProfile -ZomboidRoot $zRoot -BackupRoot $backupRoot -WhatIf
} -Assert { param($text) $text -match "Source profile: TestProfile" -and $text -match "Target profile: OtherProfile" -and $text -match "WhatIf" }

Invoke-Checked -Name "copy world warns about profile identity" -Script {
    $ps = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\pz-copy-world.ps1") -SourceProfileName $profile -TargetProfileName $otherProfile -ZomboidRoot $zRoot -BackupRoot $backupRoot -WhatIf
} -Assert { param($text) $text -match "Profile identity warning" -and $text -match "client-local state" }

Invoke-Checked -Name "copy players what-if describes transfer" -Script {
    New-Item -ItemType Directory -Path (Join-Path $savesDir $otherProfile) -Force | Out-Null
    $ps = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\pz-copy-players.ps1") -SourceProfileName $profile -TargetProfileName $otherProfile -ZomboidRoot $zRoot -BackupRoot $backupRoot -WhatIf
} -Assert { param($text) $text -match "Source profile: TestProfile" -and $text -match "Target profile: OtherProfile" -and $text -match "WhatIf" }

Invoke-Checked -Name "copy players warns about profile identity" -Script {
    New-Item -ItemType Directory -Path (Join-Path $savesDir $otherProfile) -Force | Out-Null
    $ps = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\pz-copy-players.ps1") -SourceProfileName $profile -TargetProfileName $otherProfile -ZomboidRoot $zRoot -BackupRoot $backupRoot -WhatIf
} -Assert { param($text) $text -match "Profile identity warning" -and $text -match "client-local state" }

if ($python) {
    Invoke-Checked -Name "reset hosted player what-if keeps row" -Script {
        & (Join-Path $root "tools\pz-reset-hosted-player.ps1") -ProfileName $profile -Username "FixtureUser" -ZomboidRoot $zRoot -BackupRoot $backupRoot -WhatIf
    } -Assert { param($text) $text -match "WhatIf: would delete" -and $text -match "Players after" }
}
else {
    Write-TestResult -Name "reset hosted player what-if keeps row" -Ok $false -Message "Python not found; SQLite tests require Python."
}

Invoke-Checked -Name "reset hosted world what-if keeps save" -Script {
    & (Join-Path $root "tools\pz-reset-hosted-world.ps1") -ProfileName $profile -ZomboidRoot $zRoot -BackupRoot $backupRoot -WhatIf
    Test-Path -LiteralPath (Join-Path $savesDir $profile)
} -Assert { param($text) $text -match "True" }

Write-Host ""
Write-Host "Smoke tests: $pass passed, $fail failed"

if (-not $KeepTemp -and (Test-Path -LiteralPath $tmp)) {
    Remove-Item -LiteralPath $tmp -Recurse -Force
}

if ($fail -gt 0) { exit 1 }
