# CLAUDE.md

**King of the Hill: Destruction Derby** is a Roblox game for up to 10
players. A flatbed truck laps a track. Players race to catch it, drive up
its ramp and park in the yellow bay while rivals ram them. Wrecked cars
spectate, and the first valid park wins. It's a code-only Rojo project: all
world, cars and UI are generated at runtime, with no `.rbxl`/`.rbxm` files
(ADR-0001). Player-facing rules, controls and tuning are in `README.md`.

## Start of every session

1. Read the newest `docs/sessions/*.md`. Its **Follow-ups** list is the
   current backlog and status.
2. Skim `docs/adr/README.md` before touching vehicles, trailer, damage,
   parking or camera.

## Commands

```sh
rojo build -o KingOfTheHill.rbxlx   # build a place for Studio (or: rojo serve + Rojo plugin)
stylua src                          # format (tabs, 120 cols)
selene src                          # lint, std = "roblox" (downloads the API dump on first run)
./tools/lint-offline.sh             # stylua --check + selene with a minimal std; use in cloud sandboxes
```

- Before every commit, run `stylua src`, then `selene src` or
  `./tools/lint-offline.sh`. Everything must report zero problems.
- Cloud sandbox notes:
  - GitHub release downloads are blocked, so `rokit install` fails.
  - Install the tools with `cargo install selene` and
    `cargo install stylua --features luau` (crates.io is reachable).
    Binaries land in `~/.cargo/bin`.
- There are no automated tests, and Roblox only runs in Studio. Verify
  behaviour with a Studio playtest (**Test → Clients and Servers**). If you
  couldn't playtest, **say so** in the session log and the commit message.
- Pure maths, like the track spline, can be checked in Python. That's how
  the track's minimum turn radius was validated.

## Layout (Rojo → Roblox)

- `src/shared/` → `ReplicatedStorage.Shared`: `Config` (**all tuning**),
  `CarCatalog`, `CarBuilder`, `TrackPath`
- `src/server/` → `ServerScriptService.Server`: `Main.server` (entry),
  `MapBuilder`, `Trailer`, `CarService`, `ParkingJudge`, `MatchManager`
- `src/client/` → `StarterPlayerScripts.Client`: `Main.client` (entry),
  `CarController`, `InputState`, `CameraController`, `VehicleVisuals`,
  `ParkReporter`, `Hud`
- `docs/adr/` (decisions), `docs/sessions/` (dated logs), `tools/` (offline
  lint)

## Invariants: don't break these without a new ADR

- **Cars run on the driver's client** (network ownership, raycast
  suspension in `CarController`). The server never applies driving forces.
  (ADR-0002)
- **All cars handle identically.** Everything except `Chassis` is
  `Massless`, non-colliding, non-queryable and welded to it. No per-car
  stats. (ADR-0003)
- **The trailer is server-owned physics**, driven by
  LinearVelocity + AlignOrientation. The track must keep a turn radius of
  at least about 95 studs, because the truck is rigid. (ADR-0004)
- **Damage is inferred on the server** from a velocity spike plus a contact
  check. Never trust the client for damage. (ADR-0005)
- **Parking uses the client-reported, bay-relative pose, sanity-checked by
  the server.** Don't "simplify" it to server-only checks: server positions
  lag by speed × latency, about 9 studs. (ADR-0006)
- **No avatars** (`CharacterAutoLoads=false`), a scripted camera, and
  `StreamingEnabled=false`. (ADR-0007)
- **Match length is controlled by parking difficulty**, not by points.
  (ADR-0008)

## Code conventions

- Every file starts with `--!strict` and a header comment saying what the
  module owns. Use tabs and `local X = {}` modules, and call
  `game:GetService` at the top.
- Gameplay numbers go in `Config.luau`. Small implementation constants can
  be `UPPER_CASE` locals.
- Build geometry and UI with each module's local `new`/`part`/`make`
  helper.
- Only use Roblox asset IDs that have been verified. That's why there is no
  audio yet.

## Replicated contract (change both sides, then update this list)

- `ReplicatedStorage.GameState` attributes:
  - `Phase` (`Lobby|CarSelect|Countdown|Racing|Results`)
  - `PhaseEndsAt` and `RampUnlockAt` (in `Workspace:GetServerTimeNow()` time)
  - `WinnerName`, `WinnerUserId`, `EndReason` (`parked|timeout|wiped`)
  - `Participants`, `Alive`, `Waiting`, `MinPlayers`, `MaxPlayers`
- `ReplicatedStorage.Remotes`:
  - `SelectCar` (client→server: `carId, lock`)
  - `Feed` (server→all: `{kind="destroyed"|"ramp"|"winner", ...}`)
  - `ParkReport` (UnreliableRemoteEvent, client→server: `relativeCFrame, relativeVelocity`)
- `Workspace.Cars.<PlayerName>` attributes: `OwnerUserId`, `OwnerName`,
  `CarId`, `CarNumber`, `Health`, `MaxHealth`, `Destroyed`, `ParkProgress`
  (0..1)
- Player attributes: `InMatch`, `SelectedCar`, `CarLocked`
- `Workspace.Trailer` has the parts `Deck` (root) and `ParkingBay` (its -Z
  faces the cab). Model attributes: `Speed`, `RampLocked`.

## Documentation workflow

- **Session log:** create or append `docs/sessions/YYYY-MM-DD.md`. Cover what
  changed and why, how it was verified, and an updated **Follow-ups** list.
- **ADR:** any decision that is hard to reverse or constrains future work
  gets a new `docs/adr/NNNN-kebab-title.md` (template in
  `docs/adr/README.md`) plus a row in the index. Supersede old ADRs; never
  rewrite them.
- **Repo settings:** work on the branch you're assigned, and commit and push
  when done. Don't open a PR unless asked.
