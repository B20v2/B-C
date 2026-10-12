--!nocheck
-- Dumps the game's catalogs to blender/manifest.json so the Blender kit is
-- generated from the same data the game uses.
--   lune run tools/export_manifest.luau build/ForgeAndFrontline.rbxlx
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local place = roblox.deserializePlace(fs.readFile(process.args[1]))
local Shared = place:FindFirstChildOfClass("ReplicatedStorage"):FindFirstChild("Shared")
local cache = {}
local function load(m)
	local key = m:GetFullName()
	if cache[key] then return cache[key] end
	local env = { script = m, Vector3 = roblox.Vector3, Color3 = roblox.Color3, Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame, Enum = roblox.Enum, UDim2 = roblox.UDim2 }
	env.require = load
	local r = luau.load(m.Source, { debugName = key, environment = env })()
	cache[key] = r
	return r
end
local function mod(path)
	local inst = Shared
	for part in path:gmatch("[^%.]+") do inst = inst:FindFirstChild(part) end
	return load(inst)
end

local Config = mod("Config")
local out = { cellSize = Config.CellSize, buildings = {}, units = {}, weapons = {}, points = {} }
for _, b in mod("Catalog.Buildings").all() do
	table.insert(out.buildings, { id = b.id, name = b.name, model = b.model, w = b.size[1], d = b.size[2],
		params = b.params or {}, category = b.category, tab = b.tab, faction = b.faction })
end
for _, u in mod("Catalog.Units").all() do
	table.insert(out.units, { id = u.id, name = u.name, model = u.model, params = u.params or {}, faction = u.faction })
end
for _, w in mod("Catalog.Weapons").all() do
	table.insert(out.weapons, { id = w.id, name = w.name, kind = w.kind })
end
for _, p in mod("Catalog.WarMap") do
	table.insert(out.points, { id = p.id, name = p.name, model = p.model })
end
fs.writeFile(process.args[2] or "blender/manifest.json", serde.encode("json", out, true))
print(("manifest: %d buildings, %d units, %d weapons, %d points"):format(#out.buildings, #out.units, #out.weapons, #out.points))
