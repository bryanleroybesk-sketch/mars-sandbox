--[[
	MapBuilder  (ModuleScript in ServerScriptService/Services)

	Builds the jungle valley with code when the server starts, so the
	whole game fits in plain text files. Layout (seen from above):

	  -X  [Green hill + ruin house] ---- middle zone ---- [ruin house + Brown hill]  +X

	The middle zone is MIRRORED (point-symmetric), so neither team gets
	better cover. A fixed random seed means the map is the same every time.

	WANT TO HAND-EDIT THE MAP?
	  1. Press Play in Studio, select Workspace > Map, copy it (Ctrl+C).
	  2. Stop, select Workspace, paste (Ctrl+V).
	  3. Terrain is not copied that way: use the Terrain Editor or keep
	     BUILD_TERRAIN_IF_MAP_EXISTS = true below.
	  If a "Map" folder already exists, its parts are kept and only the
	  markers inside Map/Markers are read (house centers and grass patches).

	Other scripts read map data through MapBuilder.Info:
	  Info.Houses.Green / .Brown = { Center: Vector3, Crate: BasePart }
	  Info.GrassPatches = { { Position: Vector3, Radius: number }, ... }
]]

local Lighting = game:GetService("Lighting")
local Teams = game:GetService("Teams")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.GameConfig)

local MapBuilder = {}

MapBuilder.Info = {
	Houses = {} :: { [string]: { Center: Vector3, Crate: BasePart? } },
	GrassPatches = {} :: { { Position: Vector3, Radius: number } },
}

---------------------------------------------------------------------------
-- Layout numbers (studs). The valley runs along the X axis.
---------------------------------------------------------------------------
local HALF_LENGTH = 255 -- play area is X from -255 to 255
local HALF_WIDTH = 140 -- play area is Z from -140 to 140
local HOUSE_X = 205 -- houses at X = -205 (Green) and +205 (Brown)
local HOUSE_FLOOR_Y = 1
local LOBBY_POSITION = Vector3.new(0, 400, 0) -- floating lobby, far above the fog
local BUILD_TERRAIN_IF_MAP_EXISTS = true
local SEED = 20240611

-- Muted palette: nothing bright, so the ruin houses blend in.
local COLORS = {
	Stone = { Color3.fromRGB(104, 104, 94), Color3.fromRGB(92, 94, 84), Color3.fromRGB(116, 114, 102) },
	Moss = { Color3.fromRGB(64, 86, 48), Color3.fromRGB(78, 98, 54) },
	Grass = {
		Color3.fromRGB(78, 116, 50),
		Color3.fromRGB(92, 128, 56),
		Color3.fromRGB(68, 104, 44),
		Color3.fromRGB(104, 134, 62),
	},
	Leaves = { Color3.fromRGB(44, 74, 36), Color3.fromRGB(54, 86, 40), Color3.fromRGB(38, 64, 32) },
	Wood = { Color3.fromRGB(86, 64, 44), Color3.fromRGB(74, 56, 40) },
	Rock = { Color3.fromRGB(110, 110, 104), Color3.fromRGB(96, 98, 92), Color3.fromRGB(124, 122, 114) },
	Rust = Color3.fromRGB(112, 70, 42),
}

local rng = Random.new(SEED)
local mapFolder: Folder
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Creates an anchored part. `props` can set any Part property.
local function makePart(props: { [string]: any }, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	-- Order matters: Shape changes Size, and position must be set last.
	if props.Shape then
		part.Shape = props.Shape
	end
	if props.Size then
		part.Size = props.Size
	end
	for key, value in props do
		if key ~= "Shape" and key ~= "Size" and key ~= "CFrame" and key ~= "Position" then
			(part :: any)[key] = value
		end
	end
	if props.CFrame then
		part.CFrame = props.CFrame
	elseif props.Position then
		part.Position = props.Position
	end
	part.Parent = parent
	return part
end

-- Height of the terrain at (x, z). Terrain must already exist.
local function groundY(x: number, z: number): number
	local result = workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -400, 0), groundParams)
	return if result then result.Position.Y else 0
