# Architecture Decision Records

Short records of decisions that are hard to reverse or that constrain future
work. Each ADR is immutable once **Accepted**. To change course, add a new ADR
that supersedes the old one and update the old one's status line to point at
it.

| # | Title | Status | Date |
|---|---|---|---|
| [0001](0001-code-only-rojo-project.md) | Code-only Rojo project; world, cars and UI generated at runtime | Accepted | 2026-09-23 |
| [0002](0002-client-owned-raycast-vehicles.md) | Client-owned raycast vehicles instead of VehicleSeat/constraint cars | Accepted | 2026-09-23 |
| [0003](0003-cosmetic-only-car-choice.md) | Car choice is cosmetic-only on one shared chassis | Accepted | 2026-09-23 |
| [0004](0004-server-physics-trailer.md) | Trailer is a server-owned physics assembly driven by constraints | Accepted | 2026-09-23 |
| [0005](0005-server-inferred-impact-damage.md) | Impact damage inferred on the server from velocity spikes plus contact | Accepted | 2026-09-23 |
| [0006](0006-client-reported-parking-pose.md) | Parking judged on the server from client-reported bay-relative pose | Accepted | 2026-09-23 |
| [0007](0007-no-avatars-scripted-camera.md) | No avatars, fully scripted camera, streaming disabled | Accepted | 2026-09-23 |
| [0008](0008-parking-difficulty-model.md) | Match-length control through parking difficulty, not a scoring system | Accepted | 2026-09-23 |

## Template

```markdown
# NNNN. Title

- Status: Proposed | Accepted | Superseded by NNNN
- Date: YYYY-MM-DD

## Context
What forces are at play and why a decision is needed.

## Decision
What we are doing.

## Consequences
What becomes easier or harder, risks, and follow-ups.

## Alternatives considered
Options rejected and why.
```
