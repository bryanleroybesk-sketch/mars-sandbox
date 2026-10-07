--[[
	ShopService  (ModuleScript in ServerScriptService/Services)

	The rusty supply crate in each ruin house opens the shop.

	Rules (all checked on the SERVER, every time):
	  * only during the first SHOP_OPEN_TIME seconds of a round
	  * only at YOUR team's crate, while inside your own ruin house
	    (your own safe zone)
	  * you must be alive and have enough Coins
	  * one of each one-round item per round

	The client only sends an item id ("Bandage", "Camo_Bamboo", ...).
	Prices come from the server's copy of ShopCatalog.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local DataService = require(script.Parent.DataService)
local ItemService = require(script.Parent.ItemService)
local MapBuilder = require(script.Parent.MapBuilder)
local RoundState = require(script.Parent.RoundState)
local SafeZoneService = require(script.Parent.SafeZoneService)
local SniperService = require(script.Parent.SniperService)
local TeamManager = require(script.Parent.TeamManager)

local ShopService = {}

local boughtThisRound: { [Player]: { [string]: boolean } } = {}
local lastRequest: { [Player]: number } = {}

function ShopService.IsOpen(): boolean
	return RoundState.IsRoundActive() and RoundState.TimeIntoRound() <= GameConfig.SHOP_OPEN_TIME
end

-- Returns (true) or (false, reason)
local function canUseShop(player: Player): (boolean, string?)
	if not ShopService.IsOpen() then
		return false, "The shop is only open for the first " .. GameConfig.SHOP_OPEN_TIME .. " seconds of a round."
	end
	if not RoundState.IsAlive(player) then
		return false, "You must be alive to use the shop."
	end
	if not SafeZoneService.IsInOwnSafeZone(player) then
		return false, "You can only shop inside your own team's ruin house."
	end
	return true
end

-- Everything the shop UI needs to draw itself for this player.
local function buildState(player: Player)
	local profile = DataService.GetProfile(player)
	local roundStartServerTime = Remotes.GetStatus():GetAttribute("RoundStartedAt") or 0
	return {
		Coins = if profile then profile.Coins else 0,
		OwnedCamos = if profile then profile.OwnedCamos else {},
		OwnedSkins = if profile then profile.OwnedSkins else {},
		EquippedSkin = if profile then profile.EquippedSkin else "",
		Bought = boughtThisRound[player] or {},
		ClosesAt = roundStartServerTime + GameConfig.SHOP_OPEN_TIME,
	}
end

local function onPromptTriggered(player: Player, crateTeam: string)
	if TeamManager.GetTeamKey(player) ~= crateTeam then
		Remotes.Get("Notify"):FireClient(player, "This isn't your team's supply crate.")
		return
	end
	local ok, reason = canUseShop(player)
	if not ok then
		Remotes.Get("Notify"):FireClient(player, reason)
		return
	end
	Remotes.Get("OpenShop"):FireClient(player, buildState(player))
end

local function onBuy(player: Player, itemId: any)
	local result = Remotes.Get("ShopResult")

	-- Validate the argument and rate-limit
	if typeof(itemId) ~= "string" or #itemId > 50 then
		return
	end
	local now = os.clock()
	if lastRequest[player] and now - lastRequest[player] < 0.25 then
		return
	end
	lastRequest[player] = now

	local entry = ShopCatalog.ById[itemId]
	if not entry then
		return
	end
	local ok, reason = canUseShop(player)
	if not ok then
		result:FireClient(player, false, reason, buildState(player))
		return
	end

	local item = entry.Item
	local message

	if entry.Kind == "RoundItem" then
		local bought = boughtThisRound[player] or {}
		boughtThisRound[player] = bought
		if bought[itemId] then
			result:FireClient(player, false, "You already bought that this round.", buildState(player))
			return
		end
		if not DataService.SpendCoins(player, item.Price) then
			result:FireClient(player, false, "Not enough Coins.", buildState(player))
			return
		end
		bought[itemId] = true
		ItemService.GiveItem(player, itemId)
		message = "Bought " .. item.Name .. "!"
	elseif entry.Kind == "Camo" then
		if DataService.OwnsCamo(player, item.CamoName) then
			result:FireClient(player, false, "You already own that camo.", buildState(player))
			return
		end
		if not DataService.SpendCoins(player, item.Price) then
			result:FireClient(player, false, "Not enough Coins.", buildState(player))
			return
		end
		DataService.GrantCamo(player, item.CamoName)
		message = "Unlocked " .. item.Name .. "! Pick it in the next camo selection."
	elseif entry.Kind == "Skin" then
		if DataService.OwnsSkin(player, itemId) then
			-- Owned already: clicking it equips it (or unequips if equipped)
			local newSkin = if DataService.GetEquippedSkin(player) == itemId then "" else itemId
			DataService.SetEquippedSkin(player, newSkin)
			message = if newSkin == "" then "Skin removed." else "Equipped " .. item.Name .. "."
		else
			if not DataService.SpendCoins(player, item.Price) then
				result:FireClient(player, false, "Not enough Coins.", buildState(player))
				return
			end
			DataService.GrantSkin(player, itemId)
			DataService.SetEquippedSkin(player, itemId)
			message = "Unlocked and equipped " .. item.Name .. "!"
		end
		SniperService.RefreshSkin(player)
	end

	result:FireClient(player, true, message, buildState(player))
end

function ShopService.Init()
	for teamKey, house in MapBuilder.Info.Houses do
		local crate = house.Crate
		local prompt = crate and crate:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(player)
				onPromptTriggered(player, teamKey)
			end)
		end
	end
	Remotes.Get("ShopBuy").OnServerEvent:Connect(onBuy)
	Players.PlayerRemoving:Connect(function(player)
		boughtThisRound[player] = nil
		lastRequest[player] = nil
	end)
end

function ShopService.ResetRound()
	table.clear(boughtThisRound)
end

return ShopService
