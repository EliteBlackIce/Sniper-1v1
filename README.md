# Sniper Duel (Roblox, Luau + Rojo)

A 1v1 first-person sniper duel with fast, momentum-based movement and
ROUNDS-style roguelike progression. Best of 9 (first to 5 round wins). After
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
  GunModel.lua                the sniper rifle + a visual mod for every power-up
  Remotes.lua                 list of every RemoteEvent
  Signal.lua, Util.lua        small helpers

src/server/                -> ServerScriptService.Server
  Main.server.lua             entry point, starts every service
  LightingSetup.lua           Future lighting, Atmosphere, Bloom, ColorCorrection, SunRays
  MapBuilder.lua              builds the lobby and the arena from parts
  ArenaSimple.lua             the default map: a simple 1v1 arena (ramps, walls, cover)
  ArenaDowntown.lua           optional detailed city map (Config.Match.Map = "Downtown")
  DummyService.lua            practice dummies on the lobby shooting range
  CharacterService.lua        spawning, flat character style, freeze, invisibility, void
  MatchService.lua            lobby, queue, matchmaking, arena slots
  Match.lua                   one match: countdown, rounds, scoring, power-up picks, victory
  CombatService.lua           server-side hit validation, damage, power-up abilities
  BotService.lua              computer opponent for admin "/bot" matches (AI + fake player)
  SettingsService.lua         saves settings + keybinds (DataStore)

src/client/                -> StarterPlayerScripts.Client
  Main.client.lua             entry point, starts every controller
  ClientState.lua             latest match snapshot, my power-up stats, settings
  Keybinds.lua                every rebindable action + its keyboard / controller default
  CameraController.lua        first-person lock, FOV kicks, tilt, recoil, sensitivity
  MovementController.lua      bhop, air control, sprint, slide, wall run, grapple...
  ViewmodelController.lua     arms + sniper on the camera (sway, bob, recoil, bolt)
  WeaponController.lua        scope + fire, local tracers, sends shots to the server
  CharacterPoser.lua          third-person rifle-holding pose for other players
  EffectsController.lua       tracers, explosions, ropes, wallhack pulse, screen tints
  UIController.lua            creates all screens
  Sfx.lua, Spring.lua         sound + spring helpers
  ui/
    Theme.lua                 fonts, colours, rounded corners, helpers
    Icons.lua                 draws flat power-up icons from shape data
    HUD.lua                   crosshair, scope, scoreboard + power-up icons, health, banners
    PickScreen.lua            the 5-card power-up pick screen
    VictoryScreen.lua         end of match screen
    LobbyUI.lua               find match / playground buttons (keys shown on them)
    SettingsMenu.lua          General / Keyboard / Controller tabs: sliders, toggles, keybinds
    Toast.lua                 short messages from the server (admin commands)
    PowerUpLab.lua            try any power-up solo in the lobby (B)

src/character/             -> StarterPlayer.StarterCharacterScripts
  Health.server.lua           empty script that disables health regeneration
