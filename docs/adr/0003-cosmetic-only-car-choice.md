# 0003. Car choice is cosmetic-only on one shared chassis

- Status: Accepted
- Date: 2026-09-23

## Context
The brief: players pick one of five derby cars, and **every car has the same
speed and handling**.

## Decision
- `CarCatalog` entries contain only presentation data: name, tagline,
  colours and body style.
- `CarBuilder.Build` always creates the same `Chassis`: size, density and
  physical properties come from `Config.Vehicle`. Every body part is
  `Massless`, non-colliding, non-queryable and welded to the chassis.
- Handling reads only `Config.Vehicle`.

## Consequences
- Parity is guaranteed by construction. Adding a sixth car is purely visual
  work.
- The hitbox is always a 7×13 box, so a taller body (the pickup's roll bar,
  the wagon's roof rack) doesn't collide the way it looks. This is an
  accepted trade-off.
- Any future request for per-car stats would need a new ADR superseding this
  one.

## Alternatives considered
- **Per-car stats balanced to be "equal overall".** Contradicts the brief
  and is harder to balance.
- **Collidable body parts.** Would change mass, inertia and hitbox per car,
  which breaks parity.
