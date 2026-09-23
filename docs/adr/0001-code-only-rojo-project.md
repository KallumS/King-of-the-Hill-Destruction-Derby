# 0001. Code-only Rojo project; world, cars and UI generated at runtime

- Status: Accepted
- Date: 2026-09-23

## Context
The repository started empty, and the game was built in an environment with
no Roblox Studio. Binary place and model files (`.rbxl`, `.rbxm`) are hard to
review in git, can't be written without Studio, and cause merge conflicts.

## Decision
The game is a [Rojo](https://rojo.space) project (`default.project.json`)
containing only Luau source. Everything is built from code at runtime:

- `MapBuilder` builds the arena (ground, road, walls, stands, obstacles).
- `Trailer` builds the truck.
- `CarBuilder` builds the five cars.
- `Hud` builds all UI.

Service properties that must differ from the defaults, such as
`CharacterAutoLoads` and `StreamingEnabled`, are set in the project file.

## Consequences
- The whole game is reviewable, diffable text, and `rojo build` produces a
  playable place.
- Visual fidelity is limited to primitive parts (Part, WedgePart, cylinders)
  unless meshes are introduced later.
- Settings that scripts can't set, most importantly **Max Players = 10**,
  still have to be configured in Studio Game Settings. This is documented in
  README and CLAUDE.md.
- Asset IDs (sounds, meshes) can't be verified offline, so none are used
  yet.

## Alternatives considered
- **Hand-built place in Studio with scripts synced separately.** Not possible
  without Studio, and loses reviewability.
- **Committing `.rbxlx` XML.** Technically diffable, but huge and noisy, and
  merges badly.
