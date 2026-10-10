--[[
	ClientMain  (LocalScript in StarterPlayer/StarterPlayerScripts)

	Starts every client controller once. All UI is created by code from
	here (instead of StarterGui) so it never resets or duplicates when
	your character respawns. StarterGui stays empty on purpose.
]]

local Controllers = script.Parent:WaitForChild("Controllers")

local order = {
	"MainMenu",
	"HudController",
	"CamoMenu",
	"ShopUI",
	"SniperClient",
	"ItemClient",
	"BirdEffects",
	"MovementController",
	"SpectateController",
	"NameTagController",
}

for _, name in order do
	local ok, err = pcall(function()
		require(Controllers:WaitForChild(name)).Init()
	end)
	if not ok then
		warn("[ClientMain] " .. name .. " failed to start: " .. tostring(err))
	end
end
