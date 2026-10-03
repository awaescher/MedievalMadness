# Medieval Madness — Implementation Specification

Version 2.0 (Godot edition). Audience: an implementing developer or LLM. Everything needed is defined here. When something is not specified, choose the simplest option that satisfies the acceptance criteria. Do NOT add features not listed here until all phases are done.

**Maintenance rule: `SPEC.md` and `CHANGELOG.md` are updated with EVERY change** (new feature, rule or number changed, bug fix worth noting). **Status (kept in sync with the game):** this document describes the game as it is built. Decisions taken after the first port (teams, the two turn actions, starting-arsenal presets, the UI redesign, the online lobby and the relay help) are folded into the sections they belong to and summarised in **section 26 (decision log)**. **Game version**: `res://VERSION` holds `major.minor.patch`; `export.sh` / `export.bat` increase the patch number with every build (so the menu and the online `hello` always show a fresh number); the minor/major number is raised by hand for bigger releases.

This spec is the native port of the browser version (Three.js + Rapier). Game rules, content, numbers and tables are unchanged; only the technology (engine, project layout, rendering, audio, UI, packaging) differs. Section numbers match the browser spec on purpose.

---

## 0. Summary

**Medieval Madness** is a turn-based, physics-heavy 3D artillery game that runs as a **standalone desktop application on Windows, macOS and Linux**, built with **Godot 4**. 2–8 players (humans and/or CPU bots, on one screen or online) each own a medieval village and up to 5 catapults. Players take turns; in a turn a player fires one shot from one catapult at any other village **or** spends the turn on one of two actions (drive a catapult to a new spot, build a stone wall, 6.8). Everything in the world is a physics object and is destructible. Fire spreads, water extinguishes, settlers become ragdolls and shout jokes. A player whose catapults are all destroyed is eliminated. Players may form **teams** (the player colour is the team, 6.9); the **last team standing wins together**.

Tone: silly, cartoonish, modern comic look. Humor everywhere (texts, sounds, effects).

### 0.1 Hard constraints
- **Engine: Godot 4.4 or newer 4.x stable**, standard (non-.NET) build, **GDScript only**. No C#, no GDExtension, no C++ modules, no addons/plugins, no Asset Library content.
- **Physics: Jolt Physics** (built into Godot 4.4+). Set explicitly in `project.godot`: `physics/3d/physics_engine="Jolt Physics"`. Do not use the legacy GodotPhysics3D.
- **Renderer: Mobile** (`rendering/renderer/rendering_method="mobile"`; Vulkan on Windows/Linux, Metal on macOS via MoltenVK/Metal driver). Forward+ features (SSAO, SDFGI, volumetric fog…) are NOT used. The Compatibility renderer is not a target.
- All graphics are procedural (Godot primitive meshes, `ArrayMesh`/`SurfaceTool` generated geometry, shaders, `Image`-generated textures). **No image, model, font or audio files** in the project. (`assets/relay_help/*.txt` are plain text copies of the relay spec and template that `export.sh` makes from `relay/`; only the relay help dialog reads them.)
- All audio is synthesized at startup into `AudioStreamWAV` resources (section 17). No audio files.
- Fonts: engine default font + `SystemFont` (see 16.1). No bundled fonts.
- UI languages: English (default) and German, switchable at runtime.
- Target: 60 FPS with 4 players on Medium quality on a mid-range laptop (integrated GPU, e.g. Apple M1 / Intel Iris Xe / Radeon 680M).
- Input: mouse + keyboard. Gamepad/touch are out of scope.
- Fully static typing in GDScript (`var x: float`, `func f(a: int) -> void`). Warnings "untyped declaration" and "unsafe *" are set to *warn* in project settings; the project must start with zero errors and zero GDScript warnings in the output panel.
- **Standalone**: exported builds must run by double-click with no installer, no network needed (online play, section 19, is an optional feature), no runtime downloads and no separately installed engine (details in section 25).
- Cross-platform means: identical gameplay and visuals on Windows 10+, macOS 12+ (Apple Silicon and Intel) and Linux (x86_64, Vulkan-capable GPU). Never use platform-specific APIs; use `user://` for all writes; use `/` path separators; never call `OS.execute` in game code.

### 0.2 Deliverable folder
Everything lives in `./medieval-madness-native/`. Do not read or modify any other folder in the parent directory (in particular not `../medieval-madness/`).

### 0.3 Prerequisites (for building, not for players)
- Godot 4.4+ standard editor binary on `PATH` as `godot` (macOS: `brew install --cask godot`, binary at `/Applications/Godot.app/Contents/MacOS/Godot`; Windows: `godot.exe`; Linux: package or download).
- Godot export templates matching the editor version (Editor → Manage Export Templates, or download `Godot_v4.x-stable_export_templates.tpz`). Required only for section 25.
- Check with `godot --version` and adapt to the installed version; if it is newer than 4.4, keep the code compatible with 4.4 API where possible.

---

## 1. Project Layout

```
medieval-madness-native/
  SPEC.md
  README.md                 short: how to run, build, controls
  project.godot             all engine settings (section 1.2)
  export_presets.cfg        Windows / macOS / Linux presets (section 25)
  icon.svg                  tiny hand-written SVG (a catapult silhouette); only allowed "asset"
  export.sh  export.bat     build scripts (section 25)
  run.sh     run.bat        launch from source: godot --path .
  assets/                   reserved, empty (.gdkeep)
  scenes/
    main.tscn               ONE scene: Node root (main.gd) - everything else is created in code
  scripts/
    main.gd                 bootstrap, state switching, main loop glue
    autoload/
      cfg.gd                class_name Cfg: ALL constants from section 3 (not an autoload, static consts)
      events.gd             autoload "Events": signal bus (section 20)
      settings.gd           autoload "Settings": ConfigFile persistence (section 18.3)
      i18n.gd               autoload "I18n": t(), tr_list(), set_lang(), get_lang()
      game.gd               autoload "Game": global game state + state machine
      sfx.gd                autoload "Sfx": sound synthesis + playback pool (section 17)
    core/
      rng.gd                class_name Rng: seeded PRNG (mulberry32) + helpers, FNV-1a string hash
      noise.gd              value noise / fbm (own implementation, no FastNoiseLite for map gen)
      util.gd               static helpers (mesh merge, easing, spatial hash, ...)
    lang/
      en.gd                 const DATA := { ... } all strings + quips
      de.gd
    render/
      quality.gd            quality tiers application (section 15)
      toon.gd               toon + outline shader materials factory (16.1)
      cameras.gd            camera rig (overview, aim, follow, impact, focus, orbit)
      sky.gd                gradient sky shader, sun, clouds
      water.gd              water plane(s) + shader
      shaders/              *.gdshader written by hand (toon, outline, sky, water, terrain, particles)
    physics/
      world.gd              physics helpers on top of PhysicsServer3D, body registry, sleeping
      materials.gd          material table (section 4)
      breakable.gd          destructible parts + structures (section 5)
      debris.gd             debris cap + cleanup
    world/
      terrain.gd            heightmap mesh + HeightMapShape3D
      mapgen.gd             seeded map generation (section 7)
      village.gd            village generator (section 8)
    buildings/
      kit.gd                helper functions (box, wall, gable roof, ...)
      registry.gd           registry of building builders
      (one file per building type, section 9)
    props/
      registry.gd           registry of prop builders (section 10)
    entities/
      catapult.gd
      projectile.gd
      settler.gd
      animal.gd
    systems/
      damage.gd
      fire.gd
      water_sys.gd
      explosion.gd
      weather.gd
      random_events.gd      dragon, meteor cheese etc.
      turn.gd               turn manager, settle detection, predict_trajectory
      scoring.gd            stats and titles
    fx/
      particles.gd          pooled GPUParticles3D effect presets
      comic_text.gd         floating "KRAWUMM!" Label3D pool
      speech.gd             speech bubbles
      trails.gd
    ai/
      cpu.gd                bot logic (section 14)
    ui/
      theme.gd              builds the parchment Theme resource in code
      menu.gd  hud.gd  aiming.gd  placement.gd  results.gd  pause.gd  debug_overlay.gd
  tests/
    run_tests.gd            headless test entry (section 21)
    (test_*.gd)
```

### 1.1 Scene and code style
- `main.tscn` contains only a root `Node` with `main.gd` attached. All other nodes are created in code (this keeps the project diff-friendly and avoids `.tscn` authoring errors). Only autoloads are registered in `project.godot`.
- One `class_name` per file where the class is referenced elsewhere. Files are `snake_case.gd`, classes `PascalCase`.
- Systems talk through `Events` signals (section 20); systems never call UI directly.
- Hot paths (physics sync loop, fire tick, part release, particle spawn) must avoid allocations: reuse `Transform3D`/`Vector3` locals, use `PackedFloat32Array`/`PackedVector3Array`, avoid per-frame `Array.append` churn, no `Dictionary` creation per frame.

### 1.2 project.godot (required settings)
```
[application]
config/name="Medieval Madness"
run/main_scene="res://scenes/main.tscn"
config/icon="res://icon.svg"
[autoload]
Events="*res://scripts/autoload/events.gd"
Settings="*res://scripts/autoload/settings.gd"
I18n="*res://scripts/autoload/i18n.gd"
Game="*res://scripts/autoload/game.gd"
Sfx="*res://scripts/autoload/sfx.gd"
[display]
window/size/viewport_width=1600
window/size/viewport_height=900
window/size/window_width_override=1600
window/size/window_height_override=900
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
[physics]
common/physics_ticks_per_second=60
common/max_physics_steps_per_frame=3
3d/physics_engine="Jolt Physics"
3d/default_gravity=19.62
3d/run_on_separate_thread=false
[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="mobile"
anti_aliasing/quality/msaa_3d=2
environment/defaults/default_clear_color=Color(0.29, 0.66, 1, 1)
[debug]
gdscript/warnings/untyped_declaration=1
```
(Adapt exact key names to the installed Godot version; the intent is what matters.) The window is resizable, minimum size 1024×600, F11 toggles fullscreen (also an option in the menu).

### 1.3 Autoloads and startup
`main.gd` `_ready()`: load settings, apply quality tier and language, build UI theme, start audio synthesis (progress shown on a splash label), then show the MENU state. Wait for `Sfx.ready` before enabling `Start battle` (usually < 2 s).

---

## 2. Game Flow (State Machine)

States (in `scripts/autoload/game.gd`): `MENU → GENERATING → PLACEMENT → BATTLE → GAME_OVER → MENU`.

