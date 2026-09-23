--!strict
-- Cosmetic per-frame animation for every car in the match, run locally on
-- each client: suspension travel, wheel spin, front-wheel steer and tyre
-- smoke while sliding. Nothing here affects physics.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local CarController = require(script.Parent:WaitForChild("CarController"))

local V = Config.Vehicle
local RAY_LENGTH = V.RestLength + V.WheelRadius
local MAX_DISTANCE = 350
local MAX_STEER = math.rad(28)

type WheelInfo = {
	part: BasePart,
	weld: Weld,
	x: number,
	z: number,
	front: boolean,
	smoke: ParticleEmitter?,
	spin: number,
}

type CarInfo = {
	wheels: { WheelInfo },
	params: RaycastParams,
}

local VehicleVisuals = {}

local cache: { [Model]: CarInfo } = {}

local function collect(model: Model): CarInfo?
	local folder = model:FindFirstChild("Wheels")
	if not folder then
		return nil
	end
	local wheels: { WheelInfo } = {}
	for _, wheel in folder:GetChildren() do
		if not wheel:IsA("BasePart") then
			continue
		end
		local weld = wheel:FindFirstChild("WheelWeld")
		if not weld or not weld:IsA("Weld") then
			continue
		end
		local attachment = wheel:FindFirstChild("SmokeAttachment")
		local smoke = attachment and attachment:FindFirstChild("TyreSmoke")
		table.insert(wheels, {
			part = wheel,
			weld = weld,
			x = (wheel:GetAttribute("BaseX") :: number?) or 0,
			z = (wheel:GetAttribute("BaseZ") :: number?) or 0,
			front = wheel:GetAttribute("Front") == true,
			smoke = if smoke and smoke:IsA("ParticleEmitter") then smoke else nil,
			spin = 0,
		})
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	return { wheels = wheels, params = params }
end

local function animate(model: Model, info: CarInfo, dt: number, cameraPosition: Vector3)
	local chassis = model.PrimaryPart
	if not chassis then
		return
	end
	if (chassis.Position - cameraPosition).Magnitude > MAX_DISTANCE then
		return
	end
	local destroyed = model:GetAttribute("Destroyed") == true
	local isLocal = CarController.State.model == model

	local cf = chassis.CFrame
	local velocity = chassis.AssemblyLinearVelocity
	local forwardSpeed = velocity:Dot(cf.LookVector)
	local lateralSpeed = math.abs(velocity:Dot(cf.RightVector))

	local steer: number
	if isLocal then
		steer = CarController.State.steer
	else
		local yawRate = cf:VectorToObjectSpace(chassis.AssemblyAngularVelocity).Y
		steer = math.clamp(-yawRate / 2, -1, 1)
	end

	local sliding = not destroyed
		and (if isLocal then CarController.State.drifting else lateralSpeed > 16 and math.abs(forwardSpeed) > 15)

	for _, wheel in info.wheels do
		local distance: number
		if isLocal and CarController.State.wheelDistance[wheel.part.Name] then
			distance = CarController.State.wheelDistance[wheel.part.Name]
		else
			local rayX = math.sign(wheel.x) * V.WheelOffsetX
			local origin = cf:PointToWorldSpace(Vector3.new(rayX, 0, wheel.z))
			local result = Workspace:Raycast(origin, -cf.UpVector * RAY_LENGTH, info.params)
			distance = if result then result.Distance else RAY_LENGTH
		end
		local grounded = distance < RAY_LENGTH - 0.05
		local y = math.clamp(-distance + V.WheelRadius, -RAY_LENGTH + V.WheelRadius, -0.3)

		wheel.spin = (wheel.spin - forwardSpeed / V.WheelRadius * dt) % (math.pi * 2)
		local steerAngle = if wheel.front then -steer * MAX_STEER else 0
		wheel.weld.C0 = CFrame.new(wheel.x, y, wheel.z)
			* CFrame.Angles(0, steerAngle, 0)
			* CFrame.Angles(wheel.spin, 0, 0)

		if wheel.smoke then
			wheel.smoke.Enabled = sliding and grounded
		end
	end
end

function VehicleVisuals.Init()
	local carsFolder = Workspace:WaitForChild("Cars")

	carsFolder.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			cache[child] = nil
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
		for _, model in carsFolder:GetChildren() do
			if not model:IsA("Model") then
				continue
			end
			local info = cache[model]
			if not info then
				info = collect(model)
				if not info then
					continue
				end
				cache[model] = info
			end
			animate(model, info, dt, cameraPosition)
		end
	end)
end

return VehicleVisuals
