# Dystopia

This repository contains the source code for Dystopia servers in No More Room in Hell.

Please note that the code is provided as-is. There may be some missing or incomplete files, and no support will be provided.

## Some hints

- `addons/sourcemod/scripting` - Contains the source code for most, if not all, of the unique functionality found in Dystopia.
- `addons/sourcemod/data/sourcemod-local.sq3` - Contains all statistics and player settings as of 11/19/23, with sensitive tables stripped out.

## Plugins

| Filename                | Brief description                                                                                                                                                                 |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `database-campaigns`    | Introduces the concept of "campaigns," combining maps and game modes with assigned points. Implements a vote system for campaigns.                                        |
| `breakable-hud`         | Displays remaining health on breakables.                                                                                                                                    |
| `chat_processor`        | Custom chat processor designed to work seamlessly with NMRiH.                                                                                                               |
| `connect_messages`      | Shows chat messages when someone joins or leaves the game.                                                                                                                  |
| `database-players`      | Registers all connecting players in a database, utilized by other plugins.                                                                                                  |
| `database-stats`        | Saves extensive gameplay statistics, including extractions, rankings, and categorizes them into "casual," "pro," and "no damage."                                            |
| `dead-cant-see-health`  | Prevents spectators from viewing health numbers or colors.                                                                                                                  |
| `dist`                  | Allows players to use `sm_dist` to limit their render distance.                                                                                                              |
| `dont-extract-dead`     | Fixes a bug granting extractions to dead players.                                                                                                                           |
| `forcedrop`             | Admin command `sm_drop` to force a player to drop an item.                                                                                                                  |
| `gamestyles`            | Legacy plugin enabling players to choose their game mode at the start of the round via `sm_mode`.                                                                          |
| `hide`                  | Lets players hide other players using `sm_hide`.                                                                                                                           |
| `hub_menu`              | Displays a menu listing various available commands.                                                                                                                         |
| `infect`                | Admin command `sm_infect` to infect a player.                                                                                                                               |
| `ipsleuth`              | Implements `sm_trace <name>` and `sm_traceid <accountid>` to identify a user's alternate accounts.                                                                         |
| `labcolors_new`         | Allows players to pick up to 15 colors for their name, supports gradients, and saves results to the database.                                                               |
| `manager_abra`          | Lets you control Abra Dungeon's difficulty through cvars.                                                                                                                  |
| `manager_dangerspot`    | Fixes softlocking issues with Danger Spot.                                                                                                                                  |
| `manager_fallout`       | Lets you control Fallout Limbo's difficulty through cvars.                                                                                                                 |
| `manager_kink`          | Provides landmine notifications for Kink.                                                                                                                                  |
| `manager_lux`           | Notifies about core actions in Lux Umbra.                                                                                                                                  |
| `manager_silenthill`    | Lets you control Silent Hills's difficulty through cvars.                                                                                                                 |
| `manager_subside`        | Work in progress to make the battery a hard requirement in Subside.                                                                                                        |
| `manager_tenki`         | Lets you control Tenki no Ko's stages through cvars.                                                                                                                       |
| `message-share`         | Allows saving and sharing messages via `sm_messages`.                                                                                                                      |
| `nmrih_afk`             | Prevents people from using binds to go AFK and allows graceful AFK through `sm_afk`.                                                                                      |
| `no-walkies`            | Removes all walkie-talkies from the game.                                                                                                                                  |
| `ragdoll-limiter`       | Allows turning off zombie ragdolls using `sm_ragdolls`.                                                                                                                    |
| `runners-only`          | Transforms all zombies into runners gracefully.                                                                                                                            |
| `shovescript`           | Attempts to detect players using shove scripts, though not very effective.                                                                                                 |
| `stats_nade`            | Legacy grenade stats.                                                                                                                                                      |
| `wr-discord-notifications` | Sends notifications to a Discord channel when someone achieves a new time record.                                                                                           |
