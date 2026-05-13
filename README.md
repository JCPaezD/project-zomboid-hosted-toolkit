# PZ Hosted Toolkit

Safe diagnostics and maintenance tools for **modded Project Zomboid hosted/co-op servers** on Windows.

This project targets the servers launched from the in-game **Host** menu. It is built for the messy middle where casual co-op hosts start using Steam Workshop mods and suddenly need to understand profiles, saves, Workshop caches, logs, players, and backups without deleting folders blindly.

```text
PZ Hosted Toolkit
Safe diagnostics and maintenance for Project Zomboid hosted/co-op profiles.
Use WhatIf/dry-run first for repair, reset, copy, restore, and cleanup actions.

  Inspect & Diagnose                 Backup & Recovery
  > Quick diagnosis                  Backup hosted profile
    Inspect hosted profile           Verify backup
    Health check profile             Restore profile backup
    Find latest errors
    Inspect BLAM chunks              Compare & Transfer
                                      Compare sandbox
  Workshop & Mods                    Compare mods
    Clear client mods                Copy world/save
    Repair Workshop redownload       Copy players

  Up/Down: move    ENTER: run    H: help    Q/Esc: quit
```

## What It Helps With

- Finding where hosted profiles, saves, players, databases, logs, and client mod state live.
- Running a quick read-only diagnosis before touching files.
- Backing up a hosted profile before changing mods, sandbox settings, players, or world data.
- Verifying toolkit-created backups before relying on them.
- Restoring a backup to the original hosted profile or to a new profile name.
- Inspecting hosted profile files, mods, maps, save size, player rows, and recent state.
- Comparing active mods, Workshop IDs, map lists, and sandbox settings between profiles.
- Exporting mod, Workshop, map, server setting, sandbox, and player summaries for review.
- Clearing the global client mod list left by the single-player Mods menu.
- Diagnosing common Workshop update/redownload/reinstalling failures.
- Repairing a narrow Workshop staged-download case safely when the required cache exists.
- Inspecting Build 42 `blam` chunk-load markers without touching the save.
- Copying world/save data or player data between existing hosted profiles with backups.
- Resetting one hosted player or one hosted world intentionally instead of deleting random files.

## What It Is Not

- Not a Project Zomboid mod.
- Not a mod manager or Steam collection manager.
- Not a dedicated server control panel.
- Not a GUI application.
- Not a magic compatibility checker for mod packs.
- Not a replacement for keeping real backups.

## Safety Model

The toolkit is built around a simple rule:

> Audit first. Back up before edits. Touch the smallest possible file set. Keep every operation reversible when possible.

Most write-capable scripts support `-WhatIf`, create a backup, ask for confirmation, or refuse to run when Project Zomboid, Java, or related helper processes are still open. Scripts print a title banner at startup so interactive users can see which operation is running.

The toolkit is plain PowerShell: no opaque executable, no Steam login, and no automatic upload of your files.

The `.cmd` wrappers use PowerShell's `-ExecutionPolicy Bypass` only for that local process. This avoids changing your global Windows execution policy; it does not grant administrator rights or download code. You can always run `.\pz-toolkit.ps1` directly from PowerShell instead.

## Requirements

- Windows PowerShell 5.1 or newer.
- Project Zomboid installed through Steam.
- Hosted/co-op profiles launched from the in-game **Host** menu.
- Python available in `PATH` for SQLite operations involving `players.db`.
- `robocopy`, included with Windows, for save-folder backups.

Tested primarily with **Project Zomboid Build 42 hosted/co-op profiles** on Windows. Some tools may also help with Build 41 layouts, but Build 41 is not the primary test target for v0.1.

## Quick Start

Open PowerShell in this folder:

```powershell
cd .\project-zomboid-hosted-toolkit
```

For the guided menu:

```powershell
.\pz-toolkit.ps1
```

Or double-click:

```text
scripts\toolkit.cmd
```

For the initial Spanish interactive layer:

```text
scripts\toolkit-es.cmd
```

This localizes the guided menu and many human-facing prompts while keeping command names, file names, and technical categories mostly in English.

If you are not comfortable with PowerShell, start with [docs/first-run-guide.md](docs/first-run-guide.md).

## Common Workflows

Run a read-only diagnosis:

```powershell
.\pz-toolkit.ps1 quick-diagnosis
```

Health-check one hosted profile:

```powershell
.\pz-toolkit.ps1 health-check -ProfileName "MyHostedServer"
```

Audit the local PZ state:

```powershell
.\pz-toolkit.ps1 audit
```

Back up a hosted profile before experimenting:

```powershell
.\pz-toolkit.ps1 backup-profile -ProfileName "MyHostedServer"
```

Backups are marked `INCOMPLETE` at the start and `COMPLETE` at the end. Verify a backup before relying on it:

```powershell
.\pz-toolkit.ps1 verify-backup -BackupPath ".\backups\profile-MyHostedServer-20260101-120000"
```

Inspect a hosted profile:

```powershell
.\pz-toolkit.ps1 inspect-profile -ProfileName "MyHostedServer"
```

Export mod/map/server/player information for a profile:

