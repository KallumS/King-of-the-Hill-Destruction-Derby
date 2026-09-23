--!strict
-- Builds a derby car Model from a CarCatalog entry.
--
-- Only the "Chassis" part collides or has mass; everything else is a massless,
-- non-colliding visual welded to it. That keeps the physics identical for all
-- five bodies. The chassis front faces -Z.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CarCatalog = require(Shared:WaitForChild("CarCatalog"))

type CarDefinition = CarCatalog.CarDefinition

local V = Config.Vehicle

local CarBuilder = {}

local GLASS = Color3.fromRGB(30, 38, 48)
local METAL_DARK = Color3.fromRGB(45, 45, 50)
local TIRE = Color3.fromRGB(28, 28, 30)
local RIM = Color3.fromRGB(170, 170, 175)

local function visual(
	parent: Instance,
	chassis: BasePart,
	props: {
		Name: string?,
		Size: Vector3,
		Offset: CFrame,
		Color: Color3,
		Material: Enum.Material?,
		Shape: Enum.PartType?,
		Transparency: number?,
		Wedge: boolean?,
	}
): BasePart
	local part: BasePart
	if props.Wedge then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		if props.Shape then
			p.Shape = props.Shape
		end
		part = p
	end
	part.Name = props.Name or "Body"
	part.Size = props.Size
	part.Color = props.Color
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Transparency = props.Transparency or 0
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = chassis.CFrame * props.Offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = chassis
	weld.Part1 = part
	weld.Parent = part
	part.Parent = parent
	return part
end

local function addNumber(parent: Instance, chassis: BasePart, number: number, def: CarDefinition, y: number, z: number)
	-- Roof number panel, readable from above and from the chase cam.
	local panel = visual(parent, chassis, {
		Name = "NumberPanel",
		Size = Vector3.new(3.4, 0.1, 3.4),
		Offset = CFrame.new(0, y, z),
		Color = Color3.new(1, 1, 1),
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.CanvasSize = Vector2.new(200, 200)
	gui.LightInfluence = 0.5
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = tostring(number)
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = def.AccentColor
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Parent = gui
	gui.Parent = panel

	-- Door numbers on both sides
	for _, side in { -1, 1 } do
		local door = visual(parent, chassis, {
			Name = "DoorNumber",
			Size = Vector3.new(0.1, 1.8, 2.4),
			Offset = CFrame.new(side * (V.ChassisSize.X / 2 + 0.06), 0.1, -0.4),
			Color = Color3.new(1, 1, 1),
		})
		local doorGui = Instance.new("SurfaceGui")
		doorGui.Face = if side > 0 then Enum.NormalId.Right else Enum.NormalId.Left
		doorGui.CanvasSize = Vector2.new(160, 120)
		doorGui.LightInfluence = 0.5
		local doorLabel = label:Clone()
		doorLabel.Parent = doorGui
		doorGui.Parent = door
	end
end

local function addWheels(model: Model, chassis: BasePart)
	local wheels = Instance.new("Folder")
	wheels.Name = "Wheels"
	wheels.Parent = model
	local restY = -(V.RestLength + V.WheelRadius) + V.WheelRadius + 0.9
	for _, spec in
		{
			{ "FL", -1, -1 },
			{ "FR", 1, -1 },
			{ "RL", -1, 1 },
			{ "RR", 1, 1 },
		}
	do
		local name, sx, sz = spec[1] :: string, spec[2] :: number, spec[3] :: number
		local x = sx * (V.WheelOffsetX + 0.55)
		local z = sz * V.WheelOffsetZ

		local wheel = Instance.new("Part")
		wheel.Name = name
		wheel.Shape = Enum.PartType.Cylinder
		wheel.Size = Vector3.new(1.3, V.WheelRadius * 2, V.WheelRadius * 2)
		wheel.Color = TIRE
		wheel.Material = Enum.Material.Rubber
		wheel.CanCollide = false
		wheel.CanQuery = false
		wheel.CanTouch = false
		wheel.Massless = true

		local rim = Instance.new("Part")
		rim.Name = "Rim"
		rim.Shape = Enum.PartType.Cylinder
		rim.Size = Vector3.new(1.35, V.WheelRadius * 1.1, V.WheelRadius * 1.1)
		rim.Color = RIM
		rim.Material = Enum.Material.Metal
		rim.CanCollide = false
		rim.CanQuery = false
		rim.CanTouch = false
		rim.Massless = true

		-- The Weld's C0 is animated on clients by VehicleVisuals (suspension + spin + steer).
		local weld = Instance.new("Weld")
		weld.Name = "WheelWeld"
		weld.Part0 = chassis
		weld.Part1 = wheel
		weld.C0 = CFrame.new(x, restY, z)
		weld.Parent = wheel
		wheel:SetAttribute("BaseX", x)
		wheel:SetAttribute("BaseZ", z)
		wheel:SetAttribute("Front", sz < 0)
		wheel.CFrame = chassis.CFrame * weld.C0
		wheel.Parent = wheels

		rim.CFrame = wheel.CFrame
		local rimWeld = Instance.new("WeldConstraint")
		rimWeld.Part0 = wheel
		rimWeld.Part1 = rim
		rimWeld.Parent = rim
		rim.Parent = wheel

		if sz > 0 then
			-- Tyre smoke emitter at each rear wheel; toggled on clients while sliding.
			local attachment = Instance.new("Attachment")
			attachment.Name = "SmokeAttachment"
			attachment.Position = Vector3.new(0, -V.WheelRadius * 0.8, 0)
			attachment.Parent = wheel
			local smoke = Instance.new("ParticleEmitter")
			smoke.Name = "TyreSmoke"
			smoke.Enabled = false
			smoke.Rate = 45
			smoke.Lifetime = NumberRange.new(0.6, 1.1)
			smoke.Speed = NumberRange.new(2, 5)
			smoke.SpreadAngle = Vector2.new(35, 35)
			smoke.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1.2),
				NumberSequenceKeypoint.new(1, 4.5),
			})
			smoke.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(1, 1),
			})
			smoke.Color = ColorSequence.new(Color3.fromRGB(225, 225, 225))
			smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
			smoke.Parent = attachment
		end
	end
