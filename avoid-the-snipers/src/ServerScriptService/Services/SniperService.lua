--[[
	SniperService  (ModuleScript in ServerScriptService/Services)

	Gives every player a sniper at round start and handles every shot.

	WEAPON MODEL
	  Put the official Roblox "Weapons Kit" sniper rifle in
	  ServerStorage/Weapons and name it "SniperRifle" (see README).
	  We clone it, but REMOVE its scripts: the kit has its own damage
	  system, and this game must use the GameConfig damage values and
	  server checks below. We keep its model, grip and fire sound.
	  If no template is found, a simple built-in rifle is used, so the
	  game still works while you set things up.

	SHOOTING (server-authoritative)
	  The client sends: aim direction, the part it thinks it hit, and the
	  hit position. The server then:
	    1. checks round state, that the shooter is alive and holding the
	       sniper, and the fire-rate cooldown
	    2. raycasts from the shooter's HEAD (server position) to the hit
	       position - walls and rocks block the shot
	    3. accepts the client's target only if nothing blocked the path
	       and the target part is close to the claimed point
	       (SNIPER_HIT_TOLERANCE, allows for network lag)
	    4. picks damage from the BODY PART: head / body / limb
	  Then it shows a tracer + gunshot sound to everyone.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local DamageService = require(script.Parent.DamageService)
local DataService = require(script.Parent.DataService)
local RoundState = require(script.Parent.RoundState)

local SniperService = {}

local HEAD_PARTS = { Head = true }
local BODY_PARTS = { UpperTorso = true, LowerTorso = true, Torso = true, HumanoidRootPart = true }

local lastShotAt: { [Player]: number } = {}
local gunshotSoundId = GameConfig.SOUNDS.Gunshot

---------------------------------------------------------------------------
-- Building the rifle Tool
---------------------------------------------------------------------------
local function weldTo(handle: BasePart, part: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = part
	weld.Parent = part
end

-- Simple rifle made of parts (used only when the Weapons Kit is missing)
local function buildFallbackRifle(): Tool
	local tool = Instance.new("Tool")
	tool.RequiresHandle = true
	tool.Grip = CFrame.new(0, -0.1, 0.8)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, 0.45, 3.2)
	handle.Color = Color3.fromRGB(60, 58, 52)
	handle.Material = Enum.Material.Metal
	handle.Parent = tool

	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, shape: Enum.PartType?)
		local p = Instance.new("Part")
		p.Name = name
		if shape then
			p.Shape = shape
		end
		p.Size = size
		p.CFrame = handle.CFrame * offset
		p.Color = color
		p.Material = Enum.Material.Metal
		p.Parent = tool
		weldTo(handle, p)
		return p
	end
	piece("Barrel", Vector3.new(2.4, 0.16, 0.16), CFrame.new(0, 0.1, -2.6) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(40, 40, 38), Enum.PartType.Cylinder)
	piece("Scope", Vector3.new(1.4, 0.28, 0.28), CFrame.new(0, 0.42, -0.2) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(35, 35, 33), Enum.PartType.Cylinder)
	piece("Stock", Vector3.new(0.28, 0.6, 1.2), CFrame.new(0, -0.15, 2.0), Color3.fromRGB(76, 60, 44))

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0.1, -3.9)
	muzzle.Parent = handle
	return tool
end

-- Clones the Weapons Kit sniper (minus its scripts) or builds the fallback.
local function createRifle(): Tool
	local weapons = ServerStorage:FindFirstChild("Weapons")
	local template = weapons and weapons:FindFirstChild(GameConfig.SNIPER_TEMPLATE_NAME)
	local tool: Tool
	if template and template:IsA("Tool") then
		tool = template:Clone()
		for _, d in tool:GetDescendants() do
			if d:IsA("LuaSourceContainer") then
				d:Destroy() -- remove the kit's own (client-trusting) logic
			end
		end
	else
		tool = buildFallbackRifle()
	end

	tool.Name = "Sniper"
	tool.CanBeDropped = false
	tool.ManualActivationOnly = false -- clicking must fire Tool.Activated
	tool.ToolTip = "Sniper rifle - Right click / Q to scope"
	tool:SetAttribute("IsSniper", true)

	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false -- bullets pass through guns
			d.CanTouch = false
			d.Massless = true
		end
	end
	return tool
end

-- Muted skin color over the whole rifle (cosmetic only).
local function applySkin(tool: Tool, skinId: string)
	local entry = ShopCatalog.ById[skinId]
	if not entry or entry.Kind ~= "Skin" then
		return
	end
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color = entry.Item.Color
			if d:IsA("MeshPart") then
				d.TextureID = ""
			end
		end
	end
end

-- Finds a fire sound inside the template so the real kit sound is used.
local function findTemplateFireSound()
	local weapons = ServerStorage:FindFirstChild("Weapons")
	local template = weapons and weapons:FindFirstChild(GameConfig.SNIPER_TEMPLATE_NAME)
	if not template then
		warn("[SniperService] No ServerStorage/Weapons/" .. GameConfig.SNIPER_TEMPLATE_NAME .. " found - using the built-in rifle. See README to add the Weapons Kit sniper.")
		return
	end
	for _, d in template:GetDescendants() do
		if d:IsA("Sound") and d.SoundId ~= "" then
			local name = d.Name:lower()
			if name:find("fire") or name:find("shot") or name:find("shoot") then
				gunshotSoundId = d.SoundId
				return
			end
		end
	end
end

local function getMuzzlePosition(tool: Tool, fallback: Vector3): Vector3
	for _, d in tool:GetDescendants() do
		if d:IsA("Attachment") then
			local name = d.Name:lower()
			if name:find("muzzle") or name:find("tip") or name:find("nozzle") then
				return d.WorldPosition
			end
		end
	end
	local handle = tool:FindFirstChild("Handle")
	return if handle and handle:IsA("BasePart") then handle.Position else fallback
