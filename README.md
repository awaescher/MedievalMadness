# Medieval Madness

A turn-based, physics-heavy 3D artillery game for 2-8 players (humans and/or CPU bots), on one screen or online, alone or in teams.
Everybody owns a medieval village and 5 catapults. Take turns firing one shot at any other village.
Everything is a physics object and destructible, fire spreads, water puts it out, settlers become ragdolls and
shout jokes. Lose all 5 catapults and you are out - the last player standing wins.

<p align="center"><img src="docs/game.png" alt="Medieval Madness" width="720"></p>

Built with **Godot 4.4+ (tested with 4.7.2)**, GDScript only, Jolt Physics, Mobile renderer.
No image, model, font or audio files: all graphics are procedural and all sounds are synthesized at startup.

## Run

```bash
./run.sh                 # or:  godot --path .          (Windows: run.bat)
godot --path . -- --debug   # enables the debug keys (see below)
```

Needs `godot` (4.4 or newer, standard non-.NET build) on the `PATH`; on macOS `brew install --cask godot`.

## Build standalone executables

```bash
./export.sh              # Windows / macOS / Linux into build/   (Windows: export.bat)
```

Every export increases the patch number in `VERSION` (shown in the menu and sent when joining online).

The export presets live in `export_presets.cfg` (Windows x86_64 single .exe with embedded PCK, macOS universal .zip,
Linux x86_64 single file). They need the matching Godot **export templates** (Editor -> Manage Export Templates).
`build/` is git-ignored.

## Controls

| Action | Input |
|---|---|
| Aim + fire (slingshot) | Hold the **left mouse button anywhere**, pull *away* from where you want to shoot, release to fire. The white arrow starts at the catapult and shows the real flight direction on screen (the camera is frozen while you pull); pull length = power |
| Elevation | `Up`/`Down` (also while pulling) or `Shift` + mouse wheel |
| Cancel a pull | `Esc`, or pull back to less than 10 px |
| Orbit camera | Right mouse drag (aiming: +-60 deg / +-25 deg around the chase view) |
| Zoom | Mouse wheel |
| Choose ammo | `1`-`8` or click the ammo bar (locked weapons are dimmed with a padlock until earned) |
| Turn actions instead of a shot | `U` = relocate the selected catapult (`W`/`S` drive, `A`/`D` steer, any distance, `Space` ends the turn; people, animals and crates are no obstacle, buildings are rammed and take damage - the neighbours comment on it). `B` = build a stone wall (click sets it, `Q`/`E` turns it, next to a wall it continues it, click on a wall stacks another layer, only the top layer keeps its crenellations). Both sit at the right end of the weapon bar with a grey rim; the strip above the bar always lists what is possible right now |
| Choose catapult | `Tab` / `Shift+Tab`, click a catapult, or use the numbered catapult buttons (bottom right) |
| Skip the aftermath | click or `Space` after the first impact |
| Fine aim | Arrows (azimuth / elevation, `Shift` = finer), `W`/`S` power, `Space` fire |
| Face the next enemy village / your marker | `R` / `M` |
| Overview camera | `V` - shows the whole map (drag to orbit, middle mouse or `Shift`+right drag to pan, `WASD` pans, `Home` recenters) |
| Map marker | In the overview **left-click the ground** to set your one marker (new click moves it, click on it or `Shift`+click removes it). It stays for the whole match; while aiming a dashed line, a compass label and the range readout point to it |
| Skip turn | hold `X` for 2 s (or hold the button) |
| Pause / options | `Esc` |
| Fullscreen | `F11` |
| Placement | click ground = place, `Q`/`E` rotate, right click / `Z` removes the last one |
| Fast-forward (3x) | `F`, the `Vorspulen/Fast-forward` button, or `Space` outside your own aiming phase - handy during CPU turns; it switches itself off when it is your turn to aim |

**Aiming in detail** - the pull direction is opposite to the launch direction: drag *left* to aim *right*, drag
*down* to lob higher. Power = pull length (up to 220 px), azimuth = 0.25 deg per pixel, elevation = 15 deg + 0.3 deg per pixel
of downward pull. The first 40% of the flight path is previewed as dotted spheres; wind and per-ammo drag are included.
The HUD shows power / elevation / azimuth and the distance to the predicted landing point.

## Teams

