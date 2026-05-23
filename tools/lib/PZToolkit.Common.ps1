Set-StrictMode -Version 2.0

$script:PZTToolkitRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path

function Write-PZTStep {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [string]$Scope = "pz-toolkit"
    )
    Write-Host "[$Scope] $Message"
}

function Write-PZTTitle {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [string]$Scope = "pz-toolkit"
    )

    if ((Get-PZTLanguage) -eq "es") {
        $titleMap = @{
            "PZ Hosted Toolkit - Audit" = "PZ Hosted Toolkit - Auditoria"
            "PZ Hosted Toolkit - Backup Profile" = "PZ Hosted Toolkit - Backup de perfil"
            "PZ Hosted Toolkit - Clear Client Mods" = "PZ Hosted Toolkit - Limpiar mods globales cliente"
            "PZ Hosted Toolkit - Compare Mods" = "PZ Hosted Toolkit - Comparar mods"
            "PZ Hosted Toolkit - Compare Profile Mods" = "PZ Hosted Toolkit - Comparar mods de perfil"
            "PZ Hosted Toolkit - Compare Sandbox" = "PZ Hosted Toolkit - Comparar sandbox"
            "PZ Hosted Toolkit - Copy Players" = "PZ Hosted Toolkit - Copiar jugadores"
            "PZ Hosted Toolkit - Copy World" = "PZ Hosted Toolkit - Copiar mundo"
            "PZ Hosted Toolkit - Export Profile" = "PZ Hosted Toolkit - Exportar perfil"
            "PZ Hosted Toolkit - Find Latest Errors" = "PZ Hosted Toolkit - Ultimos errores"
            "PZ Hosted Toolkit - Health Check" = "PZ Hosted Toolkit - Comprobar salud"
            "PZ Hosted Toolkit - Profile Health Check" = "PZ Hosted Toolkit - Comprobar salud de perfil"
            "PZ Hosted Toolkit - Inspect Blam" = "PZ Hosted Toolkit - Inspeccionar blam"
            "PZ Hosted Toolkit - Inspect Auto Backups" = "PZ Hosted Toolkit - Inspeccionar backups auto"
            "PZ Hosted Toolkit - Inspect Problem Chunks" = "PZ Hosted Toolkit - Inspeccionar chunks problematicos"
            "PZ Hosted Toolkit - Inspect Profile" = "PZ Hosted Toolkit - Inspeccionar perfil"
            "PZ Hosted Toolkit - Quick Diagnosis" = "PZ Hosted Toolkit - Diagnostico rapido"
            "PZ Hosted Toolkit - Repair Workshop Redownload" = "PZ Hosted Toolkit - Reparar redownload Workshop"
            "PZ Hosted Toolkit - Reset Hosted Player" = "PZ Hosted Toolkit - Resetear jugador"
            "PZ Hosted Toolkit - Reset Hosted World" = "PZ Hosted Toolkit - Resetear mundo"
            "PZ Hosted Toolkit - Restore Profile" = "PZ Hosted Toolkit - Restaurar perfil"
            "PZ Hosted Toolkit - Restore Auto Backup" = "PZ Hosted Toolkit - Restaurar backup auto"
            "PZ Hosted Toolkit - Verify Backup" = "PZ Hosted Toolkit - Verificar backup"
        }
        if ($titleMap.ContainsKey($Title)) { $Title = $titleMap[$Title] }
    }

    Write-Host ""
    Write-Host "========================================"
    Write-Host $Title
    Write-Host "========================================"
    if ((Get-PZTLanguage) -eq "es") {
        Write-PZTStep "Iniciando..." $Scope
    }
    else {
        Write-PZTStep "Starting..." $Scope
    }
}

function Get-PZTLanguage {
    if ($env:PZTK_LANGUAGE) { return $env:PZTK_LANGUAGE.ToLowerInvariant() }
    return "en"
}

function Get-PZTToolkitRoot {
    return $script:PZTToolkitRoot
}

function Write-PZTActionLog {
    param(
        [Parameter(Mandatory=$true)][string]$Action,
        [string]$Status = "Info",
        [hashtable]$Data = @{}
    )

    $logDir = Join-Path (Get-PZTToolkitRoot) "logs"
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $entry = [ordered]@{
        Timestamp = (Get-Date).ToString("o")
        Action = $Action
        Status = $Status
        User = $env:USERNAME
        Machine = $env:COMPUTERNAME
        Data = $Data
    }
    $json = $entry | ConvertTo-Json -Depth 12 -Compress
    Add-Content -LiteralPath (Join-Path $logDir "toolkit-actions.jsonl") -Value $json -Encoding UTF8
}

function Get-PZTText {
    param(
        [Parameter(Mandatory=$true)][string]$English,
        [Parameter(Mandatory=$true)][string]$Spanish
    )
    if ((Get-PZTLanguage) -eq "es") { return $Spanish }
    return $English
}

