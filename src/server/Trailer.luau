--!strict
-- The flatbed truck that laps the track. It is a heavy, unanchored, server
-- owned assembly steered by a LinearVelocity + AlignOrientation pair, so cars
-- driving onto the deck are carried by real contact physics.
--
-- To make parking hard the truck:
--   * keeps its tailgate up for the opening phase of the match
--   * changes speed every few seconds, sometimes with a sudden brake check
--   * sways (yaw + roll) continuously, so the deck is never still

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TrackPath = require(Shared:WaitForChild("TrackPath"))

type TrackPath = TrackPath.TrackPath

local C = Config.Trailer

local DECK_THICKNESS = 1.2
local DECK_CENTER_Y = C.DeckHeight - DECK_THICKNESS / 2

local Trailer = {}
Trailer.__index = Trailer

export type Trailer = typeof(setmetatable(
	{} :: {
		path: TrackPath,
		model: Model,
		deck: BasePart,
		tailgate: BasePart,
		bay: BasePart,
		linearVelocity: LinearVelocity,
		alignOrientation: AlignOrientation,
		distance: number,
		speed: number,
		targetSpeed: number,
		nextSpeedChange: number,
		brakeCheckUntil: number,
		elapsed: number,
		running: boolean,
		rng: Random,
		connection: RBXScriptConnection?,
	},
	Trailer
))

local function make(className: string, parent: Instance, props: { [string]: any }): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	instance.Parent = parent
	return instance
end

local HEAVY = PhysicalProperties.new(100, 0.6, 0.1, 1, 1)

local function solid(
	model: Model,
	deck: BasePart,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material?
): BasePart
	local p = make("Part", model, {
		Name = name,
		Size = size,
		CFrame = deck.CFrame * offset,
		Color = color,
		Material = material or Enum.Material.Metal,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		CustomPhysicalProperties = HEAVY,
		Anchored = false,
	}) :: BasePart
	make("WeldConstraint", p, { Part0 = deck, Part1 = p })
	return p
end

local function decor(
	model: Instance,
	deck: BasePart,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): BasePart
	local p = make("Part", model, {
		Name = name,
		Size = size,
		CFrame = deck.CFrame * offset,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Massless = true,
		Anchored = false,
	}) :: Part
	if shape then
		p.Shape = shape
	end
	make("WeldConstraint", p, { Part0 = deck, Part1 = p })
	return p
end

