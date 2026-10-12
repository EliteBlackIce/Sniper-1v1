# Sniper Duel (Roblox, Luau + Rojo)

A 1v1 first-person sniper duel with fast, momentum-based movement and
ROUNDS-style roguelike progression. Best of 7 (first to 4 round wins). After
each round, the player who **died** picks 1 of 5 random power-up cards. Cards
stack for the rest of the match, so the losing player gets stronger each round.

Everything (map, viewmodel, UI, icons) is built from flat, single-colour
SmoothPlastic parts and frames. The project uses no images, meshes or
textures, so it runs as soon as it's synced.

---

## File structure

```
default.project.json          Rojo project: maps the folders below into Roblox
rokit.toml                    pins the Rojo version (optional, for Rokit users)

src/shared/                -> ReplicatedStorage.Shared   (server + client)
  Config.lua                  ALL tunable numbers + colour palette + sounds + lighting
  PowerUps.lua                every power-up as one data entry + card drawing
  Ballistics.lua              bullet tracing (ghost / ricochet / homing / split shot)
  Remotes.lua                 list of every RemoteEvent
  Signal.lua, Util.lua        small helpers

src/server/                -> ServerScriptService.Server
  Main.server.lua             entry point, starts every service
  LightingSetup.lua           Future lighting, Atmosphere, Bloom, ColorCorrection, SunRays
  MapBuilder.lua              builds the lobby and the arena from parts
  CharacterService.lua        spawning, flat character style, freeze, invisibility, void
  MatchService.lua            lobby, queue, matchmaking, arena slots
  Match.lua                   one match: countdown, rounds, scoring, power-up picks, victory
  CombatService.lua           server-side hit validation, damage, power-up abilities
  SettingsService.lua         saves sensitivity settings (DataStore)

src/client/                -> StarterPlayerScripts.Client
  Main.client.lua             entry point, starts every controller
  ClientState.lua             latest match snapshot, my power-up stats, settings
  CameraController.lua        first-person lock, FOV kicks, tilt, recoil, sensitivity
  MovementController.lua      sprint, slide, double jump, air dash, wall run, grapple...
  ViewmodelController.lua     arms + sniper on the camera (sway, bob, recoil, bolt)
  WeaponController.lua        scope + fire, local tracers, sends shots to the server
  EffectsController.lua       tracers, explosions, ropes, wallhack pulse, screen tints
  UIController.lua            creates all screens
  Sfx.lua, Spring.lua         sound + spring helpers
  ui/
    Theme.lua                 fonts, colours, rounded corners, helpers
    Icons.lua                 draws flat power-up icons from shape data
    HUD.lua                   crosshair, scope, scoreboard + power-up icons, health, banners
    PickScreen.lua            the 5-card power-up pick screen
    VictoryScreen.lua         end of match screen
    LobbyUI.lua               PLAY / queue button, controls list
    SettingsMenu.lua          sensitivity sliders, hold/toggle scope

src/character/             -> StarterPlayer.StarterCharacterScripts
  Health.server.lua           empty script that disables health regeneration
```

---

## Setup: Rojo + Roblox Studio

### 1. Install Rojo (the command-line tool)

Pick **one** of these:

- **Rokit (recommended):** install Rokit from <https://github.com/rojo-rbx/rokit>,
  then in this folder run:
  ```
  rokit install
  ```
  (This reads `rokit.toml` and installs the pinned Rojo version.)
- **VS Code:** install the **Rojo** extension by evaera. It can install and
  run Rojo for you from the command palette ("Rojo: Open menu").
- **Manual:** download `rojo` for your OS from
  <https://github.com/rojo-rbx/rojo/releases> (7.4.x) and put it on your PATH.

Check it works:
```
rojo --version
```

### 2. Install the Rojo plugin in Roblox Studio

Run this once (with Studio closed):
```
rojo plugin install
```
Or search **"Rojo"** in the Studio Toolbox (Plugins tab), by *Rojo*, and install it.

### 3. Create the place and connect

1. Open Roblox Studio and create a new **Baseplate** place.
2. **Delete the Baseplate** part and the **SpawnLocation** from Workspace
   (the game builds its own lobby and arenas).
3. In a terminal in this folder run:
   ```
   rojo serve
   ```
