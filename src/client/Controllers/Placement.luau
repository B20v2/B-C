--[[
	Placement
	Free-form building. Anything goes anywhere on your island, at any angle:

	  place  - LMB places (stays selected for fast building)
	  rotate - R turns 15 deg (Shift+R back), 90 deg in GRID mode
	  snap   - G toggles FREE / GRID (4-stud grid, quarter turns)
	  align  - in FREE mode, buildings near a road turn to face it and sit
	           flush with the kerb (hold Alt to place freely)
	  roads  - click-click (or drag) to draw a road of any length/direction;
	           it keeps going from the last point until you click the same
	           spot twice, right-click or press Q. Ends snap to other roads.
	  drag   - hold and drag to lay a row of the selected building
	  delete - click a building to demolish it (hotkey 2)
	  undo   - hotkey 3
	  move   - click a building, then click its new spot (hotkey 5)
	When nothing is selected, clicking one of your buildings opens its panel.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Buildings = require(Shared.Catalog.Buildings)
local Grid = require(Shared.Util.Grid)
local Footprint = require(Shared.Util.Footprint)
local ModelBuilder = require(Shared.ModelBuilder)
local Net = require(Shared.Net)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Hub = require(Client.Hub)
local Notifications = require(script.Parent.Notifications)
local Sounds = require(script.Parent.Sounds)

local Placement = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local VALID = Color3.fromRGB(80, 220, 120)
local INVALID = Color3.fromRGB(235, 70, 60)
local MOVE = Color3.fromRGB(80, 160, 255)
local ROAD = Color3.fromRGB(255, 180, 54)

local HALF = Grid.PlotSize / 2 - 0.5
local ROAD_SNAP = 7 -- studs: endpoints join existing road ends / centrelines

type Other = { uid: number, rect: Footprint.Rect, ground: boolean, road: boolean }

local selected: any = nil
local tool: string? = nil -- nil | "delete" | "move"
local angle = 0 -- degrees, island-local
local snapMode = "free" -- "free" | "grid"
local dragMode = false
local pointer = Vector2.new(0, 0)

local ghost: Model? = nil
local plate: Part? = nil
local highlight: Highlight? = nil
local hoverHighlight: Highlight
local moving: Model? = nil -- building being moved
local movingLen: number? = nil
local spot: { x: number, z: number, a: number, valid: boolean }? = nil
local dragStart: Vector2? = nil -- local studs (row drag)
local dragTiles: { Part } = {}
local roadAnchor: Vector2? = nil -- start of the road being drawn
local roadPress: Vector2? = nil
local roadPressAnchored = false
local roadPreview: Part? = nil
local roadInfo: { len: number, cost: number, valid: boolean }? = nil
local listeners: { () -> () } = {}

-- client-side copy of the island's footprints (rebuilt from building models)
local others: { [number]: Other } = {}
local hash: Footprint.Hash = {}

local function notifyChanged()
	for _, fn in listeners do
		task.spawn(fn)
	end
end

function Placement.onChanged(fn: () -> ())
	table.insert(listeners, fn)
end

function Placement.state()
	return {
		def = selected,
		tool = tool,
		rotation = angle,
		drag = dragMode,
		moving = moving ~= nil,
		snap = snapMode,
		road = roadInfo,
		drawing = roadAnchor ~= nil,
	}
end

local function plotIndex(): number?
	return ClientState.get("plot")
end

local function buildingsFolder(): Folder?
	local idx = plotIndex()
	if not idx then
		return nil
	end
	local homeland = workspace:FindFirstChild("Homeland")
	local plot = homeland and homeland:FindFirstChild("Plot_" .. idx)
	return plot and plot:FindFirstChild("Buildings") :: Folder? or nil
end

local function isSegment(def): boolean
	return def ~= nil and def.id == "road"
end

local function isGround(def): boolean
	return def ~= nil and (def.id == "road" or def.id == "plaza")
end

local function rectFor(def, x: number, z: number, a: number, len: number?): Footprint.Rect
	local w, d = Footprint.size(def, len)
	return Footprint.rect(x, z, w, d, a)
end

local function rebuildOccupancy()
	table.clear(others)
	table.clear(hash)
	local folder = buildingsFolder()
	if not folder then
		return
	end
	for _, model in folder:GetChildren() do
		if model:IsA("Model") and model ~= moving then
			local def = Buildings.get(model:GetAttribute("BuildingId") :: string)
			local px, pz = model:GetAttribute("PX") :: number?, model:GetAttribute("PZ") :: number?
			local uid = model:GetAttribute("Uid") :: number?
			if def and px and pz and uid then
				local rect = rectFor(def, px, pz, (model:GetAttribute("Angle") :: number?) or 0, model:GetAttribute("Len") :: number?)
				others[uid] = { uid = uid, rect = rect, ground = isGround(def), road = isSegment(def) }
				Footprint.hashAdd(hash, uid, rect)
			end
		end
	end
end

local function canPlaceLocal(def, x: number, z: number, a: number, len: number?): boolean
	local rect = rectFor(def, x, z, a, len)
	if not Footprint.inside(rect, HALF) then
		return false
	end
	local ground = isGround(def)
	-- a road's round end caps count against buildings (same rule as the server)
	local mine = isSegment(def) and Footprint.capped(rect) or rect
	for uid in Footprint.hashQuery(hash, mine) do
		local o = others[uid]
		if o and not (ground and o.ground) then
			local theirs = o.road and Footprint.capped(o.rect) or o.rect
			if Footprint.overlaps(mine, theirs) then
				return false
			end
		end
	end
	return true
end

---------------------------------------------------------------------------
-- Ghost visuals
---------------------------------------------------------------------------
local function clearDragTiles()
	for _, t in dragTiles do
		t:Destroy()
	end
	table.clear(dragTiles)
end

local function clearGhost()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	if plate then
		plate:Destroy()
		plate = nil
	end
	if roadPreview then
		roadPreview:Destroy()
		roadPreview = nil
	end
	highlight = nil
	clearDragTiles()
	spot = nil
	roadInfo = nil
end

local function neon(name: string, transparency: number): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Transparency = transparency
	p.Parent = workspace
	return p
end

local function makeGhost(def, len: number?)
	clearGhost()
	local m
	if isSegment(def) then
		m = ModelBuilder.roadSegment(def.size[1] * Grid.CellSize, len or def.size[2] * Grid.CellSize)
	else
		m = ModelBuilder.building(def)
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Transparency = math.max(d.Transparency, 0.35)
		end
	end
	local h = Instance.new("Highlight")
	h.FillTransparency = 0.75
	h.OutlineTransparency = 0.1
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Parent = m
	highlight = h
	m.Name = "Ghost"
	m.Parent = workspace
	ghost = m
	plate = neon("GhostPlate", 0.55)
	if isSegment(def) and not moving then
		local preview = neon("RoadPreview", 0.35)
		preview.Parent = nil
		roadPreview = preview
	end
end

---------------------------------------------------------------------------
-- Pointer -> island
---------------------------------------------------------------------------
local function groundHit(): Vector3?
	local ray = camera:ScreenPointToRay(pointer.X, pointer.Y)
	if math.abs(ray.Direction.Y) < 1e-4 then
		return nil
	end
	local t = -ray.Origin.Y / ray.Direction.Y
	if t < 0 or t > 4000 then
		return nil
	end
	return ray.Origin + ray.Direction * t
end

-- Pointer in island-local studs.
local function localHit(): Vector2?
	local idx = plotIndex()
	local hit = groundHit()
	if not idx or not hit then
		return nil
	end
	local l = Grid.toLocal(idx, hit)
	return Vector2.new(l.X, l.Z)
end

local function buildingUnderPointer(): Model?
	local folder = buildingsFolder()
	if not folder then
		return nil
	end
	local ray = camera:ScreenPointToRay(pointer.X, pointer.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 4000, params)
	if not result then
		return nil
	end
	local inst: Instance? = result.Instance
	while inst and inst.Parent ~= folder do
		inst = inst.Parent
	end
	return inst and inst:IsA("Model") and inst or nil
end

local function closestOnSegment(p: Vector2, a: Vector2, b: Vector2): (Vector2, number)
	local ab = b - a
	local t = ab.Magnitude > 1e-6 and math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1) or 0
	return a + ab * t, t
end

-- Snap a road end to nearby road ends, then onto nearby road centrelines.
local function snapRoadPoint(p: Vector2): (Vector2, boolean)
	local best, bestD = nil, ROAD_SNAP
	local rect = Footprint.rect(p.X, p.Y, ROAD_SNAP * 2, ROAD_SNAP * 2, 0)
	local near = Footprint.hashQuery(hash, rect, ROAD_SNAP)
	for uid in near do
		local o = others[uid]
		if o and o.road then
			local a, b = Footprint.ends(o.rect)
			for _, e in { a, b } do
				local d = (e - p).Magnitude
				if d < bestD then
					best, bestD = e, d
				end
			end
		end
	end
	if best then
		return best, true
	end
	for uid in near do
		local o = others[uid]
		if o and o.road then
			local a, b = Footprint.ends(o.rect)
			local c = closestOnSegment(p, a, b)
			local d = (c - p).Magnitude
			if d < bestD then
				best, bestD = c, d
			end
		end
	end
	if best then
		return best, true
	end
	return p, false
end

-- Building footprint position for the pointer (snap / align applied).
local function solveSpot(def, p: Vector2, len: number?): (number, number, number)
	local w, d = Footprint.size(def, len)
	if snapMode == "grid" then
		local a = (math.floor(angle / 90 + 0.5) * 90) % 360
		local x, z = Grid.snapLocal(p.X, p.Y, w, d, a)
		return x, z, a
	end
	-- align to the nearest road so the front (-Z) faces the kerb
	if not isGround(def) and not UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) then
		local reach = d / 2 + 10
		local rect = Footprint.rect(p.X, p.Y, reach * 2, reach * 2, 0)
		local best, bestD, bestRoad = nil, math.huge, nil
		for uid in Footprint.hashQuery(hash, rect, reach) do
			local o = others[uid]
			if o and o.road then
				local a, b = Footprint.ends(o.rect)
				local c = closestOnSegment(p, a, b)
				local dist = (c - p).Magnitude
				if dist < o.rect.hw + reach and dist < bestD then
					best, bestD, bestRoad = c, dist, o
				end
			end
		end
		if best and bestRoad then
			local a, b = Footprint.ends(bestRoad.rect)
			local dir = (b - a).Unit
			local normal = Vector2.new(-dir.Y, dir.X)
			if (p - best):Dot(normal) < 0 then
				normal = -normal
			end
			local yaw = math.deg(math.atan2(normal.X, normal.Y)) % 360
			local centre = best + normal * (bestRoad.rect.hw + 0.4 + d / 2)
			return math.floor(centre.X * 20 + 0.5) / 20, math.floor(centre.Y * 20 + 0.5) / 20, yaw
		end
	end
	return math.floor(p.X * 2 + 0.5) / 2, math.floor(p.Y * 2 + 0.5) / 2, angle
