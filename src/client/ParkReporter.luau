--!strict
-- Sends the local car's pose relative to the trailer's parking bay to the
-- server while it is near the bay. The server judges parking from these
-- reports because only this client sees the car and the deck in the same
-- moment (see MatchManager's ParkReport handler).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CarController = require(script.Parent:WaitForChild("CarController"))

local SEND_INTERVAL = 1 / 15
local REPORT_RADIUS = 35

local ParkReporter = {}

function ParkReporter.Init()
	local gameState = ReplicatedStorage:WaitForChild("GameState")
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ParkReport") :: UnreliableRemoteEvent
	local elapsed = 0

	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < SEND_INTERVAL then
			return
		end
		elapsed = 0

		if gameState:GetAttribute("Phase") ~= "Racing" then
			return
		end
		local model = CarController.State.model
		local chassis = CarController.GetChassis()
		if not model or not chassis or not chassis.Parent or model:GetAttribute("Destroyed") then
			return
		end
		local trailer = Workspace:FindFirstChild("Trailer")
		local bay = trailer and trailer:FindFirstChild("ParkingBay")
		local deck = trailer and trailer:FindFirstChild("Deck")
		if not bay or not bay:IsA("BasePart") or not deck or not deck:IsA("BasePart") then
			return
		end

		local relative = bay.CFrame:ToObjectSpace(chassis.CFrame)
		if relative.Position.Magnitude > REPORT_RADIUS then
			return
		end
		local velocity = chassis.AssemblyLinearVelocity - deck:GetVelocityAtPosition(chassis.Position)
		remote:FireServer(relative, velocity)
	end)
end

return ParkReporter