The player colour is the team: give several players the same colour and they play as one team (no limit, no symmetry needed;
a match needs at least two colours). Turn order stays as it is. A team wins together as soon as no catapult of another team is
left. Allies are not targeted by the bots or by `R`, hits on allies count as own goals, markers set in the overview are shown to the
whole team (online too), every village has a flagpole in its team colour and window frames in a darker shade of it.

See [CHANGELOG.md](CHANGELOG.md) for the release notes (kept up to date together with `SPEC.md`).

## Rules in one minute

* Placement: every player puts 5 catapults inside their village zone (green ghost = valid).
* Each turn: pick a catapult, pick ammo, pull, release. Wind changes every turn; weather (rain, thunderstorm, storm)
  and random events (dragon, cheese meteor, cow rain, earthquake, geese, tax collector, fireworks, wizard bubble, flood)
  can spice things up.
* Ammo: Boring Rock (unlimited), Flaming Chamber Pot, Mighty Powder Keg, Splashy Water Balloon, Grandma's Buckshot,
  Moo-nition (a cow), Stone Hail, Chain Shot, Pointy Log and the Meteor Marker.
* A catapult dies at 0 hp, when it tips over for 3 s, or when it sinks in deep water. Eliminations are checked at the end of
  each turn.
* Spectacular hits (direct catapult hits) play in cancelable bullet time; the camera always stays on the impacted village.

## Debug keys (only with `-- --debug`, or in debug builds)

`B` test ball - `E` cycle random events - `W` cycle weather - `K` kill selected catapult - `F` ignite under the cursor -
`X` explode at the cursor - `C` collider wireframes - `H` heal catapults - `T` slow motion - `O` outlines - `F3` debug overlay.

## Tests

```bash
godot --headless --path . --script res://tests/run_tests.gd    # logic tests without autoloads (~2000 assertions)
godot --path . -- --autotest=units                             # in-scene physics / fire / ragdoll / powder-chain tests
godot --path . -- --autotest=cpugame --seed=x --wall=300       # 4 bots (Peasant, Squire, Knight, King) play a whole game
godot --path . -- --autotest=ammo                              # fires all 8 ammo types (screenshots in user://)
```

Other autotest scenarios: `menu`, `placement`, `village`, `shoot`, `physics`, `hud`, `perf`, `sound`. Screenshots are saved to
`user://shot_*.png` (macOS: `~/Library/Application Support/Godot/app_userdata/Medieval Madness/`).

## Project layout

```
scenes/main.tscn        one scene with a root Node; everything else is created in code
scripts/autoload/       Cfg (constants), Events (signal bus), Settings, I18n, Game, Sfx (synth + playback)
scripts/core/           Rng (mulberry32 + FNV-1a), value noise, util, ballistics, synth kit, sound recipes
scripts/render/         toon + outline + sky + water shaders, quality tiers, camera rig, procedural meshes
scripts/physics/        PhysicsServer3D wrapper, parts, structures (dormant/awake), glue links + support check, debris cap
scripts/world/          seeded map generation, chunked terrain with craters, village generator, game world
scripts/buildings/      16 building blueprints + trees + ruin, built from a small "kit" of wall/roof helpers
scripts/props/          barrels, crates, carts (hinge joints), lanterns, banners, tents, rubber duck ...
scripts/entities/       catapult, projectile (11 ammo types), meteor strike, settlers (ragdolls, bucket brigade), animals
scripts/systems/        damage, fire, explosion, water, weather, random events, turn manager, scoring
scripts/fx/             pooled particles, comic text, speech bubbles, trails, flags
scripts/ai/             CPU bots (Peasant / Squire / Knight / King)
scripts/ui/             parchment theme, menu, HUD, aiming, placement, results, pause
scripts/lang/           en.gd / de.gd (English + German)
tests/                  headless tests + in-scene unit scenarios
```

## Notes

* **Physics** bodies are created directly on `PhysicsServer3D` (Jolt). Building parts are glued by logical links (no joints):
  a structure sleeps as one merged mesh + one static compound collider until something hits it, then every part becomes its own
  frozen body and is released when its support is gone. Windmill sails and cart wheels use real hinge joints, ragdolls use
  cone-twist joints.
* **Fast-forward** (all-CPU games) raises the physics tick rate (180 Hz x time scale 3) instead of stretching the step, because long
  physics steps make bodies tunnel through the terrain.
