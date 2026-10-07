--[[
	SafeZoneService  (ModuleScript in ServerScriptService/Services)

	Each ruin house has an invisible sphere (SPAWN_SAFE_ZONE_RADIUS) around it.
	  * Your OWN zone: you can't be hurt there for SPAWN_PROTECTION_TIME
	    after the round starts (checked by DamageService), and it's where
	    the shop works.
	  * The ENEMY zone: you take damage over time and see a warning.

	The warning is shown by setting the player attribute "InEnemyZone";
	the client HUD just displays it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local MapBuilder = require(script.Parent.MapBuilder)
local RoundState = require(script.Parent.RoundState)
local TeamManager = require(script.Parent.TeamManager)

local SafeZoneService = {}

local TICK = 0.5
local running = false

local function rootPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root then (root :: BasePart).Position else nil
end

-- Is `position` inside the safe zone of the given team's ruin house?
function SafeZoneService.IsInsideZone(position: Vector3, teamKey: string): boolean
	local house = MapBuilder.Info.Houses[teamKey]
	if not house or not house.Center then
		return false
	end
	return (position - house.Center).Magnitude <= GameConfig.SPAWN_SAFE_ZONE_RADIUS
end

function SafeZoneService.IsInOwnSafeZone(player: Player): boolean
	local key = TeamManager.GetTeamKey(player)
	local pos = rootPosition(player)
	return key ~= nil and pos ~= nil and SafeZoneService.IsInsideZone(pos, key)
end

function SafeZoneService.IsInEnemySafeZone(player: Player): boolean
	local key = TeamManager.GetTeamKey(player)
	local pos = rootPosition(player)
	return key ~= nil and pos ~= nil and SafeZoneService.IsInsideZone(pos, TeamManager.GetEnemyKey(key))
end

-- Starts the damage-over-time loop. `damageFn(player, amount)` is passed
-- in by RoundManager (it's DamageService.ApplyZoneDamage).
function SafeZoneService.Start(damageFn: (Player, number) -> ())
	if running then
		return
	end
	running = true
	task.spawn(function()
		while running do
			for player in RoundState.Alive do
				local inside = SafeZoneService.IsInEnemySafeZone(player)
				if player:GetAttribute("InEnemyZone") ~= inside then
					player:SetAttribute("InEnemyZone", inside)
				end
				if inside then
					damageFn(player, GameConfig.ENEMY_SAFE_ZONE_DPS * TICK)
				end
			end
			task.wait(TICK)
		end
	end)
end

function SafeZoneService.Stop()
	running = false
	for _, player in Players:GetPlayers() do
		player:SetAttribute("InEnemyZone", false)
	end
end

return SafeZoneService
