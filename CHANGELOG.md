# Changelog

Release notes, newest first. Versions before 1.10.0 are reconstructed from the specification and are approximate.
**Rule: this file and `SPEC.md` are updated with every change.** The GitHub release text is taken from this file (only what is new since the previous release), so write entries short and for players: one line per change, bold lead phrase, no code names. The patch number rises with every build (`export.sh`).

## Unreleased

## 1.11.0

**New**

- **Drill Bomb**: a new weapon that drills down to sea level, explodes underground and lets the ground cave in. Earned by wrecking an enemy church or watchtower.
- **Wind as a match option**: none, light or strong (host decides online).
- **Auto-place option**: catapults and palisades can be placed automatically (match option, host only online).
- **Graphics styles**: Toon, Natural (golden hour), Pop art, Watercolor, Retro, Neon and Noir.
- **Rewards you can see**: a weapon you earn (crates, wrecked buildings, felled trees, fires ...) floats up from where it happened, with icon, count and the player's name in their colour.
- **Player names in their colour** in the feed, toasts and banners.

**Better**

- **Everything follows the ground**: rocks, bushes, flowers, animals and settlers lean with slopes and sink with craters and landslides. Buildings, posts, flags, flames and puddles no longer hang in the air when the ground gives way.
- **Chaos mode with fewer cows**: your own cow dying pays 2, any other animal of your camp 1. The "own goal" keg needs a whole building, not just a palisade.
- **Redesigned results screen**, new catapult icons, a starting-arsenal dialog with weapon icons that scrolls, a banner that fits the window, scrollable menu options.
- **Supply crates** are easier to tell from village crates; late in the match more of them hold powder kegs and fire barrels.
- **Aim elevation** is limited to 15°-60°.
- **Bottom-right buttons**: order Fast-forward, Map, Skip turn, Sound; keys and labels line up; Skip turn has to be held (`F12` or the mouse) with a progress fill inside the button, so it cannot be clicked by accident; `F10` switches the sound on/off (fullscreen stays on `F11`); weapon tiles look like every other button (no coloured frames), and without the glass effect (OpenGL) panels are much less transparent. Settings: toggles line up with the labels, dropdown lists are opaque again.
- **Catapults are hit everywhere**: a shot that hit only the throwing arm or the frames flew straight through; the whole catapult is hit zone now. "Elevation" is "Höhenwinkel" in German, the Fast-forward button only lights up (no colour), and the frosted-glass look can be switched off in the settings.
- **Watching the others**: the map (`M`) can be opened any time while somebody else plays and now shows who is on turn (a pulsing ring and beam in the player's colour on the catapult) and follows the shot with a bright marker and trail. New **Cinematic camera** (`C`, a button at the bottom right, saved): while others play, the camera is directed like a film - the catapult that aims, the flight of the shot from the side and the impact from above the village, from a different angle every turn; your own turn always uses the normal camera. Fast-forward runs while a CPU is on turn and in your own turn as soon as your shot is fired (not while you aim, never online, where the button is gone); it is not remembered. The debug key for collider wireframes moved from `C` to `J`.
- **Fixes**: the settings dialog stays open when you switch the language (it was closed by the rebuild of the menu), and in the cinematic camera buildings between the camera and the aiming catapult turn transparent like in your own turn.
- **Camera rides**: random events (dragon, geese, fireworks, ...) move into the camera for everybody; any key or click skips the ride. Fast-forward is greyed out until your shot is fired. The cinematic camera now stands near the place of impact, off to the side, so you see the target area before the shot lands and watch the projectile come in (a clear view, ~38 m away), and carries on from that angle after the impact.
- **Cleaner HUD**: the "X is on turn" panel at the top is gone (the arrow in the player list shows who is up; only the turn timer keeps a small panel), the player list is exactly as wide as its content, the skip-turn button and key are gone, `F12` switches the sound on/off (the button follows every change), the glass option is called "Transparency effects".
- **Flying debris**: found two causes of things being flung across the map: the terrain collider was refreshed on the real-time clock, so with fast-forward the soil changed under debris 3x as fast and pushed it out at up to 340 m/s (now it follows the game clock), and big blasts launched settlers at 60-80 m/s (everything that is not a shot is now capped at 40 m/s). Normal speed was already fine.
- More lines for the "your turn" announcement (21 instead of 5, English and German).
- **Background music**: three long songs (3.5 to 3.75 minutes each, "Tavern Dance", "Pilgrim's Road", "Castle Morning") composed and synthesised by the game itself - lute, flute / recorder / fiddle, a drone, frame drum, shaker and bells in Dorian / Aeolian / Mixolydian - play one after the other, quietly, in the menu and in the game. Own volume slider in the settings ("Music volume", quieter than the effects by default, 0 = off). The first song starts a few seconds after the game has started.
- **Sound effects no longer fade with the distance** (enemy villages were too quiet); only the direction stays, voices of people and animals still stay local. The cinematic camera is no longer remembered between games.
- **Windmills pay drill bombs**: hit the hub of an enemy windmill and you get a Drill Bomb; in Chaos mode, knocking all the sails off an enemy mill without wrecking it gives two (one reward per mill).
- **Cleaner buttons**: the thin light edge of the glass buttons is gone (it frayed at the corners, pink / white pixels); a **Quit** button in the menu; the start-up splash image is off and fullscreen is re-applied after the window is up (it drew only the top left corner on macOS).
- **Menu polish**: a proper cog for the settings button, smaller shadows with room around the fields (they were clipped), the weapon fields of the starting-arsenal dialog are glass instead of pink, dropdown lists are milky translucent.
- **Pause menu**: "Restart" (no more "same seed"), the new "Restart on a new map" (random seed, everything else kept), and the seed of the map is always shown under the menu.
- **Marker readable from far away**: the marker beacon now grows in proportion (pole, pennant, ring and beam) instead of showing a huge triangle when zoomed far out; the catapult counts in the player list are simple dots.
- **Funny names, new order every start**: 60 silly player names (it were 16); the order of the default names is drawn anew each time the game starts (names you typed yourself stay).
- **Modern menus**: every menu and dialog is frosted glass now, buttons and inputs are frosted glass tiles themselves with only a light tint and the same soft shadow everywhere, in the menus and in the game (no more playful colours or wobbling), language flags and a cog are three separate buttons at the top right, the pause menu is narrower, and the technical settings (graphics, display, sound, language) have their own **Settings** dialog, separate from the match rules. The unlock rules are shown as a plain line with a "Show rules" button instead of a disabled dropdown (the tier of a Custom arsenal is set in its Edit dialog).
- **Cleaner HUD**: the pause button is gone (Esc still opens the pause menu), the buttons at the bottom right are smaller, and the padlock on unavailable weapons is gone (they are simply more transparent).
- **New keys**: the map (overview) is on `M` and called "Map" / "Karte"; `X` sets your marker while the map is open and turns the catapult towards it while aiming; skipping a turn is `F12` (one press, no holding). The map has its own button at the bottom right (it is no move of the turn); "To enemy" (`R`) and "To marker" (`X`) stay in the strip in the middle.

**Fixed**

- Supply crates on their parachute show the painted bomb with its fuse and spark (they only showed black dots).
- The Meteor Marker icon shows the meteor falling towards the marker with its flaming tail behind it.
- The loading screen is translated; burning settlers and animals no longer leave their flame behind; puddles never lie on slopes.

**Downloads**

- One ZIP per platform (Windows, macOS, Linux); the macOS app is ad-hoc signed.

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
