--[[
	HudController  (ModuleScript in StarterPlayerScripts/Controllers)

	Top-of-screen UI. It only DISPLAYS what the server put in
	ReplicatedStorage.GameStatus and in player attributes:
	  * round timer + state text
	  * players alive per team
	  * results banner
	  * kill feed ("X eliminated Y" - never locations)
	  * small notifications (coins, shop messages)
	  * hit marker, enemy-spawn warning, subtle bird icon
	  * round start / end sounds
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local SoundUtil = require(ReplicatedStorage.Shared:WaitForChild("SoundUtil"))
local UIUtil = require(script.Parent.UIUtil)

local HudController = {}

local player = Players.LocalPlayer
local status = Remotes.GetStatus()
local C = UIUtil.Colors

local gui = UIUtil.screen("HUD", 1)

---------------------------------------------------------------------------
-- Top bar: [GREEN n]  [ 2:31 / state ]  [n BROWN]
---------------------------------------------------------------------------
local bar = UIUtil.new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.new(0, 420, 0, 58),
	BackgroundColor3 = C.Panel,
	BackgroundTransparency = 0.25,
}, gui)
UIUtil.corner(bar, 10)

local greenBox = UIUtil.label("GREEN 0", {
	Position = UDim2.new(0, 10, 0, 8),
	Size = UDim2.new(0, 110, 0, 42),
	TextColor3 = C.Green,
	TextXAlignment = Enum.TextXAlignment.Left,
}, bar)
local brownBox = UIUtil.label("0 BROWN", {
	Position = UDim2.new(1, -120, 0, 8),
	Size = UDim2.new(0, 110, 0, 42),
	TextColor3 = C.Brown,
	TextXAlignment = Enum.TextXAlignment.Right,
}, bar)
local timerLabel = UIUtil.label("", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 4),
	Size = UDim2.new(0, 160, 0, 30),
}, bar)
local stateLabel = UIUtil.label("", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 34),
	Size = UDim2.new(0, 180, 0, 18),
	TextColor3 = C.TextDim,
	Font = UIUtil.FontRegular,
}, bar)
local teamLabel = UIUtil.label("", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 70),
	Size = UDim2.new(0, 260, 0, 20),
	Font = UIUtil.FontRegular,
}, gui)

---------------------------------------------------------------------------
-- Results banner
---------------------------------------------------------------------------
local banner = UIUtil.label("", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.2, 0),
	Size = UDim2.new(0.7, 0, 0, 60),
	BackgroundColor3 = C.Panel,
	BackgroundTransparency = 0.2,
	TextColor3 = C.Gold,
	Visible = false,
}, gui)
UIUtil.corner(banner, 12)
UIUtil.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, banner)

---------------------------------------------------------------------------
-- Kill feed (top right) and notifications (bottom center)
---------------------------------------------------------------------------
local feed = UIUtil.new("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 80),
	Size = UDim2.new(0, 300, 0, 200),
	BackgroundTransparency = 1,
}, gui)
UIUtil.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, feed)

local notes = UIUtil.new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -110),
	Size = UDim2.new(0, 420, 0, 120),
	BackgroundTransparency = 1,
}, gui)
UIUtil.new("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	Padding = UDim.new(0, 4),
}, notes)

local order = 0
local function pushLine(parent: Instance, text: string, color: Color3, lifetime: number)
	order += 1
	local line = UIUtil.label(text, {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.35,
		TextColor3 = color,
		Font = UIUtil.FontRegular,
		LayoutOrder = order,
	}, parent)
	UIUtil.corner(line, 6)
	Debris:AddItem(line, lifetime)
end

---------------------------------------------------------------------------
-- Center: hit marker, enemy-zone warning. Bottom-left: bird icon.
---------------------------------------------------------------------------
local hitMarker = UIUtil.label("X", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0, 34, 0, 34),
	Visible = false,
	ZIndex = 10,
}, gui)

local zoneWarning = UIUtil.label("ENEMY SPAWN - LEAVE NOW! You are taking damage.", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.3, 0),
	Size = UDim2.new(0.6, 0, 0, 36),
	BackgroundColor3 = Color3.fromRGB(80, 20, 15),
	BackgroundTransparency = 0.2,
	TextColor3 = C.Danger,
	Visible = false,
}, gui)
UIUtil.corner(zoneWarning, 8)

