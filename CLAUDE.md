# CLAUDE.md

Guidance for Claude Code (and humans) working in this repository.

## Project

**King of the Hill: Destruction Derby** is a Roblox game for up to 10 players.
A flatbed truck laps a track, and players race to catch it, drive up its ramp
and park in the yellow bay on the deck while everyone else tries to wreck
them. Wrecked players spectate. The first valid park wins. Player-facing
rules, controls and tuning tips are in `README.md`.

The whole place is generated from Luau code synced with **Rojo**. There are no
`.rbxl`/`.rbxm` assets in the repo, and none should be added unless an ADR
changes that (see ADR-0001).

## Commands

```sh
rokit install                          # installs rojo, selene, stylua (pinned in rokit.toml)
rojo build -o KingOfTheHill.rbxlx      # build a place file to open in Studio
rojo serve                             # live-sync into Studio via the Rojo plugin
stylua src                             # format (config: stylua.toml, tabs, 120 cols)
stylua --check src                     # CI-style format check
selene src                             # lint (config: selene.toml, std = "roblox")
```

- Run `stylua src` and `selene src` before every commit. Both should report
  zero problems.
- `selene` with `std = "roblox"` downloads the Roblox API dump the first time.
  In sandboxed/cloud sessions without that network access, lint against a
  minimal std instead: a `robloxlite.yml` with `base: luau` that declares the
  Roblox globals (`game`, `Instance`, `Vector3`, `CFrame`, `Enum`, `task`, …).
  Don't commit that file.
- There is no automated test harness. Roblox can't run outside Studio, so
  behaviour changes need a Studio playtest (**Test → Clients and Servers**
  for multiplayer). When you can't playtest, say so in the session log and the
  commit or PR.

## Layout

```
default.project.json   Rojo tree; also sets CharacterAutoLoads=false, StreamingEnabled=false, lighting
src/shared/  -> ReplicatedStorage.Shared
  Config.luau          ALL tuning numbers (match, vehicle, damage, trailer, parking, track, camera)
  CarCatalog.luau      the 5 cosmetic cars
  CarBuilder.luau      builds a car Model; only "Chassis" has mass and collides
  TrackPath.luau       closed Catmull-Rom spline with arc-length lookup
src/server/  -> ServerScriptService.Server
  Main.server.luau     entry: build map -> CarService.Init -> MatchManager.Init/Run
  MapBuilder.luau      ground, road, kerbs, walls, grandstands, obstacles
  Trailer.luau         physics-driven truck (LinearVelocity + AlignOrientation)
  CarService.luau      spawn, network ownership, impact damage, destruction
  ParkingJudge.luau    pure parking rules on a bay-relative pose
  MatchManager.luau    phase state machine, remotes, parking timer
src/client/  -> StarterPlayer.StarterPlayerScripts.Client
  Main.client.luau     per-frame decision: lobby / drive / spectate
  CarController.luau   raycast suspension, drive, drift, boost, flip
  InputState.luau      keyboard + gamepad + touch merged
  CameraController.luau, VehicleVisuals.luau, ParkReporter.luau, Hud.luau
docs/adr/              architecture decision records
docs/sessions/         dated session logs
```

## Conventions

- Every file starts with `--!strict` and a header comment saying what the
  module owns. Match the existing style: tabs, `local X = {}` modules,
  `game:GetService` at the top, `require(Shared:WaitForChild(...))`.
- **Tuning lives in `Config.luau`.** Don't hard-code gameplay numbers in
  modules. Small implementation constants, such as report rates or history
  windows, may stay as `UPPER_CASE` locals.
- **All cars must handle identically.** Car bodies in `CarBuilder` are
  cosmetic: `Massless = true`, `CanCollide/CanQuery/CanTouch = false`, welded
  to `Chassis`. Never give a body part mass or collision, and never add
  per-car physics stats (see ADR-0003).
- Build UI and world geometry in code, using the local `new`/`part`/`make`
  helpers in each module.
- Only use asset IDs that have been verified. No sound assets are included
  yet for this reason.

### Replicated contract (keep server and client in sync)

- `ReplicatedStorage.GameState` (Folder) attributes: `Phase`
  (`Lobby|CarSelect|Countdown|Racing|Results`), `PhaseEndsAt` and
  `RampUnlockAt` (in `Workspace:GetServerTimeNow()` time), `WinnerName`,
  `WinnerUserId`, `EndReason` (`parked|timeout|wiped`), `Participants`,
  `Alive`, `Waiting`, `MinPlayers`, `MaxPlayers`.
- `ReplicatedStorage.Remotes`:
  - `SelectCar` (client→server: `carId, lock`)
  - `Feed` (server→all: `{kind="destroyed"|"ramp"|"winner", ...}`)
  - `ParkReport` (UnreliableRemoteEvent, client→server: `relativeCFrame, relativeVelocity`)
- `Workspace.Cars.<PlayerName>` Model attributes: `OwnerUserId`, `OwnerName`,
  `CarId`, `CarNumber`, `Health`, `MaxHealth`, `Destroyed`, `ParkProgress`
  (0..1).
- Player attributes: `InMatch`, `SelectedCar`, `CarLocked`.
- `Workspace.Trailer` has the parts `Deck` (root) and `ParkingBay`. The bay's
  -Z points at the cab. Model attributes: `Speed`, `RampLocked`.

If you rename or add anything here, update both sides and this list.

## Architecture rules of thumb

Read `docs/adr/` before changing any of these:

- Cars are simulated on the **driver's client** (ADR-0002). The server never
  applies driving forces. It only anchors or unanchors cars and hands out
  network ownership.
- The trailer is **server-owned physics** (ADR-0004).
- Damage is **inferred on the server** from velocity spikes while the chassis
  is touching something (ADR-0005).
- Parking is judged on the server from a **client-reported, bay-relative
  pose** that the server sanity-checks (ADR-0006). Don't "simplify" this back
  to a purely server-side check: latency makes that wrong.
- Players have no avatars (`CharacterAutoLoads = false`) and the camera is
  fully scripted (ADR-0007).

## Documentation workflow

- **Session log:** add or append `docs/sessions/YYYY-MM-DD.md` for each working
  session. Record what changed, why, how it was verified, and open follow-ups.
- **ADRs:** any decision that is hard to reverse or that constrains future work
  gets a new `docs/adr/NNNN-kebab-title.md`, using the template in
  `docs/adr/README.md`, and an entry in that index. To overturn an ADR, write a
  new one that supersedes it rather than editing the old decision.

## Known gaps / next steps

- Not yet playtested in Studio. Physics numbers are first-pass values.
- No audio.
- Anti-cheat is plausibility checks only.
- `Config.Match.MinPlayersToStart = 1` is for solo testing. Raise it for live
  servers.
- Max Players (10) must be set in Studio **Game Settings**. It can't be set
  from a script.
