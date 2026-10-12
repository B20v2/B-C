--[[
	AssetLibrary
	Loads the Blender-made model kit (assets/FF_*.fbx imported into
	ReplicatedStorage.Assets) and turns each asset into a ready-to-use
	template:

	  * meshes are grouped by asset name ("small_house__Body" -> small_house)
	  * scaled to the exact footprint / vehicle length the game expects
	  * rotated so footprints line up and vehicles face -Z (via "Front")
	  * animated parts (Rotor / Beam / Dish) get pivots from the "Spin" marker
	  * "Lights" meshes get a neon twin that the day/night cycle switches on
	  * an invisible Base (footprint) and Hitbox (collision) are added

	When an asset isn't in the kit, ModelBuilder falls back to its
	procedural part-built model, so the game always works.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetLibrary = {}

type Entry = { parts: { BasePart } }

local index: { [string]: Entry }? = nil
local templates: { [string]: Model | false } = {}

local MARKERS = { Front = true, Spin = true }
local GLOW = Color3.fromRGB(255, 214, 150)

local function partKind(name: string): string
	for _, kind in { "Body", "Lights", "Rotor", "Beam", "Dish", "Board", "Front", "Spin" } do
		if string.sub(name, 1, #kind) == kind then
			return kind
		end
	end
	return "Body"
end

local function buildIndex(): { [string]: Entry }
	local idx: { [string]: Entry } = {}
	local folder = ReplicatedStorage:FindFirstChild("Assets")
	if folder then
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") then
				local asset, part = string.match(d.Name, "^(.-)__(.+)$")
				if asset and part then
					local e = idx[asset]
					if not e then
						e = { parts = {} }
						idx[asset] = e
					end
					table.insert(e.parts, d)
				end
			end
		end
	end
	return idx
end

local function getIndex(): { [string]: Entry }
	local idx = index
	if not idx then
		idx = buildIndex()
		index = idx
	end
	return idx
end

function AssetLibrary.has(name: string): boolean
	return getIndex()[name] ~= nil
end

function AssetLibrary.count(): number
	local n = 0
	for _ in getIndex() do
		n += 1
	end
	return n
end

-- Re-scan (call after importing assets at runtime in Studio).
function AssetLibrary.refresh()
	index = nil
	table.clear(templates)
end

local function bounds(parts: { BasePart }): (Vector3, Vector3)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, p in parts do
		local cf, size = p.CFrame, p.Size
		for _, sx in { -0.5, 0.5 } do
			for _, sy in { -0.5, 0.5 } do
				for _, sz in { -0.5, 0.5 } do
					local w = cf:PointToWorldSpace(size * Vector3.new(sx, sy, sz))
					lo = lo:Min(w)
					hi = hi:Max(w)
				end
			end
		end
	end
	return lo, hi
end

local function invisiblePart(name: string, size: Vector3, cf: CFrame, collide: boolean): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Transparency = 1
	p.CanCollide = collide
	p.CanTouch = false
	p.CanQuery = name == "Base"
	p.CastShadow = false
	return p
end

-- opts: { width, depth } for footprints, or { length } for vehicles/props.
local function prepare(name: string, opts: { [string]: any }): Model?
	local entry = getIndex()[name]
	if not entry then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = name
	local clones: { BasePart } = {}
	local markers: { [string]: Vector3 } = {}
	for _, src in entry.parts do
		local kind = partKind(string.match(src.Name, "__(.+)$") or "Body")
		if MARKERS[kind] then
			markers[kind] = src.CFrame.Position
		else
			local c = src:Clone()
			c.Anchored = true
			c.CanTouch = false
			c:SetAttribute("Kind", kind)
			c.Parent = model
			table.insert(clones, c)
		end
	end
	if #clones == 0 then
		return nil
	end

	-- 1) normalise rotation
	local lo, hi = bounds(clones)
	local center = (lo + hi) / 2
	local rot = CFrame.new()
	local front = markers.Front
	if front then
		local dir = Vector3.new(front.X - center.X, 0, front.Z - center.Z)
		if dir.Magnitude > 1e-3 then
			local yaw = math.atan2(dir.X, dir.Z) -- angle from +Z
			rot = CFrame.Angles(0, math.pi - yaw, 0) -- turn so front points to -Z
		end
	elseif opts.width and opts.depth and math.abs(opts.width - opts.depth) > 0.5 then
		local ext = hi - lo
		local wantWide = opts.width > opts.depth
		if (ext.X > ext.Z) ~= wantWide then
			rot = CFrame.Angles(0, math.rad(90), 0)
		end
	end
	local pivot = CFrame.new(center.X, lo.Y, center.Z)
	local function remap(cf: CFrame): CFrame
		return rot * (pivot:Inverse() * cf)
	end
	for _, p in clones do
		p.CFrame = remap(p.CFrame)
	end
	for k, v in markers do
		markers[k] = remap(CFrame.new(v)).Position
	end

	-- 2) normalise scale
	lo, hi = bounds(clones)
	local ext = hi - lo
	local scale = 1
	if opts.width and opts.depth then
		scale = math.min((opts.width - 0.1) / math.max(ext.X, 1e-3), (opts.depth - 0.1) / math.max(ext.Z, 1e-3))
	elseif opts.length then
		scale = opts.length / math.max(math.max(ext.X, ext.Z), 1e-3)
	end
	if math.abs(scale - 1) > 1e-3 then
		for _, p in clones do
			local cf = p.CFrame
			p.Size *= scale
			p.CFrame = CFrame.new(cf.Position * scale) * cf.Rotation
		end
		for k, v in markers do
			markers[k] = v * scale
		end
	end
	lo, hi = bounds(clones)
	-- sit on the ground, centred
	local shift = Vector3.new(-(lo.X + hi.X) / 2, -lo.Y, -(lo.Z + hi.Z) / 2)
	for _, p in clones do
		p.CFrame += shift
	end
	for k, v in markers do
		markers[k] = v + shift
	end
	ext = hi - lo

	-- 3) structure: Base, Hitbox, animated sub-models, night lights, board
	local w = opts.width or ext.X
	local d = opts.depth or ext.Z
	local base = invisiblePart("Base", Vector3.new(w - 0.2, 0.4, d - 0.2), CFrame.new(0, 0.2, 0), false)
	base.Parent = model
	model.PrimaryPart = base
	if opts.hitbox then
		local hit = invisiblePart("Hitbox", Vector3.new(ext.X * 0.92, ext.Y * 0.95, ext.Z * 0.92), CFrame.new(0, ext.Y * 0.95 / 2, 0), true)
		hit.Parent = model
	end
	for _, p in clones do
		local kind = p:GetAttribute("Kind")
		p.CanCollide = false
		if kind == "Rotor" or kind == "Beam" or kind == "Dish" then
			local sub = Instance.new("Model")
			sub.Name = kind
			-- keep the authored axes so Rotor spins / Beam rocks the right way after normalising
			local pv = invisiblePart("Pivot", Vector3.one * 0.2, CFrame.new(markers.Spin or p.CFrame.Position) * rot, false)
			pv.Parent = sub
			sub.PrimaryPart = pv
			p.Parent = sub
			if kind == "Rotor" then
				sub:SetAttribute("Spin", 1.6)
				sub:SetAttribute("SpinAxis", "Z")
			elseif kind == "Dish" then
				sub:SetAttribute("Spin", 1.2)
				sub:SetAttribute("SpinAxis", "Y")
			else
				sub:SetAttribute("Rock", math.rad(16))
			end
			sub.Parent = model
		elseif kind == "Lights" then
			p:SetAttribute("NightLight", true)
			local glow = p:Clone()
			glow.Name = "LightsGlow"
			for _, c in glow:GetChildren() do
				c:Destroy() -- drop SurfaceAppearance etc. so neon shows its own colour
			end
			if glow:IsA("MeshPart") then
				glow.TextureID = ""
			end
			glow.Size *= 1.012 -- sits just proud of the facade (no z-fighting)
			glow.Material = Enum.Material.Neon
			glow.Color = GLOW
			glow.Transparency = 1
			glow.CastShadow = false
			glow.CanQuery = false
			glow:SetAttribute("Kind", "LightsGlow")
			glow:SetAttribute("NightGlow", true)
			glow.Parent = model
		elseif kind == "Board" then
			p.Name = "Board"
			for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
				local gui = Instance.new("SurfaceGui")
				gui.Face = face
				gui.CanvasSize = Vector2.new(400, 110)
				gui.LightInfluence = 0.2
				gui.Parent = p
				local label = Instance.new("TextLabel")
				label.Name = "Message"
				label.Size = UDim2.fromScale(1, 1)
				label.BackgroundColor3 = Color3.fromRGB(250, 248, 240)
				label.TextColor3 = Color3.fromRGB(28, 34, 46)
				label.TextScaled = true
				label.FontFace = Font.new("rbxasset://fonts/families/Sarpanch.json", Enum.FontWeight.Bold)
				label.Text = "YOUR AD HERE"
				label.Parent = gui
			end
		end
	end
	model:SetAttribute("FromKit", true)
	return model
end

-- Returns a fresh clone of the normalised asset, or nil when not imported.
function AssetLibrary.instantiate(name: string, opts: { [string]: any }?): Model?
	local o = opts or {}
	local key = name .. "|" .. tostring(o.width) .. "|" .. tostring(o.depth) .. "|" .. tostring(o.length) .. "|" .. tostring(o.hitbox)
	local t = templates[key]
	if t == nil then
		t = prepare(name, o) or false
		templates[key] = t
	end
	if t then
		return (t :: Model):Clone()
	end
	return nil
end

return AssetLibrary
