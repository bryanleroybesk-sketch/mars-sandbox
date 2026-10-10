--[[
	GameConfig  (ModuleScript in ReplicatedStorage)

	EVERY tunable number in "Avoid the Snipers" lives here.
	Both the server and the clients read this file, but only the SERVER
	ever makes decisions with it (damage, coins, round timing, etc.).
	Changing a value here on the client does nothing to the real game.

	Times are in seconds, distances are in studs.
]]

local GameConfig = {}

---------------------------------------------------------------------------
-- ROUND FLOW
---------------------------------------------------------------------------
GameConfig.MIN_PLAYERS_TO_START = 2 -- players who pressed "Play"
GameConfig.CAMO_SELECT_TIME = 15
GameConfig.ROUND_TIME = 180
GameConfig.RESULTS_TIME = 6 -- how long the results banner stays up
GameConfig.INTERMISSION_TIME = 10
GameConfig.SPAWN_PROTECTION_TIME = 3

---------------------------------------------------------------------------
-- BIRDS (anti-camping)
---------------------------------------------------------------------------
GameConfig.STILLNESS_CHECK_INTERVAL = 0.5 -- how often the server samples positions
GameConfig.STILLNESS_WARNING_TIME = 20 -- first, small bird reveal
GameConfig.STILLNESS_DANGER_TIME = 40 -- strong bird reveal
GameConfig.DANGER_REPEAT_INTERVAL = 10 -- repeat strong reveal while still
GameConfig.STILL_MOVE_THRESHOLD = 2 -- moving less than this counts as "still"
GameConfig.WARNING_REVEAL_OFFSET = 25 -- birds appear this far from the player
GameConfig.DANGER_REVEAL_OFFSET = 8
GameConfig.SPRINT_BIRD_CHANCE = 0.15 -- chance PER SECOND while sprinting in tall grass

GameConfig.WARNING_FLOCK_SIZE = { 3, 4 } -- {min, max}
GameConfig.DANGER_FLOCK_SIZE = { 8, 10 }
GameConfig.SPRINT_FLOCK_SIZE = { 1, 2 }
GameConfig.WHISTLE_FLOCK_SIZE = { 8, 10 } -- looks just like a danger flock
GameConfig.BIRD_FLIGHT_TIME = 3

---------------------------------------------------------------------------
-- SNIPER
---------------------------------------------------------------------------
GameConfig.HEADSHOT_DAMAGE = 100
GameConfig.BODY_DAMAGE = 60
GameConfig.LIMB_DAMAGE = 35

GameConfig.SNIPER_FIRE_COOLDOWN = 1.5 -- seconds between shots (bolt action)
GameConfig.SNIPER_MAX_RANGE = 1000
GameConfig.SNIPER_HIT_TOLERANCE = 8 -- lag allowance when validating hits
GameConfig.SNIPER_SCOPE_FOV = 12 -- camera FOV while scoped (smaller = more zoom)
GameConfig.SCOPE_SENSITIVITY = 0.25 -- mouse sensitivity multiplier while scoped
GameConfig.FRIENDLY_FIRE = false
GameConfig.TRACER_LIFETIME = 0.6

-- Name of the Weapons Kit sniper you put in ServerStorage/Weapons (see README)
GameConfig.SNIPER_TEMPLATE_NAME = "SniperRifle"

---------------------------------------------------------------------------
-- MOVEMENT
---------------------------------------------------------------------------
GameConfig.WALK_SPEED = 12
GameConfig.CROUCH_SPEED = 6
GameConfig.SPRINT_SPEED = 20
GameConfig.JUMP_HEIGHT = 6

-- Optional: an R15 crouch animation you uploaded. Leave "" to use the
-- built-in "kneel" pose made by bending the leg joints.
GameConfig.CROUCH_ANIMATION_ID = ""

GameConfig.WALK_FOOTSTEP_VOLUME = 0.25
GameConfig.WALK_FOOTSTEP_DISTANCE = 30 -- quiet: only heard close by
GameConfig.SPRINT_RUSTLE_VOLUME = 1.2
GameConfig.SPRINT_RUSTLE_DISTANCE = 90 -- loud: heard from far away