end

-- Calls build(x, z, yaw) for a point AND its mirror (-x, -z, yaw + 180),
-- so both halves of the map get identical cover.
local function mirrored(x: number, z: number, build: (number, number, number) -> ())
	local yaw = rng:NextNumber(0, 360)
	build(x, z, yaw)
	build(-x, -z, yaw + 180)
end

---------------------------------------------------------------------------
-- Props
---------------------------------------------------------------------------

-- A patch of tall grass. Blades are 5-6.5 studs tall, which hides a
-- crouching player (~3.5 studs) but not a standing one (~5.5 studs).
-- Grass has CanQuery = false: bullets pass through it (it's only visual cover).
local function tallGrassPatch(x: number, z: number, radius: number, parent: Instance)
	local patch = folder("TallGrass", parent)
	local clumps = math.floor(radius * radius * 0.32) + 4
	for _ = 1, clumps do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = math.sqrt(rng:NextNumber()) * radius
		local cx, cz = x + math.cos(angle) * dist, z + math.sin(angle) * dist
		local y = groundY(cx, cz)
		local yaw = rng:NextNumber(0, 180)
		for blade = 1, 3 do
			local height = rng:NextNumber(5, 6.5)
			makePart({
				Name = "Blade",
				Size = Vector3.new(0.2, height, rng:NextNumber(2.5, 3.5)),
				CFrame = CFrame.new(cx, y + height / 2 - 0.3, cz)
					* CFrame.Angles(0, math.rad(yaw + blade * 60), math.rad(rng:NextNumber(-8, 8))),
				Color = pick(COLORS.Grass),
				Material = Enum.Material.Grass,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
			}, patch)
		end
	end

	-- Invisible marker the server uses to know where tall grass is.
	local marker = makePart({
		Name = "GrassPatch",
		Size = Vector3.new(1, 1, 1),
		Position = Vector3.new(x, groundY(x, z), z),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	}, parent)
	marker:SetAttribute("Radius", radius)
	marker:AddTag("GrassPatchMarker")
end

local function bush(x: number, z: number, parent: Instance)
	local y = groundY(x, z)
	local model = folder("Bush", parent)
	for _ = 1, rng:NextInteger(2, 4) do
		local size = rng:NextNumber(3.5, 6.5)
		makePart({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(size, size, size),
			Position = Vector3.new(x + rng:NextNumber(-2.5, 2.5), y + size * 0.35, z + rng:NextNumber(-2.5, 2.5)),
			Color = pick(COLORS.Leaves),
			Material = Enum.Material.Grass,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		}, model)
	end
end

-- Rocks block bullets (CanQuery = true) and players.
local function rock(x: number, z: number, scale: number, parent: Instance)
	local y = groundY(x, z)
	local model = folder("Rock", parent)
	for i = 1, rng:NextInteger(2, 3) do
		local s = scale * rng:NextNumber(0.6, 1)
		makePart({
			Name = "Stone",
			Size = Vector3.new(s * 1.4, s, s * 1.2),
			CFrame = CFrame.new(x + (i - 2) * s * 0.5, y + s * 0.3, z + rng:NextNumber(-1, 1) * s * 0.4)
				* CFrame.Angles(math.rad(rng:NextNumber(-15, 15)), math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-15, 15))),
			Color = pick(COLORS.Rock),
			Material = Enum.Material.Slate,
		}, model)
	end
end

