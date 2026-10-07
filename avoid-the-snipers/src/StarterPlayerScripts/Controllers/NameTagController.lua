--[[
	NameTagController  (ModuleScript in StarterPlayerScripts/Controllers)

	During rounds the SERVER hides every name tag and health bar
	(DisplayDistanceType = None). This script turns them back on, on YOUR
	screen only, for YOUR TEAMMATES. Enemy names stay hidden.

	(Changing a property of someone else's Humanoid on the client only
	affects your own screen - it doesn't replicate.)
]]

local Players = game:GetService("Players")

local NameTagController = {}

local player = Players.LocalPlayer

local function update()
	local myTeam = if player.Neutral then nil else player.Team
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local humanoid = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and myTeam and not other.Neutral then
				if other.Team == myTeam then
					humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
					humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
				else
					humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
					humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
				end
			end
		end
	end
end

-- Bots (workspace.Bots) carry a "TeamKey" attribute on their body
local function updateBots()
	local myKey = if player.Neutral or not player.Team then nil else player.Team:GetAttribute("TeamKey")
	local folder = workspace:FindFirstChild("Bots")
	if not folder or not myKey then
		return
	end
	for _, model in folder:GetChildren() do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local friendly = model:GetAttribute("TeamKey") == myKey
			humanoid.DisplayDistanceType = if friendly
				then Enum.HumanoidDisplayDistanceType.Viewer
				else Enum.HumanoidDisplayDistanceType.None
			humanoid.HealthDisplayType = if friendly
				then Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
				else Enum.HumanoidHealthDisplayType.AlwaysOff
		end
	end
end

function NameTagController.Init()
	task.spawn(function()
		while true do
			update()
			updateBots()
			task.wait(0.5)
		end
	end)
end

return NameTagController