* Warnings: `untyped_declaration` and the `unsafe_*` warnings are set to *warn* in `project.godot`; the code base is fully typed. Places
  that deliberately cast values out of dictionaries/arrays carry an `@warning_ignore_start("unsafe_*")` annotation.
* The signal that tells the menu "sound is ready" is `Sfx.synth_ready` (a `ready` signal already exists on every `Node`).
* macOS: the exported app is unsigned - right-click -> Open on first launch. Linux: `chmod +x MedievalMadness.x86_64`.

Made with Godot Engine. Everything (code, look, sounds, jokes) is original; no external assets are used.

## Ready-made builds

`./export.sh` writes `build/macos/MedievalMadness.zip` (unzip -> `Medieval Madness.app`), `build/windows/MedievalMadness.exe` and
`build/linux/MedievalMadness.x86_64`. The export templates for Godot 4.7.2 are installed in
`~/Library/Application Support/Godot/export_templates/4.7.2.stable/`.

## Weapons, posts and rules (v1.1)

* **Stone** is unlimited; you start with only 2 rolling **Flaming Barrels**. Every other weapon is earned: buckshot for wrecking an enemy
  catapult, mighty boulder / powder keg for losing catapults, cow when one of your own cows dies, pointy log for damaging three trees, stone hail for two buildings with one shot, chain shot for five settlers with one shot, powder keg for blowing up a
  powder barrel or wrecking three buildings with one shot, **Meteor Marker** for destroying a church / powder store or eliminating a player.
  The menu has a **Starting arsenal** dialog to pre-grant weapons.
* The menu also sets the terrain (flat … mountainous), the number of catapults (1-5) and of **palisade fences** (1-10, default 4; every fence is 3 posts side by side) per player. After the catapults every
  player sets wooden posts (tree-trunk thick, half a tower high) as cover - side by side or stacked - but not near an enemy village.
* Replays show the settlement as it was before the shot (destroyed parts come back as ghosts until they break).

## Powder, dents and landslides (v1.2)

* **Black Powder Kegs** (key `9`): one shot sends three small kegs rolling like Flaming Barrels; they leave black powder on the ground and
  on buildings. It lies there until fire touches it, then flash flames (about 5x normal fire, very short) run along the trail. Earned by
  destroying an enemy blacksmith or by losing every third catapult.
* Everything that burns leaves **black marks** on the ground for the rest of the match.
* Stones dig small dents, boulders big ones (and furrows while they roll), explosions near the ground dig real craters.
* A hard hit on a **very steep** slope starts a **landslide**: the soil slides down until the mountain flattens out and smashes what is in
  its way (more likely with "Very hilly" / "Mountainous" terrain). A landslide that wrecks an enemy building earns a boulder.

## Versions

The project is versioned with git (repository root: the folder above this one, which also holds `SPEC.md`). The version number lives
in the `VERSION` file, is shown in the main menu (`v1.2.3`) and in the macOS bundle. `tools/release.sh 1.2.3 "note"` bumps it, commits
everything and creates the tag `v1.2.3`; `git log --oneline` / `git tag` list the releases.

## Online play

Up to 8 players over the internet, no server of your own to run (a free Cloudflare worker as relay, or any machine with Godot). Setup and rules: [relay/README.md](relay/README.md).

## Phones and tablets (not an official target)

Phones and tablets are **not a supported platform**: there are no iOS / Android downloads, and the game is designed and tested for desktop with mouse and keyboard only. The code has a rough touch layer (one finger aims and fires like the mouse, two fingers pinch to zoom and orbit the camera) and the export presets exist, so you can try building it yourself, but it is untested on real devices, performance is unknown and things may be unusable.

* **iOS**: `IOS=1 ./export.sh` writes the Xcode project to `build/ios/MedievalMadness.xcodeproj`. Open it in Xcode, choose your team under *Signing & Capabilities*, pick your device and run (needs the iOS platform from Xcode > Settings > Components). Replace the placeholder team id in `export_presets.cfg` (`application/app_store_team_id`) with yours to export an .ipa directly.
* **Android**: install the Android SDK + JDK 17 and set them in the Godot editor settings (*Export > Android*), create a debug keystore, then `godot --headless --path . --export-debug Android build/android/MedievalMadness.apk`. The preset is in `export_presets.cfg`.
* **Web** is not possible: browsers only allow the Compatibility renderer, which caps the per-instance colour system this game uses (4096 instances), so the village colours break.
