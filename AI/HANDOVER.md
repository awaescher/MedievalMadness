# Handover guide for AI agents (Medieval Madness)

This is a long, deliberately explicit guide. It is written for an AI coding agent that has **never seen this repository** and may be
less capable than the one that wrote it. Read it once from top to bottom before a bigger change; use the table of contents later.

The short version lives in [../AGENTS.md](../AGENTS.md). The player-facing description is [../README.md](../README.md). The full
specification (rules, numbers, file contracts) is [../SPEC.md](../SPEC.md).

## Table of contents

1. How to use this guide and how to think
2. The project in ten minutes
3. Daily commands (build, test, run)
4. The golden rules, with the reasons
5. Checklists for the common tasks
6. Subsystem notes (what to know before you touch it)
7. Release, CI and versions
8. What was done recently
9. Known limitations and ideas
10. Pitfall diary (mistakes that already happened)
11. Working with the owner
12. Glossary

---

## 1. How to use this guide and how to think

**Mindset in five sentences.**

1. The game is big (about 110 scripts) but very regular. Almost every feature touches the same few places; the checklists in section 5
   list them. Follow a checklist instead of inventing a route.
2. Before you change anything, find the existing code that does something similar and copy its shape (naming, comments, typing).
3. Prefer the smallest change that solves the problem. Do not refactor things you were not asked to touch.
4. Verify. "It compiles" is not "it works". Run the tests, run the right autotest scenario, look at a screenshot when the change is visual.
5. Be honest in your report: say exactly what you verified and what you could not (for example "headless tests only, I did not look at the running game").

**When something is unclear**, search `SPEC.md` first (it is long but searchable: `grep -n "keyword" SPEC.md`), then the code. If a decision
is really the owner's to make (a rule, a number, how something should feel), ask one precise question with a recommendation instead of
guessing. If it is a technical detail, decide and mention it.

**Read before you write.** Open the file you are going to edit, and one neighbouring file of the same kind. GDScript here is typed and
has a consistent style; a patch that looks foreign is a worse patch.

---

## 2. The project in ten minutes

### 2.1 What it is

A turn-based, physics-heavy 3D artillery game for 2-8 players (humans and CPU bots), hot-seat on one screen or online. Every player owns
a medieval village with up to five catapults and shoots at the others, one shot per turn. Everything is a rigid body and destructible,
fire spreads, water extinguishes, settlers become ragdolls. The last player (or team) with a living catapult wins.

Technology: **Godot 4.4+ (tested with 4.7.2), GDScript only, Jolt Physics.** No C#, no GDExtension, no addons. There are **no image, model,
font or audio files**: meshes, textures, shaders and sounds are generated in code at start-up. (Exception: a few CC0 material textures
under `assets/textures/` used by the "Natural" graphics style.)

### 2.2 Folder map (what lives where)

```
scenes/main.tscn        one scene with a root Node; everything is created in code by scripts/main.gd
scripts/main.gd         the application: builds UI, starts / ends matches, wires signals (big file, central place)
scripts/autoload/       Cfg (constants), Events (signal bus), Settings (saved options), I18n, Game (global match state),
                        Net (networking), Sfx (synthesised sound)
scripts/core/           Rng, noise, util, ballistics, ammo definitions, arsenal presets, synth kit, player data
scripts/render/         toon / outline / sky / water shaders, quality tiers, graphics styles, camera rig, procedural meshes
scripts/physics/        PhysicsServer3D wrapper (world.gd), Part / Structure, breakable.gd (support + break logic), debris, materials
scripts/world/          map generation, terrain (chunked heightfield), village generator, GameWorld (owns one match's 3D content)
scripts/buildings/      building blueprints built from a small kit of wall / roof helpers
scripts/props/          barrels, crates, carts, lanterns ...
scripts/entities/       catapult, projectile (all ammo), meteor, drill bomb, settlers (ragdolls), animals, brigade (bucket line)
scripts/systems/        damage, fire, explosion, water, weather, random events, landslide, powder, turn manager, scoring, unlocks, supply crates
scripts/fx/             pooled particles, comic text, speech bubbles, trails, flags
scripts/ai/             CPU bots (Peasant / Squire / Knight / King)
scripts/net/            online game sync (host-authoritative)
scripts/ui/             parchment theme, menu, lobby, HUD, aiming, placement, results, pause, reward popup
scripts/lang/           en.gd and de.gd (all visible texts)
scripts/autotest.gd     in-game test scenarios
tests/                  headless logic tests (run_tests.gd) and probes
tools/                  helper scripts (relay server, release helper)
relay/                  the online relay (Cloudflare worker + a Godot fallback), has its own README / PROTOCOL.md
docs/                   README images (docs/.gdignore keeps Godot from importing them)
.github/workflows/      build.yml: CI that builds all platforms and creates GitHub releases
```

