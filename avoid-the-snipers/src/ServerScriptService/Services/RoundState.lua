--[[
	RoundState  (ModuleScript in ServerScriptService/Services)

	The server's single source of truth about the current round.
	Only RoundManager WRITES to it. Other services just READ it, e.g.
	DamageService asks "is the round running and is this player alive?".

	Keeping this in its own tiny module avoids modules requiring each
	other in a circle.
]]

local RoundState = {
	-- "Waiting" | "CamoSelect" | "Round" | "Results" | "Intermission"
	Phase = "Waiting",

	-- os.clock() when the fighting part of the round began (0 if not started)
	RoundStartedAt = 0,

	-- Every player taking part this round -> their team key ("Green"/"Brown")
	Participants = {} :: { [Player]: string },

	-- Participants that are still alive -> true
	Alive = {} :: { [Player]: boolean },
}

function RoundState.IsRoundActive(): boolean
	return RoundState.Phase == "Round"
end

function RoundState.IsAlive(player: Player): boolean
	return RoundState.Alive[player] == true
end

-- Seconds since the fighting started (huge number if no round is running).
function RoundState.TimeIntoRound(): number
	if RoundState.Phase ~= "Round" then
		return math.huge
	end
	return os.clock() - RoundState.RoundStartedAt
end

return RoundState
