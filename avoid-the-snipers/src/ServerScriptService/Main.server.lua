--[[
	Main  (Script in ServerScriptService)

	The one server Script. It starts every system in the right order and
	then runs the round loop forever. All the real logic lives in the
	ModuleScripts inside ServerScriptService/Services.
]]

local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")

local Services = script.Parent:WaitForChild("Services")

-- Place settings the game depends on (set here so you don't have to
-- remember them in Studio):
Players.CharacterAutoLoads = false -- the RoundManager decides when people spawn (one life per round)
StarterPlayer.EnableMouseLockOption = false -- Shift is sprint, not shift-lock

-- Creating the Remotes first so clients can find them right away
require(game:GetService("ReplicatedStorage").Shared.Remotes)

local TeamManager = require(Services.TeamManager)
local MapBuilder = require(Services.MapBuilder)
local DataService = require(Services.DataService)
local MovementService = require(Services.MovementService)
local CamoManager = require(Services.CamoManager)
local SniperService = require(Services.SniperService)
local ItemService = require(Services.ItemService)
local ShopService = require(Services.ShopService)
local RoundManager = require(Services.RoundManager)

TeamManager.Init() -- teams must exist before the map's SpawnLocations
MapBuilder.Build()
DataService.Init()
MovementService.Init()
CamoManager.Init()
SniperService.Init()
ItemService.Init()
ShopService.Init() -- needs the map's supply crates
RoundManager.Init()

print("[Avoid the Snipers] Server ready")
RoundManager.Run()
