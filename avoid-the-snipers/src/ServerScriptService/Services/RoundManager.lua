--[[
	RoundManager  (ModuleScript in ServerScriptService/Services)

	The game loop. Runs forever on the server:

	  Waiting      until MIN_PLAYERS_TO_START players pressed "Play"
	  CamoSelect   teams balanced, players spawn (frozen) in their ruin
	               house and pick a camo (CAMO_SELECT_TIME)
	  Round        one life each, ROUND_TIME seconds. Ends early when a
	               team has nobody alive.
	  Results      banner + coins (RESULTS_TIME)
	  Intermission everyone back to the lobby with normal avatars
	               (INTERMISSION_TIME), then repeat

	Clients never decide anything here. They only READ the attributes of
	ReplicatedStorage.GameStatus (State, EndsAt, alive counts, banner).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local BirdSystem = require(script.Parent.BirdSystem)
local BotService = require(script.Parent.BotService)
local CamoManager = require(script.Parent.CamoManager)
local DamageService = require(script.Parent.DamageService)
local DataService = require(script.Parent.DataService)
local ItemService = require(script.Parent.ItemService)
local MovementService = require(script.Parent.MovementService)
local RoundState = require(script.Parent.RoundState)
local SafeZoneService = require(script.Parent.SafeZoneService)
local ShopService = require(script.Parent.ShopService)
local SniperService = require(script.Parent.SniperService)
local TeamManager = require(script.Parent.TeamManager)

local RoundManager = {}

local status = Remotes.GetStatus()

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function setStatus(state: string, duration: number?, text: string?)
	status:SetAttribute("State", state)
	status:SetAttribute("EndsAt", if duration then serverNow() + duration else 0)
	status:SetAttribute("StatusText", text or "")
end

local function notify(player: Player, text: string)
	if RoundState.IsBot(player) then
		return -- bots have no screen
	end
	Remotes.Get("Notify"):FireClient(player, text)
end

-- Players who pressed Play on the main menu
local function readyPlayers(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Ready") then
			table.insert(list, player)
		end
	end
	return list
end

local function participantList(): { Player }
	local list = {}
	for player in RoundState.Participants do
		table.insert(list, player)
	end
	return list
end

local function countAlive(): (number, number)
	local green, brown = 0, 0
	for player in RoundState.Alive do
		local key = RoundState.Participants[player]
		if key == "Green" then
			green += 1
		elseif key == "Brown" then
			brown += 1
		end
	end
	return green, brown
end

local function updateAliveCounts()
	local green, brown = countAlive()
	status:SetAttribute("GreenAlive", green)
	status:SetAttribute("BrownAlive", brown)
end

-- Respawns a player in the lobby with no team (restores their normal avatar).
local function spawnInLobby(player: Player)
	if not player.Parent then
		return
	end
	TeamManager.ClearTeam(player)
	player:SetAttribute("Spectating", false)
	MovementService.SetFrozen(player, false)
	player:LoadCharacterAsync()
end

-- Waits until every player in `list` has a character (max `timeout` s).
local function waitForCharacters(list: { Player }, timeout: number)
	local start = os.clock()
	while os.clock() - start < timeout do
		local allReady = true
		for _, player in list do
			if player.Parent and not player.Character then
				allReady = false
				break
			end
		end
		if allReady then
			return
		end
		task.wait(0.1)
	end
end

---------------------------------------------------------------------------
-- Deaths
---------------------------------------------------------------------------
local function onParticipantDied(player: Player)
	if not RoundState.Alive[player] then
		return
	end
	RoundState.Alive[player] = nil
	player:SetAttribute("Spectating", true) -- client starts spectating teammates

	local hit = DamageService.GetLastHit(player)
	local killer = hit and hit.Attacker
	if killer and killer.Parent and killer ~= player then
		DataService.AddKill(killer)
		local coins = GameConfig.COINS_PER_KILL
		local text = ("+%d Coins (elimination)"):format(GameConfig.COINS_PER_KILL)
		if hit.Headshot then
			coins += GameConfig.COINS_HEADSHOT_BONUS
			text = ("+%d Coins (elimination + headshot)"):format(coins)
		end
		DataService.AddCoins(killer, coins)
		notify(killer, text)
		-- Just "X eliminated Y" - never where it happened
		Remotes.Get("KillFeed"):FireAllClients(killer.Name, player.Name, hit.Headshot)
	else
		Remotes.Get("KillFeed"):FireAllClients(nil, player.Name, false)
	end
	updateAliveCounts()
end

-- Called for EVERY character that spawns, in the lobby or in a round.
local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	humanoid.Died:Connect(function()
		if RoundState.Participants[player] and (RoundState.Phase == "Round" or RoundState.Phase == "CamoSelect") then
			onParticipantDied(player)
		else
			-- Died in the lobby (fell off?) - respawn there after a moment
			task.delay(3, function()
				if player.Parent and player.Character == character and not RoundState.Participants[player] then
					spawnInLobby(player)
				end
			end)
		end
	end)
end

---------------------------------------------------------------------------
-- Phases
---------------------------------------------------------------------------
local function waitingPhase()
	RoundState.Phase = "Waiting"
	-- With bots on, one real player is enough (bots fill the teams)
	local needed = if GameConfig.BOTS_ENABLED then 1 else GameConfig.MIN_PLAYERS_TO_START
	while true do
		local count = #readyPlayers()
		if count >= needed then
			return
		end
		setStatus("Waiting", nil, ("Waiting for players (%d/%d)"):format(count, needed))
		task.wait(1)
	end
end

local function camoSelectPhase(): boolean
	local players = readyPlayers()
	TeamManager.Balance(players)

	table.clear(RoundState.Participants)
	table.clear(RoundState.Alive)
	for _, player in players do
		RoundState.Participants[player] = TeamManager.GetTeamKey(player) :: string
	end

	RoundState.Phase = "CamoSelect"
	setStatus("CamoSelect", GameConfig.CAMO_SELECT_TIME, "Choose your camouflage")

	-- Spawn everyone (frozen) inside their team's ruin house
	for _, player in players do
		MovementService.SetFrozen(player, true)
		player:SetAttribute("Spectating", false)
		task.spawn(function()
			player:LoadCharacterAsync()
		end)
	end
	waitForCharacters(players, 5)

	local endsAt = serverNow() + GameConfig.CAMO_SELECT_TIME
	CamoManager.BeginSelection(players, endsAt)

	-- Fill the teams with bots (only if GameConfig.BOTS_ENABLED).
	-- Done after BeginSelection, which resets everyone's camo choice.
	for _, bot in BotService.FillTeams(players) do
		RoundState.Participants[bot] = bot.TeamKey
		task.spawn(BotService.SpawnBot, bot, function()
			onParticipantDied(bot)
		end)
	end
	while serverNow() < endsAt and not CamoManager.AllChosen(participantList()) do
		task.wait(0.25)
	end
	CamoManager.FinalizeSelection(participantList())

	-- Abort if a whole team left during selection
	local green, brown = 0, 0
	for player, key in RoundState.Participants do
		if player.Parent and player.Character then
			if key == "Green" then
				green += 1
			else
				brown += 1
			end
		end
	end
	return green > 0 and brown > 0
end

local function roundPhase()
	RoundState.Phase = "Round"
	RoundState.RoundStartedAt = os.clock()
	status:SetAttribute("RoundStartedAt", serverNow())
	setStatus("Round", GameConfig.ROUND_TIME, "")
	DamageService.Reset()
	ShopService.ResetRound()

	for player in RoundState.Participants do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			RoundState.Alive[player] = true
			MovementService.SetFrozen(player, false)
			SniperService.GiveSniper(player)
		end
	end
	updateAliveCounts()

	BirdSystem.Start()
	SafeZoneService.Start(DamageService.ApplyZoneDamage)
	BotService.StartAI()

	local endTime = os.clock() + GameConfig.ROUND_TIME
	while os.clock() < endTime do
		local green, brown = countAlive()
		if green == 0 or brown == 0 then
			break
		end
		task.wait(0.25)
	end
end

local function resultsPhase()
	RoundState.Phase = "Results"
	BotService.StopAI()
	BirdSystem.Stop()
	SafeZoneService.Stop()
	updateAliveCounts()

	-- Decide the winner
	local green, brown = countAlive()
	local winnerKey: string? = nil
	local reason
	if green > 0 and brown == 0 then
		winnerKey, reason = "Green", "All enemies eliminated"
	elseif brown > 0 and green == 0 then
		winnerKey, reason = "Brown", "All enemies eliminated"
	elseif green > brown then
		winnerKey, reason = "Green", "More players alive"
	elseif brown > green then
		winnerKey, reason = "Brown", "More players alive"
	end

	local banner
	if winnerKey then
		banner = ("%s wins! (%s)"):format(GameConfig.TEAMS[winnerKey].Name, reason)
	else
		banner = "Draw! Both teams have the same number of players alive."
	end
	status:SetAttribute("ResultText", banner)
	setStatus("Results", GameConfig.RESULTS_TIME, banner)

	-- Rewards (server only)
	for player, key in RoundState.Participants do
		if player.Parent then
			local earned = 0
			if RoundState.Alive[player] then
				earned += GameConfig.COINS_FOR_SURVIVING
			end
			if winnerKey and key == winnerKey then
				earned += GameConfig.COINS_PER_ROUND_WIN
				DataService.AddWin(player)
			end
			if earned > 0 and not RoundState.IsBot(player) then
				DataService.AddCoins(player, earned)
				notify(player, ("+%d Coins this round"):format(earned))
			end
			if not RoundState.IsBot(player) then
				SniperService.RemoveSniper(player)
				ItemService.RemoveItems(player)
			end
		end
	end

	task.wait(GameConfig.RESULTS_TIME)
	status:SetAttribute("ResultText", "")
end

local function intermissionPhase()
	RoundState.Phase = "Intermission"
	BotService.DespawnAll()
	table.clear(RoundState.Participants)
	table.clear(RoundState.Alive)
	RoundState.RoundStartedAt = 0
	status:SetAttribute("RoundStartedAt", 0)
	updateAliveCounts()
	setStatus("Intermission", GameConfig.INTERMISSION_TIME, "Next round soon")

	-- Everyone back to the lobby with their normal avatar
	for _, player in Players:GetPlayers() do
		task.spawn(spawnInLobby, player)
	end
	task.wait(GameConfig.INTERMISSION_TIME)
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------
function RoundManager.Init()
	-- Main menu "Play" button. The only thing a client can do here is
	-- say "I'm ready" - there are no arguments to trust.
	Remotes.Get("PlayerReady").OnServerEvent:Connect(function(player)
		player:SetAttribute("Ready", true)
	end)

	local function setup(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		-- New players start in the lobby
		task.spawn(spawnInLobby, player)
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		if RoundState.Participants[player] then
			RoundState.Participants[player] = nil
			RoundState.Alive[player] = nil
			updateAliveCounts()
		end
	end)

	status:SetAttribute("GreenAlive", 0)
	status:SetAttribute("BrownAlive", 0)
	status:SetAttribute("ResultText", "")
	status:SetAttribute("RoundStartedAt", 0)
end

-- The forever loop. Call once, it never returns.
function RoundManager.Run()
	while true do
		waitingPhase()
		local ok = camoSelectPhase()
		if ok then
			roundPhase()
			resultsPhase()
		else
			setStatus("Results", 3, "Round cancelled - not enough players")
			for player in RoundState.Participants do
				MovementService.SetFrozen(player, false)
			end
			task.wait(3)
		end
		intermissionPhase()
	end
end

return RoundManager