---------------------------------------------------------------------------
-- SPAWNS / SAFE ZONES
---------------------------------------------------------------------------
GameConfig.SPAWN_SAFE_ZONE_RADIUS = 15
GameConfig.ENEMY_SAFE_ZONE_DPS = 20 -- damage per second to enemies camping your spawn

---------------------------------------------------------------------------
-- COINS & SHOP
---------------------------------------------------------------------------
GameConfig.COINS_PER_KILL = 25
GameConfig.COINS_HEADSHOT_BONUS = 15
GameConfig.COINS_PER_ROUND_WIN = 50
GameConfig.COINS_FOR_SURVIVING = 20
GameConfig.SHOP_OPEN_TIME = 20 -- shop only works for the first X seconds of a round

GameConfig.BANDAGE_HEAL = 40
GameConfig.BANDAGE_TIME = 3
GameConfig.SMOKE_DURATION = 8
GameConfig.SMOKE_THROW_RANGE = 60
GameConfig.WHISTLE_RANGE = 150
GameConfig.BINOCULARS_FOV = 25

---------------------------------------------------------------------------
-- TEAMS
---------------------------------------------------------------------------
GameConfig.TEAMS = {
	Green = {
		Name = "Team Green",
		TeamColor = BrickColor.new("Camo"),
		ArmbandColor = Color3.fromRGB(95, 170, 80),
	},
	Brown = {
		Name = "Team Brown",
		TeamColor = BrickColor.new("Brown"),
		ArmbandColor = Color3.fromRGB(165, 105, 55),
	},
}

---------------------------------------------------------------------------
-- BOTS (so you can test alone in Studio)
-- With bots on, a round starts with just 1 player who pressed Play, and
-- each team is filled with bots up to BOTS_FILL_TEAM_TO.
-- Set BOTS_ENABLED = false for real matches.
---------------------------------------------------------------------------
GameConfig.BOTS_ENABLED = true
GameConfig.BOTS_FILL_TEAM_TO = 3
GameConfig.BOT_VIEW_RANGE = 250 -- bots can't spot anyone farther than this
GameConfig.BOT_REACTION_TIME = 1.2 -- must see you this long before firing
GameConfig.BOT_SPREAD = 0.015 -- aim error per stud of distance (higher = worse aim)
GameConfig.BOT_HEADSHOT_CHANCE = 0.25 -- how often they aim for the head
GameConfig.BOT_SPOT_CROUCHED_IN_GRASS = 25 -- crouching in tall grass: only seen this close
GameConfig.BOT_SPOT_STANDING_IN_GRASS = 120 -- standing in tall grass: seen this close
GameConfig.BOT_HIDE_TIME = { 6, 16 } -- seconds a bot waits at a hiding spot

---------------------------------------------------------------------------
-- DATA
---------------------------------------------------------------------------
-- Bump the "_v1" if you ever change the saved data format.
GameConfig.DATASTORE_NAME = "AvoidTheSnipers_PlayerData_v1"
GameConfig.AUTOSAVE_INTERVAL = 120

---------------------------------------------------------------------------
-- SOUNDS
-- These use sounds that ship with every Roblox install so the game works
-- out of the box. For a better feel, replace them with sounds from the
-- Creator Store (Toolbox > Audio), e.g. "rbxassetid://1234567890".
-- If the Weapons Kit sniper contains a fire sound, it is used for the
-- gunshot automatically (see SniperService).
---------------------------------------------------------------------------
GameConfig.SOUNDS = {
	Gunshot = "rbxasset://sounds/collide.wav",
	HitMarker = "rbxasset://sounds/electronicpingshort.wav",
	BirdFlap = "rbxasset://sounds/swoosh.wav",
	CrowCall = "rbxasset://sounds/swoosh.wav",
	Footstep = "rbxasset://sounds/action_footsteps_plastic.mp3",
	Rustle = "rbxasset://sounds/action_footsteps_plastic.mp3",
	RoundStart = "rbxasset://sounds/electronicpingshort.wav",
	RoundEnd = "rbxasset://sounds/victory.wav",
	UIClick = "rbxasset://sounds/clickfast.wav",
}

return GameConfig
