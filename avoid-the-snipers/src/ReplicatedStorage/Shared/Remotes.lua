--[[
	Remotes  (ModuleScript in ReplicatedStorage/Shared)

	One place that creates (on the server) or finds (on the client) every
	RemoteEvent the game uses, plus the "GameStatus" folder whose attributes
	tell clients what the round is doing.

	Client -> Server events are REQUESTS. The server checks every one of them.
	Server -> Client events are just information for UI and effects.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local EVENT_NAMES = {
	-- Client -> Server (always validated on the server)
	"PlayerReady", -- (no args) player pressed Play on the main menu
	"SelectCamo", -- (camoName: string)
	"SetStance", -- (stance: "Crouch" | "Walk" | "Sprint")
	"FireSniper", -- (direction: Vector3, hitPart: BasePart?, hitPosition: Vector3?)
	"ShopBuy", -- (itemId: string)
	"UseItem", -- (itemId: string, aimPosition: Vector3?)

	-- Server -> Client
	"CamoMenu", -- (open: boolean, ownedCamos: {string}?, endsAt: number?)
	"ShotFired", -- (origin: Vector3, hitPosition: Vector3, soundId: string)
	"HitMarker", -- (isHeadshot: boolean, killed: boolean)
	"KillFeed", -- (killerName: string?, victimName: string, headshot: boolean)
	"BirdFlock", -- (position: Vector3, count: number, kind: string)
	"OpenShop", -- (shopState: table)
	"ShopResult", -- (success: boolean, message: string, shopState: table?)
	"Notify", -- (text: string)
}

local isServer = RunService:IsServer()
local folder: Folder
local statusFolder: Folder

if isServer then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing then
		folder = existing :: any
	else
		local newFolder = Instance.new("Folder")
		newFolder.Name = "Remotes"
		newFolder.Parent = ReplicatedStorage
		folder = newFolder
	end
	for _, name in EVENT_NAMES do
		if not folder:FindFirstChild(name) then
			local event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = folder
		end
	end

	local existingStatus = ReplicatedStorage:FindFirstChild("GameStatus")
	if existingStatus then
		statusFolder = existingStatus :: any
	else
		local newStatus = Instance.new("Folder")
		newStatus.Name = "GameStatus"
		newStatus.Parent = ReplicatedStorage
		statusFolder = newStatus
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	statusFolder = ReplicatedStorage:WaitForChild("GameStatus") :: Folder
end

-- Returns the RemoteEvent with this name.
function Remotes.Get(name: string): RemoteEvent
	local event = if isServer then folder:FindFirstChild(name) else folder:WaitForChild(name)
	assert(event, "Unknown remote: " .. name)
	return event :: RemoteEvent
end

-- The folder whose attributes describe the round. Attributes used:
--   State        "Waiting" | "CamoSelect" | "Round" | "Results" | "Intermission"
--   EndsAt       server time (workspace:GetServerTimeNow()) when this state ends, or 0
--   StatusText   short text for the top bar ("Waiting for players (1/2)")
--   GreenAlive / BrownAlive   players alive per team
--   ResultText   the results banner text
--   RoundStartedAt  server time the current round started
function Remotes.GetStatus(): Folder
	return statusFolder
end

return Remotes