`*.gd.uid` files next to scripts are Godot's stable ids. **Keep them in the repository** (they are tracked) and commit the `.uid`
of every new script together with the script.

### 2.3 The mental model of a match

- `Main` (scripts/main.gd) owns the window, the UI layers and one `GameWorld` per match. A new match = a new `GameWorld`; statics
  of the systems are reset in `GameWorld.reset_systems()`.
- `Game` (autoload) holds the match options (`Game.palisades_per_player`, `Game.wind_level`, `Game.auto_place_on` ...), the player list and
  the state machine `MENU -> GENERATING -> PLACEMENT -> BATTLE -> GAME_OVER`.
- `Turn` (scripts/systems/turn.gd) runs the turn phases: `TURN_START`, `AIMING`, `FLIGHT`, `AFTERMATH`, `TURN_END`. Between turns the world
  keeps simulating.
- `GameWorld.physics_tick(dt, cam_pos)` runs at a fixed 60 Hz and calls the systems in a fixed order (Breakable, Debris, Projectile,
  Explosion, Landslide, Powder, Fire, WaterSys ...). Look at it to learn the order; do not reorder casually.
- Most systems are **static classes** (`Fire`, `Explosion`, `WaterSys`, `Unlocks` ...) with `static var` state and `static func tick()`.
  Their state is cleared in their `reset()`; when you add static state, add it to `reset()` or it leaks into the next match.
- The **signal bus** is `Events` (autoload). UI and systems talk through it (`Events.toast`, `Events.banner`, `Events.reward` ...).
- Physics objects are created directly on `PhysicsServer3D` through the wrapper `PhysWorld` (scripts/physics/world.gd), not as nodes.
- The terrain is a heightfield (`MapData.heights`) rendered in chunks (`Terrain`) with a `HeightMapShape3D` collider.

### 2.4 Platforms and renderers

- Windows and macOS use **Forward+**. **Linux defaults to the Compatibility (OpenGL) renderer** (`rendering_method.linuxbsd` in
  `project.godot`), because a user saw garbage with Vulkan; Vulkan is optional with `--rendering-method forward_plus`.
  Phones would use Mobile; **phones are not an official target** (a rough, untested touch layer exists in `ui/aiming.gd`) and **web is
  impossible** (browsers force Compatibility, which breaks the per-instance colour system, see 6.9).
- Because of that the toon shader has a constant-value variant for OpenGL (`Toon.use_instance_params`). Anything that sets per-instance
  shader parameters (`set_tint`, `set_glow`, `set_wet`) must go through `Toon`.

---

## 3. Daily commands

Run everything from the repository root. `godot` must be on the PATH (on macOS: `brew install --cask godot`).

```bash
# 1. logic tests (no scene, about 40 s, ~3900 assertions) - run after every change
godot --headless --path . --script res://tests/run_tests.gd

# 2. in-scene tests (physics, fire, ragdolls, powder chains)
godot --headless --path . -- --autotest=units

# 3. a whole CPU game (4 bots), useful for crashes / hangs
godot --path . -- --autotest=cpugame --seed=x --wall=300

# 4. build a binary for all platforms (also raises the patch number in VERSION)
./export.sh

# 5. refresh Godot's class cache after you ADD a script with `class_name` (or rename one)
godot --headless --import --path .
```

**Important details**

- After adding a `class_name` script, run command 5 once. Without it Godot reports `Could not find type "X" in the current scope`.
- A parse check without running anything: `godot --headless --quit --path . 2>&1 | grep -iE "parse|SCRIPT ERROR"`.
- Exit noise like "resources still in use at exit" or "RID allocations ... leaked at exit" after autotests is old and harmless. A line
  `ERROR: Parameter "t" is null.` appears in headless cpugame runs and is also old.
- **Headless runs have a dummy renderer: no screenshots.** For pictures run the autotest *without* `--headless`; it opens a window and
  writes `user://shot_<name>.png` (macOS: `~/Library/Application Support/Godot/app_userdata/Medieval Madness/`). Look at them with the
  image viewer tool of your environment - this is how UI changes are verified.
