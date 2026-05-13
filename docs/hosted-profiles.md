# Hosted Profiles

A hosted profile name is more than a UI label. It commonly appears in:

```text
Server\<profile>.ini
Server\<profile>_SandboxVars.lua
Server\<profile>_spawnpoints.lua
Server\<profile>_spawnregions.lua
Saves\Multiplayer\<profile>\
Saves\Multiplayer\<profile>_player\
db\<profile>.db
players.db.networkPlayers.world
db.whitelist.world
```

Renaming a hosted profile safely means keeping those pieces consistent.

## Profile Export

Use:

```powershell
.\tools\pz-export-profile.ps1 -ProfileName "MyHostedServer"
```

This creates:

```text
<profile>-mods.txt
<profile>-workshopitems.txt
<profile>-map.txt
<profile>-workshop-checklist.csv
<profile>-summary.md
```

The client does not need to paste the `Mods=` string. The host's profile advertises the required Workshop items and ModIDs during connection.

## Steam Collections

For large mod packs, the reliable flow is:

1. Host creates or shares a Steam collection containing the required Workshop items.
2. Client subscribes before joining.
3. Client waits for Steam downloads to finish.
4. Client does not activate the whole pack globally in the Mods menu.
5. Client joins the hosted server.

Extra subscribed Workshop items are usually harmless if they are not loaded globally and not required by the server profile.
