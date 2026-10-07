--[[
	ShopCatalog  (ModuleScript in ReplicatedStorage/Shared)

	Everything the supply crate sells. The CLIENT only uses this to draw
	the shop; the SERVER uses it to check prices. A hacked client cannot
	change prices because the server reads its own copy.

	BALANCE RULE: nothing here raises damage, range or max health.
	Coins only buy tactics (one-round items) and style (camos, skins).
]]

local CamoData = require(script.Parent.CamoData)

local ShopCatalog = {}

-- One-round items: given as Tools, removed when the round ends.
ShopCatalog.RoundItems = {
	{
		Id = "Binoculars",
		Name = "Binoculars",
		Price = 40,
		Description = "Zoom in to scout without raising your rifle scope.",
	},
	{
		Id = "BirdWhistle",
		Name = "Bird Whistle",
		Price = 60,
		Description = "One use. Birds fly up where you aim - fake your position!",
	},
	{
		Id = "SmokeGrenade",
		Name = "Smoke Grenade",
		Price = 50,
		Description = "One throw. A smoke cloud for 8 seconds to cross open ground.",
	},
	{
		Id = "Bandage",
		Name = "Bandage",
		Price = 35,
		Description = "One use. Heals 40 health over 3 seconds. Stand still!",
	},
}

-- Sniper skins: cosmetic only, muted colors only (nothing bright or glowing).
ShopCatalog.Skins = {
	{ Id = "Skin_OliveDrab", Name = "Olive Drab", Price = 200, Color = Color3.fromRGB(85, 90, 55) },
	{ Id = "Skin_DesertTan", Name = "Desert Tan", Price = 300, Color = Color3.fromRGB(150, 130, 95) },
	{ Id = "Skin_Charcoal", Name = "Charcoal", Price = 350, Color = Color3.fromRGB(45, 45, 45) },
	{ Id = "Skin_Moss", Name = "Moss", Price = 400, Color = Color3.fromRGB(70, 95, 55) },
	{ Id = "Skin_Rust", Name = "Rust", Price = 500, Color = Color3.fromRGB(110, 65, 40) },
}

-- Camo unlocks are generated from CamoData (any camo with a price).
ShopCatalog.Camos = {}
for _, camo in CamoData.List do
	if camo.Price > 0 then
		table.insert(ShopCatalog.Camos, {
			Id = "Camo_" .. camo.Name,
			Name = camo.Name .. " Camo",
			CamoName = camo.Name,
			Price = camo.Price,
			Color = camo.Colors[1],
		})
	end
end

-- Lookup tables used by the server: ShopCatalog.ById["Bandage"]
ShopCatalog.ById = {}
for _, item in ShopCatalog.RoundItems do
	ShopCatalog.ById[item.Id] = { Kind = "RoundItem", Item = item }
end
for _, item in ShopCatalog.Skins do
	ShopCatalog.ById[item.Id] = { Kind = "Skin", Item = item }
end
for _, item in ShopCatalog.Camos do
	ShopCatalog.ById[item.Id] = { Kind = "Camo", Item = item }
end

return ShopCatalog
