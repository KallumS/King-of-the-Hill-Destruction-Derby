--!strict
-- Fully scripted camera (players have no avatar):
--   Orbit  - slow flyover of the arena for the lobby and car select
--   Follow - smoothed chase cam behind a car or the trailer; used both for
--            your own car and for spectating

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local CAM = Config.Camera

local CameraController = {}

local mode: "Orbit" | "Follow" = "Orbit"
local subject: BasePart? = nil
local subjectIsTrailer = false
local orbitAngle = 0
local yaw = 0
local position: Vector3? = nil

local collisionParams = RaycastParams.new()
collisionParams.FilterType = Enum.RaycastFilterType.Exclude
collisionParams.RespectCanCollide = true

local function lerpAngle(a: number, b: number, t: number): number
	local diff = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + diff * t
end

function CameraController.Orbit()
	mode = "Orbit"
	subject = nil
end

function CameraController.Follow(part: BasePart?, isTrailer: boolean?)
	local changed = part ~= subject or mode ~= "Follow"
	mode = "Follow"
	subject = part
	subjectIsTrailer = isTrailer == true
	if changed then
		position = nil
		if part then
			local look = part.CFrame.LookVector
			yaw = math.atan2(-look.X, -look.Z)
		end
	end
end

function CameraController.GetSubject(): BasePart?
	return subject
end

local function updateOrbit(camera: Camera, dt: number)
	orbitAngle += dt * 0.05
	local radius = 620
	local eye = Vector3.new(math.cos(orbitAngle) * radius, 260, math.sin(orbitAngle) * radius)
	camera.CFrame = CFrame.lookAt(eye, Vector3.new(0, 0, 0))
	camera.FieldOfView = 60
end

local function updateFollow(camera: Camera, dt: number)
	local part = subject
	if not part or not part.Parent then
		updateOrbit(camera, dt)
		return
	end

	local distance = if subjectIsTrailer then CAM.Distance * 3 else CAM.Distance
	local height = if subjectIsTrailer then CAM.Height * 2.5 else CAM.Height

	local cf = part.CFrame
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude > 0.2 then
		local targetYaw = math.atan2(-flat.X, -flat.Z)
		yaw = lerpAngle(yaw, targetYaw, 1 - math.exp(-CAM.Stiffness * dt))
	end
	local back = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
	local focus = part.Position + Vector3.new(0, CAM.LookHeight, 0)
	local desired = focus + back * distance + Vector3.new(0, height, 0)

	-- Keep the camera out of walls and obstacles
	local filter: { Instance } = {}
	local cars = Workspace:FindFirstChild("Cars")
	if cars then
		table.insert(filter, cars)
	end
	local trailer = Workspace:FindFirstChild("Trailer")
	if trailer then
		table.insert(filter, trailer)
	end
	collisionParams.FilterDescendantsInstances = filter
	local offset = desired - focus
	local hit = Workspace:Raycast(focus, offset, collisionParams)
	if hit then
		desired = hit.Position - offset.Unit * 1.5
	end

	local previous = position
	local eye = if previous then previous:Lerp(desired, 1 - math.exp(-14 * dt)) else desired
	position = eye
	camera.CFrame = CFrame.lookAt(eye, focus)

	local speed = part.AssemblyLinearVelocity.Magnitude
	local targetFov = CAM.FovBase + CAM.FovSpeedBonus * math.clamp(speed / Config.Vehicle.MaxSpeed, 0, 1.2)
	camera.FieldOfView += (targetFov - camera.FieldOfView) * (1 - math.exp(-4 * dt))
end

function CameraController.Init()
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable

	RunService:BindToRenderStep("DerbyCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local current = Workspace.CurrentCamera
		if not current then
			return
		end
		current.CameraType = Enum.CameraType.Scriptable
		if mode == "Orbit" then
			updateOrbit(current, dt)
		else
			updateFollow(current, dt)
		end
	end)
end

return CameraController