```

---

## Quick start (no Rojo needed)

1. Download **`dist/SniperDuel.rbxlx`** (on GitHub: open the file, then click the
   download button).
2. Double-click it, or in Roblox Studio use **File > Open from File** and pick it.
3. **Solo:** press **Play** (F5). You spawn in first person with your sniper in
   the lobby. Shoot the dummies on the range, practise bunny hopping and wall
   running.
4. **A real duel:** **Test** tab > **Clients and Servers** > **2 Players** >
   **Start**, then press **F** in both windows to find a match.
5. **File > Publish to Roblox** if you want it on your account.

This file is a snapshot of the code. If you edit the `src/` files, rebuild it with
`rojo build -o dist/SniperDuel.rbxlx`, or use the live Rojo setup below.

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
  on if you want settings and keybinds to save between sessions (DataStores).
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

Single-player check: press **Play** (F5). The lobby is a first-person practice
area with a shooting range and moving dummies, so you can test movement and
the sniper on your own. You need a second player to start a match.

---

## Controls

Every key below can be rebound in **Settings (P) > Keyboard** or
**Settings > Controller** (controller defaults in brackets).

| Key | Action |
|---|---|
| WASD [left stick] | Move |
| Mouse [right stick] | Look |
| Hold Space | **Bunny hop**: re-jump the instant you land, keeping all your speed |
| A or D + mouse | **Air strafe**: in the air, hold A and turn left (or D and right) to gain speed |
| Left Shift | Sprint (hold) |
| W (in the air) | Steer your momentum toward where you look (keeps your speed) |
| C [B / O] | Slide (tap, tap again to stand). Press in the air to slide on landing. Jump out of a slide any time |
| Space | Jump / wall jump (no double jump unless you pick the Double Jump power-up) |
| (automatic) | Wall run: jump next to a wall while moving and holding W |
| Right mouse | Scope (hold, or toggle in settings) |
| Left mouse | Fire |
| E | Grapple Hook (power-up) |
| R | Blink (power-up) |
| Q | Decoy (power-up) |
| Space (hold) | Ceiling run under a ceiling (Magnetic Boots) |
| V | Inspect your rifle |
| B | **Power-Up Lab** (lobby / playground): try any power-up solo |
| G | **Playground** (lobby): free roam on the match map with dummies |
| F [D-pad right] | Find a match / leave the queue (lobby) |
| N [RB / R1] | Play against a bot (admins, lobby) |
| P [Select] | Settings (frees the mouse) |

Controller defaults: RT fire, LT scope, A jump, B slide, L-stick click sprint,
Y grapple, X blink, D-pad up decoy, D-pad down inspect, D-pad left Power-Up
Lab, LB playground.

---

## What to test after each stage

The code was written in five stages. All stages are in this repo, so you
can work through these checklists in order once it's synced.

### Stage 1: first-person camera and movement
Files: `Config`, `CameraController`, `MovementController`, `CharacterService`, `MapBuilder` (lobby)

- [ ] You spawn in the lobby in first person, scrolling can't zoom out, and you
      can't see your own body.
- [ ] Hold Space: you bunny hop. Hold A and turn the mouse left in the air: the
      speedometer climbs.
- [ ] Shift sprint is faster and the FOV widens slightly.
- [ ] Sprint, then tap C: you slide, the camera drops and tilts, and the FOV kicks out.
      Speed bleeds off and the slide ends on its own (or tap C again).
- [ ] Slide, then Space: you jump straight away and keep the slide speed.
- [ ] Space in the air does nothing (no double jump by default).
- [ ] Hold W in the air and look left/right: you curve that way without losing speed.
- [ ] Jump next to the long lobby wall holding W: you wall run, the camera
      tilts away from the wall, and you slowly sink. Space jumps off the wall.
- [ ] Walking into walls doesn't stick or jitter, and you stop quickly when you let go of WASD.
- [ ] Tune feel in `Config.Movement` / `Config.Camera` while Rojo is connected.

### Stage 2: sniper and viewmodel
Files: `ViewmodelController`, `WeaponController`, `Ballistics`, `CombatService`, `EffectsController`

- [ ] In the lobby (and in matches) you see gloved arms holding the sniper. It
      swings up into view when you spawn, dips when you jump, slams on hard
      landings, and V inspects it. Shoot the range dummies: they flash, lose
      health and respawn.
- [ ] The rifle sways when you move
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
- [ ] The first to 5 wins sees VICTORY, the other DEFEAT, with the final score.
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
- [ ] Each power-up does what its card says. Test them **solo** in the lobby:
      press **B** to open the Power-Up Lab, left click power-ups to add them
      (right click removes), close it and try them on the range dummies.
      **DRAW 5 CARDS** opens the real pick screen with random cards.
      (Second Wind and Vampire need a real opponent: use a 2-player Studio test.)

### Stage 5: map, rifle and visuals
Files: `ArenaSimple` (the arena), `GunModel` (rifle + power-up mods), `MapBuilder`, `LightingSetup`

- [ ] Spawn on your raised deck, run down the ramp, and check the arena:
      a hill in the middle, ramps up to the side bridges, long walls to wall
      run, and a few cover pieces (see `dist/arena-preview.png`).
- [ ] The rifle is the new two-tone VX-7 with glowing lines (see
      `dist/rifle-preview.png`).
- [ ] Open the Power-Up Lab (B) and add power-ups: each one bolts a part onto
      the rifle (coils, side barrels, canister, tesla coils, laser...), the
      glow lines take the colour of your rarest power-up, and the rifle
      plays its inspect animation to show it off. Other players see the
      same attachments on your rifle.
- [ ] Shadows are crisp, the sky has a soft atmosphere, and bloom is subtle.
- [ ] Change `Config.Palette` (e.g. `AccentA`) and press Play: map, viewmodel
      and UI colours follow.

---

## Settings and keybinds

Press **P** (controller: Select) or the SETTINGS button in the lobby.
- **General**: mouse sensitivity and scoped sensitivity; controller look
  sensitivity, scoped sensitivity, stick deadzone, invert Y and aim assist;
  field of view; hold or toggle scope. Sliders can be dragged, or moved with
  the D-pad on a controller.
- **Keyboard** / **Controller**: click an action, then press the new key or
  button (Esc cancels). RESET DEFAULTS puts everything back.
- Settings save between sessions (DataStore; turn on API access in Studio).
  Tune the defaults and slider ranges in `Config.SettingsDefaults`,
  `Config.SettingsLimits` and `Config.Controller`.

## Bot (admin command)

Play a full match against a computer opponent, e.g. to test builds.
- In the lobby press **N** (controller: RB), or type in chat:
  `/bot`, `/bot easy`, `/bot normal`, `/bot hard`. `/endbot` ends the match.
- Who counts as admin (`Config.Admin`): the game's owner (or the group owner),
  anyone in `UserIds`, and everyone while testing in Studio
  (`AllowEveryoneInStudio`). Set `BotForEveryone = true` to let all players
  use it.
- The bot runs around the map with pathfinding, strafes and hops when it sees
  you, needs a moment to react, and its aim gets steadier the longer it tracks
  you (faster movers are harder for it). It shoots through the same server
  checks as players and picks power-up cards when it loses a round.
- Difficulty numbers (reaction time, aim error, headshot chance, speed) are
  in `Config.Bot`.

## Collision and hitboxes

- Walls are single solid boxes. All the detail on them (pilasters, frames,
  glass, signs, railings, car trim...) has collision **and** bullet hits off,
  so nothing snags you and shots aren't eaten by decoration.
- Movement does a body-sized sweep every frame and slides you along walls
  instead of letting you push into them (fast bunny hops and slides can't
  tunnel through), and Blink stops short of walls.
- Stairs and fire escapes walk on a smooth invisible ramp under the visible
  steps; landings have invisible rails so you can't fall off.
- Tree leaves don't block movement but do block bullets and sight.
- The viewmodel pulls back when you stand against a wall, so the rifle never
  pokes through it.

## Playground mode

Press **G** in the lobby. You're dropped into your own copy of the match map
(shared with anyone else in the playground) with practice dummies on the
high ground and in the lanes. Open the **Power-Up Lab (B)** and
try any build on the real map; press **G** again to go back to the lobby, or
**F** to queue for a match from there.

## Controller aim assist

Controller players get light aim assist (mouse players never do):
- **Slowdown**: your aim turns up to 30% slower when the crosshair is right
  on a target, so it's easier to stay on them.
- **Gentle pull**: while you move or use the right stick, the aim drifts
  very slightly toward the target's body (never the head), at most about
  3 degrees per second.
- It only works inside a small circle around the crosshair (4.5 degrees,
  smaller when scoped), only on targets you can actually see, and never on
  an invisible (Phantom Step) enemy or a decoy.
- Players can turn it off in Settings (P). Tune it in `Config.AimAssist`.

## Visual effects

Glowing tracers with a travelling bullet, muzzle flash lights, impact sparks
and smoke, ricochet flashes, fireball explosions with shockwave rings, kills
that shatter the body into shards, floating damage numbers, speed lines when
you're fast, landing dust, slide sparks, and animated UI everywhere (card
deal/flip/pick, banners, score pops, victory confetti). Tone any of it down in
`Config.Effects`.

## Power-ups and builds

There are 30 power-ups and almost all of them **stack**. Every card shows what
another copy adds ("STACKS: ..."). They're designed to combine into builds:

| Build | Cards | What happens |
|---|---|---|
| Pinball | Ricochet x4 + Pinball x2 + Shrapnel | every bounce adds +70% damage and sprays shards |
| Demolition | Explosive Rounds x3 + Split Shot + Shrapnel | five explosive bullets, each blast showers shards |
| Speedster | Adrenaline + Momentum Rounds x3 + Sky Sniper | bunny hop fast = up to +180% damage, more in the air |
| Assassin | Ghost Round + Wallhack Pulse + Marked | see them through walls, shoot through walls, marked targets take more |
| Gunslinger | Hair Trigger + Split Shot + Quickdraw | every hit re-chambers instantly |
| Storm | Static Charge x3 + Split Shot + Homing | near misses still zap for 60 |
| Tank | Thick Skin + Vampire + Second Wind x2 | survive two lethal hits a round |
| Glass | Glass Cannon x3 + Momentum Rounds | +90% damage (more when fast) on a 40 HP body |

**New in this version:** Shrapnel, Static Charge, Pinball, Momentum Rounds,
Sky Sniper, Glass Cannon, Marked, Hair Trigger, Adrenaline, Featherweight,
Spring Legs, Blink (press R).

**Damage formula** (server side): base x Glass Cannon x Sky Sniper (airborne) x
Momentum (speed) x Pinball (hops) x Marked. Headshots always kill instantly.

Test them solo in the lobby with the **Power-Up Lab** (press B).

## The arena

![Arena](dist/arena-preview.png)

The default map (`Config.Match.Map = "Simple"`) is an open 1v1 arena in the
spirit of ROUNDS, built for flow: a few big shapes and long gentle ramps, so
you can bunny hop, slide and wall run across it without snagging. It's
mirrored, so both sides are identical.
- **Spawn decks** on each end with a wide ramp down.
- **Centre hill**: a low mesa with gentle ramps on all four sides (slide
  over it) and one spine of cover on top.
- **Side bridges**: long gentle ramps up to a high deck on each side, with
  a low lip for cover.
- **Long walls** between the lanes to hide behind or wall run along.
- **Just a few cover pieces**: one low wall in each half of the middle lane
  (so you can't see spawn to spawn) and a block in each corner.

Everything is in `src/server/ArenaSimple.lua` as a short list of blocks and
ramps, so it's easy to move things around. The playground dummies for each
map are listed at the bottom of its file.

## The rifle and power-up mods

![Rifle](dist/rifle-preview.png)

![Rifle with every power-up](dist/rifle-powerups-preview.png)

The VX-7 is an angular two-tone rifle (light shell, dark metal) with glowing
energy lines, an energy cell on the side and a glowing round counter in the
magazine. It changes as you pick power-ups:
- The **glow lines** take the colour of your rarest power-up and flare
  white when you fire.
- Every power-up **bolts on its own part**, with an effect: Ghost Round
  shimmering phase fins, Ricochet glowing coils (more per stack), Split Shot
  side barrels, Homing a seeker module with a laser, Explosive Rounds a
  grenade canister and embers at the muzzle, Shrapnel spinning spikes,
  Static Charge crackling tesla coils with sparks, Pinball bumper rings,
  Momentum fins that glow as you speed up, Sky Sniper wings, Glass Cannon a
  white-hot barrel, Marked a red laser, Hair Trigger a gold trigger, Vampire
  a dripping blood vial, Bullet Time a ticking clock, Wallhack Pulse a
  spinning radar dish, Thick Skin armour plates, Second Wind a heart cell,
  Grapple a hook launcher, and so on. Movement power-ups hang a coloured charm.
- With 5 or more power-ups the handguard sparks.
- Your opponent sees the same rifle in your hands, so you can read their
  build. (Phantom Step hides the effects too.)
- Add or change mods in `GunModel.Mods`.

## The Downtown map (optional)

Set `Config.Match.Map = "Downtown"` for the detailed city instead.

![Downtown](dist/downtown-preview.png)

![Street level](dist/downtown-street.png)

A mirrored city block (both halves identical):
- **Avenue**: the main long lane between the spawns, broken up by a bus, cars,
  barriers and the plaza fountain.
- **North**: brick apartments with shops on the ground floor (24 high) and
  an office tower (48), joined by a catwalk between their steel fire escapes
  (switchback stairs with real steps, landings and railings). City Hall sits
  in the middle with a columned porch, a pediment, a 26-high roof and a clock
  tower.
- **Detail**: windows with frames and sills between pilasters, cornices and
  ledges, rooftop bulkheads, AC units and water towers, detailed cars, a taxi
  and a bus (wheels with rims, lights, mirrors), layered trees, traffic
  lights, lamps with banners, hydrants, benches and bins.
- **South**: a park with hedges and billboards (wall-runnable), the elevated
  train track (a long high lane with a train in the middle), a market, a shop,
  a warehouse, climbable shipping containers and a parking lot.
- Switch back to the original arena with `Config.Match.Map = "Classic"`.

## Bunny hopping

Movement uses the Source-engine model (Half-Life / CS / TF2):

- **On the ground**: friction, then acceleration up to run speed (30) or sprint speed (38).
- **In the air**: you can only add a tiny amount of speed *in the direction
  you're pressing* (`AirSpeedCap`), but there's no limit on total speed. When you
  strafe and turn the mouse at the same time, your input stays sideways to your
  velocity, so it keeps bending and growing. That's air strafing.
- **Holding Space** jumps again on the exact frame you land, before friction
  runs, so you lose no speed. Chain hops + air strafing = bunny hopping. Watch
  the speedometer under the crosshair (it turns teal when you're fast).
- **Tips**: don't hold W in the air. Hold only A or D and turn smoothly the same
  way. A slide (C) into a jump also starts a hop chain with extra speed.
- **Tuning** (`Config.Movement`): `AirAccel` and `AirSpeedCap` for strafe gain,
  `Friction` for how sticky the ground is, `MaxSpeed` for the speed limit, and
  `AutoBhop = false` if you want players to time each jump.

## Tuning and extending

- **All numbers live in `src/shared/Config.lua`**: movement speeds, slide/
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