local birdIcon = UIUtil.label("🐦 Birds flew up near you - keep moving", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 14, 1, -14),
	Size = UDim2.new(0, 300, 0, 22),
	TextColor3 = C.TextDim,
	TextTransparency = 0.2,
	Font = UIUtil.FontRegular,
	TextXAlignment = Enum.TextXAlignment.Left,
	Visible = false,
}, gui)

---------------------------------------------------------------------------
-- Updating
---------------------------------------------------------------------------
local STATE_TEXT = {
	CamoSelect = "Camo selection",
	Round = "Round in progress",
	Results = "Round over",
	Intermission = "Intermission",
}

local function refreshTeam()
	local team = player.Team
	if team and not player.Neutral then
		teamLabel.Text = "You are on " .. team.Name
		teamLabel.TextColor3 = if team:GetAttribute("TeamKey") == "Green" then C.Green else C.Brown
	else
		teamLabel.Text = ""
	end
end

local lastState = ""
local function onStateChanged()
	local state = status:GetAttribute("State") or "Waiting"
	if state == "Round" and lastState ~= "Round" then
		SoundUtil.Play2D(GameConfig.SOUNDS.RoundStart, 0.6)
		pushLine(notes, "Round started! Shop open for " .. GameConfig.SHOP_OPEN_TIME .. "s at your supply crate.", C.Accent, 6)
	elseif state == "Results" and lastState == "Round" then
		SoundUtil.Play2D(GameConfig.SOUNDS.RoundEnd, 0.6)
	end
	lastState = state
	local inRound = state == "CamoSelect" or state == "Round" or state == "Results"
	greenBox.Visible = inRound
	brownBox.Visible = inRound
end

local function onResultChanged()
	local text = status:GetAttribute("ResultText") or ""
	banner.Text = text
	banner.Visible = text ~= ""
end

function HudController.Init()
	status:GetAttributeChangedSignal("State"):Connect(onStateChanged)
	status:GetAttributeChangedSignal("ResultText"):Connect(onResultChanged)
	player:GetPropertyChangedSignal("Team"):Connect(refreshTeam)
	player:GetPropertyChangedSignal("Neutral"):Connect(refreshTeam)
	onStateChanged()
	onResultChanged()
	refreshTeam()

	-- Timer + alive counts, every frame (cheap)
	RunService.Heartbeat:Connect(function()
		local state = status:GetAttribute("State") or "Waiting"
		local endsAt = status:GetAttribute("EndsAt") or 0
		if endsAt > 0 then
			timerLabel.Text = UIUtil.formatTime(endsAt - workspace:GetServerTimeNow())
		else
			timerLabel.Text = "--:--"
		end
		local text = status:GetAttribute("StatusText")
		stateLabel.Text = if text and text ~= "" then text else (STATE_TEXT[state] or "")
		greenBox.Text = "GREEN " .. (status:GetAttribute("GreenAlive") or 0)
		brownBox.Text = (status:GetAttribute("BrownAlive") or 0) .. " BROWN"
	end)

	Remotes.Get("KillFeed").OnClientEvent:Connect(function(killerName: string?, victimName: string, headshot: boolean)
		local text
		if killerName then
			text = killerName .. " eliminated " .. victimName .. (if headshot then " (headshot)" else "")
		else
			text = victimName .. " was eliminated"
		end
		pushLine(feed, text, C.Text, 6)
	end)

	Remotes.Get("Notify").OnClientEvent:Connect(function(text: string)
		if typeof(text) == "string" then
			pushLine(notes, text, C.Gold, 4)
		end
	end)

	Remotes.Get("HitMarker").OnClientEvent:Connect(function(headshot: boolean, killed: boolean)
		hitMarker.TextColor3 = if headshot or killed then C.Danger else Color3.new(1, 1, 1)
		hitMarker.Visible = true
		SoundUtil.Play2D(GameConfig.SOUNDS.HitMarker, if killed then 0.9 else 0.6)
		task.delay(0.25, function()
			hitMarker.Visible = false
		end)
	end)

	player:GetAttributeChangedSignal("InEnemyZone"):Connect(function()
		zoneWarning.Visible = player:GetAttribute("InEnemyZone") == true
	end)

	-- The server only tells us birds were spotted, never the stillness timer
	player:GetAttributeChangedSignal("BirdsSpottedAt"):Connect(function()
		local stamp = player:GetAttribute("BirdsSpottedAt")
		birdIcon.Visible = true
		task.delay(4, function()
			if player:GetAttribute("BirdsSpottedAt") == stamp then
				birdIcon.Visible = false
			end
		end)
	end)
end

return HudController
