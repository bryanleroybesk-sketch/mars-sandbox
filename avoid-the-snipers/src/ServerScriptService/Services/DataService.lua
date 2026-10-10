--[[
	DataService  (ModuleScript in ServerScriptService/Services)

	Loads and saves each player's permanent data with DataStoreService:
	  TotalKills, TotalWins, Coins, OwnedCamos, OwnedSkins, EquippedSkin

	Also creates the "leaderstats" folder for the player list:
	  Kills and Wins = THIS SERVER only (reset when you leave)
	  Coins          = your saved coins

	Every DataStore call is wrapped in pcall and retried, because Roblox
	DataStores can fail. Data is saved when a player leaves, every few
	minutes (autosave), and when the server shuts down (BindToClose).

	NOTE: In Studio, enable Game Settings > Security >
	"Enable Studio Access to API Services" or saving will be skipped.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)

local DataService = {}

export type Profile = {
	TotalKills: number,
	TotalWins: number,
	Coins: number,
	OwnedCamos: { string },
	OwnedSkins: { string },
	EquippedSkin: string,
}

local function defaultProfile(): Profile
	return {
		TotalKills = 0,
		TotalWins = 0,
		Coins = 0,
		OwnedCamos = {},
		OwnedSkins = {},
		EquippedSkin = "",
	}
end

local store: DataStore? = nil
local profiles: { [Player]: Profile } = {}
local loaded: { [Player]: boolean } = {} -- only save data we actually loaded

local MAX_RETRIES = 3

local function withRetries(label: string, fn: () -> ()): boolean
	for attempt = 1, MAX_RETRIES do
		local ok, err = pcall(fn)
		if ok then
			return true
		end
		warn(("[DataService] %s failed (attempt %d): %s"):format(label, attempt, tostring(err)))
		task.wait(attempt)
	end
	return false
end

-- Pushes profile values into leaderstats and player attributes for the UI.
local function refreshPlayerValues(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local stats = player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild("Coins")
	if coins then
		(coins :: IntValue).Value = profile.Coins
	end
	player:SetAttribute("Coins", profile.Coins)
	player:SetAttribute("TotalKills", profile.TotalKills)
	player:SetAttribute("TotalWins", profile.TotalWins)
	-- Attributes can't hold tables, so lists are sent as JSON text.
	player:SetAttribute("OwnedCamos", HttpService:JSONEncode(profile.OwnedCamos))
	player:SetAttribute("OwnedSkins", HttpService:JSONEncode(profile.OwnedSkins))
	player:SetAttribute("EquippedSkin", profile.EquippedSkin)
end

local function createLeaderstats(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	for _, name in { "Kills", "Wins", "Coins" } do
		local value = Instance.new("IntValue")
		value.Name = name
		value.Parent = stats
	end
	stats.Parent = player
end

local function load(player: Player)
	createLeaderstats(player)
	local profile = defaultProfile()
	profiles[player] = profile

	if store then
		local data
		local ok = withRetries("Load " .. player.UserId, function()
			data = (store :: DataStore):GetAsync("Player_" .. player.UserId)
		end)
		if ok then
			loaded[player] = true
			if type(data) == "table" then
				-- Copy only known fields with the right types (old/bad data is ignored)
				for key, default in defaultProfile() do
					if type(data[key]) == type(default) then
						(profile :: any)[key] = data[key]
					end
				end
			end
		else
			-- Don't save over good data we failed to read.
			warn("[DataService] Could not load data for " .. player.Name .. "; progress this session won't be saved.")
		end
	end

	refreshPlayerValues(player)
end

local function save(player: Player)
	local profile = profiles[player]
	if not (store and profile and loaded[player]) then
		return
	end
	withRetries("Save " .. player.UserId, function()
		(store :: DataStore):UpdateAsync("Player_" .. player.UserId, function()
			return profile
		end)
	end)
end

function DataService.Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DATASTORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStores unavailable (enable API access in Studio). Data will not be saved.", result)
	end

	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		save(player)
		profiles[player] = nil
		loaded[player] = nil
	end)

	-- Save everyone when the server shuts down
	-- (Roblox gives BindToClose up to 30 seconds; we save everyone in parallel.)
	game:BindToClose(function()
		local remaining = 0
		for _, player in Players:GetPlayers() do
			remaining += 1
			task.spawn(function()
				save(player)
				remaining -= 1
			end)
		end
		local start = os.clock()
		while remaining > 0 and os.clock() - start < 25 do
			task.wait(0.1)
		end
	end)

	-- Autosave in case the server crashes
	task.spawn(function()
		while true do
			task.wait(GameConfig.AUTOSAVE_INTERVAL)
			for _, player in Players:GetPlayers() do
				task.spawn(save, player)
			end
		end
	end)
end

-- Waits (up to 10 s) until the player's data is ready.
function DataService.GetProfile(player: Player): Profile?
	local start = os.clock()
	while not profiles[player] and player.Parent and os.clock() - start < 10 do
		task.wait(0.1)
	end
	return profiles[player]
end

local function addStat(player: Player, statName: string, amount: number)
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild(statName)
	if value then
		(value :: IntValue).Value += amount
	end
end

function DataService.AddCoins(player: Player, amount: number, reason: string?)
	local profile = profiles[player]
	if not profile or amount <= 0 then
		return
	end
	profile.Coins += math.floor(amount)
	refreshPlayerValues(player)
end

-- Returns true if the player had enough coins (and they were removed).
function DataService.SpendCoins(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or amount < 0 or profile.Coins < amount then
		return false
	end
	profile.Coins -= amount
	refreshPlayerValues(player)
	return true
end

function DataService.AddKill(player: Player)
	local profile = profiles[player]
	if profile then
		profile.TotalKills += 1
	end
	addStat(player, "Kills", 1)
	refreshPlayerValues(player)
end

function DataService.AddWin(player: Player)
	local profile = profiles[player]
	if profile then
		profile.TotalWins += 1
	end
	addStat(player, "Wins", 1)
	refreshPlayerValues(player)
end

function DataService.OwnsCamo(player: Player, camoName: string): boolean
	local profile = profiles[player]
	return profile ~= nil and table.find(profile.OwnedCamos, camoName) ~= nil
end

function DataService.GrantCamo(player: Player, camoName: string)
	local profile = profiles[player]
	if profile and not table.find(profile.OwnedCamos, camoName) then
		table.insert(profile.OwnedCamos, camoName)
		refreshPlayerValues(player)
	end
end

function DataService.OwnsSkin(player: Player, skinId: string): boolean
	local profile = profiles[player]
	return profile ~= nil and table.find(profile.OwnedSkins, skinId) ~= nil
end

function DataService.GrantSkin(player: Player, skinId: string)
	local profile = profiles[player]
	if profile and not table.find(profile.OwnedSkins, skinId) then
		table.insert(profile.OwnedSkins, skinId)
		refreshPlayerValues(player)
	end
end

function DataService.SetEquippedSkin(player: Player, skinId: string)
	local profile = profiles[player]
	if profile then
		profile.EquippedSkin = skinId
		refreshPlayerValues(player)
	end
end

function DataService.GetEquippedSkin(player: Player): string
	local profile = profiles[player]
	return if profile then profile.EquippedSkin else ""
end

return DataService
