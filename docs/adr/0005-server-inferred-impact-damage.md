# 0005. Impact damage inferred on the server from velocity spikes plus contact

- Status: Accepted
- Date: 2026-09-23

## Context
Cars take damage and can be destroyed. Cars are client-owned (ADR-0002), so:

- the server doesn't simulate their collisions
- `Touched` events for client-owned parts aren't a reliable basis for damage
- letting clients report damage would be trivially exploitable

## Decision
`CarService._step`, running on the server every Heartbeat:

1. Keeps a 0.15 s history of each car's replicated velocity.
2. Takes the largest velocity change in that window, with vertical changes
   weighted ×0.3 so landings mostly don't count.
3. If the change is at least `ImpactThreshold` (28 studs/s), confirms contact
   with `GetPartBoundsInBox` around the chassis. The query excludes the car
   itself and the drivable surface folder, and respects `CanCollide`.
4. If there is contact, applies `(Δv − threshold) × DamagePerStud` (capped at
   `MaxSingleHit`), multiplied by the hit direction: front ×0.45, side ×1.25,
   rear ×1.
5. If another car is in the overlap, records it as the attacker. The last
   attacker within 6 s gets the credit for the wreck.

Falling below `KillY` destroys the car. A destroyed car is scorched, set on
fire, handed back to the server and removed after 8 s, so a wreck can never
permanently block the parking bay.

## Consequences
- The server stays authoritative over health. Clients only affect it through
  their motion.
- The contact check stops boosts, hard braking and drift recovery from
  causing damage.
- Accuracy depends on replication rate. Tuning `ImpactThreshold` and
  `DamagePerStud` will need playtesting.
- Clients could in theory avoid damage by faking smooth motion. That's
  accepted at this stage.

## Alternatives considered
- **Client-reported collisions.** Exploitable in both directions (immunity,
  instant kills).
- **Server-owned cars.** Rejected in ADR-0002.