local function fallenLog(x: number, z: number, yaw: number, parent: Instance)
	local y = groundY(x, z)
	local length = rng:NextNumber(12, 20)
	local d = rng:NextNumber(2.2, 3.2)
	local cf = CFrame.new(x, y + d * 0.4, z) * CFrame.Angles(0, math.rad(yaw), 0)
	local model = folder("FallenLog", parent)
	-- A Cylinder's long axis is its X axis, so it already lies on its side.
	makePart({
		Name = "Log",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, d, d),
		CFrame = cf,
		Color = pick(COLORS.Wood),
		Material = Enum.Material.Wood,
	}, model)
	makePart({
		Name = "Moss",
		Size = Vector3.new(length * 0.7, 0.3, d * 0.6),
		CFrame = cf * CFrame.new(0, d * 0.45, 0),
		Color = pick(COLORS.Moss),
		Material = Enum.Material.Grass,
		CanCollide = false,
		CanQuery = false,
	}, model)
end

local function tree(x: number, z: number, parent: Instance)
	local y = groundY(x, z)
	local height = rng:NextNumber(18, 28)
	local width = rng:NextNumber(1.6, 2.6)
	local model = folder("Tree", parent)
	makePart({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, width, width),
		-- rotate so the cylinder stands upright
		CFrame = CFrame.new(x, y + height / 2 - 1, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = pick(COLORS.Wood),
		Material = Enum.Material.Wood,
	}, model)
	for _ = 1, rng:NextInteger(2, 3) do
		local size = rng:NextNumber(10, 16)
		makePart({
			Name = "Canopy",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(size, size, size),
			Position = Vector3.new(x + rng:NextNumber(-3, 3), y + height + rng:NextNumber(-3, 1), z + rng:NextNumber(-3, 3)),
			Color = pick(COLORS.Leaves),
			Material = Enum.Material.Grass,
			CanCollide = false,
			CanQuery = false,
			CastShadow = true,
		}, model)
	end
end

-- Mossy wall piece. `cf` is the center of the bottom of the wall.
local function wall(cf: CFrame, length: number, height: number, parent: Instance)
	local w = makePart({
		Name = "Wall",
		Size = Vector3.new(length, height, 1.5),
		CFrame = cf * CFrame.new(0, height / 2, 0),
		Color = pick(COLORS.Stone),
		Material = Enum.Material.Cobblestone,
	}, parent)
	-- moss on top
	makePart({
		Name = "Moss",
		Size = Vector3.new(length, 0.4, 1.7),
		CFrame = cf * CFrame.new(0, height + 0.1, 0),
		Color = pick(COLORS.Moss),
		Material = Enum.Material.Grass,
		CanCollide = false,
		CanQuery = false,
	}, parent)
	-- a couple of hanging vines
	for _ = 1, rng:NextInteger(1, 2) do
		local vineLength = rng:NextNumber(height * 0.4, height * 0.9)
		local side = if rng:NextNumber() > 0.5 then 0.85 else -0.85
		makePart({
			Name = "Vine",
			Size = Vector3.new(0.35, vineLength, 0.15),
			CFrame = cf * CFrame.new(rng:NextNumber(-length / 2 + 0.5, length / 2 - 0.5), height - vineLength / 2, side),
			Color = pick(COLORS.Leaves),
			Material = Enum.Material.Grass,
			CanCollide = false,
			CanQuery = false,
		}, parent)
	end
	return w
end

