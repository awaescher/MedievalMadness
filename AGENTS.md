# AGENTS.md

Short orientation for AI coding agents working in this repository. Read [README.md](README.md) first (what the game is, how to run,
build and test it). The long guide with background, rules of thumb and lessons learned is
[AI/HANDOVER.md](AI/HANDOVER.md) - read it before a bigger change.

## What this is

Medieval Madness: a turn-based, physics-heavy 3D artillery game (Godot 4, GDScript only, Jolt Physics) for 2-8 players, hot-seat or
online. Everything (graphics, sounds, jokes) is generated in code; there are no art or audio assets. `SPEC.md` is the full
specification and the source of truth for rules, numbers and file contracts.

## Rules for every change

1. **Run the tests** before you say something is done:
   `godot --headless --path . --script res://tests/run_tests.gd` (logic, about 3900 assertions) and, for gameplay code,
   `godot --path . -- --autotest=units` (in-scene physics, fire, ragdolls).
2. **Keep documents current in the same change**: `SPEC.md` (rules, numbers, contracts) and `CHANGELOG.md` (one short,
   player-facing line under `## Unreleased`, bold lead phrase, no code or file names). **The GitHub release text is generated from
   the CHANGELOG** and shows only the entries the previous release does not have yet, so a change without an entry is
   missing from the release. When the minor version is raised, move `## Unreleased` into `## <major>.<minor>.0` and raise `BUILD_BASE`.
3. **Build a binary** after a change with `./export.sh` (it also raises the patch number in `VERSION`).
4. **Both languages**: every visible text lives in `scripts/lang/en.gd` and `de.gd` with identical keys (`tests/test_i18n.gd` checks it).
5. **Online play is host-authoritative**: gameplay randomness uses `Game.rng_battle`, never `randf()`; every match option must travel in
   the lobby state and the start message (checklist in the handover).
6. **Anything that sits on the terrain must survive terrain changes** (craters, landslides): see "Terrain changes" in the handover.
7. **Typed GDScript, match the surrounding style**, no allocations in hot per-frame paths.
8. **Do not claim what you did not verify.** Say whether you only ran headless tests or also looked at a screenshot / the running game.
9. Commit finished changes with a short imperative message and **no co-author trailer**; push only when the owner asks.

## Where things are

`scripts/` code by area (folder map in the handover), `tests/` headless tests, `scripts/autotest.gd` in-game scenarios
(`godot --path . -- --autotest=<name>`), `tools/` helper scripts, `relay/` the online relay, `docs/` README images,
`.github/workflows/build.yml` the CI that builds and releases.
