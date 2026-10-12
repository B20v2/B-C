--[[
	Footprint
	Rotated rectangles on an island (local studs) for free-form building:
	overlap tests (separating axes), "is it on my land", road reach and a
	spatial hash so a city of hundreds of buildings checks in microseconds.
	Shared so the placement ghost and server validation always agree.
]]

local Config = require(script.Parent.Parent.Config)

local Footprint = {}

-- Centre (x, z), half extents and the yaw's cos/sin. Local X axis = (c, -s),
-- local Z axis = (s, c), matching CFrame.Angles(0, yaw, 0).
export type Rect = { x: number, z: number, hw: number, hd: number, c: number, s: number }

function Footprint.rect(x: number, z: number, w: number, d: number, angle: number): Rect
	local a = math.rad(angle)
	return { x = x, z = z, hw = w / 2, hd = d / 2, c = math.cos(a), s = math.sin(a) }
end

-- Footprint size (studs) of a catalog building; roads use their segment length.
function Footprint.size(def: any, len: number?): (number, number)
	local cell = Config.CellSize
	return def.size[1] * cell, len or def.size[2] * cell
end

function Footprint.corners(r: Rect): { Vector2 }
	local out = {}
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local lx, lz = sx * r.hw, sz * r.hd
			table.insert(out, Vector2.new(r.x + lx * r.c + lz * r.s, r.z - lx * r.s + lz * r.c))
		end
	end
	return out
end

-- World-axis bounds (local island axes).
function Footprint.bounds(r: Rect): (number, number, number, number)
	local ex = math.abs(r.hw * r.c) + math.abs(r.hd * r.s)
	local ez = math.abs(r.hw * r.s) + math.abs(r.hd * r.c)
	return r.x - ex, r.z - ez, r.x + ex, r.z + ez
end

local function radius(r: Rect, ax: number, az: number): number
	return r.hw * math.abs(r.c * ax - r.s * az) + r.hd * math.abs(r.s * ax + r.c * az)
end

-- True when the rectangles overlap by more than `gap` studs (touching is fine).
function Footprint.overlaps(a: Rect, b: Rect, gap: number?): boolean
	local g = gap or 0.05
	local dx, dz = b.x - a.x, b.z - a.z
	for _, axis in { { a.c, -a.s }, { a.s, a.c }, { b.c, -b.s }, { b.s, b.c } } do
		local ax, az = axis[1], axis[2]
		local dist = math.abs(dx * ax + dz * az)
		if dist >= radius(a, ax, az) + radius(b, ax, az) - g then
			return false
		end
	end
	return true
end

-- Every corner within +-half of the island centre.
function Footprint.inside(r: Rect, half: number): boolean
	local x0, z0, x1, z1 = Footprint.bounds(r)
	return x0 >= -half and z0 >= -half and x1 <= half and z1 <= half
end

-- Grow a rectangle on every side (road reach checks).
function Footprint.grow(r: Rect, by: number): Rect
	return { x = r.x, z = r.z, hw = r.hw + by, hd = r.hd + by, c = r.c, s = r.s }
end

-- Point-in-rectangle (local studs).
function Footprint.contains(r: Rect, x: number, z: number, pad: number?): boolean
	local dx, dz = x - r.x, z - r.z
	local lx = dx * r.c - dz * r.s
	local lz = dx * r.s + dz * r.c
	local p = pad or 0
	return math.abs(lx) <= r.hw + p and math.abs(lz) <= r.hd + p
end

-- A road segment from A to B: centre, yaw (local Z runs A -> B) and length.
function Footprint.segment(ax: number, az: number, bx: number, bz: number): (number, number, number, number)
	local dx, dz = bx - ax, bz - az
	local len = math.sqrt(dx * dx + dz * dz)
	local angle = math.deg(math.atan2(dx, dz)) % 360
	return (ax + bx) / 2, (az + bz) / 2, angle, len
end

-- A road segment's rectangle including its round end caps (half a width
-- past each end), used when checking buildings against roads. Single tiles
-- (no longer than they are wide) are square and have no caps.
function Footprint.capped(r: Rect): Rect
	if r.hd <= r.hw + 0.005 then
		return r
	end
	return { x = r.x, z = r.z, hw = r.hw, hd = r.hd + r.hw, c = r.c, s = r.s }
end

-- Endpoints of a segment rectangle (along its local Z).
function Footprint.ends(r: Rect): (Vector2, Vector2)
	local ox, oz = r.hd * r.s, r.hd * r.c
	return Vector2.new(r.x - ox, r.z - oz), Vector2.new(r.x + ox, r.z + oz)
end

---------------------------------------------------------------------------
-- Spatial hash: bucket -> set of ids
---------------------------------------------------------------------------
local BUCKET = 32

export type Hash = { [number]: { [number]: boolean } }

local function keysFor(r: Rect, pad: number): { number }
	local x0, z0, x1, z1 = Footprint.bounds(r)
	local out = {}
	for bx = math.floor((x0 - pad) / BUCKET), math.floor((x1 + pad) / BUCKET) do
		for bz = math.floor((z0 - pad) / BUCKET), math.floor((z1 + pad) / BUCKET) do
			table.insert(out, (bx + 512) * 1024 + (bz + 512))
		end
	end
	return out
end

function Footprint.hashAdd(h: Hash, id: number, r: Rect)
	for _, k in keysFor(r, 0) do
		local set = h[k]
		if not set then
			set = {}
			h[k] = set
		end
		set[id] = true
	end
end

function Footprint.hashRemove(h: Hash, id: number, r: Rect)
	for _, k in keysFor(r, 0) do
		local set = h[k]
		if set then
			set[id] = nil
			if next(set) == nil then
				h[k] = nil
			end
		end
	end
end

-- Ids whose buckets touch `r` grown by `pad` (candidates; test them exactly).
function Footprint.hashQuery(h: Hash, r: Rect, pad: number?): { [number]: boolean }
	local out = {}
	for _, k in keysFor(r, pad or 0) do
		local set = h[k]
		if set then
			for id in set do
				out[id] = true
			end
		end
	end
	return out
end

return Footprint
