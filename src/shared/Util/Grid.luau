--[[
	Grid
	Plot layout and cell <-> world conversion. Shared so the client placement
	ghost and the server validation always agree.
]]

local Config = require(script.Parent.Parent.Config)

local Grid = {}

local CELL = Config.CellSize
local N = Config.PlotCells

Grid.CellSize = CELL
Grid.PlotCells = N
Grid.PlotSize = N * CELL

-- World-space center of plot `index` (1-based) at ground height.
function Grid.plotOrigin(index: number): Vector3
	local i = index - 1
	local row = i // Config.PlotRowLength
	local col = i % Config.PlotRowLength
	local pitch = Grid.PlotSize + Config.PlotGap
	local width = (Config.PlotRowLength - 1) * pitch
	return Config.HomelandOrigin + Vector3.new(col * pitch - width / 2, 0, row * pitch)
end

-- Footprint (in cells) after rotation. r = number of quarter turns.
function Grid.footprint(w: number, d: number, r: number): (number, number)
	if r % 2 == 1 then
		return d, w
	end
	return w, d
end

-- Center of a footprint whose min corner is at cell (x, z).
function Grid.cellToWorld(origin: Vector3, x: number, z: number, fw: number, fd: number): Vector3
	return origin + Vector3.new((x + fw / 2 - N / 2) * CELL, 0, (z + fd / 2 - N / 2) * CELL)
end

function Grid.cframeFor(origin: Vector3, x: number, z: number, w: number, d: number, r: number): CFrame
	local fw, fd = Grid.footprint(w, d, r)
	local pos = Grid.cellToWorld(origin, x, z, fw, fd)
	return CFrame.new(pos) * CFrame.Angles(0, math.rad(90 * r), 0)
end

-- Min corner cell for a footprint centered as close as possible to `world`.
function Grid.worldToCell(origin: Vector3, world: Vector3, fw: number, fd: number): (number, number)
	local local_ = world - origin
	local x = math.floor(local_.X / CELL + N / 2 - fw / 2 + 0.5)
	local z = math.floor(local_.Z / CELL + N / 2 - fd / 2 + 0.5)
	return x, z
end

function Grid.inBounds(x: number, z: number, fw: number, fd: number): boolean
	return x >= 0 and z >= 0 and x + fw <= N and z + fd <= N
end

function Grid.key(x: number, z: number): number
	return z * N + x
end

-- Is a world position inside the plot centered at origin (with optional margin)?
function Grid.insidePlot(origin: Vector3, pos: Vector3, margin: number?): boolean
	local half = Grid.PlotSize / 2 + (margin or 0)
	local d = pos - origin
	return math.abs(d.X) <= half and math.abs(d.Z) <= half
end

return Grid
