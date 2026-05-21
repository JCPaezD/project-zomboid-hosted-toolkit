# Troubleshooting Patterns

## Hosted Server Terminates During Workshop Redownload

Common log patterns:

```text
GetItemState()=Installed|NeedsUpdate ID=<WorkshopID>
Installed status but timeUpdated doesn't match
FileSystemException: ... .jar ... used by another process
onItemNotDownloaded itemID=<WorkshopID> result=33
UI_ServerStatus_Terminated
```

First checks:

1. Close PZ.
2. Check for leftover Project Zomboid / ZombieBuddy / Java processes.
3. Wait for Steam downloads to finish.
4. Check whether `Zomboid\mods\default.txt` has active mods.
5. Use quick diagnosis and latest-error.

Only use `pz-repair-workshop-redownload.ps1` when logs indicate a Workshop item update/cache problem and Steam has prepared a download folder.

With the command hub:

```powershell
.\pz-toolkit.ps1 quick-diagnosis
.\pz-toolkit.ps1 errors -ServerOnly
.\pz-toolkit.ps1 repair-workshop -WhatIf
.\pz-toolkit.ps1 repair-workshop -ConfirmRepair
```

If `quick-diagnosis` reports `Workshop update lock`, the most likely cause is that PZ, ZombieBuddy, Java, or Steam was trying to update a Workshop item while a JAR/file from that item was still loaded. Close those processes, wait a short moment for Steam to finish, and retry hosting once before doing any manual repair.

If `repair-workshop` says no `Installed|NeedsUpdate` item was found, that is a normal "nothing to repair" result. Inspect the log summary instead of repeating the repair.

If `repair-workshop` says the prepared download folder was not found, the staged Steam/PZ download has already been cleaned up or applied. Close PZ/ZombieBuddy/Java, retry hosting once, and re-run latest-error if it blocks again. The repair can only swap folders while `workshop\downloads\108600\<id>` still exists.

If the issue happens after a long session and another player sees a mod-version mismatch, treat it as a sync/update problem first: stop hosting, have every player close PZ, let Steam finish Workshop updates, then relaunch the host. Only suspect save corruption if logs also show chunk, CRC, saved-object, or repeated runtime errors after the Workshop state is clean.

## Client Fails To Subscribe To A Workshop Item

Common client-side symptoms:

- the join screen shows a required mod as unnamed, `0MB`, or not subscribed;
- PZ says it failed to subscribe to a Workshop item;
- one player cannot download a required mod while the host and other players can.

Useful log patterns:

```text
GetItemState()=None ID=<WorkshopID>
SubscribePending ID=<WorkshopID>
onItemNotSubscribed itemID=<WorkshopID> result=<code>
SubscribePending -> Fail ID=<WorkshopID>
```

This is different from a host-side Workshop redownload/cache issue. There may be no local `workshop\downloads\108600\<id>` folder to repair. The item may have been removed from Workshop, made private, blocked by Steam, or temporarily unavailable to that client's account/region/cache.

First checks:

1. Ask the affected player for `console.txt` or the latest `DebugLog.txt`.
2. Run `quick-diagnosis` or `latest-error` against those logs if copied locally.
3. Open `https://steamcommunity.com/sharedfiles/filedetails/?id=<WorkshopID>`.
4. If the item is removed/private/unavailable, back up first, then remove or replace that Workshop ID in the hosted profile and collection. For live saves, test the removal/replacement on a copy when possible.
5. If the item still exists, have the affected player close PZ, restart Steam, wait for downloads, and subscribe manually from the Workshop page.

Do not use `repair-workshop` for this pattern. `repair-workshop` intentionally handles only staged redownload/cache folders for already resolvable Workshop items.

## Client Global Mods Block Hosted Server Updates

The in-game single-player Mods menu can leave active mods in:

```text
Zomboid\mods\default.txt
```

Those mods may preload before the Host flow, including Java/helper mods. When PZ then tries to update Workshop files for a hosted server, locked files can cause repeated `reinstalling`, `redownloading`, or `terminated` behavior.

Use:

```powershell
.\pz-toolkit.ps1 clear-client-mods -WhatIf
.\pz-toolkit.ps1 clear-client-mods -ConfirmClear
```

This does not unsubscribe from Workshop items. It clears the global client preload list.

## Problem Chunks / blam Folder

Build 42 may move chunks that failed to load into a save-local `blam` folder. Typical signals:

```text
CRC mismatch
SANITY CHECK FAIL
Error loading chunk <wx>,<wy>
```

Use:

```powershell
.\pz-toolkit.ps1 inspect-blam -ProfileName "MyHostedServer"
.\pz-toolkit.ps1 errors -ServerOnly -IncludeMapLogs
```

Do not delete or restore chunks directly in a valuable save. Back up first and test any repair idea in a copied profile.

## Delete Player Fails in the Host UI

Observed pattern:

```text
user database doesn't exist
Lua(Vanilla).onDeletePlayerStep2(CoopOptionsScreen.lua:464)
NullPointerException ... ServerWorldDatabase.removeUser
```

The UI may fail before it deletes the hosted player row. Inspect:

```text
Saves\Multiplayer\<profile>\players.db
```

Use:

```powershell
.\pz-toolkit.ps1 reset-player -ProfileName "MyHostedServer" -Username "SteamName" -PlayerIndex 0 -WhatIf
```

Only run the real reset after reviewing the preview:

```powershell
.\pz-toolkit.ps1 reset-player -ProfileName "MyHostedServer" -Username "SteamName" -PlayerIndex 0 -ConfirmReset
```

## RV / Camper Interior Sends Player to Woods

Likely cause: the mod is loaded, but the required interior map directories are missing from `Map=`.

Export and inspect:

```powershell
.\pz-toolkit.ps1 export-profile -ProfileName "MyHostedServer"
```

Then compare the profile's `Map=` against map directories provided by the relevant RV/interior mods.

## A Mod Pack Works for Others but Not Locally

Check these before removing random mods:

1. Does `Mods=` include the correct ModIDs?
2. Does `WorkshopItems=` include the matching Workshop IDs?
3. Is `Map=` complete and ordered correctly?
4. Is `default.txt` empty or at least not preloading a different pack?
5. Are any Java mods locked by ZombieBuddy/PZ?
6. Are there BOM/encoding issues in profile files?
7. Are logs pointing at one specific mod, file, script, or fluid/item definition?

## Changing Mods Mid-Save

Removing mods from a live save can leave saved objects, mod data, items, vehicles, UI state, or world systems behind. The risk depends on what the mod added.

Safer workflow:

1. Back up the active profile.
2. Restore/copy it under a test name.
3. Remove the mod from the copied profile.
4. Launch and test in the copied profile.
5. Only repeat on the active profile if the copied profile behaves correctly.

Use `compare-mods` to document exactly what changed between versions.