local function buildModel(): (Model, BasePart, BasePart, BasePart)
	local model = Instance.new("Model")
	model.Name = "Trailer"

	local deck = make("Part", model, {
		Name = "Deck",
		Size = Vector3.new(C.DeckWidth, DECK_THICKNESS, C.DeckLength),
		CFrame = CFrame.new(0, DECK_CENTER_Y, 0),
		Color = Color3.fromRGB(95, 95, 100),
		Material = Enum.Material.DiamondPlate,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		CustomPhysicalProperties = HEAVY,
		Anchored = true,
	}) :: BasePart
	model.PrimaryPart = deck

	local deckTop = DECK_THICKNESS / 2
	local halfLen = C.DeckLength / 2

	-- Headboard between deck and cab
	solid(
		model,
		deck,
		"Headboard",
		Vector3.new(C.DeckWidth, 6, 1),
		CFrame.new(0, deckTop + 3, -halfLen + 0.5),
		Color3.fromRGB(40, 40, 45)
	)

	-- Tractor unit
	local cabColor = Color3.fromRGB(230, 120, 20)
	local groundLocal = -DECK_CENTER_Y -- road height in deck space
	local cabZ = -halfLen - 1 - C.CabLength / 2
	solid(model, deck, "Cab", Vector3.new(12, 10, 9), CFrame.new(0, groundLocal + 3 + 5, cabZ + 3), cabColor)
	solid(
		model,
		deck,
		"Hood",
		Vector3.new(11, 6, C.CabLength - 9),
		CFrame.new(0, groundLocal + 3 + 3, cabZ + 3 - 4.5 - (C.CabLength - 9) / 2),
		cabColor
	)
	decor(
		model,
		deck,
		"Windshield",
		Vector3.new(10.5, 3.8, 0.3),
		CFrame.new(0, groundLocal + 3 + 7.2, cabZ + 3 - 4.55),
		Color3.fromRGB(30, 38, 48),
		Enum.Material.Glass
	)
	decor(
		model,
		deck,
		"Grille",
		Vector3.new(8, 4, 0.3),
		CFrame.new(0, groundLocal + 5.5, cabZ + 3 - 4.5 - (C.CabLength - 9) - 0.1),
		Color3.fromRGB(200, 200, 205),
		Enum.Material.DiamondPlate
	)
	for _, side in { -1, 1 } do
		decor(
			model,
			deck,
			"ExhaustStack",
			Vector3.new(8, 0.8, 0.8),
			CFrame.new(side * 6.4, groundLocal + 3 + 10, cabZ + 7) * CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromRGB(210, 210, 215),
			Enum.Material.Metal,
			Enum.PartType.Cylinder
		)
		local beacon = decor(
			model,
			deck,
			"Beacon",
			Vector3.new(1.2, 1, 1.2),
			CFrame.new(side * 4, groundLocal + 3 + 10.5, cabZ + 3),
			Color3.fromRGB(255, 150, 0),
			Enum.Material.Neon
		)
		make("PointLight", beacon, { Color = Color3.fromRGB(255, 150, 0), Range = 18, Brightness = 3 })
		decor(
			model,
			deck,
			"Headlight",
			Vector3.new(1.8, 1, 0.3),
			CFrame.new(side * 4.2, groundLocal + 4.5, cabZ + 3 - 4.5 - (C.CabLength - 9) - 0.1),
			Color3.fromRGB(255, 250, 220),
			Enum.Material.Neon
		)
	end

	-- Wheels (visual)
	local axles = {
		cabZ - C.CabLength / 2 + 3,
		cabZ + C.CabLength / 2 - 3,
		halfLen - 16,
		halfLen - 10,
		halfLen - 4,
	}
	for _, z in axles do
		for _, side in { -1, 1 } do
			decor(
				model,
				deck,
				"Wheel",
				Vector3.new(2.4, 5, 5),
				CFrame.new(side * (C.DeckWidth / 2 - 1.5), groundLocal + 2.5, z),
				Color3.fromRGB(25, 25, 25),
				Enum.Material.Rubber,
				Enum.PartType.Cylinder
			)
		end
	end
	-- Frame rails under the deck
	decor(
		model,
		deck,
		"Frame",
		Vector3.new(C.DeckWidth - 4, C.DeckHeight - 4, C.DeckLength),
		CFrame.new(0, -DECK_THICKNESS / 2 - (C.DeckHeight - 4) / 2, 0),
		Color3.fromRGB(35, 35, 38),
		Enum.Material.Metal
	)

	-- Loading ramp behind the deck. WedgePart slopes down toward its -Z, so it
	-- is turned around to slope down toward the back of the truck.
	local rampBottom = 0.9
	local rampHeight = C.DeckHeight - rampBottom
	local ramp = make("WedgePart", model, {
		Name = "Ramp",
		Size = Vector3.new(C.DeckWidth, rampHeight, C.RampLength),
		CFrame = deck.CFrame
			* CFrame.new(0, groundLocal + rampBottom + rampHeight / 2, halfLen + C.RampLength / 2)
			* CFrame.Angles(0, math.pi, 0),
		Color = Color3.fromRGB(120, 120, 125),
		Material = Enum.Material.DiamondPlate,
		CustomPhysicalProperties = HEAVY,
		Anchored = false,
	}) :: BasePart
	make("WeldConstraint", ramp, { Part0 = deck, Part1 = ramp })

	-- Tailgate blocks the deck until the ramp unlocks.
	local tailgate = solid(
		model,
		deck,
		"Tailgate",
		Vector3.new(C.DeckWidth, 6, 0.8),
		CFrame.new(0, deckTop + 3, halfLen - 0.4),
		Color3.fromRGB(200, 30, 30),
		Enum.Material.SmoothPlastic
	)
	local gateGui = make("SurfaceGui", tailgate, {
		Face = Enum.NormalId.Back,
		CanvasSize = Vector2.new(400, 160),
		LightInfluence = 0,
	})
	make("TextLabel", gateGui, {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "LOCKED",
		TextScaled = true,
		Font = Enum.Font.FredokaOne,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0,
	})

	-- Parking bay markings. The bay part's CFrame is what the judge measures
	-- against; its -Z points at the cab.
	local bay = decor(
		model,
		deck,
		"ParkingBay",
		Vector3.new(C.BayWidth, 0.05, C.BayLength),
		CFrame.new(0, deckTop + 0.03, -C.BayForwardOffset),
		Color3.fromRGB(255, 220, 40),
		Enum.Material.SmoothPlastic
	)
	bay.Transparency = 0.75
	local lineThickness = 0.35
	for _, spec in
		{
			{ Vector3.new(lineThickness, 0.07, C.BayLength), Vector3.new(-C.BayWidth / 2, 0, 0) },
			{ Vector3.new(lineThickness, 0.07, C.BayLength), Vector3.new(C.BayWidth / 2, 0, 0) },
			{ Vector3.new(C.BayWidth, 0.07, lineThickness), Vector3.new(0, 0, -C.BayLength / 2) },
			{ Vector3.new(C.BayWidth, 0.07, lineThickness), Vector3.new(0, 0, C.BayLength / 2) },
		}
	do
		decor(
			model,
			deck,
			"BayLine",
			spec[1],
			CFrame.new(0, deckTop + 0.04, -C.BayForwardOffset) * CFrame.new(spec[2]),
			Color3.fromRGB(255, 220, 40),
			Enum.Material.Neon
		)
	end
	local bayGui = make("SurfaceGui", bay, {
		Face = Enum.NormalId.Top,
		CanvasSize = Vector2.new(200, 360),
		LightInfluence = 0,
	})
	make("TextLabel", bayGui, {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "PARK",
		TextScaled = true,
		Font = Enum.Font.FredokaOne,
		TextColor3 = Color3.fromRGB(255, 240, 150),
	})

	-- Big marker so the trailer can be found from anywhere
	local marker = make("BillboardGui", bay, {
		Name = "Marker",
		Size = UDim2.fromOffset(160, 60),
		StudsOffsetWorldSpace = Vector3.new(0, 16, 0),
		AlwaysOnTop = true,
		MaxDistance = 5000,
		LightInfluence = 0,
	})
	make("TextLabel", marker, {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "▼ TRAILER ▼",
		TextScaled = true,
		Font = Enum.Font.FredokaOne,
		TextColor3 = Color3.fromRGB(255, 220, 40),
		TextStrokeTransparency = 0,
	})

	local root = make("Attachment", deck, { Name = "DriveAttachment" })
	make("LinearVelocity", deck, {
		Name = "Drive",
		Attachment0 = root,
		MaxForce = math.huge,
		VelocityConstraintMode = Enum.VelocityConstraintMode.Vector,
		RelativeTo = Enum.ActuatorRelativeTo.World,
		VectorVelocity = Vector3.zero,
	})
	make("AlignOrientation", deck, {
		Name = "Steer",
		Attachment0 = root,
		Mode = Enum.OrientationAlignmentMode.OneAttachment,
		MaxTorque = math.huge,
		MaxAngularVelocity = math.huge,
		Responsiveness = 45,
	})

	return model, deck, tailgate, bay
