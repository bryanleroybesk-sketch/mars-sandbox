--[[
	ItemService  (ModuleScript in ServerScriptService/Services)

	One-round shop items. They are Tools with an "ItemId" attribute and
	are removed when the round ends.

	  Binoculars    - zoom is purely visual, done by the client
	  Bird Whistle  - client sends where it aims; SERVER clamps the range
	                  and spawns a flock that looks like a real danger flock
	  Smoke Grenade - client sends where it aims; SERVER clamps the range
	                  and creates the smoke cloud for SMOKE_DURATION
	  Bandage       - SERVER heals BANDAGE_HEAL over BANDAGE_TIME, and
	                  cancels if the player moves or the round ends

	Every "UseItem" request is checked: right round state, player alive,
	and actually HOLDING that item right now.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local BirdSystem = require(script.Parent.BirdSystem)
local DamageService = require(script.Parent.DamageService)
local MapBuilder = require(script.Parent.MapBuilder)
local RoundState = require(script.Parent.RoundState)

local ItemService = {}

local USABLE = { BirdWhistle = true, SmokeGrenade = true, Bandage = true }
local lastUse: { [Player]: number } = {}
local bandaging: { [Player]: boolean } = {}

-- Look of each item's handle (muted colors, nothing shiny)
local ITEM_LOOKS = {
	Binoculars = { Size = Vector3.new(0.9, 0.45, 0.7), Color = Color3.fromRGB(45, 48, 40) },
	BirdWhistle = { Size = Vector3.new(0.25, 0.25, 0.9), Color = Color3.fromRGB(110, 82, 55) },
	SmokeGrenade = { Size = Vector3.new(0.5, 0.8, 0.5), Color = Color3.fromRGB(70, 82, 60) },
	Bandage = { Size = Vector3.new(0.6, 0.35, 0.6), Color = Color3.fromRGB(150, 140, 118) },
}

function ItemService.GiveItem(player: Player, itemId: string)
	local entry = ShopCatalog.ById[itemId]
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not entry or entry.Kind ~= "RoundItem" or not backpack then
		return
	end
	local look = ITEM_LOOKS[itemId]

	local tool = Instance.new("Tool")
	tool.Name = entry.Item.Name
	tool.ToolTip = entry.Item.Description
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("ItemId", itemId)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = look.Size
	handle.Color = look.Color
	handle.Material = Enum.Material.SmoothPlastic
	handle.CanCollide = false
	handle.CanQuery = false
	handle.Massless = true
	handle.Parent = tool

	tool.Parent = backpack
end

-- Removes every round item (and leaves the sniper to SniperService).
function ItemService.RemoveItems(player: Player)
	for _, container in { player.Character, player:FindFirstChildOfClass("Backpack") } do
		if container then
			for _, tool in container:GetChildren() do
				if tool:IsA("Tool") and tool:GetAttribute("ItemId") then
					tool:Destroy()
				end
			end
		end
	end
	bandaging[player] = nil
end

local function notify(player: Player, text: string)
	Remotes.Get("Notify"):FireClient(player, text)
end

-- Keeps an aimed point within `range` of the player and puts it on the ground.
local function clampAim(origin: Vector3, aim: Vector3, range: number): Vector3
	local offset = aim - origin
	if offset.Magnitude > range then
		offset = offset.Unit * range
	end
	local p = origin + offset
	return Vector3.new(p.X, MapBuilder.GroundY(p.X, p.Z), p.Z)
end

local function spawnSmoke(position: Vector3)
	local cloud = Instance.new("Folder")
	cloud.Name = "SmokeCloud"
	cloud.Parent = workspace

	local rng = Random.new()
	for i = 1, 7 do
		local size = rng:NextNumber(14, 18)
		local puff = Instance.new("Part")
		puff.Name = "Puff" .. i
		puff.Shape = Enum.PartType.Ball
		puff.Anchored = true
		puff.CanCollide = false
		puff.CanQuery = false -- bullets pass through smoke; it only blocks vision
		puff.CanTouch = false
		puff.CastShadow = false
		puff.Material = Enum.Material.SmoothPlastic
		puff.Color = Color3.fromRGB(176, 180, 170)
		puff.Transparency = 0.1
		puff.Size = Vector3.new(2, 2, 2)
		puff.Position = position + Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(3, 8), rng:NextNumber(-6, 6))
		puff.Parent = cloud
		-- grow quickly, then fade out at the end
		TweenService:Create(puff, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(size, size, size),
		}):Play()
		task.delay(GameConfig.SMOKE_DURATION - 1.5, function()
			if puff.Parent then
				TweenService:Create(puff, TweenInfo.new(1.5), { Transparency = 1 }):Play()
			end
		end)
	end
	Debris:AddItem(cloud, GameConfig.SMOKE_DURATION)
