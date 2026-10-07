--[[
	ShopUI  (ModuleScript in StarterPlayerScripts/Controllers)

	The supply-crate shop window. It opens only when the SERVER says so
	(after checking team, house and time), shows items, prices and your
	Coins, and sends ONLY the item id when you click Buy. The server
	re-checks everything and answers with the new state.

	It also hides the enemy team's crate prompt on your screen, and hides
	your own crate's prompt once the shop has closed.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local ShopCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShopCatalog"))
local Remotes = require(ReplicatedStorage.Shared:WaitForChild("Remotes"))
local SoundUtil = require(ReplicatedStorage.Shared:WaitForChild("SoundUtil"))
local UIUtil = require(script.Parent.UIUtil)

local ShopUI = {}

local player = Players.LocalPlayer
local status = Remotes.GetStatus()
local C = UIUtil.Colors

local gui = UIUtil.screen("Shop", 8)
gui.Enabled = false

local panel = UIUtil.new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0, 560, 0, 440),
	BackgroundColor3 = C.Panel,
	BackgroundTransparency = 0.05,
}, gui)
UIUtil.corner(panel, 12)

UIUtil.label("SUPPLY CRATE", {
	Position = UDim2.new(0, 16, 0, 10),
	Size = UDim2.new(0, 220, 0, 30),
	TextXAlignment = Enum.TextXAlignment.Left,
}, panel)
local coinsLabel = UIUtil.label("Coins: 0", {
	Position = UDim2.new(0, 250, 0, 12),
	Size = UDim2.new(0, 160, 0, 26),
	TextColor3 = C.Gold,
}, panel)
local timeLabel = UIUtil.label("", {
	Position = UDim2.new(0, 16, 0, 42),
	Size = UDim2.new(1, -32, 0, 18),
	TextColor3 = C.TextDim,
	Font = UIUtil.FontRegular,
	TextXAlignment = Enum.TextXAlignment.Left,
}, panel)
local closeButton = UIUtil.button("X", {
	Position = UDim2.new(1, -46, 0, 10),
	Size = UDim2.new(0, 34, 0, 34),
	BackgroundColor3 = Color3.fromRGB(90, 40, 30),
}, panel)
local messageLabel = UIUtil.label("", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 16, 1, -8),
	Size = UDim2.new(1, -32, 0, 22),
	TextColor3 = C.Gold,
	Font = UIUtil.FontRegular,
}, panel)

local list = UIUtil.new("ScrollingFrame", {
	Position = UDim2.new(0, 12, 0, 66),
	Size = UDim2.new(1, -24, 1, -104),
	BackgroundTransparency = 1,
	ScrollBarThickness = 6,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
}, panel)
UIUtil.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, list)

local shopState: any = nil

local function header(text: string, order: number)
	UIUtil.label(text, {
		Size = UDim2.new(1, -8, 0, 24),
		TextColor3 = C.Accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order,
	}, list)
end

