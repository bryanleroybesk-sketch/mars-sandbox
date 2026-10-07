--[[
	DamageService  (ModuleScript in ServerScriptService/Services)

	The ONLY place that lowers a player's health. Every rule about who can
	be hurt lives here:
	  * the round must be running and the victim must be alive in it
	  * no friendly fire (unless GameConfig.FRIENDLY_FIRE = true)
	  * spawn protection: no damage for SPAWN_PROTECTION_TIME while the
	    victim is inside their own safe zone

	It also remembers who hit whom last, so RoundManager can award the
	kill when a Humanoid dies.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local RoundState = require(script.Parent.RoundState)
local SafeZoneService = require(script.Parent.SafeZoneService)
local TeamManager = require(script.Parent.TeamManager)

local DamageService = {}

export type HitInfo = {
	Attacker: Player?,
	Headshot: boolean,
	Time: number,
}

local lastHit: { [Player]: HitInfo } = {}

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

function DamageService.IsSpawnProtected(player: Player): boolean
	return RoundState.TimeIntoRound() < GameConfig.SPAWN_PROTECTION_TIME and SafeZoneService.IsInOwnSafeZone(player)
end

-- Deals damage from one player to another. Returns (damageApplied, killed).
function DamageService.ApplyDamage(victim: Player, amount: number, attacker: Player?, headshot: boolean): (boolean, boolean)
	if not RoundState.IsRoundActive() or not RoundState.IsAlive(victim) then
		return false, false
	end
	if attacker then
		if attacker == victim or not RoundState.IsAlive(attacker) then
			return false, false
		end
		if not GameConfig.FRIENDLY_FIRE and not TeamManager.AreEnemies(attacker, victim) then
			return false, false
		end
	end
	if DamageService.IsSpawnProtected(victim) then
		return false, false
	end

	local humanoid = getHumanoid(victim)
	if not humanoid then
		return false, false
	end

	lastHit[victim] = { Attacker = attacker, Headshot = headshot, Time = os.clock() }
	humanoid.Health = math.max(0, humanoid.Health - amount)
	return true, humanoid.Health <= 0
end

-- Damage from standing in the enemy spawn (no attacker).
function DamageService.ApplyZoneDamage(victim: Player, amount: number)
	DamageService.ApplyDamage(victim, amount, nil, false)
end

-- Heals without going over MaxHealth (used by the Bandage).
function DamageService.Heal(player: Player, amount: number)
	local humanoid = getHumanoid(player)
	if humanoid then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
	end
end

-- Who hit this player last (within the last 15 seconds)?
function DamageService.GetLastHit(victim: Player): HitInfo?
	local hit = lastHit[victim]
	if hit and os.clock() - hit.Time <= 15 then
		return hit
	end
	return nil
end

function DamageService.Reset()
	table.clear(lastHit)
end

return DamageService
