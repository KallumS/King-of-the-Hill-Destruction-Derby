# King of the Hill: Destruction Derby

A Roblox game for up to 10 players. A flatbed truck laps the track, and everyone
races to catch it, drive up its ramp and **park in the yellow bay on the deck**.
Meanwhile everyone else tries to ram them off it. Take too much damage and your
car is wrecked, and you spectate for the rest of the match. The first player to
hold a proper park wins.

Everything (arena, track, truck, the five cars, all UI) is built from code, so
the whole place syncs from this repo with [Rojo](https://rojo.space). There are
no binary assets to import.

## Running it

1. Install the toolchain with [Rokit](https://github.com/rojo-rbx/rokit)
   (`rokit install`), or install Rojo 7.4+ some other way.
2. Either:
   - **Build a place file:** `rojo build -o KingOfTheHill.rbxlx`, then open it in Roblox Studio, or
   - **Live sync:** `rojo serve`, open a new Baseplate in Studio, and connect with the Rojo plugin.
     (Delete the default `Baseplate` and `SpawnLocation`; the arena brings its own ground.)
3. In **Game Settings → Places**, set **Max Players = 10**. `Players.MaxPlayers`
   can't be set from a script. The server also caps each match at 10 cars.
4. Press Play. With `MinPlayersToStart = 1` you can test on your own. For
   multiplayer, use **Test → Clients and Servers**.

For a live server, set `Config.Match.MinPlayersToStart` to 2 or more.

## How a match plays

| Phase | What happens |
|---|---|
| **Lobby** | Camera flies over the arena. Once enough players are in, a 15 s countdown starts. |
| **Car Select** | Pick one of 5 derby cars (15 s, or less once everyone locks in). |
| **Countdown** | Cars sit on the starting grid. The truck is parked 260 studs up the road. 3-2-1-GO. |
| **Racing** | The truck starts driving. **The tailgate is up for the first 45 s**, so the opening is pure derby as everyone jockeys for position. Then the ramp opens and parking counts. |
| **Results** | The winner gets confetti. If nobody parks within 8 minutes it's a draw, and if every car is wrecked it's "Total Carnage". Then back to the lobby. |

### Why parking is hard (so matches last a few minutes)

To count as parked, every one of these must hold **continuously for 4 seconds**:

- The whole car footprint (7×13 studs) is inside the bay (10×17 studs). That
  leaves about 1.5 studs of slack each side, and less if the car is angled.
- The car is resting on the deck, not hovering on top of another car.
- It faces the cab to within 12°.
- It is level with the deck to within 14°.
- It is moving with the truck to within 6 studs/s.

On top of that, the truck:

- changes speed every 6–12 s (48–80 studs/s), and 25% of those changes are
  sudden **brake checks** down to 30 studs/s, which slide a coasting car
  forward on the deck
- **sways** continuously (±3.5° yaw, ±1.6° roll) and banks through corners
- is an immovable wall. Hitting its cab or headboard hurts.

Progress drains twice as fast as it fills, so one good hit from a rival usually
resets an attempt. A warning banner tells every player when someone passes 25%
parked, so the whole lobby knows who to go after.

### Controls

| Action | Keyboard | Gamepad | Touch |
|---|---|---|---|
| Accelerate / brake / reverse | W / S (or arrows) | RT / LT | GAS / BRAKE |
| Steer | A / D | Left stick | ◀ ▶ |
| Handbrake / **drift** | Space (or Left Shift) | A or B | DRIFT |
| Flip car upright | R | Y | FLIP |
| Cycle spectate target | Q / E | LB / RB | ◀ ▶ on the spectate bar |

**Drifting:** hold the handbrake above about 25 studs/s. Rear grip collapses and
steering gets sharper. Hold a slide for at least 0.9 s and the **DRIFT BOOST**
bar fills. Let go of the handbrake to spend it on a short burst of speed (a full
bar needs 3 s). The boost can briefly push you past top speed, which helps you
catch the truck.

**Damage:** damage comes from sudden changes in velocity while touching
something. Front-bumper hits take 0.45× damage, side hits 1.25× and rear hits
1×. Smoke starts at 55 HP and fire at 25 HP. At 0 HP the car explodes and you
spectate. The kill feed credits whoever hit you last. Falling out of the world
also wrecks you.

**Offroad:** the infield grass is a shortcut for cutting across to the truck,
but top speed drops to 72% and grip to 80% there. Tyre stacks, dirt jumps and
abandoned wrecks are scattered across it.

## The five cars

All five share one chassis hitbox, mass and `Config.Vehicle` tuning, so **speed
and handling are identical**. Body parts are massless and don't collide, so the
choice only changes the look.

| Car | Look |
|---|---|
| Rustbucket | Rusty sedan |
| Bulldog | Pickup with a bull bar and roll bar |
| Wagon Queen | Wood-panelled station wagon with a roof rack and spare tyre |
| Checker | Ex-taxi with checker stripes and a lit roof sign |
| Hot Rod | Muscle car with a blower, stripes and a spoiler |

## Code layout

```
src/
  shared/            -> ReplicatedStorage.Shared
    Config.luau        all tuning values (match timings, vehicle, damage, trailer, parking, track)
    CarCatalog.luau    the 5 cars (cosmetic data)
    CarBuilder.luau    builds a car model; only the "Chassis" part has mass and collides
    TrackPath.luau     closed Catmull-Rom spline with arc-length lookup
  server/            -> ServerScriptService.Server
    Main.server.luau   entry point
    MapBuilder.luau    ground, asphalt loop, kerbs, walls, grandstands, obstacles
    Trailer.luau       the truck: physics-driven (LinearVelocity + AlignOrientation), speed changes, sway, tailgate
    CarService.luau    spawning, network ownership, impact damage, destruction
    ParkingJudge.luau  the parking rules
    MatchManager.luau  match state machine, remotes, parking timer
  client/            -> StarterPlayerScripts.Client
    Main.client.luau   decides whether to drive, spectate or show the lobby
    CarController.luau raycast-suspension car physics, drift, boost, flip
    InputState.luau    keyboard, gamepad and touch input merged together
    CameraController.luau  lobby flyover and chase/spectate camera
    VehicleVisuals.luau    wheel suspension, spin and steer, plus tyre smoke, for every car
    ParkReporter.luau  sends the car's pose relative to the bay to the server
    Hud.luau           all UI
```

### How the networking works

- **Cars run on their driver's client** (network ownership), so steering and
  drifting respond with no lag. The server works out damage from the cars'
  replicated velocities: a sudden change of at least 28 studs/s while the
  chassis is touching something. Boosts, braking and drift recovery don't
  count, and neither do most landings.
- **The truck runs on the server.** Because the car is on the client and the
  truck is on the server, the server always sees a car on the deck a few studs
  behind where its driver sees it (speed × latency). So the driver's client
  reports the car's pose relative to the bay, and the server checks that the
  report is plausible: it's recent, the server's copy of the car is within 40
  studs of the bay and moving roughly with the truck. The server then applies
  the parking rules and the 4-second timer itself.
- Public match state is stored as attributes on `ReplicatedStorage.GameState`
  (Phase, PhaseEndsAt, RampUnlockAt, Winner…). Cars carry `Health`,
  `Destroyed` and `ParkProgress` attributes.

## Project docs

- `CLAUDE.md`: contributor and agent guide (commands, conventions, replicated contract).
- `docs/adr/`: architecture decision records.
- `docs/sessions/`: dated session logs.

## Tuning

Everything lives in `src/shared/Config.luau`:

- **Matches too short?** Raise `Parking.HoldTime`, lower `Parking.MaxYawError`
  or `Trailer.BayWidth`, or raise `Match.RampLockTime`.
- **Matches too long?** Do the opposite, or lower `Trailer.BrakeCheckChance`
  and `SwayYawDegrees`.
- **Cars too fragile or too tanky?** Change `Damage.DamagePerStud` and
  `Damage.ImpactThreshold`.
- **Handling:** `Vehicle.*` covers grip, steer rates, drift grip and the boost.

## Not done yet

- **Not playtested in Studio yet.** The code was linted with selene and
  formatted with StyLua, but the physics numbers (suspension, grip, damage
  thresholds, truck speed) are first-pass values and will probably need a
  tuning session.
- **No sound.** None of the Roblox audio asset IDs could be checked, so no
  engine, crash or music sounds are included. The built-in `Explosion` makes
  its own sound.
- **Anti-cheat is basic.** Driving and the parking pose come from the client
  and are checked for plausibility only. That's normal for Roblox vehicle
  games, but a determined exploiter could fake the pose while near the bay.