4. In Studio, open the **Plugins** tab, click **Rojo**, then **Connect**
   (default `localhost:34872`). The scripts appear in ReplicatedStorage,
   ServerScriptService and StarterPlayer. Any file you edit now syncs live.
5. **Save the place** (File > Save to Roblox / Save to File). Rojo syncs code
   only; the place file is yours.

> Prefer a one-off file instead of live sync? `rojo build -o SniperDuel.rbxlx`
> and open that file in Studio.

### 4. Studio settings

- **Lighting > Technology** should read **Future** (the project sets it; double check).
- **Game Settings > Security > Enable Studio Access to API Services**: turn
  on if you want sensitivity settings to save between sessions (DataStores).
  The game works without it; settings just won't persist.
- Avatar type: R15 or R6 both work. R15 is recommended
  (Game Settings > Avatar).
- `StarterPlayer.LoadCharacterAppearance` is turned off by the project, so
  everyone gets the clean flat body.

### 5. Test with two players

A duel needs two players:

1. **Test** tab > **Clients and Servers** > set **2 Players** > **Start**.
2. Two client windows open. Press **PLAY** in both.
3. The match starts in one of the arenas after a 3-second countdown.

Single-player check: press **Play** (F5). You can move around the lobby
playground and open settings, but you need a second player to start a match.
To try first-person movement alone, set `Config.Debug.FirstPersonInLobby = true`.

---

## Controls

| Key | Action |
|---|---|
| WASD | Move |
| Left Shift | Sprint (hold) / **Air dash** (press in the air) |
| C or Left Ctrl | Slide (hold). Press in the air to slide on landing |
| Space | Jump / double jump / wall jump |
| (automatic) | Wall run: jump next to a wall while moving and holding W |
| Right mouse | Scope (hold, or toggle in settings) |
| Left mouse | Fire |
| E | Grapple Hook (power-up) |
| Q | Decoy (power-up) |
| Space (hold) | Ceiling run under a ceiling (Magnetic Boots) |
| P | Settings |

---

## What to test after each stage

The code was written in five stages. All stages are in this repo, so you
can work through these checklists in order once it's synced.

### Stage 1: first-person camera and movement
Files: `Config`, `CameraController`, `MovementController`, `CharacterService`, `MapBuilder` (lobby)

- [ ] In the lobby the camera is the normal third-person camera.
- [ ] Set `Config.Debug.FirstPersonInLobby = true`: the camera locks in first
      person, scrolling can't zoom out, and you can't see your own body.
- [ ] Shift sprint is faster and the FOV widens slightly.
- [ ] Sprint, then C: you slide, the camera drops and tilts, and the FOV kicks out.
      Speed bleeds off and the slide ends on its own.
- [ ] Slide, then Space: you jump and keep the slide speed.
- [ ] Space in the air: double jump.
- [ ] Shift in the air: a fast flat dash (one per jump, refills on landing or wall run).
- [ ] Jump next to the long lobby wall holding W: you wall run, the camera
      tilts away from the wall, and you slowly sink. Space jumps off the wall
      and refreshes your double jump.
- [ ] Wall run, then Shift: you dash off the wall with the speed carried.
- [ ] Walking into walls doesn't stick or jitter, and you stop quickly when you let go of WASD.
- [ ] Tune feel in `Config.Movement` / `Config.Camera` while Rojo is connected.

### Stage 2: sniper and viewmodel
Files: `ViewmodelController`, `WeaponController`, `Ballistics`, `CombatService`, `EffectsController`

- [ ] In a match you see arms holding a flat sniper. It sways when you move
      the mouse, bobs when you walk, lowers when you sprint and tilts while sliding.
- [ ] The small crosshair shows in the centre.
- [ ] Right mouse: the gun slides to centre, the FOV zooms in, the scope overlay
      appears and the crosshair hides. Scoped sensitivity is used.
- [ ] Left click: recoil kick, a tracer from the muzzle, a bolt-action animation
      with a click sound, and you can't fire again until it finishes (bar under the crosshair).
- [ ] Hit the enemy: white hitmarker + ping. Headshot: red hitmarker and instant kill.
      A body shot does 72 damage, so it takes two.
- [ ] The enemy sees your tracer coming from your third-person gun.
- [ ] Server validation: firing faster than the bolt (e.g. with a modified client)
      or from far away from your body is rejected and logged in the server Output.