end

local function addDamageEffects(chassis: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Name = "EngineAttachment"
	attachment.Position = Vector3.new(0, V.ChassisSize.Y / 2 + 0.5, -V.ChassisSize.Z / 2 + 2.5)
	attachment.Parent = chassis

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "DamageSmoke"
	smoke.Enabled = false
	smoke.Rate = 18
	smoke.Lifetime = NumberRange.new(1.2, 2)
	smoke.Speed = NumberRange.new(4, 7)
	smoke.SpreadAngle = Vector2.new(15, 15)
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.5),
		NumberSequenceKeypoint.new(1, 6),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Color = ColorSequence.new(Color3.fromRGB(60, 60, 60))
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Parent = attachment

	local fire = Instance.new("Fire")
	fire.Name = "DamageFire"
	fire.Enabled = false
	fire.Size = 6
	fire.Heat = 12
	fire.Parent = attachment
end

-- Shared derby touches: front push bar, rear bumper, headlights and the car number.
local function addNumberAndBars(model: Model, chassis: BasePart, def: CarDefinition, roofY: number, roofZ: number)
	if def.Style ~= "Pickup" then
		visual(model, chassis, {
			Name = "PushBar",
			Size = Vector3.new(7.6, 1.0, 0.8),
			Offset = CFrame.new(0, -0.1, -6.9),
			Color = METAL_DARK,
			Material = Enum.Material.DiamondPlate,
		})
	end
	visual(model, chassis, {
		Name = "RearBumper",
		Size = Vector3.new(7.4, 0.8, 0.6),
		Offset = CFrame.new(0, -0.3, 6.8),
		Color = METAL_DARK,
		Material = Enum.Material.Metal,
	})
	for _, side in { -1, 1 } do
		local lamp = visual(model, chassis, {
			Name = "Headlight",
			Size = Vector3.new(1.2, 0.6, 0.2),
			Offset = CFrame.new(side * 2.4, 0.6, -6.55),
			Color = Color3.fromRGB(255, 250, 220),
			Material = Enum.Material.Neon,
		})
		lamp:SetAttribute("Lamp", true)
		visual(model, chassis, {
			Name = "Taillight",
			Size = Vector3.new(1.2, 0.5, 0.2),
			Offset = CFrame.new(side * 2.6, 0.6, 6.55),
			Color = Color3.fromRGB(200, 20, 20),
			Material = Enum.Material.Neon,
		})
	end
	local number = model:GetAttribute("CarNumber")
	addNumber(model, chassis, if typeof(number) == "number" then number else 0, def, roofY, roofZ)
