--!strict
-- Runs the match loop:
--   Lobby -> CarSelect -> Countdown -> Racing -> Results -> Lobby
--
-- Public state lives as attributes on ReplicatedStorage.GameState so every
-- client can render the HUD without extra remotes:
--   Phase, PhaseEndsAt, RampUnlockAt, WinnerName, WinnerUserId, EndReason,
--   Participants, Alive, Waiting

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CarCatalog = require(Shared:WaitForChild("CarCatalog"))
local TrackPath = require(Shared:WaitForChild("TrackPath"))

local Server = script.Parent
local CarService = require(Server:WaitForChild("CarService"))
local ParkingJudge = require(Server:WaitForChild("ParkingJudge"))
local Trailer = require(Server:WaitForChild("Trailer"))

type TrackPath = TrackPath.TrackPath
type Trailer = Trailer.Trailer
type Car = CarService.Car

local M = Config.Match
local T = Config.Track

local MatchManager = {}

local gameState: Folder
local remotes: Folder
local feedRemote: RemoteEvent
local path: TrackPath
local trailer: Trailer

local participants: { Player } = {}

-- Latest parking report from each driver (see ParkReport below).
type ParkReport = { relative: CFrame, velocity: Vector3, at: number }
local parkReports: { [Player]: ParkReport } = {}
local REPORT_TIMEOUT = 0.35 -- seconds before a missing report counts as a fail
local SANITY_RADIUS = 40 -- server-side car must be this close to the bay (covers latency)
local SANITY_SPEED = 30 -- and roughly moving with the trailer

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function setPhase(phase: string, duration: number?)
	gameState:SetAttribute("Phase", phase)
	gameState:SetAttribute("PhaseEndsAt", if duration then now() + duration else 0)
end

local function feed(kind: string, data: { [string]: any })
	data.kind = kind
	feedRemote:FireAllClients(data)
end

local function isParticipant(player: Player): boolean
	return table.find(participants, player) ~= nil
end

