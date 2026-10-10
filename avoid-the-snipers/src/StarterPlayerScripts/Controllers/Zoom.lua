--[[
	Zoom  (ModuleScript in StarterPlayerScripts/Controllers)

	Camera zoom shared by the sniper scope and the binoculars.
	Zoom is purely visual, so it's fine for the client to do it.
	  Zoom.Set("Scope")       -> sniper scope (crosshair overlay)
	  Zoom.Set("Binoculars")  -> binocular view (two circles overlay)
	  Zoom.Set(nil)           -> back to normal
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("GameConfig"))
local UIUtil = require(script.Parent.UIUtil)

local Zoom = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local current: string? = nil
local normalFov = 70
local normalCameraMode = Enum.CameraMode.Classic

local gui = UIUtil.screen("ZoomOverlay", 5)
gui.Enabled = false

-- Scope overlay: black edges + a thin crosshair in the middle
local scopeFrame = UIUtil.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
do
	local ring = UIUtil.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.9),
		BackgroundTransparency = 1,
	}, scopeFrame)
	UIUtil.new("UIAspectRatioConstraint", { AspectRatio = 1 }, ring)
	UIUtil.new("UIStroke", { Thickness = 2000, Color = Color3.new(0, 0, 0) }, ring) -- huge stroke = black outside the circle
	UIUtil.corner(ring, 10000)
	for _, size in { UDim2.new(1, 0, 0, 2), UDim2.new(0, 2, 1, 0) } do
		UIUtil.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = size,
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
		}, ring)
	end
end

-- Binocular overlay: two overlapping circles
local binoFrame = UIUtil.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
for _, x in { 0.38, 0.62 } do
	local circle = UIUtil.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, 0.5),
		Size = UDim2.fromScale(0.62, 0.62),
		BackgroundTransparency = 1,
	}, binoFrame)
	UIUtil.new("UIAspectRatioConstraint", { AspectRatio = 1 }, circle)
	UIUtil.new("UIStroke", { Thickness = 6, Color = Color3.new(0, 0, 0) }, circle)
	UIUtil.corner(circle, 10000)
end

function Zoom.Get(): string?
	return current
end

function Zoom.Set(mode: string?)
	if mode == current then
		return
	end
	if current == nil then
		-- remember the normal view before zooming
		normalFov = camera.FieldOfView
		normalCameraMode = player.CameraMode
	end
	current = mode

	if mode == nil then
		camera.FieldOfView = normalFov
		player.CameraMode = normalCameraMode
		UserInputService.MouseDeltaSensitivity = 1
		gui.Enabled = false
		return
	end

	player.CameraMode = Enum.CameraMode.LockFirstPerson
	gui.Enabled = true
	scopeFrame.Visible = mode == "Scope"
	binoFrame.Visible = mode == "Binoculars"
	if mode == "Scope" then
		camera.FieldOfView = GameConfig.SNIPER_SCOPE_FOV
		UserInputService.MouseDeltaSensitivity = GameConfig.SCOPE_SENSITIVITY
	else
		camera.FieldOfView = GameConfig.BINOCULARS_FOV
		UserInputService.MouseDeltaSensitivity = 0.4
	end
end

-- Leave zoom when the character dies or respawns
player.CharacterAdded:Connect(function()
	Zoom.Set(nil)
end)

return Zoom
