--[[
	SniperClient  (ModuleScript in StarterPlayerScripts/Controllers)

	Client side of the sniper. It ONLY:
	  * aims (camera/mouse ray) and sends a fire REQUEST to the server
	  * handles the scope zoom (right mouse / Q / mobile "Scope" button)
	  * draws tracers and plays gunshots the server tells it about
	The server decides if the shot hit and how much damage it did.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local SoundUtil = require(ReplicatedStorage.Shared:WaitForChild("SoundUtil"))
local Zoom = require(script.Parent.Zoom)

local SniperClient = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local mouse = player:GetMouse()

local equipped: Tool? = nil
local lastShot = 0

-- Where is the player aiming? Returns (direction, hitPart, hitPosition)
local function aim(): (Vector3, BasePart?, Vector3?)
	local ray
	if Zoom.Get() == "Scope" then
		local size = camera.ViewportSize
		ray = camera:ViewportPointToRay(size.X / 2, size.Y / 2)
	else
		ray = mouse.UnitRay -- also follows the last tap on mobile
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Instance }
	local result = workspace:Raycast(ray.Origin, ray.Direction * GameConfig.SNIPER_MAX_RANGE, params)
	if result then
		return ray.Direction, result.Instance :: BasePart, result.Position
	end
	return ray.Direction, nil, nil
end

local function fire()
	if not equipped then
		return
	end
	if os.clock() - lastShot < GameConfig.SNIPER_FIRE_COOLDOWN then
		return
	end
	lastShot = os.clock()
	local direction, hitPart, hitPosition = aim()
	Remotes.Get("FireSniper"):FireServer(direction, hitPart, hitPosition)
end

local function setScoped(scoped: boolean)
	if scoped and equipped then
		Zoom.Set("Scope")
	elseif Zoom.Get() == "Scope" then
		Zoom.Set(nil)
	end
end

local function onScopeAction(_, state: Enum.UserInputState, input: InputObject)
	if not equipped then
		return Enum.ContextActionResult.Pass
	end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		setScoped(state == Enum.UserInputState.Begin) -- hold right mouse
	elseif state == Enum.UserInputState.Begin then
		setScoped(Zoom.Get() ~= "Scope") -- Q / touch button toggles
	end
	return Enum.ContextActionResult.Sink
end

local activatedConn: RBXScriptConnection? = nil

local function onEquipped(tool: Tool)
	equipped = tool
	activatedConn = tool.Activated:Connect(fire)
	ContextActionService:BindAction("SniperScope", onScopeAction, true, Enum.UserInputType.MouseButton2, Enum.KeyCode.Q, Enum.KeyCode.ButtonL2)
	ContextActionService:SetTitle("SniperScope", "Scope")
	ContextActionService:SetPosition("SniperScope", UDim2.new(1, -170, 1, -150))
end

local function onUnequipped()
	equipped = nil
	if activatedConn then
		activatedConn:Disconnect()
		activatedConn = nil
	end
	ContextActionService:UnbindAction("SniperScope")
	setScoped(false)
end

local function watchCharacter(character: Model)
	onUnequipped()
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("IsSniper") then
			onEquipped(child)
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child == equipped then
			onUnequipped()
		end
	end)
end

-- Tracer + gunshot for EVERY shot on the map (yours and enemies')
local function onShotFired(origin: Vector3, hitPosition: Vector3, soundId: string)
	local distance = (hitPosition - origin).Magnitude
	if distance > 0.5 then
		local tracer = Instance.new("Part")
		tracer.Name = "Tracer"
		tracer.Anchored = true
		tracer.CanCollide = false
		tracer.CanQuery = false
		tracer.CanTouch = false
		tracer.CastShadow = false
		tracer.Material = Enum.Material.Neon
		tracer.Color = Color3.fromRGB(255, 236, 170)
		tracer.Transparency = 0.2
		tracer.Size = Vector3.new(0.12, 0.12, distance)
		tracer.CFrame = CFrame.lookAt((origin + hitPosition) / 2, hitPosition)
		tracer.Parent = workspace
		TweenService:Create(tracer, TweenInfo.new(GameConfig.TRACER_LIFETIME), { Transparency = 1 }):Play()
		Debris:AddItem(tracer, GameConfig.TRACER_LIFETIME + 0.1)
	end
	-- Loud: heard across the whole map, so shooting reveals your position
	SoundUtil.PlayAt(origin, soundId, { Volume = 2, MinDistance = 80, MaxDistance = 3000 })
end

function SniperClient.Init()
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
	Remotes.Get("ShotFired").OnClientEvent:Connect(onShotFired)
end

return SniperClient