end

local function buildSedan(model: Model, chassis: BasePart, def: CarDefinition)
	visual(model, chassis, {
		Name = "Cabin",
		Size = Vector3.new(6.2, 2.3, 5.6),
		Offset = CFrame.new(0, 2.45, 0.8),
		Color = def.BodyColor,
		Material = Enum.Material.CorrodedMetal,
	})
	visual(model, chassis, {
		Name = "Windshield",
		Size = Vector3.new(6.0, 2.2, 1.8),
		Offset = CFrame.new(0, 2.4, -2.9),
		Color = GLASS,
		Material = Enum.Material.Glass,
		Transparency = 0.25,
		Wedge = true,
	})
	visual(model, chassis, {
		Name = "RearGlass",
		Size = Vector3.new(6.0, 2.2, 1.4),
		Offset = CFrame.new(0, 2.4, 4.3) * CFrame.Angles(0, math.pi, 0),
		Color = GLASS,
		Material = Enum.Material.Glass,
		Transparency = 0.25,
		Wedge = true,
	})
	for _, side in { -1, 1 } do
		visual(model, chassis, {
			Name = "SideWindow",
			Size = Vector3.new(0.1, 1.4, 4.6),
			Offset = CFrame.new(side * 3.12, 2.55, 0.8),
			Color = GLASS,
			Material = Enum.Material.Glass,
			Transparency = 0.2,
		})
	end
	-- Rust patches
	visual(model, chassis, {
		Name = "RustPatch",
		Size = Vector3.new(3, 0.15, 2.4),
		Offset = CFrame.new(-1.2, 1.36, -4.5),
		Color = def.AccentColor,
		Material = Enum.Material.CorrodedMetal,
	})
	addNumberAndBars(model, chassis, def, 3.64, 0.8)
end

local function buildPickup(model: Model, chassis: BasePart, def: CarDefinition)
	visual(model, chassis, {
		Name = "Cab",
		Size = Vector3.new(6.4, 2.8, 4.4),
		Offset = CFrame.new(0, 2.7, -0.6),
		Color = def.BodyColor,
		Material = Enum.Material.Metal,
	})
	visual(model, chassis, {
		Name = "Windshield",
		Size = Vector3.new(6.2, 2.5, 1.2),
		Offset = CFrame.new(0, 2.55, -3.4),
		Color = GLASS,
		Material = Enum.Material.Glass,
		Transparency = 0.25,
		Wedge = true,
	})
	-- Bed walls
	for _, side in { -1, 1 } do
		visual(model, chassis, {
			Name = "BedWall",
			Size = Vector3.new(0.4, 1.3, 5.2),
			Offset = CFrame.new(side * 3.3, 1.95, 3.8),
			Color = def.BodyColor,
			Material = Enum.Material.Metal,
		})
	end
	visual(model, chassis, {
		Name = "Tailgate",
		Size = Vector3.new(7, 1.3, 0.4),
		Offset = CFrame.new(0, 1.95, 6.3),
		Color = def.AccentColor,
		Material = Enum.Material.Metal,
	})
	-- Big bull bar
	visual(model, chassis, {
		Name = "BullBar",
		Size = Vector3.new(7.8, 2.4, 0.7),
		Offset = CFrame.new(0, 0.6, -7.0),
		Color = def.AccentColor,
		Material = Enum.Material.DiamondPlate,
	})
	-- Roll bar over the bed
	visual(model, chassis, {
		Name = "RollBar",
		Size = Vector3.new(6.6, 0.5, 0.5),
		Offset = CFrame.new(0, 3.3, 1.8),
		Color = METAL_DARK,
		Material = Enum.Material.Metal,
	})
	addNumberAndBars(model, chassis, def, 4.14, -0.6)