- Autotest scenarios are `match` branches in `scripts/autotest.gd` (list: `grep -n '^\t\t"[a-z_0-9]*":$' scripts/autotest.gd`). Extra
  arguments are read with `uarg("name", "default")`, passed as `-- --autotest=cpugame --seed=x --wall=300`.
- Autotests never overwrite the player's saved settings (`Settings._is_test_run()`).
- `export.sh` needs the Godot export templates for the same version (4.7.2) installed. On macOS they live in
  `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`.

**Shell environment tips (macOS, zsh)**

- There is no `timeout` command on macOS. Do not pipe long runs through it; just run them (they end by themselves).
- zsh expands unquoted globs: write `grep -rn "x" scripts --include="*.gd"` (quotes), otherwise "no matches found".
- zsh does not word-split a variable in a `for` list or `set -- $var` the way bash does; use explicit values or call `bash -c`.
- The default file system is **case-insensitive**: `release_body.md` and `Release_Body.md` would be the same file on a Mac and different on the
  Linux CI. Never create two names that differ only in case.
- `sips` converts / resizes images (`sips -Z 1000 in.png --out out.png`, `sips -s format jpeg -s formatOptions 74 in.png --out out.jpg`).
- Python helpers that need packages (Pillow) go into a throw-away virtual environment outside the repository
  (`python3 -m venv /tmp/venv && /tmp/venv/bin/pip install pillow`), not into the system Python and not into the repo.

---

## 4. The golden rules, with the reasons

1. **Run the tests before you call something done.** The logic tests are fast and catch most breakage (i18n key mismatches, map
   generation, ballistics, building generation). If you only ran some of them, say which.
2. **Update `SPEC.md` and `CHANGELOG.md` in the same change.** SPEC is how the next agent understands the rules; stale documentation
   caused real drift in the past (the renderer section said "Mobile" while the project used Forward+ / Compatibility). CHANGELOG gets one
   short, player-facing line under `## Unreleased` (see section 7).
3. **Both languages, always.** Texts are keys in `scripts/lang/en.gd` and `de.gd`. The two files must have identical key sets
   (`tests/test_i18n.gd` fails otherwise). Never hard-code a visible string. Names of players and the language names are the only exceptions.
4. **Online correctness.** The host decides gameplay; guests only display. Consequences: gameplay randomness uses `Game.rng_battle`
   (a seeded `Rng`), never `randf()` / `randi()`; every match option must be sent in the lobby state and the start message; effects that
   only look nice (particles, popups) may use anything. If a rule grants something, only the host evaluates it (`Unlocks.grant` returns on
   clients unless the host announced it).
5. **Everything on the terrain must handle terrain changes.** Craters, landslides and the drill bomb change the heightfield at any time.
   Details in 6.2. Forgetting this produced floating settlers, flames, puddles, rocks and half a dozen other bugs.
6. **Typed GDScript, no surprises.** Annotate types of variables and functions. Many files start with `@warning_ignore_start("unsafe_*")`
   because they cast out of dictionaries; follow the file you are in. Do not allocate arrays / dictionaries / vectors every frame in hot paths
   (physics sync, fire tick, part release, particles).
7. **Bounded work per frame.** Loops over all structures / parts / bodies must be budgeted or event-driven (see how `Fire._fire_tick` limits to
   200 parts per tick, how `Breakable` sweeps run once per second, how `Quality.body_cap` limits bodies).
8. **UI must work in small windows.** The game is played in windows from about 1024 x 600 up. Never assume 1600 x 900. Test visual changes
   with a screenshot and, if layout is involved, with a small window (see 6.7).
9. **Keep the look consistent.** Parchment panels (`UITheme`), comic font for banners (`ComicText.comic_font()`), weapon icons drawn with
   primitives in `Hud.AmmoSlot._draw_icon`. Do not add image files.
10. **Do not break the macOS / Windows / Linux builds.** After a change run `./export.sh` (it builds all three). If it fails, fix it before
    anything else.
11. **Do not do destructive things unasked**: no deleting data, no force-pushing, no rewriting shared history, no publishing, unless the owner
    explicitly says so. Push only when asked.
12. **Report honestly.** If a test fails, show the output. If you skipped something, say so. If you are not sure whether something works in
    the running game, say that instead of "done".

---

## 5. Checklists for the common tasks

### 5.1 Add or change a **match option** (a setting the host chooses, e.g. "Auto-place catapults & palisades")

