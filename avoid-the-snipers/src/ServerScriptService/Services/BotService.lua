--[[
	BotService  (ModuleScript in ServerScriptService/Services)

	AI snipers so you can play alone in Studio. Turn off with
	GameConfig.BOTS_ENABLED = false.

	A bot is a small Lua table that looks like a Player to the rest of
	the game (Name, Team, Character, Get/SetAttribute). That means bots go
	through the SAME server systems as you: DamageService, spawn
	protection, safe zones, birds, footstep sounds, camo, kill feed.

	THE BRAIN (runs on the server every 0.25 s per bot)
	  * Move between hiding spots (tall grass, ruins) in the middle zone.
	    Sprints when far away (loud rustling, birds in grass!).
	  * Hide crouched for BOT_HIDE_TIME, then move on. Sometimes they
	    stay too long and the birds give them away, just like players.
	  * Spot enemies: needs line of sight within BOT_VIEW_RANGE. A
	    player crouching in tall grass is only seen within
	    BOT_SPOT_CROUCHED_IN_GRASS studs. Camo and grass really work.
	  * After seeing a target for BOT_REACTION_TIME, shoot with an aim
	    error that grows with distance (BOT_SPREAD).
	  * When hit, run to a new spot.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local CamoManager = require(script.Parent.CamoManager)
local MapBuilder = require(script.Parent.MapBuilder)
local MovementService = require(script.Parent.MovementService)
local RoundState = require(script.Parent.RoundState)
local SniperService = require(script.Parent.SniperService)
local TeamManager = require(script.Parent.TeamManager)

local BotService = {}

local NAMES = { "Viper", "Hawk", "Fern", "Cobra", "Ghost", "Raven", "Badger", "Lynx", "Otter", "Moss", "Thorn", "Jackal" }

-- Default Roblox R15 animations (played on the server so everyone sees them)
local ANIMATIONS = {
	Idle = "rbxassetid://507766388",
	Walk = "rbxassetid://507777826",
	Run = "rbxassetid://507767714",
}

local rng = Random.new()
local bots: { any } = {}
local aiRunning = false
local botFolder: Folder? = nil

---------------------------------------------------------------------------
-- The fake "Player" object
---------------------------------------------------------------------------
local Bot = {}
Bot.__index = Bot

function Bot.new(name: string, teamKey: string)
	local self = setmetatable({
		IsBot = true,
		Name = name,
		DisplayName = name,
		UserId = -rng:NextInteger(1000, 999999),
		Team = TeamManager.GetTeam(teamKey),
		Neutral = false,
		Parent = workspace, -- "still in the game"
		Character = nil :: Model?,
		TeamKey = teamKey,
		Attributes = {},
		Brain = nil :: any,
	}, Bot)
	return self
end

function Bot:GetAttribute(key: string)
	return self.Attributes[key]
end

function Bot:SetAttribute(key: string, value: any)
	self.Attributes[key] = value
end

-- Bots have no leaderstats / Backpack / PlayerGui
function Bot:FindFirstChild(_name: string)
	return nil
end

function Bot:FindFirstChildOfClass(_className: string)
	return nil
end

---------------------------------------------------------------------------
-- Character
---------------------------------------------------------------------------
local function getFolder(): Folder
	if not botFolder or not botFolder.Parent then
		local folder = Instance.new("Folder")
		folder.Name = "Bots"
		folder.Parent = workspace
		botFolder = folder
	end
	return botFolder :: Folder
end

local function setupAnimations(bot: any, humanoid: Humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local tracks = {}
	for name, id in ANIMATIONS do
		local ok, track = pcall(function()
			local animation = Instance.new("Animation")
			animation.AnimationId = id
			return animator:LoadAnimation(animation)
		end)
		if ok and track then
			track.Looped = true
			tracks[name] = track
		end
	end
	bot.Tracks = tracks
	bot.CurrentTrack = nil
end

local function playTrack(bot: any, name: string)
	if bot.CurrentTrack == name or not bot.Tracks then
		return
	end
	local old = bot.CurrentTrack and bot.Tracks[bot.CurrentTrack]
	if old then
		old:Stop(0.2)
	end
	local track = bot.Tracks[name]
	if track then
		track:Play(0.2)
	end
	bot.CurrentTrack = name
end

-- Builds the bot's body and puts it in its team's ruin house.
local function spawnCharacter(bot: any, onDied: () -> ()): boolean
	local ok, character = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end)
	if not ok or not character then
		warn("[BotService] Could not create a bot body:", character)
		return false
	end
	character.Name = bot.Name
	character:SetAttribute("TeamKey", bot.TeamKey) -- clients use this for teammate names/spectating

	-- The client-side Animate script doesn't run for NPCs; we animate on the server
	local animate = character:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	humanoid.DisplayName = bot.Name

	local house = MapBuilder.Info.Houses[bot.TeamKey]
	local center = if house and house.Center then house.Center else Vector3.new(0, 10, 0)
	local spawnPos = center + Vector3.new(rng:NextNumber(-4, 4), 1, rng:NextNumber(-5, 5))
	character:PivotTo(CFrame.lookAt(spawnPos, Vector3.new(0, spawnPos.Y, 0)))
	character.Parent = getFolder()
	root:SetNetworkOwner(nil) -- the server moves bots

	bot.Character = character
	RoundState.BotByCharacter[character] = bot
	setupAnimations(bot, humanoid)
	MovementService.SetupCharacter(bot, character)

	humanoid.Died:Connect(function()
		playTrack(bot, "")
		onDied()
	end)
	return true
end

---------------------------------------------------------------------------
-- Public: creating / removing bots
---------------------------------------------------------------------------

-- Adds bots so each team has at least BOTS_FILL_TEAM_TO members (and both
-- teams are the same size). Returns the new bots.
function BotService.FillTeams(players: { Player }): { any }
	if not GameConfig.BOTS_ENABLED then
		return {}
	end
	local counts = { Green = 0, Brown = 0 }
	for _, player in players do
		local key = TeamManager.GetTeamKey(player)
		if key then
			counts[key] += 1
		end
	end
	local target = math.max(GameConfig.BOTS_FILL_TEAM_TO, counts.Green, counts.Brown)

	local created = {}
	local nameIndex = rng:NextInteger(1, #NAMES)
	for _, key in TeamManager.TEAM_KEYS do
		for _ = counts[key] + 1, target do
			local name = "Bot " .. NAMES[(nameIndex % #NAMES) + 1]
			nameIndex += 1
			local bot = Bot.new(name, key)
			table.insert(bots, bot)
			table.insert(created, bot)
		end
	end
	return created
end

-- Spawns a bot's body (frozen until the round starts) and picks its camo.
function BotService.SpawnBot(bot: any, onDied: () -> ())
	MovementService.SetFrozen(bot, true)
	if spawnCharacter(bot, onDied) then
		CamoManager.ChooseForBot(bot)
	end
end

function BotService.DespawnAll()
	aiRunning = false
	for _, bot in bots do
		if bot.Character then
			RoundState.BotByCharacter[bot.Character] = nil
			bot.Character:Destroy()
		end
		bot.Parent = nil
		MovementService.Forget(bot)
	end
	table.clear(bots)
end

---------------------------------------------------------------------------
-- The brain
---------------------------------------------------------------------------
type Brain = {
	State: string, -- "Moving" | "Hiding"
	Waypoint: Vector3?,
	HideUntil: number,
	LastPosition: Vector3,
	StuckSince: number,
	LastHealth: number,
	Target: Model?,
	SeenSince: number?,
}

local function parts(bot: any): (Model?, Humanoid?, BasePart?, BasePart?)
	local character = bot.Character
	if not character then
		return nil, nil, nil, nil
	end
	return character,
		character:FindFirstChildOfClass("Humanoid"),
		character:FindFirstChild("HumanoidRootPart") :: BasePart?,
		character:FindFirstChild("Head") :: BasePart?
end

-- A hiding spot in the middle zone (never inside a spawn safe zone).
local function pickWaypoint(): Vector3
	local patches = MapBuilder.Info.GrassPatches
	for _ = 1, 10 do
		local candidate
		if #patches > 0 and rng:NextNumber() < 0.75 then
			local patch = patches[rng:NextInteger(1, #patches)]
			candidate = patch.Position
		else
			candidate = Vector3.new(rng:NextNumber(-160, 160), 0, rng:NextNumber(-120, 120))
		end
		if math.abs(candidate.X) <= 175 then
			return Vector3.new(candidate.X, MapBuilder.GroundY(candidate.X, candidate.Z), candidate.Z)
		end
	end
	return Vector3.new(0, MapBuilder.GroundY(0, 0), 0)
end

-- Every alive enemy of this bot (players AND bots)
local function enemiesOf(bot: any): { Model }
	local list = {}
	for combatant in RoundState.Alive do
		local key = RoundState.Participants[combatant]
		local character = (combatant :: any).Character
		if key and key ~= bot.TeamKey and character then
			table.insert(list, character)
		end
	end
	return list
end

-- Can the bot see this enemy right now? Uses the same "hidden in grass"
-- rules as a human would face: crouching in tall grass = very hard to see.
local function canSee(bot: any, myHead: BasePart, enemy: Model): (boolean, number)
	local enemyHead = enemy:FindFirstChild("Head") :: BasePart?
	local enemyRoot = enemy:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not enemyHead or not enemyRoot then
		return false, math.huge
	end
	local distance = (enemyHead.Position - myHead.Position).Magnitude
	if distance > GameConfig.BOT_VIEW_RANGE then
		return false, distance
	end

	if MapBuilder.IsInTallGrass(enemyRoot.Position) then
		local limit = if enemy:GetAttribute("Stance") == "Crouch"
			then GameConfig.BOT_SPOT_CROUCHED_IN_GRASS
			else GameConfig.BOT_SPOT_STANDING_IN_GRASS
		if distance > limit then
			return false, distance
		end
	end

	-- Line of sight (rocks, walls, logs block it; grass doesn't block rays,
	-- which is why the grass rule above exists)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bot.Character }
	for _, targetPart in { enemyHead, enemyRoot } do
		local direction = targetPart.Position - myHead.Position
		local result = workspace:Raycast(myHead.Position, direction, params)
		if not result or result.Instance:IsDescendantOf(enemy) then
			return true, distance
		end
	end
	return false, distance
end

local function shootAt(bot: any, myHead: BasePart, enemy: Model)
	local aimPart: BasePart? = nil
	if rng:NextNumber() < GameConfig.BOT_HEADSHOT_CHANCE then
		aimPart = enemy:FindFirstChild("Head") :: BasePart?
	end
	aimPart = aimPart
		or enemy:FindFirstChild("UpperTorso") :: BasePart?
		or enemy:FindFirstChild("Torso") :: BasePart?
		or enemy:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not aimPart then
		return
	end
	local distance = (aimPart.Position - myHead.Position).Magnitude
	-- Aim error grows with distance
	local spread = distance * GameConfig.BOT_SPREAD
	local offset = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * spread
	SniperService.BotFire(bot, aimPart.Position + offset)
end

local function think(bot: any, now: number)
	local character, humanoid, root, head = parts(bot)
	if not character or not humanoid or not root or not head or humanoid.Health <= 0 then
		return
	end
	local brain: Brain = bot.Brain
	if not brain then
		brain = {
			State = "Moving",
			Waypoint = nil,
			HideUntil = 0,
			LastPosition = root.Position,
			StuckSince = now,
			LastHealth = humanoid.Health,
			Target = nil,
			SeenSince = nil,
		}
		bot.Brain = brain
	end

	-- Animation from actual speed
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	playTrack(bot, if speed > GameConfig.WALK_SPEED + 2 then "Run" elseif speed > 1 then "Walk" else "Idle")

	-- Got shot? Run somewhere else.
	if humanoid.Health < brain.LastHealth then
		brain.LastHealth = humanoid.Health
		brain.State = "Moving"
		brain.Waypoint = pickWaypoint()
		brain.Target = nil
		brain.SeenSince = nil
		MovementService.SetStance(bot, "Sprint")
		humanoid:MoveTo(brain.Waypoint)
		return
	end

	-- Look for the closest visible enemy
	local best: Model? = nil
	local bestDistance = math.huge
	for _, enemy in enemiesOf(bot) do
		local visible, distance = canSee(bot, head, enemy)
		if visible and distance < bestDistance then
			best, bestDistance = enemy, distance
		end
	end

	if best then
		if brain.Target ~= best then
			brain.Target = best
			brain.SeenSince = now
		end
		-- Stop, face the target, and shoot after the reaction time
		humanoid:MoveTo(root.Position)
		local targetRoot = best:FindFirstChild("HumanoidRootPart") :: BasePart?
		if targetRoot then
			root.CFrame = CFrame.lookAt(root.Position, Vector3.new(targetRoot.Position.X, root.Position.Y, targetRoot.Position.Z))
		end
		if now - (brain.SeenSince :: number) >= GameConfig.BOT_REACTION_TIME then
			shootAt(bot, head, best)
		end
		return
	end
	brain.Target = nil
	brain.SeenSince = nil

	if brain.State == "Hiding" then
		if now >= brain.HideUntil then
			brain.State = "Moving"
			brain.Waypoint = pickWaypoint()
			brain.StuckSince = now
			brain.LastPosition = root.Position
		end
		return
	end

	-- Moving
	if not brain.Waypoint then
		brain.Waypoint = pickWaypoint()
	end
	local waypoint = brain.Waypoint :: Vector3
	local flat = Vector3.new(waypoint.X - root.Position.X, 0, waypoint.Z - root.Position.Z)
	if flat.Magnitude < 4 then
		-- Arrived: crouch and hide for a while
		brain.State = "Hiding"
		brain.HideUntil = now + rng:NextNumber(GameConfig.BOT_HIDE_TIME[1], GameConfig.BOT_HIDE_TIME[2])
		MovementService.SetStance(bot, "Crouch")
		humanoid:MoveTo(root.Position)
		return
	end

	MovementService.SetStance(bot, if flat.Magnitude > 60 then "Sprint" else "Walk")
	humanoid:MoveTo(waypoint)

	-- Stuck on a rock? Jump, and after a while pick another spot.
	if (root.Position - brain.LastPosition).Magnitude > 2 then
		brain.LastPosition = root.Position
		brain.StuckSince = now
	elseif now - brain.StuckSince > 1.5 then
		humanoid.Jump = true
		if now - brain.StuckSince > 4 then
			brain.Waypoint = pickWaypoint()
			brain.StuckSince = now
		end
	end
end

function BotService.StartAI()
	if aiRunning or #bots == 0 then
		return
	end
	aiRunning = true
	for _, bot in bots do
		bot.Brain = nil
	end
	task.spawn(function()
		while aiRunning do
			local now = os.clock()
			for _, bot in bots do
				if RoundState.IsRoundActive() and RoundState.IsAlive(bot) then
					local ok, err = pcall(think, bot, now)
					if not ok then
						warn("[BotService] " .. bot.Name .. ": " .. tostring(err))
					end
				end
			end
			task.wait(0.25)
		end
	end)
end

function BotService.StopAI()
	aiRunning = false
	for _, bot in bots do
		local _, humanoid, root = parts(bot)
		if humanoid and root then
			humanoid:MoveTo(root.Position)
		end
		playTrack(bot, "Idle")
	end
end

return BotService