function Get-PZTWorkshopSubscriptionFailure {
    param([string]$Text)
    if (-not $Text) { return $null }

    $patterns = @(
        "onItemNotSubscribed\s+itemID=(\d+)\s+result=(\d+)",
        "item\s+state\s+SubscribePending\s+->\s+Fail\s+ID=(\d+)",
        "GetItemState\(\)=None\s+ID=(\d+)"
    )

    $events = New-Object System.Collections.Generic.List[object]
    foreach ($pattern in $patterns) {
        foreach ($match in [regex]::Matches($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            $resultCode = if ($match.Groups.Count -gt 2 -and $match.Groups[2].Success) { $match.Groups[2].Value } else { $null }
            $events.Add([pscustomobject]@{
                WorkshopId = $match.Groups[1].Value
                ResultCode = $resultCode
                Index = $match.Index
                Pattern = $pattern
            }) | Out-Null
        }
    }

    if ($events.Count -eq 0) { return $null }
    $latest = @($events | Sort-Object Index | Select-Object -Last 1)[0]
    $result = @($events | Where-Object { $_.WorkshopId -eq $latest.WorkshopId -and $_.ResultCode } | Sort-Object Index | Select-Object -Last 1)

    [pscustomobject]@{
        WorkshopId = $latest.WorkshopId
        ResultCode = if ($result.Count -gt 0) { $result[0].ResultCode } else { $null }
        EventCount = $events.Count
        Index = $latest.Index
        Url = "https://steamcommunity.com/sharedfiles/filedetails/?id=$($latest.WorkshopId)"
    }
}

function Write-PZTProfileIdentityWarning {
    param([string]$Scope = "pz-toolkit")

    Write-PZTStep (Get-PZTText `
        "Profile names are part of hosted/co-op identity, not just labels." `
        "Los nombres de perfil forman parte de la identidad hosted/co-op; no son solo etiquetas.") $Scope
    Write-PZTStep (Get-PZTText `
        "Copying or continuing a live co-op save under another profile name can detach client-local state such as explored map, map symbols, thumbnails, or other per-client files." `
        "Copiar o continuar una partida co-op viva con otro nombre de perfil puede desenganchar estado local de clientes: mapa explorado, simbolos, miniaturas u otros archivos por cliente.") $Scope
    Write-PZTStep (Get-PZTText `
        "For active co-op games, prefer backing up and editing the same profile name in place. Use new profile names mainly for lab copies, forks, or disposable tests." `
        "Para partidas co-op activas, prefiere backup y edicion in-place manteniendo el mismo nombre. Usa nombres nuevos sobre todo para copias de laboratorio, forks o pruebas desechables.") $Scope
}

function Get-PZTDefaultZomboidRoot {
    $candidate = Join-Path $env:USERPROFILE "Zomboid"
    if (Test-Path -LiteralPath $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
    return $candidate
}

function Get-PZTSteamLibraryRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    $defaultSteam = Join-Path ${env:ProgramFiles(x86)} "Steam"
    if (Test-Path -LiteralPath $defaultSteam) { $roots.Add($defaultSteam) }

    $vdf = Join-Path $defaultSteam "steamapps\libraryfolders.vdf"
    if (Test-Path -LiteralPath $vdf) {
        $text = Get-Content -LiteralPath $vdf -Raw
        $matches = [regex]::Matches($text, '"path"\s+"([^"]+)"')
        foreach ($m in $matches) {
            $path = $m.Groups[1].Value -replace "\\\\", "\"
            if (Test-Path -LiteralPath $path) { $roots.Add((Resolve-Path -LiteralPath $path).Path) }
        }
    }

    $roots | Select-Object -Unique
}

function Find-PZTWorkshopRoot {
    param([string]$WorkshopRoot)
    if ($WorkshopRoot) { return $WorkshopRoot }

    foreach ($root in Get-PZTSteamLibraryRoots) {
        $candidate = Join-Path $root "steamapps\workshop"
        if (Test-Path -LiteralPath (Join-Path $candidate "content\108600")) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Find-PZTInstallRoot {
    param([string]$InstallRoot)
    if ($InstallRoot) { return $InstallRoot }

    foreach ($root in Get-PZTSteamLibraryRoots) {
        $candidate = Join-Path $root "steamapps\common\ProjectZomboid"
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Get-PZTPaths {
    param(
        [string]$ZomboidRoot,
        [string]$WorkshopRoot,
        [string]$InstallRoot,
        [string]$BackupRoot
    )

    if (-not $ZomboidRoot) { $ZomboidRoot = Get-PZTDefaultZomboidRoot }
    if (-not $BackupRoot) { $BackupRoot = Join-Path (Get-Location).Path "backups" }

    [pscustomobject]@{
        ZomboidRoot = $ZomboidRoot
        ServerDir = Join-Path $ZomboidRoot "Server"
        SavesDir = Join-Path $ZomboidRoot "Saves\Multiplayer"
        DbDir = Join-Path $ZomboidRoot "db"
        LogsDir = Join-Path $ZomboidRoot "Logs"
        ClientModsDir = Join-Path $ZomboidRoot "mods"
        WorkshopRoot = (Find-PZTWorkshopRoot -WorkshopRoot $WorkshopRoot)
        InstallRoot = (Find-PZTInstallRoot -InstallRoot $InstallRoot)
        BackupRoot = $BackupRoot
    }
}

function Get-PZTGameProcesses {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match "ProjectZomboid|ZombieBuddy" -or
            (($_.Name -match "java|javaw|zulu") -and ($_.CommandLine -match "ProjectZomboid|ZombieBuddy|ZModUnbork|PeekAView|ZBBetterFPS|Staircast"))
        } |
        Where-Object { $_.ProcessId -ne $PID }
}

function Format-PZTProcessCommandLine {
    param([AllowNull()][string]$CommandLine)
    if (-not $CommandLine) { return "" }
    $value = $CommandLine
    if ($env:USERPROFILE) { $value = $value.Replace($env:USERPROFILE, "%USERPROFILE%") }
    if ($value.Length -gt 220) { $value = $value.Substring(0, 220) + "..." }
    return $value
}

function Assert-PZTNoGameProcesses {
    $procs = Get-PZTGameProcesses
    if ($procs) {
        $procs | Select-Object ProcessId, Name, @{Name="CommandLine";Expression={ Format-PZTProcessCommandLine -CommandLine $_.CommandLine }} | Format-List
        throw "Project Zomboid, ZombieBuddy, or Java-related processes are running. Close the game before modifying files."
    }
}

function Assert-PZTProfileNameSafe {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$ProfileName,
        [string]$ParamName = "ProfileName"
    )

    if ($ProfileName -ne $ProfileName.Trim()) { throw "$ParamName has leading or trailing whitespace." }
    if (-not $ProfileName) { throw "$ParamName cannot be empty." }
    if ($ProfileName -eq "." -or $ProfileName -eq ".." -or $ProfileName.Contains("..")) { throw "$ParamName cannot contain '..'." }
    if ($ProfileName -match '[\\/:\*\?"<>\|]') { throw "$ParamName contains characters that are not safe for hosted profile filenames." }
    if ($ProfileName -match '[\x00-\x1F]') { throw "$ParamName contains control characters." }

    $reserved = @("CON","PRN","AUX","NUL","COM1","COM2","COM3","COM4","COM5","COM6","COM7","COM8","COM9","LPT1","LPT2","LPT3","LPT4","LPT5","LPT6","LPT7","LPT8","LPT9")
    if ($reserved -contains $ProfileName.ToUpperInvariant()) { throw "$ParamName uses a reserved Windows filename." }
}

function Get-PZTFullPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Assert-PZTPathInside {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Parent,
        [string]$Description = "path"
    )

    $fullPath = Get-PZTFullPath -Path $Path
    $fullParent = Get-PZTFullPath -Path $Parent
    $parentWithSeparator = $fullParent.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not ($fullPath.Equals($fullParent, [System.StringComparison]::OrdinalIgnoreCase) -or $fullPath.StartsWith($parentWithSeparator, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "Refusing unsafe $Description outside expected root. Path='$fullPath' Root='$fullParent'"
    }
    return $fullPath
}

function Assert-PZTProfilePathsContained {
    param(
        [Parameter(Mandatory=$true)]$Paths,
        [Parameter(Mandatory=$true)][string]$ProfileName
    )

    Assert-PZTProfileNameSafe -ProfileName $ProfileName
    foreach ($file in Get-PZTProfileFilePaths -ServerDir $Paths.ServerDir -ProfileName $ProfileName) {
        Assert-PZTPathInside -Path $file -Parent $Paths.ServerDir -Description "server profile file" | Out-Null
    }
    $saveName = Convert-PZTProfileNameToSaveName -ProfileName $ProfileName
    Assert-PZTProfileNameSafe -ProfileName $saveName -ParamName "SaveName"
    Assert-PZTPathInside -Path (Join-Path $Paths.SavesDir $saveName) -Parent $Paths.SavesDir -Description "save folder" | Out-Null
    Assert-PZTPathInside -Path (Join-Path $Paths.SavesDir "${saveName}_player") -Parent $Paths.SavesDir -Description "player folder" | Out-Null
    Assert-PZTPathInside -Path (Join-Path $Paths.DbDir "$ProfileName.db") -Parent $Paths.DbDir -Description "profile database" | Out-Null
}

function New-PZTBackupDir {
    param(
        [Parameter(Mandatory=$true)][string]$BackupRoot,
        [Parameter(Mandatory=$true)][string]$Name
    )
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $dir = Join-Path $BackupRoot "$Name-$stamp"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

function Copy-PZTDirectory {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$DestinationParent
    )
    if (-not (Test-Path -LiteralPath $Source)) { return $false }
    $destination = Join-Path $DestinationParent (Split-Path -Leaf $Source)
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    & robocopy $Source $destination /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) {
        throw "Robocopy failed with exit code $LASTEXITCODE while copying $Source to $destination"
    }
    return $true
}

function Copy-PZTDirectoryWithProgress {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$DestinationParent,
        [string]$Scope = "pz-toolkit"
    )
    if (-not (Test-Path -LiteralPath $Source)) {
        Write-PZTStep "Skipped missing folder: $Source" $Scope
        return $false
    }

    $summary = Get-PZTTreeSummary -Path $Source
    Write-PZTStep ("Copying {0} files ({1} MB): {2}" -f $summary.Files, $summary.SizeMB, $Source) $Scope
    $result = Copy-PZTDirectory -Source $Source -DestinationParent $DestinationParent
    Write-PZTStep ("Copied {0} files." -f $summary.Files) $Scope
    return $result
}

function Copy-PZTFileIfExists {
    param([string]$Path, [string]$Destination)
    if (Test-Path -LiteralPath $Path) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        Copy-Item -LiteralPath $Path -Destination $Destination -Force
        return $true
    }
    return $false
}

