--!strict
-- Central tuning values shared by the server and every client.
-- Every car uses the same Vehicle block, so speed and handling are identical
-- no matter which body a player picks.

local Config = {}

Config.Match = {
	MaxPlayers = 10,
	MinPlayersToStart = 1, -- raise to 2+ for live servers; 1 lets you test solo in Studio
	LobbyCountdown = 15, -- seconds of "match starting" once enough players are waiting
	CarSelectTime = 15,
	StartCountdown = 3,
	MaxMatchTime = 8 * 60, -- hard cap; if nobody parks the match ends in a draw
	RampLockTime = 45, -- tailgate stays up this long so the opening is pure derby
	PostMatchTime = 10,
}

Config.Vehicle = {
	-- Chassis hitbox (identical for all cars)
	ChassisSize = Vector3.new(7, 2.6, 13),
	Density = 0.7,

	-- Suspension (raycast, one ray per wheel)
	WheelOffsetX = 3.1,
	WheelOffsetZ = 4.6,
	RestLength = 2.2,
	SpringStiffness = 220, -- per unit of supported mass; ~0.9 stud sag at rest
	SpringDamping = 12,
	WheelRadius = 1.3,

	-- Drive
	MaxSpeed = 105, -- studs/s on tarmac
	ReverseSpeed = 40,
	EngineAccel = 70,
	BrakeDecel = 140,
	RollingDrag = 0.35,
	OffroadSpeedMultiplier = 0.72,
	OffroadGripMultiplier = 0.8,

	-- Steering
	SteerRateLowSpeed = 2.6, -- rad/s of yaw at low speed at full lock
	SteerRateHighSpeed = 1.5,
	SteerResponse = 8,

	-- Grip (fraction of lateral velocity removed per second)
	FrontGrip = 9,
	RearGrip = 8,
	DriftRearGrip = 1.4,
	DriftFrontGrip = 6.5,
	DriftSteerBonus = 1.45,
	DriftSpeedKeep = 0.985, -- per-second multiplier of speed loss while sliding

	-- Drift boost: hold a drift then release for a short shove
	DriftBoostMinTime = 0.9,
	DriftBoostMaxTime = 3.0,
	DriftBoostMaxImpulse = 45, -- studs/s added at max charge
	DriftBoostSpeedCap = 1.25, -- boost may exceed MaxSpeed by this factor briefly

	-- Self-righting when the car is on its roof / side
	FlipCooldown = 3,
}

Config.Damage = {
	MaxHealth = 100,
	ImpactThreshold = 28, -- change in velocity (studs/s) in one step before damage applies
	DamagePerStud = 0.55,
	MaxSingleHit = 45,
	FrontArmorMultiplier = 0.45, -- hitting with your bumper hurts you less
	SideMultiplier = 1.25,
	RearMultiplier = 1.0,
	AttackerWindow = 0.35, -- seconds: another car within this window of a hit gets the credit
	AttackerRadius = 18,
	KillY = -40, -- falling below this destroys the car
	SmokeHealth = 55,
	FireHealth = 25,
	ContactCooldown = 0.12,
}

Config.Trailer = {
	-- Truck + flatbed dimensions
	DeckLength = 54,
	DeckWidth = 15,
	DeckHeight = 5.5, -- height of deck surface above the road
	RampLength = 18,
	CabLength = 16,

	-- Parking bay painted on the deck: smaller than the deck on purpose
	BayLength = 17,
	BayWidth = 10,
	BayForwardOffset = 14, -- from deck centre toward the cab

	-- Movement
	BaseSpeed = 62,
	MinSpeed = 48,
	MaxSpeed = 80,
	SpeedChangeInterval = NumberRange.new(6, 12),
	SpeedChangeRate = 12, -- studs/s^2 while ramping between targets
	SwayYawDegrees = 3.5,
	SwayRollDegrees = 1.6,
	SwayPeriod = 3.3,
	BrakeCheckChance = 0.25, -- chance each speed change is a sudden brake check
	BrakeCheckSpeed = 30,
	LeadDistance = 260, -- how far down the track the trailer starts ahead of the grid
}

Config.Parking = {
	HoldTime = 4.0, -- seconds that every condition must hold continuously
	MaxRelativeSpeed = 6, -- studs/s relative to the trailer
	MaxYawError = 12, -- degrees off the trailer's heading (must face the cab)
	MaxTilt = 14, -- degrees from the deck's up vector
	DecayRate = 2.0, -- progress drains this many times faster than it fills
}

Config.Track = {
	Width = 70,
	GroundSize = 1400,
	SampleSpacing = 10,
	-- Control points of the closed Catmull-Rom loop (XZ plane)
	ControlPoints = {
		Vector3.new(0, 0, -460),
		Vector3.new(210, 0, -320),
		Vector3.new(330, 0, -170),
		Vector3.new(480, 0, 0),
		Vector3.new(450, 0, 230),
		Vector3.new(210, 0, 320),
		Vector3.new(0, 0, 340),
		Vector3.new(-240, 0, 370),
		Vector3.new(-450, 0, 230),
		Vector3.new(-420, 0, 0),
		Vector3.new(-330, 0, -170),
		Vector3.new(-240, 0, -370),
	},
	GridStartDistance = 20, -- track distance where the grid is placed
	GridRows = 5,
	GridColumns = 2,
	GridRowSpacing = 22,
	GridColumnSpacing = 18,
}

Config.Camera = {
	Distance = 26,
	Height = 9,
	LookHeight = 3,
	Stiffness = 7,
	FovBase = 70,
	FovSpeedBonus = 14,
}

return Config
