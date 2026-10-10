--[[
	CamoMenu  (ModuleScript in StarterPlayerScripts/Controllers)

	Full-screen camo picker shown during camo selection. Each button has
	a 3-color swatch preview. Clicking sends ONLY the camo name; the
	server checks it and paints your character (you see it instantly).
	The server also decides which camos you're allowed to see here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local CamoData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CamoData"))
local Remotes = require(ReplicatedStorage.Shared:WaitForChild("Remotes"))
local SoundUtil = require(ReplicatedStorage.Shared:WaitForChild("SoundUtil"))
local UIUtil = require(script.Parent.UIUtil)

local CamoMenu = {}
local C = UIUtil.Colors

local gui = UIUtil.screen("CamoMenu", 10)
gui.Enabled = false

local backdrop = UIUtil.new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.35,
}, gui)

UIUtil.label("CHOOSE YOUR CAMOUFLAGE", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.1, 0),
	Size = UDim2.new(0.8, 0, 0, 44),
}, backdrop)
local timerLabel = UIUtil.label("", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.1, 50),
	Size = UDim2.new(0.6, 0, 0, 26),
	TextColor3 = C.TextDim,
	Font = UIUtil.FontRegular,
}, backdrop)

local grid = UIUtil.new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.1, 100),
	Size = UDim2.new(0.9, 0, 0.65, 0),
	BackgroundTransparency = 1,
}, backdrop)
UIUtil.new("UIGridLayout", {
	CellSize = UDim2.new(0, 150, 0, 150),
	CellPadding = UDim2.new(0, 12, 0, 12),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, grid)

local buttons: { [string]: TextButton } = {}
local selected: string? = nil
local endsAt = 0

local function highlight()
	for name, button in buttons do
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Enabled = name == selected
		end
	end
end

local function build(available: { string })
	for _, button in buttons do
		button:Destroy()
	end
	table.clear(buttons)

	for index, camo in CamoData.List do
		if not table.find(available, camo.Name) then
			continue -- not owned: don't show it
		end
		local button = UIUtil.button("", {
			LayoutOrder = index,
			BackgroundColor3 = C.Panel,
		}, grid)
		UIUtil.new("UIStroke", { Color = C.Gold, Thickness = 3, Enabled = false }, button)

		-- 3-color swatch preview
		for i, color in camo.Colors do
			local swatch = UIUtil.new("Frame", {
				Position = UDim2.new((i - 1) / 3, 6, 0, 8),
				Size = UDim2.new(1 / 3, -8, 0.6, 0),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
			}, button)
			UIUtil.corner(swatch, 6)
		end
		UIUtil.label(camo.Name, {
			Position = UDim2.new(0, 6, 0.7, 0),
			Size = UDim2.new(1, -12, 0.25, 0),
		}, button)

		button.MouseButton1Click:Connect(function()
			selected = camo.Name
			highlight()
			SoundUtil.Play2D(GameConfig.SOUNDS.UIClick, 0.4)
			Remotes.Get("SelectCamo"):FireServer(camo.Name)
		end)
		buttons[camo.Name] = button
	end
end

function CamoMenu.Init()
	Remotes.Get("CamoMenu").OnClientEvent:Connect(function(open: boolean, available: { string }?, closesAt: number?)
		if open then
			selected = nil
			endsAt = closesAt or 0
			build(available or {})
			highlight()
			gui.Enabled = true
			task.spawn(function()
				while gui.Enabled do
					local left = endsAt - workspace:GetServerTimeNow()
					timerLabel.Text = ("%d seconds left - %s is chosen if you don't pick"):format(
						math.max(0, math.ceil(left)),
						CamoData.DEFAULT_CAMO
					)
					task.wait(0.2)
				end
			end)
		else
			gui.Enabled = false
		end
	end)
end

return CamoMenu