-- A small ruin for the middle zone: broken walls, a pillar, rubble.
local function ruin(x: number, z: number, yaw: number, parent: Instance)
	local y = groundY(x, z)
	local base = CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw), 0)
	local model = folder("Ruin", parent)
	makePart({
		Name = "Floor",
		Size = Vector3.new(14, 1, 12),
		CFrame = base * CFrame.new(0, 0.3, 0),
		Color = pick(COLORS.Stone),
		Material = Enum.Material.Slate,
	}, model)
	wall(base * CFrame.new(0, 0.8, -5.5), 14, rng:NextNumber(4, 6), model)
	wall(base * CFrame.new(-6.5, 0.8, -1) * CFrame.Angles(0, math.rad(90), 0), 8, rng:NextNumber(3, 5), model)
	wall(base * CFrame.new(4, 0.8, 5.5), 6, rng:NextNumber(2.5, 4), model)
	makePart({
		Name = "Pillar",
		Size = Vector3.new(1.8, 7, 1.8),
		CFrame = base * CFrame.new(6, 4.3, -4.5),
		Color = pick(COLORS.Stone),
		Material = Enum.Material.Cobblestone,
	}, model)
	makePart({
		Name = "FallenPillar",
		Size = Vector3.new(1.8, 1.8, 7),
		CFrame = base * CFrame.new(3, 1.6, 1) * CFrame.Angles(0, math.rad(35), math.rad(5)),
		Color = pick(COLORS.Stone),
		Material = Enum.Material.Cobblestone,
	}, model)
	for _ = 1, 4 do
		local s = rng:NextNumber(0.8, 1.6)
		makePart({
			Name = "Rubble",
			Size = Vector3.new(s, s * 0.7, s),
			CFrame = base * CFrame.new(rng:NextNumber(-7, 7), 1, rng:NextNumber(-6, 6)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0),
			Color = pick(COLORS.Stone),
			Material = Enum.Material.Slate,
		}, model)
	end
	bush(x + rng:NextNumber(-9, 9), z + rng:NextNumber(-9, 9), model)
end

