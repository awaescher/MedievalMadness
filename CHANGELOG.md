# Changelog

Rough release notes, newest first. Versions before 1.10.0 are reconstructed from the specification and are approximate.
**Rule: this file and `SPEC.md` are updated with every change.** The patch number rises with every build (`export.sh`).

## Unreleased
- **Nothing hangs in the air after the ground slides away** (landslide / crater): the anchor test now looks at the whole footprint of a part and compares with the gap it had when built (before: only the centre point vs a fixed 0.7 m). Parts that stood on the ground (foundations, posts) let go when the soil under them drops > 1 m. A building whose ground gave way is `undermined`: its support check is strict (no cantilevers, parts only rest on parts directly below them, roofs need a wall under them), so what hung from a few surviving corners now comes down. A sweep over the changed area for 6 s after every soil change also wakes sleeping loose parts left in the air and releases stacked palisade posts / wall layers that hang over nothing. New autotest `--autotest=hanging`.
- **Flags fall with their mast**: a flag hangs on the nearest live part of its building (pole, spire, ridge); when that part breaks loose or is shot away the flag drops too instead of hovering (`Flag.mast`).
- **No more flames in mid-air**: ground fires follow the soil height each tick (craters / landslides lower the ground), and a flame whose burning part is gone or out is released at once.
- **Supply crates look different**: the small crates are lighter wood with a round black bomb (with fuse) painted on every side (new prop `crate_supply`), also while on the parachute, so they are no longer mistaken for village crates.
- **Powder kegs and fire barrels turn up more**: late in the match (from turn 4 × players) 20 % of the small supply crates hold a powder keg and 20 % a fire barrel instead of boulders / logs.
- Aim elevation is limited to **15°–60°** (before 5°–80°); the CPU bots sample 20°–60°.
- **Graphics styles** (options menu and pause menu, "Graphics style"): Toon (default, unchanged), Natural (golden hour), Retro, Noir comic, Neon synthwave, Watercolor. One global shader parameter (`gfx_style`, `project.godot` `[shader_globals]`) switches the toon / outline / water / sky shaders; `GfxStyle` (`scripts/render/gfx_style.gd`) holds the per-style table (colours, tonemapper, glow, SSAO, shadows, lighting preset); a full-screen post shader (`post.gdshader`) adds grain / pixelation + CRT / halftone / paper. Saved as `gfx_style` in `settings.cfg`. Index 2 of the shader style numbers is unused (the removed diorama style).
  - **Natural** (`photo`): real CC0 material textures from ambientCG (`assets/textures/`, 512 px: bark, planks, stone, brick, thatch, cloth, metal, grass, ground, leaf), projected triplanar with anti-tiling (`GfxTextures`); the material of each part comes from the physics material (`MeshGen.Buf.mat` -> UV.x, or the `mat_id` instance parameter for single parts); foliage gets bulging leaf clumps, single leaves and light shining through; ground grass has its own colour and tufts; sky ambient light, 4 shadow cascades (8k atlas on Ultra), SSAO / SSIL / SSR / SDFGI, ACES tonemap, shadows let 20% light through so nothing turns black.
  - **Photo, second pass** (reference: a golden-hour mood image): low warm sun, sun-coloured haze with aerial perspective, volumetric light shafts, bloom, AgX tonemap with warm highlights / cool shadows, distance blur, moss streaks on stone, shingle texture on non-thatch roofs, cobbled patches in the trodden earth.
  - Stone is now a fine, quiet granite grain (ambientCG Granite002A) so the single stone blocks are not covered in a second pattern; thatched roofs get straw bundles laid in rows down the slope (shadowed lip per row, fine strands); water in this style has broad, slow ripples.
  - Style names lost their bracket texts (except "Toon (default)") and the list is ordered: Toon, Natural, Pop art, Watercolor, Retro, Neon, Noir. The natural style's distance blur is switched off in the overview.
  - **Colour comic** (`comic`): the toon look with very thick black outlines (no dots).
  - **Retro**: 640 px grid, vertex snapping, 8 colour levels, ordered dither, curved CRT screen with neutral scan lines and grille (no colour fringes), faint glow, almost no flicker and a faint bar rolling down every 7 s.
  - New autotests `--autotest=styles`, `--autotest=trees`, `--autotest=water` (screenshots of all styles / tree close-ups / the dropdown toggle).
