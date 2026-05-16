# Safe Operations

## Golden Rules

1. Close Project Zomboid before modifying profiles, saves, databases, or Workshop folders.
2. Back up before edits.
3. Prefer copying/moving whole profile-related sets together:

```text
Server\<profile>.*
Saves\Multiplayer\<profile>\
Saves\Multiplayer\<profile>_player\
db\<profile>.db
```

4. Do not use Workshop repairs to fix save/profile problems.
5. Do not use save deletion to fix Workshop errors.
6. Do not rewrite `.lua` or `.ini` files with tools that may insert UTF-8 BOM.
7. For active co-op games, keep the active profile name stable when possible. Use backups for version history.

## Recommended Flow Before Experiments

```powershell
.\pz-toolkit.ps1 audit
.\pz-toolkit.ps1 quick-diagnosis
.\pz-toolkit.ps1 health-check -ProfileName "MyHostedServer"
.\pz-toolkit.ps1 backup-profile -ProfileName "MyHostedServer"
.\pz-toolkit.ps1 verify-backup -BackupPath ".\backups\profile-MyHostedServer-20260101-120000"
```

If the profile is irreplaceable, copy the resulting backup to another drive.

Backups are written with `BACKUP_STATUS.txt`. If a backup is interrupted before completion, it should remain marked `INCOMPLETE` or lack a complete status. Do not rely on interrupted backups as restore points.

## Resetting a Test World

If a hosted profile has been used only for testing and you want the next launch to generate a fresh world:

```powershell
.\pz-toolkit.ps1 reset-world -ProfileName "MyHostedServer" -WhatIf
.\pz-toolkit.ps1 reset-world -ProfileName "MyHostedServer" -ConfirmReset
```

This moves the save folder, optional `_player` folder, and optional `db\<profile>.db` into a timestamped backup. It does not modify `Server\<profile>.*`.

Do not run this on a valuable world unless you are intentionally removing that world from the active game folder and relying on the generated backup.

## Restoring or Copying a Backup

Restore/copy always starts with `-WhatIf`:

```powershell
.\pz-toolkit.ps1 restore-profile -BackupPath ".\backups\profile-MyHostedServer-20260101-120000" -WhatIf
```

To copy a backup into a new profile name for a lab/fork copy:

```powershell
.\pz-toolkit.ps1 restore-profile -BackupPath ".\backups\profile-MyHostedServer-20260101-120000" -TargetProfileName "MyHostedServer_Copy" -WhatIf
```

If the target already exists, the restore refuses to continue unless `-Overwrite` is passed. When `-Overwrite` is used, the current target is backed up first.

When copying to a new profile name, `restore-profile` renames the restored server files, save folder, optional `_player` folder, profile database, and hosted player `world` rows in `players.db`. It also updates `PublicName` when the old value exactly matches the source profile name.

Do not treat that as a fully transparent rename for a valuable live co-op game. Other players can have client-local folders tied to the old hosted profile identity. Those folders may contain explored map data, symbols, thumbnails, `InGameMap.ini`, or other per-client files the host cannot migrate automatically.

Recommended interpretation:

- same target profile name: restore/recover the active identity;
- new target profile name: lab copy, fork, disposable test, or advanced migration;
- live co-op mod/config change: back up, then edit the same profile in place.

Real direct-script restore/copy/reset operations require explicit confirmation flags after you review `-WhatIf` output:

```powershell
.\pz-toolkit.ps1 restore-profile -BackupPath ".\backups\profile-MyHostedServer-20260101-120000" -TargetProfileName "MyHostedServer_Copy" -ConfirmRestore
.\pz-toolkit.ps1 copy-world -SourceProfileName "SourceProfile" -TargetProfileName "TargetProfile" -Overwrite -ConfirmCopy
.\pz-toolkit.ps1 copy-players -SourceProfileName "SourceProfile" -TargetProfileName "TargetProfile" -Overwrite -ConfirmCopy
.\pz-toolkit.ps1 reset-player -ProfileName "MyHostedServer" -Username "SteamName" -PlayerIndex 0 -ConfirmReset
```

`restore-profile` refuses to restore backups whose `BACKUP_STATUS.txt` is not `COMPLETE`, unless you add `-AllowIncompleteBackup` for a deliberate manual rescue.

## Encoding Safety

Some PZ Lua/config files may fail to load if they start with UTF-8 BOM:

```text
EF BB BF
```

The audit tool checks profile `.ini` and `SandboxVars.lua` files for BOM.

If you need to edit values programmatically, prefer byte-preserving replacement or explicit BOM-free writes.

## Client Global Mods

After using the in-game Mods menu for sorting or testing, check:

```powershell
.\pz-toolkit.ps1 audit
```

If `ClientMods.ActiveModLines` is greater than zero and you are about to host a server, consider:

```powershell
.\pz-toolkit.ps1 clear-client-mods -WhatIf
.\pz-toolkit.ps1 clear-client-mods -ConfirmClear
```