end

local function buildWagon(model: Model, chassis: BasePart, def: CarDefinition)
	visual(model, chassis, {
		Name = "Cabin",
		Size = Vector3.new(6.2, 2.4, 9),
		Offset = CFrame.new(0, 2.5, 1.8),
		Color = def.BodyColor,
		Material = Enum.Material.SmoothPlastic,
	})
	visual(model, chassis, {
		Name = "Windshield",
		Size = Vector3.new(6.0, 2.3, 1.6),
		Offset = CFrame.new(0, 2.45, -3.45),
		Color = GLASS,
		Material = Enum.Material.Glass,
		Transparency = 0.25,
		Wedge = true,
	})
	for _, side in { -1, 1 } do
		visual(model, chassis, {
			Name = "WoodPanel",
			Size = Vector3.new(0.12, 1.1, 10),
			Offset = CFrame.new(side * 3.55, 0.2, 0.8),
			Color = def.AccentColor,
			Material = Enum.Material.Wood,
		})
		visual(model, chassis, {
			Name = "SideWindow",
			Size = Vector3.new(0.1, 1.4, 8),
			Offset = CFrame.new(side * 3.12, 2.6, 1.8),
			Color = GLASS,
			Material = Enum.Material.Glass,
			Transparency = 0.2,
		})
	end
	-- Roof rack with a spare tyre
	visual(model, chassis, {
		Name = "RoofRack",
		Size = Vector3.new(5.4, 0.3, 6.5),
		Offset = CFrame.new(0, 3.85, 2.3),
		Color = METAL_DARK,
		Material = Enum.Material.Metal,
	})
	visual(model, chassis, {
		Name = "SpareTyre",
		Size = Vector3.new(0.9, 2.6, 2.6),
		Offset = CFrame.new(0, 4.4, 4.1) * CFrame.Angles(0, 0, math.pi / 2),
		Color = TIRE,
		Material = Enum.Material.Rubber,
		Shape = Enum.PartType.Cylinder,
	})
	addNumberAndBars(model, chassis, def, 4.02, 0.2)
end