```powershell
.\pz-toolkit.ps1 export-profile -ProfileName "MyHostedServer"
.\pz-toolkit.ps1 export-profile -ProfileName "MyHostedServer" -OutputDir "ShareableExportName"
```

By default exports go to `.\exports\<ProfileName>`. If `-OutputDir` is a simple name, it goes to `.\exports\<OutputDir>`. Absolute paths or paths with `\` or `/` are treated as explicit paths. The export includes mod, Workshop, map, server setting, a raw copy of `SandboxVars.lua`, Workshop checklist, and player CSV files when those data sources are available.

Clear the client global mod list after using the single-player Mods menu:

```powershell
.\pz-toolkit.ps1 clear-client-mods -WhatIf
.\pz-toolkit.ps1 clear-client-mods
```

Restore a profile backup, or copy it into a new hosted profile:

```powershell
.\pz-toolkit.ps1 restore-profile -BackupPath ".\backups\profile-MyHostedServer-20260101-120000" -WhatIf
.\pz-toolkit.ps1 restore-profile -BackupPath ".\backups\profile-MyHostedServer-20260101-120000" -TargetProfileName "MyHostedServer_Copy" -WhatIf
```

When copying to a new profile name, the restore tool renames the server files, save folder, optional `_player` folder, profile database, and `players.db` world rows. If `PublicName` exactly matches the source profile name, it is updated too. Real restore operations require `-ConfirmRestore` after you review `-WhatIf` output.

Find recent known error patterns:

```powershell
.\pz-toolkit.ps1 errors -ServerOnly
.\pz-toolkit.ps1 errors -ServerOnly -IncludeMapLogs
```

Compare sandbox settings between profiles:

```powershell
.\pz-toolkit.ps1 compare-sandbox -LeftProfile "BaseProfile" -RightProfile "TargetProfile"
.\pz-toolkit.ps1 compare-sandbox -LeftProfile "BaseProfile" -RightProfile "TargetProfile" -IncludeProfileOnlyDetails
.\pz-toolkit.ps1 compare-sandbox -LeftProfile "BaseProfile" -RightProfile "TargetProfile" -OutputCsv ".\exports\sandbox-diff.csv"
```

Compare mod, Workshop, and map lists between profiles:

```powershell
.\pz-toolkit.ps1 compare-mods -LeftProfile "OldProfile" -RightProfile "NewProfile"
.\pz-toolkit.ps1 compare-mods -LeftProfile "OldProfile" -RightProfile "NewProfile" -Detailed
```

Inspect Build 42 `blam` / problem chunk markers:

```powershell
.\pz-toolkit.ps1 inspect-blam -ProfileName "MyHostedServer"
```

Copy world/save data or players between profiles:

```powershell
.\pz-toolkit.ps1 copy-world -SourceProfileName "SourceProfile" -TargetProfileName "TargetProfile" -WhatIf
.\pz-toolkit.ps1 copy-players -SourceProfileName "SourceProfile" -TargetProfileName "TargetProfile" -WhatIf
```

Reset one hosted player:

```powershell
.\pz-toolkit.ps1 reset-player -ProfileName "MyHostedServer" -Username "SteamName" -PlayerIndex 0 -WhatIf
.\pz-toolkit.ps1 reset-player -ProfileName "MyHostedServer" -Username "SteamName" -PlayerIndex 0 -ConfirmReset
```

Reset the world/save data for a selected hosted profile while keeping the server profile:

```powershell
.\pz-toolkit.ps1 reset-world -ProfileName "MyHostedServer" -WhatIf
.\pz-toolkit.ps1 reset-world -ProfileName "MyHostedServer" -ConfirmReset
```

Repair a specific Workshop redownload/cache case:

```powershell
.\pz-toolkit.ps1 repair-workshop -WhatIf
```

You can still call any script directly under `tools\` if you prefer. The root `pz-toolkit.ps1` hub supports both modes:

- interactive mode for common manual operations and profile/backup selection;
- command mode for repeatable examples, documentation, scripts, and tests.

The interactive menu and profile/backup pickers use Up/Down plus Enter for normal navigation, with `H` for help and `Q`/Esc to quit in the main menu.

## Tools

| Tool | Purpose |
| --- | --- |
| `tools/pz-audit.ps1` | Print paths, running game processes, hosted profiles, client global mods, BOM checks, and optional Workshop summary. |
| `tools/pz-quick-diagnosis.ps1` | Run a read-only, high-level diagnosis with OK/Warning/Needs attention findings. |
| `tools/pz-inspect-profile.ps1` | Inspect one hosted profile: profile files, counts, storage, mod/map previews, and hosted player rows. |
| `tools/pz-health-check.ps1` | Check one profile for obvious file, save, BOM, and list consistency issues. |
| `tools/pz-inspect-blam.ps1` | Inspect `Saves\Multiplayer\<profile>\blam` for chunk load failures and explain safe next checks. |
| `tools/pz-backup-profile.ps1` | Back up `Server\<profile>.*`, `Saves\Multiplayer\<profile>`, `<profile>_player`, and `db\<profile>.db`. |
| `tools/pz-verify-backup.ps1` | Check whether a toolkit backup is marked complete and contains the expected profile/save/db pieces. |
| `tools/pz-restore-profile.ps1` | Restore a profile backup to its original name or copy it into a new profile name. |
| `tools/pz-export-profile.ps1` | Export `Mods`, `WorkshopItems`, `Map`, server settings, sandbox, Workshop checklist, and player CSV data. |
| `tools/pz-clear-client-mods.ps1` | Back up and clear `Zomboid\mods\default.txt` so single-player active mods do not preload before Host. |
| `tools/pz-reset-hosted-player.ps1` | Delete one row from `Saves\Multiplayer\<profile>\players.db.networkPlayers` after backup. |
| `tools/pz-reset-hosted-world.ps1` | Move the selected profile's world/player/db out of the game so the next launch starts fresh. |
| `tools/pz-compare-sandbox.ps1` | Compare simple key/value paths in two hosted `SandboxVars.lua` files, summarizing profile-only/mod sections by default. |
| `tools/pz-compare-mods.ps1` | Compare `Mods`, `WorkshopItems`, and `Map` lists between two hosted profiles, with compact defaults and detailed mode. |
| `tools/pz-copy-world.ps1` | Copy one profile's save/world data into another existing profile, with safety backup on overwrite. |
| `tools/pz-copy-players.ps1` | Copy hosted player rows and optional `_player` folder from one profile to another. |
| `tools/pz-find-latest-error.ps1` | Search latest PZ logs for common failure patterns. |
| `tools/pz-repair-workshop-redownload.ps1` | Conservative repair for `Installed|NeedsUpdate` plus prepared Workshop download cache. |

## Safety Levels

| Area | Default behavior |
| --- | --- |
| Diagnosis and inspection | Read-only. |
| Backup and export | Writes only under toolkit `backups\` or `exports\` unless an explicit path is provided. |
| Restore/copy/reset | Supports `-WhatIf`; real direct-script operations require explicit confirmation flags such as `-ConfirmRestore`, `-ConfirmCopy`, or `-ConfirmReset`. |
| Workshop repair | Narrow repair only; use `-WhatIf` first and close PZ/Steam helper processes before writing. |

## Testing

Run automated smoke tests against generated fake Zomboid/Workshop folders:

```powershell
.\tests\run-smoke-tests.ps1
```

Contributors can run automated smoke tests before changing toolkit behavior:

```powershell
.\tests\run-smoke-tests.ps1
```

## What Lives Where

Default Windows paths:

```text
%USERPROFILE%\Zomboid\Server\<profile>.ini
%USERPROFILE%\Zomboid\Server\<profile>_SandboxVars.lua
%USERPROFILE%\Zomboid\Saves\Multiplayer\<profile>\
%USERPROFILE%\Zomboid\Saves\Multiplayer\<profile>_player\
%USERPROFILE%\Zomboid\Saves\Multiplayer\<profile>\players.db
%USERPROFILE%\Zomboid\db\<profile>.db
%USERPROFILE%\Zomboid\mods\default.txt
%USERPROFILE%\Zomboid\Logs\
<SteamLibrary>\steamapps\workshop\content\108600\
<SteamLibrary>\steamapps\workshop\downloads\108600\
```

See [docs/where-things-live.md](docs/where-things-live.md).

## Feedback And Issues

Feedback is welcome. If the toolkit helps you, fails somewhere, or misses a common Project Zomboid hosted-server problem, please open an issue.

Helpful issue reports include:

- Project Zomboid version and build.
- Windows and PowerShell version.
- Whether this is in-game Host/co-op or another server setup.
- The action you ran and whether you used `-WhatIf`.
- Relevant log excerpts or toolkit output.
- Whether Project Zomboid, Steam, Java, or mod helper tools were open.

Please remove private data before posting logs or exports: usernames, Steam IDs, private paths, server names, IPs, and personal save data.

See [docs/privacy.md](docs/privacy.md) for a short redaction checklist.

## Important Caveats

- Hosted servers and dedicated servers have different operational shapes. These scripts target hosted/co-op profiles.
- Subscribing to extra Workshop items is usually harmless. Loading extra mods in a server profile is not.
- The in-game Mods menu can leave a global client mod list active in `mods\default.txt`; this can preload Java mods and block updates.
- `players.db` stores hosted MP player rows. The in-game Delete Player flow can fail before deleting those rows in some Build 42 cases.
- Some PZ files are encoding-sensitive. Avoid tools that rewrite `.lua`/`.ini` with UTF-8 BOM.
- Modded saves can behave unpredictably after adding, removing, or updating mods. Always keep a backup you can restore.

## Roadmap

- Improve diagnostics for common Workshop/update failures.
- Expand safe hosted profile, world, and player maintenance flows.
- Add more automated tests and sample fixtures.
- Improve support/debug exports for issue reports.
- Polish documentation from real hosted/co-op troubleshooting cases.

## Status

v0.1-alpha stabilization. Built from a real hosted-server troubleshooting session and generalized into a conservative toolkit. Review carefully before using on valuable saves.

## License

MIT. See [LICENSE](LICENSE).
