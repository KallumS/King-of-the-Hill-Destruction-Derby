--!strict
-- Builds the arena procedurally so the place works straight from Rojo with
-- no binary assets: grass ground, an asphalt loop for the trailer, perimeter
-- walls, grandstands and derby junk scattered off the racing line.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TrackPath = require(Shared:WaitForChild("TrackPath"))

type TrackPath = TrackPath.TrackPath

local T = Config.Track

local MapBuilder = {}

local function part(props: {
	Name: string,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3,
	Material: Enum.Material?,
	CanCollide: boolean?,
	Shape: Enum.PartType?,
	Parent: Instance,
}): Part
	local p = Instance.new("Part")
	p.Name = props.Name
	p.Anchored = true
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Color = props.Color
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape then
		p.Shape = props.Shape
	end
	p.Parent = props.Parent
	return p
end

local function buildGround(folder: Folder, walls: Folder)
	local size = T.GroundSize
	local ground = part({
		Name = "Ground",
		Size = Vector3.new(size, 4, size),
		CFrame = CFrame.new(0, -2, 0),
		Color = Color3.fromRGB(88, 128, 60),
		Material = Enum.Material.Grass,
		Parent = folder,
	})
	CollectionService:AddTag(ground, "Ground")

	-- Perimeter wall
	local half = size / 2
	local wallHeight = 24
	for _, spec in
		{
			{ Vector3.new(0, 0, -half), Vector3.new(size + 8, wallHeight, 8) },
			{ Vector3.new(0, 0, half), Vector3.new(size + 8, wallHeight, 8) },
			{ Vector3.new(-half, 0, 0), Vector3.new(8, wallHeight, size + 8) },
			{ Vector3.new(half, 0, 0), Vector3.new(8, wallHeight, size + 8) },
		}
	do
		local pos, wallSize = spec[1] :: Vector3, spec[2] :: Vector3
		part({
			Name = "ArenaWall",
			Size = wallSize,
			CFrame = CFrame.new(pos + Vector3.new(0, wallHeight / 2, 0)),
			Color = Color3.fromRGB(150, 150, 155),
			Material = Enum.Material.Concrete,
			Parent = walls,
		})
		-- Hazard stripe along the top
		part({
			Name = "WallStripe",
			Size = wallSize + Vector3.new(0.2, -wallHeight + 2, 0.2),
			CFrame = CFrame.new(pos + Vector3.new(0, wallHeight - 1, 0)),
			Color = Color3.fromRGB(240, 190, 20),
			Material = Enum.Material.SmoothPlastic,
			Parent = walls,
		})
	end
end

