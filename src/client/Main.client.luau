--!strict
-- Client entry point. Decides each frame what the local player should be
-- doing (watching the lobby, driving, or spectating) and wires the modules
-- together.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local Client = script.Parent
local CameraController = require(Client:WaitForChild("CameraController"))
local CarController = require(Client:WaitForChild("CarController"))
local Hud = require(Client:WaitForChild("Hud"))
local InputState = require(Client:WaitForChild("InputState"))
local ParkReporter = require(Client:WaitForChild("ParkReporter"))
local VehicleVisuals = require(Client:WaitForChild("VehicleVisuals"))

local player = Players.LocalPlayer
local gameState = ReplicatedStorage:WaitForChild("GameState") :: Folder
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local feedRemote = remotes:WaitForChild("Feed") :: RemoteEvent
local carsFolder = Workspace:WaitForChild("Cars")

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

CameraController.Init()
CarController.Init()
VehicleVisuals.Init()
ParkReporter.Init()
Hud.Init()

local ownCar: Model? = nil
local wreckedAt: number? = nil
local spectateIndex = 1
local lastPhase = ""

local function findOwnCar(): Model?
	for _, model in carsFolder:GetChildren() do
		if model:IsA("Model") and model:GetAttribute("OwnerUserId") == player.UserId then
			return model
		end
	end
	return nil
end

-- Alive cars (by car number) followed by the trailer.
local function spectateTargets(): { { part: BasePart, label: string, model: Model?, trailer: boolean } }
	local list = {}
	local models = {}
	for _, model in carsFolder:GetChildren() do
		if model:IsA("Model") and model.PrimaryPart and model:GetAttribute("Destroyed") ~= true and model ~= ownCar then
			table.insert(models, model)
		end
	end
	table.sort(models, function(a, b)
		return ((a:GetAttribute("CarNumber") :: number?) or 0) < ((b:GetAttribute("CarNumber") :: number?) or 0)
	end)
	for _, model in models do
		table.insert(list, {
			part = model.PrimaryPart :: BasePart,
			label = string.format(
				"#%d %s",
				(model:GetAttribute("CarNumber") :: number?) or 0,
				(model:GetAttribute("OwnerName") :: string?) or model.Name
			),
			model = model,
			trailer = false,
		})
	end
	local trailer = Workspace:FindFirstChild("Trailer")
	local deck = trailer and trailer:FindFirstChild("Deck")
	if deck and deck:IsA("BasePart") then
		table.insert(list, { part = deck, label = "THE TRAILER", model = nil, trailer = true })
	end
	return list
end

InputState.OnCycleSpectate(function(direction: number)
	spectateIndex += direction
end)

feedRemote.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then
		return
	end
	local kind = data.kind
	if kind == "destroyed" then
		local victim = tostring(data.victim)
		local text
		if data.attacker then
			text = string.format("%s wrecked %s", tostring(data.attacker), victim)
		elseif data.reason == "fell" then
			text = victim .. " fell out of the arena"
		else
			text = victim .. " is scrap metal"
		end
		Hud.PushFeed("💥 " .. text, Color3.fromRGB(255, 140, 90))
		if data.victimUserId == player.UserId then
			Hud.ShowCenter("WRECKED!", "You can spectate the rest of the match", 3, Color3.fromRGB(230, 60, 50))
		end
	elseif kind == "ramp" then
		Hud.PushFeed("The ramp is down!", Color3.fromRGB(255, 196, 0))
		Hud.ShowCenter("RAMP IS DOWN!", "Get on the trailer and park in the yellow bay", 3)
	elseif kind == "winner" then
		Hud.PushFeed("🏆 " .. tostring(data.name) .. " parked on the trailer!", Color3.fromRGB(255, 196, 0))
	end
end)

RunService.RenderStepped:Connect(function()
	local phase = (gameState:GetAttribute("Phase") :: string?) or "Lobby"

	if phase ~= lastPhase then
		lastPhase = phase
		if phase == "Racing" then
			Hud.ShowCenter("GO!", "Catch the trailer!", 1.2)
		end
		if phase == "Lobby" or phase == "CarSelect" then
			wreckedAt = nil
		end
	end

	-- Track our own car
	local car = findOwnCar()
	if car ~= ownCar then
		ownCar = car
		wreckedAt = nil
		if car and car.PrimaryPart then
			CarController.Bind(car)
		else
			CarController.Unbind()
		end
		Hud.SetOwnCar(car)
	end

	local inPlay = phase == "Countdown" or phase == "Racing" or phase == "Results"
	local alive = car ~= nil and car.PrimaryPart ~= nil and car:GetAttribute("Destroyed") ~= true
	CarController.SetDriveEnabled(alive and phase == "Racing")

	if car and not alive and wreckedAt == nil then
		wreckedAt = os.clock()
	end

	if not inPlay then
		CameraController.Orbit()
		Hud.SetSpectating(nil, nil)
		return
	end

	-- Results: show the winner if there is one
	if phase == "Results" then
		local winnerId = gameState:GetAttribute("WinnerUserId")
		for _, model in carsFolder:GetChildren() do
			if model:IsA("Model") and winnerId ~= 0 and model:GetAttribute("OwnerUserId") == winnerId then
				CameraController.Follow(model.PrimaryPart)
				Hud.SetSpectating(nil, nil)
				return
			end
		end
	end

	-- Driving (or watching our own wreck burn for a moment)
	if car and car.PrimaryPart and (alive or (wreckedAt and os.clock() - wreckedAt < 3)) then
		CameraController.Follow(car.PrimaryPart)
		Hud.SetSpectating(nil, nil)
		return
	end

	-- Spectating
	local targets = spectateTargets()
	if #targets == 0 then
		CameraController.Orbit()
		Hud.SetSpectating(nil, nil)
		return
	end
	spectateIndex = ((spectateIndex - 1) % #targets) + 1
	local target = targets[spectateIndex]
	if CameraController.GetSubject() ~= target.part then
		CameraController.Follow(target.part, target.trailer)
	end
	Hud.SetSpectating(target.model, string.format("SPECTATING %s (%d/%d)", target.label, spectateIndex, #targets))
end)

RunService.RenderStepped:Connect(function()
	Hud.Update()
end)