- Results screen redesigned: dark winner banner with crowns (long team names wrap), wider panel, header row plus one card per player with fixed right-aligned columns (so the numbers line up), gold / silver / bronze rank medals, team colour bar, winning team highlighted in gold, best value per column in orange, titles as orange star chips under the player instead of a text list, panel pops in, rows fade in one after another and the points count up. New autotest `--autotest=results_ui` shows the screen with made-up stats.
- New app icon: view from a flying boulder at a village at noon - a castle tower with battlements on a hill, a church in the background, differently built houses standing on the ground (foundation + ground shadow), smoke from chimneys, no fire.
- Cow: the black spots no longer stick out. They are now thin discs projected onto the body surface and tilted to its normal (`CowMesh._spot`), so they lie on the skin like paint.
- GitHub Actions (`.github/workflows/build.yml`): build + export (Windows, macOS, Linux via `export.sh`) now runs on every push to any branch and on pull requests (before: only `main` and `v*` tags); a newer push cancels the running build of the same ref. Release files are still only attached for `v*` tags, and the release text is taken from the matching `## <version>` section of this file (tag `v1.10.18` -> section `## 1.10.18`).

## 1.10.17
- Linux / OpenGL: the Compatibility renderer only has 4096 slots for per-instance shader values and the toon shader used three per object, so thousands of objects got garbage colours (orange / purple) and the console flooded with "Too many instances using shader instance variables". The toon shader is now a constant-value copy in the OpenGL renderer; part colours come from cached materials, glow / wet are skipped there. Forward+ / Mobile are unchanged.
- VSync is off by default (much faster on Linux). Saved settings stay as they are; "Reset options" applies the new default.
- `DEBUG=1 ./export.sh` additionally builds a debug macOS app (prints a script backtrace on engine crashes).

## 1.10.16
- Online: weather / random events / supply crates (like timer, catapults, palisades, terrain, arsenal, unlock rules) can only be changed by the host; guests see the host's values (and get their own back when they leave). (Weather and random events are switched off in online matches anyway.)
- The owner's name floats above every village flag (small, visible up to ~140 m), so you always see whose village you are hitting.

## 1.10.15
- Online: "Main menu" after a finished match keeps the relay room and its players (before, everybody was kicked out and the guest seats turned into "CPU"). Leaving the room still works with "Leave / Close lobby" or via the pause menu.
- Linux (Ubuntu) now uses the Compatibility (OpenGL) renderer by default: a user saw garbled textures and a magenta 3D view with the Vulkan Forward+ renderer. Override: `--rendering-method forward_plus`. Not testable here (only checked that Compatibility and Mobile render fine on the Mac).

## 1.10.14
- Team gifts (online): while a team mate is on turn you get an "Offer to <name>" strip at the bottom left with your weapons; click one to offer a unit. The player on turn sees a gift ribbon on that weapon (tooltip: who gives it, this turn only) and can fire it; the giver then has one less. Not used = it stays with the giver; offers end with the turn and can be taken back.

## 1.10.13
- Fixed a crash after "same map" / restart: all physics joints (cart wheels, ragdolls, ...) are now tracked and freed before their bodies.
- Church & co: a roof no longer hangs in the air from one tower - roof panels only stay if a wall / post is under them or they rest on a held panel.
- Chain shot: 40 % bigger, twice the mass (twice the punch).
- Supply crates turn into real physics crates after landing (slide down slopes, tip over, get pushed or smashed; smashed = content to whoever hit it last).
- Announcement banner no longer creeps upwards out of the screen when several banners come quickly.
- The fast-forward / skip / sound buttons are narrower and sit at the bottom edge.
- Bloom (glow) is switched off in all lighting modes: it was the suspect behind the blocky yellow squares around fires (report back if they still show up).

## 1.10.9
- Small plain supply crates (3 boulders or 5 logs) land quietly near the villages, as many as there are players (+30 % Powerplay, +50 % Chaos). New option "Supply crates" switches all crates off. Meteor crate: epic sound + camera look when it comes, fanfare when somebody hits it.
- Unlock rules are now tiered by game mode: Standard/Quarry = core, Powerplay adds power rules, Chaos adds chaos rules, Quarry has its own. New menu row "Unlock rules" (tier choosable for Custom) with a "?" that lists the rules. Locked weapons explain how to get them in their tooltip.
- New team rules: team mates get weapons when a mate loses a catapult, is down to the last one, is eliminated or wrecks an enemy catapult.
- New rules like revenge keg, own-goal keg, cow for destroyed animals / combo turns (Chaos), tavern/windmill/powder store boulders.
- Flaming barrel: fires are counted per turn (a spreading fire is one), every 3rd (Chaos: 2nd) turn pays one.
- Meteor marker only from the new supply crate: green glowing crate on a parachute sinks between two villages, hit it to win the marker. Not before every player has fired 5 shots, 1 (Standard) or 2 (Powerplay/Chaos) per match.
- Game mode dropdown order: Standard, Powerplay, Quarry, Chaos, Custom.
- Unlocks: powder keg only when your own blacksmith is destroyed; black powder only when one last catapult is left; blowing up barrels and wrecking 3 buildings no longer pay a keg (chain reactions still give points).
- New game icon (bold comic style: catapult, flaming boulder, castle tower).
- GitHub Action (`.github/workflows/build.yml`) builds Windows, macOS and Linux with `export.sh`; the run number becomes the patch number (`MM_BUILD_NUMBER`). Tags `v*` attach the files to a release. macOS stays unsigned.
- Defaults: 3 catapults, no round timer (also for "Reset options").
- Enemy markers on the 3D direction arrows are crossed swords instead of a red X (the X looked like an error).
- A rock that merely rolls into a catapult only bumps it (little damage, no bullet time); real hits still wreck it.
- Fixed: when the selected catapult was lost during the player's own turn the game hung. It now picks another catapult, or ends the turn at once: the player is eliminated, the next player is up, or the game ends.
- Camera shake is gentler (about a third) and only fires for real impacts (big explosions, boulders, meteors).