---------------------------------------------------------------------------
-- Team ruin house (spawn). `dir` = +1 means the doorway faces +X.
---------------------------------------------------------------------------
local function ruinHouse(teamKey: string, hx: number, dir: number, parent: Instance)
	local model = folder(teamKey .. "House", parent)
	-- Local frame: +X points out of the doorway, toward the middle of the map.
	local base = CFrame.new(hx, HOUSE_FLOOR_Y, 0) * CFrame.Angles(0, if dir > 0 then 0 else math.rad(180), 0)

	makePart({
		Name = "Floor",
		Size = Vector3.new(20, 1, 18),
		CFrame = base * CFrame.new(0, -0.5, 0),
		Color = pick(COLORS.Stone),
		Material = Enum.Material.Slate,
	}, model)

	-- Back wall (dug into the hill), two heights so the top looks broken
	wall(base * CFrame.new(-10, 0, -4.5) * CFrame.Angles(0, math.rad(90), 0), 9, 7, model)
	wall(base * CFrame.new(-10, 0, 4.5) * CFrame.Angles(0, math.rad(90), 0), 9, 5.5, model)
	-- Side walls with gaps
	wall(base * CFrame.new(-5, 0, -9), 10, 6.5, model)
	wall(base * CFrame.new(6.5, 0, -9), 7, 4, model)
	wall(base * CFrame.new(-4, 0, 9), 12, 6, model)
	wall(base * CFrame.new(8, 0, 9), 4, 3, model)
	-- Front wall with a doorway in the middle (z from -3 to 3)
	wall(base * CFrame.new(10, 0, -6) * CFrame.Angles(0, math.rad(90), 0), 6, 5, model)
	wall(base * CFrame.new(10, 0, 6) * CFrame.Angles(0, math.rad(90), 0), 6, 3.5, model)

	-- Partly collapsed roof: covers the back half, one slab sagging down
	makePart({
		Name = "Roof",
		Size = Vector3.new(10, 1, 19),
		CFrame = base * CFrame.new(-5, 7.2, 0) * CFrame.Angles(math.rad(3), 0, math.rad(-4)),
		Color = pick(COLORS.Stone),
		Material = Enum.Material.Slate,
	}, model)
	makePart({
		Name = "RoofMoss",
		Size = Vector3.new(9, 0.4, 17),
		CFrame = base * CFrame.new(-5, 7.9, 0) * CFrame.Angles(math.rad(3), 0, math.rad(-4)),
		Color = pick(COLORS.Moss),
		Material = Enum.Material.Grass,
		CanCollide = false,
		CanQuery = false,
	}, model)
	makePart({
		Name = "CollapsedSlab",
		Size = Vector3.new(7, 0.8, 8),
		CFrame = base * CFrame.new(6, 3.2, -5) * CFrame.Angles(0, 0, math.rad(32)),
		Color = pick(COLORS.Stone),
		Material = Enum.Material.Slate,
	}, model)

	-- Rusty supply crate with the "Open Shop" prompt
	local crate = makePart({
		Name = "SupplyCrate",
		Size = Vector3.new(3, 2.6, 4),
		CFrame = base * CFrame.new(-7.5, 1.3, 0),
		Color = COLORS.Rust,
		Material = Enum.Material.CorrodedMetal,
	}, model)
	crate:SetAttribute("Team", teamKey)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Open Shop"
	prompt.ObjectText = "Supply Crate"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = crate

	-- Invisible SpawnLocations (no decal, no ForceField glow: Duration = 0)
	local teamColor = GameConfig.TEAMS[teamKey].TeamColor
	for i, offset in { Vector3.new(-2, 0, -5), Vector3.new(2, 0, 0), Vector3.new(-2, 0, 5) } do
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = teamKey .. "Spawn" .. i
		spawn.Anchored = true
		spawn.Size = Vector3.new(3, 0.2, 3)
		spawn.CFrame = base * CFrame.new(offset + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, math.rad(90), 0)
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.CanQuery = false
		spawn.Neutral = false
		spawn.TeamColor = teamColor
		spawn.AllowTeamChangeOnTouch = false
		spawn.Duration = 0
		spawn.Parent = model
	end

	-- Overgrown bushes and trees around the house, so it's hard to spot
	for _, offset in { Vector3.new(12, 0, -12), Vector3.new(13, 0, 11), Vector3.new(-2, 0, -13), Vector3.new(0, 0, 13) } do
		local p = base * CFrame.new(offset)
		bush(p.X, p.Z, model)
	end
	for _, offset in { Vector3.new(4, 0, -17), Vector3.new(4, 0, 17), Vector3.new(16, 0, -20), Vector3.new(16, 0, 21) } do
		local p = base * CFrame.new(offset)
		tree(p.X, p.Z, model)
	end

	-- Cover leaving the house: a trail of tall grass, bushes and rocks so
	-- nobody gets shot the moment they step out.
	local cover = folder(teamKey .. "SpawnCover", parent)
	local trail = {
		{ "grass", 18, -7, 7 },
		{ "grass", 18, 8, 6 },
		{ "bush", 24, -1, 0 },
		{ "grass", 33, 0, 8 },
		{ "rock", 29, -15, 4 },
		{ "rock", 40, 14, 4.5 },
		{ "grass", 48, -12, 8 },
		{ "grass", 50, 12, 7 },
		{ "log", 56, -3, 0 },
		{ "bush", 62, 6, 0 },
		{ "grass", 66, 0, 9 },
	}
	for _, entry in trail do
		local p = base * CFrame.new(entry[2] :: number, 0, entry[3] :: number)
		local kind = entry[1]
		if kind == "grass" then
			tallGrassPatch(p.X, p.Z, entry[4] :: number, cover)
		elseif kind == "bush" then
			bush(p.X, p.Z, cover)
		elseif kind == "rock" then
			rock(p.X, p.Z, entry[4] :: number, cover)
		elseif kind == "log" then
			fallenLog(p.X, p.Z, 90 + rng:NextNumber(-20, 20), cover)
		end
	end

	return crate
end