function Get-PZTTreeSummary {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Path = $Path; Exists = $false; Files = 0; SizeMB = 0; LastWrite = $null }
    }
    $files = Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue
    $measure = $files | Measure-Object Length -Sum
    $last = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    [pscustomobject]@{
        Path = $Path
        Exists = $true
        Files = ($files | Measure-Object).Count
        SizeMB = [math]::Round(($measure.Sum / 1MB), 2)
        LastWrite = if ($last) { $last.LastWriteTime } else { $null }
    }
}

function Test-PZTUtf8Bom {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
}

function Set-PZTTextNoBom {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content
    )
    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Invoke-PZTPython {
    param([Parameter(Mandatory=$true)][string]$Code)

    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) { $python = Get-Command py -ErrorAction SilentlyContinue }
    if (-not $python) { throw "Python was not found in PATH. SQLite operations require Python." }

    $tmp = Join-Path $env:TEMP ("pz-toolkit-{0}.py" -f ([guid]::NewGuid().ToString("N")))
    try {
        Set-PZTTextNoBom -Path $tmp -Content $Code
        & $python.Source $tmp
        if ($LASTEXITCODE -ne 0) { throw "Python exited with code $LASTEXITCODE." }
    }
    finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    }
}

function Invoke-PZTPythonJson {
    param(
        [Parameter(Mandatory=$true)][string]$Code,
        [Parameter(Mandatory=$true)]$InputObject
    )

    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) { $python = Get-Command py -ErrorAction SilentlyContinue }
    if (-not $python) { throw "Python was not found in PATH. SQLite operations require Python." }

    $tmpCode = Join-Path $env:TEMP ("pz-toolkit-{0}.py" -f ([guid]::NewGuid().ToString("N")))
    $tmpJson = Join-Path $env:TEMP ("pz-toolkit-{0}.json" -f ([guid]::NewGuid().ToString("N")))
    try {
        Set-PZTTextNoBom -Path $tmpCode -Content $Code
        Set-PZTTextNoBom -Path $tmpJson -Content ($InputObject | ConvertTo-Json -Depth 10)
        & $python.Source $tmpCode $tmpJson
        if ($LASTEXITCODE -ne 0) { throw "Python exited with code $LASTEXITCODE." }
    }
    finally {
        if (Test-Path -LiteralPath $tmpCode) { Remove-Item -LiteralPath $tmpCode -Force }
        if (Test-Path -LiteralPath $tmpJson) { Remove-Item -LiteralPath $tmpJson -Force }
    }
}