local function buildTaxi(model: Model, chassis: BasePart, def: CarDefinition)
	visual(model, chassis, {
		Name = "Cabin",
		Size = Vector3.new(6.2, 2.3, 6),
		Offset = CFrame.new(0, 2.45, 0.6),
		Color = def.BodyColor,
		Material = Enum.Material.SmoothPlastic,
	})
	visual(model, chassis, {
		Name = "Windshield",
		Size = Vector3.new(6.0, 2.2, 1.6),
		Offset = CFrame.new(0, 2.4, -3.2),
		Color = GLASS,
		Material = Enum.Material.Glass,
		Transparency = 0.25,
		Wedge = true,
	})
	for _, side in { -1, 1 } do
		visual(model, chassis, {
			Name = "SideWindow",
			Size = Vector3.new(0.1, 1.4, 5),
			Offset = CFrame.new(side * 3.12, 2.55, 0.6),
			Color = GLASS,
			Material = Enum.Material.Glass,
			Transparency = 0.2,
		})
		-- Checker stripe: alternating squares along the flank
		for i = 0, 7 do
			visual(model, chassis, {
				Name = "Checker",
				Size = Vector3.new(0.1, 0.6, 1.2),
				Offset = CFrame.new(side * 3.53, if i % 2 == 0 then -0.55 else -0.0, -4.2 + i * 1.2),
				Color = def.AccentColor,
			})
		end
	end
	local sign = visual(model, chassis, {
		Name = "TaxiSign",
		Size = Vector3.new(3.2, 1, 1.2),
		Offset = CFrame.new(0, 4.1, -0.6),
		Color = Color3.fromRGB(255, 240, 180),
		Material = Enum.Material.Neon,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 120)
	light.Range = 10
	light.Brightness = 1.5
	light.Parent = sign
	addNumberAndBars(model, chassis, def, 3.64, 2.3)
end

local function buildMuscle(model: Model, chassis: BasePart, def: CarDefinition)
	visual(model, chassis, {
		Name = "Cabin",
		Size = Vector3.new(6.0, 1.9, 4.6),
		Offset = CFrame.new(0, 2.25, 1.6),
		Color = def.BodyColor,
		Material = Enum.Material.SmoothPlastic,
	})
	visual(model, chassis, {
		Name = "Windshield",
		Size = Vector3.new(5.8, 1.8, 2.2),
		Offset = CFrame.new(0, 2.2, -1.8),
		Color = GLASS,
		Material = Enum.Material.Glass,
		Transparency = 0.25,
		Wedge = true,
	})
	-- Racing stripes
	for _, x in { -0.9, 0.9 } do
		visual(model, chassis, {
			Name = "Stripe",
			Size = Vector3.new(0.9, 0.1, 13),
			Offset = CFrame.new(x, 1.33, 0),
			Color = Color3.new(1, 1, 1),
		})
	end
	-- Supercharger blower through the hood
	visual(model, chassis, {
		Name = "Blower",
		Size = Vector3.new(2.4, 1.4, 2.4),
		Offset = CFrame.new(0, 2.0, -4.2),
		Color = Color3.fromRGB(190, 190, 195),
		Material = Enum.Material.Metal,
	})
	visual(model, chassis, {
		Name = "Scoop",
		Size = Vector3.new(2.0, 0.8, 1.6),
		Offset = CFrame.new(0, 3.0, -4.2),
		Color = def.AccentColor,
		Material = Enum.Material.Metal,
	})
	-- Rear spoiler
	visual(model, chassis, {
		Name = "Spoiler",
		Size = Vector3.new(7.2, 0.3, 1.6),
		Offset = CFrame.new(0, 2.6, 5.9),
		Color = def.AccentColor,
		Material = Enum.Material.SmoothPlastic,
	})
	for _, side in { -1, 1 } do
		visual(model, chassis, {
			Name = "SpoilerPost",
			Size = Vector3.new(0.3, 1.2, 0.3),
			Offset = CFrame.new(side * 2.8, 1.9, 5.9),
			Color = def.AccentColor,
		})
		visual(model, chassis, {
			Name = "Exhaust",
			Size = Vector3.new(2, 0.5, 0.5),
			Offset = CFrame.new(side * 2.2, -0.9, 6.9) * CFrame.Angles(0, math.pi / 2, 0),
			Color = Color3.fromRGB(150, 150, 155),
			Material = Enum.Material.Metal,
			Shape = Enum.PartType.Cylinder,
		})
	end
	addNumberAndBars(model, chassis, def, 3.24, 1.6)
end

local builders: { [string]: (Model, BasePart, CarDefinition) -> () } = {
	Sedan = buildSedan,
	Pickup = buildPickup,
	Wagon = buildWagon,
	Taxi = buildTaxi,
	Muscle = buildMuscle,
}

--[[
	Builds a car at `cframe` (the chassis centre). The model is returned
	unparented with its chassis anchored; callers unanchor it when the race
	starts.
]]
function CarBuilder.Build(def: CarDefinition, cframe: CFrame, carNumber: number): Model
	local model = Instance.new("Model")
	model.Name = def.Id
	model:SetAttribute("CarId", def.Id)
	model:SetAttribute("CarNumber", carNumber)

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = V.ChassisSize
	chassis.CFrame = cframe
	chassis.Color = def.BodyColor
	chassis.Material = if def.Style == "Sedan" then Enum.Material.CorrodedMetal else Enum.Material.Metal
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	chassis.CustomPhysicalProperties = PhysicalProperties.new(V.Density, 0.25, 0.25, 1, 1)
	chassis.Anchored = true
	chassis.Parent = model
	model.PrimaryPart = chassis

	local builder = builders[def.Style] or buildSedan
	builder(model, chassis, def)
	addWheels(model, chassis)
	addDamageEffects(chassis)

	return model
end

-- Cosmetic-only copy for UI previews (ViewportFrames); no scripts rely on it.
function CarBuilder.BuildPreview(def: CarDefinition): Model
	local model = CarBuilder.Build(def, CFrame.new(), 0)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	return model
end

return CarBuilder
