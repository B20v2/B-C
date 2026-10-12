--[[
	Unlocks
	One place that answers "can this player use X?" for buildings, weapons and
	units, used by the build menu (locked badges) and the server (validation).
]]

local Unlocks = {}

export type Access = {
	researched: { [string]: boolean },
	passes: { [string]: boolean },
}

-- Returns ok, reason
function Unlocks.check(def: { research: string?, pass: string? }, access: Access): (boolean, string?)
	if def.pass and not access.passes[def.pass] then
		return false, "Requires pass"
	end
	if def.research and not access.researched[def.research] then
		return false, "Research needed"
	end
	return true, nil
end

return Unlocks
