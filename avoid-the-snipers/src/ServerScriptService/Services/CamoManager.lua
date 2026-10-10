--[[
	CamoManager  (ModuleScript in ServerScriptService/Services)

	Handles the camo selection phase and dresses players for battle.

	Flow:
	  1. RoundManager calls BeginSelection(players, endsAt).
	     Each player gets the camo menu with the camos they may use.
	  2. The client sends ONLY a camo name through "SelectCamo".
	     The server checks: right phase? taking part? real camo? owned?
	  3. FinalizeSelection() gives "Jungle" to anyone who didn't choose.

	Applying a camo (server side, so everyone sees the same thing):
	  * removes all accessories, shirts, pants and body textures
	  * recolors body parts with the camo's colors
	  * deletes lights, particles, trails, beams, highlights, GUIs...
	    and turns neon parts into plain plastic (no glowing cheats)
	  * adds a small team armband on the left upper arm
	  * hides name tags and health bars (clients re-enable them for
	    teammates only - see NameTagController)

	Normal avatars come back automatically when players respawn in the
	lobby after the round (a fresh character loads their real look).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local CamoData = require(ReplicatedStorage.Shared.CamoData)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local RoundState = require(script.Parent.RoundState)

local CamoManager = {}

local choices: { [Player]: string } = {}
local glowWatchers: { [Model]: RBXScriptConnection } = {}

-- Which of the camo's 3 colors each body part gets (blotchy camo look).
local PART_COLOR_SLOT = {
	-- R15
	Head = 3,
	UpperTorso = 1,
	LowerTorso = 2,
	LeftUpperArm = 2,
	LeftLowerArm = 1,
	LeftHand = 3,
	RightUpperArm = 1,
	RightLowerArm = 2,
	RightHand = 3,
	LeftUpperLeg = 1,
	LeftLowerLeg = 2,
	LeftFoot = 2,
	RightUpperLeg = 2,
	RightLowerLeg = 1,
	RightFoot = 2,
	-- R6
	Torso = 1,
	["Left Arm"] = 2,
	["Right Arm"] = 1,
	["Left Leg"] = 1,
	["Right Leg"] = 2,
}

-- Anything of these classes can glow or stand out -> removed during rounds.
local GLOWING_CLASSES = {
	"Light", -- PointLight, SpotLight, SurfaceLight
	"ParticleEmitter",
	"Fire",
	"Smoke",
	"Sparkles",
	"Trail",
	"Beam",
	"Highlight",
	"SelectionBox",
	"BillboardGui",
	"SurfaceGui",
	"ForceField",
}

local function isGlowing(instance: Instance): boolean
	for _, className in GLOWING_CLASSES do
		if instance:IsA(className) then
			return true
		end
	end
	return false
end

-- Removes or fixes anything that could make a player easy to spot.
local function stripGlow(instance: Instance)
	if isGlowing(instance) then
		instance:Destroy()
	elseif instance:IsA("BasePart") then
		if instance.Material == Enum.Material.Neon or instance.Material == Enum.Material.ForceField then
			instance.Material = Enum.Material.SmoothPlastic
		end
		if instance.Name ~= "Armband" and instance.Name ~= "HumanoidRootPart" then
			-- Very bright colors on attached parts get darkened
			local h, s, v = instance.Color:ToHSV()
			if v > 0.75 and s > 0.4 then
				instance.Color = Color3.fromHSV(h, s * 0.5, 0.45)
			end
		end
	end
end

-- The camos this player is allowed to pick right now.
function CamoManager.GetAvailableCamos(player: Player): { string }
	local list = {}
	for _, camo in CamoData.List do
		if camo.Price == 0 or DataService.OwnsCamo(player, camo.Name) then
			table.insert(list, camo.Name)
		end
	end
	return list
end

local function addArmband(character: Model, teamKey: string)
	local old = character:FindFirstChild("Armband")
	if old then
		old:Destroy()
	end
	local arm = (character:FindFirstChild("LeftUpperArm") or character:FindFirstChild("Left Arm")) :: any
	if not arm then
		return
	end
	local band = Instance.new("Part")
	band.Name = "Armband"
	band.Size = Vector3.new(arm.Size.X + 0.12, 0.3, arm.Size.Z + 0.12)
	band.CFrame = arm.CFrame * CFrame.new(0, arm.Size.Y * 0.2, 0)
	band.Color = GameConfig.TEAMS[teamKey].ArmbandColor
	band.Material = Enum.Material.Fabric
	band.CanCollide = false
	band.CanQuery = false -- bullets hit the arm, not the band
	band.CanTouch = false
	band.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = arm
	weld.Part1 = band
	weld.Parent = band
	band.Parent = character
end

-- Dresses a character in a camo. Safe to call more than once.
function CamoManager.ApplyCamo(character: Model, camoName: string, teamKey: string)
	local camo = CamoData.ByName[camoName] or CamoData.ByName[CamoData.DEFAULT_CAMO]

	for _, child in character:GetChildren() do
		if child:IsA("Accessory") or child:IsA("Shirt") or child:IsA("Pants") or child:IsA("ShirtGraphic") or child:IsA("BodyColors") then
			child:Destroy()
		end
	end

	for _, part in character:GetChildren() do
		local slot = PART_COLOR_SLOT[part.Name]
		if slot and part:IsA("BasePart") then
			part.Color = camo.Colors[slot]
			part.Material = Enum.Material.Fabric
			if part:IsA("MeshPart") then
				part.TextureID = "" -- some avatar bodies have bright textures
			end
			for _, child in part:GetChildren() do
				if child:IsA("SurfaceAppearance") then
					child:Destroy()
				end
			end
		end
	end

	-- Optional real camo clothing (set the templates in CamoData)
	if camo.ShirtTemplate ~= "" then
		local shirt = Instance.new("Shirt")
		shirt.ShirtTemplate = camo.ShirtTemplate
		shirt.Parent = character
	end
	if camo.PantsTemplate ~= "" then
		local pants = Instance.new("Pants")
		pants.PantsTemplate = camo.PantsTemplate
		pants.Parent = character
	end

	for _, descendant in character:GetDescendants() do
		stripGlow(descendant)
	end
	-- Keep stripping anything added later (e.g. by other scripts)
	if not glowWatchers[character] then
		glowWatchers[character] = character.DescendantAdded:Connect(function(descendant)
			task.defer(function()
				if not descendant.Parent then
					return
				end
				-- Avatar items that finished loading late are removed too
				if descendant.Parent == character and (descendant:IsA("Accessory") or descendant:IsA("Clothing") or descendant:IsA("ShirtGraphic")) then
					descendant:Destroy()
				else
					stripGlow(descendant)
				end
			end)
		end)
		character.Destroying:Connect(function()
			local conn = glowWatchers[character]
			if conn then
				conn:Disconnect()
				glowWatchers[character] = nil
			end
		end)
	end

	addArmband(character, teamKey)

	-- Hide name + health bar for everyone. Each client turns names back on
	-- for its own teammates (NameTagController), never for enemies.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.NameOcclusion = Enum.NameOcclusion.EnemyOcclusion
	end

	character:SetAttribute("Camo", camo.Name)
end

local function applyToPlayer(player: Player, camoName: string)
	local teamKey = RoundState.Participants[player]
	local character = player.Character
	if teamKey and character then
		CamoManager.ApplyCamo(character, camoName, teamKey)
	end
end

function CamoManager.BeginSelection(players: { Player }, endsAt: number)
	table.clear(choices)
	local menuEvent = Remotes.Get("CamoMenu")
	for _, player in players do
		menuEvent:FireClient(player, true, CamoManager.GetAvailableCamos(player), endsAt)
	end
end

-- True when every listed player has picked a camo (used to end early).
function CamoManager.AllChosen(players: { Player }): boolean
	for _, player in players do
		if not choices[player] then
			return false
		end
	end
	return true
end

function CamoManager.FinalizeSelection(players: { Player })
	local menuEvent = Remotes.Get("CamoMenu")
	for _, player in players do
		if not choices[player] then
			choices[player] = CamoData.DEFAULT_CAMO
			applyToPlayer(player, CamoData.DEFAULT_CAMO)
		end
		if not RoundState.IsBot(player) then
			menuEvent:FireClient(player, false)
		end
	end
end

-- Bots pick a random free camo.
function CamoManager.ChooseForBot(bot: Player)
	local free = {}
	for _, camo in CamoData.List do
		if camo.Price == 0 then
			table.insert(free, camo.Name)
		end
	end
	local name = free[math.random(1, #free)]
	choices[bot] = name
	applyToPlayer(bot, name)
end

function CamoManager.GetChoice(player: Player): string
	return choices[player] or CamoData.DEFAULT_CAMO
end

function CamoManager.Init()
	Remotes.Get("SelectCamo").OnServerEvent:Connect(function(player, camoName)
		-- VALIDATE EVERYTHING the client sent
		if RoundState.Phase ~= "CamoSelect" then
			return
		end
		if not RoundState.Participants[player] then
			return
		end
		if typeof(camoName) ~= "string" or #camoName > 40 then
			return
		end
		local camo = CamoData.ByName[camoName]
		if not camo then
			return
		end
		if camo.Price > 0 and not DataService.OwnsCamo(player, camoName) then
			return -- trying to use a camo they never bought
		end

		choices[player] = camoName
		applyToPlayer(player, camoName) -- instant preview on your character
	end)
end

return CamoManager
