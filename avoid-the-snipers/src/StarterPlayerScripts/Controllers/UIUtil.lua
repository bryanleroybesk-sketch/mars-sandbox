--[[
	UIUtil  (ModuleScript in StarterPlayerScripts/Controllers)

	Builds UI from code so the whole game is plain text.
	  UIUtil.new("TextLabel", { Text = "Hi", Size = ... }, parent)
	Also holds shared colors/fonts so every screen looks the same.
]]

local Players = game:GetService("Players")

local UIUtil = {}

UIUtil.Colors = {
	Panel = Color3.fromRGB(24, 32, 22),
	PanelLight = Color3.fromRGB(40, 52, 36),
	Text = Color3.fromRGB(232, 236, 222),
	TextDim = Color3.fromRGB(170, 180, 160),
	Accent = Color3.fromRGB(150, 190, 90),
	Green = Color3.fromRGB(110, 180, 90),
	Brown = Color3.fromRGB(190, 130, 70),
	Danger = Color3.fromRGB(220, 90, 70),
	Gold = Color3.fromRGB(230, 200, 90),
}
UIUtil.Font = Enum.Font.GothamBold
UIUtil.FontRegular = Enum.Font.Gotham

function UIUtil.new(className: string, props: { [string]: any }?, parent: Instance?): any
	local instance = Instance.new(className)
	if props then
		for key, value in props do
			(instance :: any)[key] = value
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

-- Rounded corners on any GuiObject
function UIUtil.corner(parent: Instance, radius: number?)
	UIUtil.new("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, parent)
end

-- A ScreenGui that survives respawns
function UIUtil.screen(name: string, displayOrder: number?): ScreenGui
	return UIUtil.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = displayOrder or 0,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, Players.LocalPlayer:WaitForChild("PlayerGui"))
end

-- A standard label
function UIUtil.label(text: string, props: { [string]: any }?, parent: Instance?): TextLabel
	local label = UIUtil.new("TextLabel", {
		Text = text,
		BackgroundTransparency = 1,
		TextColor3 = UIUtil.Colors.Text,
		Font = UIUtil.Font,
		TextScaled = true,
	}, parent)
	if props then
		for key, value in props do
			(label :: any)[key] = value
		end
	end
	return label
end

-- A standard button
function UIUtil.button(text: string, props: { [string]: any }?, parent: Instance?): TextButton
	local button = UIUtil.new("TextButton", {
		Text = text,
		BackgroundColor3 = UIUtil.Colors.PanelLight,
		TextColor3 = UIUtil.Colors.Text,
		Font = UIUtil.Font,
		TextScaled = true,
		AutoButtonColor = true,
	}, parent)
	if props then
		for key, value in props do
			(button :: any)[key] = value
		end
	end
	UIUtil.corner(button)
	return button
end

-- "1:05" style time text
function UIUtil.formatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

return UIUtil