end

local function cashOk(cost: number): boolean
	return (ClientState.get("cash") or 0) >= cost
end

local function roadCost(def, len: number): number
	return def.cost * math.max(1, math.ceil(len / (def.size[2] * Grid.CellSize) - 0.01))
end

-- Road end point for the pointer (grid / snapping / max length applied).
local function roadPoint(p: Vector2): Vector2
	local q = p
	if snapMode == "grid" then
		q = Vector2.new(math.floor(q.X / Grid.CellSize + 0.5) * Grid.CellSize, math.floor(q.Y / Grid.CellSize + 0.5) * Grid.CellSize)
	end
	local snapped
	q, snapped = snapRoadPoint(q)
	local anchor = roadAnchor
	if anchor and not snapped then
		local v = q - anchor
		if v.Magnitude > 0.5 then
			local step = snapMode == "grid" and 45 or (UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and 15 or 0)
			if step > 0 then
				local a = math.atan2(v.X, v.Y)
				a = math.rad(math.floor(math.deg(a) / step + 0.5) * step)
				q = anchor + Vector2.new(math.sin(a), math.cos(a)) * v.Magnitude
			end
		end
		local l = (q - anchor).Magnitude
		if l > Config.RoadMaxLength then
			q = anchor + (q - anchor).Unit * Config.RoadMaxLength
		end
	end
	return q
