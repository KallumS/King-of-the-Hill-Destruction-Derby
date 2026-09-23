# 0002. Client-owned raycast vehicles instead of VehicleSeat/constraint cars

- Status: Accepted
- Date: 2026-09-23

## Context
Drifting is a headline feature, and derby contact needs to feel immediate.
Roblox's `VehicleSeat` with hinge/spring constraints is hard to tune for
arcade drifting and depends on character seating. Any car simulated on the
server has input lag equal to the round-trip time.

## Decision
- Each car is one collidable `Chassis` part with massless visuals. The server
  gives the driver **network ownership** when the race starts
  (`CarService.ReleaseAll`).
- The driver's client runs `CarController` in `RunService.PreSimulation`:
  - one raycast spring/damper per wheel, applied with `ApplyImpulseAtPosition`
  - arcade longitudinal and lateral grip applied as impulses
  - yaw rate set directly from steering input
- All velocities are measured **relative to the surface under the wheels**
  (`GetVelocityAtPosition` of the hit part), so driving on the moving
  trailer handles like driving on the road.
- Drift: the handbrake blends rear grip down (`DriftRearGrip`), raises the
  steer rate, and charges a boost that fires when the handbrake is released.
- `ReceiveAge == 0` is checked so the client only drives parts it actually
  simulates.

## Consequences
- Zero-latency handling for the driver, and full control over drift feel via
  `Config.Vehicle`.
- Other players see each car with normal replication delay. Wheel animation
  is recreated locally for every car by `VehicleVisuals`.
- The client is authoritative over its own car's motion. Speed hacks and
  teleports are possible. Mitigation is plausibility checks on the server
  (ADR-0005, ADR-0006).
- Damage and parking can't simply trust server-side positions (see ADR-0005
  and ADR-0006).

## Alternatives considered
- **Server-simulated cars.** Input lag makes drifting and aiming rams
  unpleasant.
- **VehicleSeat + constraints.** Needs characters, is harder to make drift
  predictably, and ties handling to part masses.
