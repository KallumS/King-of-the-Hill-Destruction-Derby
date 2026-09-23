# 0007. No avatars, fully scripted camera, streaming disabled

- Status: Accepted
- Date: 2026-09-23

## Context
Players only ever drive, spectate or watch the lobby. Avatars would need
seats, spawn locations and death handling, and would bring default controls
(jump on Space, which conflicts with the handbrake). Streaming would make
client raycasts (suspension, visuals) miss geometry that hasn't streamed in,
and without a character there's no natural streaming focus.

## Decision
- `Players.CharacterAutoLoads = false`, set in the project file and in
  `Main.server.luau`.
- `CameraController` binds to the render step with a `Scriptable` camera and
  has two modes: an arena orbit (lobby and car select) and a smoothed chase
  cam used for your own car, for spectating cars, and for the truck.
- Spectating cycles through alive cars and then the truck (Q/E, LB/RB, or
  on-screen arrows). Wrecked players watch their own wreck for 3 s first.
- `Workspace.StreamingEnabled = false` in the project file.

## Consequences
- Simple, predictable input and camera. There are no default character
  scripts to fight.
- No avatar customisation is visible. Name tags on cars identify players.
- With streaming off, the whole arena loads up front. It's a few thousand
  simple parts, which is fine now but should be watched if the map grows.

## Alternatives considered
- **Characters seated in VehicleSeats.** More setup and seat edge cases, and
  unnecessary with the vehicle model in ADR-0002.
- **Streaming with `RequestStreamAroundAsync`.** Adds complexity for no
  benefit at the current map size.