The option has to exist in five worlds: saved settings, the running match, the online start message, the lobby display for guests, and the
menu UI. Missing one gives a bug that only shows online. The reference implementation is `auto_place` / `auto_place_on`; copy it:

1. `scripts/autoload/settings.gd`: field with default; load (`cf.get_value`) and save (`cf.set_value`); `_snapshot()` and `_apply_snapshot()`
   (guest lobby overlay; use `d.get("key", default)` for new keys); `reset_options()` (only inside `if not local_only`).
2. `scripts/autoload/game.gd`: runtime field (`Game.auto_place_on`).
3. `scripts/main.gd` `_start_game`: copy `Settings.x` into `Game.x` for the local game **and** read it from `net_cfg` in the online branch.
4. `scripts/net/netgame.gd`: add the key to the start message dictionary.
5. `scripts/ui/menu.gd`: `lobby_state()` (host sends it), `net_lobby_apply()` (guest applies it), and the UI row in `_options_panel()` with
   `_host_only(control)` so guests see it disabled.
6. `scripts/lang/en.gd` + `de.gd`: the label under `"menu"`.
7. Use it where the behaviour happens (e.g. `Placement.start`).
8. SPEC.md (options section / the system that uses it) and CHANGELOG.md.

### 5.2 Add a **weapon (ammo)**

Ammo definitions are in `scripts/core/ammo_def.gd`; their behaviour in `scripts/entities/projectile.gd` (a big `match ammo.id`); how they are earned in
`scripts/systems/unlocks.gd` (`RULES` table, the single source) ; the icon in `Hud.AmmoSlot._draw_icon`; the sound in `core/sound_recipes.gd`;
the starting arsenal presets in `core/arsenal.gd`; tooltips and names in the language files (`ammo.<id>`, `ammo_tip.<id>.*`,
`unlock.*`, `unlock_how.*`); bots in `scripts/ai/`; SPEC table in section 6.4. The drill bomb (`entities/drillbomb.gd`) is a recent, complete
example of a weapon with its own simulation.

### 5.3 Add **visible text**

Add the key to **both** `en.gd` and `de.gd`, use `I18n.t("group.key", {"param": value})` (list texts: `I18n.pick` / `I18n.tr_list`).
Run the logic tests (i18n test). If a label is built once at start-up it will not follow a language switch: either rebuild on
`Events.language_changed` (see `hud.gd`, `pause.gd`) or set the text again when it is shown (the loading title bug).

### 5.4 Add something that **sits on or follows the terrain**

See 6.2. Short version: do not store a height once. Either read `Terrain.h(x, z)` every frame (settlers, animals), or register for the
terrain hooks (`Terrain.decor_hook`, `Terrain.ground_hook`, `Terrain.wake_hook`), or re-check on `Terrain.current.change_stamp`.

### 5.5 Add a **new script with `class_name`**

Create the script, add `class_name X`, run `godot --headless --import --path .`, commit the `.uid` file. Static classes extend `RefCounted`.

### 5.6 Add a **gameplay rule that grants / punishes**

Put the rule in the system that owns the topic (rewards in `Unlocks`, scoring in `Scoring`), use `Game.rng_battle` for randomness, make it
host-only, add texts (5.3), document it in SPEC and write a player-facing line in CHANGELOG.

### 5.7 Add or change **UI**

Use `UITheme` helpers (`label`, `rich_label`, `button`, `box`, `option_button`); colours as in the existing code; keep the parchment look.
Player names should be shown in the player's colour wherever they are mentioned (`UITheme.tint_names` / `rich_label`). Then take a screenshot with
a small autotest scenario (copy `hud`) and look at it.

---

## 6. Subsystem notes

### 6.1 Physics and destruction (`scripts/physics/`)

- A **structure** (a house, a fence) is a list of **parts** (single planks, beams, stones, shingles ...). Each part has a material
  (`materials.gd`: density, friction, break force, flammability, hit points per volume).
- A structure **sleeps** as one merged static mesh with one compound collider. When something hits it, `Breakable.awaken` turns the parts
  into individual bodies that stay *frozen* until released.
- **Links**: parts that touch are logically glued (no physics joints). `Breakable.support_check` walks the links from "anchored" parts
  (foundations, parts touching terrain). Everything not reachable is released and falls. A part may hang at most 3 links off a supported
  one (`CANTILEVER`). A structure whose ground gave way is `undermined` and uses a stricter rule (no cantilevers).
- A part breaks when an impact impulse exceeds `breakForce x size factor`; damage goes into part hit points; destroyed parts splinter into
  debris (`debris.gd`, capped; oldest sleeping debris fades first).
