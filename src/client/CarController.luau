--!strict
-- Drives the local player's car. The server hands the chassis's network
-- ownership to this client, so all vehicle physics runs here for zero-lag
-- handling:
--
--   * raycast suspension, one spring/damper per wheel
--   * arcade drive model working in the frame of whatever is under the
--     wheels, so driving on the moving trailer feels like driving on the road
--   * handbrake drift: rear grip collapses, steering gets sharper, and a held
--     drift charges a short boost that fires when the handbrake is released
--
-- Every car shares Config.Vehicle, so all five bodies handle identically.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local InputState = require(script.Parent:WaitForChild("InputState"))

local V = Config.Vehicle

local OFFROAD: { [Enum.Material]: boolean } = {
	[Enum.Material.Grass] = true,
	[Enum.Material.Ground] = true,
	[Enum.Material.Mud] = true,
	[Enum.Material.Sand] = true,
	[Enum.Material.LeafyGrass] = true,
}

local WHEELS = {
	{ name = "FL", offset = Vector3.new(-V.WheelOffsetX, 0, -V.WheelOffsetZ) },
	{ name = "FR", offset = Vector3.new(V.WheelOffsetX, 0, -V.WheelOffsetZ) },
	{ name = "RL", offset = Vector3.new(-V.WheelOffsetX, 0, V.WheelOffsetZ) },
	{ name = "RR", offset = Vector3.new(V.WheelOffsetX, 0, V.WheelOffsetZ) },
}

local RAY_LENGTH = V.RestLength + V.WheelRadius

export type State = {
	model: Model?,
	speed: number,
	steer: number,
	drifting: boolean,
	driftBlend: number,
	driftCharge: number, -- 0..1 for the HUD
	boosting: boolean,
	grounded: number,
	wheelDistance: { [string]: number }, -- ray hit distance per wheel, for visuals
	canFlip: boolean,
}

local CarController = {}

local state: State = {
	model = nil,
	speed = 0,
	steer = 0,
	drifting = false,
	driftBlend = 0,
	driftCharge = 0,
	boosting = false,
	grounded = 0,
	wheelDistance = {},
	canFlip = false,
}
CarController.State = state

local chassis: BasePart? = nil
local driveEnabled = false
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local driftTime = 0
local wasHandbrake = false
local boostRemaining = 0
local boostRate = 0
local lastFlip = 0
local upsideDownTime = 0

