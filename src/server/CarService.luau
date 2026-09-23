--!strict
-- Spawns player cars and owns everything the server decides about them:
-- health, impact damage, who gets credit for a hit, and destruction.
--
-- Cars are simulated on their driver's client (network ownership) for
-- responsive handling, so damage is inferred on the server from sudden
-- changes in replicated velocity while the chassis is touching something.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CarBuilder = require(Shared:WaitForChild("CarBuilder"))
local CarCatalog = require(Shared:WaitForChild("CarCatalog"))

type CarDefinition = CarCatalog.CarDefinition

local D = Config.Damage
local HISTORY_WINDOW = 0.15
local WRECK_LIFETIME = 8

export type Car = {
	player: Player,
	model: Model,
	chassis: BasePart,
	health: number,
	destroyed: boolean,
	history: { { t: number, v: Vector3 } },
	lastHitAt: number,
	lastAttacker: Player?,
	lastAttackerAt: number,
}

local CarService = {}

local cars: { [Player]: Car } = {}
local carsFolder: Folder
local excludedSurface: Instance?
local destroyedListeners: { (car: Car, attacker: Player?, reason: string) -> () } = {}
local hitListeners: { (car: Car, damage: number, attacker: Player?) -> () } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function carFromPart(part: BasePart): Car?
	local node: Instance? = part
	while node and node.Parent ~= carsFolder do
		node = node.Parent
	end
	if not node then
		return nil
	end
	for _, car in cars do
		if car.model == node then
			return car
		end
	end
	return nil
end

local function updateEffects(car: Car)
	local attachment = car.chassis:FindFirstChild("EngineAttachment")
	if not attachment then
		return
	end
	local smoke = attachment:FindFirstChild("DamageSmoke") :: ParticleEmitter?
	local fire = attachment:FindFirstChild("DamageFire") :: Fire?
	if smoke then
		smoke.Enabled = car.health <= D.SmokeHealth
		smoke.Rate = if car.health <= D.FireHealth then 40 else 18
	end
	if fire then
		fire.Enabled = car.health <= D.FireHealth
	end
end

function CarService.Init(surfaceFolder: Instance?)
	excludedSurface = surfaceFolder
	carsFolder = Workspace:FindFirstChild("Cars") :: Folder
	if not carsFolder then
		carsFolder = Instance.new("Folder")
		carsFolder.Name = "Cars"
		carsFolder.Parent = Workspace
	end

	RunService.Heartbeat:Connect(function()
		CarService._step()
	end)

	Players.PlayerRemoving:Connect(function(player)
		CarService.Remove(player)
	end)
end

function CarService.OnDestroyed(callback: (car: Car, attacker: Player?, reason: string) -> ())
	table.insert(destroyedListeners, callback)
end

function CarService.OnHit(callback: (car: Car, damage: number, attacker: Player?) -> ())
	table.insert(hitListeners, callback)
end

function CarService.Spawn(player: Player, def: CarDefinition, cframe: CFrame, carNumber: number): Car
	CarService.Remove(player)

	local model = CarBuilder.Build(def, cframe, carNumber)
	model.Name = player.Name
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("OwnerName", player.DisplayName)
	model:SetAttribute("Health", D.MaxHealth)
	model:SetAttribute("MaxHealth", D.MaxHealth)
	model:SetAttribute("Destroyed", false)
	model:SetAttribute("ParkProgress", 0)

	-- Name tag above the car for everyone else
	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromOffset(200, 30)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
	tag.MaxDistance = 250
	tag.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = string.format("#%d %s", carNumber, player.DisplayName)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Parent = tag
	tag.Parent = model.PrimaryPart

	model.Parent = carsFolder

	local car: Car = {
		player = player,
		model = model,
		chassis = model.PrimaryPart :: BasePart,
		health = D.MaxHealth,
		destroyed = false,
		history = {},
		lastHitAt = 0,
		lastAttacker = nil,
		lastAttackerAt = 0,
	}
	cars[player] = car
	return car
end

-- Unanchors every car and hands physics to its driver.
function CarService.ReleaseAll()
	for player, car in cars do
		if not car.destroyed and car.chassis.Parent then
			car.chassis.Anchored = false
			if player.Parent == Players then
				car.chassis:SetNetworkOwner(player)
			end
		end
	end
end

function CarService.Get(player: Player): Car?
	return cars[player]
end

function CarService.GetAll(): { [Player]: Car }
	return cars
end

function CarService.AliveCount(): number
	local count = 0
	for _, car in cars do
		if not car.destroyed then
			count += 1
		end
	end
	return count
end

function CarService.Remove(player: Player)
	local car = cars[player]
	if car then
		cars[player] = nil
		car.destroyed = true
		car.model:Destroy()
	end
end

function CarService.ClearAll()
	for player in cars do
		CarService.Remove(player)
	end
	carsFolder:ClearAllChildren()
end

function CarService.Freeze(car: Car)
	if car.chassis.Parent then
		car.chassis.Anchored = true
	end
end