end

function Trailer.new(path: TrackPath): Trailer
	local model, deck, tailgate, bay = buildModel()
	local self = setmetatable({
		path = path,
		model = model,
		deck = deck,
		tailgate = tailgate,
		bay = bay,
		linearVelocity = deck:FindFirstChild("Drive") :: LinearVelocity,
		alignOrientation = deck:FindFirstChild("Steer") :: AlignOrientation,
		distance = 0,
		speed = 0,
		targetSpeed = C.BaseSpeed,
		nextSpeedChange = 0,
		brakeCheckUntil = 0,
		elapsed = 0,
		running = false,
		rng = Random.new(),
		connection = nil :: RBXScriptConnection?,
	}, Trailer)
	model.Parent = Workspace
	self:Reset(0)
	return self
end

function Trailer._targetCFrame(self: Trailer): CFrame
	local base = self.path:CFrameAt(self.distance)
	local t = self.elapsed
	local w = (2 * math.pi) / C.SwayPeriod
	local yaw = math.rad(C.SwayYawDegrees) * math.sin(t * w)
	local roll = math.rad(C.SwayRollDegrees) * math.sin(t * w * 1.37 + 0.8)
	local bank = math.clamp(-self.path:TurnRateAt(self.distance) * self.speed * 0.25, -0.035, 0.035)
	return CFrame.new(base.Position + Vector3.new(0, DECK_CENTER_Y, 0))
		* base.Rotation
		* CFrame.Angles(0, yaw, 0)
		* CFrame.Angles(0, 0, roll + bank)