### Stage 3: rounds and scoring
Files: `MatchService`, `Match`, `HUD`, `LobbyUI`, `VictoryScreen`

- [ ] PLAY in both clients: the queue status updates, then both are teleported to
      opposite spawns, frozen, with a 3-2-1 countdown, then GO.
- [ ] The scoreboard at the top shows names and round wins (e.g. 2 - 1), the round
      number and a round timer.
- [ ] Killing the enemy shows ROUND WON / ROUND LOST (and HEADSHOT when it was one).
- [ ] The first to 4 wins sees VICTORY, the other DEFEAT, with the final score.
      Both return to the lobby with the normal camera.
- [ ] One player leaving mid-match gives the other the win ("OPPONENT LEFT").
- [ ] Falling out of the map kills you. The reset button is disabled.

### Stage 4: power-ups
Files: `PowerUps`, `PickScreen`, `Icons`, plus power-up code in Movement/Weapon/Combat/Effects

- [ ] After each round the loser sees 5 cards flip in one by one: rarity-coloured
      glow, icon, name and description, with no duplicates. The mouse is free.
- [ ] Legendary cards shimmer and play a deeper sound when they flip.
- [ ] Hovering lifts and brightens a card. Clicking plays a pick animation.
- [ ] The winner sees the same cards ("X IS CHOOSING") and can't click them,
      then sees which one was picked.
- [ ] Let the 15s timer run out: a random card is picked.
- [ ] Collected power-ups show as small icons under each name on the scoreboard.
- [ ] Each power-up does what its card says. Quick ways to test one:
      temporarily raise its `Weight` in `Config.Rarity`, or reduce the
      `Definitions` list in `PowerUps.lua` to just the cards you want to test.

### Stage 5: map and visuals
Files: `MapBuilder` (arena), `LightingSetup`, `Config.Palette`, `Config.Lighting`

- [ ] The arena has a centre tower, four mid towers with bridges, wall-run
      walls, long side lanes, and cover blocks. Both spawns sit on raised decks
      at opposite ends.
- [ ] Every part is SmoothPlastic and one solid colour from the palette.
- [ ] Shadows are crisp, the sky has a soft atmosphere, and bloom is subtle.
- [ ] Change `Config.Palette` (e.g. `AccentA`) and press Play: map, viewmodel
      and UI colours follow.

---

## Tuning and extending

- **All numbers live in `src/shared/Config.lua`**: movement speeds, slide/dash/
  wall run, damage, bolt time, scope speed, server validation tolerances,
  power-up strengths, rarity weights, sensitivity defaults, palette, lighting
  and sound IDs.
- **Add a power-up:** add one entry to `PowerUps.Definitions` (name, description,
  rarity, icon colour, icon shapes, max stacks, `Effect`). If the effect only
  changes existing stats (health, jumps, bolt time, bullets, bounces...), you're
  done. For new behaviour, add a field to `baseStats()` and read it where the
  behaviour lives (see the comment at the top of `PowerUps.lua`).
- **Sounds:** `Config.Sounds` uses sounds bundled with the Roblox client
  (`rbxasset://sounds/...`). Swap any of them for `rbxassetid://<id>` from the
  Creator Store if you want different ones.

## How hit detection works (anti-exploit)

1. The client traces the bullet with `Ballistics` for instant tracers and sends
   `origin`, `direction` and what it saw itself hit.
2. The server rejects shots that come too fast for the (power-up adjusted) bolt
   time, start too far from the shooter's server-side head, have invalid
   numbers, or happen outside a live round.
3. The server re-traces the bullet with the **same** `Ballistics` code
   (ricochets, ghost walls, homing and split shot included) against the real
   map and the real enemy position.
4. Lag compensation: a client hit claim is only accepted if the claimed point
   lies on the server's own bullet path **and** near where that body part
   actually is on the server. A cheater can't shoot through walls or hit
   someone who wasn't there.

## Design notes

- **Bullet Time** is personal: Roblox can't slow the server clock for one
  player. While it's active you fall very slowly, drift at reduced speed, aim is
  steadier, your bolt cycles twice as fast and the screen tints.
- **Decoy** is a hologram copy of your character that runs in a straight line,
  follows the floor, stops at walls and pops when shot.
- Up to `Config.Match.MaxArenas` matches run at once in one server. Each
  gets its own copy of the arena.