---------------------------------------------------------------------------
-- Terrain: flat valley floor, two hills, small mounds in the middle
---------------------------------------------------------------------------
local function buildTerrain()
	local terrain = workspace.Terrain
	terrain:Clear()
	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(84, 118, 54))
	terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(92, 78, 58))

	-- Valley floor: top surface at Y = 0
	terrain:FillBlock(CFrame.new(0, -10, 0), Vector3.new(HALF_LENGTH * 2 + 140, 20, HALF_WIDTH * 2 + 120), Enum.Material.Grass)

	-- Hills behind each spawn
	for _, sx in { -1, 1 } do
		terrain:FillBall(Vector3.new(sx * 275, -40, 0), 85, Enum.Material.Grass)
		terrain:FillBall(Vector3.new(sx * 285, -45, -70), 80, Enum.Material.Grass)
		terrain:FillBall(Vector3.new(sx * 285, -45, 70), 80, Enum.Material.Grass)

		-- Dig a notch into the hillside for the ruin house, with a dirt floor
		local hx = sx * HOUSE_X
		terrain:FillBlock(CFrame.new(hx, HOUSE_FLOOR_Y + 6, 0), Vector3.new(24, 12, 22), Enum.Material.Air)
		terrain:FillBlock(CFrame.new(hx, HOUSE_FLOOR_Y - 1, 0), Vector3.new(24, 2, 22), Enum.Material.Ground)
	end

	-- Low, mirrored mounds in the middle for extra cover
	for _ = 1, 6 do
		local x, z = rng:NextNumber(-140, -20), rng:NextNumber(-110, 110)
		local r = rng:NextNumber(10, 15)
		terrain:FillBall(Vector3.new(x, -r + rng:NextNumber(3, 6), z), r, Enum.Material.Grass)
		terrain:FillBall(Vector3.new(-x, -r + rng:NextNumber(3, 6), -z), r, Enum.Material.Grass)
	end
end

---------------------------------------------------------------------------
-- Map edges: invisible walls + a thick tree line so it looks natural
---------------------------------------------------------------------------
local function buildBoundaries(parent: Instance)
	local edges = folder("Boundaries", parent)
	local h = 400
	local walls = {
		{ Vector3.new(HALF_LENGTH + 2, h / 2 - 50, 0), Vector3.new(4, h, HALF_WIDTH * 2 + 8) },
		{ Vector3.new(-HALF_LENGTH - 2, h / 2 - 50, 0), Vector3.new(4, h, HALF_WIDTH * 2 + 8) },
		{ Vector3.new(0, h / 2 - 50, HALF_WIDTH + 2), Vector3.new(HALF_LENGTH * 2 + 8, h, 4) },
		{ Vector3.new(0, h / 2 - 50, -HALF_WIDTH - 2), Vector3.new(HALF_LENGTH * 2 + 8, h, 4) },
	}
	for i, w in walls do
		makePart({
			Name = "InvisibleWall" .. i,
			Position = w[1],
			Size = w[2],
			Transparency = 1,
			CanQuery = false, -- bullets and cameras ignore it
		}, edges)
	end

	-- Tree line along the long edges (it also hides the walls)
	local treeLine = folder("TreeLine", parent)
	for x = -HALF_LENGTH, HALF_LENGTH, 16 do
		tree(x + rng:NextNumber(-4, 4), HALF_WIDTH + rng:NextNumber(-2, 10), treeLine)
		tree(x + rng:NextNumber(-4, 4), -HALF_WIDTH - rng:NextNumber(-2, 10), treeLine)
	end
	for z = -HALF_WIDTH + 30, HALF_WIDTH - 30, 18 do
		tree(HALF_LENGTH + rng:NextNumber(-2, 8), z, treeLine)
		tree(-HALF_LENGTH - rng:NextNumber(-2, 8), z, treeLine)
	end
end