end

-- Parks the trailer (anchored, stationary) at `distance` along the track.
function Trailer.Reset(self: Trailer, distance: number)
	self:Stop()
	self.distance = self.path:Wrap(distance)
	self.speed = 0
	self.targetSpeed = C.BaseSpeed
	self.elapsed = 0
	self.brakeCheckUntil = 0
	self.deck.Anchored = true
	self.deck.AssemblyLinearVelocity = Vector3.zero
	self.deck.AssemblyAngularVelocity = Vector3.zero
	self.model:PivotTo(self:_targetCFrame())
	self:SetRampLocked(true)
	self.model:SetAttribute("Speed", 0)
end

function Trailer.SetRampLocked(self: Trailer, locked: boolean)
	self.tailgate.CanCollide = locked
	self.tailgate.Transparency = if locked then 0 else 1
	local gui = self.tailgate:FindFirstChildOfClass("SurfaceGui")
	if gui then
		gui.Enabled = locked
	end
	self.model:SetAttribute("RampLocked", locked)
end

function Trailer._pickNewSpeed(self: Trailer)
	local now = self.elapsed
	local interval = C.SpeedChangeInterval
	self.nextSpeedChange = now + self.rng:NextNumber(interval.Min, interval.Max)
	if self.rng:NextNumber() < C.BrakeCheckChance then
		self.targetSpeed = C.BrakeCheckSpeed
		self.brakeCheckUntil = now + 2
		self.nextSpeedChange = now + 2.2
	else
		self.targetSpeed = self.rng:NextNumber(C.MinSpeed, C.MaxSpeed)
	end
end

function Trailer.Start(self: Trailer)
	if self.running then
		return
	end
	self.running = true
	self.deck.Anchored = false
	self.deck:SetNetworkOwner(nil)
	self.speed = 0
	self.targetSpeed = C.BaseSpeed
	self.nextSpeedChange = 8
	self.connection = RunService.Heartbeat:Connect(function(dt)
		self:_step(dt)
	end)
end

function Trailer.Stop(self: Trailer)
	self.running = false
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	if not self.deck.Anchored then
		self.linearVelocity.VectorVelocity = Vector3.zero
	end
end

function Trailer._step(self: Trailer, dt: number)
	self.elapsed += dt
	if self.elapsed >= self.nextSpeedChange then
		self:_pickNewSpeed()
	end

	local rate = if self.elapsed < self.brakeCheckUntil then C.SpeedChangeRate * 4 else C.SpeedChangeRate
	if self.speed < self.targetSpeed then
		self.speed = math.min(self.targetSpeed, self.speed + rate * dt)
	else
		self.speed = math.max(self.targetSpeed, self.speed - rate * dt)
	end
	self.distance = self.path:Wrap(self.distance + self.speed * dt)

	local target = self:_targetCFrame()
	local tangent = self.path:TangentAt(self.distance)
	local correction = target.Position - self.deck.Position
	if correction.Magnitude > 30 then
		correction = correction.Unit * 30
	end
	self.linearVelocity.VectorVelocity = tangent * self.speed + correction * 4
	self.alignOrientation.CFrame = target.Rotation
	self.model:SetAttribute("Speed", math.floor(self.speed + 0.5))
end

function Trailer.GetBayCFrame(self: Trailer): CFrame
	return self.bay.CFrame
end

function Trailer.GetVelocityAt(self: Trailer, position: Vector3): Vector3
	return self.deck:GetVelocityAtPosition(position)
end

return Trailer
