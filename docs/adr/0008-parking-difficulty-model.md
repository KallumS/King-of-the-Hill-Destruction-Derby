# 0008. Match-length control through parking difficulty, not a scoring system

- Status: Accepted
- Date: 2026-09-23

## Context
The brief: the first player to park on the trailer wins, and parking should
be mechanically hard enough that a match lasts a few minutes. There is one
win condition and no points.

## Decision
Match length is controlled by the difficulty of the single win condition.
Each layer is a knob in `Config`:

1. **Opening lock:** the tailgate is up for `Match.RampLockTime` (45 s), so
   the first phase is a pure derby for position.
2. **Moving target:** the truck changes speed every 6–12 s (48–80 studs/s).
   25% of those changes are brake checks down to 30 studs/s, which slide a
   coasting car forward on the deck.
3. **Unstable platform:** continuous yaw/roll sway plus banking in corners.
4. **Strict pose:**
   - the bay is only 1.5 studs wider than the car on each side
   - the car must face the cab within 12°, be level within 14°, and match
     the truck's speed within 6 studs/s
5. **Sustained hold:** all conditions must hold for 4 s. Progress drains
   at twice the fill rate.
6. **Social pressure:** everyone sees a banner when any player passes 25%
   progress, which draws rams.
7. **Safety valves:**
   - an 8-minute cap that ends in a draw
   - an "all wrecked" end state
   - wrecks are removed after 8 s so the bay can't be permanently blocked

## Consequences
- One clear goal that's easy to explain. Difficulty can be tuned
  independently per knob. README lists which knobs to turn.
- Real match length is unknown until playtested. The numbers are first-pass
  estimates.
- A very skilled player could still finish quickly once the ramp opens. The
  45 s lock is the guaranteed minimum.

## Alternatives considered
- **Points for time parked.** Changes the game's identity away from "first
  to park wins".
- **Randomly timed ramp openings.** Less readable for players. Could be added
  later on top of the lock.
