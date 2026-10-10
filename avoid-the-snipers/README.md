# Avoid the Snipers (Roblox)

A server-authoritative, team-based sniper game for Roblox. Two teams, Green and Brown, hide in a jungle valley. A camo menu runs before each round. Birds give away campers. Coins buy tactics and cosmetics in a supply-crate shop.

All tunable values are in **`ReplicatedStorage/GameConfig`**.

---

## 1. Put it into the place you have open in Studio

The `build/models/` folder has 5 model files. In Studio's **Explorer**, right-click the service in the table → **Insert from File...** → pick the file:

| # | File | Right-click this in Explorer |
|---|---|---|
| 1 | `1_ReplicatedStorage_GameConfig.rbxmx` | **ReplicatedStorage** |
| 2 | `2_ReplicatedStorage_Shared.rbxmx` | **ReplicatedStorage** |
| 3 | `3_ServerScriptService_AvoidTheSnipers_Server.rbxmx` | **ServerScriptService** |
| 4 | `4_StarterPlayerScripts_AvoidTheSnipers_Client.rbxmx` | **StarterPlayer > StarterPlayerScripts** |
| 5 | `5_StarterPlayerScripts_RbxCharacterSounds.rbxmx` | **StarterPlayer > StarterPlayerScripts** (it must sit directly inside, not in a folder) |

You should end up with:

```
ReplicatedStorage
├── GameConfig                    (ModuleScript)  all settings
└── Shared                        (Folder)
    ├── Remotes, CamoData, ShopCatalog, SoundUtil   (ModuleScripts)
ServerScriptService
└── AvoidTheSnipers_Server        (Folder)
    ├── Main                      (Script)  starts everything
    └── Services                  (ModuleScripts)
        RoundManager, CamoManager, BirdSystem, MovementService, SniperService,
        DamageService, SafeZoneService, ShopService, ItemService, DataService,
        TeamManager, MapBuilder, RoundState
StarterPlayer
└── StarterPlayerScripts
    ├── RbxCharacterSounds        (LocalScript, empty; turns off default footsteps)
    └── AvoidTheSnipers_Client    (Folder)
        ├── ClientMain            (LocalScript)  starts every controller
        └── Controllers           (ModuleScripts)
            MovementController, SniperClient, HudController, CamoMenu, ShopUI,
            MainMenu, BirdEffects, SpectateController, NameTagController,
            ItemClient, Zoom, UIUtil
ServerStorage
└── Weapons                       (Folder)  you create this, see step 3
StarterGui                        empty on purpose (UI is built by code so it
                                   never duplicates when you respawn)
```

**Other setup steps:**

1. **Game Settings > Avatar**: set **Avatar Type = R15**. The crouch pose bends R15 leg joints.
2. **Game Settings > Security**: turn on **Enable Studio Access to API Services**. Without it, DataStores (coins, kills and wins) don't save in Studio.
3. **Sniper (official Weapons Kit):**
   1. Open Toolbox → Models.
   2. Search for **"Weapons Kit"** by **Roblox** (look for the verified Roblox badge).
   3. Insert it and find the **Sniper** tool inside it.
   4. In **ServerStorage**, create a Folder named **`Weapons`**. Move the sniper Tool into it and rename the Tool to **`SniperRifle`**.
   5. Delete the rest of the kit, including any `WeaponsSystem` folder it added to ReplicatedStorage.

   When the game hands out the rifle, it removes the kit's scripts and keeps its model and fire sound. Damage, headshots and validation all run in `SniperService`, using GameConfig values. If `SniperRifle` is missing, a simple built-in rifle is used and the Output window warns you.
4. The Baseplate and any template SpawnLocation are removed or disabled automatically while the game runs, so you don't have to delete them. Deleting them anyway stops the Output message.
5. You don't need to set anything else. `Main` sets `Players.CharacterAutoLoads = false` and turns off shift-lock (Shift is sprint).

> Using Rojo instead? `rojo serve default.project.json` syncs `src/` into Studio. `build/AvoidTheSnipers.rbxlx` is the full place file, ready to open.

---

## 2. How it fits together (server-authoritative)

- **The client only sends requests:**
  - `PlayerReady`
  - `SelectCamo(name)`
  - `SetStance(stance)`
  - `FireSniper(direction, part, position)`
  - `ShopBuy(itemId)`
  - `UseItem(itemId, aim)`
- **The server validates every request.** It checks types, round phase, that the player is alive and holding the right tool, cooldowns, range, ownership and coins.
- **The server alone decides** damage, kills, camo, coins, birds, safe zones and round state.
- **Clients read the round state** from attributes on `ReplicatedStorage.GameStatus`: `State`, `EndsAt`, `GreenAlive`, `BrownAlive`, `ResultText`.
- **Shots:** the server raycasts from the shooter's **head** to the claimed hit point, so walls and rocks block it. It accepts the client's target only if the path is clear and the target is within `SNIPER_HIT_TOLERANCE`, which allows for lag. Damage depends on the body part hit: head, body or limb.
- **Bushes, tall grass, tree canopies and smoke** have `CanQuery = false`. They block sight, not bullets. Rocks, logs, walls and ruins stop bullets.

