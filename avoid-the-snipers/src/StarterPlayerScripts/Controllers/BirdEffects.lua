--[[
	BirdEffects  (ModuleScript in StarterPlayerScripts/Controllers)

	Draws the bird flocks the SERVER announces (BirdSystem decides where
	and when). Each bird is 3 tiny parts (body + 2 wings), created only on
	this client, flies up and away over BIRD_FLIGHT_TIME, then is deleted.
	Very lightweight: one RenderStepped connection per flock.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local SoundUtil = require(ReplicatedStorage.Shared:WaitForChild("SoundUtil"))

local BirdEffects = {}

local BIRD_COLOR = Color3.fromRGB(34, 30, 28)

local function makePart(name: string, size: Vector3, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = BIRD_COLOR
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

type Bird = {
	Body: BasePart,
	LeftWing: BasePart,
	RightWing: BasePart,
	Start: Vector3,
	Finish: Vector3,
	Delay: number,
	FlapSpeed: number,
}

local function spawnFlock(position: Vector3, count: number, kind: string)
	if typeof(position) ~= "Vector3" or typeof(count) ~= "number" then
		return
	end
	count = math.clamp(math.floor(count), 1, 12)

	local folder = Instance.new("Folder")
	folder.Name = "Flock"
	folder.Parent = workspace

	local rng = Random.new()
	-- The whole flock heads roughly the same way
	local heading = rng:NextNumber(0, math.pi * 2)
	local birds: { Bird } = {}
	for _ = 1, count do
		local start = position + Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(0.5, 2), rng:NextNumber(-3, 3))
		local angle = heading + rng:NextNumber(-0.5, 0.5)
		local distance = rng:NextNumber(35, 55)
		table.insert(birds, {
			Body = makePart("Body", Vector3.new(0.35, 0.3, 0.8), folder),
			LeftWing = makePart("Wing", Vector3.new(0.9, 0.06, 0.45), folder),
			RightWing = makePart("Wing", Vector3.new(0.9, 0.06, 0.45), folder),
			Start = start,
			Finish = start + Vector3.new(math.cos(angle) * distance, rng:NextNumber(28, 42), math.sin(angle) * distance),
			Delay = rng:NextNumber(0, 0.35),
			FlapSpeed = rng:NextNumber(22, 30),
		})
	end

	-- Sounds: flapping for small flocks, loud crows for danger flocks
	if kind == "Danger" then
		SoundUtil.PlayAt(position, GameConfig.SOUNDS.CrowCall, { Volume = 1.6, MinDistance = 30, MaxDistance = 350, PlaybackSpeed = 0.6 })
		SoundUtil.PlayAt(position, GameConfig.SOUNDS.BirdFlap, { Volume = 1.2, MinDistance = 20, MaxDistance = 250 })
	elseif kind == "Warning" then
		SoundUtil.PlayAt(position, GameConfig.SOUNDS.BirdFlap, { Volume = 1, MinDistance = 15, MaxDistance = 180 })
	else
		SoundUtil.PlayAt(position, GameConfig.SOUNDS.BirdFlap, { Volume = 0.6, MinDistance = 10, MaxDistance = 90 })
	end

	local duration = GameConfig.BIRD_FLIGHT_TIME
	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		for _, bird in birds do
			local t = math.clamp((elapsed - bird.Delay) / duration, 0, 1)
			-- ease out: fast take-off, slowing as they leave
			local eased = 1 - (1 - t) ^ 2
			local pos = bird.Start:Lerp(bird.Finish, eased)
			local look = CFrame.lookAt(pos, pos + (bird.Finish - bird.Start).Unit)
			local flap = math.sin(elapsed * bird.FlapSpeed) * 0.9
			bird.Body.CFrame = look
			bird.LeftWing.CFrame = look * CFrame.Angles(0, 0, flap) * CFrame.new(-0.55, 0, 0)
			bird.RightWing.CFrame = look * CFrame.Angles(0, 0, -flap) * CFrame.new(0.55, 0, 0)
		end
		if elapsed >= duration + 0.4 then
			connection:Disconnect()
			folder:Destroy()
		end
	end)
end

function BirdEffects.Init()
	Remotes.Get("BirdFlock").OnClientEvent:Connect(spawnFlock)
end

-- Exposed so you can test visuals from the command bar
BirdEffects.SpawnFlock = spawnFlock

return BirdEffects