end

---------------------------------------------------------------------------
-- Per-frame update
---------------------------------------------------------------------------
local function paint(color: Color3)
	if plate then
		plate.Color = color
	end
	if highlight then
		highlight.FillColor = color
		highlight.OutlineColor = color
	end
end

local function update()
	local active = ClientState.mode == "build" or moving ~= nil
	-- hover highlight for delete / move / inspect
	local hovered: Model? = nil
	if active and (tool == "delete" or (tool == "move" and not moving)) then
		hovered = buildingUnderPointer()
	end
	if hovered then
		if hoverHighlight.Adornee ~= hovered then
			hoverHighlight.Adornee = hovered
		end
		hoverHighlight.OutlineColor = tool == "delete" and INVALID or MOVE
		hoverHighlight.FillColor = hoverHighlight.OutlineColor
	end
	hoverHighlight.Enabled = hovered ~= nil

	local def = selected
	local idx = plotIndex()
	if not active or not def or not ghost or not plate or not idx then
		return
	end
	local p = localHit()
	if not p then
		ghost.Parent = nil
		plate.Parent = nil
		spot = nil
		return
	end

	-- drawing a road: preview the segment from the anchor
	if isSegment(def) and not moving then
		local q = roadPoint(p)
		local anchor = roadAnchor
		local w = def.size[1] * Grid.CellSize
		if anchor and roadPreview then
			local x, z, a, len = Footprint.segment(anchor.X, anchor.Y, q.X, q.Y)
			len = math.max(len, 0.1)
			local valid = len >= 2 and canPlaceLocal(def, x, z, a, len) and cashOk(roadCost(def, len))
			roadPreview.Parent = workspace
			roadPreview.Size = Vector3.new(w, 0.35, len + w)
			roadPreview.CFrame = Grid.toWorld(idx, x, z, a) * CFrame.new(0, 0.2, 0)
			roadPreview.Color = valid and ROAD or INVALID
			roadInfo = { len = len, cost = roadCost(def, len), valid = valid }
		elseif roadPreview then
			roadPreview.Parent = nil
			roadInfo = nil
		end
		-- the ghost tile marks the pen tip
		ghost.Parent = workspace
		plate.Parent = workspace
		ghost:PivotTo(Grid.toWorld(idx, q.X, q.Y, angle))
		plate.Size = Vector3.new(w + 1, 0.1, w + 1)
		plate.CFrame = Grid.toWorld(idx, q.X, q.Y, angle) * CFrame.new(0, 0.08, 0)
		paint(anchor and ROAD or VALID)
		spot = { x = q.X, z = q.Y, a = angle, valid = true }
		return
	end

	ghost.Parent = workspace
	plate.Parent = workspace
	local len = moving and movingLen or nil
	local x, z, a = solveSpot(def, p, len)
	local cost = len and roadCost(def, len) or def.cost
	local valid = canPlaceLocal(def, x, z, a, len) and (moving ~= nil or cashOk(cost))
	local cf = Grid.toWorld(idx, x, z, a)
	ghost:PivotTo(cf)
	local w, d = Footprint.size(def, len)
	plate.Size = Vector3.new(w - 0.2, 0.1, d - 0.2)
	plate.CFrame = cf * CFrame.new(0, 0.08, 0)
	paint(moving and (valid and MOVE or INVALID) or (valid and VALID or INVALID))
	spot = { x = x, z = z, a = a, valid = valid }

	-- row preview
	local start = dragStart
	if start then
		local spots = Placement.rowSpots(def, start, Vector2.new(x, z), a)
		for i, s in spots do
			local t = dragTiles[i]
			if not t then
				t = neon("RowTile", 0.45)
				dragTiles[i] = t
			end
			t.Size = Vector3.new(w - 0.4, 0.3, d - 0.4)
			t.CFrame = Grid.toWorld(idx, s[1], s[2], a) * CFrame.new(0, 0.15, 0)
			t.Color = canPlaceLocal(def, s[1], s[2], a) and VALID or INVALID
		end
		for i = #spots + 1, #dragTiles do
			dragTiles[i]:Destroy()
			dragTiles[i] = nil
		end
	end
