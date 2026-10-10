--[[
	MainMenu  (ModuleScript in StarterPlayerScripts/Controllers)

	Simple full-screen menu with a Play button and your saved stats.
	Pressing Play tells the server you're ready to be put into rounds
	(players still on this menu are left out of the next round).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local SoundUtil = require(ReplicatedStorage.Shared:WaitForChild("SoundUtil"))
local UIUtil = require(script.Parent.UIUtil)

local MainMenu = {}

local player = Players.LocalPlayer
local C = UIUtil.Colors

function MainMenu.Init()
	local gui = UIUtil.screen("MainMenu", 20)

	local backdrop = UIUtil.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(16, 24, 14),
		BackgroundTransparency = 0.1,
	}, gui)
	UIUtil.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(40, 60, 32), Color3.fromRGB(10, 14, 9)),
		Rotation = 90,
	}, backdrop)

	UIUtil.label("AVOID THE SNIPERS", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.18, 0),
		Size = UDim2.new(0.8, 0, 0, 70),
		TextColor3 = C.Accent,
	}, backdrop)
	UIUtil.label("Hide. Spot. Shoot first. Don't stay still - the birds will give you away.", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.18, 78),
		Size = UDim2.new(0.8, 0, 0, 24),
		TextColor3 = C.TextDim,
		Font = UIUtil.FontRegular,
	}, backdrop)

	local stats = UIUtil.label("", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.45, 0),
		Size = UDim2.new(0.6, 0, 0, 24),
		TextColor3 = C.Gold,
		Font = UIUtil.FontRegular,
	}, backdrop)
	local function refreshStats()
		stats.Text = ("Total kills: %d    Total wins: %d    Coins: %d"):format(
			player:GetAttribute("TotalKills") or 0,
			player:GetAttribute("TotalWins") or 0,
			player:GetAttribute("Coins") or 0
		)
	end
	for _, name in { "TotalKills", "TotalWins", "Coins" } do
		player:GetAttributeChangedSignal(name):Connect(refreshStats)
	end
	refreshStats()

	local play = UIUtil.button("PLAY", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.55, 0),
		Size = UDim2.new(0, 240, 0, 64),
		BackgroundColor3 = Color3.fromRGB(70, 110, 50),
	}, backdrop)

	UIUtil.label("Shift: sprint   C / Ctrl: crouch   Right mouse / Q: scope   Click: shoot", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -30),
		Size = UDim2.new(0.8, 0, 0, 20),
		TextColor3 = C.TextDim,
		Font = UIUtil.FontRegular,
	}, backdrop)

	play.MouseButton1Click:Connect(function()
		SoundUtil.Play2D(GameConfig.SOUNDS.UIClick, 0.5)
		Remotes.Get("PlayerReady"):FireServer()
		gui:Destroy()
	end)
end

return MainMenu