---------------------------------------------------------------------------
-- Lobby: a floating stone platform where players wait between rounds
---------------------------------------------------------------------------
local function buildLobby(parent: Instance)
	local lobby = folder("Lobby", parent)
	makePart({
		Name = "Platform",
		Size = Vector3.new(60, 2, 60),
		Position = LOBBY_POSITION,
		Color = COLORS.Stone[1],
		Material = Enum.Material.Slate,
	}, lobby)
	for i, w in
		{
			{ Vector3.new(0, 6, 31), Vector3.new(64, 12, 2) },
			{ Vector3.new(0, 6, -31), Vector3.new(64, 12, 2) },
			{ Vector3.new(31, 6, 0), Vector3.new(2, 12, 64) },
			{ Vector3.new(-31, 6, 0), Vector3.new(2, 12, 64) },
		}
	do
		makePart({
			Name = "LobbyWall" .. i,
			Size = w[2],
			Position = LOBBY_POSITION + w[1],
			Color = COLORS.Stone[2],
			Material = Enum.Material.Cobblestone,
			Transparency = 0.6,
		}, lobby)
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.Position = LOBBY_POSITION + Vector3.new(0, 1.5, 0)
	spawn.Color = COLORS.Moss[1]
	spawn.Material = Enum.Material.Grass
	spawn.Neutral = true
	spawn.AllowTeamChangeOnTouch = false
	spawn.Duration = 0
	spawn.Parent = lobby
end

---------------------------------------------------------------------------
-- Lighting: soft sun + light fog (Atmosphere) so long shots are hard but fair
---------------------------------------------------------------------------
local function setupLighting()
	Lighting.ClockTime = 15
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(70, 80, 70)
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 135, 120)
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.GlobalShadows = true

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.34 -- raise for thicker fog, lower for clearer view
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(196, 214, 196)
	atmosphere.Decay = Color3.fromRGB(104, 126, 104)
	atmosphere.Glare = 0
	atmosphere.Haze = 1.6
	atmosphere.Parent = Lighting

	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.05
	cc.Contrast = 0.03
	cc.TintColor = Color3.fromRGB(246, 255, 244)
	cc.Parent = Lighting
end

---------------------------------------------------------------------------
-- Middle zone: grass, bushes, rocks, logs, trees and stone ruins
---------------------------------------------------------------------------
local function buildMiddle(parent: Instance)
	local middle = folder("MiddleZone", parent)

	-- Ruins: one in the center, the rest mirrored
	ruin(0, 0, 15, middle)
	mirrored(-70, 45, function(x, z, yaw)
		ruin(x, z, yaw, middle)
	end)
	mirrored(-38, -88, function(x, z, yaw)
		ruin(x, z, yaw, middle)
	end)

	-- Everything below is generated for the Green half (x < 0) and mirrored.
	local function randomHalfPoint(minX: number, maxX: number): (number, number)
		return rng:NextNumber(minX, maxX), rng:NextNumber(-HALF_WIDTH + 15, HALF_WIDTH - 15)
	end

	for _ = 1, 26 do
		local x, z = randomHalfPoint(-150, -5)
		local r = rng:NextNumber(5, 9)
		mirrored(x, z, function(mx, mz)
			tallGrassPatch(mx, mz, r, middle)
		end)
	end
	for _ = 1, 22 do
		local x, z = randomHalfPoint(-150, -5)
		mirrored(x, z, function(mx, mz)
			bush(mx, mz, middle)
		end)
	end
	for _ = 1, 14 do
		local x, z = randomHalfPoint(-150, -5)
		local s = rng:NextNumber(3, 6)
		mirrored(x, z, function(mx, mz)
			rock(mx, mz, s, middle)
		end)
	end
	for _ = 1, 6 do
		local x, z = randomHalfPoint(-150, -10)
		mirrored(x, z, function(mx, mz, yaw)
			fallenLog(mx, mz, yaw, middle)
		end)
	end
	for _ = 1, 12 do
		local x, z = randomHalfPoint(-160, -15)
		mirrored(x, z, function(mx, mz)
			tree(mx, mz, middle)
		end)
	end

	-- Trees on the hills behind each house
	for _ = 1, 10 do
		local x, z = rng:NextNumber(-250, -222), rng:NextNumber(-120, 120)
		mirrored(x, z, function(mx, mz)
			tree(mx, mz, middle)
		end)
	end
end

