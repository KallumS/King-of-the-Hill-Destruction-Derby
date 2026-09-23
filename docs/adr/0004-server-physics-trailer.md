# 0004. Trailer is a server-owned physics assembly driven by constraints

- Status: Accepted
- Date: 2026-09-23

## Context
Cars have to drive onto the moving truck and be carried along by it. An
anchored part moved by setting its CFrame each frame teleports: it passes
no velocity to what's resting on it, so cars would slide off. The truck
also has to be unstoppable, sway, and brake-check.

## Decision
- The truck is one unanchored welded assembly with a heavy root `Deck`
  (density 100). The server holds network ownership (`SetNetworkOwner(nil)`).
- Every Heartbeat, `Trailer._step`:
  - advances a distance along `TrackPath` at the current speed
  - sets `LinearVelocity.VectorVelocity` to tangent × speed plus a
    proportional correction toward the path point
  - sets `AlignOrientation.CFrame` to the path heading with sinusoidal
    yaw/roll sway and a small bank on corners
- Both constraints have infinite force/torque.
- Speed changes every `SpeedChangeInterval`. Some changes are brake checks.
- A collidable tailgate part blocks the deck until the ramp unlocks.
- The track spline was reshaped so its minimum turn radius is about 95 studs.
  That keeps the rigid ~80-stud truck's overhang (~10 studs) inside the
  70-stud road.

## Consequences
- Real contact physics carries cars on the deck, and the car controller's
  surface-relative drive (ADR-0002) makes driving on it controllable.
- The truck is effectively immovable, so rams bounce off it.
- Clients see the truck with replication delay. That creates a position
  mismatch between client-owned cars and the server's copy of the truck,
  which ADR-0006 handles.
- The truck is rigid (no articulation between cab and trailer), so tight
  corners must be avoided in the track design.

## Alternatives considered
- **Anchored truck moved by CFrame with velocity set by hand.** Carrying
  behaviour is unreliable, especially while rotating.
- **Truck simulated deterministically on every client.** Would remove the
  lag mismatch, but needs every machine to share the speed schedule and a
  local kinematic truck on each client. Much more complex, so it's deferred.
  It's a possible future superseding ADR if observers see too much jitter.
- **Articulated tractor + trailer.** More realistic, but harder to keep on
  the path and unnecessary for gameplay.