- Windmill sails and cart wheels use real hinge joints; ragdolls use cone-twist joints. Everything else uses the link logic.
- `PhysWorld` wraps the server: `add_body`, `remove_body`, `apply_impulse`, `wake`, `wake_in_box`, `raycast`, `overlap_sphere` ...
  Use it, do not call the server directly.
- Fast-forward raises the physics tick (180 Hz x time scale 3) instead of stretching steps, because long steps let bodies tunnel through the
  terrain.

### 6.2 Terrain changes (the most common source of bugs)

`Terrain` (scripts/world/terrain.gd) owns the heightfield. Systems that change it: explosions (`crater`), `dig`, `furrow`, `Landslide`,
`DrillBomb`. After a change `Terrain.mark_dirty(...)` is called, and every 0.5 s `flush()` rebuilds the chunk meshes and the collider, then
calls the hooks:

| Hook / mechanism | Who uses it | What it does |
|---|---|---|
| `Terrain.ground_hook` -> `Breakable.ground_changed(box)` | structures | parts lose their anchor / are released when the ground sank (gap > 0.7 m), structure becomes `undermined` |
| `Breakable` sweep (6 s after a change) | structures, props | wakes sleeping loose parts hovering over a hole, drops stacked posts |
| `Terrain.wake_hook` -> `PhysWorld.wake_in_box` | all rigid bodies | wakes sleeping bodies so they fall into craters |
| `Terrain.decor_hook` -> `GameWorld._realign_decor` | rocks, bushes, flowers (MultiMesh) | re-seats instances on the new ground, hides those under water |
| every frame `Terrain.h()` | settlers, animals | `position.y` follows the ground; animals also lean with the slope |
| `Fire` tick | ground fires | `g.pos.y` follows the soil |
| `WaterSys._ground_changed` | puddles | a puddle vanishes when its centre / edge heights change by more than 0.25 m; puddles are only created on flat ground |
| `Flag.mast` | flags | a flag hangs on the nearest live part of its building |

Known gap: the **rock colliders** (static compound body) are created once and are *not* moved when the ground changes (the visual is). Props and
catapults are physics bodies and fall by themselves.

When you add something new that stands on the ground, ask: "what happens to it when a crater appears under it?" and wire one of the above.

### 6.3 Fire, water, powder (`scripts/systems/fire.gd`, `water_sys.gd`, `powder.gd`, `explosion.gd`)

- Fire works per part: `ignite(part, amount)` raises `burning`; at 1.0 the part is `on_fire`, gets a pooled flame (`Fx.acquire_flame`), damages itself,
  spreads to neighbours (wind and upward boost), and burns out after `BURN_TIME` (charred parts cannot ignite again). Wet parts and rain stop
  it. Ground fires are small timed flames.
- **Every flame that is acquired must be released.** Flames are pooled (`Fx.Flame`). Parts release theirs in `_stop_fire`; ground fires in
  `_end_ground_fire`; settlers / animals / catapults hold their own `_flame` and must release it when they die, ragdoll, or are extinguished.
  A leaked flame stays in the world forever (this happened with burning settlers that died).
- Water: bodies below the water level get buoyancy; releases (barrels, tower, well) make droplets and a flat puddle disc that makes parts wet.
- Explosions: impulse with falloff, damage, crater, optional fire, chain triggers for powder kegs, and a pressure wave (expanding front) for big blasts.

### 6.4 Unlocks and rewards (`scripts/systems/unlocks.gd`, `ui/reward_popup.gd`)

- Stone is unlimited; everything else is earned. `Unlocks.RULES` maps weapon -> `[tier, key]`; tiers: 0 core (always), 1 power, 2 chaos, 3 quarry.
  `Unlocks.tier_on(n)` tells which tiers are active in the current mode (Standard / Powerplay / Chaos / Quarry / Custom).
- `Unlocks.grant(player_id, ammo_id, n, reason_key, pos)` is the only way to give ammo. It adds the ammo, writes a kill-feed line, toasts, plays a
  sound for humans, and emits `Events.reward`, which `RewardPopup` shows as a floating icon (icon, `+n`, player name in colour, weapon name).
  `pos` is where it happened; if you do not pass one it uses `Unlocks.hint_pos` (last part break / fire / explosion, set via `Unlocks.set_hint`),
  else the village. The host sends `pos` to clients with the grant message.