end

---------------------------------------------------------------------------
-- Shooting
---------------------------------------------------------------------------
local function isFiniteVector(v: Vector3): boolean
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) < 1e6 and math.abs(v.Y) < 1e6 and math.abs(v.Z) < 1e6
end

-- Walks up from a hit part to the character model that owns it.
local function characterOf(instance: Instance): Model?
	local model = instance:FindFirstAncestorWhichIsA("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then
			return model
		end
		model = model:FindFirstAncestorWhichIsA("Model")
	end
	return nil
end

local function damageForPart(part: BasePart): (number, boolean)
	if HEAD_PARTS[part.Name] then
		return GameConfig.HEADSHOT_DAMAGE, true
	elseif BODY_PARTS[part.Name] then
		return GameConfig.BODY_DAMAGE, false
	end
	return GameConfig.LIMB_DAMAGE, false
end

local function onFire(player: Player, direction: any, claimedPart: any, claimedPosition: any)
	-- 1) Validate the arguments' TYPES (exploiters can send anything)
	if typeof(direction) ~= "Vector3" or not isFiniteVector(direction) or direction.Magnitude < 0.1 then
		return
	end
	if claimedPosition ~= nil and (typeof(claimedPosition) ~= "Vector3" or not isFiniteVector(claimedPosition)) then
		return
	end
	if claimedPart ~= nil and (typeof(claimedPart) ~= "Instance" or not claimedPart:IsA("BasePart")) then
		claimedPart = nil
	end

	-- 2) Validate game state
	if not RoundState.IsRoundActive() or not RoundState.IsAlive(player) then
		return
	end
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	local tool = character and character:FindFirstChildOfClass("Tool")
	if not head or not tool or not tool:GetAttribute("IsSniper") then
		return
	end
	local now = os.clock()
	if lastShotAt[player] and now - lastShotAt[player] < GameConfig.SNIPER_FIRE_COOLDOWN - 0.1 then
		return -- firing faster than the bolt allows
	end
	lastShotAt[player] = now

	-- 3) Server raycast from the head to where the client aimed
	local origin = head.Position
	local target: Vector3 = claimedPosition or (origin + direction.Unit * GameConfig.SNIPER_MAX_RANGE)
	local toTarget = target - origin
	if toTarget.Magnitude < 0.1 then
		return
	end
	if toTarget.Magnitude > GameConfig.SNIPER_MAX_RANGE then
		toTarget = toTarget.Unit * GameConfig.SNIPER_MAX_RANGE
		claimedPart = nil
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local result = workspace:Raycast(origin, toTarget.Unit * (toTarget.Magnitude + 3), params)

	local hitPart: BasePart? = nil
	local endPoint = origin + toTarget
	if result then
		endPoint = result.Position
		if characterOf(result.Instance) then
			hitPart = result.Instance :: BasePart
		end
	end

	-- 4) Lag compensation: the client saw a hit, the server ray missed the
	--    (moved) target. Accept it only if the path was clear and the part
	--    is still near the claimed point.
	if not hitPart and claimedPart and claimedPosition and claimedPart:IsDescendantOf(workspace) then
		local claimedCharacter = characterOf(claimedPart)
		local pathClear = result == nil or (result.Position - origin).Magnitude >= toTarget.Magnitude - 1
		local closeEnough = (claimedPart.Position - claimedPosition).Magnitude
			<= GameConfig.SNIPER_HIT_TOLERANCE + claimedPart.Size.Magnitude / 2
		if claimedCharacter and pathClear and closeEnough then
			hitPart = claimedPart
			endPoint = claimedPosition
		end
	end

	-- 5) Everyone sees the tracer and hears the shot (reveals the shooter!)
	Remotes.Get("ShotFired"):FireAllClients(getMuzzlePosition(tool, origin), endPoint, gunshotSoundId)

	-- 6) Damage, decided by the server from the body part
	if hitPart then
		local victimCharacter = characterOf(hitPart)
		local victim = victimCharacter and Players:GetPlayerFromCharacter(victimCharacter)
		if victim then
			local damage, headshot = damageForPart(hitPart)
			local applied, killed = DamageService.ApplyDamage(victim, damage, player, headshot)
			if applied then
				Remotes.Get("HitMarker"):FireClient(player, headshot, killed)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
function SniperService.Init()
	findTemplateFireSound()
	Remotes.Get("FireSniper").OnServerEvent:Connect(onFire)
	Players.PlayerRemoving:Connect(function(player)
		lastShotAt[player] = nil
	end)
end

function SniperService.GiveSniper(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	local tool = createRifle()
	applySkin(tool, DataService.GetEquippedSkin(player))
	tool.Parent = backpack

	-- Equip it right away
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:EquipTool(tool)
	end
end

-- Re-color the rifle the player is holding (after buying/equipping a skin).
function SniperService.RefreshSkin(player: Player)
	local skinId = DataService.GetEquippedSkin(player)
	for _, container in { player.Character, player:FindFirstChildOfClass("Backpack") } do
		if container then
			for _, tool in container:GetChildren() do
				if tool:IsA("Tool") and tool:GetAttribute("IsSniper") then
					applySkin(tool, skinId)
				end
			end
		end
	end
end

function SniperService.RemoveSniper(player: Player)
	for _, container in { player.Character, player:FindFirstChildOfClass("Backpack") } do
		if container then
			for _, tool in container:GetChildren() do
				if tool:IsA("Tool") and tool:GetAttribute("IsSniper") then
					tool:Destroy()
				end
			end
		end
	end
end

return SniperService