local function buildRoad(folder: Folder, path: TrackPath)
	local spacing = T.SampleSpacing
	local count = math.floor(path.totalLength / spacing)
	local step = path.totalLength / count
	local asphalt = Color3.fromRGB(58, 58, 62)
	for i = 0, count - 1 do
		local d0 = i * step
		local d1 = (i + 1) * step
		local a = path:PositionAt(d0)
		local b = path:PositionAt(d1)
		local mid = (a + b) / 2
		local length = (b - a).Magnitude
		local cf = CFrame.lookAt(mid, b)

		local road = part({
			Name = "Road",
			Size = Vector3.new(T.Width, 0.2, length + 0.4),
			CFrame = cf * CFrame.new(0, -0.05, 0),
			Color = asphalt,
			Material = Enum.Material.Asphalt,
			CanCollide = false,
			Parent = folder,
		})
		road.CanTouch = false
		CollectionService:AddTag(road, "Ground")

		-- Disc at each joint fills the wedge-shaped gap on the outside of bends.
		local disc = part({
			Name = "RoadJoint",
			Size = Vector3.new(0.2, T.Width, T.Width),
			CFrame = CFrame.new(a + Vector3.new(0, -0.05, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = asphalt,
			Material = Enum.Material.Asphalt,
			CanCollide = false,
			Shape = Enum.PartType.Cylinder,
			Parent = folder,
		})
		disc.CanTouch = false
		CollectionService:AddTag(disc, "Ground")

		-- Red/white kerbs on both edges
		local kerbColor = if i % 2 == 0 then Color3.fromRGB(210, 40, 40) else Color3.fromRGB(240, 240, 240)
		for _, side in { -1, 1 } do
			local kerb = part({
				Name = "Kerb",
				Size = Vector3.new(2.5, 0.25, length + 0.2),
				CFrame = cf * CFrame.new(side * (T.Width / 2 + 1.25), -0.02, 0),
				Color = kerbColor,
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				Parent = folder,
			})
			kerb.CanQuery = false
			kerb.CanTouch = false
		end
	end

	-- Checkered start line
	local startCf = path:CFrameAt(T.GridStartDistance + 14)
	local squares = 14
	local squareSize = T.Width / squares
	for row = 0, 1 do
		for col = 0, squares - 1 do
			local x = -T.Width / 2 + squareSize * (col + 0.5)
			local square = part({
				Name = "StartLine",
				Size = Vector3.new(squareSize, 0.22, squareSize),
				CFrame = startCf * CFrame.new(x, -0.02, (row - 0.5) * squareSize),
				Color = if (row + col) % 2 == 0 then Color3.new(1, 1, 1) else Color3.new(0.05, 0.05, 0.05),
				CanCollide = false,
				Parent = folder,
			})
			square.CanQuery = false
			square.CanTouch = false
		end
	end
end

local function buildGrandstand(folder: Folder, cframe: CFrame, length: number)
	local crowdColors = {
		Color3.fromRGB(220, 60, 60),
		Color3.fromRGB(60, 120, 220),
		Color3.fromRGB(240, 200, 40),
		Color3.fromRGB(240, 240, 240),
		Color3.fromRGB(60, 180, 90),
	}
	local rng = Random.new(7)
	for stepIndex = 0, 5 do
		local stepCf = cframe * CFrame.new(0, 2 + stepIndex * 4, stepIndex * 6)
		part({
			Name = "Grandstand",
			Size = Vector3.new(length, 4 + stepIndex * 8, 6),
			CFrame = stepCf * CFrame.new(0, -stepIndex * 4, 0),
			Color = Color3.fromRGB(120, 120, 128),
			Material = Enum.Material.Concrete,
			Parent = folder,
		})
		-- Spectators as coloured blocks
		for x = -length / 2 + 3, length / 2 - 3, 4 do
			if rng:NextNumber() < 0.75 then
				local fan = part({
					Name = "Fan",
					Size = Vector3.new(1.8, 3, 1.4),
					CFrame = stepCf * CFrame.new(x, 3.5, 0),
					Color = crowdColors[rng:NextInteger(1, #crowdColors)],
					CanCollide = false,
					Parent = folder,
				})
				fan.CanQuery = false
				fan.CanTouch = false
			end
		end
	end
end

local function farFromTrack(path: TrackPath, position: Vector3, margin: number): boolean
	local _, distance = path:ClosestDistance(position)
	return distance > T.Width / 2 + margin
end

local function buildObstacles(folder: Folder, path: TrackPath)
	local rng = Random.new(1337)
	local limit = T.GroundSize / 2 - 40
	local placed = 0
	local attempts = 0
	while placed < 34 and attempts < 600 do
		attempts += 1
		local position = Vector3.new(rng:NextNumber(-limit, limit), 0, rng:NextNumber(-limit, limit))
		if farFromTrack(path, position, 18) then
			placed += 1
			local yaw = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
			local kind = rng:NextInteger(1, 3)
			if kind == 1 then
				-- Tyre stack
				local height = rng:NextInteger(3, 5)
				for level = 0, height - 1 do
					part({
						Name = "TyreStack",
						Size = Vector3.new(1.6, 5, 5),
						CFrame = CFrame.new(position + Vector3.new(0, 0.8 + level * 1.6, 0))
							* CFrame.Angles(0, 0, math.pi / 2),
						Color = Color3.fromRGB(30, 30, 32),
						Material = Enum.Material.Rubber,
						Shape = Enum.PartType.Cylinder,
						Parent = folder,
					})
				end
			elseif kind == 2 then
				-- Dirt jump
				local ramp = Instance.new("WedgePart")
				ramp.Name = "DirtJump"
				ramp.Anchored = true
				ramp.Size = Vector3.new(16, 5, 18)
				ramp.CFrame = CFrame.new(position + Vector3.new(0, 2.5, 0)) * yaw
				ramp.Color = Color3.fromRGB(120, 84, 52)
				ramp.Material = Enum.Material.Ground
				ramp.Parent = folder
				part({
					Name = "DirtJumpTop",
					Size = Vector3.new(16, 5, 6),
					CFrame = ramp.CFrame * CFrame.new(0, 0, 12),
					Color = Color3.fromRGB(120, 84, 52),
					Material = Enum.Material.Ground,
					Parent = folder,
				})
			else
				-- Abandoned wreck
				local wreckColor = Color3.fromHSV(rng:NextNumber(), 0.4, 0.4)
				local base = part({
					Name = "Wreck",
					Size = Vector3.new(7, 3, 13),
					CFrame = CFrame.new(position + Vector3.new(0, 1.5, 0)) * yaw,
					Color = wreckColor,
					Material = Enum.Material.CorrodedMetal,
					Parent = folder,
				})
				part({
					Name = "WreckCabin",
					Size = Vector3.new(6, 2, 6),
					CFrame = base.CFrame
						* CFrame.new(0, 2.5, 1)
						* CFrame.Angles(0, 0, math.rad(rng:NextNumber(-12, 12))),
					Color = wreckColor,
					Material = Enum.Material.CorrodedMetal,
					Parent = folder,
				})
			end
		end
	end
end

local function buildLighting()
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.28
		atmosphere.Haze = 1.2
		atmosphere.Color = Color3.fromRGB(199, 170, 140)
		atmosphere.Decay = Color3.fromRGB(106, 90, 80)
		atmosphere.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("Sky") then
		Instance.new("Sky").Parent = Lighting
	end
end

function MapBuilder.Build(path: TrackPath): Folder
	local existing = Workspace:FindFirstChild("Arena")
	if existing then
		existing:Destroy()
	end

	local arena = Instance.new("Folder")
	arena.Name = "Arena"

	local surface = Instance.new("Folder")
	surface.Name = "Surface"
	surface.Parent = arena
	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	walls.Parent = arena
	buildGround(surface, walls)
	buildRoad(surface, path)

	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = arena
	local half = T.GroundSize / 2
	buildGrandstand(decor, CFrame.new(0, 0, -half - 8) * CFrame.Angles(0, math.pi, 0), 300)
	buildGrandstand(decor, CFrame.new(0, 0, half + 8), 300)

	local obstacles = Instance.new("Folder")
	obstacles.Name = "Obstacles"
	obstacles.Parent = arena
	buildObstacles(obstacles, path)

	buildLighting()

	arena.Parent = Workspace
	return arena
end

return MapBuilder
