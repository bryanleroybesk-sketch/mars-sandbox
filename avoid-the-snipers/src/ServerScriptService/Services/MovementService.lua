--[[
	MovementService  (ModuleScript in ServerScriptService/Services)
	Server half of the movement system (the client half is MovementController).

	The client only ASKS for a stance ("Crouch", "Walk", "Sprint").
	The server sets the real WalkSpeed, the crouch pose and the sounds, so:
	  * crouch: CROUCH_SPEED, lower body, NO footsteps, no jumping
	  * walk:   WALK_SPEED, quiet footsteps heard close by
	  * sprint: SPRINT_SPEED, loud rustling heard far away

	Sounds are created on the server inside the HumanoidRootPart, so every
	player hears them coming from the right place.

	Players can be "frozen" (camo selection): speed 0, no jumping.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local MovementService = {}

local VALID_STANCES = { Crouch = true, Walk = true, Sprint = true }
local SOUND_TICK = 0.1

type PlayerState = {
	Stance: string,
	Frozen: boolean,
}

local states: { [Player]: PlayerState } = {}
-- Original joint positions so we can undo the crouch pose (weak keys)
local originalC0: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local originalHipHeight: { [Humanoid]: number } = setmetatable({}, { __mode = "k" }) :: any

local function getState(player: Player): PlayerState
	local state = states[player]
	if not state then
		state = { Stance = "Walk", Frozen = false }
		states[player] = state
	end
	return state
end

local function getParts(player: Player): (Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	return character:FindFirstChildOfClass("Humanoid"), character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Bends the legs into a kneel (R15 only). Uses Motor6D.C0, which replicates
-- to every player, so everyone sees you crouch and your hitbox really drops.
local function setCrouchPose(character: Model, crouched: boolean)
	if GameConfig.CROUCH_ANIMATION_ID ~= "" then
		return -- the client plays the uploaded crouch animation instead
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return
	end

	-- Joint name -> rotation while crouched (degrees around the X axis)
	local POSE = {
		{ "LeftUpperLeg", "LeftHip", 90 },
		{ "RightUpperLeg", "RightHip", 90 },
		{ "LeftLowerLeg", "LeftKnee", -90 },
		{ "RightLowerLeg", "RightKnee", -90 },
		{ "UpperTorso", "Waist", -20 },
	}

	local thighLength = 0
	for _, entry in POSE do
		local part = character:FindFirstChild(entry[1])
		local motor = part and part:FindFirstChild(entry[2])
		if motor and motor:IsA("Motor6D") then
			if not originalC0[motor] then
				originalC0[motor] = motor.C0
			end
			local base = originalC0[motor]
			motor.C0 = if crouched then base * CFrame.Angles(math.rad(entry[3] :: number), 0, 0) else base
			if entry[2] == "LeftHip" then
				-- hip joint -> knee joint distance = how much lower we get
				local knee = character:FindFirstChild("LeftLowerLeg")
				local kneeMotor = knee and knee:FindFirstChild("LeftKnee")
				if kneeMotor and kneeMotor:IsA("Motor6D") then
					thighLength = math.abs(motor.C1.Position.Y) + math.abs((originalC0[kneeMotor] or kneeMotor.C0).Position.Y)
				end
			end
		end
	end

	if not originalHipHeight[humanoid] then
		originalHipHeight[humanoid] = humanoid.HipHeight
	end
	humanoid.HipHeight = if crouched then originalHipHeight[humanoid] - thighLength else originalHipHeight[humanoid]
end

-- Applies speed / jump / pose for the player's current stance.
local function applyStance(player: Player)
	local state = getState(player)
	local humanoid = getParts(player)
	local character = player.Character
	if not humanoid or not character then
		return
	end

	local stance = state.Stance
	if state.Frozen then
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
	elseif stance == "Crouch" then
		humanoid.WalkSpeed = GameConfig.CROUCH_SPEED
		humanoid.JumpHeight = 0
	elseif stance == "Sprint" then
		humanoid.WalkSpeed = GameConfig.SPRINT_SPEED
		humanoid.JumpHeight = GameConfig.JUMP_HEIGHT
	else
		humanoid.WalkSpeed = GameConfig.WALK_SPEED
		humanoid.JumpHeight = GameConfig.JUMP_HEIGHT
	end

	setCrouchPose(character, stance == "Crouch" and not state.Frozen)
	character:SetAttribute("Stance", stance)
end

local function makeLoopSound(name: string, parent: Instance, volume: number, maxDistance: number, speed: number): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = if name == "Footsteps" then GameConfig.SOUNDS.Footstep else GameConfig.SOUNDS.Rustle
	sound.Looped = true
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 5
	sound.RollOffMaxDistance = maxDistance
	sound.Parent = parent
	return sound
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root then
		return
	end
	humanoid.UseJumpPower = false
	getState(player).Stance = "Walk"

	makeLoopSound("Footsteps", root, GameConfig.WALK_FOOTSTEP_VOLUME, GameConfig.WALK_FOOTSTEP_DISTANCE, 1)
	makeLoopSound("Rustle", root, GameConfig.SPRINT_RUSTLE_VOLUME, GameConfig.SPRINT_RUSTLE_DISTANCE, 0.75)
	applyStance(player)
end

-- Plays/stops footstep sounds depending on stance and movement.
local function updateSounds()
	for player, state in states do
		local humanoid, root = getParts(player)
		if humanoid and root then
			local velocity = root.AssemblyLinearVelocity
			local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 1
				and humanoid.FloorMaterial ~= Enum.Material.Air
				and humanoid.Health > 0
			local footsteps = root:FindFirstChild("Footsteps") :: Sound?
			local rustle = root:FindFirstChild("Rustle") :: Sound?
			local wantFootsteps = moving and state.Stance == "Walk"
			local wantRustle = moving and state.Stance == "Sprint"
			if footsteps and footsteps.Playing ~= wantFootsteps then
				footsteps.Playing = wantFootsteps
			end
			if rustle and rustle.Playing ~= wantRustle then
				rustle.Playing = wantRustle
			end
		end
	end
end

function MovementService.Init()
	Remotes.Get("SetStance").OnServerEvent:Connect(function(player, stance)
		-- Validate: must be one of the three known stances
		if typeof(stance) ~= "string" or not VALID_STANCES[stance] then
			return
		end
		local state = getState(player)
		if state.Stance ~= stance then
			state.Stance = stance
			applyStance(player)
		end
	end)

	local function setup(player: Player)
		getState(player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	task.spawn(function()
		while true do
			updateSounds()
			task.wait(SOUND_TICK)
		end
	end)
end

-- Freeze (camo selection) or unfreeze a player.
function MovementService.SetFrozen(player: Player, frozen: boolean)
	getState(player).Frozen = frozen
	applyStance(player)
end

-- Used by BotService: bots get the same speeds, pose and sounds as players.
function MovementService.SetupCharacter(who: Player, character: Model)
	onCharacterAdded(who, character)
end

function MovementService.SetStance(who: Player, stance: string)
	local state = getState(who)
	if VALID_STANCES[stance] and state.Stance ~= stance then
		state.Stance = stance
		applyStance(who)
	end
end

function MovementService.Forget(who: Player)
	states[who] = nil
end

-- Is this player sprinting AND actually moving?
function MovementService.IsSprinting(player: Player): boolean
	local state = states[player]
	if not state or state.Stance ~= "Sprint" or state.Frozen then
		return false
	end
	local _, root = getParts(player)
	if not root then
		return false
	end
	local v = root.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude > GameConfig.WALK_SPEED
end

function MovementService.GetStance(player: Player): string
	return getState(player).Stance
end

return MovementService