---

## 3. Phase-by-phase testing in Studio

For "2+ players", use **Test tab → Clients and Servers → 2 Players (or 3) → Start**. This opens a server window plus one window per player. Set the player count before pressing Start. In every client window, press **PLAY** on the main menu, because only players who pressed Play join rounds.

To test faster, temporarily lower times in GameConfig, e.g. `ROUND_TIME = 60`, `STILLNESS_WARNING_TIME = 5`, `STILLNESS_DANGER_TIME = 10`.

### Phase 1 – Teams, spawns, round loop
- **Files:** `RoundManager`, `RoundState`, `TeamManager`, `DamageService`, `SafeZoneService`, `HudController`, `SpectateController`.
- **Solo test.** Press **Play** (single player) → click **PLAY**. The top bar says "Waiting for players (1/2)" and you stand on the floating lobby platform.
- **Team test.** Run **2 Players**:
  1. Within a second both clients go into **Camo selection**. One player is on each team and each spawns frozen inside their own ruin house, one at each end of the map.
  2. After the camo timer the round starts. The bar shows the timer and `GREEN 1 / 1 BROWN`.
  3. In the **server** window, run this in the command bar:
     `game.Players:GetPlayers()[1].Character.Humanoid.Health = 0`
  4. Check that the dead player gets the spectate bar. It should say "No teammates left" in a 1v1, and should show teammates only in a 3-player test.
  5. Check that the round ends right away with "Team X wins! (All enemies eliminated)".
  6. Check that ~6 s later everyone is back in the lobby with their normal avatar, and a new round starts after the intermission.
- **Timer win / draw.** Let the timer run out with both alive. Expect "Draw!".
- **Spawn protection.** In the first 3 s of a round, shoot a player who is still inside their house. No damage is dealt.
- **Enemy safe zone.** Walk into the enemy house. A red warning appears and health drops by 20 per second.

### Phase 2 – Camo selection
- **Files:** `CamoManager`, `CamoMenu`, `CamoData`, `NameTagController`.
- **Menu and preview.** With 2 players, the camo menu shows 5 swatch buttons. Clicking one recolors your character instantly; check from the other window too.
- **Default camo.** Don't click anything. When the timer ends you are given **Jungle**.
- **Avatar cleanup.** Hats, hair and clothing are gone, and a small armband sits on the left upper arm (green or brown).
- **Name tags.** You can't see the enemy's name or health bar. In a **3-player** test, the two teammates see each other's names.
- **Server validation.** In a client's command bar (Studio lets clients run code there), run:
  `game.ReplicatedStorage.Remotes.SelectCamo:FireServer("Temple Stone")`
  without owning that camo. Nothing changes, because the server rejects it.
- **Avatar restore.** After the round, avatars are back to normal in the lobby.

### Phase 3 – Sniper
- **Files:** `SniperService`, `SniperClient`, `Zoom`.
- **Rifle.** At round start each player holds the rifle, which is auto-equipped.
- **Scope.** Hold **right mouse** or press **Q** to scope. You get the black scope overlay and lower mouse sensitivity.
- **Damage.** Shoot the other player:
  - Head → 100, an instant kill.
  - Torso → 60.
  - Arm or leg → 35.
  - Watch `Humanoid.Health` in the server Explorer.
- **Feedback.** Every shot shows a tracer and a loud gunshot in **both** windows. Hits show a hit marker, which is red for a headshot or kill.
- **Kill feed.** It shows only "X eliminated Y".
- **Cover.** Shooting through a rock or ruin wall does no damage. Shooting through tall grass or a bush does.
- **Cleanup.** The rifle disappears when the round ends.

### Phase 3B – Coins and shop
- **Files:** `ShopService`, `ItemService`, `ShopUI`, `ItemClient`, `ShopCatalog`, `DataService`.
- **Give coins.** In the server command bar:
  `require(game.ServerScriptService.AvoidTheSnipers_Server.Services.DataService).AddCoins(game.Players:GetPlayers()[1], 1000)`
- **Open the shop.** In the first 20 s of a round, walk to the rusty crate at the back of your house → **Open Shop**.
  - The enemy crate's prompt is hidden on your screen. If triggered anyway, the server refuses.
  - After 20 s the prompt disappears and the window closes.
- **Binoculars.** Click to zoom.
- **Bird Whistle.** Aim and click. A flock appears there in both windows.
- **Smoke Grenade.** Aim and click. Gray cloud for 8 s.
- **Bandage.** Take damage, stand still and click → +40 HP over 3 s. Moving cancels it, and the bandage is kept.
- **Permanent unlocks.**
  1. Buy **Bamboo Camo**. It appears in the next camo menu.
  2. Buy a **skin**. The rifle recolors to a muted color.