-- One row: [swatch] Name / description ............ [button]
local function row(order: number, name: string, description: string, buttonText: string, enabled: boolean, color: Color3?, onClick: () -> ())
	local frame = UIUtil.new("Frame", {
		Size = UDim2.new(1, -8, 0, 52),
		BackgroundColor3 = C.PanelLight,
		LayoutOrder = order,
	}, list)
	UIUtil.corner(frame, 8)
	local textX = 10
	if color then
		local swatch = UIUtil.new("Frame", {
			Position = UDim2.new(0, 8, 0, 8),
			Size = UDim2.new(0, 36, 0, 36),
			BackgroundColor3 = color,
		}, frame)
		UIUtil.corner(swatch, 6)
		textX = 52
	end
	UIUtil.label(name, {
		Position = UDim2.new(0, textX, 0, 4),
		Size = UDim2.new(1, -textX - 130, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, frame)
	UIUtil.label(description, {
		Position = UDim2.new(0, textX, 0, 27),
		Size = UDim2.new(1, -textX - 130, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.TextDim,
		Font = UIUtil.FontRegular,
	}, frame)
	local button = UIUtil.button(buttonText, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.new(0, 112, 0, 36),
		BackgroundColor3 = if enabled then Color3.fromRGB(70, 100, 50) else Color3.fromRGB(60, 60, 60),
		AutoButtonColor = enabled,
	}, frame)
	if enabled then
		button.MouseButton1Click:Connect(onClick)
	end
end

local function buy(itemId: string)
	SoundUtil.Play2D(GameConfig.SOUNDS.UIClick, 0.4)
	Remotes.Get("ShopBuy"):FireServer(itemId)
end

local function render()
	for _, child in list:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	if not shopState then
		return
	end
	coinsLabel.Text = "Coins: " .. tostring(shopState.Coins)
	local coins = shopState.Coins

	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	header("THIS ROUND ONLY", nextOrder())
	for _, item in ShopCatalog.RoundItems do
		local bought = shopState.Bought[item.Id]
		local text = if bought then "Bought" else (item.Price .. " coins")
		row(nextOrder(), item.Name, item.Description, text, not bought and coins >= item.Price, nil, function()
			buy(item.Id)
		end)
	end

	header("CAMOS (PERMANENT)", nextOrder())
	for _, item in ShopCatalog.Camos do
		local owned = table.find(shopState.OwnedCamos, item.CamoName) ~= nil
		local text = if owned then "Owned" else (item.Price .. " coins")
		row(nextOrder(), item.Name, "Unlock forever. Pick it in camo selection.", text, not owned and coins >= item.Price, item.Color, function()
			buy(item.Id)
		end)
	end

	header("SNIPER SKINS (COSMETIC)", nextOrder())
	for _, item in ShopCatalog.Skins do
		local owned = table.find(shopState.OwnedSkins, item.Id) ~= nil
		local equipped = shopState.EquippedSkin == item.Id
		local text = if equipped then "Unequip" elseif owned then "Equip" else (item.Price .. " coins")
		local enabled = owned or coins >= item.Price
		row(nextOrder(), item.Name, "Muted rifle color. Looks only.", text, enabled, item.Color, function()
			buy(item.Id)
		end)
	end
end

local function close()
	gui.Enabled = false
	shopState = nil
end

-- Show your own crate's prompt only while the shop is open
local prompts: { ProximityPrompt } = {}
local function updatePrompts()
	local myKey = player.Team and not player.Neutral and player.Team:GetAttribute("TeamKey")
	local roundStart = status:GetAttribute("RoundStartedAt") or 0
	local open = status:GetAttribute("State") == "Round"
		and workspace:GetServerTimeNow() - roundStart <= GameConfig.SHOP_OPEN_TIME
	if #prompts == 0 then
		-- Find the crate prompts once (the map has thousands of parts)
		local map = workspace:FindFirstChild("Map")
		if not map then
			return
		end
		for _, d in map:GetDescendants() do
			if d:IsA("ProximityPrompt") and d.Name == "ShopPrompt" then
				table.insert(prompts, d)
			end
		end
	end
	for _, prompt in prompts do
		local crate = prompt.Parent
		prompt.Enabled = open and myKey ~= nil and crate ~= nil and crate:GetAttribute("Team") == myKey
	end
end

function ShopUI.Init()
	closeButton.MouseButton1Click:Connect(close)

	Remotes.Get("OpenShop").OnClientEvent:Connect(function(state)
		shopState = state
		messageLabel.Text = ""
		render()
		gui.Enabled = true
	end)

	Remotes.Get("ShopResult").OnClientEvent:Connect(function(success: boolean, message: string, state)
		messageLabel.TextColor3 = if success then C.Gold else C.Danger
		messageLabel.Text = message or ""
		if state and gui.Enabled then
			shopState = state
			render()
		end
	end)

	-- Countdown, auto-close, prompt visibility
	task.spawn(function()
		while true do
			updatePrompts()
			if gui.Enabled and shopState then
				local left = (shopState.ClosesAt or 0) - workspace:GetServerTimeNow()
				timeLabel.Text = ("Shop closes in %d s"):format(math.max(0, math.ceil(left)))
				if left <= 0 or status:GetAttribute("State") ~= "Round" then
					close()
				end
			end
			task.wait(0.25)
		end
	end)
end

return ShopUI
