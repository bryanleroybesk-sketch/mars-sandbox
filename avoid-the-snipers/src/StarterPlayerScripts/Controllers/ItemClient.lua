--[[
	ItemClient  (ModuleScript in StarterPlayerScripts/Controllers)

	Client side of the one-round shop items:
	  Binoculars    - click (or tap) to toggle zoom. Purely visual.
	  Bird Whistle  - click to whistle at the spot you aim at
	  Smoke Grenade - click to throw at the spot you aim at
	  Bandage       - click to start healing (stand still!)
	Whistle/smoke/bandage only send a REQUEST; the server validates it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local Zoom = require(script.Parent.Zoom)

local ItemClient = {}

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local function onActivated(tool: Tool)
	local itemId = tool:GetAttribute("ItemId")
	if itemId == "Binoculars" then
		Zoom.Set(if Zoom.Get() == "Binoculars" then nil else "Binoculars")
	elseif itemId == "BirdWhistle" or itemId == "SmokeGrenade" then
		Remotes.Get("UseItem"):FireServer(itemId, mouse.Hit.Position)
	elseif itemId == "Bandage" then
		Remotes.Get("UseItem"):FireServer(itemId)
	end
end

local function watchCharacter(character: Model)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("ItemId") then
			local conn = child.Activated:Connect(function()
				onActivated(child)
			end)
			child.Unequipped:Once(function()
				conn:Disconnect()
				if child:GetAttribute("ItemId") == "Binoculars" and Zoom.Get() == "Binoculars" then
					Zoom.Set(nil)
				end
			end)
		end
	end)
end

function ItemClient.Init()
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
end

return ItemClient