## 1.10.8
- New "Reset options" button in the main menu (first-start defaults for the options panel).
- Round timer defaults to 30 seconds; the last 5 seconds show a big red countdown with ticks and a flashing timer ring.
- Test runs no longer touch the saved settings (they had been leaving odd values like timer off behind).

## 1.10.7
- Online lobby is synchronised: each guest changes only their own colour, the host changes everybody's colours, defines the bots and the match options, and everybody sees the changes live.
- The V overview now stays open while another player (online or CPU) is playing.
- Online version number raised: older builds cannot join (lobby sync).

## 1.10.6
- Voices of people and animals are friendlier cartoon sounds, much quieter and only audible close to the camera.
- Fixed the blocky yellow halo around fire (lighting settings: no SSIL, finer glow, fire lights no longer feed global illumination and fog).

## 1.10.5
- A 3D arrow floats at your village while placing catapults and points to every other village, in their colour (green ring = team, red swords = enemy).
- Builders stand right at the wall they repair.
- Bullet time now only happens for direct hits on a catapult.
- The Boulder is 15% bigger and heavier; Chaos has 5 Boulders and 3 Logs, Quarry 3 Boulders and 6 Logs, Powerplay 2 Logs.
- Shooting down a tree near your own camp earns a Pointy Log.

## 1.10.4
- Settlers now rebuild damaged houses of their own village: slowly, with a hammer, only when calm and alive (never catapults).
- The last powder keg bursts over a much smaller area (30%) but leaves three times the powder, and the powder visibly flies.
- The version number is written into the app (Finder, Windows file properties) at every export.
- Added this changelog.

## 1.10.3
- While placing catapults, every other village is marked with its colour, name, distance and a Team / Enemy tag.
- Comic words ("BONK!") no longer cover the projectile; the Boulder rolls about 70% farther.
- After a Flints shot the camera shows the village that was actually hit.
- People and animals move smoothly at high frame rates.

## 1.10.1 – 1.10.2
- Cow weapon icon redrawn (detailed head, straight mouth); hosting dialog has an OK button instead of Leave.
- Version numbers now count up automatically; spec brought in line with all decisions.

## 1.10.0
- **Turn actions**: instead of a shot you can reposition a catapult (rams buildings) or build a stackable stone wall.
- **Teams**: the player colour is the team; teams win together; shared map markers; flagpole and tinted windows per village.
- **Starting arsenal presets** (Standard, Powerplay, Chaos, Quarry, Custom); the Flaming Barrel must now be earned.
- New UI: flat weapon bar, hint strip with key caps, flags for language, colour dropdowns, aligned menu, consistent buttons and dialogs, short tooltips with pros and cons.
- Online: relay hidden behind a cog, relay help with copyable spec and template, separate room-code step, room banner, Close/Leave lobby.
- Two cows per village with a new rounded model; Pointy Log tuning (about 70% stick, lies where it falls); powder ignites next to existing fire; many more (and rarer) settler sayings; buildings between camera and catapult turn see-through.

## 1.9.x
- Online play for up to 8 players through a relay (Cloudflare worker or self-hosted), with host-authoritative rules and turn snapshots.
- Mobile (touch) controls and export presets; quality tiers and lighting presets; automatic quality drop on low FPS.

## 1.8.x
- Points / scoreboard and end-of-game titles; impact focus with bullet time instead of replays; map marker with compass while aiming.
- Weapons are earned during the match (unlocks); Meteor Marker, Black Powder Kegs, Chain Shot, Stone Hail and Pointy Log added.

## 1.0 – 1.7
- First native (Godot 4, Jolt) port: 2–8 players hot-seat with CPU bots (four levels), procedural destructible villages, fire, water, weather, random events, ragdoll settlers and animals, synthesized sound, English and German, palisade posts, standalone exports for Windows, macOS and Linux.
