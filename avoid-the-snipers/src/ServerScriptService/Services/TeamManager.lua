--[[
	TeamManager  (ModuleScript in ServerScriptService/Services)

	Creates Team Green and Team Brown, balances players between them at
	the start of each round, and answers "which team is this player on?".
	Team keys used everywhere in code: "Green" and "Brown".
]]

local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.GameConfig)

local TeamManager = {}

local teamObjects: { [string]: Team } = {}
TeamManager.TEAM_KEYS = { "Green", "Brown" }

function TeamManager.Init()
	for _, key in TeamManager.TEAM_KEYS do
		local def = GameConfig.TEAMS[key]
		local team = Teams:FindFirstChild(def.Name) :: Team?
		if not team then
			team = Instance.new("Team")
			assert(team)
			team.Name = def.Name
			team.TeamColor = def.TeamColor
			team.AutoAssignable = false -- we assign teams ourselves
			team.Parent = Teams
		end
		assert(team):SetAttribute("TeamKey", key)
		teamObjects[key] = team :: Team
	end
end

function TeamManager.GetTeam(key: string): Team
	return teamObjects[key]
end

-- Returns "Green", "Brown" or nil (in the lobby).
function TeamManager.GetTeamKey(player: Player): string?
	if player.Neutral or not player.Team then
		return nil
	end
	return player.Team:GetAttribute("TeamKey") :: any
end

function TeamManager.GetEnemyKey(key: string): string
	return if key == "Green" then "Brown" else "Green"
end

function TeamManager.AreEnemies(a: Player, b: Player): boolean
	local ka, kb = TeamManager.GetTeamKey(a), TeamManager.GetTeamKey(b)
	return ka ~= nil and kb ~= nil and ka ~= kb
end

-- Splits `players` into two even teams (shuffled, so teams change each round).
function TeamManager.Balance(players: { Player })
	local shuffled = table.clone(players)
	local rng = Random.new()
	for i = #shuffled, 2, -1 do
		local j = rng:NextInteger(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end
	-- Randomly decide which team gets the odd player out
	local first = if rng:NextNumber() < 0.5 then "Green" else "Brown"
	local second = TeamManager.GetEnemyKey(first)
	for i, player in shuffled do
		local key = if i % 2 == 1 then first else second
		player.Team = teamObjects[key]
		player.Neutral = false
	end
end

-- Puts a player back in the lobby (no team).
function TeamManager.ClearTeam(player: Player)
	(player :: any).Team = nil
	player.Neutral = true
end

return TeamManager
