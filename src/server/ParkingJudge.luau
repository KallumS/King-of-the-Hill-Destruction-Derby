--!strict
-- Decides when a car has "properly" parked on the trailer. Every condition
-- must hold continuously for Config.Parking.HoldTime seconds:
--
--   * the whole footprint of the car is inside the painted bay
--   * the car is sitting on the deck (not hovering or wedged on a rail)
--   * it faces the cab to within MaxYawError degrees
--   * it is level with the deck (MaxTilt)
--   * it is moving with the trailer (MaxRelativeSpeed)
--
-- Progress drains quickly when any check fails, so a single shove from a
-- rival usually resets the attempt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local P = Config.Parking
local C = Config.Trailer
local V = Config.Vehicle

local ParkingJudge = {}

export type Verdict = {
	inBay: boolean,
	aligned: boolean,
	level: boolean,
	matched: boolean,
}

local HALF_X = V.ChassisSize.X / 2
local HALF_Z = V.ChassisSize.Z / 2
local CORNERS = {
	Vector3.new(-HALF_X, 0, -HALF_Z),
	Vector3.new(HALF_X, 0, -HALF_Z),
	Vector3.new(-HALF_X, 0, HALF_Z),
	Vector3.new(HALF_X, 0, HALF_Z),
}
local COS_TILT = math.cos(math.rad(P.MaxTilt))
local COS_YAW = math.cos(math.rad(P.MaxYawError))

-- Distance from deck surface to chassis centre when resting on suspension,
-- with generous slack for the deck's sway.
local MIN_HEIGHT = 0.5
local MAX_HEIGHT = V.RestLength + V.WheelRadius + 1.5

-- `relative` is the chassis CFrame expressed in the bay's space and
-- `relativeVelocity` the car's velocity minus the deck's velocity at the car.
-- Both come from the driver's client (see MatchManager for why and how they
-- are sanity-checked); the thresholds and timing are applied here on the server.
function ParkingJudge.Evaluate(relative: CFrame, relativeVelocity: Vector3): Verdict
	local inBay = true
	local halfW = C.BayWidth / 2
	local halfL = C.BayLength / 2
	for _, corner in CORNERS do
		local p = relative * corner
		if math.abs(p.X) > halfW or math.abs(p.Z) > halfL then
			inBay = false
			break
		end
	end
	local height = relative.Position.Y
	if height < MIN_HEIGHT or height > MAX_HEIGHT then
		inBay = false
	end

	-- Bay -Z points at the cab; the car's LookVector is its -Z too.
	local look = relative.LookVector
	local aligned = look.Z < 0 and -look.Z >= COS_YAW * math.sqrt(look.X * look.X + look.Z * look.Z)

	local level = relative.UpVector.Y >= COS_TILT

	local matched = relativeVelocity.Magnitude <= P.MaxRelativeSpeed

	return {
		inBay = inBay,
		aligned = aligned,
		level = level,
		matched = matched,
	}
end

-- Drains progress when there is no valid report this step.
function ParkingJudge.Decay(progress: number, dt: number): number
	return math.max(0, progress - dt * P.DecayRate / P.HoldTime)
end

-- Advances a 0..1 progress value for one physics step.
function ParkingJudge.Advance(progress: number, verdict: Verdict, dt: number): number
	local ok = verdict.inBay and verdict.aligned and verdict.level and verdict.matched
	if ok then
		return math.min(1, progress + dt / P.HoldTime)
	end
	return ParkingJudge.Decay(progress, dt)
end

return ParkingJudge