function Get-PZTPlayersInfo {
    param([Parameter(Mandatory=$true)][string]$PlayersDb)

    if (-not (Test-Path -LiteralPath $PlayersDb)) { return @() }
    $code = @"
import json, sqlite3, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    args = json.load(f)
db = args["db"]
con = sqlite3.connect(db)
con.row_factory = sqlite3.Row
cur = con.cursor()
tables = [r[0] for r in cur.execute("select name from sqlite_master where type='table'").fetchall()]
if "networkPlayers" not in tables:
    con.close()
    raise SystemExit(0)
cols = [r[1] for r in cur.execute("pragma table_info(networkPlayers)").fetchall()]
wanted = ["id", "world", "username", "playerIndex", "name", "steamid", "x", "y", "z", "isDead", "lastConnection", "lastSeen", "lastOnline", "lastUpdated"]
select_cols = [c for c in wanted if c in cols]
if not select_cols:
    con.close()
    raise SystemExit(0)
order = "id" if "id" in cols else select_cols[0]
rows = cur.execute("select " + ",".join(select_cols) + " from networkPlayers order by " + order).fetchall()
for row in rows:
    data = {}
    for col in select_cols:
        data[col] = row[col]
    if "isDead" in data and data["isDead"] is not None:
        data["isDead"] = bool(data["isDead"])
    print(json.dumps(data))
con.close()
"@

    $raw = Invoke-PZTPythonJson -Code $code -InputObject @{ db = $PlayersDb }
    if (-not $raw) { return @() }
    return @($raw | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
}

function Get-PZTProfilePlayers {
    param(
        [Parameter(Mandatory=$true)]$Paths,
        [Parameter(Mandatory=$true)][string]$ProfileName
    )

    $saveName = Get-PZTProfileSaveName -SavesDir $Paths.SavesDir -ProfileName $ProfileName
    $playersDb = Join-Path (Join-Path $Paths.SavesDir $saveName) "players.db"
    return @(Get-PZTPlayersInfo -PlayersDb $playersDb)
}

function Get-PZTProfileFilePaths {
    param(
        [Parameter(Mandatory=$true)][string]$ServerDir,
        [Parameter(Mandatory=$true)][string]$ProfileName
    )
    @(
        Join-Path $ServerDir "$ProfileName.ini"
        Join-Path $ServerDir "${ProfileName}_SandboxVars.lua"
        Join-Path $ServerDir "${ProfileName}_spawnpoints.lua"
        Join-Path $ServerDir "${ProfileName}_spawnregions.lua"
    )
}

function Convert-PZTProfileNameToSaveName {
    param([Parameter(Mandatory=$true)][string]$ProfileName)
    return ($ProfileName -replace '\s+', '_')
}

function Get-PZTProfileSaveName {
    param(
        [Parameter(Mandatory=$true)][string]$SavesDir,
        [Parameter(Mandatory=$true)][string]$ProfileName
    )

    if (Test-Path -LiteralPath (Join-Path $SavesDir $ProfileName)) { return $ProfileName }
    $normalized = Convert-PZTProfileNameToSaveName -ProfileName $ProfileName
    if (Test-Path -LiteralPath (Join-Path $SavesDir $normalized)) { return $normalized }
    return $normalized
}

function Read-PZTIniValue {
    param(
        [Parameter(Mandatory=$true)][string]$IniPath,
        [Parameter(Mandatory=$true)][string]$Key
    )
    if (-not (Test-Path -LiteralPath $IniPath)) { return $null }
    $line = Get-Content -LiteralPath $IniPath | Where-Object { $_ -like "$Key=*" } | Select-Object -First 1
    if (-not $line) { return $null }
    return ($line -replace "^[^=]+=", "")
}

function Read-PZTIniList {
    param(
        [Parameter(Mandatory=$true)][string]$IniPath,
        [Parameter(Mandatory=$true)][string]$Key
    )
    $value = Read-PZTIniValue -IniPath $IniPath -Key $Key
    if (-not $value) { return @() }
    return @($value -split ";" | Where-Object { $_ } | ForEach-Object { $_.Trim() })
}

function Get-PZTHostedProfileNames {
    param([Parameter(Mandatory=$true)][string]$ServerDir)

    if (-not (Test-Path -LiteralPath $ServerDir)) { return @() }
    return @(Get-ChildItem -LiteralPath $ServerDir -File -Filter *.ini -Force |
        Sort-Object Name |
        ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) })
}