### 2.1 MENU
Main menu (Godot `Control` nodes built in `ui/menu.gd`). Fields:
- Language: two drawn **flags** (black-red-gold, Union Jack; selected one has a gold rim) at the top right of the options panel; the in-game pause menu uses the same flags.
- Player count 2–8 (slider) and a small `Random names` button on the same row. For each player row: name (text input, prefilled), **team colour dropdown** (swatch + name: Red, Blue, Green, Yellow, Purple, Orange, Teal, Pink — eight colours for up to eight players; **any number of players may pick the same colour = one team, no limits, no symmetry rule**, 6.9), type dropdown: `Human`, `CPU Peasant`, `CPU Squire`, `CPU Knight`, `CPU King`.
- Map seed (text input; `Random` button generates one), map size preset is derived from player count (section 7).
- **Match rules**: terrain (flat … mountainous), catapults per player (slider 1–5, default 3), palisades per player (slider 1–10, default 4; each = 3 posts) and the **starting arsenal**, a dropdown at the left **above the map seed** with the presets `Standard` (only the stone, every other weapon has to be earned), `Powerplay` (stone ∞, Stone Hail ×4, Boulder ×2, Log ×2), `Quarry` / `Steinbruch` (stone and Stone Hail ∞, Chain Shot ×5, **Boulder ×3**, **Log ×6**), `Chaos` (every weapon except the Meteor Marker ×2, but **Boulder ×5 and Log ×3**) — in this dropdown order and `Custom` / `Eigene Auswahl`. The `Edit` button beside it **always** opens the weapon list (stone "always", every other weapon a 0–9 spinner plus an ∞ check box): for a preset it shows what is inside and tweaks are **for this session only**; for Custom the list is the editable selection. **Only Custom and its weapons are saved** (`Settings.arsenal_preset` is written as `custom` or `standard`, `Settings.arsenal_custom` holds the counts); unlocks work in every mode (∞ weapons simply never run out). Terrain, catapult count and palisade count persist in `Settings` and are copied into `Game` at match start; the resolved arsenal is `Settings.arsenal` (a getter) → `Game.arsenal` → `PlayerData.reset_ammo(start)` where the values are **absolute** counts (-1 = unlimited).
- Options: Turn timer (Off / 20 / 30 / 45 / 60 s, default Off; **the last 5 seconds of a human's turn show a big red 5-4-3-2-1 in the middle of the screen with a tick sound each second and the timer ring flashes red**), Quality (Low/Medium/High/Ultra, default Medium), Lighting (Basic / Enhanced / Ray-marched GI, default Enhanced), Weather events (on/off, default on), Random events (on/off, default on), Sound volume slider, Screen shake on/off (gentle: only impacts of amplitude >= 0.4 shake, at 0.12 m scale).
- A small `Reset options` button at the bottom of the options panel (`Settings.reset_options`): timer Off, catapults 3, palisades 4, terrain 2, arsenal Standard, quality Medium, lighting Enhanced, weather / events / shake / auto-quality / vsync on, fullscreen off, volume 0.8 — language, names, players, seed and the saved Custom arsenal stay (a guest in an online lobby only resets its own display / sound options). Automated test runs (`-- --autotest=...`) never write `settings.cfg` (`Settings._is_test_run`).
- Layout: the left panel (players, then one aligned grid `label | field | button` for Start arsenal and Map seed with the map radius line under it) and the right panel (options). Every control of the options column has the same width (230 px, `Menu.OPT_W`) so the left edges line up. Bottom bar: two **equal big buttons** (340×68, font 26) — **`Start battle` (green; also in single player)** and `Online play` (gold). No quit button, no help line and no "Ready" text; the status line only appears while the sound loads or when all players share one colour (`Start` is disabled then: a match needs at least two teams). While the player is in an online room the second button becomes the red `Close lobby` (host) / `Leave lobby` (guest), the first one becomes `Start online game` (host) or a disabled `Waiting for the host …` (guest), and a **room banner** above the buttons shows `Room <CODE> – n players` (code in 40 px) with a `Copy` button.
- Subtitle under the title: "Catapult chaos for 2-8 players" / "Katapult-Chaos für 2-8 Spieler". **No all-caps button texts** (`Start battle`, not `START BATTLE`).
- **Button sizes, one rule for the whole UI** (`UITheme`): the two start buttons are big; buttons inside dialogs (lobby, arsenal, pause, results, placement bar) are all `DIALOG_H` = 44 px high with font 18 (`UITheme.dialog_button`); buttons inside option rows are `OPTION_H` = 32 px with font 15 (`UITheme.option_button`). Every dialog has the **red close button with a white cross in its top right corner** (`CloseButton`).
- Default player names pool (section 12.1) used for prefill; CPU names use the pool in 12.2.

### 2.2 GENERATING
Show a loading bar with rotating funny messages (section 12.6). Generate terrain, villages, physics. Then go to PLACEMENT.

### 2.3 PLACEMENT
Players in order each place their catapults (`Game.catapults_per_player`, 1–5) inside their own **village zone** (a circle on the ground, radius `ZONE_RADIUS`), and then their palisade posts (2.3b).
- Human: click on the ground inside the zone to place; a ghost preview follows the mouse (green = valid, red = invalid). Valid = inside zone, slope ≤ 25°, not overlapping a building/prop (raycast down + overlap test with radius 2.2 m), min distance 4 m from other catapults. Right-click / `Z` removes the last placed one. `Q`/`E` rotate the catapult facing. Button `Auto-place` places the remaining ones automatically. Button `Done` is enabled when all catapults are placed and leads on to the palisade stage (or to the next player when the post count is 0).
- CPU: places automatically (random valid spots, spread out; Knight/King prefer spots behind walls or next to buildings), then builds a short palisade wall towards the nearest enemy.
- Camera focuses on the current player's village during their placement. **Direction markers** (`Placement._draw`): every other village is marked with a dark pill with a rim in its colour, its name, the distance and a tag — a green shield + `Team` for teammates, crossed red swords + `Enemy` for opponents; above the village when it is on screen, as a pill with an arrow at the screen border when it is not. **In addition a 3D arrow hovers at the edge of the placing player's own village for every other player** (6 m above the ground, bobbing, `Placement._update_arrows`), pointing towards that village, in that player's colour: **a green ring under it for teammates, red crossed swords above it for enemies**.
- All villages are visible to everybody (no fog of war).

### 2.3b Palisade posts
**Posts are placed in a second round, only after EVERY player's catapults stand** (round 1: all players in order place catapults; round 2: all players in order place posts; a banner announces the palisade phase). Each player places `Game.palisades_per_player` (1–10, default 4) **wooden posts** as cover (`world/posts.gd`, kind `palisadepost`, name "Palisade Post" / "Palisadenpfahl"):
- A post is a wooden cylinder as thick as a tree trunk (radius 0.25 m) and **half as high as the watchtower** (5.5 m); one wood `Part`, anchored when it stands on the ground.
- **A fence is always 3 posts side by side** (centre distance 0.52 m, touching) and one placement sets one fence; the match option counts fences (1–10, default 4 = 12 posts). `Q`/`E` turns the fence; a fence set next to the end of another one snaps on and continues it in a straight line (`Posts.snap_fence`).
- **Where**: anywhere dry and not steeper than 35° within `ZONE_RADIUS + 25 m` of the own village centre, but never closer than `ZONE_RADIUS + 12 m` to an enemy village centre; nothing solid may be in the way, and all three posts must be valid.
- **Stacking**: pointing at an own fence places the next row of 3 on top of it (max 4 rows = 22 m); a stacked row counts as one fence of the budget. A post only holds up the ones above it: when a post breaks or is released, every post above it falls (`PostBehavior`).
- UI: second placement stage with its own title/hint (`placement.title_posts`, `placement.hint_posts`), a ghost of three cylinders (green/red), `Undo` (right-click / `Z`) removes the last step (a whole fence or a whole stacked row, `Breakable.remove_structure`), `Auto-place`, `Done`.
- Posts are ordinary destructible structures: they burn, break, score as damage and can be destroyed by any weapon.


### 2.3c Quick start (placement)
The placement bar has a **Quick start** button (`Placement._quick_start`): it places the catapults and the palisade fences of everybody automatically and starts the battle. Online only the seats of this machine are placed automatically (the other players place theirs).
\n### 2.4 BATTLE
Loop of turns. Each turn (`scripts/systems/turn.gd`), sub-phases:
1. `TURN_START`: banner "PlayerName's turn". Skip eliminated players. Roll wind change (section 6.3). Apply weather tick. Camera flies to the current player's village.
2. `SELECT_CATAPULT`: a human chooses which of their living catapults fires: click the catapult, press `Tab` / `Shift+Tab` to cycle (handled before GUI focus navigation), or click one of the numbered catapult buttons of the **catapult selector** (bottom right, shown when the player has more than one living catapult; the selected one has a red frame, destroyed ones are dark red). Default selected = last used still alive. CPU chooses by its own logic.
3. `AIMING`: slingshot aiming (section 6.1). Human also selects ammo in the ammo bar (keys `1`–`9`). Timer runs (if enabled). If the timer expires, fire with the current aim pulled at that moment (if never aimed: random angle at 50% power with Stone). **Instead of firing, the player may select one of the two turn actions** — `Reposition catapult` (key `U`) or `Build stone wall` (key `B`), slots 12 and 13 of the ammo bar (6.8); doing it ends the turn like a shot.
4. `FLIGHT`: projectile in flight. Camera follows.
5. `AFTERMATH`: physics continues until the world is **settled** (section 6.5). Camera shows the impact area; slow motion on big events. Fires keep burning during this phase but are not required to be out.
6. `TURN_END`: check eliminations (section 2.5). Apply fire/settler damage, update stats. If the living players belong to only one team → GAME_OVER (6.9). Otherwise next living player.
- Between turns the world keeps simulating (fires burn, settlers run), only the turn logic pauses at a fixed clock.

### 2.5 Elimination
A catapult is **destroyed** when `hp <= 0`, or it fell into deep water, or it was crushed (see section 11.1). A player with 0 living catapults is **eliminated** (if the last one is lost during the player's own aiming phase, the turn ends immediately and the normal checks run: eliminate, next player or game over; with other catapults left, the next one is selected automatically). A boulder or stone that merely rolls into a catapult (speed < 14 m/s after the first contact) does at most 12 damage and below 4 m/s none; bullet time only for real direct hits: show comic banner (random line from 12.5), the village remains as a burnable playground (all physics keep working). Eliminated players are skipped. A catapult destroyed by its own owner's shot counts normally (a "self-own" stat, see scoring).

Eliminations are checked at `TURN_END` only (not mid-flight) so simultaneous kills are processed together. If all remaining players are eliminated at the same turn end, the winner is the one with the most total remaining building HP; tie → "Everybody loses" screen.
**Teams**: elimination is per player; the game ends when only one team has living players. All members of that team win (1000 points each); the "most remaining building HP" tie rule above applies to the players eliminated in the same turn.

### 2.6 GAME_OVER
Results screen: winner with confetti and silly crown, ranking, stats table, titles (section 13), buttons `Rematch (same settings, new seed)`, `Play again same map`, `Main menu`. With teams the header names the whole winning team (`{names} win!`) and the ranking lists the winning team first.

---

## 3. Constants (`scripts/autoload/cfg.gd`)
`class_name Cfg` with `const` values (access as `Cfg.GRAVITY`). Values are authoritative; tune later only if noted:

```gdscript
class_name Cfg
extends RefCounted

const PHYSICS_HZ := 60
const MAX_SUBSTEPS := 3
const GRAVITY := -19.62                # stronger than real for snappy comic feel (set as project gravity 19.62)
const MIN_PLAYERS := 2
const MAX_PLAYERS := 8
const CATAPULTS_PER_PLAYER := 5        # maximum; the match uses Game.catapults_per_player (1–5, menu)
const ZONE_RADIUS := 22.0              # village zone radius, meters
const WORLD_UNIT := 1.0                # 1 unit = 1 meter
const MAX_DYNAMIC_BODIES := 900        # hard cap (quality-scaled, see 15)
const DEBRIS_LIFETIME := 25.0          # seconds after sleep before fade (Medium)
const SETTLE_SPEED := 0.35             # m/s: below this a body counts as still
const SETTLE_TIME := 0.8               # seconds all relevant bodies must be still (kept short: fast turn pacing)
const SETTLE_MAX := 8.0                # seconds max aftermath wait, then force end
const WIND_MAX := 8.0                  # m/s
const WIND_CHANGE_MAX := 3.0
const DRAG_MAX_PX := 220.0             # max slingshot pull in screen pixels (at 1600x900 reference; scale by window height/900)
const POWER_MAX_SPEED := 140.0         # m/s launch speed at 100% power; MUST reach every enemy on the largest map (see 6.1 'Guaranteed range')
const POWER_MIN_SPEED := 8.0           # at 0% (still valid > 8%)
const PREVIEW_FRACTION := 0.4          # show first 40% of predicted flight path
const CATAPULT_HP := 100.0
const SETTLER_HP := 30.0
const TURN_TIMER_DEFAULT := 30
const FIRE_TICK := 0.5                 # seconds between fire logic ticks
const FIRE_SPREAD_RADIUS := 3.2
const SLOWMO_SCALE := 0.25
```

---

## 4. Materials (`scripts/physics/materials.gd`)

| id | density kg/m³ | friction | restitution | breakForce (impulse threshold) | flammability 0–1 | burnHP/sec | hp per m³ | shard particle | hit sound |
|---|---|---|---|---|---|---|---|---|---|
| wood | 600 | 0.6 | 0.2 | 260 | 0.7 | 6 | 400 | splinter (brown) | thunk |
| plank | 550 | 0.55 | 0.25 | 160 | 0.75 | 7 | 250 | splinter (light brown) | clack |
| stone | 2300 | 0.8 | 0.1 | 900 | 0 | 0 | 1200 | dust (grey) + pebbles | crunch |
| brick | 1900 | 0.75 | 0.12 | 600 | 0 | 0 | 800 | dust (red) | crunch |
| thatch | 120 | 0.9 | 0.05 | 60 | 1.0 | 12 | 60 | straw bits (yellow) | swish |
| cloth | 80 | 0.9 | 0.05 | 40 | 0.9 | 10 | 30 | rag bits | fwump |
| metal | 7800 | 0.4 | 0.2 | 2500 | 0 | 0 | 3000 | sparks | clang |
| hay | 90 | 0.95 | 0.02 | 80 | 1.0 | 14 | 40 | straw bits | fwump |
| barrel_wood | 400 | 0.5 | 0.35 | 220 | 0.5 | 5 | 180 | splinter | thunk |
| glass | 2500 | 0.3 | 0.1 | 50 | 0 | 0 | 20 | glitter | tinkle |
| flesh | 1000 | 0.7 | 0.15 | n/a | 0.4 | 10 | n/a | (settlers only) | boing/splat-lite |

Physics body/shape properties: set friction, restitution (`PhysicsMaterial` or `PhysicsServer3D.body_set_param(BODY_PARAM_FRICTION / BODY_PARAM_BOUNCE)`), and mass = density × volume from this table. Configure friction/bounce combine mode as Jolt defaults.

`breakForce` semantics: when a contact-force event on a part (or a projectile/explosion impulse applied to it) exceeds `breakForce × part.size_factor` (size_factor = cbrt(volume)/0.3), the part takes damage = `(impulse − breakForce)/breakForce × 40`. A part with `hp <= 0` breaks (section 5.3).

---

## 5. Destructible Structure System (`scripts/physics/breakable.gd`)

### 5.1 Part
A **Part** is a single rigid box/cylinder with: `id`, `material`, `size (x,y,z)`, `hp`, `mesh instance`, `physics body RID`, `structureId`, `neighbors[]` (adjacent parts it is glued to), `burning` (0–1), `onFire` (bool), `flags`.

Hp = `material.hpPerM3 × volume`, minimum 10.

### 5.2 Structure and dormant/active optimization
A **Structure** is a building (or big prop). Performance rule:
- **Dormant**: the whole structure is rendered with merged static geometry (one mesh per material per structure) and has ONE static compound collider (a `StaticBody3D` with one shape child per part, or a static `PhysicsServer3D` body with multiple shapes). Zero dynamic bodies.
- **Awakening**: when a structure receives a hit (projectile/explosion within `radius + 2` m, or fire damage that breaks a part, or a neighbor structure collapses onto it), it is **awakened**: replaced by individual Part bodies (dynamic `PhysicsServer3D` bodies) **only for parts within the affected radius + 2 m**, others remain in the static compound body as a "remainder" that is rebuilt (or simply the whole structure is converted to parts if it has ≤ 60 parts). Simplification allowed: awaken the entire structure (all parts become dynamic, initially **sleeping** (`body_set_state(rid, BODY_STATE_SLEEPING, true)`) except those in impact range). Parts asleep cost almost nothing.
- Awakening must be done in one frame without visible popping (same transforms).
- After awakening, parts are held by **glue links** (5.3).

### 5.3 Glue links (fake joints, cheap)
**Ground loss**: when the terrain under a building changes (landslide steps, craters deeper than 0.5 m) every anchored part whose bottom now hangs more than 0.7 m above the ground loses its anchor (`Breakable.ground_changed`); the support rule below then drops whatever is no longer held, so buildings never float over a landslide or crater.
**Support rule v2 (overhangs fall)**: a part stays when it stands on a part that stands (resting contact: its bottom touches the top of a supported linked part; anchored parts are the roots) or when it hangs at most `CANTILEVER = 3` links sideways / downwards off such a part. Everything else is released and falls. So when the lower storey of a house is shot away, the upper storey, sticking-out floors, walls and roofs no longer float on their glue links but come down (`Breakable.support_check`, depth-relaxed BFS).

Do NOT use physics joints for building parts. Use logical links:
- Each Part has `links[]` to neighbor parts (built at build time: parts whose boxes touch/overlap by ≤ 0.05 m).
- While linked, a part is dynamic but its body is kept **frozen** until a link is broken: parts with all links intact are static-mode bodies (`BODY_MODE_STATIC`) that the awakening logic converts to `BODY_MODE_RIGID` (`body_set_mode`) only when they are "released".
- **Release rule**: a part is released (becomes dynamic) when (a) its hp <= 0 (it is destroyed → also becomes a broken **debris piece**, possibly split, see below), or (b) it loses support: run a **support check** (BFS over links) from all "ground-anchored" parts (parts with `anchor:true`, e.g. foundation, or touching terrain); every part not reachable from an anchor is released. Run the support check after any part is removed (max once per 0.1 s per structure, budgeted).
- Released dynamic parts take normal physics, collide, break more when they hit things (impulse rule of section 4), and add damage to whatever they land on (including settlers and catapults).
- Damage propagation: when a part's hp reaches 0 it "breaks": remove it; spawn 2–4 smaller **shards** (dynamic small boxes, 40% of the size each, material same, no links, are `debris` with lifetime) and particles (material shard particle), play its hit sound, spawn comic text sometimes (5% chance).
- Performance: cap shards per structure to 40; beyond that spawn only particles.

### 5.4 Damage sources
`scripts/systems/damage.gd` exposes:
- `damage_parts_in_radius(pos, radius, max_damage, falloff := "linear", source)` — for explosions.
- `apply_impact(part, impulse, source)`.
- `damage_catapult`, `damage_settler`.
Each call records `source` ({playerId, projectileType}) so stats can attribute damage/kills. Attribution for indirect damage (collapse, fire) inherits the last `source` that hit the structure within the last 20 s.

### 5.5 Debris cap
`scripts/physics/debris.gd`: Track all dynamic non-essential bodies (shards, released parts, props). When count > cap (scaled by quality) remove the oldest sleeping ones first (fade scale to 0 over 0.4 s, free the body RID and the visual). Bodies sleeping longer than `DEBRIS_LIFETIME` are removed similarly if they are shards (not full released parts of buildings; those stay unless cap exceeded).

---

## 6. Core Gameplay Mechanics

### 6.1 Aiming (slingshot in 3D)
- Catapult model has a base (rotates around Y = azimuth) and an arm. Camera in AIMING sits behind and above the selected catapult looking along its facing direction (chase camera, ~9 m behind, ~5 m up, FOV 60). Right mouse drag orbits camera slightly (±60° yaw, ±25° pitch) without changing the aim. **The mouse wheel zooms from 4 m to 260 m**: beyond 16 m the camera climbs steeply (+0.8 m height per metre) and looks further ahead (+0.45 m per metre), so zoomed far out it becomes a map view with the catapult in it, and it can be zoomed in and out at any time, also during the shot.
- Left mouse (`InputEventMouseButton`/`InputEventMouseMotion`): press on/near the catapult (or anywhere, "drag anywhere" is accepted) starts a pull. While dragging:
  - Pull vector = current mouse pos − start pos (pixels), clamped to length `DRAG_MAX_PX`.
  - **Power** = pullLength / DRAG_MAX_PX (0..1) → speed = lerp(POWER_MIN_SPEED, POWER_MAX_SPEED, power).
  - **Azimuth (screen-true)** = the world heading that the *opposite of the pull vector* points to **on screen**. Project the catapult to screen, add the launch direction (−pull, normalized) × 120 px, unproject that point onto the ground plane at the catapult's height, and use the heading from the catapult to that point (fallback when the ray misses the ground: camera-forward/right flattened onto the ground). So the on-screen arrow, the rubber band (exactly opposite), the catapult's rotation and the real flight direction always agree. Range: any 360°.
  - **The camera must not rotate during a pull**: while dragging, the chase camera's base yaw is frozen (otherwise the screen axes move under the cursor and the arrow lies). After release / when not dragging the chase camera eases back behind the catapult's new heading.
  - **Elevation** is *not* part of the pull (it would fight with the screen-true heading). Default 30°, range 5°–80°; changed with `Arrow up/down` (also while pulling; hold = 15°/s, `Shift` = fine) and `Shift+mouse wheel` (±1.5° per notch). The HUD aim info shows it; the preview updates live.
  - **Direction arrow**: a white arrow is drawn from the *catapult's own screen position* along the projected world heading, so it is faithful by construction (it is the projection of the real launch direction).
  - **Guaranteed range**: at 100% power, best elevation, worst-case ammo (highest drag: cow) and adverse max wind (storm, 14.4 m/s head-on), a shot MUST be able to land at least `1.15 ×` farther than the largest catapult-to-enemy-building distance that can occur on any generated map (8 players, radius `60 + 14·8`). Increase `POWER_MAX_SPEED` — never shrink the map — if this fails. A unit test checks it over many seeds. The preview dots adapt their spacing so that they always cover `PREVIEW_FRACTION` of the flight, and scale with camera distance so far shots stay visible.
  - Visual: the catapult arm rotates back proportionally, a rubber band/rope stretches, a small pull indicator UI arrow shows power.
- **See-through instead of hiding**: while a catapult aims or fires, every building / tree / post whose bounding box lies between the chase camera and the catapult fades to about 12% opacity (`GeometryInstance3D.transparency` 0.88, eased at 4 per second; physics unchanged) and fades back when the catapult has fired or another one is selected (`Main._update_occluders`). Nothing disappears completely.
- Release: fire. Cancel by pressing Esc or by pulling back to < 10 px.
- **`Q` / `E` turn the catapult** (2°/tick at 30 Hz, `Shift` 0.4°) — also **while the slingshot is being pulled** (the correction is added to the screen-true heading as a trim until the pull ends). Keyboard fine-tune: Arrow left/right = azimuth ±0.5° (Shift ±0.1°), Arrow up/down = elevation ±0.5° per step, `A/D`... not used. Fire with `Space` using the current values, power held by keys `W/S` ±2%. `M` turns the catapult toward the map marker (6.7). While aiming a **range readout** next to the aim info shows `predicted landing distance` and, if a marker exists, `distance to marker` with the signed difference ("−12 m short" / "+8 m long").
- **Trajectory preview**: simulate ballistic path with gravity, wind acceleration and the projectile's drag (no collisions except terrain), sample points every 0.05 s. Compute full flight time until y < terrain height. Draw only the first `PREVIEW_FRACTION` (40%) as dotted line of spheres (one `MultiMeshInstance3D`, pool of 40) whose alpha fades toward the end. Not drawn for Cow/Cheese? — Drawn for all ammo types; per-ammo drag modifies it.
- Predicted preview is computed with the same function used by the CPU (`predict_trajectory(pos, dir, speed, ammo, wind)` in `scripts/systems/turn.gd`).

### 6.2 Projectile launch
- Muzzle position = catapult arm tip. Initial velocity = direction × speed, plus small random spread of `±0.5°` (none for Stone at ≥ 50% power? no, always ±0.5° for everyone, mandatory for fairness).
- Projectile is a dynamic physics body with continuous collision detection enabled. Wind applies as constant acceleration: `a_wind = windVector × ammo.windFactor` (windVector in m/s² = wind speed × 0.35).
- Camera FLIGHT: follows the projectile from behind/above with smoothing; when it hits, switches to impact-cam.
- Time out: if the projectile is still moving 12 s after launch or falls below y = −30, it is despawned (miss).

### 6.2b Impact strength and ploughing through
- Stone/cow impact: parts within `1.6 + speed/40` m (stone, max +2.6) or `2.2 + speed/30` m (cow, max +3) receive `mass × speed × IMPACT_K` (`IMPACT_K = 11`) through the break-force rule (section 4) with falloff; settlers within radius + 1.2 m are hurt and launched. Direct catapult hit: `mass × speed / 22` damage.
- **Ploughing**: if an impact destroys parts of a building, the projectile keeps its direction and most of its speed (`0.92 − 0.04 × partsBroken`, at least 0.45 of the impact speed; 0.9 max for the cow) and rolls/ploughs on through the village, hitting (and damaging) whatever comes next. Hits on the bare ground damp the body strongly so miss-shots stop quickly; hits on buildings use light damping so the stone may roll a few more meters.

- **Masonry**: parts made of `stone` or `brick` take projectile impact energy ×2.6 and `IMPACT_K` is 14, so a fast stone drives through tower walls instead of bouncing off them.

### 6.3 Wind
- Vector (windX, windZ) with speed ≤ `WIND_MAX`. Each turn start: change speed by random ±`WIND_CHANGE_MAX` and rotate direction ±40°. During Storm weather multiply by 1.8.
- HUD: wind arrow + speed, plus flags and smoke in the world lean accordingly (flags on buildings: cloth part with sine deformation; simple).

### 6.4 Ammo (per player inventory)
**In the catapult's bucket the ammo looks like what it is** (`Projectile.bucket_visual`: barrels lie across the arm, the log lies across, the cow, the chain, the boulder potato, four stones for the hail ...). **Powder keg fuse**: while a powder keg flies its fuse hisses and crackles (looped sound `fuse`, attached to the keg with `Sfx.attach_loop`) and spits sparks from the fuse tip every 0.045 s. Eleven weapons in this order: Stone, Stone Hail, Chain Shot, Boulder, Pointy Log, Flaming Barrel, Powder Keg, Flints, Cow, Black Powder Kegs, Meteor Marker; then the two **turn actions** (slot 12 `U` Reposition catapult, slot 13 `B` Build stone wall, `AmmoDef.kind = "action"`, unlimited, never earnable). Keys: `1`–`9`, `0` (slot 10), `-` (slot 11, also `/` or `ß`), `U`, `B`, or click. **The ammo bar is flat**: 52×52 px slots (key bubble top left, count at the bottom, icon scaled 0.6), **weapons have a slightly reddish rim, the two actions a grey rim** (selected: bright red resp. dark grey rim, lifted). **Icons** are drawn by `AmmoSlot._draw_icon` with primitives (shaded balls, staved barrels with iron bands, flames, **the cow as a detailed front-view head**: curved horns, leaf ears with pink insides, a dark eye patch, big pink muzzle with nostrils and a **straight mouth**, a sack with pellets, a log with rings and rotation arcs, a marker orb with beam, a catapult with drive arrows, a crenellated wall); locked weapons are dimmed and show a padlock (not the actions). **Tooltips** (`AmmoSlot._make_custom_tooltip`, texts `ammo_tip.<id>.what/pro/con` in both languages): name, one line what it is, then short **advantages in green (`+`) and drawbacks in red (`-`)**, font 12–15, 230 px wide, ONE parchment border (the theme's `TooltipPanel` draws it). Writing rules for the tips: seconds are written out ("Sekunden" / "seconds"), "no fire" is never listed as a drawback, rolling weapons (Boulder, Flaming Barrel, Black Powder Kegs) list "rolling direction is hard to predict", scattering weapons (Stone Hail, Flints) list "spreads far apart at long range", the log says "10x more damage", the Meteor Marker has no drawback, the Black Powder Kegs have ONE advantage (spreads powder that stays and, with later shots or any other fire, causes heavy damage) and the drawback "almost no damage on its own", Reposition lists "ramming damages your own buildings" as a drawback.
| # | id | EN name | DE name | start count | mass kg | radius m | windFactor | effect |
|---|---|---|---|---|---|---|---|---|
| 1 | stone | Boring Rock | Langweiliger Stein | ∞ (always) | 40 | 0.45 | 0.3 | Heavy impact. Direct damage. |
| 2 | quad | Stone Hail (x4) | Steinhagel (x4) | earned | 40 each | 0.45 | 0.3 | **Four stones at once**, behaves like the stone (`AmmoDef.base = "stone"`) but each stone only has **30% of the damage** (`Projectile.power_k`). Distribution like the powder keg volley: the primary stone flies straight, two more fan out ±1–2.2°, the fourth is a little short or long (±0.8–1.8° elevation). Only the primary stone counts as the shot (camera, score, landing); the others are `is_extra`. |
| 3 | chain | Chain Shot | Kettenkugel | earned | 80 (two balls) | 0.4 per ball (slightly smaller than the stone) | 0.25 | **Two black iron balls on a short chain (2.3 m)**: ONE body with two sphere shapes, spinning flat around the vertical axis at **26 rad/s (≈4 turns per second, ≈30 m/s at the balls)**. Each ball hits with **twice the punch of a stone** (energy = 80 kg × (speed + 0.45 × whirl speed)); after the first impact the balls keep smashing what they touch while the chain tumbles (every 0.1 s, `_tick_chain`) for up to 5 s. Black balls, grey links. |
| 4 | boulder | Mighty Boulder | Gewaltige Felskugel | earned | 13800 | ≈1.035 (2.3× the stone's 0.45; 15% bigger and heavier than before) | 0.12 | **Not a sphere but a lumpy potato, different every shot**: a sphere with 4–6 broad bumps/dents (±15–17%), slight axis stretching (0.8–1.15) and in 30% of the shots one outlier lump (+22–38%); the collision shape is the **convex hull of exactly the vertices of the visual mesh** (`Projectile._boulder_geometry`, `PhysWorld` shape type `convex`), so the shape decides how it tumbles and rolls — it is deliberately unpredictable. About 2.3× the size and ≈350× the mass of the stone (**13.8 tonnes**; trajectory, wind and drag are unchanged by the mass); impact energy ×1.73 (15% stronger than before), smash radius 2.75–6.15 m, **does not bounce off buildings**: its collision restitution is 0, **everything solid within 1.3 × its radius + 0.4 m of its centre is torn out for certain when it hits (speed > 6 m/s)** and again every 0.1 s while it rolls (`Damage.smash_in_radius`), so it tears straight through walls; per hit it keeps at most 95% of its speed (−1.5% per destroyed part, min 60%) and 90% of its old heading is restored (6.2b), so walls get huge holes instead of throwing it back. It **keeps rolling** (light damping) for up to 10 s and **keeps crushing while it rolls**: every 0.1 s at speed > 3.5 m/s it smashes parts within 2.1 m (energy ×0.52; each destroyed part takes 2.5% of its speed, min 70%) and hurts settlers within 2.6 m. The impact camera follows it while it rolls **and keeps the village that is being hit in the picture** (focus halfway between the rolling object and the village centre, camera distance grows with their separation, 34–120 m). |
| 5 | log | Pointy Log | Spitzer Baumstamm | earned | 300 | 5.4 m long, ⌀0.6, pointed at both ends (convex hull) | 0.2 | A tree trunk that leaves the catapult **pointing along the flight direction** and turns slowly (**0.3–0.7 turns per second**) end over end in the vertical plane of flight (about the horizontal axis across the flight, plus a little roll), so a tip points forward most of the time; about 28% of the logs lie across the flight and roll like a rolling pin instead (they land flat and only thump). Only the first ground contact can plant the log - or a later one once the log has hit a building (rolled off a roof or wall). A log that does not stick stays lying for the whole match (it is exempt from the debris fade). On open ground ≈70% of the shots stick, measured with `--autotest=lograte`. Little mass: hitting **crosswise** it only thumps (energy × 0.25). If a **pointed end** arrives first (contact within 1.0 m of an end and the end moving along the flight direction, cos > 0.3) the impact energy is computed **internally ×10**; if that tip hits the ground (speed > 9 m/s) the log **sticks in the ground (tip 1.3 m deep, steep) as a static obstacle for the rest of the game** (other shots bounce off it; a blast such as the meteor tears it loose again: `Projectile.release_stuck_logs`). |
| 6 | firebarrel | Flaming Barrel | Brennendes Fass | earned (0 at the start in every preset except those that grant some) | 60 | 0.42 (cylinder, lying) | 0.25 | A flaming barrel with a real **barrel-shaped collision hull** (bulging staves, 0.42 × 0.98 m, convex hull) that lies on its side and rolls along its curved belly like a barrel, not like a ball. **It does not explode: it bounces off houses and trees and rolls on for a few seconds** — a rolling assist keeps it at ≥ 9 m/s for 3.5 s after its first impact, it burns out after 5.5 s (or 3 s once it has stopped) — and **every touch sets flammable things alight** (ignite radius 3.2 on contact, 2.1 while rolling, leaves ground fires, sets settlers ablaze). Moderate impact damage (30% of a stone). The impact camera follows it while it rolls **and keeps the village that is being hit in the picture** (focus halfway between the rolling object and the village centre, camera distance grows with their separation, 34–120 m). |
| 7 | powderkeg | Mighty Powder Keg | Mächtiges Pulverfass | earned | 35 | 0.5 | 0.4 | Explodes on impact: **radius 12, max damage 1700**, plus a pressure wave (11.2). Flies and tumbles as a real barrel (convex barrel hull 0.42 × 0.78 m). |
| 8 | scatter | Flints | Feuersteine | earned | 30 | 0.4 | 0.35 | Splits at apex or on impact into **24 flints (mass 9 each, radius 0.24)** scattering in a 2–20° cone; each smashes parts in 1.3 m (energy ×9), hurts settlers in 2.2 m (30) and sparks fires. Split when velocity.y <= 0 first time, or at impact. |
| 9 | cow | Moo-nition (a Cow) | Muh-nition (eine Kuh) | earned | 250 | 0.9 | 0.15 | A cow body + head. **On its first impact it bursts into 34 red chunks** (mass 8, radius 0.2, 16–40 m/s, flat fan around the impact normal) that fly outwards like small projectiles in a **flat fan along the ground** (little lift, vertical speed capped at 22%): each smashes parts in 1.3 m, hurts settlers in 2.2 m (30 damage) and splats; plus a heavy kinetic hit (radius 2.4–5.4 m, energy ×0.7), 80 damage to settlers within 6 m and a bowling pressure wave (radius 11). |
| 10 | powdertrail | Black Powder Kegs | Schwarzpulver-Fässer | earned | 28 each | 0.27 (small barrel hull 0.27 × 0.62 m) | 0.25 | **One shot launches FIVE small kegs** (the aimed one plus four in a tight fan of ±0.8–3° and ±0.55 m offsets); they roll **like Flaming Barrels** (same barrel hull, bounce off houses and trees) but a little longer: roll assist 4.8 s, burn-out after 7.5 s (4 s once stopped) but instead of fire they **leave black powder**: irregular heaps on the ground (about every 0.09 s with 85% chance, jittered ±1 m) and powder smeared on every building part within 1.5 m of a contact; at the end of its roll a keg bursts and sprays its powder (see 15.2 note / 11.6 and the balance notes). Extra kegs do not score as shots of their own. See 11.6 for what powder does. |
| 11 | meteor | Meteor Marker | Meteoriten-Markierung | earned | 30 | 0.3 (small, glowing green ball) | 0.3 | **Orbital strike** (replaces the Big Red Barrel). The ball itself does nothing. Where it lands (ground, building or water) it stays as a glowing marker, a **thin bright translucent green beam** shoots into the sky and a pulsing ring marks the spot. After **3.6 s** a **burning meteor** (a lumpy rock with a **lava shader** (dark crust, glowing cracks that crawl, hot rim), three additive glow shells, two fiery ribbon trails, flames / sparks / smoke every 0.05 s, an orange light, ≈105 m/s from a diagonal ≈330 m up) falls onto **exactly that point** (`entities/meteor.gd`). Impact: explosion **radius 64, max damage 18000 (twice the old red barrel)**, everything in 80% of the radius burns, pressure wave, catapult scale 0.12, 22 glowing fragments, and a **fat crater** (radius 30 m, depth 12 m, raised rim, landslide), a white screen flash (`Events.screen_flash`), a fading blinding light, thunder, four smoke/fire columns up to 50 m and a lava pool in the crater that cools over 30 s. **Cinematic camera, no bullet time**: slow orbit round the beam tilting up (3.6 s), the camera holds and follows the falling rock down to the point, shakes harder as it comes closer, then pulls back to a wide orbit over the crater (4.5 s). Slowmo requests are ignored during a strike; clicks/Space cannot skip it. |

**No water weapon and no cheese weapon exist** (the old Water Balloon and Holy Cheese were removed). Goats and chickens are never ammunition. (The random event "Cheese Meteor" stays as a joke event, 11.5.)

### 6.4b Weapons are earned (`systems/unlocks.gd`)
- **Only the Stone is unlimited. Every other weapon starts at 0** unless the chosen **starting arsenal preset** (2.1) grants it (counts are absolute, -1 = unlimited), and is **locked** in the ammo bar (dimmed, padlock) until the player earns it. `AmmoDef.earnable` marks the eleven weapons (the Stone and the two actions are not earnable); `PlayerData.reset_ammo(start)` applies the arsenal. Unlocks work in every preset.
- Earning rules (each grants +1 to ONE player and announces it: kill feed line, banner + toast for humans, stinger sound; `unlock.*` strings in both languages). **Rules come in tiers and the game mode decides which are active** (`Game.rule_level` 0 core / 1 power / 2 chaos, `Game.rule_quarry`; Standard = core, Powerplay = core + power, Quarry = core + quarry, Chaos = core + power + chaos; Custom: the player picks the tier in the `Unlock rules` dropdown of the menu, the `?` button lists the active rules per weapon; the tier travels in the lobby / start messages as `rules`, `rquarry`). The table in `Unlocks.RULES` is the single source: weapon -> [tier, key]; the tooltip of a locked weapon in the ammo bar shows the active rules (`unlock_how.<key>`) under a padlock line. Online only the host evaluates the rules (`grant` messages).

| Weapon | Core (always) | Power | Chaos | Quarry |
|---|---|---|---|---|
| Buckshot (scatter) | destroy an enemy catapult | | | |
| Mighty Boulder | lose a catapult; your landslide wrecks an enemy building | wreck an enemy powder store | wreck an enemy tavern | wreck an enemy windmill |
| Powder Keg | your own blacksmith is destroyed; a team mate is eliminated | wreck a catapult of the player who wrecked one of yours (revenge) | own goal: wreck a building of your own / a team mate (once per turn) | |
| Black Powder Kegs | you are down to your last catapult; a team mate is | | | |
| Cow | one of your own cows dies in your camp | | another animal of your camp dies; wreck an enemy building AND launch an enemy settler in one turn; a cow wrecks one of your catapults | |
| Pointy Log | damage 3 different trees; a tree within 45 m of your village is shot down (by anyone) | | | 2 trees instead of 3 |
| Stone Hail (x4) | wreck 2 buildings with one shot; a team mate wrecks an enemy catapult | | | |
| Chain Shot | launch 5 settlers with one shot | wreck 3 buildings with one shot | | |
| Flaming Barrel | every **3rd turn** in which you set something on fire (**counted per turn**: a spreading fire is one fire); a team mate loses a catapult | | every 2nd such turn instead of every 3rd; anybody (not on the victim's team) loses a catapult | |
| Meteor Marker | **only the supply crate** (below) | | | |

Powder barrels exploding earn **no** weapon (chain reactions still pay points). Team rules (grant to the OTHER members of the team) only matter when teams exist; the meteor is never handed to team mates.

**Supply crates** (`systems/supply_crate.gd`, `SupplyCrate`; all can be switched off with the `Supply crates` option, `Settings.crates_on` -> `Game.crates_on`, synced in the lobby / start messages as `crates`). They sink on parachutes, land and stay until a shot hits one (any projectile, `try_hit` from the projectile sweep; the hitter gets the content; confetti).
- **Meteor crate**: the only source of the Meteor Marker. Green glow, green beam, label "Supply crate", sinks from 75 m at 2.2 m/s at a spot **between two villages** (>= zone radius + 10 m from every village, above water). Announced with banner, toast, a short camera look and the epic sound `crate_epic`; a **fanfare** (`fanfare`) plays when somebody hits it. Appears at the earliest after **every living player has fired 5 shots**, 45 % chance per turn end, at most **once per match (Standard / Quarry) or twice (Powerplay, Chaos)**, a new one 8 / 6 / 4 turns after the last was collected (core / power / chaos).
- **Small crates**: plain wood, no glow, no announcement, no sound beyond a thud: **3 boulders or 5 logs** (50/50). They land **just outside the villages** (3-9 m beyond the zone radius, so you see them and may hit one by accident). As many at the same time as there are living players (**+30 % in Powerplay, +50 % in Chaos**), one new per turn end while below that number.
Online the host sends `crate` (id, kind, x, y, z, ammo, n) and `cratego` (id, player id).

**No water weapon and no cheese weapon exist** (the old Water Balloon and Holy Cheese were removed). Goats and chickens are never ammunition. (The random event "Cheese Meteor" stays as a joke event, 11.5.)

### 6.4b Weapons are earned (`systems/unlocks.gd`)
- **Only the Stone is unlimited. Every other weapon starts at 0** unless the chosen **starting arsenal preset** (2.1) grants it (counts are absolute, -1 = unlimited), and is **locked** in the ammo bar (dimmed, padlock) until the player earns it. `AmmoDef.earnable` marks the eleven weapons (the Stone and the two actions are not earnable); `PlayerData.reset_ammo(start)` applies the arsenal. Unlocks work in every preset.
- Earning rules (each grants +1 to ONE player and announces it: kill feed line, banner + toast for humans, stinger sound; `unlock.*` strings in both languages):

| Weapon | Earned by |
|---|---|
| Buckshot (scatter) | destroying an enemy catapult (shrapnel from the wreck) |
| Mighty Boulder | losing a catapult (every time: revenge); a landslide you started wrecks an enemy building (once per slide) |
| Powder Keg | **your own blacksmith is destroyed** (by anyone); blowing up powder barrels earns no weapon (chain reactions still pay points) |
| Flaming Barrel | every 8th fire you start (none at the start unless a preset grants some) |
| Black Powder Kegs | **only when a single catapult is left** (losing a catapult leaves you with exactly one) |
| Cow | **one of your own cows dies in your own camp** (killed by anyone or anything, e.g. a fire) |
| Pointy Log | damaging 3 different trees (counter resets after each log); **a tree within 45 m of the player's own village centre is shot to pieces (by anyone)** — the owner of that camp gets the log (`Unlocks.on_tree_destroyed`, called when a tree structure counts as destroyed) |
| Stone Hail (x4) | wrecking 2 buildings with one shot |
| Chain Shot | launching 5 settlers with one shot |
| Meteor Marker | destroying an enemy church or powder store; eliminating an enemy player (the last player who damaged them gets it) |

- Being hit therefore pays back a little (boulder / keg), real achievements pay more. CPU players earn weapons by the same rules and use them (section 14).
- The ammo bar shows the count; slots with 0 are disabled. Keys `1`–`9` select, locked weapons cannot be selected.

- Projectile detonation: on first contact with anything except own launching catapult during the first 0.3 s.
- **Ammo choice is per player**: every player keeps their own selected ammo (initially Stone); a choice made by player 1 is never inherited by the next player. If the stored ammo ran out, Stone is used.
- Bot (King) uses ammo per section 14.

### 6.5 Settled detection and turn pacing
Turns must feel brisk: `TURN_START` banner phase 1.0 s, the settle check starts 0.5 s after the first impact. **A shot that did nothing relevant** (no damage to anyone, no blast, no fire, no kills, no bees/stink) **ends the turn 0.9 s after the impact** with only a 0.35 s `TURN_END` pause. **A shot that did something** keeps the impact camera in place for at least 2.0 s (2.8 s for scores above 250, 6 s for the meteor) before the world may count as settled, and holds 1.5 s at `TURN_END` so the camera never leaves the impact while the destruction is still playing out.
When a projectile splits in the air (Buckshot, cow burst) the camera keeps following the pieces towards the target and then sits on the first piece's impact; it never swings back to the shooter (`Projectile.last_pos`, `last_impact_pos`). The impact camera must also work when the projectile detonated in the very tick of the impact (keg, red barrel, hive, cow burst): the impact position is recorded separately (`Projectile.last_impact_pos`). Impact cam: 26 m away at 48° pitch, never pulled in by the camera-arm raycast.
**Skipping**: after the first impact of a shot (phase `AFTERMATH`) a click or `Space` ends the turn immediately and moves on to the next player (a hint is shown); before the first impact it does nothing. **Fast-forward** (key `F`, the HUD button `[F] Fast-forward`, and `Space` when it is not a human's aiming phase): runs the simulation at 3× (physics ticks ×3 together with `Engine.time_scale = 3`, so every physics step stays 1/60 s). It is available at any time — in particular during CPU turns, during flight and aftermath — and switches itself off when a human's aiming phase begins, at game over and when a match is left.
The world is **settled** when, for `SETTLE_TIME` seconds continuously: all projectiles are gone, no explosion is active, and the fastest awake dynamic body in the "relevant set" (all bodies within 40 m of any impact this turn, plus all catapults) moves slower than `SETTLE_SPEED`. Ignore settlers that are alive and walking, animals, particles, and fire. Force end after `SETTLE_MAX` seconds.

### 6.7 Map marker (per player, one at a time)
A player can place **one map marker** to remember where an enemy is (or where a good target lies):
- In the overview camera (`V`) a plain **left click** on the ground (not a drag; right/middle mouse keep orbit/pan) sets the marker at the picked terrain point. Setting a new marker **removes the old one**; clicking very close to the existing marker (< 4 m) or `Shift+click` removes it. A click on the HUD is ignored.
- The marker belongs to the player who set it and **persists across turns and camera modes** for the whole match. It is visible to its owner **and to the owner's teammates** (6.9): a teammate's marker is drawn as an extra beacon with the owner's name above it (`MapMarker.slot`), and a player without a marker of their own gets a teammate's one in the aiming compass / `M` (`Game.marker_for`). Enemies and CPUs never see or use it. Online the marker is sent to all machines (`marker` message).
- In the world it is a tall beacon: a pole with a pennant in the owner's color, a pulsing ground ring and a faint vertical light beam, visible from far away (also in the aiming camera and overview). Unshaded, drawn above fog.
- **During aiming** the marker's direction is always shown: (a) a dashed ground line from the selected catapult toward the marker (screen-space overlay of the projected ground points), (b) a compass chevron on the screen border / over the marker position with `<distance> m` and the bearing difference to the current aim, e.g. `Marker 142 m · 12° right`, (c) the range readout from 6.1. `M` snaps the azimuth to the marker; `R` (face next enemy) is unchanged.
- Toast on set / clear; HUD hint in the overview. Strings under `marker.*` in both language files.

### 6.6 Damage to catapults
Catapult is a compound of parts (base, 2 wheels, arm, bucket) but tracked as a single entity with `hp = 100`. Damage arises from: direct projectile hit (impulse/40), explosions (via damage falloff), falling debris (impulse above 500 → (impulse−500)/30), fire (2 hp/s while burning; catapult is wood so burns), being crushed. Tipped over (up vector y < 0.2 for 3 s) = disabled: counts as destroyed. Upon destruction: catapult breaks into its parts (dynamic pieces), with fire and smoke and a comic text (section 12.4).

---

### 6.8 Turn actions: reposition a catapult, build a stone wall
Instead of a shot a human can spend the turn on one of two **actions** (ammo-bar slots 12 and 13, grey rim, keys `U` and `B`; always available, unlimited). Code: `ui/actions.gd` (input, ghost, driving), `world/walls.gd` (walls), `Turn.do_action` / `Turn.net_act` (the action happens identically on every machine, then the phase goes to `AFTERMATH` with an empty `shot_ammo`, so the turn ends about 0.9 s later). Switching to another weapon before the action is confirmed cancels it (a started drive is undone). If the timer runs out during a drive, the drive is undone and the normal timeout shot happens. CPUs do not use the actions.

**Reposition catapult (`U`)** — the selected catapult is driven with `W`/`S` (forward / back, 5 m/s) and `A`/`D` (turn, 75°/s) under the chase camera; `Space` / `Enter` confirms and ends the turn. **There is no distance limit** (the HUD only shows the distance driven). Allowed ground: inside the own zone + 3 m, dry, slope ≤ 30°, no other catapult within 3.6 m. **People, animals, debris and loose props never block** (props are shoved aside). **Buildings are rammed**: every frozen building part under the frame takes 450 damage per second (`Actions.RAM_DAMAGE`, attributed to the driver, so it costs points when it is the own village), and only a part that survives blocks the way (wood breaks, stone foundations hold; a still dormant structure is woken first). Ramming makes screen shake, a crash sound, a comic "crash" and a neighbour within 18 m shouts a `speech.bump` line (at most every 2.2 s). Online the final pose and the rammed parts (`hits`) are sent so every machine repeats them; the other players see the catapult jump at confirmation.

**Build stone wall (`B`)** — works exactly like the palisade fences (2.3b) but during the battle: a green / red ghost follows the mouse over the ground (camera in focus mode on the own village, right drag orbits), `Q`/`E` turn it, a click builds it, a wall set next to the end of another one continues it in a straight line (`Walls.snap`, 3.4 m), a click on an own wall stacks another layer on top. Geometry (`Walls`): one layer is **as wide as four palisade fences** (4 × 3 posts × 0.52 m = **6.24 m**), **60% as high as a post** (0.6 × 5.5 = **3.3 m**) and 1.0 m thick, built from stone blocks in a running bond (6 per row, 4 rows, colour `#8a9096` like the castle ruins) with **5 crenellations on top. Only the topmost layer carries crenellations**: stacking silently removes the ones below (`Breakable.discard_part` after waking the structure). At most 6 layers per wall and 14 layers per player. Valid ground: `Posts.area_ok` (own zone + 25 m, never near an enemy village), 9 sample points dry and not steeper than 35°, height spread ≤ 1.3 m, nothing solid and no own wall in the way; the base sits at the lowest sample so no end hangs in the air. A layer is one `Structure` of kind `playerwall` (name "Sturdy Wall"), bottom row anchored; a `LayerBehavior` makes the blocks above fall when blocks below them are broken or released. **Stone is sturdier than the palisade wood**: 1200 hp/m³ and break force 900 against 400 / 260 for wood, and it does not burn. Building a wall pays +20 points (silent). Online: `act` with centre, yaw and `stack`, built with the host's random seed.

### 6.9 Teams
- **The player colour is the team.** `PlayerData.team = colour index`; players with the same colour are allies, there is no limit and no symmetry rule (3 v 1, 2 v 2 v 1 … all fine) and the turn order is unchanged. A match needs at least two different colours (the menu disables `Start battle` otherwise).
- API: `PlayerData.is_ally(o)` / `is_enemy(o)`, `Game.living_teams()`, `Game.team_members(team)`, `Game.is_winner(p)`, `Game.marker_for(p)`.
- **Winning**: eliminations stay per player; the game is over when the living players belong to one team; every member of that team wins together (1000 points each, banner `{names} win!`, results header and ranking list the team).
- **Allies**: bots never pick an ally as a target; `R` (face next enemy) skips allies; placement / palisade defaults face the nearest enemy. Hits on an ally (damage, buildings, catapults, settlers) are scored like hits on oneself (self damage and penalties); splash damage can still hit allies.
- **Marker**: shared inside a team (6.7), also online.
- **Recognition**: a flagpole with a big team-colour flag in every village (8), team-colour window frames (a darker shade) on farmhouses and tavern, the existing banners / catapult flags / marker pennants use the same colour.
- Online the colour index is part of the `start` message, so every machine derives the same teams.

## 7. Map Generation (`scripts/world/mapgen.gd`, `scripts/world/terrain.gd`)

### 7.1 Seed
`seed` string → hashed to a 32-bit integer → mulberry32 (`Rng`). All generation uses this RNG only (never `randf()`/default `RandomNumberGenerator`). Gameplay randomness during battle (spread, settlers) uses a separate RNG seeded with `seed + '-battle'`.

### 7.2 Size
`baseRadius = 60 + 14 × playerCount` (2 players = 88 m … 8 players = 172 m); **the real `mapRadius` is `min(baseRadius × rand(1.3, 3.0), 300)` per seed** (up to twice as big as before), so every map has a different size and the distance to the enemy (and the power needed to hit it) differs from game to game (2 players: villages 58–360 m apart, median 124 m, in a 40-seed probe, `tests/map_probe.gd`). The menu shows the possible range. Terrain is a square heightfield of side `2 × mapRadius + 40`, resolution 1 vertex per 2 m (max 256×256). Circular island shape: heights fall below sea level near the border (`waterLevel = -0.5`), water plane at y = waterLevel. Outside island: infinite sea (large plane).

**Terrain hilliness (menu option, `Settings.terrain_hills` 0–4, default 2 = Normal)**: Flat / Gentle / Normal / Hilly / Mountainous. Main height noise amplitude 2 / 10 / 26 / 34 / 44 m plus broad hills and valleys of ±0 / 4 / 16 / 24 / 35 m; **Mountainous additionally adds sharp ridges** (`ridge² × 30 − 10` m at 1/110 m frequency) and is deliberately drastic (probe `tests/hill_probe.gd` on 3-player maps: slope > 25° on 2% / 2% / 10% / 25% / **58%** of the land, slope > 36° (landslide-capable) on 1% / 2% / 3% / 7% / **31%**, highest point 5 / 11 / 29 / 40 / 71 m). Village zones are flattened as always; placement rules unchanged.

### 7.3 Height function
`h(x,z) = fbm(x,z) * amplitude * islandMask(x,z) + rivers carving`
- fbm: value/simplex noise (implement simple 2D value noise + smoothing in `core/noise.gd`), 4 octaves, base freq 1/70, amplitude 9 m.
- islandMask: smoothstep from radius mapRadius (0) to mapRadius − 25 (1) plus radial falloff so edges dip below sea level.
- **0–3 watercourses (plus a 45% chance of a tributary each), every one different**, as wandering polylines (22 segments, smoothed random turning) with varying width along the course; kinds: **stream** (2.5–4.5 m wide, shallow, gentle banks), **river** (7–13 m wide, strong meanders, 7–13 m soft banks), **canyon** (3.5–6.5 m wide, 4–7.5 m deep, steep walls with sharp zigzags; the tributary of a canyon is a canyon too) and **dry gorge** (4–8 m wide ravine whose floor stays 1.2–2.2 m above the water). Carving: `h = min(h, lerp(h, floor, smoothstep(...)^profile))` with a per-course bank width and profile (profile < 1 = steep walls, > 1 = gentle). Per-course bounding boxes keep map generation fast (≈0.3–0.9 s).
- **0–4 lakes** (+ optionally one at the map center): ponds (5–9 m, shallow), big lakes (12–24 m, 1.8–3.4 m deep) and long lakes (10–18 m, stretched 1.8–3.2× and rotated); every outline is made irregular by three harmonic wobbles (amplitude 4–30%), with its own depth and bank softness.
- **Flatten village sites**: at each village center, blend height toward the average within radius `ZONE_RADIUS`, smoothing over an extra 8 m band. Slope in zone ≤ 10° guaranteed.

### 7.4 Village placement
- Villages are spread loosely and unevenly: a random global angle offset, angle_i = offset + 2π × i / N + rand(±0.9 × 2π/N), radius = mapRadius × rand(0.22, 0.8) (so neighbours can be near or far). Reject sites where terrain height < waterLevel + 1 (retry up to 240 times, moving toward the center after 150 failures; if everything fails use the ring slot of 24 that is farthest from all placed villages). Minimum distance between village centers = `2.6 × ZONE_RADIUS` (retry). Village index i is player i.
- The center of the map may contain: a hill with "Ruined Castle" decoration (optional prop group), or a lake (random).

### 7.5 Decor
- Trees (oak, pine): 60 + 14×N instances, not inside any zone (or rarely: 15% inside zone edges), trees are physics-active only when hit: they are static `MultiMeshInstance3D` instances, converted to a dynamic single body (tree trunk box + crown sphere) when a projectile is nearby (same dormant/awake rule as 5.2). Trees burn (flammability 0.8, crown dies and trunk stays).
- Rocks, bushes, flowers (pure visuals, instanced, no colliders except rocks with static collider).
- Sheep/cows/chickens/ducks: see section 10 animals.

### 7.6 Rendering terrain
Vertex colors by height/slope: grass green (#7ec850 to #5aa53c), sand near water (#e8d8a0), rock on steep slopes (#8a8a8a), dirt paths between village buildings (painted with vertex color in zone). Toon shaded (terrain shader reads vertex colors). Craters: on explosion, deform the heightfield: lower height within radius r by a bell shape depth up to 0.25 × r, update mesh vertices in that area and update the `HeightMapShape3D.map_data` (throttled: at most once per 0.5 s, batch). Scorch color on crater (darken vertex color).

---

### 7.7 Terrain damage and landslides (`world/terrain.gd`, `systems/landslide.gd`)
- **Dents**: a stone hitting the ground digs a small bell-shaped dent (radius 0.9–1.9 m, depth 0.18–0.48 m, browned soil); a boulder a big one with a raised rim of torn-up soil (radius 3.0–5.5 m, depth 1.0–2.4 m). A **rolling boulder cuts a furrow** along its path (radius 1.1 m, every 0.1 s, real grooves in the heightfield and brown soil). Explosions dig real craters when they go off near the ground (closeness = 1 − height above ground / (1.2 × blast radius), needs > 0.15): crater radius = 0.7 × blast radius, depth = 0.4 × blast radius × closeness, with a **raised rim of thrown-out soil** (up to 1.6 × radius out, height 0.2 × depth, soil browned) and a blackened floor (keg: ~8 m wide, ~4.5 m deep; red barrel: ~22 m wide, ~12 m deep; holes below sea level fill with water). Heights are clamped at −8 m; meshes and the collider are refreshed (`Terrain.dig`, `furrow`, `mark_dirty`).
- **Landslides** start only when something hits a **very steep** slope (≥ 36° measured at the impact and on a 3 m ring) hard enough: strength = impact energy / 9000 (×1.6 for the boulder) or, for explosions, `maxDamage / 1200 × closeness to the ground` (stone ≈ 0.25 = small, boulder ≈ 1–2, keg ≈ 1.4, red barrel ≈ 7 = huge); minimum 0.2; at most 3 at once; not within 6 m of a running slide. The blow first loosens the soil at the impact.
- **Simulation**: thermal erosion on the heightfield inside a window of radius `4 + 3.5 × strength` m (max 28): in steps of 0.05 s (3 sweeps each, `24 + 28 × strength` steps at most) soil moves from a cell to its lowest neighbour wherever the slope exceeds the angle of repose (tan 0.62 ≈ 32°), at most 14% of the excess / 0.25 m per move — a slide moves noticeably little material. The slide therefore **runs only as far as the mountain is steep and stops where it flattens out** (it also stops by itself when nothing moves any more).
- **Everything in the way is pushed and smashed**: where soil piles up, parts within 2.4 m get a heavy impact in the downhill direction (energy up to 26 000 × strength factor, through the normal break-force rule), settlers there take 40 + 10 × strength damage and are flung. The aftermath waits until the slide is over. Dust, sounds, camera shake and a banner "LANDSLIDE!" announce it; the damage is credited to the shooter (ammo "landslide", see 6.4b).

## 8. Village Generation (`scripts/world/village.gd`)

Each village occupies a circle of radius `ZONE_RADIUS` (22 m) at center `c`. Composition (seeded RNG):

**Mandatory** (placed in ring positions to leave open space in the middle for catapults, which are placed by the player anywhere valid):
- 1× Well (near center, offset 0–4 m)
- 1× Tavern
- 1× Church OR 1× Watchtower (50/50)
- 2–3× Farmhouse
- 1× Barn
- 1× Market stall group (2–3 stalls)
- 1× **Flagpole** (`buildings/flagpole.gd`): a 10 m pole on a stone plinth with a big flag (scale 2.4) in the **team colour**, so every village can be recognised from far away.

**Random extras** (pick 3–5 from list, with weights): Blacksmith, Windmill, Stable, Granary, Powder Store (max 1 per village, weight low 0.4), Water Tower (max 1), Outhouse (1–2, always placed at edge), Palisade segments and Stone Wall segments around parts of the perimeter (about 40% coverage, with 1 gap). Also: haystacks (3–6), barrels (8–15), crates (6–12), carts (1–2), fence sections (around farmhouses), pumpkins (6–10), lanterns (4–8), banners (2–4), tents (0–2), chickens (3–6), sheep (2–4), cow (0–1), settlers (10–16), a duck pond optional.

**Layout algorithm** (simple, robust):
1. Compute `slots`: 14 candidate positions, at distance 9–20 m from center, evenly spaced by angle with jitter ±10°.
2. For each building in the mandatory + extras list (largest footprint first), pick the best free slot (no overlap with already placed footprints: test circle radius per building footprint + 1.5 m gap). Rotate to face the village center ±15°.
3. Leave inner circle r < 7 m free of buildings (open space for catapults and settlers), except the well.
4. Props scattered near buildings (barrels next to tavern, hay next to barn, etc.) using each building's `propHints`.
5. Player color is shown on: banner flags on tower/church/well, the flagpole (big flag), the window frames of farmhouses and tavern (a darker shade of the team colour), catapult decals, and roof accent of the tavern (a colored cloth part).

Village HP (for tie-breaking) = sum of part HP still existing.

---

## 9. Building Catalog (`scripts/buildings/*.gd`)

Common interface (every building module exports):
```gdscript
const DEF := { "id": "farmhouse", "footprint_radius": 4.0, "prop_hints": [], "name_key": "building.farmhouse" }
static func build(ctx: BuildContext, rng: Rng, opts: Dictionary) -> BuildResult   # parts: Array[PartDef], extras: Array
```
Where `PartDef` (RefCounted): `material: String, size: Vector3, pos: Vector3` (relative to building base, rotation applied later), `rot: Vector3` (optional), `shape: 'box'|'cyl'|'roof'`, `color: Color` (optional), `anchor: bool`, `tag: String`. Use the helper `box()` etc. in `scripts/buildings/kit.gd` (create this file; helper functions for walls of bricks, plank floors, roof pyramids/gables built from tilted boxes, timber frames).

**Global rules for all buildings**
- Use small parts so buildings collapse convincingly: stone/brick blocks ~0.5–0.8 m; planks 0.25×1.5×0.12–0.25×3×0.12; roof tiles as plank/thatch panels ≤ 1×0.1×1.2.
- Part count per building: 30–110 (see below). Total per village ≤ 700 parts. (Merge visual dormant geometry, see 5.2.)
- Foundation parts have `anchor:true`.
- Doors/windows: parts (wood door box, glass window box that shatters with `tinkle`).
- Colors: earthy but saturated (toon palette section 16.2).

| id | Nice name (EN / DE) | Footprint r | Description | Parts | Special behavior |
|---|---|---|---|---|---|
| `farmhouse` | Cosy Cottage / Gemütliche Hütte | 4 | Stone foundation 5×5, brick/plank walls 3 m high, thatch or tile gable roof, chimney (brick, smoke particles), 2 windows, door. | 60–80 | thatch roof burns very fast; chimney topples nicely. |
| `barn` | Big Hay Barn / Große Heuscheune | 6 | 8×6 plank walls 5 m, large gable plank roof, big double door, interior 4–6 hay bales. | 80–110 | Hay inside ignites everything; bursts into hay when hit. |
| `tavern` | The Drunken Goose / Zur Betrunkenen Gans | 5 | Two-story plank + stone building, sign (cloth+wood, swings), balcony, 3 barrels (beer) outside, 4 mugs (tiny props) | 90–110 | Beer barrels: flammable liquids (burning puddle when broken, spawns a 4 s flame). Settlers gather here (many). Fun: when destroyed, spawns 6 "beer geysers" (blue-gold particles). |
| `church` | Church of Holy Confusion / Kirche der Heiligen Verwirrung | 5 | Stone nave 6×10×5, steeple tower 3×3×10 with metal bell inside (dynamic, `metal` sphere-cyl), red tile roof, stained glass front window. | 90–110 | Bell clangs on any hit anywhere within 30 m (sound "BONG"), falls down when tower collapses and crushes stuff. |
| `watchtower` | Lookout Tower / Wachturm | 3 | Stone tower 3×3×9, wooden top platform with crenellations and cloth banner (player color), 1 archer settler on top. | 50–70 | Tall = falls in long arc, toppling as chain. |
| `well` | Wishing Well / Wunschbrunnen | 1.6 | Stone ring, wooden roof frame, bucket, rope. Water inside. | 20–30 | If destroyed: gushes water fountain particles 10 s and puts out fire within 6 m; settlers use it for bucket brigade while intact. |
| `stall` | Market Stall / Marktstand | 2 | Wood frame with striped cloth awning (player color or random palette), table with crates, fruit props (small spheres, dynamic). | 15–25 | Cloth burns; fruit rolls; spawn sound "splat" when fruit is hit. |
| `stable` | Stable / Stall | 4 | Plank open shed 6×3.5×3, thatch roof, 2 horses (Animal type horse, ragdoll-lite) | 40–60 | Horses run away when burning. |
| `granary` | Granary / Kornspeicher | 3 | Raised wooden building on 4 stone stilts (stilts anchor), plank walls, thatch roof, sacks | 40–55 | Collapses when stilts break. Sacks explode in flour cloud (white particles + small explosion when there is fire nearby: "flour dust explosion", radius 4, damage 250). |
| `powderstore` | Definitely Not Explosive / Ganz Sicher Nicht Explosiv | 3 | Stone shed 4×4×3 with metal-studded door, sign with skull, 6 powder kegs inside (barrel_wood, kind powder). | 40–50 | Any fire or big hit on it → all kegs explode in chain (each radius 5, damage 500). Big BOOM with mushroom cloud particle ("skull smoke"). |
| `watertower` | Aqua Tower / Wasserturm | 3 | 4 wooden stilts 5 m tall + large round wooden tank on top (barrel, radius 2, height 2.5) full of water. | 25–35 | On tank break: huge water release, spawns 30 water particles/physics droplets (visual + impulse volume push radius 8) and extinguishes fire radius 10, pushes settlers around. |
| `windmill` | Windy Windmill / Windige Windmühle | 4 | Stone round tower (8-sided) 8 m, wooden cap, 4 sails (each 5 m, dynamic body attached via a hinge joint (`joint_make_hinge`) to a hub; rotates slowly with motor while intact). | 60–80 | When hit, sails fall off and roll; burning sails spin faster (glow). |
| `blacksmith` | Ye Olde Smithy / Alte Schmiede | 4 | Stone base, open front with anvil (metal), forge (stone block with glowing coal, is a permanent low fire source that does not spread), bellows, weapon rack with swords (tiny). | 45–60 | Anvil dropping onto things does big impact (heavy). Forge coals scatter as fire when destroyed. |
| `outhouse` | The Royal Loo / Das Königliche Klo | 1.2 | Wooden 1.2×1.2×2.2, crescent moon on door, door, roof | 12–16 | Special: when destroyed, launches a settler (the "occupant" 60% of the time) out with a giant hurl and voice line "OCCUPIED!!!". |
| `palisade` | Sharp Fence / Spitzer Zaun | seg 3 | Row of sharpened logs (wood cylinders 0.3×3), lashed in segments of 6 logs | 6 per seg | Logs fall like dominoes. |
| `stonewall` | Sturdy Wall / Feste Mauer | seg 4 | Stone block wall 4×2×0.8 with top crenellations | 20–30 per seg | Blocks are heavy; can protect catapults. |

### 9.1 Structure HP
Total HP is derived from parts; there is no separate building HP bar. When the majority of parts (> 70%) of a building are broken or collapsed, mark it `destroyed` for stats and play a "CRASH" comic text.

### 9.2 Fire
Buildings share the fire system of section 11.

---

## 10. Props and Animals (`scripts/props/*.gd`)

Each prop builder returns 1+ physics bodies + meshes; props are dynamic but start asleep (`BODY_STATE_SLEEPING`) and wake on nearby impulse (the engine wakes bodies automatically on contact; also wake within explosion radii).

| id | Name | Description | Material | Mass | Special |
|---|---|---|---|---|---|
| `barrel_beer` | Beer Barrel | cylinder r0.45 h0.9 | barrel_wood | 60 | on break: spawns ale splash; flammable puddle |
| `barrel_water` | Water Barrel | as above, blue-ish bands | barrel_wood | 120 | on break: water splash, extinguish r4 |
| `barrel_powder` | Powder Keg | small black barrel with skull | barrel_wood | 40 | explosion r5 dmg 500 when broken or burning > 2 s |
| `crate` | Wooden Crate | 0.8³ box | wood | 30 | shatters |
| `haybale` | Hay Bale | 1×0.7×0.7 | hay | 25 | burns fast, bounce soft |
| `pumpkin` | Pumpkin | sphere r0.3 | flesh-like (custom hp 12, restitution 0.5) | 6 | splat, orange particles |
| `cart` | Farm Cart | box bed 2×0.2×1, 2 cylinder wheels (dynamic each, hinge joints (`joint_make_hinge`)), 2 shaft poles | wood | 80 | rolls downhill |
| `fence` | Picket Fence | 2 m section (3 posts + rails) | plank | 25 | falls, breaks |
| `lantern` | Street Lantern | pole 2.4 m + glowing box | wood + glass | 15 | glass breaks → small fire spawn with 30% chance if wood nearby |
| `banner` | Player Banner | pole with cloth colored | wood+cloth | 10 | burns |
| `tent` | Circus Tent | striped cloth cone on pole | cloth | 40 | burns, collapses |
| `anvil` | Anvil | metal block | metal | 150 | only from blacksmith |
| `mug` | Ale Mug | tiny cylinder | glass | 0.5 | tinkle |
| `bucket` | Bucket | small cylinder | wood | 3 | carried by settlers |
| `rubberduck` | Giant Rubber Duck | yellow duck 1 m, floats on water (buoyancy) | flesh-like (restitution 0.8) | 8 | squeak on impacts. Easter egg: 1 per map, at a random lake/pond/river spot. |

### 10.1 Animals (`scripts/entities/animal.gd`)
Composed of 1–3 bodies with simple joints (pin/cone-twist joint), pure procedural mesh.
| id | Name | Behavior | Death/hit |
|---|---|---|---|
| chicken | Chicken | wanders, pecks | "BAWK!" sound, feathers particle burst (10), ragdoll flies far (light) |
| sheep | Sheep | wanders, bleats | "BAAA!", wool particles, bouncy |
| cow | Cow | wanders slow | "MOOO!", heavy |
| horse | Horse | stable only; flees when fire | "NEIGH!" |
| duck | Duck | pond only, floats | "QUACK!" |
Animals: HP 15/20/60/60/8. When HP ≤ 0 or hit by an impulse > 200, switch from wander-AI to ragdoll (all bodies dynamic).
Fire panic: burning animals run randomly with flame particles for 4 s.
**Cows**: every village starts with **exactly two cows**, placed on open ground (clear of buildings, not in water, slope ≤ 14°; `GameWorld._free_animal_spot`). They use the shared model `render/cow_mesh.gd` (`CowMesh.body/head`): rounded barrel, shoulders and rump (ellipsoids), black spots, tapered legs with dark hooves, udder with teats, tail with a dark tuft; the head is a separate mesh (ragdoll head) with skull, pink muzzle, nostrils, eyes, ears (one black), horns and a tuft. The flying Moo-nition uses the same model.

---

## 11. Systems

### 11.1 Fire system (`scripts/systems/fire.gd`)
- Every flammable part (material flammability > 0) has `burning` in [0,1] and `onFire` bool.
- **Ignition**: (a) fire-pot impact; (b) explosion: any flammable part in radius gets +0.5 burning (times falloff); (c) lightning; (d) dragon breath; (e) neighbor fire (below); (f) forge coals scattering; (g) burning projectiles.
- **Tick** every `FIRE_TICK` s (budgeted to ≤ 200 parts checked per tick, round-robin):
  - For each `onFire` part `P`: damage P by `material.burnHP × 2.6 × FIRE_TICK` (hard-hitting fire) — but **a part burns at most 10 s** (`BURN_TIME`), then it is charred and can never catch fire again; ground fires last 3 s (half as long as before) and catapults burn for at most 10 s (3.6 hp/s). For each flammable part `Q` within `FIRE_SPREAD_RADIUS` (spatial hash grid, cell size 3 m, do not do O(n²)): `Q.burning += flammability(Q) × 0.34 × FIRE_TICK × windBoost × (1 − wet)` where `windBoost = 1 + windSpeed × 0.05` if Q is in downwind half-plane else 1. Upward spread ×1.5.
  - When `burning >= 1` → `onFire = true`, spawn flame emitter on it.
  - `burning` decays by 0.15/s if not on fire (partial heating cools).
  - Part reaches `hp <= 0` → breaks (charred shard: dark color) → ash particles; support check as in 5.3.
- **Extinguish**: water sources (water barrels, water tower, well rupture, rain) set `wet = 1` on parts within radius, set `onFire=false`, `burning=0` and spawn steam. Rain: while raining, every tick each onFire part has a 25% chance to be extinguished; and no new spread.
- **Fire visuals**: pooled emitter per burning part (max 60 simultaneous emitters, prioritize nearest to camera; beyond limit only shared glow billboards). Flames = additive billboard particles orange→red→black smoke (`GPUParticles3D` presets). Plus `OmniLight3D`s (max per quality tier) for biggest fires, others emissive only.
- **Settlers/animals in fire** catch fire: run in panic, 5 dmg/s, jump into water if near (well/pond/river).
- **Burnable ground**: dry grass under burning part has a 30% chance to spawn a "ground fire" that spreads within 2 m and lasts 6 s (visual + ignites flammable parts touching).
- Fire creeps from part to part (spread 0.5) rather than jumping: ground fires ignite touching parts at 0.45/s and spawn offspring with 5%/s; flames are big (emitter scale ×1.4, min 1.0; ground fire ×1.5) and the biggest fires cast light (range 13, energy 2.2). **Catapults suffer twice as much**: fire within 4 m heats the wood (2.5 hp/s even before it catches) and ignites it after 0.9 s; a burning catapult loses 7.2 hp/s for at most 10 s; explosions / fire barrels / any `ignite_in_radius` with strength ≥ 0.5 ignite catapults within 90% of the radius.
- Explosive triggers: powder kegs on fire ≥ 2 s explode (prop keg: radius 9, damage 1000).

- Debris speed is clamped to 60 m/s so a 4-tonne boulder cannot turn splinters into bullets.

### 11.2 Explosion system (`scripts/systems/explosion.gd`)
`explode(pos, radius, max_damage, opts: {fire: bool, source: Dictionary, sound: String})`:
1. Query bodies in radius via `PhysicsDirectSpaceState3D.intersect_shape` (sphere shape) or a manual spatial hash.
2. For each body: falloff `f = 1 − dist/radius` (clamped), impulse magnitude = `max_damage × f × 0.6` direction from pos (add +0.4 up), apply to dynamic bodies (`body_apply_impulse`); wake sleeping ones.
3. Call `damage_parts_in_radius`, `damage_settlers`, `damage_catapults` with `max_damage × f`.
4. Terrain crater (radius × 0.35, depth as 7.3).
5. FX: fireball (expanding sphere mesh, 0.4 s), smoke column, sparks, shockwave ring on ground, screen shake (amplitude scaled), `OmniLight3D` flash, sound. (No slow motion for explosions, see 13.2.)
6. If `fire:true` ignite flammables in radius × 0.8.
7. Chain: powder kegs in radius receive an explosion trigger with delay 0.1–0.35 s.
8. **Pressure wave** (blasts with radius ≥ 6 unless `shock:false`): an expanding front (42 m/s, reach `radius × 2.4`, strength `max_damage × 0.55` N·s, visible as an expanding ring on the ground) that hits things when the front passes them, nearest first: loose bodies and free parts get an impulse `strength × f²` (capped), light building parts (mass < 40 kg and break force < 400: thatch, cloth, hay, glass, leaves, light planks) are shoved and lightly damaged, settlers and animals are knocked over (little damage), **catapults are never damaged or moved by it**. The blast itself damages catapults with a steep falloff: `max_damage × f² × 0.14` (f over `radius + 1.5`), so one keg cannot wipe out a whole village.

### 11.3 Water (`scripts/systems/water_sys.gd`)
- Global sea/lake/river water plane(s) with animated toon-ish shader/vertex wave (hand-written water shader: animated vertex Y via sine waves + toon-ish banded color/foam at shoreline via depth or height difference; keep cheap). Water is decorative + logic: bodies below `waterLevel` get buoyancy (`body_apply_central_force` up = density_factor × submerged_fraction) and drag; catapults falling into deep water (depth > 1 m) are destroyed after 2 s ("Glug glug").
- Splash particles when bodies cross the water surface with speed > 3.
- Droplet effects for water releases (barrels, tower, well): 40 pooled droplets with simple particle physics (not the physics engine) plus an impulse volume (`overlap_sphere` + impulses) on nearby light bodies. A temporary "puddle" decal (blue disc, fades over 12 s) that sets `wet=1` on parts within radius.

### 11.4 Weather (`scripts/systems/weather.gd`)
State machine, evaluated at each turn start (if the option is on): 
| weather | chance/turn | duration (turns) | effect |
|---|---|---|---|
| Clear | 55% | — | none |
| Cloudy | 15% | 1–3 | darker sky, no gameplay effect |
| Rain | 12% | 2–3 | fire spread stops, 25% extinguish chance/tick, wet ground; rain particles (one `GPUParticles3D` following the camera, ≤ 800 particles) & sound; reduces visibility fog |
| Thunderstorm | 8% | 1–2 | as rain + lightning: at each TURN_START (and 1 additional random time during AFTERMATH) a bolt strikes a random flammable-rich location (weighted by tallest structure: church, tower, windmill weight 3) → ignites (+0.8 burning) parts within 3 m, small explosion r3 dmg 120, lightning flash + thunder + comic text "ZAP!"; announcer line. Strike locations choose among all *living* villages uniformly, biased 60% toward the player who was ahead (most catapults). |
| Storm (wind only) | 10% | 1–2 | wind ×1.8, trees sway, flags flap, tornado-like leaf particles, `WIND_MAX×1.8` |
Weather changes announced by banner + funny line (12.7).

### 11.5 Random events (`scripts/systems/random_events.gd`)
At each TURN_END if enabled: chance 12% for one event (cooldown 3 turns). Pick by weights:
| id | weight | title EN / DE | effect |
|---|---|---|---|
| dragon | 25 | "A wild Dragon appears!" / "Ein wilder Drache erscheint!" | A big procedural dragon (body spheres/tapered cylinders, wings flap, green) flies over the map on a curve at height 25 m over 8 s. Every 0.6 s it breathes a flame cone at the ground at a random spot near a random living village (3 breaths); flame ignites parts within radius 4, no direct explosive damage. Settlers scream "DRAAAGON!". Dragon can be knocked down? No (out of reach). |
| cheese_meteor | 10 | "Meteor made of Cheese!" | A glowing yellow meteor drops at a random spot in a random village; explosion r6 dmg 500 + leaves cheese chunks (edible... nothing) + stink cloud. |
| cow_rain | 12 | "It's raining cows!" / "Es regnet Kühe!" | 6–10 cows spawn 40 m above random village positions and fall (with "MOO" sounds), bounce; each impact acts as a Stone with mass 250 (damage) and cows do not explode. Cows stay as props. |
| earthquake | 10 | "Rumble rumble!" / "Rummel rummel!" | 3 s of camera shake; every structure receives random impulse jitters on top parts causing tall structures (tower, church, windmill, water tower) to collapse with 35% chance each, props hop. |
| goose_army | 8 | "The Geese Have Come!" / "Die Gänse sind gekommen!" | 20 geese (procedural white geese) run across the map, knocking settlers and light props (they are dynamic bodies with mass 5), honk; they disappear after 10 s off the map edge. |
| tax_collector | 8 | "The Tax Collector arrives!" | A settler in gold clothes walks to a random village center; on arrival "Tax!!" and 3 random settlers of that village drop coins (visual). If he is hit, comic reaction "AUDIT!". Pure humor, no gameplay effect. |
| fireworks_accident | 8 | "Fireworks Factory Incident!" | Random village: a burst of 15 rockets fly in random directions (small explosions r2 dmg 80, each with sparkle trails). |
| bubble | 6 | "Wizard's Bubble Spell!" | Giant bubble (translucent sphere r 4) appears over a random settler group, lifts them slowly 8 m, then pops; they fall as ragdolls. Purely comic. |
| flood | 5 | "Sudden Flood!" | Water level rises 1.2 m over 4 s and falls again over 8 s. Everything low-lying gets buoyancy, fires extinguished on submerged parts, catapults in water > 1 m for > 3 s are destroyed. Pick only if map has any village with height < waterLevel + 2.5 (else skip). |

Each event has a banner + announcer voice line and a music sting (sfx).

---

### 11.6 Black powder (`systems/powder.gd`)
- **Powder heaps** (`Powder.Dust`) lie on the ground (dark flat discs in one `MultiMesh`, max 520, oldest dropped first) or are smeared on building parts (the part is tinted dark). They stay **until they are set alight — also over any number of later turns**.
- **Ignition**: anything that burns lights powder within reach: `Fire.ignite_in_radius` (explosions, fire barrels, lightning, dragon breath…: radius × 0.9), a part starting to burn (1.8 m) and ground fires (1.6 m). Each lit heap flashes after a tiny delay (0.04–0.16 s + 0.03 s per metre), and every flash lights the heaps within 2.8 m: the flame **runs along the whole trail in a blink**. **A keg that rolls into a fire ignites its powder at once**: whenever powder appears (`Powder._add`) within 2.2 m horizontally of a burning part or ground fire (burning part at most 3 m above / 2 m below the powder, `Fire.fire_within`), it is lit immediately (delay 0.03–0.12 s), so a fresh trail next to even a small fire flashes away right away.
- **Flash flame**: a violent, very short jet (upward flame + sparks, sound): area damage 150 to parts within 2.3 m (about **5× the damage of the normal fire** on the same part), 34 to settlers within 2.5 m (and they catch fire within 2 m), catapults within 2.4 m catch fire, flammable parts within 2.4 m are ignited at full strength; then the heap is gone.
- **Scorch marks**: wherever something burned — powder flashes (radius 1.7 m, 0.95) or normal ground fires (radius 2.6 m, 0.85) — the terrain is painted black and **stays black** for the rest of the match.

## 12. Content Lists (all names, texts, jokes; pre-defined so the implementer only copies them)

### 12.1 Default human player names (pool, pick unused in order shuffled by seed)
Sir Reginald von Bumblebutt, Lady Guinevere Flatulence, Baron Von Kaboom, Duke Dudley Doomsday, Lord Fluffington, Countess Cheesewheel, Prince Pumpernickel, Dame Doreen Dungpile, Sir Loin of Beef, Lord Percival Pickle, Earl of Hamburg, Baroness Butterfingers, Sir Cumference, Squire Squishy, Queen Mildred the Moist, King Kevin the Kinda Okay.

### 12.2 CPU names (by difficulty)
- Peasant: Gary the Peasant, Old Man Hobbs, Bertha the Baffled, Dim Dave, Wobbly Wilf, Turnip Tom, Clumsy Clara, Peasant Pete.
- Squire: Squire Steve, Squire Sheila, Junior Knight Jim, Apprentice Alfred, Shieldbearer Sally, Trainee Trevor, Bucket-Head Bob, Squire Sue.
- Knight: Sir Lancelot-ish, Sir Bash-a-Lot, Dame Dragonbane, Sir Reads-a-Lot, Sir Robin the Not-So-Brave, Sir Galahad Gains, Dame Gwendolyn Grimm, Sir Kills-a-Lot.
- King: King Kaboom I, King Cruelbeard, King Mad-Ness the Magnificent, Emperor Explosion, Kaiser Chaos, King Arthur's Evil Twin, Queen Catastrophe, His Royal Highness Rick.

### 12.3 Settler name pool (used in speech/killfeed)
Bob, Hilda, Wat, Agnes, Ethelred, Mabel, Godric, Petronella, Ned, Wulfric, Beatrix, Cuthbert, Gertrude, Osric, Winifred, Alaric, Sybil, Egbert, Millicent, Thaddeus.

### 12.4 Comic text (floating `Label3D` billboards; random from list per event; each entry is EN/DE; keep both in lang files under `comic.*`)
- Generic impact: BOOM! / WUMMS!, KRACH! / KRACH!, BAM! / BAM!, WHAM! / WUMM!, KRAWUMM! / KRAWUMM!, SPLAT! / PATSCH!, BONK! / BONK!, THUD! / RUMS!
- Wood breaking: CRUNCH! / KNACK!, SPLINTER! / SPLITTER!, TIMBER! / UMFALLEN!
- Stone: CRASH! / KRACHBUMM!, RUMBLE! / RUMMS!
- Explosion: KABOOM! / KAWUMM!, BLAM! / PENG!, MEGA-BOOM! / MEGA-KNALL!, KA-BLOOEY! / KA-BUMM!
- Fire: FWOOSH! / FFFUMM!, SIZZLE! / ZISCH!, HOT! / HEISS!
- Water: SPLASH! / PLATSCH!, GLUG GLUG / BLUBB BLUBB, SPLOOSH! / PLANSCH!
- Cow: MOO! / MUH!, MOOOO!? / MUUUH!?
- Settler hit: BOING! / BOING!, OOF! / UFF!, YEET! / JUCHHU!, WHEEE! / WIIIE!
- Catapult destroyed: TOTAL LOSS! / TOTALSCHADEN!, OUCH, WOOD! / AUA, HOLZ!, R.I.P. / R.I.P.
- Bell: BONG! / BONG!
- Outhouse: OCCUPIED! / BESETZT!
- Lightning: ZAP! / ZACK!
Rule: spawn comic text only on significant events (explosion ≥ radius 4, building > 30% destroyed, kill of ≥ 1 settler at most once per second, max 3 alive on screen). Font: bold sans (`SystemFont` Impact-like stack, see 16.1) rendered as `Label3D` (billboard, `no_depth_test`), white text with thick black outline, rotate randomly ±12°, scale bounce in, float up and fade out in 1.2 s, colors random from [#ffd400, #ff5b2e, #ffffff, #7cf0ff].

### 12.5 Elimination banners (random, EN/DE)
1. "{name} has been REDUCED TO KINDLING!" / "{name} wurde zu ANZÜNDHOLZ verarbeitet!"
2. "{name}'s catapults have left the chat." / "{name}s Katapulte haben den Chat verlassen."
3. "That was {name}'s last catapult. Also their pride." / "Das war {name}s letztes Katapult. Und der Stolz gleich mit."
4. "{name} is out! Please queue for the peasant lottery." / "{name} ist raus! Bitte in der Bauernlotterie anstellen."
5. "RIP {name}. It was a good village. Mostly." / "R.I.P. {name}. Es war ein gutes Dorf. Größtenteils."
6. "{name} has been declared 'extra crispy'." / "{name} wurde für 'extra knusprig' erklärt."
7. "The pigeons will mourn {name}." / "Die Tauben trauern um {name}."
8. "{name} ragequits into the moat." / "{name} verlässt wütend das Spiel und springt in den Burggraben."

### 12.6 Loading messages (random rotating)
- Sharpening pitchforks… / Mistgabeln werden geschärft…
- Herding chickens… / Hühner werden zusammengetrieben…
- Teaching cows to fly… / Kühen wird das Fliegen beigebracht…
- Inflating peasants… / Bauern werden aufgeblasen…
- Bribing the dragon… / Der Drache wird bestochen…
- Stacking questionable buildings… / Fragwürdige Gebäude werden gestapelt…
- Removing all safety regulations… / Sämtliche Sicherheitsvorschriften werden entfernt…
- Adding extra explosions… / Zusätzliche Explosionen werden hinzugefügt…
- Counting the cheese… / Der Käse wird gezählt…
- Lighting the very first torch… / Die erste Fackel wird angezündet…

### 12.7 Announcer lines (banners at events; EN / DE)
Turn start (random): "{name}, your move!" / "{name}, du bist dran!"; "Fire at will, {name}!" / "Feuer frei, {name}!"; "{name} cracks their knuckles." / "{name} knackt mit den Fingern."; "Somebody's about to have a bad day, {name}." / "Jemand hat gleich einen schlechten Tag, {name}."; "Choose wisely, {name}. Or don't." / "Wähle weise, {name}. Oder auch nicht."
Miss (shot lands in water/nowhere): "Missed by a mile." / "Um Meilen verfehlt."; "The fish are offended." / "Die Fische sind beleidigt."; "Did you mean to do that?" / "War das Absicht?"; "Nice shot, if the target was a tree." / "Toller Schuss – wenn das Ziel ein Baum war."
Big hit (≥ 3 settlers or building destroyed): "DIRECT HIT!" / "VOLLTREFFER!"; "Absolutely devastating." / "Absolut verheerend."; "That's gonna leave a mark." / "Das gibt einen Fleck."; "The insurance company is crying." / "Die Versicherung weint."
Friendly fire / self-hit: "Did you just shoot yourself? Bold." / "Hast du dich gerade selbst beschossen? Mutig."; "Own goal!" / "Eigentor!"
Weather: Rain: "Rain! Bad news for arsonists." / "Regen! Schlechte Nachrichten für Brandstifter."; Thunderstorm: "Zeus is angry today." / "Zeus ist heute schlecht gelaunt."; Storm: "Hold on to your hats!" / "Haltet die Hüte fest!"; Clear: "The sun comes out. The chaos continues." / "Die Sonne kommt raus. Das Chaos geht weiter."
Fire: "Something's burning… and it's not the toast." / "Da brennt was… und es ist nicht der Toast."; "The fire brigade is on the way (it's a guy with a bucket)." / "Die Feuerwehr ist unterwegs (ein Typ mit Eimer)."
Powder store: "That was NOT the pantry!" / "Das war NICHT die Speisekammer!"
Cheese: "The Holy Cheese descends!" / "Der Heilige Käse kommt herab!"

### 12.8 Settler speech bubbles (random by situation; at most 1 bubble per settler, **at most 4 bubbles on screen (2 for idle chatter) and a minimum pause per category** — idle 9 s, panic 2.5 s, hit 1.5 s, fire 4 s, landed 3 s, bump 2.5 s, bucket 8 s —; idle chatter is rare (chance 0.012 per think step, 20 s cooldown per settler); the line is drawn from the RNG before the throttling so online machines stay in step; lasts 2.2 s; keep in lang files under `speech.<situation>` arrays). The lists below are the minimum; the game has more (idle 30, panic 18, hit 16 lines, similar growth elsewhere, identical counts in EN and DE). **New category `bump`** (12 lines): what neighbours say when a catapult is driven into a building ("That's totally over the top!" / "Das ist ja voll übertrieben!", "Well, I guess I'll believe that too!" / "Ja, dann glaub ich das halt auch noch!", "Did he just PARK in my house?!" …).

**idle / chatting (EN / DE)**
- "Lovely weather for a siege." / "Schönes Wetter für eine Belagerung."
- "I should've stayed in the other village." / "Ich hätte im anderen Dorf bleiben sollen."
- "Has anyone seen my goat?" / "Hat jemand meine Ziege gesehen?"
- "Nice hat!" / "Schicker Hut!"
- "Back in my day, we had walls." / "Zu meiner Zeit hatten wir Mauern."
- "I love this village!" / "Ich liebe dieses Dorf!"
- "Is that a catapult?" / "Ist das ein Katapult?"
- "Just another Tuesday." / "Ein ganz normaler Dienstag."
- "Ale o'clock!" / "Bierzeit!"
- "Somebody feed the chickens." / "Jemand muss die Hühner füttern."

**panic (incoming projectile within 15 m or explosion nearby)**
- "RUN!" / "LAUFT!"
- "INCOMING!" / "ACHTUNG, EINSCHLAG!"
- "NOT MY HOUSE!" / "NICHT MEIN HAUS!"
- "MOMMYYYY!" / "MAMAAAA!"
- "WHY MEEEE?" / "WARUM ICHHH?"
- "I left the stove on!" / "Ich hab den Herd angelassen!"
- "AAAAAH!" / "AAAAAH!"
- "Every peasant for themselves!" / "Jeder Bauer für sich!"

**hit / ragdoll launch**
- "WHEEEEE!" / "WIIIIIE!"
- "I REGRET NOTHING!" / "ICH BEREUE NICHTS!"
- "TELL MY WIFE…" / "SAGT MEINER FRAU…"
- "OH COME ON!" / "ACH KOMM SCHON!"
- "YEEEEET!" / "JUUUCHHUUU!"
- "I believe I can fly!" / "Ich glaube, ich kann fliegen!"
- "Not the face!" / "Nicht das Gesicht!"
- "It's a bird… it's a plane… it's Bob!" / "Ist es ein Vogel… ein Flugzeug… es ist Bob!"

**on fire**
- "I'M ON FIRE!" / "ICH BRENNE!"
- "HOT HOT HOT!" / "HEISS HEISS HEISS!"
- "STOP DROP AND ROLL… or was it run?" / "Stop, Drop and Roll… oder war's Rennen?"
- "WATER! ANYONE?!" / "WASSER! IRGENDJEMAND?!"

**bucket brigade**
- "Pass the bucket!" / "Gebt den Eimer weiter!"
- "It's leaking!" / "Der ist undicht!"
- "More water!" / "Mehr Wasser!"
- "I'm too old for this." / "Ich bin zu alt dafür."

**after landing (dead/limp)**
- "Ow." / "Aua."
- "…I'm fine." / "…Mir geht's gut."
- "Definitely broken." / "Definitiv gebrochen."
- "I saw the light." / "Ich habe das Licht gesehen."

**bees**
- "BEEEEES!" / "BIIIENEN!"
- "NOT THE BEES!" / "NICHT DIE BIENEN!"
- "They're in my pants!" / "Die sind in meiner Hose!"

**cheese**
- "WHAT IS THAT SMELL?!" / "WAS IST DAS FÜR EIN GERUCH?!"
- "So… cheesy…" / "So… käsig…"

**dragon**
- "DRAAAGON!" / "DRAAACHE!"
- "I didn't sign up for this!" / "Dafür hab ich nicht unterschrieben!"

**outhouse**
- "OCCUPIED!!!" / "BESETZT!!!"

**cow**
- "Is that… a cow?" / "Ist das… eine Kuh?"
- "The cow! THE COW!" / "Die Kuh! DIE KUH!"

**celebration (own village had enemy destroyed / winner)**
- "We won! I think!" / "Wir haben gewonnen! Glaub ich!"
- "Free ale for everyone!" / "Freibier für alle!"

### 12.9 Settler outfits/colors
Randomized per settler: tunic color from palette [#c0392b, #2980b9, #27ae60, #f39c12, #8e44ad, #d35400, #16a085, #7f8c8d], hat types: none, straw hat, cap, pointy wizard hat, bucket (very rare 3%: bucket on head), crown (0.5%). Villagers of a village have a shoulder patch or hat feather in the player's color.

---

## 13. Statistics and Titles (`scripts/systems/scoring.gd`)

Tracked per player: `shots`, `hits` (shot that damaged any enemy building/settler/catapult), `damageDealt` (sum HP damage to enemy parts, converted: 1 hp = 1 gold coin, display as "Gulden"/"Gold"), `settlersLaunched` (ragdolls launched by your shots), `settlersKilled`, `catapultsDestroyed` (enemy), `buildingsDestroyed`, `firesStarted`, `firesExtinguished`, `cowsFired`, `cheeseUsed`, `selfDamage`, `waterMisses` (shots that landed in water), `longestShot` (m), `turnsSurvived`, `catapultsLeft`.

### 13.1 Titles (awarded at GAME_OVER; each title goes to the top player for that metric if metric ≥ threshold; a player can get max 2; awarded in this order; skip if no candidate)
| id | EN title | DE title | Metric | Threshold |
|---|---|---|---|---|
| cow_launcher | Cow Catapulter | Kuh-Katapultierer | cowsFired | ≥ 1 |
| pyro | Certified Pyromaniac | Zertifizierter Pyromane | firesStarted | ≥ 10 |
| pacifist | Pacifist (Accidentally) | Pazifist (aus Versehen) | fewest hits among players with shots ≥ 3 | – |
| sniper | Eagle Eye | Adlerauge | highest hits/shots ratio, shots ≥ 4 | ≥ 60% |
| fisherman | Master Fisherman | Meisterfischer | waterMisses | ≥ 3 |
| destroyer | Wrecking Ball | Abrissbirne | buildingsDestroyed | ≥ 4 |
| settler_bowler | Peasant Bowler | Bauernkegler | settlersLaunched | ≥ 15 |
| self_own | Own-Goal Champion | Eigentor-Meister | selfDamage | ≥ 200 |
| firefighter | Bucket Hero | Eimer-Held | firesExtinguished | ≥ 5 |
| cheesemaster | Meteor Baron | Meteoritenbaron | meteorUsed (stat field `cheese_used`) | ≥ 1 |
| longshot | Long-Range Menace | Weitschuss-Bedrohung | longestShot | ≥ 90 m |
| survivor | Cockroach | Kakerlake | turnsSurvived (winner excluded) | top |
| loser | Participation Trophy | Teilnahmeurkunde | first eliminated | – |

Winner crown title (random): "Supreme Overlord of Rubble" / "Oberster Herrscher über Trümmer"; "Grand Pooh-Bah of Ashes" / "Großmeister der Asche"; "Emperor of Ruins" / "Kaiser der Ruinen"; "Chief Chaos Officer" / "Oberster Chaos-Beauftragter".

### 13.2 Impact focus and bullet time (replaces the former replay — replays were removed)
- **FPS counter**: a tiny label (10 px, white with dark outline) at the very bottom left of every screen, updated twice a second.
- **Wind** is verified by the scenario `--autotest=wind`: in the real physics a 14 m/s wind shifts a stone's landing point by ≈19–23 m along the wind and `Ballistics.predict` matches the simulated landing within ~1 m.
- No replay exists. After a shot the **impact camera** keeps the village where the shot lands in view (yaw behind the shot direction, ~34 m, pitch 44°), it never turns away, also for scatter/fire bombs.
- **Bullet time is played ONLY for a direct hit by a projectile on a catapult** (`Engine.time_scale` 0.22 for 1.5 s, audio `playback_speed_scale` follows, any click/key cancels it). Nothing else slows the game down: no explosions, no big scores, no catapult kills by splash, no boulder (the meteor has its own cinematic). The former slow motion for hits with a score ≥ 600 and for explosions was removed because it disturbed more than it helped.
- Banners/turn panel are larger and no longer repeat messages.
- Catapults must stand on the ground: `Catapult.ensure_grounded()` re-seats a buried catapult (terrain + 0.35, upright); if buried > 3 m deep it is destroyed ("buried"). A catapult cannot be selected/fire unless grounded.
- Terrain changes (`Terrain.flush`) wake sleeping debris in the changed area (`PhysWorld.wake_in_box`) so it sinks into craters instead of floating.
- Boulder mass is 13.8 t. A powder keg bursts at the end of its roll: **48 powder blobs (extra kegs: 24) fly up in an arc and come down within only ≈2.8 m (extra kegs ≈1.8 m) of the keg** — 30% of the former radius, three times the former amount; the first 24 blobs are drawn flying (`Powder.spray`), plus a dust cloud, keg splinters and the splat sound. Powder trails are 60% denser.
- **Village layout**: the seed decides only the terrain; the village layout uses a separate RNG (`seed|layout|nonce`), the nonce is random per fresh match and kept on "same map"/restart.
- **Versioning**: `VERSION` file, shown in the menu credits via `Cfg.game_version()`; releases via `tools/release.sh <ver> "<note>"` (git commit + tag).

### 13.3 Points (cosmetic score, `Scoring.award`, `PlayerData.points`)
Every action pays points that are shown right of the names in the top-left player list (thousands separated by dots) and as a gold popup line in the feed (`Events.points_awarded`); small amounts are silent. Funny or spectacular hits pay more. Examples: shot +5 (silent), damage dealt 0.04 per hit point (silent), building 100 (church 250, powder store 300, tavern 150, windmill 200, outhouse 60 ...), 3 / 5 buildings with one shot +200 / +400, settler launched +25 ("Flying lesson"), 3 / 5 / 10 launched in one shot +75 / +150 / +400 ("Triple flyer", "Strike", "Settler bowling"), catapult destroyed +400, 2 catapults in one shot +200, direct hit on a catapult +150, long throw (hit beyond 80 m: 1.5 per extra metre, max 300), chain reaction (powder barrel) +120, animals (chicken 30, cow 60, sheep/duck/goose 40, horse 80), cow burst +100, log stuck in the ground +120 ("World's biggest toothpick"), meteor call +150, shot into the water +10 ("Fish food"), fire started +20, fire put out +15, player eliminated +500, turn survived +10 (silent), winner +1000. Own goals cost points (own building -60, own catapult -200). Online the host decides and sends `pts` messages. The results table has a Points column. Damage to the player's own **or a teammate's** property, own-goal kills and friendly fire count as self damage with penalties (building −60, catapult −200); driving into your own buildings therefore costs points; building a wall pays +20 (silent).

### 14.1 Difficulty parameters
```gdscript
const AI := {
  "peasant": { "aim_noise_deg": 14.0, "power_noise": 0.25, "use_wind": false, "learns": false, "ammo_smart": "none", "target_smart": "random", "think_time": [0.8, 1.6], "sim_samples": 1 },
  "squire":  { "aim_noise_deg": 7.0, "power_noise": 0.14, "use_wind": false, "learns": false, "ammo_smart": "none", "target_smart": "nearest", "think_time": [1.0, 2.0], "sim_samples": 6 },
  "knight":  { "aim_noise_deg": 3.0, "power_noise": 0.07, "use_wind": true, "learns": true, "ammo_smart": "basic", "target_smart": "weakest", "think_time": [1.2, 2.4], "sim_samples": 20 },
  "king":    { "aim_noise_deg": 0.8, "power_noise": 0.02, "use_wind": true, "learns": true, "ammo_smart": "full", "target_smart": "threat", "think_time": [1.5, 2.8], "sim_samples": 60 },
}
```
All bots use the same aiming inputs as a human in effect (azimuth, elevation, power, ammo) and are subject to the same ±0.5° launch spread.

### 14.2 Turn procedure
1. **Pick target player** (rules by `target_smart`): **Allies (same team) are never targets** (`PlayerData.is_enemy`); the same holds for the `R` key and the default facing at placement.
   - `random`: random living enemy.
   - `nearest`: nearest enemy village.
   - `weakest`: enemy with fewest catapults (ties → lowest total village HP).
   - `threat`: score = 3 × (catapults left) + 2 × (enemy's last shot damaged me? yes → +8) + (1 if they are the leader) − 0.02 × distance; pick highest.
2. **Pick target point**:
   - If enemy has known catapults (all are visible): aim at a random living catapult (prefer the one that has the least cover: fewest parts within 4 m; King computes cover by counting parts along the straight line).
   - `peasant`: also 30% chance to aim at any random building instead.
   - Fire targets: King aims at powder store if alive and it is within 4 m of ≥ 1 catapult, or at the barn/haystacks when at least 1 catapult is within 8 m.
3. **Pick catapult** to fire from: random (peasant/squire); knight/king: the one with the best line (least cover in front), prefer not being close (< 15 m) to burning parts and prefer catapults not yet targeted by known threats.
4. **Solve ballistic**: For a target point T, run `sim_samples` random tries: sample (azimuth ≈ direct heading ± 3°, elevation ∈ [20°, 70°], power solved by binary search) using `predict_trajectory` (with or without wind depending on `use_wind`) to minimize landing distance to T; pick the best. Then add noise: azimuth += N(0, aimNoiseDeg), power += N(0, powerNoise) × power.
5. **Learn** (`learns = true`): after a shot at the same target, record error vector (landing − target) in azimuth and range terms; next shot at the same target corrects by the observed error × 0.8 (Knight) or × 1.0 (King); reset when target changes.
6. **Choose ammo**:
   - `ammo_smart none`: Stone always.
   - `basic`: 30% chance for the Flaming Barrel; otherwise Stone by default; 25% chance to use any available special when target catapult has cover (walls: keg / boulder / buckshot) or target village has ≥ 5 settlers close (flints / cow).
   - `full`: Rules in priority: (a) if the target player has ≤ 2 catapults left and the bot has a Meteor Marker → meteor, (b) if the target is behind ≥ 3 walls parts → powderkeg, (c) if a solid wall stands in the way of the target catapult → boulder, (d) if enemy catapults ≥ 3 clustered within 8 m → scatter, (e) 30% cow if available, (f) 35% Flaming Barrel, (g) otherwise stone. Bots earn weapons by the same rules as humans (6.4b).
7. **Execution**: think time random in `think_time`, then camera pans, arm animates the pull over 0.9 s, then fire. Show a thinking bubble (text only, no emoji: "Hmm…" / "Hmmm…") above the bot's selected catapult.
8. Humor: bots occasionally (5%) do a "silly mistake" (fire with random power) even on King; bots occasionally taunt (speech bubble at the start of turn, 25% chance): "Prepare thyself!" / "Bereite dich vor!", "This will hurt you more than me." / "Das tut dir mehr weh als mir.", "I calculated this. Roughly." / "Ich hab das berechnet. Ungefähr.", "Behold, science!" / "Seht her, Wissenschaft!".

### 14.3 Placement AI
Random valid candidates (30 tries per catapult): score = distance from other own catapults ≥ 5 m (mandatory) + for Knight/King prefer positions with buildings within 6 m in the directions toward enemies (cover) + not near powder store (≥ 8 m, King) + not near flammable barn (≥ 8 m, King). Peasant/Squire: purely random.

---

## 15. Performance Requirements

### 15.0 Renderer and lighting presets
The project uses the **Forward+** renderer (Metal on macOS). `SkyRig.apply_lighting(mode)` (setting `Settings.lighting`, applied live, forced to `basic` on the Low tier, `rt` falls back to `enhanced` when the renderer is not Forward+): **basic** = linear tonemap, flat ambient (the old look); **enhanced** = filmic tonemap + saturation/contrast adjustment, SSAO (no SSIL since 1.10.6), bloom (HDR threshold 1.2, softlight, fine glow levels only), soft sun shadows, half the distance fog; **rt** = enhanced + SDFGI (5 cascades, occlusion, bounce feedback) and low-density volumetric fog (light shafts). Godot has no hardware ray tracing; SDFGI is the closest ray-marched GI. Measured on an M4 Max the game is CPU-bound (≈3–4 ms per frame, 250+ fps uncapped at 3456×2234 on every tier); `PhysWorld.buoyant` limits the water tick to floating bodies. Dev benchmark: `MM_PERF_SECS=60 MM_PERF_L=rt MM_PERF_Q=ultra MM_PERF_W=3456 MM_PERF_H=2234 godot --path . -- --autotest=perf` (draw calls, fps, frame spikes, per-system CPU time).

### 15.1 Quality tiers (`render/quality.gd`)
| tier | 3D render scale (`Viewport.scaling_3d_scale`) | MSAA 3D | shadows | shadow atlas | particles cap | dynamic bodies cap | settlers per village | fire emitters | point lights (OmniLight3D) | outlines |
|---|---|---|---|---|---|---|---|---|---|---|
| Low | 0.75 | off | off (blob shadow decals under catapults/settlers) | – | 600 | 350 | 6 | 20 | 2 | off |
| Medium | 1.0 | 2× | on | 1024 | 1500 | 600 | 10 | 40 | 4 | on |
| High | 1.0 | 4× | on | 2048 | 3000 | 900 | 14 | 60 | 6 | on |
| Ultra | 1.0 | 4× | on (soft: `light_angular_distance` > 0, PCF) | 4096 | 6000 | 1400 | 16 | 80 | 8 | on |

Apply shadow size via `RenderingServer.directional_shadow_atlas_set_size(size, true)`, filtering via `RenderingServer.directional_soft_shadow_filter_set_quality`. Quality changes apply live without restart (except nothing requires restart). The particle cap is enforced by the pooled particle system (15.2).

### 15.2 Rules
- Fixed physics timestep 60 Hz through the engine (`physics_ticks_per_second=60`, `max_physics_steps_per_frame=3`; the engine drops time when behind). All gameplay logic that touches physics runs in `_physics_process`; visuals/UI in `_process`.
- **Physics access:** Parts, shards, projectiles, props and ragdoll limbs are bodies created directly on `PhysicsServer3D` (RIDs; `body_create`, `shape_create`, `body_add_shape`, `body_set_space`) — **not** as `RigidBody3D` nodes — to avoid per-node overhead. Simple singletons (catapult base, terrain, dormant structures) may use `StaticBody3D`/`RigidBody3D` nodes if that is simpler. A thin wrapper in `physics/world.gd` owns all RIDs, ids, freeing and the id→object registry.
- **Sync of awake bodies:** register per body `PhysicsServer3D.body_set_state_sync_callback(rid, callable)` (called only for active bodies) and write the transform into the visual; sleeping bodies cost nothing per frame. If that API is not usable in the installed version, fall back to iterating an "awake list" and reading `PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM)`, skipping bodies where `BODY_STATE_SLEEPING` is true. Contact impulses come from `PhysicsDirectBodyState3D.get_contact_impulse()` (enable with `body_set_max_contacts_reported`, only for parts/projectiles/catapults/settlers, small value like 4).
- Enable continuous collision detection on projectiles (`body_set_enable_continuous_collision_detection`).
- **Rendering of parts:**
  - Dormant buildings: one merged `ArrayMesh` per material per structure (merge manually with `Util.merge_meshes`; `SurfaceTool` allowed), one `MeshInstance3D` per material. Vertex colors carry per-part color; a single toon material per material class reads `COLOR`.
  - Awake parts: one `MeshInstance3D` each, sharing `Mesh` and `ShaderMaterial` resources (materials cached per palette color; instance uniform `instance_uniform` for color is allowed). Debris shards, hay, coins, particles' physical droplets, trees' repeated instances and grass/rocks decor use `MultiMeshInstance3D` (pool per shape+material, max 2048 instances each; unused instances hidden by zero-scale transform + `visible_instance_count` management).
  - Never call `add_child` / `queue_free` for hundreds of nodes in one frame: budget spawns (≤ 60 nodes/frame) via a spawn queue.
- Colliders: boxes, cylinders, spheres, capsules only. No concave trimesh shapes for dynamic bodies. Terrain: one `HeightMapShape3D` collider (`StaticBody3D`). Dormant structures: one `StaticBody3D` per structure with one `BoxShape3D`/`CylinderShape3D` child per part (compound).
- Shadow: one `DirectionalLight3D`, `directional_shadow_mode = PSSM 2 Splits`, `directional_shadow_max_distance` fitted (≈ 90 m Medium). Do not re-render shadows more often than needed if the engine allows (`light_bake`/update mode is not required; acceptable to leave default).
- Particles: pooled `GPUParticles3D` emitters, one pool per effect preset (see `fx/particles.gd`: splinter, dust, straw, spark, glitter, smoke, flame, steam, splash, feather, wool, bee, stink, confetti, leaf, rain). Each preset: `one_shot=true`, small `amount` (≤ 64), custom `ParticleProcessMaterial`, unshaded billboard quad mesh with `use_billboard`-style draw pass (`BaseMaterial3D` billboard mode particles, or a hand-written `shader_type spatial` with `render_mode unshaded`), spawned by `restart()` at a position from a pool (reuse, never instantiate at runtime beyond the pool). Global live-particle budget = tier particle cap (track `amount` of active emitters).
- Speech bubbles and comic text: `Label3D` pool (max 6 bubbles alive, max 3 comic texts alive), billboard, `no_depth_test=true`, fixed size scaled by distance.
- Settlers: a **single kinematic capsule** (or none: pure logic + transform snapping to terrain) per walking settler with animated child meshes (no per-limb bodies). Ragdoll = 6 bodies (torso, head, 2 arms, 2 legs) connected with `PhysicsServer3D.joint_make_cone_twist` or `joint_make_pin`, **only in ragdoll state**. Convert to ragdoll on hit (impulse > 40 or explosion or fire-launch). After 6 s asleep the ragdoll bodies are removed and the settler becomes a static "lying" mesh (pose frozen, if dead) or gets up (if alive, hp > 0: 3 s later, walking again with "Ow." bubble). Limit simultaneously active ragdolls to 40 (others convert immediately to frozen pose). Walking settlers update at 10 Hz (lower when far from the camera).
- Frame budget (Medium, reference M1/Iris Xe): physics ≤ 6 ms, all GDScript game logic ≤ 3 ms, render ≤ 8 ms. GDScript is slower than JavaScript-JIT for tight loops — so: budget round-robin work per frame (fire ≤ 200 parts/tick, support checks ≤ 1 structure/frame, settlers 10 Hz), use packed arrays and integer indices, cache node references, avoid `get_node` in loops, avoid `Dictionary` lookups in inner loops when an array index works.
- `Engine.max_fps = 0` (vsync on via `DisplayServer.window_set_vsync_mode(ENABLED)`, option in menu). Clamp `delta` in `_process` to 1/20 s. Pause (`get_tree().paused`) when the window loses focus (`NOTIFICATION_APPLICATION_FOCUS_OUT`) during a human turn only.
- Debug overlay: launch with user arg `-- --debug` (see 22) or press `F3` in debug builds: FPS (`Engine.get_frames_per_second()`), frame ms, physics active bodies (`Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)`), our body count / awake count, draw calls (`Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME`), particles alive, memory (`Performance.MEMORY_STATIC`). Hand-written `Label` overlay.
- Auto quality: if average FPS < 40 for 5 s, drop one tier (if the option `Auto quality` is on, default on) and show a small toast.
- Slow motion uses `Engine.time_scale` (0.25); UI timers and animations that must keep real time use `Time.get_ticks_msec()` deltas.

---

## 16. Visual Style

### 16.1 Look
- Toon/cel look via a hand-written `spatial` shader (`render/shaders/toon.gdshader`): `render_mode unshaded`-free normal spatial shader with a custom `light()` function that quantizes `NdotL * ATTENUATION` into **4 steps** (0.31, 0.55, 0.78, 1.0, hard edges via `floor`), `specular_disabled`, `ALBEDO` from `COLOR` (vertex color) × `albedo` uniform. One shader, many materials (uniform for tint/emission, cached per palette color). Shadows work through the normal `ATTENUATION` path.
- Outlines: inverted hull as `next_pass` material of the toon material: `shader_type spatial; render_mode cull_front, unshaded;` vertex: `VERTEX += NORMAL * 0.03;` (uniform `width`), fragment: `ALBEDO = vec3(0.10, 0.07, 0.13)` (#1a1220). Works with `MeshInstance3D` and `MultiMeshInstance3D`. Skip outlines for particles, terrain, water, sky. For thin parts (< 0.15 m) use width 0.015. Outlines off on Low.
- Lighting: 1 `DirectionalLight3D` (warm `#fff1d0`, energy 1.6), an `Environment` with ambient light from sky/color (`ambient_light_source = COLOR`, sky-ish `#9fd8ff` at energy 0.9, approximating the hemisphere light; a subtle ground-tint via a second very weak upward-facing fill is allowed), fog enabled exponential (`fog_density` 0.006, color = sky horizon, density increases in rain), tonemap `FILMIC` or `LINEAR` (choose what gives saturated comic colors; no glow, no SSAO, no SSR).
- Sky: a custom sky shader (`shader_type sky`) with vertical gradient (top `#4aa8ff`, horizon `#ffe9b8`; storm: `#4a5568` / `#8a8f99`, blended by weather), a sun disc using `LIGHT0_DIRECTION`, plus 8–14 procedural puffy clouds (grouped white toon spheres as `MeshInstance3D`s, slowly drifting with wind, wrap around the map).
- Post: none required. Optional cheap vignette via a `ColorRect` with a radial-gradient shader on the UI layer.
- Fonts: HUD/menus use `SystemFont` with `font_names = ["Trebuchet MS", "Comic Sans MS", "Verdana", "DejaVu Sans", "Arial"]` (falls back to the engine default if none exists — must still look fine); comic text uses `SystemFont` `["Impact", "Arial Black", "Haettenschweiler", "DejaVu Sans Bold", "Arial"]` with `font_weight = 900` / `Label3D.outline_size`. Verify German umlauts and emoji-free rendering on all platforms: **do not rely on emoji glyphs** (ammo icons in the HUD are drawn procedurally with `Control._draw()` shapes/colored circles plus a 1–2 letter label; see 18.1).
- UI look: chunky rounded parchment panels (`StyleBoxFlat`: bg `#f4e4bc`, border `#3b2a1a` 3 px, corner radius 14, shadow via `shadow_size`), bright buttons (`#e74c3c`, `#f1c40f`), hover wobble via `Tween` (scale/rotation ±2°). Built once in `ui/theme.gd` into a `Theme` applied to the UI root `Control`.

### 16.2 Palette (for materials colors, pick via RNG from these sets)
- wood: #b5763a, #a0622d, #c58a4a
- plank: #d09a5a, #c48748
- stone: #9aa0a6, #8a9096, #a9aeb3
- brick: #c0533a, #b34a33
- thatch: #e0c060, #d4b04a
- roof tile: #c0392b, #d35400, #8e44ad-ish accent 10%
- plaster wall (farmhouse): #f2e6c9, #eddcb0
- metal: #7f8c9a
- grass: see 7.6, water: #3fa9f5 alpha 0.75
- fire: #ffb347 → #ff5722 → #2b2b2b

### 16.3 Catapult model (`scripts/entities/catapult.gd`)
Procedural: wooden base frame (2.4×0.3×1.6), 4 wheels (cylinders, metal hubs), vertical side frames, rotating arm (long box 3 m, pivot 1.1 m above base) with a bucket (open cylinder/box) at the end; the arm rotates about the pivot; rope; a colored flag/decal on the frame with the player's color; a little nameplate "owner name" floating above (`Label3D`, only visible during TURN and in overview, size scaled by distance).
Physics: base = one dynamic box body (`PhysicsServer3D` or `RigidBody3D`) (mass 400 kg, damping 0.3), arm is animated (not physical), destroyed catapult replaced by dynamic parts (frame planks ×6, wheels ×4, arm ×1, each own body).
Selection highlight: a pulsating ring + outline color. Show hp bar above catapult while aiming or when damaged (small, world-space billboard quad).

### 16.4 Settlers (`scripts/entities/settler.gd`)
Capsule-style procedural model: body (cylinder tapered, tunic color), head (sphere), nose (small cone), arms/legs (thin boxes; animated by sin walk cycle), hat variants. Behaviors (state machine, updated at 10 Hz for all, lower for far):
- `idle` (stand, occasionally chat bubble),
- `wander` (walk to random point in village at 1.2 m/s, avoid buildings by simple steering with terrain height snapping via heightfield lookup),
- `work` (near a building: hammer animation at 20% frequency — and **rebuilding**, below),
- `panic` (run away from explosion/projectile impact point at 3.5 m/s, screaming bubble),
- `extinguish` (grab bucket, run to nearest water (well/pond/river/water barrel), then to nearest fire (max distance 20 m), throw water; each throw extinguishes fire in radius 1.6 m, chain up to 4 settlers passing the bucket if ≥ 3 idle settlers available),
- `burning` (run randomly, 5 dmg/s),
- `ragdoll` (physics),
- `dead` (frozen pose, fades away after 30 s or stays; cap).
**Rebuilding (`systems/repair.gd`, `Settler._try_repair`)**: settlers give the village a meaning. A calm settler (idle, not in panic / burning / fleeing, alive; each idle settler tries it with 55% chance when its idle timer runs out) looks for a **missing part of a building of its own village** — a part that is `DEAD`, or a fallen piece that lies asleep (it is carried back with `Breakable.reattach_part`) — walks to it, takes a **hammer** (a small tool mesh in the right hand, only visible while working), hammers for **11 s** (a knock sound every 0.9 s, the arm animation of `work`) and then the part is back in its old place (`Breakable.revive_part`, dust puff). It is deliberately **slow and mostly cosmetic**: at most **3 builders per village**, one part each, low parts first and only parts that have something to rest on (ground or a standing part), only in the **calm phases of a turn** (`TURN_START`, `AIMING`, `TURN_END`; work pauses during flight / aftermath), never for trees, palisade posts, player walls or props, **never for catapults**, and **not on an online client** (the host's turn snapshot restores the parts there). Panic, fire, ragdoll or death cancels the job (the claim is released); **dead settlers cannot rebuild**, so killing the villagers stops the repairs. `Structure.destroyed` stays set once reached (no second destruction points).
Kill attribution and stats as 13. Every settler killed spawns a small gravestone-shaped billboard? No. On death: a tiny ghost billboard rises (white, semi-transparent, 2 s) — cute and comic.

---

## 17. Audio (`scripts/autoload/sfx.gd`)

**No audio files.** At startup `Sfx` synthesizes every sound below into an `AudioStreamWAV` (16-bit PCM mono, 32 000 Hz, `format = FORMAT_16_BITS`, `data = PackedByteArray`) using a small GDScript synth kit (oscillators sine/square/saw/triangle, noise white/pink/brown, ADSR/exp envelope, biquad low/high/band-pass filter, pitch sweep, vibrato/tremolo, simple soft-clip distortion, mixing of partials). Cache streams in a `Dictionary` by name; for frequently repeated sounds (thunk, clack, crunch, splash, boing, scream, moo …) pre-render **3 variants** with slightly different parameters. Generation may run on a worker `Thread` (or in chunks with `await get_tree().process_frame`) while the splash shows progress; total budget < 3 s on a mid-range laptop; emit `Sfx.ready` when done.

Playback: a pool of 24 `AudioStreamPlayer` (2D/global) and 24 `AudioStreamPlayer3D` nodes (`unit_size` ≈ 20, `max_distance` ≈ 250, attenuation model inverse-square-clamped) reused round-robin with priority stealing; `pitch_scale = randf_range(0.92, 1.08)` per play; UI sounds use non-3D players. Master volume from settings via `AudioServer.set_bus_volume_db(0, linear_to_db(v))`. Looped sounds (`fire_loop`, `rain_loop`, `gust`, `buzz`) use `loop_mode = LOOP_FORWARD` with `loop_end` set to the sample count; volume/pitch modulated at runtime. Audio starts only after the first user input is not required on desktop (no autoplay restrictions), but do not play before `START BATTLE`/menu interaction except UI sounds.

Provide `Sfx.play(name, position := Vector3.INF, volume := 1.0, priority := 0)` (INF = non-positional). **Sound design v2 (required quality bar).** The effects must not sound like beeps: every effect is a *layered* design (sharp transient + body + tail, loudness-matched, reverberated where it makes sense), built from: polyBLEP saw/square oscillators, FM, **modal resonator banks** (wood, metal, glass, bell), **Karplus-Strong plucked string** (catapult rope), a **vocal formant source** (animals, settlers, horns), RBJ biquads incl. swept filters, a Freeverb-style room reverb, soft saturation and seamless equal-power loops (fire, rain, wind, bees). Explosions = noise crack + pressure body (brown noise, swept low-pass) + pitch-dropping sub + debris rattle + large room; impacts = pitch-dropping sub + dull body noise + click; brass (turn start, victory, defeat, stinger) = detuned saws with an opening low-pass and vibrato. `tests/sound_probe.gd` prints duration / peak / RMS / spectrum split / NaN check for every sound. The table below only names the layers roughly; the exact recipes live in `core/sound_recipes.gd`. Synthesis recipes (all with random pitch ±8% to avoid repetition):
| name | synthesis |
|---|---|
| `thunk` | short sine 120→60 Hz thump + noise burst lowpass 400 Hz, 0.12 s |
| `clack` | two quick triangle blips 700 & 500 Hz + highpass noise, 0.08 s |
| `crunch` | noise bursts lowpass 800, 3 x 20ms with random spacing, decreasing |
| `clang` | 3 detuned square/sine partials 620, 930, 1490 Hz exp decay 0.5 s |
| `tinkle` | 4–6 random sine pings 2–4 kHz, 40 ms each, staggered |
| `fwump` | lowpass noise 200 Hz, 0.2 s |
| `swish` | bandpass noise sweep 300→2000 Hz 0.25 s |
| `boom` | sine sweep 90→30 Hz 0.8 s + noise lowpass sweep 1500→100 Hz 0.9 s, plus optional distortion |
| `bigboom` | boom ×1.5 length, added sub 30 Hz rumble 1.5 s |
| `whoosh` | highpass noise whoosh 0.4 s (projectile launch) |
| `twang` | triangle 180 Hz pluck with fast decay + slight pitch bend (slingshot release) |
| `creak` | sawtooth 60–90 Hz with slow amplitude wobble 0.5 s (arm pull); level 0.4 |
| `fire_loop` | filtered brown noise + random crackle pops; volume by number of active fires near camera (one loop node total) |
| `splash` | bandpass noise 1000 Hz 0.3 s with decay + bubble blips |
| `moo` | **Animal and people voices v4: cartoon instruments, no voice formants** (the formant voices sounded creepy). Cow: soft tuba "muuuh" (two detuned saws + a square an octave down, vibrato, low-pass opening 260→1250→420 Hz), 1.0–1.3 s, 3 variants; level 0.45 |
| `bawk` | chicken: 3–4 quick wooden "bok" FM blips falling 720→470 Hz, 3 variants; level 0.36 |
| `baa` | sheep: soft kazoo-like bleat (saw + triangle 330→290 Hz, 24 Hz tremolo depth 0.45, low-pass 1.7 kHz), 0.7–0.95 s, 3 variants; level 0.38 |
| `neigh` | horse: playful slide-whistle whinny (sine 520→1350 Hz, then 1350→760 Hz with vibrato), 1.3 s, 2 variants; level 0.38 |
| `quack` | duck: 2–3 kazoo-like FM quacks (420→300 Hz) getting quieter, 3 variants; `honk` (goose): two toy-trumpet notes via `_brass` (330→360 and 300→330 Hz), 2 variants; levels 0.36 / 0.4 |
| `squeak` | sine 1200→2000 Hz 0.08 s |
| `bell` | sines 520, 1040, 1560 Hz exp decay 2 s ("BONG") |
| `scream` | comic settler "waaah": slide-whistle rise and fall (sine, base 480–700 Hz ×1.9 then ×0.85, vibrato 8–10 Hz) plus a quiet triangle, low-passed, 0.9 s; level 0.38 |
| `yeet` | sine sweep rising 300→1400 Hz 0.5 s with slight tremolo |
| `boing` | sine with pitch wobble 200→400→200, 0.3 s |
| `buzz` | sawtooth 180 Hz + AM 40 Hz, looped, for bees |
| `thunder` | brown noise lowpass sweep 600→60 Hz, 2.5 s with rumble tail, delayed by distance |
| `zap` | sawtooth 3 kHz → 200 Hz in 80 ms + noise |
| `rain_loop` | pink/white noise highpass 1000 Hz low volume |
| `gust` | bandpass noise slow LFO (storm) |
| `stinger_event` | ascending 4-note arpeggio (square, C-E-G-C) 0.5 s |
| `ui_click` | sine 800 Hz 30 ms |
| `ui_hover` | sine 500 Hz 15 ms quiet |
| `turn_start` | two-note fanfare (trumpet-like sawtooth with lowpass: G4, C5) |
| `victory` | 6-note major fanfare + cheering noise burst |
| `defeat` | descending trombone "wah wah wah waaah" (sawtooth slides) |
| `splat` | noise burst + sine 200→80 Hz, wet 0.15 s |
| `pop` | sine burst 400 Hz with fast decay (bubble) |

Music: none required. Optional: a simple looping 8-bar chiptune-ish medieval march synthesized the same way, off by default (setting) — can be skipped.

Limit concurrent sounds to 24 (drop lowest priority or oldest). Do not play more than 6 impact sounds per 100 ms.

---

## 18. UI Details

### 18.1 HUD (during BATTLE)
- Top center: current player's name + color + turn banner and timer (circular).
- Top left: list of players with color chip, name, catapults left (5 small catapult icons: green alive/red destroyed), and "current" marker.
- Top right: wind arrow + speed (m/s) and weather icon; settings button (opens pause menu).
- Bottom center: **ammo bar** (flat, see 6.4: 13 slots, 52×52 px) and above it ONE **hint strip** (`Hud.KeyHints`): a parchment pill with key caps and short labels that shows only what is possible right now — aiming: `Drag Fire · Q/E Turn · ↑↓ Elevation · Tab Catapult · R Enemy · M Marker · V Overview`; reposition: `W/S Drive · A/D Steer · Space Done (turn ends) · Distance n m · 1-9 Weapon · V Overview`; wall: `Click Build wall (turn ends) · Q/E Turn · Click a wall Stack on top · 1-9 Weapon · V Overview`; overview: `Click Set marker · Right-click Rotate camera · V Back`; aftermath: `Click / Space Next turn · V Overview`. The `V Overview` and `Click / Space Next turn` chips are clickable (only the chips catch the mouse). There is no grey/white help text at the bottom any more.
- Bottom left: aim info (power %, elevation°, azimuth°) during aiming.
- Bottom right: catapult selector (numbered buttons, **right-aligned with the buttons below**, 6.4 / 2.4), then three uniform parchment buttons with key-cap chips (`KeyButton`): `[F] Fast-forward`, `[X hold] Skip turn`, and `Sound`. The overview camera is no button (key `V` / the chip in the strip).
- Center: announcer banner (slides in, 2.5 s).
- Kill-feed at the left (max 5 lines, 4 s): "{attacker} launched Bob into orbit", "{attacker}'s stone flattened a Cosy Cottage", "{victim}'s catapult was lost to the fire". Provide a few variants in lang files.
- Pause menu (Esc): Resume, Restart (same seed), Quit to menu, Options. The language row of the pause menu uses the DE/EN flags.

### 18.2 Camera controls
- `AIMING`: as described. `Right mouse drag` orbit, mouse wheel zoom, `Shift+wheel` elevation.
- `OVERVIEW` (V toggles at any time in own turn, and always available between turns): free camera: right drag orbit around focus, middle/`Shift+right` drag pan, wheel zoom; `WASD` pan; `Home` recenters; auto-returns after fire. **It must show the whole playfield**: focus on the map center, distance ≈ 1.9 × map radius at 58° pitch, zoom out up to 3.2 × map radius, and **the camera-arm collision shortening is never applied** in this mode (otherwise the camera is pulled into the ground). Left click sets the map marker (6.7).
- **The overview stays open while somebody else plays** (a CPU or an online player): `CameraRig.hold_overview` makes the game cameras (aim, follow, impact, focus) ignore the request while the overview is open and it is not the local human's turn; the overview is only closed by `V` or when the player's own turn starts. The hint strip then shows `V Overview`.
- Impact cam: at first collision of projectile: camera moves to hover 12 m from impact at 35° pitch, maintains for aftermath, blends smoothly (`lerp` with damping k=4). Slight screen shake (translate camera by noise, amplitude = min(1.5, blastDamage/900)).
- The camera never enters terrain or goes below terrainHeight + 1.

### 18.3 Accessibility/Settings
Settings persisted via `ConfigFile` at `user://settings.cfg` (autoload `Settings`): language, volume, quality, shake, timer, weather, events, autoquality, fullscreen, vsync, window size, last used player list, relay URL, online name, and the starting arsenal **only as `custom` + the custom counts** (a chosen preset or a tweak of a preset is never saved; the next start begins with `Standard`).

---

## 19. Localization (`scripts/autoload/i18n.gd`, `scripts/lang/en.gd`, `scripts/lang/de.gd`)

- Language data are GDScript files: `const DATA := { "menu": { "start": "Start battle", ... }, "speech": { "panic": ["RUN!", ...] }, ... }` (nested dictionaries; keys are dotted paths like `menu.start`). Do NOT use `.po`/`.csv`/`TranslationServer`; own lookup keeps it simple and testable.
- `I18n.t(key, params := {})` looks up nested keys, replaces `{name}` placeholders, falls back to English, then to the key itself. `I18n.tr_list(key) -> Array` returns arrays of random lines; pick with `Rng.pick`. (Do not name the method `tr` — it clashes with `Object.tr`.)
- All UI, banners, kill feed, speech bubbles, comic text, titles, event names must be in both languages. Language switch applies instantly to the menu (rebuild labels through a `language_changed` signal); in-game text uses the current language at the time it is generated. Names of ammo/buildings in lang files under `ammo.<id>` and `building.<id>` using the names in sections 6.4 and 9.
- Provide minimum keys: `menu.*`, `hud.*`, `placement.*`, `ammo.*`, `building.*`, `banner.*`, `speech.*`, `comic.*`, `event.*`, `title.*`, `loading.*`, `kill.*`, `stats.*`, `pause.*`.
- Casing: button and banner texts are normal case (no ALL CAPS buttons). Extra key groups: `hint.*` (hint strip), `action.*` (turn action toasts), `ammo_tip.<id>.what/pro/con` (tooltips; empty lists are omitted, the test forbids empty lists), `net.*` incl. the relay help texts, `menu.ars_*` and `menu.color_*`.
- A test (`tests/test_i18n.gd`) verifies both language files have identical key sets and no empty strings.

---

## 20. Module Contracts (key APIs)

```gdscript
# physics/world.gd  (class_name PhysWorld, static + a singleton Node "PhysRoot" created by main.gd)
static func init_physics() -> void
static func add_body(desc: Dictionary) -> int              # returns id; desc: shape(s), transform, mass, material, layer/mask, kind
static func remove_body(id: int) -> void
static func body_rid(id: int) -> RID
static func for_each_awake(cb: Callable) -> void
static func raycast(origin: Vector3, dir: Vector3, max_t: float) -> Dictionary   # {} or {point, normal, collider_id}
static func overlap_sphere(center: Vector3, r: float, cb: Callable) -> void      # PhysicsDirectSpaceState3D.intersect_shape

# systems/damage.gd
static func apply_impact(part: Part, impulse: float, source: Dictionary) -> void
static func damage_in_radius(center: Vector3, radius: float, max_damage: float, source: Dictionary) -> void

# systems/fire.gd
static func ignite(part: Part, amount: float, source: Dictionary) -> void
static func extinguish_in_radius(center: Vector3, r: float) -> void
static func update(dt: float) -> void

# systems/explosion.gd
static func explode(pos: Vector3, radius: float, max_damage: float, opts: Dictionary) -> void

# systems/turn.gd
static func start_battle(players: Array) -> void
static func predict_trajectory(start_pos: Vector3, velocity: Vector3, ammo_id: String, wind: Vector2, max_t: float) -> Dictionary  # {points: PackedVector3Array, flight_time, landing: Vector3}
static func current_player() -> PlayerData

# entities/projectile.gd
static func launch(ammo_id: String, muzzle_pos: Vector3, velocity: Vector3, owner_player_id: int) -> Projectile
```

`autoload/events.gd` declares these signals (systems emit, stats/killfeed/audio/UI connect; systems never call UI directly):
`projectile_launch`, `projectile_impact`, `part_break`, `building_destroyed`, `settler_hit`, `settler_killed`, `catapult_destroyed`, `fire_started`, `fire_out`, `explosion`, `turn_start`, `turn_end`, `player_eliminated`, `game_over`, `weather_change`, `event_start`, `language_changed`, `quality_changed`.

Data classes: `PlayerData`, `Part`, `Structure`, `AmmoDef`, `MaterialDef` are `RefCounted` classes with typed fields (no untyped dictionaries for core data). `source` dictionaries are `{player_id: int, ammo: String}`.

---

## 21. Implementation Phases and Acceptance Tests

Implement strictly in order. After each phase the game must start (`godot --path . `) without errors or warnings in the output. Every phase adds headless tests under `tests/` where logic is testable without rendering; run them with:
```
godot --headless --path . --script res://tests/run_tests.gd
```
`run_tests.gd` (`extends SceneTree`) discovers `tests/test_*.gd`, runs every `func test_*()`, prints a summary and calls `quit(1)` on any failure. Rendering/feel checks are done by running the game (also allowed: a `--autotest` user arg that starts a scripted scenario, saves screenshots with `get_viewport().get_texture().get_image().save_png("user://shot_N.png")`, and exits).

**Phase 1 — Foundation.** `project.godot`, autoloads (cfg, events, settings, i18n stub), main scene, toon + outline shaders, sky, seeded terrain (no villages) with `HeightMapShape3D`, free overview camera, debug overlay, quality tiers, window handling.
*Accept:* terrain renders with hills/water at 60 FPS; debug key `B` spawns a ball that rolls on the terrain and splashes in water; same seed → identical heightmap hash (test).

**Phase 2 — Destructibles.** materials, kit.gd, parts, dormant/awake structures, glue links + support check, debris cap; buildings: farmhouse, barn, watchtower, well; props: barrel, crate, haybale; one catapult with aiming (slingshot), Stone ammo, preview at 40%, wind; explosions/craters minimal (Stone impact damage only).
*Accept:* firing a stone at a farmhouse damages and topples parts; a tower falls over as expected; sleeping bodies cost no CPU (body count vs. awake count in the debug overlay); support-check unit test (removing the foundation releases all parts).

**Phase 3 — Game loop.** Menu, player setup, generation of villages (all mandatory buildings available so far, missing types substituted by farmhouse), placement UI, turn manager, settle detection, elimination, GAME_OVER screen, HUD, i18n skeleton (EN/DE for all UI), CPU "peasant" stub (random shot).
*Accept:* a full game 2–8 players playable with human + peasant bots start to finish; elimination and winner work. **First playable milestone.**

**Phase 4 — Content.** All 16 buildings, all props, animals, settlers with behaviors + ragdolls, speech bubbles, comic texts, kill feed.
*Accept:* every building type builds and collapses without errors or NaNs (test builds each type, applies a big explosion, steps physics 300 ticks headless); settlers ragdoll properly when hit; ≤ 700 parts per village.

**Phase 5 — Elements.** Fire, water, explosions, all ammo types, powder chain reactions, well/water tower rupture, craters, catapult destruction, steam/smoke.
*Accept:* fire spreads across a thatch barn to adjacent buildings and burns down; powder store chain explosion works; all 9 ammo types work (earned weapons unlock by the rules of 6.4b); the flaming barrel rolls ≥ 5 s; palisade posts stack and fall together.

**Phase 6 — AI.** Full cpu.gd per section 14; difficulty comparisons: Peasant misses > 80% at 60 m, King hits within 3 m on average when no wind noise applies (test on `predict_trajectory` without full physics).
*Accept:* 4-bot game (Peasant, Squire, Knight, King) runs alone to completion (`--autotest` with a speed-up); King wins most.

**Phase 7 — Extras.** Weather, random events, impact focus, statistics, titles, all audio, full localization check, pause menu, settings persistence.
*Accept:* every event in 11.5 can be triggered via debug key `E` cycle; all sounds exist in the `Sfx` cache (test); both languages complete (i18n test passes, no key fallbacks visible).

**Phase 8 — Polish, performance and packaging.** Auto quality, shadow optimization, pooled particles audit, allocation audit, bugs, README, **export builds for all three platforms (section 25)**.
*Accept:* 4 players Medium ≥ 55 FPS average during a firefight; no memory growth beyond 50% in a 20 minute session (bodies, meshes, materials disposed; check `Performance.OBJECT_COUNT`, `OBJECT_ORPHAN_NODE_COUNT` = 0 after returning to the menu); exported macOS/Windows/Linux builds start by double-click.

---

## 22. Debug Keys (only when launched with user arg `--debug`, e.g. `godot --path . -- --debug`, or in editor/debug builds; release exports without the arg ignore them)
`B` spawn test ball, `E` cycle random events, `W` cycle weather, `K` kill current player's selected catapult, `F` ignite the part under the cursor, `X` explode at the cursor point (radius 6), `C` toggle physics collider wireframes (`get_tree().debug_collisions_hint` / `RenderingServer` debug draw), `H` heal all catapults, `T` toggle slow motion 0.25×, `O` toggle outlines, `F3` debug overlay.

---

## 23. Edge Cases (must be handled)
- Shot never lands (out of world): after 12 s, despawn; counts as miss.
- Window loses focus / minimized mid-turn: pause simulation, resume without timer jump (use accumulated active time, not wall-clock).
- Catapult fired while another projectile is alive: not possible (one projectile at a time; scatter pellets / cow chunks / red-barrel fragments do not count).
- Player eliminated during AFTERMATH by fire after the turn ended: handled at the next `TURN_END` check (also verify at `GAME_OVER` check after each turn).
- If a catapult is placed on a building that later collapses and it falls: catapult body is dynamic, so it falls; tipping rule applies.
- Extremely long AFTERMATH: `SETTLE_MAX` forced end.
- Bots when all enemies' catapults are somehow unreachable: fire at any building of the strongest enemy.
- Heightfield rebuild after craters: throttled and batched (update `HeightMapShape3D.map_data` and the mesh region); ignore craters outside the map.
- NaN guard: if any body's origin becomes NaN/inf or |y| > 500, remove it.
- Seeds: same seed + same settings must produce the same map and same initial layout on all platforms (battle is not deterministic across frame rates; that's OK). Use only `Rng` (own mulberry32 + FNV-1a string hash), never `randf()`/`RandomNumberGenerator` default seeding for generation; do not use `String.hash()`.
- Window resize / fullscreen toggle / HiDPI: 3D viewport and UI reflow (stretch mode `canvas_items`, `expand`); pull distance `DRAG_MAX_PX` scales with window height / 900.
- Human tries to select an enemy catapult: ignore.
- All players CPU: allowed (spectator mode with camera auto-follow, `Space` speeds up time ×3 as toggle).
- Save/settings file missing or corrupt (`user://settings.cfg`): fall back to defaults silently.
- Quit during any state (window close, Alt+F4/Cmd+Q): free everything cleanly, no errors on exit.

---

## 24. README.md (to be written in Phase 8)
Contents: what the game is; how to run from source (`godot --path .` or `./run.sh`); how to build (`./export.sh`, section 25); controls table (mouse drag to aim, right-drag to orbit, V overview, 1–8 ammo, Tab cycle catapult, Space fire, Esc pause, F11 fullscreen); platform notes (macOS Gatekeeper: right-click → Open on first launch for the unsigned app; Linux: `chmod +x`); credits line "Made with Godot Engine". Note that no assets are external. The controls table also lists `U` (reposition catapult), `B` (build stone wall), `W/A/S/D` (drive), `Q/E` (turn the wall ghost), the hint strip and the teams rule.

---

## 25. Packaging and Cross-Platform Builds

Goal: a player downloads one file per platform, double-clicks it, and plays. No installer, no engine, no internet.

### 25.1 Export presets (`export_presets.cfg`, committed)
| preset | target | notes |
|---|---|---|
| `Windows` | Windows Desktop, x86_64 | output `build/windows/MedievalMadness.exe`; **embed PCK** on (single .exe); no code signing; icon from `icon.svg` if the toolchain allows, otherwise engine default |
| `macOS` | macOS, **universal** (arm64 + x86_64) | output `build/macos/MedievalMadness.zip` containing `MedievalMadness.app`; bundle id `com.example.medievalmadness`; ad-hoc/no signing and no notarization (documented in README: right-click → Open); `application/min_macos_version` 12.0 |
| `Linux` | Linux, x86_64 | output `build/linux/MedievalMadness.x86_64`; **embed PCK** on (single file); README notes `chmod +x` |

Export runs headless with the matching export templates installed:
```
godot --headless --path . --export-release "Windows" build/windows/MedievalMadness.exe
godot --headless --path . --export-release "macOS"   build/macos/MedievalMadness.zip
godot --headless --path . --export-release "Linux"   build/linux/MedievalMadness.x86_64
```
`export.sh` / `export.bat` create the `build/*` directories, run all three exports, print sizes and fail loudly on error. `build/` is git-ignored (add `.gitignore`).
`export.sh` / `export.bat` also (1) **increase the patch number in `VERSION` and write the version into `export_presets.cfg`** (macOS `application/short_version` + `application/version`, Windows file / product version, iOS, Android `version/name` + `version/code` = major×10000 + minor×100 + patch; so Finder, Explorer and the stores show the real version) (so the version in the menu counts up with every build), (2) copy `relay/PROTOCOL.md`, `relay/template/relay_node.mjs` and `relay/template/check.mjs` to `assets/relay_help/{spec,relay_node,check}.txt` (the presets use `include_filter="VERSION, assets/relay_help/*"` and `exclude_filter="build/*, *.md, run.sh, run.bat, export.sh, export.bat, relay/*"`).

### 25.2 Cross-platform rules (checklist the implementer must satisfy)
- Only engine-provided APIs; no `OS.execute`, no shell, no file dialogs (none needed), no reads outside `res://` and `user://`.
- All strings/paths use `/`; case-sensitive file names (Linux): the file name in code must match the file on disk exactly.
- No reliance on system fonts being present: every `SystemFont` has a fallback chain and the UI must remain usable with the engine default font.
- Vulkan 1.0-class feature set only (Mobile renderer). No compute-shader-dependent features, no `GPUParticles3D` features that require newer GPUs beyond the Mobile renderer's support; if `GPUParticles3D` misbehaves on a driver, `CPUParticles3D` with the same preset is an allowed drop-in (keep the preset API identical so switching is one flag: `Settings.cpu_particles`).
- macOS: high-DPI support on (`display/window/dpi/allow_hidpi=true`), keyboard shortcuts must not require the Windows key; Cmd+Q quits.
- Shader code must compile identically on Metal/Vulkan drivers: avoid undefined behavior (uninitialized variables, out-of-range array indices, division by zero).
- File writes only to `user://` (settings); the game must run from a read-only location.
- Frame pacing: vsync on by default; menu option `VSync`.
- Test matrix to run at least once per platform available to the implementer: start game → menu → 2-player human vs. Peasant game to completion → quit; verify settings persist after restart.

### 25.2b GitHub Actions
`.github/workflows/build.yml` (repository root = the project folder) installs Godot 4.7.2 and its export templates on `ubuntu-latest`, runs `./export.sh` with `MM_BUILD_NUMBER=$GITHUB_RUN_NUMBER` (becomes the patch number) and uploads `build/` as an artifact; tags `v*` also attach the files to a release. The macOS build is unsigned (Gatekeeper warning); not testable locally.

### 25.3 Optional (out of scope unless everything else is done)
Web export, mobile, gamepad, online multiplayer, code signing/notarization, auto-updater, installers.

## 19. Online play (up to 8 players)

**Transport** (`autoload/net.gd`): one WebSocket per player to a **relay** (`relay/cloudflare/worker.js` on Cloudflare Workers + Durable Objects, `tools/relay_server.gd` self-hosted, or `relay/template/relay_node.mjs`; same protocol, specified in `relay/PROTOCOL.md`). Rooms have a 4 letter code, topology is a star: clients only send to the host, the host sends to one or all. JSON text frames: `hi`, `hello`, `peer`, `msg`, `err`, 15 s heartbeat. No port forwarding, works behind every NAT. **Lobby dialog** (`ui/lobby.gd`, 460 px wide, red close button top right, a cog button next to it): step 1 = name + two equal buttons `Host game` / `Join`; `Join` leads to step 2 = the room code, big and centred, with `Back` / `Join`; in a room the dialog shows the code, the players and an `OK` button that **only closes the dialog** (the room is ended / left with `Close lobby` / `Leave lobby` in the main menu). **The default relay address is never shown in the UI.** The cog unfolds an optional `Relay server` field (empty = default, `Default` reset button, a `?` button); the `?` opens the **relay help** (what a relay is, how to run an own one, three buttons that copy the specification, the Node.js template and the test script to the clipboard from `res://assets/relay_help/*.txt`). The host starts the match from the main menu (`Start online game`). Seat 1 = host, then peers in joining order, the remaining seats are CPUs run by the host. Weather and random events are off online

**Sync model** (`net/netgame.gd`): the world is built from seed + layout nonce on every machine. The **host decides the rules**, every machine **simulates every shot itself** for the visuals:
- *Placement*: the author of a seat (human, or the host for a CPU) sends the result (`placed`: catapult poses / fences with layers); the others apply it in seat order.
- *Turns*: the host picks the next player and the wind and sends `turn_start`. The active player's aim is streamed (`aim`, 8 Hz) so the others see the catapult turn.
- *Shots*: a client sends `fire_req`; the host stamps it with a random seed and broadcasts `shot`; all machines reseed all gameplay RNGs (`NetGame.reseed`) and fire exactly that shot.
- *Turn actions* (`act_req` → `act`): reposition / wall are sent like shots (the host stamps a random seed and broadcasts; every machine applies them: `Turn.net_act`). A reposition carries the final pose and the list of buildings parts the driver rammed (`hits`) which the other machines repeat (`Actions.apply_hits`); a wall carries centre, yaw and whether it stacks.
- *Lobby* (`lobby`, `lobby_set`; `Menu.lobby_state`, `Menu.net_lobby_apply`, `Menu.net_lobby_set`): while a room is open the **main menu is the lobby**. Rules: **every guest may change only its own colour** (the dropdown of its seat; its name is the net name), **the host may change everybody's colour, the player count, the match options and define the CPU seats** (a seat of a connected player is a fixed human with the peer's name; free seats can only be CPUs, `Human` is disabled there; the count can not drop below the seats in use). The host sends the complete menu state (seats with peer ids, names, colours, types, count, seed, timer, catapults, palisades, terrain, arsenal preset and resolved counts) to everybody whenever it changes (checked every 0.4 s and on every roster change); a guest sends `lobby_set {color}` and the host takes it over and re-broadcasts. Guests show the host's state as a **temporary overlay** (`Settings.push_lobby` / `pop_lobby`: their own saved settings are untouched and come back when the lobby is left; nothing of it is written to disk) and the host-only controls are disabled for them. Local options (language, quality, lighting, sound, shake, vsync, fullscreen) stay the player's own.
- *Markers* (`marker`): a player's marker is sent to everybody (the host relays) so teammates see it (6.7).
- *Authority*: only the host damages / destroys catapults (`cat_dead` events), grants weapons (`grant`), eliminates players and announces the winner (`over`). Clients never decide these.
- *Turn end* (`turn_end`): snapshot of ammo, stats, catapult hp / poses and the **list of damaged structures as bitmaps of living parts**. Clients remove parts that already fell on the host and **put back** parts that fell only here (`Breakable.revive_part`, parts remember their pose `xf0`), so the villages are identical at the start of every turn even though the physics never agree bit by bit. A structure-hash is compared for diagnostics (`NetGame.hash_mismatches`). Debris, settlers, fire and craters may differ slightly between machines.
- *Leaving*: a client that disconnects is out (`drop`): its catapults vanish, its turn is skipped; a join after the start is rejected; if the host leaves the relay ends the room.
- Pause does not stop the world online; rematch / same map are not offered online.
- Seats: `PlayerData.net_peer`; `is_human()` means "a human on THIS machine", `is_remote()` a human elsewhere.

**Versions**: `Net.RELAY_PROTO` (relay envelope + URL prefix `/v1`, reported in `hello` as `relay`; a mismatch ends the connection with "relay outdated") and `Net.NET_VERSION` (game-level sync). A client introduces itself with `hello {net, ver}`; the host refuses a different `NET_VERSION` (`reject` / `netver`) and only seats accepted peers, a different game version only produces a warning. `Cfg.DEFAULT_RELAY` is the built-in relay address. The Cloudflare worker has a mock-runtime test (`relay/cloudflare/test.mjs`). `NET_VERSION` is **3** (2: turn actions, markers, team colours and absolute arsenals; 3: lobby sync) (a build with another value is refused when joining). The relay can be replaced by anybody; its spec, a runnable template and a conformance script (`relay/template/check.mjs <url>`) are part of the repository.

**Tests**: `--autotest=nethost` / `--autotest=netjoin` (see `relay/README.md`) play a whole match with several headless processes; their `NETLOG` lines must agree.

## 20. Mobile (iOS / Android)
Both use the **Mobile renderer** (`renderer/rendering_method.mobile`); the desktop default is Forward+. Landscape only (`display/window/handheld/orientation=6`). Touch: one finger = mouse (aim by dragging, release fires, tap selects), **two fingers** = pinch zoom + drag orbit (`Aiming._touch_input`; a running gesture suppresses the emulated mouse of the first finger). Export presets `iOS` (Xcode project via `IOS=1 ./export.sh`, placeholder team id) and `Android` (needs the Android SDK, see README) exist; Web is not supported because the Compatibility renderer limits shader instance uniforms (tint / glow / wet per mesh) to 4096 instances.

---

## 26. Decision log (what was decided after the first port; every point is implemented and mirrored in the sections above)
**Turn actions and teams** — two turn actions instead of a shot (6.8: reposition without distance limit that rams buildings, stone wall that works like the palisades: 6.24 m wide, 60% of a post high, only the top layer crenellated, stackable, sturdier than wood); teams by player colour with joint win, shared markers, flagpole and tinted window frames (6.9).
**Weapons** — the Flaming Barrel is no longer free (Standard preset = stone only); arsenal presets `Standard / Powerplay / Chaos / Quarry / Custom` (2.1, only Custom is saved); Buckshot renamed Flints; the **Pointy Log** starts along the flight direction and turns slowly in the plane of flight, 28% fly side-lying and roll flat, only the first ground contact (or one after a building hit) plants it → ≈ 70% stick on open ground (`--autotest=lograte`; `--autotest=logroof` throws at a house), a log that does not stick lies there for the whole match (`Debris` item `persistent`); powder ignites at once when it appears next to a fire (11.6); Black Powder Kegs launch five kegs.
**Cows and animals** — two cows per village at start, new rounded cow model (`CowMesh`), cow weapon icon = detailed head with a straight mouth; settlers with the "feather" outfit wear a beret in the team colour.
**Speech** — more lines everywhere, new `bump` category, throttled (12.8).
**UI** — flat ammo bar with reddish (weapons) / grey (actions) rims, hint strip with key-cap chips instead of grey help text, key-cap buttons `[F]`/`[X]`, one size per button class, red close button top right in every dialog, flags for the language, team colour dropdown, aligned grid / common control width in the menu, green `Start battle`, no quit button, no all-caps texts, room banner with the code, `Close lobby` / `Leave lobby` (the lobby dialog only has `OK` while in a room), single-border tooltips with short pros / cons (6.4), see-through buildings between camera and catapult (6.1), right-aligned catapult selector, subtitle without "same screen".
**Online** — default relay hidden behind a cog, relay help dialog with copy buttons for the spec / template / test script, `relay/PROTOCOL.md`, `relay/template/relay_node.mjs`, `relay/template/check.mjs`; join = name, then a separate step for the room code; `NET_VERSION` 2; messages `act_req` / `act` / `marker` (19).
**Sound** — the voices of people and animals (scream, moo, bawk, baa, neigh, quack, honk, squeak, yeet, boing) are cartoon instrument sounds instead of formant voices, much quieter (peak 0.36–0.5 instead of 0.75–0.85, −3 dB more on play) and **local**: a 3D player with unit size 5 and max distance 70 (other sounds 20 / 250), so they fade out quickly with the distance to the camera (`Sfx.CREATURES`).
**Look** — fire no longer paints blocky yellow halos: SSIL is off, only the fine glow levels are used (threshold 1.2, bicubic glow upscaling), short-lived omni lights (fire, explosions, meteor, lightning) are excluded from SDFGI (`light_bake_mode` disabled) and from the volumetric fog (`light_volumetric_fog_energy` 0), SDFGI bounce 0.2 / energy 0.85, fire lights 1.5 energy / 12 m.
**Feel** — comic words ("BONK!") are lifted up and to the side relative to the camera (more with distance), smaller, at most one per 0.6 s, so they never cover the projectile; the Boulder rolls about 70% farther (damping 0.03 / 0.06, a 5 m/s² roll assist for 6 s after the first impact, rolls up to 16 s; `--autotest=boulderroll` measures it); after a Flints shot the camera waits ~0.9 s for the pieces and then shows the village nearest to where most of them landed (`Projectile.pellet_impacts`); settlers and animals move smoothly at any frame rate (the 10 Hz behaviour only sets a velocity and a facing, position, facing and limb animation advance every rendered frame; `--autotest=smooth` checks the per-frame steps).
**Rendering** — Medium quality uses a 2048 shadow atlas (the 1024 one produced a checkerboard / stripe pattern on terrain and roofs).
**Build** — patch number in `VERSION` increases with every export; relay help files are bundled; `relay/*` and `*.md` are not exported.
**Tests / autotest scenarios added** — `actions`, `teams`, `ram`, `logroof`, `lograte` (80 logs), `powderfire`, `cows`, `menu_arsenal` (menu, lobby steps, arsenals, relay help files) next to the existing ones; `tests/` count 3445+ assertions.

**1.10.17** — OpenGL renderer: toon shader without instance uniforms (`Toon.use_instance_params`, `set_tint` / `set_glow` / `set_wet`), VSync default off, optional debug export.
**1.10.16** — host-only match options in the online lobby (weather, events, crates also synced / restored), owner name label above the village flag (`Flag.add_owner_name`).
**1.10.15** — online room stays open after a match (`NetGame.reset(keep_room)`, results -> main menu returns to the lobby), Linux defaults to the Compatibility renderer (`rendering_method.linuxbsd`).
**1.10.14** — team gifts: `Turn.gifts` (ammo id -> giver id, this turn only), `Turn.set_gift`, messages `offer` (client -> host) / `gift` (host -> all), offer strip + gift ribbon in the HUD; the gift is used before the shooter's own stock and costs the giver one unit when fired. Online only (in hot-seat the viewer is always the player on turn).
**1.10.13** — joint tracking (`PhysWorld.new_joint` / `free_joint` / `attach_joint`, all freed before bodies: fixes a crash on restart), roof sag rule in `Breakable.support_check` (`_roof_sag`), chain shot radius 0.56 / mass 160, crates become physics props after landing, banner position constant, narrower bottom-right buttons, glow disabled.
**1.10.9** — unlock rules in tiers per game mode (core / power / chaos / quarry), team rules, fires counted per turn, meteor only from the supply crate (parachute, 1-2 per match, after 5 shots each), small boulder / log crates near the villages (option to switch crates off, +30 % / +50 % in Powerplay / Chaos), fanfare and epic sound for the meteor crate, rules dialog and tooltip hints; weapon unlocks reworked (see 6.4b): powder keg only for losing your own blacksmith, black powder only at the last catapult, barrels earn nothing, one-shot demolition pays no keg.
**1.10.9** — new game icon, GitHub Actions build (`.github/workflows/build.yml`, `MM_BUILD_NUMBER` sets the patch number; macOS unsigned), defaults 3 catapults / timer off, crossed-sword enemy markers on the 3D arrows, rolling rocks only bump catapults, turn no longer hangs when the active catapult is lost (re-select or end turn / eliminate / game over), gentler camera shake.
**1.10.8** — "Reset options" button in the menu (first-start defaults for the options panel), round timer default 30 s, a loud red 5-4-3-2-1 countdown with ticks and a flashing ring for the last 5 seconds of a turn, automated test runs no longer overwrite the saved settings.
**1.10.7** — Online lobby sync: guests change only their own colour, the host everybody's and defines bots, all menu changes reach everybody; the V overview works while others are playing.
**1.10.6** — Calmer, friendlier sounds for people and animals (cartoon instruments, quieter, short range); fewer blocky halos around fire.
**1.10.5** — 3D direction arrows at the own village while placing, builders stand right at the wall, bullet time only for direct catapult hits, Boulder 15% bigger / heavier, more Boulders and Logs in the Chaos / Quarry / Powerplay presets, trees shot down near the own camp earn a log.
**1.10.4** — Settlers rebuild damaged houses slowly with a hammer (16.4); the last powder keg bursts over 30% of the old radius with 3× the powder and visibly flies (6.4 table / 11.6); the export writes the version into the presets (Finder shows it); `CHANGELOG.md` added.
**1.10.3** — Direction markers while placing catapults (2.3), comic words moved off the action, Boulder rolls ~70% farther, Flints camera shows the hit village, smooth settler / animal movement at any FPS.