local function waitingPlayers(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		table.insert(list, player)
	end
	return list
end

local function gridCFrame(slot: number): CFrame
	-- Slots fill left/right, then row by row back from the start line.
	local index = slot - 1
	local row = index // T.GridColumns
	local column = index % T.GridColumns
	local distance = T.GridStartDistance - row * T.GridRowSpacing
	local base = path:CFrameAt(distance)
	local lateral = (column - (T.GridColumns - 1) / 2) * T.GridColumnSpacing
	local rideHeight = Config.Vehicle.RestLength + Config.Vehicle.WheelRadius - 0.9
	return base * CFrame.new(lateral, rideHeight + 0.2, 0)
end

local function runLobby()
	setPhase("Lobby")
	gameState:SetAttribute("WinnerName", "")
	gameState:SetAttribute("WinnerUserId", 0)
	gameState:SetAttribute("EndReason", "")
	while true do
		local count = #waitingPlayers()
		gameState:SetAttribute("Waiting", count)
		if count >= M.MinPlayersToStart then
			setPhase("Lobby", M.LobbyCountdown)
			local deadline = now() + M.LobbyCountdown
			local cancelled = false
			while now() < deadline do
				task.wait(0.25)
				local current = #waitingPlayers()
				gameState:SetAttribute("Waiting", current)
				if current < M.MinPlayersToStart then
					cancelled = true
					break
				end
			end
			if not cancelled then
				return
			end
			setPhase("Lobby")
		end
		task.wait(0.5)
	end
end

local function runCarSelect(): boolean
	table.clear(participants)
	for _, player in Players:GetPlayers() do
		if #participants >= M.MaxPlayers then
			break
		end
		table.insert(participants, player)
	end
	for _, player in Players:GetPlayers() do
		player:SetAttribute("InMatch", isParticipant(player))
	end
	gameState:SetAttribute("Participants", #participants)
	if #participants == 0 then
		return false
	end

	setPhase("CarSelect", M.CarSelectTime)
	local deadline = now() + M.CarSelectTime
	while now() < deadline do
		task.wait(0.25)
		-- Finish early once everybody has locked in a car
		local allPicked = true
		for _, player in participants do
			if player.Parent == Players and not player:GetAttribute("CarLocked") then
				allPicked = false
				break
			end
		end
		if allPicked then
			task.wait(1)
			break
		end
	end

	-- Drop anyone who left during selection
	for i = #participants, 1, -1 do
		if participants[i].Parent ~= Players then
			table.remove(participants, i)
		end
	end
	return #participants > 0
end

local function spawnCars()
	CarService.ClearAll()
	trailer:Reset(T.GridStartDistance + Config.Trailer.LeadDistance)
	for slot, player in participants do
		local def = CarCatalog.Get(player:GetAttribute("SelectedCar") :: string?) or CarCatalog.Random()
		player:SetAttribute("SelectedCar", def.Id)
		CarService.Spawn(player, def, gridCFrame(slot), slot)
	end
	gameState:SetAttribute("Alive", CarService.AliveCount())
end

local function runCountdown()
	setPhase("Countdown", M.StartCountdown)
	task.wait(M.StartCountdown)
end

-- Returns winner (or nil) and a reason string.
local function runRace(): (Player?, string)
	local startedAt = now()
	local rampUnlockAt = startedAt + M.RampLockTime
	gameState:SetAttribute("RampUnlockAt", rampUnlockAt)
	setPhase("Racing", M.MaxMatchTime)

	trailer:SetRampLocked(true)
	trailer:Start()
	CarService.ReleaseAll()

	local rampLocked = true
	local winner: Player? = nil
	local reason = "timeout"

	while true do
		local dt = RunService.Heartbeat:Wait()
		local t = now()

		if rampLocked and t >= rampUnlockAt then
			rampLocked = false
			trailer:SetRampLocked(false)
			feed("ramp", {})
		end

		local bayCFrame = trailer:GetBayCFrame()
		local alive = 0
		for _, player in participants do
			local car = CarService.Get(player)
			if not car or car.destroyed or player.Parent ~= Players then
				continue
			end
			alive += 1
			local progress = (car.model:GetAttribute("ParkProgress") :: number?) or 0
			if rampLocked then
				progress = 0
			else
				local report = parkReports[player]
				local chassis = car.chassis
				local plausible = report ~= nil
					and t - report.at <= REPORT_TIMEOUT
					and (chassis.Position - bayCFrame.Position).Magnitude <= SANITY_RADIUS
					and (chassis.AssemblyLinearVelocity - trailer:GetVelocityAt(chassis.Position)).Magnitude
						<= SANITY_SPEED
				if plausible and report then
					local verdict = ParkingJudge.Evaluate(report.relative, report.velocity)
					progress = ParkingJudge.Advance(progress, verdict, dt)
				else
					progress = ParkingJudge.Decay(progress, dt)
				end
			end
			car.model:SetAttribute("ParkProgress", progress)
			if progress >= 1 and not winner then
				winner = player
			end
		end
		gameState:SetAttribute("Alive", alive)

		if winner then
			reason = "parked"
			break
		end
		if alive == 0 then
			reason = "wiped"
			break
		end
		if t - startedAt >= M.MaxMatchTime then
			reason = "timeout"
			break
		end
	end

	return winner, reason
end

local function runResults(winner: Player?, reason: string)
	gameState:SetAttribute("WinnerName", if winner then winner.DisplayName else "")
	gameState:SetAttribute("WinnerUserId", if winner then winner.UserId else 0)
	gameState:SetAttribute("EndReason", reason)
	setPhase("Results", M.PostMatchTime)

	-- Clients stop accepting driving input outside the Racing phase.
	if winner then
		local car = CarService.Get(winner)
		if car then
			local attachment = Instance.new("Attachment")
			attachment.Position = Vector3.new(0, 4, 0)
			attachment.Parent = car.chassis
			local confetti = Instance.new("ParticleEmitter")
			confetti.Rate = 120
			confetti.Lifetime = NumberRange.new(1.5, 2.5)
			confetti.Speed = NumberRange.new(25, 40)
			confetti.SpreadAngle = Vector2.new(40, 40)
			confetti.Acceleration = Vector3.new(0, -30, 0)
			confetti.Rotation = NumberRange.new(0, 360)
			confetti.RotSpeed = NumberRange.new(-200, 200)
			confetti.Size = NumberSequence.new(0.6)
			confetti.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
				ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 220, 40)),
				ColorSequenceKeypoint.new(0.66, Color3.fromRGB(60, 200, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 255, 120)),
			})
			confetti.Parent = attachment
		end
	end

	task.wait(M.PostMatchTime)
	trailer:Stop()