end

-- Evenly spaced copies from a to b (spacing = footprint along the drag).
function Placement.rowSpots(def, a: Vector2, b: Vector2, yaw: number): { { number } }
	local w, d = Footprint.size(def)
	local v = b - a
	if v.Magnitude < 0.5 then
		return { { a.X, a.Y } }
	end
	local dir = v.Unit
	local rad = math.rad(yaw)
	local ux = Vector2.new(math.cos(rad), -math.sin(rad))
	local along = math.abs(dir:Dot(ux)) >= 0.7071 and w or d
	local n = math.min(math.floor(v.Magnitude / along + 0.5), 60)
	local out = {}
	for i = 0, n do
		local p = a + dir * along * i
		table.insert(out, { p.X, p.Y })
	end
	return out
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
local function toast(res)
	if res and not res.ok and res.err then
		Notifications.show(res.err, "bad")
		Sounds.play("Error")
		return false
	end
	return true
end

local function endRoad()
	roadAnchor = nil
	roadPress = nil
	roadInfo = nil
	if roadPreview then
		roadPreview.Parent = nil
	end
	notifyChanged()
end

function Placement.select(def)
	moving = nil
	movingLen = nil
	tool = nil
	selected = def
	dragStart = nil
	roadAnchor = nil
	if def then
		makeGhost(def)
		dragMode = def.drag == true and not isSegment(def)
	else
		clearGhost()
		dragMode = false
	end
	notifyChanged()
