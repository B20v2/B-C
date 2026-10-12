--[[
	Grid
	World layout shared by client and server:

	  * the central battlefield (round continent at Config.MainlandOrigin)
	  * eight nation islands on a ring around it, each rotated so its front
	    edge (local -Z) faces the centre
	  * a bridge from every island's front edge to the battlefield

	Buildings are stored in island-local studs (x, z) plus a yaw in degrees,
	so placement is free-form; Grid only converts between spaces and answers
	"where is this point?" questions.
]]

local Config = require(script.Parent.Parent.Config)

local Grid = {}

Grid.CellSize = Config.CellSize
Grid.PlotSize = Config.PlotSize
Grid.Rim = 34 -- sand beach around each island

local CENTER = Config.MainlandOrigin
local RING = Config.PlotRingRadius
local frames: { [number]: CFrame } = {}

-- Yaw of island `index` around the centre (radians).
function Grid.plotAngle(index: number): number
	return (index - 1) * math.pi / 4
end

-- Unit vector from the centre towards island `index`.
function Grid.direction(index: number): Vector3
	local a = Grid.plotAngle(index)
	return Vector3.new(math.sin(a), 0, math.cos(a))
end

function Grid.plotOrigin(index: number): Vector3
	return CENTER + Grid.direction(index) * RING
end

-- Island frame: origin at its centre, LookVector (-Z) pointing at the battlefield.
function Grid.plotCFrame(index: number): CFrame
	local cf = frames[index]
	if not cf then
		cf = CFrame.new(Grid.plotOrigin(index)) * CFrame.Angles(0, Grid.plotAngle(index), 0)
		frames[index] = cf
	end
	return cf
end

-- Island-local (x, z, yaw degrees) -> world CFrame at ground level.
function Grid.toWorld(index: number, x: number, z: number, angle: number?): CFrame
	return Grid.plotCFrame(index) * CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(angle or 0), 0)
end

-- World position -> island-local position (Y is kept as-is).
function Grid.toLocal(index: number, world: Vector3): Vector3
	return Grid.plotCFrame(index):PointToObjectSpace(world)
end

-- World yaw (degrees) -> island-local yaw.
function Grid.localYaw(index: number, worldYaw: number): number
	return (worldYaw - math.deg(Grid.plotAngle(index))) % 360
end

function Grid.insidePlot(index: number, pos: Vector3, margin: number?): boolean
	local l = Grid.toLocal(index, pos)
	local half = Grid.PlotSize / 2 + (margin or 0)
	return math.abs(l.X) <= half and math.abs(l.Z) <= half
end

-- Which island contains `pos` (the beach counts when margin is given)?
function Grid.plotAt(pos: Vector3, margin: number?): number?
	for i = 1, Config.MaxPlots do
		if Grid.insidePlot(i, pos, margin) then
			return i
		end
	end
	return nil
end

-- Island end of the bridge (outer edge of the beach, centre of the front).
function Grid.gate(index: number): Vector3
	return (Grid.plotCFrame(index) * CFrame.new(0, 0, -(Grid.PlotSize / 2 + Grid.Rim))).Position
end

-- Inside the front edge of the island: where vehicles gather before crossing.
function Grid.yard(index: number): Vector3
	return (Grid.plotCFrame(index) * CFrame.new(0, 0, -(Grid.PlotSize / 2 - 26))).Position
end

-- Battlefield end of the bridge (on the shore).
function Grid.shore(index: number): Vector3
	return CENTER + Grid.direction(index) * Config.MainlandRadius
end

-- Staging area just inland from the bridge on the battlefield.
function Grid.landing(index: number): Vector3
	return CENTER + Grid.direction(index) * (Config.MainlandRadius - 90)
end

local function flat(p: Vector3): Vector3
	return Vector3.new(p.X, 0, p.Z)
end

function Grid.inMainland(pos: Vector3, margin: number?): boolean
	return (flat(pos) - flat(CENTER)).Magnitude <= Config.MainlandRadius + (margin or 0)
end

-- Index of the bridge whose deck contains `pos`.
function Grid.bridgeAt(pos: Vector3): number?
	local p = flat(pos)
	for i = 1, Config.MaxPlots do
		local a, b = flat(Grid.shore(i)), flat(Grid.gate(i))
		local ab = b - a
		local t = (p - a):Dot(ab) / ab:Dot(ab)
		if t >= -0.05 and t <= 1.05 then
			local closest = a + ab * math.clamp(t, 0, 1)
			if (p - closest).Magnitude <= Config.BridgeWidth / 2 + 4 then
				return i
			end
		end
	end
	return nil
end

-- "plot" (index), "bridge" (index), "mainland" or "sea".
function Grid.zoneAt(pos: Vector3): (string, number?)
	local plot = Grid.plotAt(pos, 2)
	if plot then
		return "plot", plot
	end
	if Grid.inMainland(pos) then
		return "mainland", nil
	end
	local bridge = Grid.bridgeAt(pos)
	if bridge then
		return "bridge", bridge
	end
	local beach = Grid.plotAt(pos, Grid.Rim)
	if beach then
		return "plot", beach
	end
	return "sea", nil
end

-- GRID snap: put a footprint's edges on the cell grid (quarter-turn yaws).
function Grid.snapLocal(x: number, z: number, w: number, d: number, angle: number): (number, number)
	local quarter = math.floor(angle / 90 + 0.5) % 2
	local fw, fd = w, d
	if quarter == 1 then
		fw, fd = d, w
	end
	local cell = Grid.CellSize
	local function snap(v: number, size: number): number
		local min = math.floor((v - size / 2) / cell + 0.5) * cell
		return min + size / 2
	end
	return snap(x, fw), snap(z, fd)
end

return Grid
