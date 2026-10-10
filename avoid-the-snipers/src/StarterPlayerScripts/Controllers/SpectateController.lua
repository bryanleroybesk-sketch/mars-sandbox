--[[
	SpectateController  (ModuleScript in StarterPlayerScripts/Controllers)

	When you die in a round the server sets your "Spectating" attribute.
	You can then watch ALIVE TEAMMATES ONLY (never enemies), so dead
	players can't scout enemy positions. Use the < > buttons or the
	Left/Right arrow keys to switch.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local UIUtil = require(script.Parent.UIUtil)

local SpectateController = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local C = UIUtil.Colors

local gui = UIUtil.screen("Spectate", 3)
gui.Enabled = false
local bar = UIUtil.new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -20),
	Size = UDim2.new(0, 380, 0, 50),
	BackgroundColor3 = C.Panel,
	BackgroundTransparency = 0.2,
}, gui)
UIUtil.corner(bar, 10)
local prevButton = UIUtil.button("<", { Position = UDim2.new(0, 6, 0, 6), Size = UDim2.new(0, 38, 0, 38) }, bar)
local nextButton = UIUtil.button(">", { Position = UDim2.new(1, -44, 0, 6), Size = UDim2.new(0, 38, 0, 38) }, bar)
local nameLabel = UIUtil.label("", {
	Position = UDim2.new(0, 50, 0, 6),
	Size = UDim2.new(1, -100, 0, 38),
}, bar)

local index = 1

-- Alive teammates (players and bots, never me): { Name, Humanoid }
local function aliveTeammates(): { { Name: string, Humanoid: Humanoid } }
	local list = {}
	local myKey = player.Team and player.Team:GetAttribute("TeamKey")
	local bots = workspace:FindFirstChild("Bots")
	if bots and myKey then
		for _, model in bots:GetChildren() do
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if model:GetAttribute("TeamKey") == myKey and humanoid and humanoid.Health > 0 then
				table.insert(list, { Name = model.Name, Humanoid = humanoid })
			end
		end
	end
	for _, other in Players:GetPlayers() do
		if other ~= player and other.Team == player.Team and not other.Neutral and not other:GetAttribute("Spectating") then
			local humanoid = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				table.insert(list, { Name = other.DisplayName, Humanoid = humanoid })
			end
		end
	end
	return list
end

local function refresh()
	local spectating = player:GetAttribute("Spectating") == true and player.Team ~= nil and not player.Neutral
	gui.Enabled = spectating
	if not spectating then
		return
	end
	local mates = aliveTeammates()
	if #mates == 0 then
		nameLabel.Text = "No teammates left"
		return
	end
	index = ((index - 1) % #mates) + 1
	local target = mates[index]
	camera.CameraSubject = target.Humanoid
	nameLabel.Text = "Spectating " .. target.Name
end

local function step(delta: number)
	index += delta
	refresh()
end

function SpectateController.Init()
	prevButton.MouseButton1Click:Connect(function()
		step(-1)
	end)
	nextButton.MouseButton1Click:Connect(function()
		step(1)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not gui.Enabled then
			return
		end
		if input.KeyCode == Enum.KeyCode.Left then
			step(-1)
		elseif input.KeyCode == Enum.KeyCode.Right then
			step(1)
		end
	end)

	player:GetAttributeChangedSignal("Spectating"):Connect(function()
		index = 1
		refresh()
		if not player:GetAttribute("Spectating") then
			-- back to our own character
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
	end)

	-- Re-check every second (teammates die, leave, etc.)
	task.spawn(function()
		while true do
			task.wait(1)
			if gui.Enabled or player:GetAttribute("Spectating") then
				refresh()
			end
		end
	end)
end

return SpectateController