end

function Placement.setTool(t: string?)
	if moving then
		moving = nil
		movingLen = nil
		rebuildOccupancy()
	end
	if t == tool then
		t = nil
	end
	tool = t
	if t then
		selected = nil
		roadAnchor = nil
		clearGhost()
	end
	notifyChanged()
end

local function startMove(target: Model)
	local def = Buildings.get(target:GetAttribute("BuildingId") :: string)
	if not def then
		return
	end
	angle = (target:GetAttribute("Angle") :: number?) or 0
	tool = "move"
	selected = def
	moving = target
	movingLen = target:GetAttribute("Len") :: number?
	makeGhost(def, movingLen)
	rebuildOccupancy()
	notifyChanged()
end

-- Start moving a specific building (used by the building panel's Move button).
function Placement.beginMove(target: Model)
	startMove(target)
end

function Placement.rotate(reverse: boolean?)
	local step = snapMode == "grid" and 90 or 15
	angle = (angle + (reverse and -step or step)) % 360
	if snapMode == "grid" then
		angle = (math.floor(angle / 90 + 0.5) * 90) % 360
	end
	notifyChanged()
end

function Placement.toggleSnap()
	snapMode = snapMode == "free" and "grid" or "free"
	if snapMode == "grid" then
		angle = (math.floor(angle / 90 + 0.5) * 90) % 360
	end
	Sounds.play("Click", snapMode == "grid" and 1.2 or 0.9)
	notifyChanged()
end

function Placement.toggleDrag()
	dragMode = not dragMode
	notifyChanged()
end

function Placement.cancel()
	moving = nil
	movingLen = nil
	selected = nil
	tool = nil
	dragStart = nil
	roadAnchor = nil
	clearGhost()
	rebuildOccupancy()
	notifyChanged()
end

function Placement.undo()
	local res = Net.request("Undo")
	if toast(res) then
		Sounds.play("Click", 0.8)
		task.delay(0.3, rebuildOccupancy)
	end
end

local function placeAt(def, x: number, z: number, a: number)
	local res = Net.request("PlaceBuilding", def.id, x, z, a)
	if toast(res) then
		Sounds.play("Place")
	end
end

-- Lay a road from a to b (local studs); returns true when placed.
function Placement.drawRoad(def, a: Vector2, b: Vector2): boolean
	local res = Net.request("PlaceRoad", def.id, a.X, a.Y, b.X, b.Y)
	if toast(res) then
		Sounds.play("Place")
		return true
	end
	return false
end

local function primaryDown()
	local mode = ClientState.mode
	if mode == "war" then
		return
	end
	if moving and selected then
		local s = spot
		if not s then
			return
		end
		local uid = moving:GetAttribute("Uid")
		local res = Net.request("MoveBuilding", uid, s.x, s.z, s.a)
		if toast(res) then
			Sounds.play("Place")
			moving = nil
			movingLen = nil
			selected = nil
			clearGhost()
			task.delay(0.2, rebuildOccupancy)
			notifyChanged()
		end
		return
	end
	if mode == "build" and tool == "delete" then
		local target = buildingUnderPointer()
		if target then
			local res = Net.request("DeleteBuilding", target:GetAttribute("Uid"))
			if toast(res) then
				Sounds.play("Click", 0.7)
			end
		end
		return
	end
	if mode == "build" and tool == "move" then
		local target = buildingUnderPointer()
		if target then
			startMove(target)
		end
		return
	end
	if mode == "build" and selected then
		local s = spot
		if not s then
			return
		end
		if isSegment(selected) then
			local p = Vector2.new(s.x, s.z)
			roadPress = p
			roadPressAnchored = roadAnchor ~= nil
			if not roadAnchor then
				roadAnchor = p
				notifyChanged()
			end
		elseif dragMode then
			dragStart = Vector2.new(s.x, s.z)
		else
			placeAt(selected, s.x, s.z, s.a)
		end
		return
	end
	-- inspect
	local target = buildingUnderPointer()
	if target then
		Hub.call("openBuilding", target)
	end
end

local function primaryUp()
	local def = selected
	if def and isSegment(def) and roadPress then
		local press = roadPress
		roadPress = nil
		local s = spot
		local anchor = roadAnchor
		if not s or not anchor then
			return
		end
		local p = Vector2.new(s.x, s.z)
		local dragged = (p - press).Magnitude > 4
		if dragged or roadPressAnchored then
			if (p - anchor).Magnitude < 2 then
				endRoad() -- clicked the same spot twice: finish the road
			elseif Placement.drawRoad(def, anchor, p) then
				roadAnchor = p -- keep drawing from here
				task.delay(0.2, rebuildOccupancy)
				notifyChanged()
			end
		end
		return
	end
	local start = dragStart
	dragStart = nil
	if start and def and spot then
		clearDragTiles()
		local spots = Placement.rowSpots(def, start, Vector2.new(spot.x, spot.z), spot.a)
		if #spots == 1 then
			placeAt(def, spots[1][1], spots[1][2], spot.a)
		else
			local res = Net.request("PlaceMany", def.id, spots, spot.a)
			if toast(res) then
				Sounds.play("Place")
			end
		end
	end
end

function Placement.init()
	hoverHighlight = Instance.new("Highlight")
	hoverHighlight.FillTransparency = 0.7
	hoverHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hoverHighlight.Enabled = false
	hoverHighlight.Parent = player:WaitForChild("PlayerGui")

	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			pointer = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			pointer = Vector2.new(input.Position.X, input.Position.Y)
			if processed then
				return
			end
			update() -- refresh the ghost under the pointer / finger first
			primaryDown()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 and roadAnchor then
			endRoad()
		elseif not processed and ClientState.mode == "build" then
			local key = input.KeyCode
			if key == Enum.KeyCode.R or key == Enum.KeyCode.Six then
				Placement.rotate(UserInputService:IsKeyDown(Enum.KeyCode.LeftShift))
			elseif key == Enum.KeyCode.G then
				Placement.toggleSnap()
			elseif key == Enum.KeyCode.Two then
				Placement.setTool("delete")
			elseif key == Enum.KeyCode.Three or (key == Enum.KeyCode.Z and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)) then
				Placement.undo()
			elseif key == Enum.KeyCode.Four then
				Placement.toggleDrag()
			elseif key == Enum.KeyCode.Five then
				Placement.setTool("move")
			elseif key == Enum.KeyCode.Q or key == Enum.KeyCode.Escape then
				if roadAnchor then
					endRoad()
				else
					Placement.cancel()
				end
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			update()
			primaryUp()
		end
	end)

	RunService.RenderStepped:Connect(update)

	-- keep occupancy in sync with the island
	local function hookFolder()
		local folder = buildingsFolder()
		if not folder then
			return
		end
		folder.ChildAdded:Connect(function()
			task.defer(rebuildOccupancy)
		end)
		folder.ChildRemoved:Connect(function()
			task.defer(rebuildOccupancy)
		end)
		rebuildOccupancy()
	end
	ClientState.on("plot", function()
		task.wait(0.5)
		hookFolder()
	end)
	ClientState.onMode(function(mode)
		if mode ~= "build" and not moving then
			Placement.cancel()
		end
	end)
end

-- exposed for automated tests
Placement._rebuild = rebuildOccupancy
Placement._canPlace = canPlaceLocal
Placement._solve = function(def, x: number, z: number): (number, number, number)
	return solveSpot(def, Vector2.new(x, z))
end

return Placement
