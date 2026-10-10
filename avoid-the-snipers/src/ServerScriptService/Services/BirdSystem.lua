--[[
	BirdSystem  (ModuleScript in ServerScriptService/Services)

	Anti-camping. Every STILLNESS_CHECK_INTERVAL (0.5 s) the server looks at
	each alive player:

	  * Moved at least STILL_MOVE_THRESHOLD studs from where they started
	    standing still?  -> stillness timer resets to 0.
	  * Otherwise the stillness timer goes up.

	  stillness >= STILLNESS_WARNING_TIME (20 s)
	      -> 3-4 birds fly up WARNING_REVEAL_OFFSET (25) studs away (rough area)
	  stillness >= STILLNESS_DANGER_TIME (40 s)
	      -> 8-10 birds + crow calls only DANGER_REVEAL_OFFSET (8) studs away,
	         repeated every DANGER_REPEAT_INTERVAL (10 s)

	  Sprinting through tall grass: SPRINT_BIRD_CHANCE per second of 1-2 birds.

	The SERVER decides where and when birds appear. It then tells every
	client "birds at X" and the clients animate them (smooth and cheap).
	The stillness timer is never sent to the player.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MapBuilder = require(script.Parent.MapBuilder)
local MovementService = require(script.Parent.MovementService)
local RoundState = require(script.Parent.RoundState)

local BirdSystem = {}

type Tracker = {
	Anchor: Vector3, -- where the player started standing still
	Stillness: number, -- seconds spent near the anchor
	WarnedAt: number?, -- stillness value when the warning flock fired
	LastDangerAt: number?, -- stillness value when the last danger flock fired
}

local trackers: { [Player]: Tracker } = {}
local running = false
local rng = Random.new()

local function randomCount(range: { number }): number
	return rng:NextInteger(range[1], range[2])
end

-- A point `distance` studs away from `center` in a random direction, on the ground.
local function pointAround(center: Vector3, distance: number): Vector3
	local angle = rng:NextNumber(0, math.pi * 2)
	local d = distance * rng:NextNumber(0.8, 1.2)
	local x, z = center.X + math.cos(angle) * d, center.Z + math.sin(angle) * d
	return Vector3.new(x, MapBuilder.GroundY(x, z), z)
end

-- Sends a flock to every client. kind: "Warning" | "Danger" | "Sprint"
function BirdSystem.SpawnFlock(position: Vector3, count: number, kind: string)
	Remotes.Get("BirdFlock"):FireAllClients(position, count, kind)
end

-- Lets the player's own HUD show a small bird icon (not the timer!).
local function flagPlayer(player: Player)
	player:SetAttribute("BirdsSpottedAt", workspace:GetServerTimeNow())
end

local function rootPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root then (root :: BasePart).Position else nil
end

local function tick(dt: number)
	-- chance per tick from a chance per second: 1 - (1 - p)^dt
	local sprintChance = 1 - (1 - GameConfig.SPRINT_BIRD_CHANCE) ^ dt

	for player in RoundState.Alive do
		local position = rootPosition(player)
		if not position then
			continue
		end

		local tracker = trackers[player]
		if not tracker then
			tracker = { Anchor = position, Stillness = 0 }
			trackers[player] = tracker
		end

		-- 1) Stillness
		if (position - tracker.Anchor).Magnitude >= GameConfig.STILL_MOVE_THRESHOLD then
			-- Real movement: start over from here
			tracker.Anchor = position
			tracker.Stillness = 0
			tracker.WarnedAt = nil
			tracker.LastDangerAt = nil
		else
			tracker.Stillness += dt
			local still = tracker.Stillness

			if still >= GameConfig.STILLNESS_DANGER_TIME then
				local due = tracker.LastDangerAt == nil
					or still - (tracker.LastDangerAt :: number) >= GameConfig.DANGER_REPEAT_INTERVAL
				if due then
					tracker.LastDangerAt = still
					BirdSystem.SpawnFlock(
						pointAround(position, GameConfig.DANGER_REVEAL_OFFSET),
						randomCount(GameConfig.DANGER_FLOCK_SIZE),
						"Danger"
					)
					flagPlayer(player)
				end
			elseif still >= GameConfig.STILLNESS_WARNING_TIME and not tracker.WarnedAt then
				tracker.WarnedAt = still
				BirdSystem.SpawnFlock(
					pointAround(position, GameConfig.WARNING_REVEAL_OFFSET),
					randomCount(GameConfig.WARNING_FLOCK_SIZE),
					"Warning"
				)
				flagPlayer(player)
			end
		end

		-- 2) Sprinting through tall grass scares birds
		if MovementService.IsSprinting(player) and MapBuilder.IsInTallGrass(position) then
			if rng:NextNumber() < sprintChance then
				BirdSystem.SpawnFlock(pointAround(position, 4), randomCount(GameConfig.SPRINT_FLOCK_SIZE), "Sprint")
			end
		end
	end

	-- Forget players who are no longer alive
	for player in trackers do
		if not RoundState.Alive[player] then
			trackers[player] = nil
		end
	end
end

function BirdSystem.Start()
	if running then
		return
	end
	running = true
	table.clear(trackers)
	task.spawn(function()
		local interval = GameConfig.STILLNESS_CHECK_INTERVAL
		while running do
			local dt = task.wait(interval)
			if running then
				tick(math.min(dt, interval * 2))
			end
		end
	end)
end

function BirdSystem.Stop()
	running = false
	table.clear(trackers)
end

return BirdSystem
