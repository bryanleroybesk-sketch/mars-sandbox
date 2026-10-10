--[[
	SoundUtil  (ModuleScript in ReplicatedStorage/Shared)

	Tiny helpers to play one-shot sounds. Works on server or client.
	  PlayAt(position, soundId, options)  -> 3D sound in the world
	  Play2D(soundId, volume)             -> UI sound, no position
]]

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local SoundUtil = {}

export type SoundOptions = {
	Volume: number?,
	MaxDistance: number?, -- how far away it can be heard
	MinDistance: number?, -- full volume inside this distance
	PlaybackSpeed: number?,
	Lifetime: number?,
}

function SoundUtil.PlayAt(position: Vector3, soundId: string, options: SoundOptions?): Sound?
	if not soundId or soundId == "" then
		return nil
	end
	local opts: SoundOptions = options or {}

	-- An Attachment on Terrain is the cheapest way to give a sound a position.
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = opts.Volume or 1
	sound.PlaybackSpeed = opts.PlaybackSpeed or 1
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = opts.MinDistance or 10
	sound.RollOffMaxDistance = opts.MaxDistance or 100
	sound.Parent = attachment
	sound:Play()

	Debris:AddItem(attachment, opts.Lifetime or 6)
	return sound
end

function SoundUtil.Play2D(soundId: string, volume: number?)
	if not soundId or soundId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.5
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 6)
end

return SoundUtil