local function directionMultiplier(car: Car, deltaV: Vector3): number
	-- The obstacle is on the opposite side to the velocity change.
	local impactDir = car.chassis.CFrame:VectorToObjectSpace(-deltaV.Unit)
	if impactDir.Z < -0.65 then
		return D.FrontArmorMultiplier
	elseif impactDir.Z > 0.65 then
		return D.RearMultiplier
	end
	return D.SideMultiplier
end

function CarService.Damage(car: Car, amount: number, attacker: Player?)
	if car.destroyed or amount <= 0 then
		return
	end
	if attacker and attacker ~= car.player then
		car.lastAttacker = attacker
		car.lastAttackerAt = now()
	end
	car.health = math.max(0, car.health - amount)
	car.model:SetAttribute("Health", car.health)
	updateEffects(car)
	for _, listener in hitListeners do
		task.spawn(listener, car, amount, attacker)
	end
	if car.health <= 0 then
		local credit = if car.lastAttacker and now() - car.lastAttackerAt < 6 then car.lastAttacker else nil
		CarService.Destroy(car, credit, "wrecked")
	end
end

function CarService.Destroy(car: Car, attacker: Player?, reason: string)
	if car.destroyed then
		return
	end
	car.destroyed = true
	car.health = 0
	car.model:SetAttribute("Health", 0)
	car.model:SetAttribute("Destroyed", true)
	car.model:SetAttribute("ParkProgress", 0)

	local chassis = car.chassis
	if chassis.Parent then
		if not chassis.Anchored then
			pcall(function()
				chassis:SetNetworkOwner(nil)
			end)
		end

		local explosion = Instance.new("Explosion")
		explosion.Position = chassis.Position
		explosion.BlastPressure = 0
		explosion.BlastRadius = 12
		explosion.DestroyJointRadiusPercent = 0
		explosion.Parent = Workspace

		if not chassis.Anchored then
			local mass = chassis.AssemblyMass
			chassis:ApplyImpulse(Vector3.new(0, mass * 70, 0))
			chassis:ApplyAngularImpulse(chassis.CFrame.LookVector * mass * 60)
		end

		-- Scorch the paint
		for _, descendant in car.model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Color = descendant.Color:Lerp(Color3.fromRGB(25, 22, 20), 0.75)
				if descendant.Material ~= Enum.Material.Glass then
					descendant.Material = Enum.Material.CorrodedMetal
				end
			elseif descendant:IsA("BillboardGui") then
				descendant.Enabled = false
			end
		end
		local attachment = chassis:FindFirstChild("EngineAttachment")
		local fire = attachment and attachment:FindFirstChild("DamageFire") :: Fire?
		if fire then
			fire.Enabled = true
			fire.Size = 10
		end
	end

	for _, listener in destroyedListeners do
		task.spawn(listener, car, attacker, reason)
	end

	-- Clear the wreck so it can't permanently block the trailer bay.
	local model = car.model
	task.delay(WRECK_LIFETIME, function()
		if cars[car.player] == car then
			cars[car.player] = nil
		end
		if model.Parent then
			model:Destroy()
		end
	end)
end

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
overlapParams.RespectCanCollide = true

function CarService._step()
	local t = now()
	for _, car in cars do
		if car.destroyed or car.chassis.Anchored or not car.chassis.Parent then
			continue
		end
		local chassis = car.chassis

		if chassis.Position.Y < D.KillY then
			CarService.Destroy(car, car.lastAttacker, "fell")
			continue
		end

		local velocity = chassis.AssemblyLinearVelocity
		local history = car.history
		table.insert(history, { t = t, v = velocity })
		while #history > 0 and t - history[1].t > HISTORY_WINDOW do
			table.remove(history, 1)
		end

		if t - car.lastHitAt < D.ContactCooldown + HISTORY_WINDOW then
			continue
		end

		-- Largest velocity change inside the window; vertical changes (landings)
		-- count for much less than horizontal ones.
		local peak = Vector3.zero
		local peakMagnitude = 0
		for _, sample in history do
			local delta = velocity - sample.v
			local weighted = Vector3.new(delta.X, delta.Y * 0.3, delta.Z)
			local magnitude = weighted.Magnitude
			if magnitude > peakMagnitude then
				peak = weighted
				peakMagnitude = magnitude
			end
		end
		if peakMagnitude < D.ImpactThreshold then
			continue
		end

		-- Only count it if the chassis is actually touching something, so
		-- boosts, braking and drift recovery never hurt.
		local exclude: { Instance } = { car.model }
		if excludedSurface then
			table.insert(exclude, excludedSurface)
		end
		overlapParams.FilterDescendantsInstances = exclude
		local touching =
			Workspace:GetPartBoundsInBox(chassis.CFrame, chassis.Size + Vector3.new(2.5, 1.5, 2.5), overlapParams)
		if #touching == 0 then
			continue
		end

		local attacker: Player? = nil
		for _, part in touching do
			local other = carFromPart(part)
			if other and other ~= car then
				attacker = other.player
				break
			end
		end

		car.lastHitAt = t
		table.clear(history)

		local damage = (peakMagnitude - D.ImpactThreshold) * D.DamagePerStud * directionMultiplier(car, peak)
		damage = math.min(damage, D.MaxSingleHit)
		CarService.Damage(car, damage, attacker)
	end
end

return CarService
