--[[
	CamoData  (ModuleScript in ReplicatedStorage/Shared)

	The list of every camouflage. Each camo has three colors that are
	spread over the body parts to give a blotchy camo look.

	Price = 0  -> free for everyone (the 5 starter camos)
	Price > 0  -> permanent unlock bought in the shop

	Optional: put Shirt/Pants template IDs from the Creator Store in
	ShirtTemplate / PantsTemplate to also dress players in real camo
	clothing. Leave them "" to use plain colored body parts.
]]

local CamoData = {}

CamoData.DEFAULT_CAMO = "Jungle"

CamoData.List = {
	-- The 5 free starter camos (shown in this order in the menu)
	{
		Name = "Jungle",
		Price = 0,
		Colors = { Color3.fromRGB(46, 74, 38), Color3.fromRGB(30, 50, 25), Color3.fromRGB(70, 92, 45) },
		ShirtTemplate = "",
		PantsTemplate = "",
	},
	{
		Name = "Grass",
		Price = 0,
		Colors = { Color3.fromRGB(110, 150, 60), Color3.fromRGB(88, 128, 48), Color3.fromRGB(138, 168, 80) },
		ShirtTemplate = "",
		PantsTemplate = "",
	},
	{
		Name = "Rice Field",
		Price = 0,
		Colors = { Color3.fromRGB(158, 164, 72), Color3.fromRGB(128, 138, 55), Color3.fromRGB(184, 178, 96) },
		ShirtTemplate = "",
		PantsTemplate = "",
	},
	{
		Name = "Mud",
		Price = 0,
		Colors = { Color3.fromRGB(95, 70, 45), Color3.fromRGB(74, 54, 35), Color3.fromRGB(116, 90, 60) },
		ShirtTemplate = "",
		PantsTemplate = "",
	},
	{
		Name = "Shadow",
		Price = 0,
		Colors = { Color3.fromRGB(20, 28, 20), Color3.fromRGB(12, 16, 12), Color3.fromRGB(34, 42, 30) },
		ShirtTemplate = "",
		PantsTemplate = "",
	},

	-- Permanent unlocks (bought with Coins in the shop)
	{
		Name = "Bamboo",
		Price = 150,
		Colors = { Color3.fromRGB(120, 140, 70), Color3.fromRGB(92, 110, 50), Color3.fromRGB(158, 158, 98) },
		ShirtTemplate = "",
		PantsTemplate = "",
	},
	{
		Name = "Autumn",
		Price = 250,
		Colors = { Color3.fromRGB(138, 90, 42), Color3.fromRGB(108, 70, 35), Color3.fromRGB(158, 120, 62) },
		ShirtTemplate = "",
		PantsTemplate = "",
	},
	{
		Name = "Swamp",
		Price = 300,
		Colors = { Color3.fromRGB(60, 70, 45), Color3.fromRGB(45, 55, 40), Color3.fromRGB(84, 90, 55) },
		ShirtTemplate = "",
		PantsTemplate = "",
	},
	{
		Name = "Temple Stone",
		Price = 400,
		Colors = { Color3.fromRGB(110, 110, 95), Color3.fromRGB(85, 88, 75), Color3.fromRGB(130, 128, 110) },
		ShirtTemplate = "",
		PantsTemplate = "",
	},
}

-- Quick lookup: CamoData.ByName["Mud"]
CamoData.ByName = {}
for _, camo in CamoData.List do
	CamoData.ByName[camo.Name] = camo
end

-- Is this camo free for everyone?
function CamoData.IsFree(name: string): boolean
	local camo = CamoData.ByName[name]
	return camo ~= nil and camo.Price == 0
end

return CamoData