function Read-PZTMenuChoice {
    param(
        [Parameter(Mandatory=$true)][string]$Prompt,
        [Parameter(Mandatory=$true)][string[]]$Items,
        [switch]$AllowCancel
    )

    if ($Items.Count -eq 0) { throw "No choices available for: $Prompt" }

    $choices = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $choices.Add([pscustomobject]@{
            Label = $Items[$i]
            Value = $Items[$i]
            IsCancel = $false
        })
    }
    if ($AllowCancel) {
        $choices.Add([pscustomobject]@{
            Label = $(if ((Get-PZTLanguage) -eq "es") { "Cancelar" } else { "Cancel" })
            Value = $null
            IsCancel = $true
        })
    }

    $selected = 0
    while ($true) {
        Write-Host ""
        Write-Host $Prompt -ForegroundColor Cyan
        if ((Get-PZTLanguage) -eq "es") {
            $arrows = "$([char]0x2191)/$([char]0x2193)"
            Write-Host "Usa $arrows y ENTER. Esc cancela cuando este disponible." -ForegroundColor DarkGray
        }
        else {
            Write-Host "Use Up/Down and Enter. Esc cancels when available." -ForegroundColor DarkGray
        }

        for ($i = 0; $i -lt $choices.Count; $i++) {
            $choice = $choices[$i]
            $prefix = if ($choice.IsCancel) { "  0." } else { ("  {0}." -f ($i + 1)) }
            $line = "{0} {1}" -f $prefix, $choice.Label
            if ($i -eq $selected) {
                Write-Host ("> $line") -ForegroundColor Black -BackgroundColor Gray
            }
            else {
                Write-Host ("  $line")
            }
        }

        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            "UpArrow" {
                if ($selected -gt 0) { $selected-- } else { $selected = $choices.Count - 1 }
            }
            "DownArrow" {
                if ($selected -lt ($choices.Count - 1)) { $selected++ } else { $selected = 0 }
            }
            "Home" { $selected = 0 }
            "End" { $selected = $choices.Count - 1 }
            "PageUp" { $selected = [Math]::Max(0, $selected - 10) }
            "PageDown" { $selected = [Math]::Min($choices.Count - 1, $selected + 10) }
            "Escape" {
                if ($AllowCancel) { return $null }
            }
            "Enter" {
                return $choices[$selected].Value
            }
            default { }
        }

        $linesToClear = $choices.Count + 3
        if ($Host.UI.RawUI.CursorPosition.Y -ge $linesToClear) {
            [Console]::SetCursorPosition(0, [Console]::CursorTop - $linesToClear)
        }
    }
}

function Read-PZTYesNo {
    param(
        [Parameter(Mandatory=$true)][string]$Prompt,
        [bool]$Default = $true
    )

    if ((Get-PZTLanguage) -eq "es") {
        $suffix = if ($Default) { "[Enter=si, n=no]" } else { "[s=si, Enter=no]" }
    }
    else {
        $suffix = if ($Default) { "[Enter=yes, n=no]" } else { "[y=yes, Enter=no]" }
    }
    while ($true) {
        $raw = (Read-Host "$Prompt $suffix").Trim()
        if (-not $raw) { return $Default }
        if ($raw -match '^(y|yes|s|si)$') { return $true }
        if ($raw -match '^(n|no)$') { return $false }
        if ((Get-PZTLanguage) -eq "es") { Write-Host "Responde s o n." } else { Write-Host "Please answer y or n." }
    }
}

function Get-PZTBackupDirectories {
    param(
        [Parameter(Mandatory=$true)][string]$BackupRoot,
        [int]$Limit = 20
    )

    if (-not (Test-Path -LiteralPath $BackupRoot)) { return @() }
    return @(Get-ChildItem -LiteralPath $BackupRoot -Directory -Force |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First $Limit)
}

function Get-PZTAutoBackupReadme {
    param([Parameter(Mandatory=$true)][string]$Text)

    $result = [ordered]@{
        BackupTime = $null
        ServerName = $null
        CurrentServerVersion = $null
        CurrentWorldVersion = $null
        BackupWorldVersion = $null
    }

    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^Backup time:\s*(.+)$') {
            $raw = $matches[1].Trim()
            $result.BackupTime = $raw
        }
        elseif ($line -match '^ServerName:\s*(.+)$') {
            $result.ServerName = $matches[1].Trim()
        }
        elseif ($line -match '^Current server version:\s*(.+)$') {
            $result.CurrentServerVersion = $matches[1].Trim()
        }
        elseif ($line -match '^Current world version:\s*(.+)$') {
            $result.CurrentWorldVersion = $matches[1].Trim()
        }
        elseif ($line -match '^World version in this backup is:\s*(.+)$') {
            $result.BackupWorldVersion = $matches[1].Trim()
        }
    }

    [pscustomobject]$result
}

