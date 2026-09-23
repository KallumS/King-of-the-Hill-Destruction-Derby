# 0006. Parking judged on the server from client-reported bay-relative pose

- Status: Accepted
- Date: 2026-09-23

## Context
The win condition is a precise park inside a 10×17-stud bay on a truck doing
48–80 studs/s. The car is simulated on its driver's client and the truck on
the server (ADR-0002, ADR-0004). The server receives the car's position
roughly one latency period late, so it sees the car about speed × latency
behind where it is on the deck. At 60 studs/s and 150 ms that's around 9
studs, which is more than half the bay. A purely server-side check would
reject real parks and accept fake ones.

## Decision
- The client (`ParkReporter`) computes, at 15 Hz while within 35 studs of the
  bay:
  - `relative = bay.CFrame:ToObjectSpace(chassis.CFrame)`
  - `velocity = chassis velocity − deck:GetVelocityAtPosition(chassis)`

  It sends both over the `ParkReport` **UnreliableRemoteEvent**.
- The server validates each report: it must arrive during Racing, have the
  right types, contain no NaN, and have sane magnitudes.
- Each Heartbeat, the report is only used if it is under 0.35 s old, the
  server's copy of the car is within 40 studs of the bay, and it is moving
  within 30 studs/s of the truck.
- `ParkingJudge.Evaluate` applies the rules on the server:
  - the whole footprint is inside the bay
  - the chassis is at the right height above the deck
  - yaw is within 12°
  - tilt is within 14°
  - relative speed is at most 6 studs/s
- `MatchManager` advances or drains `ParkProgress` over a 4 s hold. Without
  a valid report, progress drains.

## Consequences
- The judgement matches what the driver sees, so parks feel fair.
- The thresholds and the timer are applied on the server, and a
  wildly-wrong position is rejected.
- A cheater within about 40 studs of the bay could fake a perfect pose.
  That's accepted for now. It could be tightened later with a stricter
  radius, cross-checks against server state lagged by the player's ping, or
  ADR-0004's deterministic-trailer alternative.
- Observers may see a parked car slightly offset on the deck. That's
  cosmetic.

## Alternatives considered
- **Purely server-side evaluation.** Wrong by speed × latency, as described
  above. This was the first implementation and was replaced before commit.
- **Server rewinding the truck to the player's ping.** Imprecise: Roblox
  interpolation delay is unknown and ping jitters.
- **Deterministic client-side truck.** See ADR-0004.