---------------------------------------------------------------------------
-- Reads house centers, crates and grass patches from the Map folder.
---------------------------------------------------------------------------
local function readInfo()
	local info = MapBuilder.Info
	table.clear(info.Houses)
	table.clear(info.GrassPatches)

	for _, marker in mapFolder:GetDescendants() do
		if marker:IsA("BasePart") then
			if marker.Name == "GrassPatch" then
				table.insert(info.GrassPatches, {
					Position = marker.Position,
					Radius = marker:GetAttribute("Radius") or 6,
				})
			elseif marker.Name == "HouseCenter" then
				local teamKey = marker:GetAttribute("Team")
				info.Houses[teamKey] = info.Houses[teamKey] or {}
				info.Houses[teamKey].Center = marker.Position
			elseif marker.Name == "SupplyCrate" then
				local teamKey = marker:GetAttribute("Team")
				info.Houses[teamKey] = info.Houses[teamKey] or {}
				info.Houses[teamKey].Crate = marker
			end
		end
	end
end

---------------------------------------------------------------------------
-- Public: build everything (call once when the server starts)
---------------------------------------------------------------------------
-- Things from a default Studio template that would get in the way.
-- This only happens while the game runs; your saved place is not changed.
local function cleanUpTemplate()
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate:Destroy()
		print("[MapBuilder] Removed the template Baseplate for this session (delete it in Studio to silence this).")
	end
	for _, d in workspace:GetDescendants() do
		if d:IsA("SpawnLocation") and not d:IsDescendantOf(mapFolder) then
			d.Enabled = false -- only our lobby and ruin-house spawns are used
		end
	end
end

function MapBuilder.Build()
	setupLighting()
	groundParams.FilterDescendantsInstances = { workspace.Terrain }

	local existing = workspace:FindFirstChild("Map")
	if existing and existing:IsA("Folder") then
		-- A saved map is already in the place: keep it.
		mapFolder = existing
		if BUILD_TERRAIN_IF_MAP_EXISTS and workspace.Terrain:CountCells() == 0 then
			buildTerrain()
		end
		readInfo()
		cleanUpTemplate()
		return
	end

	-- Teams must exist before SpawnLocations use their TeamColor
	assert(#Teams:GetTeams() > 0, "Create teams (TeamManager.Init) before MapBuilder.Build")

	buildTerrain()

	mapFolder = folder("Map", workspace)
	mapFolder:SetAttribute("Built", true)

	-- Spawn houses: Green on the -X side, doorway facing +X. Brown is mirrored.
	local houses = folder("Houses", mapFolder)
	local markers = folder("Markers", mapFolder)
	for _, def in { { "Green", -HOUSE_X, 1 }, { "Brown", HOUSE_X, -1 } } do
		local teamKey, hx, dir = def[1] :: string, def[2] :: number, def[3] :: number
		ruinHouse(teamKey, hx, dir, houses)
		local center = makePart({
			Name = "HouseCenter",
			Size = Vector3.new(1, 1, 1),
			Position = Vector3.new(hx, HOUSE_FLOOR_Y + 3, 0),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		}, markers)
		center:SetAttribute("Team", teamKey)
	end

	buildMiddle(mapFolder)
	buildBoundaries(mapFolder)
	buildLobby(mapFolder)
	readInfo()
	cleanUpTemplate()

	print(("[MapBuilder] Map built: %d grass patches"):format(#MapBuilder.Info.GrassPatches))
end

-- Is this position inside any tall grass patch?
function MapBuilder.IsInTallGrass(position: Vector3): boolean
	for _, patch in MapBuilder.Info.GrassPatches do
		local offset = position - patch.Position
		if Vector2.new(offset.X, offset.Z).Magnitude <= patch.Radius and math.abs(offset.Y) < 8 then
			return true
		end
	end
	return false
end

-- Finds the ground height under a point (ignores players and props).
function MapBuilder.GroundY(x: number, z: number): number
	return groundY(x, z)
end

return MapBuilder