- Chaos cows: your own cow dying gives 2 cows (other modes 1); any other animal of your camp dying gives 1 cow in chaos; nothing else gives cows.
  The chaos "own goal" keg is only for real buildings (`_is_fence_or_prop`).

### 6.5 Turn flow, scoring, bots

`Turn` runs the phases; `Scoring` tracks points and titles; `CpuAI` (scripts/ai/) solves aim with a ballistic sampler (`CpuAI.solve_sample`) and
differs per level in accuracy and weapon choice. Autotests drive human players through `Turn.select_catapult`, `Turn.set_aim`, `Turn.fire`.

### 6.6 Online play (`scripts/net/netgame.gd`, `scripts/autoload/net.gd`, `relay/`)

Up to 8 players through a relay (a Cloudflare worker, or any machine running the Godot relay). The world is built from seed + layout nonce on
every machine; the host decides rules and sends messages for things that must agree (shots, grants, crates, options). Version gate:
`Cfg.game_version()` must match (`net.netver` error). Relay protocol: `relay/PROTOCOL.md`. Guest menus show the host's options as a temporary overlay
(`Settings.push_lobby` / `pop_lobby`); the guest's own saved settings come back when it leaves.

### 6.7 UI, theme, banners, small windows (`scripts/ui/`)

- `UITheme` (theme.gd): `label`, `rich_label` (BBCode, used for coloured names), `set_rich`, `name_color` (lightens very dark player colours),
  `tint_names(text)` (wraps every player name in a colour tag), `button`, `option_button`, `box` (stylebox).
- `Hud` (hud.gd) is big: player list, turn banner, wind widget, ammo bar (`AmmoSlot` draws the weapon icons with primitives; `icon_only` for
  menus), catapult selector (`CatSelect`, with `CatGlyph` as the little catapult icon), aim box (scales with the window), kill feed, toasts, announcer
  banner.
- **Announcer banner**: `_fit_banner` picks the largest font (44 down to 22) that keeps the text on one line within 88 % of the window width and sets an
  exact size. Do not use `fit_content = true` on a wrapped `RichTextLabel` inside a container: it computes its height from an unwrapped text and can
  cover half the screen (this happened).
- The menu's options column is a `ScrollContainer` so the Start / Online buttons never slip off a low window.
- Reward popups (`RewardPopup`) project a world position to the screen every frame (`CameraRig.project`) and clamp it inside the window.
- Check small windows by resizing in an autotest or by launching with a smaller window size setting; look for clipped text and overlaps.

### 6.8 Rendering and graphics styles (`scripts/render/`)

Quality tiers (`quality.gd`: low / medium / high / ultra) cap bodies, particles, shadows, lights. Lighting modes (basic / enhanced / ray-marched GI)
and **graphics styles** (`gfx_style.gd`: Toon, Natural, Pop art, Watercolor, Retro, Neon, Noir) are applied live; one global shader parameter
`gfx_style` switches the toon, outline, water and sky shaders; a full-screen post shader adds grain / pixelation / CRT / halftone. "Natural"
uses CC0 textures projected triplanar (`gfx_textures.gd`).

### 6.9 Why Compatibility is special

The OpenGL renderer has only 4096 slots for per-instance shader values and the toon shader used three per object, so thousands of objects got
garbage colours. The fix: `Toon.use_instance_params` is false there and tint / glow / wet are cached materials or skipped. If you add a new
per-instance shader parameter, add a Compatibility path too.

### 6.10 Audio

All sound is synthesised at start-up (`core/synth.gd`, `core/sound_recipes.gd`, `autoload/sfx.gd`). There are no audio files. New sounds are new
recipes.

### 6.11 Settings

`user://settings.cfg` (macOS: `~/Library/Application Support/Godot/app_userdata/Medieval Madness/settings.cfg`). Loaded by `Settings.load_settings()` (from `_ready`), saved
by `save_settings()`. Autotests do not save. "Reset options" (`reset_options`) restores first-start defaults for the options panel.

---

## 7. Release, CI and versions

- **VERSION** holds `major.minor.patch`. `./export.sh` raises the patch by one on every local build and writes the version into
  `export_presets.cfg` (macOS bundle version, Windows file properties ...). The version is shown in the main menu and sent when joining online.
- **CI** (`.github/workflows/build.yml`): on every push to `main` (and on `v*` tags and pull requests) it installs Godot 4.7.2 + templates,
  runs `./export.sh`, packs one ZIP per platform (`MedievalMadness-<version>-Windows.zip` / `-macOS.zip` / `-Linux.zip`), uploads them as an
  artifact, and (for `main` and tags) creates a GitHub release `v<major.minor.patch>`. **CI does not run the tests**; you must.
