--!strict
-- Server entry point: build the arena, then run matches forever.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TrackPath = require(Shared:WaitForChild("TrackPath"))

local Server = script.Parent
local MapBuilder = require(Server:WaitForChild("MapBuilder"))
local CarService = require(Server:WaitForChild("CarService"))
local MatchManager = require(Server:WaitForChild("MatchManager"))

-- Players drive cars, not avatars; the camera is fully scripted on the client.
Players.CharacterAutoLoads = false

local path = TrackPath.new(Config.Track.ControlPoints)
local arena = MapBuilder.Build(path)

CarService.Init(arena:FindFirstChild("Surface"))
MatchManager.Init(path)
MatchManager.Run()