local function exponentialFactor(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

function CarController.Bind(model: Model)
	state.model = model
	chassis = model.PrimaryPart
	rayParams.FilterDescendantsInstances = { model }
	driftTime = 0
	boostRemaining = 0
	state.driftCharge = 0
	state.driftBlend = 0
	table.clear(state.wheelDistance)
end

function CarController.Unbind()
	state.model = nil
	chassis = nil
	state.speed = 0
	state.drifting = false
	state.driftCharge = 0
	state.boosting = false
end

function CarController.SetDriveEnabled(enabled: boolean)
	driveEnabled = enabled
end

function CarController.GetChassis(): BasePart?
	return chassis
end

local function isUsable(part: BasePart?): boolean
	if not part or not part.Parent or part.Anchored then
		return false
	end
	local model = state.model
	if not model or model:GetAttribute("Destroyed") then
		return false
	end
	-- ReceiveAge is 0 only for parts this machine simulates.
	return part.ReceiveAge == 0
end

function CarController.Flip()
	local part = chassis
	if not part or not isUsable(part) then
		return
	end
	local t = os.clock()
	if t - lastFlip < V.FlipCooldown then
		return
	end
	local cf = part.CFrame
	local tilted = cf.UpVector.Y < 0.6
	local stuck = part.AssemblyLinearVelocity.Magnitude < 8
	if not (tilted or stuck) then
		return
	end
	lastFlip = t
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.zAxis
	end
	local position = part.Position + Vector3.new(0, 5, 0)
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	local model = state.model
	if model then
		model:PivotTo(CFrame.lookAt(position, position + flat.Unit))
	end
end

local function step(dt: number)
	InputState.Update()
	local part = chassis
	if not part or not isUsable(part) then
		state.speed = 0
		state.drifting = false
		state.boosting = false
		return
	end
	dt = math.min(dt, 1 / 30)

	local cf = part.CFrame
	local up = cf.UpVector
	local look = cf.LookVector
	local right = cf.RightVector
	local mass = part.AssemblyMass
	local wheelMass = mass / 4
	local velocity = part.AssemblyLinearVelocity
	local angular = part.AssemblyAngularVelocity
	local center = part.AssemblyCenterOfMass

	-- Suspension
	local grounded = 0
	local offroad = 0
	local groundVelocity = Vector3.zero
	local groundYawRate = 0
	for _, wheel in WHEELS do
		local origin = cf:PointToWorldSpace(wheel.offset)
		local result = Workspace:Raycast(origin, -up * RAY_LENGTH, rayParams)
		if result then
			state.wheelDistance[wheel.name] = result.Distance
			local compression = RAY_LENGTH - result.Distance
			local hitPart = result.Instance
			local surfaceVelocity = if hitPart:IsA("BasePart") and not hitPart.Anchored
				then hitPart:GetVelocityAtPosition(result.Position)
				else Vector3.zero
			local pointVelocity = velocity + angular:Cross(origin - center)
			local closing = (pointVelocity - surfaceVelocity):Dot(up)
			local force = wheelMass * (V.SpringStiffness * compression - V.SpringDamping * closing)
			if force > 0 then
				part:ApplyImpulseAtPosition(up * force * dt, origin)
			end
			grounded += 1
			groundVelocity += surfaceVelocity
			if hitPart:IsA("BasePart") and not hitPart.Anchored then
				groundYawRate += hitPart.AssemblyAngularVelocity:Dot(up)
			end
			if OFFROAD[result.Material] then
				offroad += 1
			end
		else
			state.wheelDistance[wheel.name] = RAY_LENGTH
		end
	end
	state.grounded = grounded

	-- Flip detection (auto-recover after a few seconds on the roof)
	if up.Y < 0.2 then
		upsideDownTime += dt
		if upsideDownTime > 3 then
			upsideDownTime = 0
			task.defer(CarController.Flip)
		end
	else
		upsideDownTime = 0
	end
	state.canFlip = up.Y < 0.6

	local throttle = if driveEnabled then InputState.throttle else 0
	local steerInput = if driveEnabled then InputState.steer else 0
	local handbrake = driveEnabled and InputState.handbrake

	state.steer += (steerInput - state.steer) * exponentialFactor(V.SteerResponse, dt)

	if grounded == 0 then
		state.speed = velocity.Magnitude
		state.drifting = false
		wasHandbrake = handbrake
		return
	end

	local traction = grounded / 4
	local isOffroad = offroad >= 2
	groundVelocity /= grounded
	groundYawRate /= grounded

	local relative = velocity - groundVelocity
	local forwardSpeed = relative:Dot(look)
	local lateralSpeed = relative:Dot(right)
	state.speed = math.abs(forwardSpeed)

	local maxSpeed = V.MaxSpeed * (if isOffroad then V.OffroadSpeedMultiplier else 1)

	-- Drift state
	local wantsDrift = handbrake and math.abs(forwardSpeed) > 25
	local blendTarget = if wantsDrift then 1 else 0
	local blendRate = if wantsDrift then 6 else 2.5
	state.driftBlend += (blendTarget - state.driftBlend) * exponentialFactor(blendRate, dt)
	state.drifting = state.driftBlend > 0.5 and math.abs(lateralSpeed) > 8

	if wantsDrift and math.abs(lateralSpeed) > 12 then
		driftTime += dt
	elseif not handbrake then
		driftTime = 0
	end
	state.driftCharge =
		math.clamp((driftTime - V.DriftBoostMinTime) / (V.DriftBoostMaxTime - V.DriftBoostMinTime), 0, 1)
	if driftTime >= V.DriftBoostMinTime then
		state.driftCharge = math.max(state.driftCharge, 0.05)
	end

	-- Released the handbrake after a good drift: queue a boost
	if wasHandbrake and not handbrake and driftTime >= V.DriftBoostMinTime then
		local charge = math.max(0.3, state.driftCharge)
		boostRemaining = V.DriftBoostMaxImpulse * charge
		boostRate = boostRemaining / 0.4
		driftTime = 0
		state.driftCharge = 0
	end
	wasHandbrake = handbrake

	-- Longitudinal
	local dvForward = 0
	if throttle > 0 then
		if forwardSpeed < -2 then
			dvForward = math.min(V.BrakeDecel * throttle * dt, -forwardSpeed)
		elseif forwardSpeed < maxSpeed then
			local ratio = forwardSpeed / maxSpeed
			dvForward = V.EngineAccel * throttle * math.max(0.15, 1 - ratio * ratio) * dt
		end
	elseif throttle < 0 then
		if forwardSpeed > 2 then
			dvForward = -math.min(V.BrakeDecel * -throttle * dt, forwardSpeed)
		elseif forwardSpeed > -V.ReverseSpeed then
			dvForward = -V.EngineAccel * 0.6 * -throttle * dt
		end
	else
		dvForward = -forwardSpeed * V.RollingDrag * dt
	end
	-- Over the limit (offroad or after a boost): bleed speed smoothly
	local cap = if boostRemaining > 0 then maxSpeed * V.DriftBoostSpeedCap else maxSpeed
	if forwardSpeed > cap then
		dvForward = math.min(dvForward, -(forwardSpeed - cap) * 1.5 * dt)
	end
	if handbrake then
		dvForward -= math.sign(forwardSpeed) * math.min(math.abs(forwardSpeed), 10 * dt)
	end

	-- Boost
	state.boosting = boostRemaining > 0
	if boostRemaining > 0 then
		local amount = math.min(boostRemaining, boostRate * dt)
		boostRemaining -= amount
		if forwardSpeed < maxSpeed * V.DriftBoostSpeedCap then
			dvForward += amount
		end
	end

	-- Lateral grip
	local grip = V.RearGrip + (V.DriftRearGrip - V.RearGrip) * state.driftBlend
	if isOffroad then
		grip *= V.OffroadGripMultiplier
	end
	local dvLateral = -lateralSpeed * exponentialFactor(grip, dt)
	-- While drifting, some of the scrubbed sideways speed is carried forward
	if state.driftBlend > 0.3 and forwardSpeed > 0 and forwardSpeed < maxSpeed then
		dvForward += math.abs(dvLateral) * 0.35 * state.driftBlend
	end

	part:ApplyImpulse((look * dvForward + right * dvLateral) * mass * traction)

	-- Steering: drive yaw rate directly (relative to the surface's own spin)
	local speedRatio = math.clamp(math.abs(forwardSpeed) / V.MaxSpeed, 0, 1)
	local steerRate = V.SteerRateLowSpeed + (V.SteerRateHighSpeed - V.SteerRateLowSpeed) * speedRatio
	local lowSpeedFade = math.clamp(math.abs(forwardSpeed) / 10, 0, 1)
	local direction = if forwardSpeed >= 0 then 1 else -1
	local driftBonus = 1 + (V.DriftSteerBonus - 1) * state.driftBlend
	local targetYaw = -state.steer * steerRate * lowSpeedFade * direction * driftBonus + groundYawRate

	local localAngular = cf:VectorToObjectSpace(angular)
	local yawResponse = (10 - 6 * state.driftBlend) * traction
	local newYaw = localAngular.Y + (targetYaw - localAngular.Y) * exponentialFactor(yawResponse, dt)
	-- Calm pitch/roll wobble a little while on the ground
	local settle = math.exp(-2.5 * traction * dt)
	part.AssemblyAngularVelocity =
		cf:VectorToWorldSpace(Vector3.new(localAngular.X * settle, newYaw, localAngular.Z * settle))
end

function CarController.Init()
	InputState.OnFlip(CarController.Flip)
	RunService.PreSimulation:Connect(step)
end

return CarController