- **Patch number in CI** = GitHub run number minus the number in the file `BUILD_BASE`. When the minor (or major) version is raised, set `VERSION`
  and set `BUILD_BASE` to the run number of the last run, so the new series starts at `.1`.
- **Release text** comes from `CHANGELOG.md`: the CI takes the `## Unreleased` section and, if a previous release exists, only the lines that
  are new compared to that release's own `## Unreleased`. While `## Unreleased` is empty (first build of a new minor), it uses
  `## <major>.<minor>.0`. When you raise the minor version: move the content of `## Unreleased` into a new `## X.Y.0` section.
- Write release notes **for players**, one line per change, bold lead phrase, no code names, no file names. Technical details belong in SPEC.md.
- **macOS builds are ad-hoc signed** (`codesign/codesign=1`, Godot's built-in signer, works in the Linux CI). Without a paid Apple developer account
  a downloaded app still triggers Gatekeeper once (README explains the manual steps). Real notarisation is not set up.
- Do not create or delete GitHub releases or tags unless the owner asks.

---

## 8. What was done recently (digest)

This is the history of the last working days, so you understand why things look the way they do. Newest ideas last.

- **Graphics styles** (Toon default, Natural, Pop art, Watercolor, Retro, Neon, Noir) with one global shader parameter, a post shader and CC0 textures
  for Natural; new app icon; cow spots lie flat on the body; results screen redesign (winner banner, player cards, medals, title chips); aim
  elevation limited to 15-60 degrees.
- **Flags fall with their mast**, flames no longer hover in mid-air, supply crates look different (bomb painted on every side), late in a match
  more small crates hold powder kegs / fire barrels. **Ground loss**: buildings and posts no longer hang in the air after landslides or craters
  (footprint-based anchor test, `undermined` structures, a 6 s sweep).
- **Wind option** (none / light / strong, host only online) with re-tuned strengths.
- **Drill bomb** weapon (drills to sea level, explodes underground, the ground caves in), earned by wrecking an enemy church or watchtower; starting
  arsenal dialog got real weapon icons and scrolls.
- **Release pipeline**: CI releases every push, one ZIP per platform, macOS ad-hoc signed, patch numbers relative to `BUILD_BASE`, short
  player-facing `CHANGELOG.md` (the GitHub release text is generated from it).
- **Everything follows the ground**: rocks / bushes / flowers lean with the slope and are re-seated after terrain changes; animals and settlers
  follow the soil every frame (also when standing); puddles vanish when the ground changes and are never created on slopes.
- **Leaked flames fixed**: burning settlers / animals that died kept a flame in the world.
- **Match option "Auto-place catapults & palisades"** (default off, host only).
- **Rewards you can see**: `RewardPopup`; the old big "unlocked" banner was removed.
- **Names in the player's colour** everywhere (`UITheme.tint_names`).
- **Chaos balance**: cows only from two sources; own-goal keg only for whole buildings.
- **HUD polish**: proper catapult icons (`CatGlyph`), selector directly above Fast-forward, autosizing aim box, an announcer banner that fits the window
  (a first version using `fit_content` was far too big and was fixed), scrollable menu options, translated loading screen.
- **Docs**: README rewritten (run instructions for all platforms, "Physics is the game" with GIF, new screenshot, outdated sections removed),
  renderer facts corrected (Forward+ / Compatibility on Linux / Mobile on phones), `AGENTS.md`, this guide, and a short, player-facing 1.11.0 section in `CHANGELOG.md` (the older technical detail stays in the git history).

---

## 9. Known limitations and ideas

**Known limitations**

- Rock colliders do not follow terrain changes (visual does). A prop that fell asleep less than about 0.6 m above ground that then sank may
  hover until something wakes it.
- The Linux build was not tested on real Linux hardware by the authors of these notes; the Compatibility path is verified only on macOS.
- The touch layer for phones is untested; phones and web are not supported.
- CI builds but does not run tests.
- The macOS app is not notarised.
- Cow-related rules in chaos can still produce many cows when one blast kills many animals (no cap per shot by design, see the owner's wording).

**Ideas (not decided - ask before building)**

- A renderer switch (OpenGL / Vulkan) in the Linux launcher or the options menu (needs a restart) and a clear start-up message when a renderer
  fails.
- Run the logic tests in CI (headless Godot is already installed there) and fail the build when they fail.
- A cap for cows per shot; more rules per game mode; more weapons in the same style as the drill bomb.
- Move rock colliders with the terrain (rebuild the static body for affected rocks).
- A spectator / replay view, a short tutorial, colour-blind-friendly team markers, more languages (add a `scripts/lang/xx.gd`, load it in `I18n` - today `EN` and `DE` are preloaded constants and `set_lang` only accepts `en` / `de` - and add a flag button in the menu).
- Notarised macOS builds, a Windows installer.
- Better CPU bots (cover-aware targeting, using terrain deformation weapons deliberately).

---

## 10. Pitfall diary (mistakes that already happened - do not repeat)

1. **Static state not reset**: a new system with `static var` lists forgot `reset()`, and the next match started with leftovers. Always reset.
2. **Pooled objects not released**: flames (see 6.3). When you acquire from a pool, find the line that releases and make sure every exit path hits it.
3. **Heights stored once**: puddles, rocks, flowers, settlers kept their start height and hovered after craters (see 6.2).
4. **Labels built once**: the loading screen title stayed German after a language switch. Texts built in a constructor need a refresh path.
5. **`fit_content` RichTextLabel in a container** produced a gigantic banner. Compute sizes explicitly (see 6.7).
6. **Claiming facts without checking**: an answer said the Linux build needs Vulkan; the project actually forces OpenGL on Linux. Read the config (`project.godot`)
   before you state how something works. Same for "there is no touch support": there is a touch layer.
7. **Case-insensitive file names**: a CI output file named `release_notes.md` overwrote a document called `RELEASE_NOTES.md` on a Mac during a local test (that document no longer exists). Use different names, not different cases.
8. **New `class_name` without refreshing the class cache** -> parse errors that look like missing code. Run the import command.
9. **Per-instance shader parameters** break on the OpenGL renderer (section 6.9).
10. **Hard-coded German or English strings** slip in when a UI is quick to write. Search for string literals in the UI code you wrote.
11. **Changing a match option in only some of the five places** (5.1) works in hot-seat and breaks online.
12. **Trusting a green headless run for visual work**: headless has no renderer. Look at a screenshot.
13. **Overlapping systems**: the support check, the ground-loss sweep and the wake hook interact. If you change one, run `--autotest=units` and
    `--autotest=hanging`.

---

## 11. Working with the owner

- The owner writes in German and short messages; answers and documents in the repository are English unless asked otherwise. Reply in the
  language of the question.
- The owner reviews visually and will tell you when something looks wrong ("zu groß", "ruckelt"). When you have a screenshot or GIF, check it
  yourself first and describe what you see, including weaknesses.
- Keep answers short and concrete: what changed, what you verified, what is open. Give a recommendation when you ask a question.
- Update the documents (SPEC, CHANGELOG) yourself; do not leave it for later.
- Commit messages: short, imperative, one line plus an optional short body. Do not add co-author trailers. Commit when a change is finished and
  verified; push only when asked. Never run history-changing or destructive git commands unless the owner explicitly asks for that exact action.
- If a tool or permission is denied, do not look for a workaround that achieves the same thing; report what you wanted to do and why, and let
  the owner decide.
- Never put secrets or personal data into the repository. Do not commit build output (`build/` is ignored) or large binaries without a reason
  (the README GIF and JPEG are the exceptions and are size-limited on purpose).

---

## 12. Glossary

- **Part**: one rigid piece of a building (plank, stone, shingle ...). **Structure**: a building made of parts. **Dormant / awake**: asleep as one static block / individually simulated.
- **Anchor**: a part that rests on the ground and holds the structure. **Support check**: the walk over links that releases unsupported parts.
- **Link**: the logical glue between touching parts. **Cantilever**: how many links a part may hang sideways off a supported part.
- **Ammo / weapon**: what a catapult fires (stone, boulder, drill bomb ...). **Unlock / reward**: earning a weapon.
- **Tier / rule level**: which unlock rules are active (core, power, chaos, quarry), decided by the game mode.
- **Host / guest**: online, the host runs the rules, guests display.
- **Decor**: trees, rocks, bushes and flowers scattered over the map.
- **Autotest**: an in-game scenario run with `-- --autotest=<name>`.
- **Quality tier**: low / medium / high / ultra caps. **Graphics style**: the look (Toon, Natural, ...).
- **BUILD_BASE**: the CI run number subtracted to get the patch number.
