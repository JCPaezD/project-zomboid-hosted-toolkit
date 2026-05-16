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

Renaming a hosted profile safely means keeping those pieces consistent, but consistency is not the whole story.

## Profile Identity And Live Co-op Games

A hosted profile name is also part of the practical identity that clients see over time. In active co-op games, changing the name of the profile/save can make Project Zomboid treat the game like a different hosted identity on each player's machine.

That can detach or reset local client-side state such as:

- explored in-game map or minimap state;
- map symbols and thumbnails;
- `InGameMap.ini` view state;
- files under `Saves\Multiplayer\<profile>_player\`;
- Build 42 `map_visited_server` handoff behavior, depending on the game build.

For a valuable active co-op game, prefer this pattern:

1. Back up the current profile.
2. Keep the same active profile name.
3. Edit mods, sandbox, or server settings in place.
4. Keep version history in backup names, changelogs, or notes instead of renaming the live profile.

Use a new profile name mainly for:

- lab copies;
- forked experiments;
- disposable tests;
- migration work where every player understands that local client files may need manual handling.

The toolkit can rename/copy the host-side files it can see. It cannot automatically migrate client-local map state on another player's computer.

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