function Format-PZTAutoBackupTime {
    param(
        [AllowNull()]$BackupInfo,
        [string]$Format = "yyyy-MM-dd HH:mm"
    )

    $readme = $null
    if ($BackupInfo -and $BackupInfo.PSObject.Properties.Match("Readme").Count -gt 0) {
        $readme = $BackupInfo.Readme
    }
    if ($readme -and $readme.PSObject.Properties.Match("BackupTime").Count -gt 0 -and $readme.BackupTime) {
        $raw = [string]$readme.BackupTime
        $match = [regex]::Match($raw, '(\d{4}-\d{2}-\d{2})\s+at\s+(\d{2}:\d{2})(?::\d{2})?')
        if ($match.Success) {
            return "$($match.Groups[1].Value) $($match.Groups[2].Value)"
        }
        return $raw
    }

    if ($BackupInfo -and $BackupInfo.PSObject.Properties.Match("LastWriteTime").Count -gt 0 -and $BackupInfo.LastWriteTime) {
        try {
            return ([datetime]$BackupInfo.LastWriteTime).ToString($Format)
        }
        catch {
            return [string]$BackupInfo.LastWriteTime
        }
    }

    return ""
}

function Get-PZTAutoBackupInfo {
    param(
        [Parameter(Mandatory=$true)][string]$ZipPath,
        [switch]$NoCache
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $resolved = (Resolve-Path -LiteralPath $ZipPath).Path
    $file = Get-Item -LiteralPath $resolved
    $type = Split-Path -Leaf (Split-Path -Parent $resolved)
    $cacheDir = Join-Path (Get-PZTToolkitRoot) "cache\auto-backups"
    $cacheKey = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($resolved)).TrimEnd("=").Replace("+","-").Replace("/","_")
    $cachePath = Join-Path $cacheDir "$cacheKey.json"
    if (-not $NoCache -and (Test-Path -LiteralPath $cachePath)) {
        try {
            $cached = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
            if ($cached.Cache.SchemaVersion -eq 2 -and $cached.Cache.Path -eq $resolved -and [int64]$cached.Cache.Length -eq [int64]$file.Length -and $cached.Cache.LastWriteTimeUtc -eq $file.LastWriteTimeUtc.ToString("o")) {
                return $cached.Info
            }
        }
        catch { }
    }

    $zip = [System.IO.Compression.ZipFile]::OpenRead($resolved)
    try {
        $readmeEntry = $zip.GetEntry("readme.txt")
        $readmeText = $null
        if ($readmeEntry) {
            $reader = [System.IO.StreamReader]::new($readmeEntry.Open())
            try { $readmeText = $reader.ReadToEnd() } finally { $reader.Dispose() }
        }
        $readme = if ($readmeText) { Get-PZTAutoBackupReadme -Text $readmeText } else { $null }
        $serverName = if ($readme) { $readme.ServerName } else { $null }
        $entries = @($zip.Entries | ForEach-Object { $_.FullName -replace '\\','/' })
        $serverEntries = @($entries | Where-Object { $_ -like "Server/*" })
        $dbEntries = @($entries | Where-Object { $_ -like "db/*" })
        $saveEntries = @($entries | Where-Object { $_ -like "Saves/Multiplayer/*" })

        $profileInfo = $null
        if ($serverName) {
            $normalizedSaveName = Convert-PZTProfileNameToSaveName -ProfileName $serverName
            $saveNameInZip = $null
            if (@($entries | Where-Object { $_.StartsWith("Saves/Multiplayer/$serverName/", [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
                $saveNameInZip = $serverName
            }
            elseif (@($entries | Where-Object { $_.StartsWith("Saves/Multiplayer/$normalizedSaveName/", [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
                $saveNameInZip = $normalizedSaveName
            }
            $serverFileNames = @(
                "Server/$serverName.ini",
                "Server/${serverName}_SandboxVars.lua",
                "Server/${serverName}_spawnpoints.lua",
                "Server/${serverName}_spawnregions.lua"
            )
            $profileInfo = [pscustomobject]@{
                SaveNameInZip = $saveNameInZip
                SaveEntries = if ($saveNameInZip) { @($entries | Where-Object { $_.StartsWith("Saves/Multiplayer/$saveNameInZip/", [System.StringComparison]::OrdinalIgnoreCase) }).Count } else { 0 }
                PlayerEntries = if ($saveNameInZip) { @($entries | Where-Object { $_.StartsWith("Saves/Multiplayer/${saveNameInZip}_player/", [System.StringComparison]::OrdinalIgnoreCase) }).Count } else { 0 }
                ServerEntries = @($entries | Where-Object { $serverFileNames -icontains $_ }).Count
                IniEntries = @($entries | Where-Object { $_ -ieq "Server/$serverName.ini" }).Count
                SandboxEntries = @($entries | Where-Object { $_ -ieq "Server/${serverName}_SandboxVars.lua" }).Count
                DbEntries = @($entries | Where-Object { $_ -ieq "db/$serverName.db" }).Count
            }
        }

        $info = [pscustomobject]@{
            Path = $resolved
            Name = $file.Name
            Type = $type
            SizeMB = [math]::Round($file.Length / 1MB, 2)
            LastWriteTime = $file.LastWriteTime
            BackupDisplayTime = $null
            HasReadme = [bool]$readmeEntry
            Readme = $readme
            ServerName = $serverName
            EntryCounts = [pscustomobject]@{
                Total = $entries.Count
                Server = $serverEntries.Count
                Db = $dbEntries.Count
                Saves = $saveEntries.Count
                Lua = @($entries | Where-Object { $_ -like "Lua/*" }).Count
                Mods = @($entries | Where-Object { $_ -like "mods/*" }).Count
            }
            ProfileEntries = $profileInfo
            ContainsGlobalState = ($serverEntries.Count -gt 0 -or $dbEntries.Count -gt 0 -or @($entries | Where-Object { $_ -like "Lua/*" -or $_ -like "mods/*" }).Count -gt 0)
        }
        $info.BackupDisplayTime = Format-PZTAutoBackupTime -BackupInfo $info
        if (-not $NoCache) {
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            $payload = [pscustomobject]@{
                Cache = [pscustomobject]@{
                    SchemaVersion = 2
                    Path = $resolved
                    Length = $file.Length
                    LastWriteTimeUtc = $file.LastWriteTimeUtc.ToString("o")
                    CachedAt = (Get-Date).ToString("o")
                }
                Info = $info
            }
            Set-PZTTextNoBom -Path $cachePath -Content ($payload | ConvertTo-Json -Depth 16)
        }
        return $info
    }
    finally {
        $zip.Dispose()
    }
}

function Get-PZTAutoBackups {
    param(
        [Parameter(Mandatory=$true)][string]$ZomboidRoot,
        [string]$Type,
        [int]$Limit = 50,
        [string]$ProgressScope,
        [switch]$NoCache
    )

    $backupRoot = Join-Path $ZomboidRoot "backups"
    $types = if ($Type) { @($Type) } else { @("startup", "version", "period") }
    $items = New-Object System.Collections.Generic.List[object]
    $zipFiles = New-Object System.Collections.Generic.List[object]
    foreach ($backupType in $types) {
        $dir = Join-Path $backupRoot $backupType
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        Get-ChildItem -LiteralPath $dir -File -Filter "*.zip" -Force |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First $Limit |
            ForEach-Object { $zipFiles.Add([pscustomobject]@{ Type = $backupType; File = $_ }) | Out-Null }
    }
    if ($ProgressScope) { Write-PZTStep (Get-PZTText "ZIP files found before analysis: $($zipFiles.Count)" "ZIPs encontrados antes de analizar: $($zipFiles.Count)") $ProgressScope }
    $n = 0
    foreach ($zipItem in $zipFiles) {
        $n++
        $zipFile = $zipItem.File
        if ($ProgressScope) { Write-PZTStep (Get-PZTText "Analyzing backup $n/$($zipFiles.Count): $($zipItem.Type)\$($zipFile.Name)" "Analizando backup $n/$($zipFiles.Count): $($zipItem.Type)\$($zipFile.Name)") $ProgressScope }
        try {
            $items.Add((Get-PZTAutoBackupInfo -ZipPath $zipFile.FullName -NoCache:$NoCache)) | Out-Null
        }
        catch {
            $items.Add([pscustomobject]@{
                Path = $zipFile.FullName
                Name = $zipFile.Name
                Type = $zipItem.Type
                SizeMB = [math]::Round($zipFile.Length / 1MB, 2)
                LastWriteTime = $zipFile.LastWriteTime
                BackupDisplayTime = Format-PZTAutoBackupTime -BackupInfo ([pscustomobject]@{ LastWriteTime = $zipFile.LastWriteTime })
                HasReadme = $false
                Readme = $null
                ServerName = $null
                EntryCounts = $null
                ProfileEntries = $null
                ContainsGlobalState = $false
                Error = $_.Exception.Message
            }) | Out-Null
        }
    }
    return @($items.ToArray() | Sort-Object LastWriteTime -Descending)
}

function Test-PZTBackupComplete {
    param([Parameter(Mandatory=$true)][string]$BackupPath)
    $statusPath = Join-Path $BackupPath "BACKUP_STATUS.txt"
    if (-not (Test-Path -LiteralPath $statusPath)) { return $false }
    $firstLine = Get-Content -LiteralPath $statusPath -First 1 -ErrorAction SilentlyContinue
    return ($firstLine -eq "COMPLETE")
}

function Get-PZTProfileHealth {
    param(
        [Parameter(Mandatory=$true)]$Paths,
        [Parameter(Mandatory=$true)][string]$ProfileName
    )

    $ini = Join-Path $Paths.ServerDir "$ProfileName.ini"
    $sandbox = Join-Path $Paths.ServerDir "${ProfileName}_SandboxVars.lua"
    $spawnregions = Join-Path $Paths.ServerDir "${ProfileName}_spawnregions.lua"
    $saveName = Get-PZTProfileSaveName -SavesDir $Paths.SavesDir -ProfileName $ProfileName
    $saveDir = Join-Path $Paths.SavesDir $saveName
    $profileDb = Join-Path $Paths.DbDir "$ProfileName.db"
    $playersDb = Join-Path $saveDir "players.db"

    $mods = @(if (Test-Path -LiteralPath $ini) { Read-PZTIniList -IniPath $ini -Key "Mods" })
    $workshop = @(if (Test-Path -LiteralPath $ini) { Read-PZTIniList -IniPath $ini -Key "WorkshopItems" })
    $maps = @(if (Test-Path -LiteralPath $ini) { Read-PZTIniList -IniPath $ini -Key "Map" })
    $publicName = if (Test-Path -LiteralPath $ini) { Read-PZTIniValue -IniPath $ini -Key "PublicName" } else { $null }

    $issues = New-Object System.Collections.Generic.List[object]
    function Add-PZTHealthIssue {
        param([string]$Severity, [string]$Code, [string]$Message)
        $issues.Add([pscustomobject]@{ Severity = $Severity; Code = $Code; Message = $Message }) | Out-Null
    }

    if (-not (Test-Path -LiteralPath $ini)) { Add-PZTHealthIssue -Severity "Error" -Code "MissingIni" -Message (Get-PZTText "Server INI is missing." "Falta el INI del servidor.") }
    if (-not (Test-Path -LiteralPath $sandbox)) { Add-PZTHealthIssue -Severity "Error" -Code "MissingSandbox" -Message (Get-PZTText "SandboxVars file is missing." "Falta el archivo SandboxVars.") }
    if (-not (Test-Path -LiteralPath $spawnregions)) { Add-PZTHealthIssue -Severity "Warning" -Code "MissingSpawnregions" -Message (Get-PZTText "Spawnregions file is missing; hosting may still work if PZ regenerates it, but the profile is incomplete." "Falta el archivo spawnregions; el host puede funcionar si PZ lo regenera, pero el perfil esta incompleto.") }
    if (Test-Path -LiteralPath $ini) {
        if (Test-PZTUtf8Bom -Path $ini) { Add-PZTHealthIssue -Severity "Warning" -Code "IniBom" -Message (Get-PZTText "INI has UTF-8 BOM. PZ usually tolerates this, but BOM-free UTF-8 is safer for automated edits." "El INI tiene UTF-8 BOM. PZ suele tolerarlo, pero UTF-8 sin BOM es mas seguro para ediciones automatizadas.") }
        if (-not $publicName) { Add-PZTHealthIssue -Severity "Warning" -Code "MissingPublicName" -Message (Get-PZTText "PublicName is empty or missing." "PublicName esta vacio o falta.") }
    }
    if (Test-Path -LiteralPath $sandbox) {
        if (Test-PZTUtf8Bom -Path $sandbox) { Add-PZTHealthIssue -Severity "Warning" -Code "SandboxBom" -Message (Get-PZTText "SandboxVars has UTF-8 BOM. This has caused load/edit issues before; keep profile files BOM-free." "SandboxVars tiene UTF-8 BOM. Esto ya ha causado problemas de carga/edicion; manten los archivos de perfil sin BOM.") }
    }
    $modsCount = @($mods).Count
    $workshopCount = @($workshop).Count
    $mapsCount = @($maps).Count
    if ($modsCount -eq 0 -and $workshopCount -gt 0) { Add-PZTHealthIssue -Severity "Warning" -Code "WorkshopWithoutMods" -Message (Get-PZTText "WorkshopItems are set but Mods is empty." "WorkshopItems tiene valores, pero Mods esta vacio.") }
    if ($modsCount -gt 0 -and $workshopCount -eq 0) { Add-PZTHealthIssue -Severity "Warning" -Code "ModsWithoutWorkshop" -Message (Get-PZTText "Mods are set but WorkshopItems is empty. This is valid only for local/non-Workshop mods." "Mods tiene valores, pero WorkshopItems esta vacio. Solo es valido para mods locales/no Workshop.") }
    if ($mapsCount -eq 0) { Add-PZTHealthIssue -Severity "Warning" -Code "NoMapEntries" -Message (Get-PZTText "Map list is empty." "La lista Map esta vacia.") }
    if (-not (Test-Path -LiteralPath $saveDir)) { Add-PZTHealthIssue -Severity "Info" -Code "NoSaveYet" -Message (Get-PZTText "Save folder was not found. This is normal for a profile that has not launched a world yet." "No se encontro carpeta de save. Es normal en un perfil que aun no ha lanzado un mundo.") }
    if ((Test-Path -LiteralPath $saveDir) -and -not (Test-Path -LiteralPath $playersDb)) { Add-PZTHealthIssue -Severity "Warning" -Code "MissingPlayersDb" -Message (Get-PZTText "Save folder exists but players.db is missing." "La carpeta de save existe, pero falta players.db.") }

    $status = "OK"
    if (@($issues | Where-Object { $_.Severity -eq "Warning" }).Count -gt 0) { $status = "Warning" }
    if (@($issues | Where-Object { $_.Severity -eq "Error" }).Count -gt 0) { $status = "Needs attention" }

    [pscustomobject]@{
        Profile = $ProfileName
        Status = $status
        PublicName = $publicName
        SaveName = $saveName
        Counts = [pscustomobject]@{
            Mods = $modsCount
            WorkshopItems = $workshopCount
            Maps = $mapsCount
        }
        Paths = [pscustomobject]@{
            Ini = $ini
            Sandbox = $sandbox
            Spawnregions = $spawnregions
            Save = $saveDir
            ProfileDb = $profileDb
            PlayersDb = $playersDb
        }
        Exists = [pscustomobject]@{
            Ini = (Test-Path -LiteralPath $ini)
            Sandbox = (Test-Path -LiteralPath $sandbox)
            Spawnregions = (Test-Path -LiteralPath $spawnregions)
            Save = (Test-Path -LiteralPath $saveDir)
            ProfileDb = (Test-Path -LiteralPath $profileDb)
            PlayersDb = (Test-Path -LiteralPath $playersDb)
        }
        Issues = @($issues.ToArray())
    }
}
