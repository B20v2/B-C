--!nocheck
--[[
	export_parts.luau
	Dumps the procedural (part-built) models from ModelBuilder to JSON so
	blender/render_parts.py can render preview sheets of what players see
	before the Blender kit is imported.

	  lune run tools/export_parts.luau build/ForgeAndFrontline.rbxlx out.json [filter]

	filter (optional): only models whose name contains this text.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local function bbox(model)
	local lo, hi
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local cf, h = d.CFrame, d.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local w = cf:PointToWorldSpace(Vector3.new(h.X * sx, h.Y * sy, h.Z * sz))
						lo = lo and Vector3.new(math.min(lo.X, w.X), math.min(lo.Y, w.Y), math.min(lo.Z, w.Z)) or w
						hi = hi and Vector3.new(math.max(hi.X, w.X), math.max(hi.Y, w.Y), math.max(hi.Z, w.Z)) or w
					end
				end
			end
		end
	end
	return lo or Vector3.zero, hi or Vector3.zero
end
roblox.implementMethod("Model", "GetPivot", function(self)
	if self.PrimaryPart then
		return self.PrimaryPart.CFrame
	end
	local lo, hi = bbox(self)
	return CFrame.new((lo + hi) / 2)
end)
roblox.implementMethod("Model", "PivotTo", function(self, cf)
	local delta = cf * self:GetPivot():Inverse()
	for _, d in self:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
end)
roblox.implementMethod("Model", "TranslateBy", function(self, v)
	for _, d in self:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = d.CFrame + v
		end
	end
end)
roblox.implementMethod("Model", "GetBoundingBox", function(self)
	local lo, hi = bbox(self)
	return CFrame.new((lo + hi) / 2), hi - lo
end)
roblox.implementMethod("Model", "ScaleTo", function() end)

local Random = {}
Random.__index = Random
function Random.new(seed)
	return setmetatable({ s = (seed or 12345) % 2147483647 + 1 }, Random)
end
function Random:_n()
	self.s = (self.s * 16807) % 2147483647
	return self.s / 2147483647
end
function Random:NextNumber(a, b)
	a, b = a or 0, b or 1
	return a + (b - a) * self:_n()
end
function Random:NextInteger(a, b)
	return math.floor(a + (b - a + 1) * self:_n())
end

local game = roblox.deserializePlace(fs.readFile(process.args[1]))
local cache = {}
local env = {
	Instance = roblox.Instance, Vector3 = Vector3, Vector2 = roblox.Vector2, CFrame = CFrame,
	Color3 = roblox.Color3, UDim2 = roblox.UDim2, UDim = roblox.UDim, Enum = roblox.Enum, Font = roblox.Font,
	NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	ColorSequence = roblox.ColorSequence, ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberRange = roblox.NumberRange, Random = Random, typeof = typeof, task = require("@lune/task"), warn = print,
	game = game, workspace = game:FindFirstChildOfClass("Workspace"),
}
local function req(module)
	local key = module:GetFullName()
	if cache[key] then
		return cache[key]
	end
	local e = { script = module, require = req }
	for k, v in env do
		e[k] = v
	end
	local result = luau.load(module.Source, { debugName = key, environment = e })()
	cache[key] = result
	return result
end

local Shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
local function mod(path)
	local inst = Shared
	for part in path:gmatch("[^%.]+") do
		inst = inst:FindFirstChild(part)
	end
	return req(inst)
end

local ModelBuilder = mod("ModelBuilder")
local Buildings = mod("Catalog.Buildings")
local Units = mod("Catalog.Units")

local filter = process.args[3]
local out = {}

local function dump(name: string, group: string, model)
	if filter and not string.find(name, filter, 1, true) then
		return
	end
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.98 then
			local cf = d.CFrame
			local comps = { cf:GetComponents() }
			local shape = "Block"
			if d:IsA("Part") then
				shape = d.Shape.Name
			elseif d:IsA("WedgePart") then
				shape = "Wedge"
			end
			local mesh = d:FindFirstChildOfClass("SpecialMesh")
			local c = d.Color
			table.insert(parts, {
				n = d.Name,
				shape = shape,
				mesh = mesh and mesh.MeshType.Name or nil,
				meshScale = mesh and { mesh.Scale.X, mesh.Scale.Y, mesh.Scale.Z } or nil,
				size = { d.Size.X, d.Size.Y, d.Size.Z },
				cf = comps,
				color = { c.R, c.G, c.B },
				mat = d.Material.Name,
				t = d.Transparency,
			})
		end
	end
	table.insert(out, { name = name, group = group, parts = parts })
end

for _, def in Buildings.all() do
	dump(def.id, "Buildings", ModelBuilder.building(def))
end
for _, def in Units.all() do
	dump("unit_" .. def.id, "Units", ModelBuilder.unit(def))
end
dump("road_segment", "Buildings", ModelBuilder.roadSegment(8, 40, 0))
if ModelBuilder.extras then
	for name, fn in ModelBuilder.extras() do
		dump(name, "Extras", fn())
	end
end

fs.writeFile(process.args[2], serde.encode("json", out))
print(("exported %d models"):format(#out))