- **Kill coins.** Kill → +25, or +40 for a headshot.
- **Round-end coins.** Surviving → +20. Winning team → +50 each.
- **Saving.** Leave and rejoin (needs API access on). Coins, owned camos and skins are still there.

### Phase 4 – Movement
- **Files:** `MovementController` (client), `MovementService` (server), `RbxCharacterSounds`.
- **Walk.** Speed 12, with quiet footsteps.
- **Sprint.** Hold **Shift** → speed 20 with loud rustling. The other window hears it from up to ~90 studs.
- **Crouch.** Hold **C** or **Ctrl** → speed 6. The character kneels and drops lower, makes no sound, and can't jump.
- **Mobile.** In Studio use **Test → Device emulator** (pick a phone) and press Play. You get **Crouch**, **Sprint** and **Scope** buttons, which toggle.
- **Server validation.** In the client command bar, run:
  `game.ReplicatedStorage.Remotes.SetStance:FireServer("Fly")`
  It is ignored.

### Phase 5 – Birds
- **Files:** `BirdSystem` (server), `BirdEffects` (client).
- **Setup.** Use the short stillness times above, with 2 players in a round, and have one player stand still:
  - At 20 s, 3-4 birds fly up ~25 studs away with flapping, seen in **both** windows, and you get a small 🐦 hint.
  - At 40 s, 8-10 birds fly up ~8 studs away with crow calls. This repeats every 10 s.
  - Moving 2+ studs resets the timer. Shuffling in place does not.
- **Sprinting.** Sprint around inside tall grass. Now and then 1-2 birds pop up near you.
- **Timer stays hidden.** The stillness timer is never shown to the player.

### Phase 6 – Map
- **File:** `MapBuilder`. It builds terrain, both ruin houses, the middle zone, the boundaries, the lobby and the lighting when the server starts.
- **Look around.**
  - Each team's house is low and mossy, dug into its hill, and has an invisible spawn.
  - Tall grass hides a crouching player, but not a standing one.
  - There is a trail of grass, bushes and rocks out of each door.
  - The middle zone has ruins, rocks and logs.
- **Mirrored cover.** The middle zone is point-symmetric, so both teams get equal cover.
- **Distance.** Sprinting from one house to the middle takes about 10-12 s, so teams meet within ~30 s.
- **Boundaries.** You can't walk past the tree line.
- **Fog.** It is light; raise or lower `Atmosphere.Density` in `setupLighting()`.
- **Hand-editing the map.**
  1. While playing, copy `Workspace.Map`.
  2. Stop, then paste it into Workspace.
  3. Edit it. If a `Map` folder exists, it is used instead of building a new one.

### Phase 7 – Polish
- **Main menu.** It has a **PLAY** button and shows total kills, wins and coins.
- **Leaderboard.** The player list (Tab) shows **Kills**, **Wins** and **Coins**. Kills and wins count this server only; the totals are saved.
- **Saving.** `DataService` saves with `pcall` and retries:
  - when a player leaves
  - every 2 minutes
  - in `BindToClose`
- **Sounds.** There are sounds for gunshots, hit markers, birds, footsteps and rustling, round start and round end. They use sounds built into Roblox. For better audio, put Creator Store sound IDs in `GameConfig.SOUNDS`. If the Weapons Kit rifle has a fire sound, it's used for the gunshot automatically.

---

### Bots (solo testing)
- **File:** `BotService`, which is switched on with `GameConfig.BOTS_ENABLED = true`.
- **Getting into a round alone:** with bots on, one player pressing **PLAY** is enough to start. Each team is filled with bots up to `BOTS_FILL_TEAM_TO` (3), so you play 3v3: you plus 2 bot teammates against 3 bot enemies.
- **Same rules as players:** bots use the same server systems as you, so their shots, damage, spawn protection, safe zones, footsteps and birds all work the same way. They also get a random free camo.
- **Spotting you:** a bot needs line of sight, and sees no farther than 250 studs. If you crouch in tall grass, it only sees you within 25 studs.
- **Shooting:** a bot only fires after seeing you for 1.2 s, and its aim gets worse with distance.
- **Moving:** bots move between grass patches and ruins and hide crouched for a while. Sometimes they stay too long and the birds give them away.
- **Spectating and name tags:** after you die you can spectate your bot teammates, and they show their name tag to you.
- **Difficulty:** tune it with the `BOT_*` values in GameConfig. Set `BOTS_ENABLED = false` for real matches.

## 4. Tweaking

- **Settings:** every number is in `GameConfig`.
- **Camos:** colors and prices are in `Shared/CamoData`. Add `ShirtTemplate` / `PantsTemplate` IDs for real camo clothing.
- **Shop:** items and prices are in `Shared/ShopCatalog`. Balance rule: never sell more damage, range or max health.
- **Crouch animation:** to use your own instead of the joint-bend kneel, set `CROUCH_ANIMATION_ID` to an uploaded R15 animation.
