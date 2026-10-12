--[[
	Ballistics
	Deterministic flight paths so the server (interception timing) and every
	client (visuals) agree on where a projectile is at any moment.
]]

local Ballistics = {}

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

-- Position at progress alpha (0..1).
function Ballistics.position(from: Vector3, to: Vector3, apex: number, kind: string, alpha: number): Vector3
	alpha = math.clamp(alpha, 0, 1)
	local flat = from:Lerp(to, alpha)
	local height: number
	if kind == "drone" or apex < 60 then
		-- climb quickly, cruise, then dive onto the target
		local climb = math.min(1, alpha / 0.12)
		local dive = alpha > 0.85 and (1 - (alpha - 0.85) / 0.15) or 1
		height = apex * smooth(climb) * smooth(math.clamp(dive, 0, 1))
	else
		height = 4 * apex * alpha * (1 - alpha)
	end
	return flat + Vector3.new(0, height, 0)
end

function Ballistics.cframe(from: Vector3, to: Vector3, apex: number, kind: string, alpha: number): CFrame
	local p0 = Ballistics.position(from, to, apex, kind, alpha)
	local p1 = Ballistics.position(from, to, apex, kind, math.min(1, alpha + 0.01))
	if (p1 - p0).Magnitude < 1e-3 then
		p1 = p0 + (to - from).Unit
	end
	return CFrame.lookAt(p0, p1)
end

return Ballistics