end

local function startBandage(player: Player, tool: Tool)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or bandaging[player] then
		return
	end
	local v = root.AssemblyLinearVelocity
	if Vector3.new(v.X, 0, v.Z).Magnitude > 1.5 then
		notify(player, "Stand still to use the bandage.")
		return
	end

	bandaging[player] = true
	notify(player, "Bandaging... don't move!")
	local startPos = root.Position
	local steps = 12
	local perStep = GameConfig.BANDAGE_HEAL / steps
	for _ = 1, steps do
		task.wait(GameConfig.BANDAGE_TIME / steps)
		local stillValid = bandaging[player]
			and RoundState.IsRoundActive()
			and RoundState.IsAlive(player)
			and root.Parent ~= nil
			and (root.Position - startPos).Magnitude < 1.5
		if not stillValid then
			bandaging[player] = nil
			notify(player, "Bandage interrupted - you moved.")
			return -- the bandage is NOT used up, try again
		end
		DamageService.Heal(player, perStep)
	end
	bandaging[player] = nil
	tool:Destroy() -- one use
	notify(player, "Bandaged: +" .. GameConfig.BANDAGE_HEAL .. " health")
end

local function onUseItem(player: Player, itemId: any, aimPosition: any)
	-- Validate arguments
	if typeof(itemId) ~= "string" or not USABLE[itemId] then
		return
	end
	if aimPosition ~= nil then
		if typeof(aimPosition) ~= "Vector3" or aimPosition ~= aimPosition then
			return
		end
	end
	-- Validate state
	if not RoundState.IsRoundActive() or not RoundState.IsAlive(player) then
		return
	end
	local now = os.clock()
	if lastUse[player] and now - lastUse[player] < 0.5 then
		return
	end
	lastUse[player] = now

	-- Must be HOLDING this exact item
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not tool or tool:GetAttribute("ItemId") ~= itemId or not head then
		return
	end

	if itemId == "BirdWhistle" then
		if not aimPosition then
			return
		end
		local spot = clampAim(head.Position, aimPosition, GameConfig.WHISTLE_RANGE)
		local size = GameConfig.WHISTLE_FLOCK_SIZE
		-- Sent as a "Danger" flock so enemies can't tell it's fake
		BirdSystem.SpawnFlock(spot, math.random(size[1], size[2]), "Danger")
		tool:Destroy()
		notify(player, "Whistled! Birds flew up over there.")
	elseif itemId == "SmokeGrenade" then
		if not aimPosition then
			return
		end
		spawnSmoke(clampAim(head.Position, aimPosition, GameConfig.SMOKE_THROW_RANGE))
		tool:Destroy()
	elseif itemId == "Bandage" then
		task.spawn(startBandage, player, tool)
	end
end

function ItemService.Init()
	Remotes.Get("UseItem").OnServerEvent:Connect(onUseItem)
	Players.PlayerRemoving:Connect(function(player)
		lastUse[player] = nil
		bandaging[player] = nil
	end)
end

return ItemService