end

local function cleanup()
	table.clear(parkReports)
	CarService.ClearAll()
	trailer:Reset(T.GridStartDistance + Config.Trailer.LeadDistance)
	table.clear(participants)
	gameState:SetAttribute("Participants", 0)
	gameState:SetAttribute("Alive", 0)
	for _, player in Players:GetPlayers() do
		player:SetAttribute("InMatch", false)
		player:SetAttribute("CarLocked", false)
	end
end

function MatchManager.Init(trackPath: TrackPath)
	path = trackPath

	gameState = Instance.new("Folder")
	gameState.Name = "GameState"
	gameState:SetAttribute("Phase", "Lobby")
	gameState:SetAttribute("PhaseEndsAt", 0)
	gameState:SetAttribute("RampUnlockAt", 0)
	gameState:SetAttribute("WinnerName", "")
	gameState:SetAttribute("WinnerUserId", 0)
	gameState:SetAttribute("EndReason", "")
	gameState:SetAttribute("Participants", 0)
	gameState:SetAttribute("Alive", 0)
	gameState:SetAttribute("Waiting", 0)
	gameState:SetAttribute("MinPlayers", M.MinPlayersToStart)
	gameState:SetAttribute("MaxPlayers", M.MaxPlayers)
	gameState.Parent = ReplicatedStorage

	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	local selectCar = Instance.new("RemoteEvent")
	selectCar.Name = "SelectCar"
	selectCar.Parent = remotes
	feedRemote = Instance.new("RemoteEvent")
	feedRemote.Name = "Feed"
	feedRemote.Parent = remotes
	-- The car is simulated on its driver's client and the trailer on the
	-- server, so the server always sees the car a few studs behind where it
	-- really sits on the deck (speed x latency). Drivers therefore report
	-- their pose relative to the bay as they see it; the server checks it is
	-- plausible and applies the parking rules and timer itself.
	local parkReport = Instance.new("UnreliableRemoteEvent")
	parkReport.Name = "ParkReport"
	parkReport.Parent = remotes
	remotes.Parent = ReplicatedStorage

	parkReport.OnServerEvent:Connect(function(player, relative, velocity)
		if gameState:GetAttribute("Phase") ~= "Racing" then
			return
		end
		if typeof(relative) ~= "CFrame" or typeof(velocity) ~= "Vector3" then
			return
		end
		local position = relative.Position
		-- Reject NaN / absurd values
		if position ~= position or velocity ~= velocity then
			return
		end
		if position.Magnitude > 100 or velocity.Magnitude > 500 then
			return
		end
		parkReports[player] = { relative = relative, velocity = velocity, at = now() }
	end)

	Players.PlayerRemoving:Connect(function(player)
		parkReports[player] = nil
	end)

	selectCar.OnServerEvent:Connect(function(player, carId, lock)
		local phase = gameState:GetAttribute("Phase")
		if phase ~= "Lobby" and phase ~= "CarSelect" then
			return
		end
		if typeof(carId) ~= "string" or not CarCatalog.Get(carId) then
			return
		end
		player:SetAttribute("SelectedCar", carId)
		if phase == "CarSelect" and lock == true and isParticipant(player) then
			player:SetAttribute("CarLocked", true)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("InMatch", false)
		player:SetAttribute("CarLocked", false)
	end)

	trailer = Trailer.new(path)
	trailer:Reset(T.GridStartDistance + Config.Trailer.LeadDistance)

	CarService.OnDestroyed(function(car: Car, attacker: Player?, reason: string)
		feed("destroyed", {
			victim = car.player.DisplayName,
			victimUserId = car.player.UserId,
			attacker = if attacker then attacker.DisplayName else nil,
			reason = reason,
		})
	end)
end

function MatchManager.Run()
	while true do
		runLobby()
		if runCarSelect() then
			spawnCars()
			runCountdown()
			local winner, reason = runRace()
			if winner then
				feed("winner", { name = winner.DisplayName, userId = winner.UserId })
			end
			runResults(winner, reason)
		end
		cleanup()
	end
end

return MatchManager
