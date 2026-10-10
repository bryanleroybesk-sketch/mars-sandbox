--[[
	MovementController  (ModuleScript in StarterPlayerScripts/Controllers)
	Client half of movement (server half: MovementService).

	  Hold C or Left Ctrl -> crouch
	  Hold Left Shift     -> sprint
	  Mobile: on-screen "Crouch" and "Sprint" buttons (tap to toggle)

	The client only tells the server which stance it WANTS. The server sets
	the real speed, the crouch pose, and the footstep/rustle sounds.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local MovementController = {}

local player = Players.LocalPlayer
local crouchHeld = false
local sprintHeld = false
local currentStance = "Walk"
local crouchTrack: AnimationTrack? = nil

-- Crouch wins over sprint; otherwise walk.
local function updateStance()
	local wanted = if crouchHeld then "Crouch" elseif sprintHeld then "Sprint" else "Walk"
	if wanted ~= currentStance then
		currentStance = wanted
		Remotes.Get("SetStance"):FireServer(wanted)
	end
end

local function handle(actionName: string, state: Enum.UserInputState, input: InputObject)
	local isTouch = input.UserInputType == Enum.UserInputType.Touch
	if isTouch then
		-- Mobile buttons toggle, so your thumbs stay free to move and aim
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Sink
		end
		if actionName == "Crouch" then
			crouchHeld = not crouchHeld
			sprintHeld = false
		else
			sprintHeld = not sprintHeld
			crouchHeld = false
		end
	else
		local down = state == Enum.UserInputState.Begin
		if state ~= Enum.UserInputState.Begin and state ~= Enum.UserInputState.End then
			return Enum.ContextActionResult.Pass
		end
		if actionName == "Crouch" then
			crouchHeld = down
		else
			sprintHeld = down
		end
	end
	updateStance()
	return Enum.ContextActionResult.Sink
end

-- Optional uploaded crouch animation (GameConfig.CROUCH_ANIMATION_ID).
-- Animations played on your own character replicate to everyone.
local function watchCrouchAnimation(character: Model)
	if GameConfig.CROUCH_ANIMATION_ID == "" then
		return
	end
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local animator = humanoid:WaitForChild("Animator") :: Animator
	local animation = Instance.new("Animation")
	animation.AnimationId = GameConfig.CROUCH_ANIMATION_ID
	crouchTrack = animator:LoadAnimation(animation)
	character:GetAttributeChangedSignal("Stance"):Connect(function()
		local track = crouchTrack
		if not track then
			return
		end
		if character:GetAttribute("Stance") == "Crouch" then
			track:Play(0.2)
		else
			track:Stop(0.2)
		end
	end)
end

function MovementController.Init()
	ContextActionService:BindAction("Crouch", handle, true, Enum.KeyCode.C, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonB)
	ContextActionService:BindAction("Sprint", handle, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	-- Titles/positions only matter for the mobile buttons
	ContextActionService:SetTitle("Crouch", "Crouch")
	ContextActionService:SetTitle("Sprint", "Sprint")
	ContextActionService:SetPosition("Crouch", UDim2.new(1, -230, 1, -90))
	ContextActionService:SetPosition("Sprint", UDim2.new(1, -230, 1, -150))

	player.CharacterAdded:Connect(function(character)
		-- New character starts walking (the server resets too)
		crouchHeld, sprintHeld, currentStance = false, false, "Walk"
		watchCrouchAnimation(character)
	end)
	if player.Character then
		task.spawn(watchCrouchAnimation, player.Character)
	end
end

return MovementController
