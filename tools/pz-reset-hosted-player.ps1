param(
    [Parameter(Mandatory=$true)][string]$ProfileName,
    [string]$Username,
    [int]$PlayerIndex = 0,
    [string]$ZomboidRoot,
    [string]$BackupRoot,
    [switch]$ConfirmReset,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\PZToolkit.Common.ps1"

Write-PZTTitle "PZ Hosted Toolkit - Reset Hosted Player" "pz-reset-hosted-player"

Assert-PZTNoGameProcesses
$paths = Get-PZTPaths -ZomboidRoot $ZomboidRoot -BackupRoot $BackupRoot
Assert-PZTProfilePathsContained -Paths $paths -ProfileName $ProfileName
$saveName = Get-PZTProfileSaveName -SavesDir $paths.SavesDir -ProfileName $ProfileName
$playersDb = Join-Path $paths.SavesDir "$saveName\players.db"
if (-not (Test-Path -LiteralPath $playersDb)) { throw "players.db not found: $playersDb" }
$players = @(Get-PZTPlayersInfo -PlayersDb $playersDb)
Write-Host ""
Write-Host "=== Players before reset ==="
if ($players.Count -gt 0) {
    $players | Select-Object id, world, username, playerIndex, name, steamid, isDead, x, y, z | Format-Table -AutoSize
}
else {
    Write-Host "No player rows found."
}

if ($WhatIf) {
    Write-PZTStep "WhatIf: no backup will be created and no row will be deleted." "pz-reset-hosted-player"
}
else {
    if (-not $ConfirmReset) {
        Write-PZTStep "Refusing real player reset without -ConfirmReset. Run with -WhatIf first, then add -ConfirmReset when the selected player is correct." "pz-reset-hosted-player"
        exit 1
    }
    $backupDir = New-PZTBackupDir -BackupRoot $paths.BackupRoot -Name "$ProfileName-players-db"
    Copy-Item -LiteralPath $playersDb -Destination (Join-Path $backupDir "players.db") -Force
    if (Test-Path -LiteralPath ($playersDb + "-journal")) {
        Copy-Item -LiteralPath ($playersDb + "-journal") -Destination (Join-Path $backupDir "players.db-journal") -Force
    }
    Write-PZTStep "Backup: $backupDir" "pz-reset-hosted-player"
}

$code = @"
import json, sqlite3, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    args = json.load(f)
db = args["db"]
profile = args["profile"]
username = args.get("username") or ""
player_index = int(args["player_index"])
what_if = bool(args["what_if"])

con = sqlite3.connect(db)
cur = con.cursor()
rows = cur.execute("select id, world, username, playerIndex, name, steamid, x, y, z, isDead from networkPlayers order by id").fetchall()
print("Players before:")
for row in rows:
    print(row)

if username:
    ids = [r[0] for r in cur.execute("select id from networkPlayers where world=? and username=? and playerIndex=?", (profile, username, player_index)).fetchall()]
else:
    ids = [r[0] for r in cur.execute("select id from networkPlayers where world=? and playerIndex=?", (profile, player_index)).fetchall()]

if not ids:
    raise SystemExit("No matching player row found.")
if len(ids) > 1:
    raise SystemExit(f"Multiple rows matched ({ids}). Pass -Username.")

if what_if:
    print("WhatIf: would delete networkPlayers.id =", ids[0])
else:
    cur.execute("delete from networkPlayers where id=?", (ids[0],))
    con.commit()
    print("Deleted networkPlayers.id =", ids[0])

rows = cur.execute("select id, world, username, playerIndex, name, steamid, x, y, z, isDead from networkPlayers order by id").fetchall()
print("Players after:")
for row in rows:
    print(row)
con.close()
"@

Invoke-PZTPythonJson -Code $code -InputObject @{ db = $playersDb; profile = $ProfileName; username = ($Username -as [string]); player_index = $PlayerIndex; what_if = [bool]$WhatIf }
