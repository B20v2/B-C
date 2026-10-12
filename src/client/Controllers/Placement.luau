--[[
	Placement
	Ghost previews and every build tool:
	  place  - LMB place (stays selected for fast building), R rotate
	  drag   - hold and drag to paint a line (roads, or any item with Drag on)
	  delete - click a building to demolish it (hotkey 2)
	  undo   - hotkey 3
	  move   - click a building, then click its new spot (hotkey 5)
	  rotate - R / hotkey 6
	When nothing is selected, clicking one of your buildings opens its panel.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Buildings = require(Shared.Catalog.Buildings)
local Grid = require(Shared.Util.Grid)
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

local selected: any = nil
local tool: string? = nil -- nil | "delete" | "move"
local rotation = 0
local dragMode = false
local pointer = Vector2.new(0, 0)

local ghost: Model? = nil
local plate: Part? = nil
local highlight: Highlight? = nil
local hoverHighlight: Highlight
local dragStart: Vector2? = nil -- cell
local dragTiles: { Part } = {}
local moving: Model? = nil -- building being moved
local lastCell: Vector2? = nil
local listeners: { () -> () } = {}

-- client-side occupancy (rebuilt from the plot's building models)
local occupied: { [number]: number } = {}

local function notifyChanged()
	for _, fn in listeners do
		task.spawn(fn)
	end
end

function Placement.onChanged(fn: () -> ())
	table.insert(listeners, fn)
end

function Placement.state()
	return { def = selected, tool = tool, rotation = rotation, drag = dragMode, moving = moving ~= nil }
end

local function plotOrigin(): Vector3?
	local idx = ClientState.get("plot")
	if not idx then
		return nil
	end
	return Grid.plotOrigin(idx)
end

local function buildingsFolder(): Folder?
	local idx = ClientState.get("plot")
	if not idx then
		return nil
	end
	local homeland = workspace:FindFirstChild("Homeland")
	local plot = homeland and homeland:FindFirstChild("Plot_" .. idx)
	return plot and plot:FindFirstChild("Buildings") :: Folder? or nil
end

local function footprintFromModel(model: Model): (number?, number?, number?, number?, number?)
	local def = Buildings.get(model:GetAttribute("BuildingId") :: string)
	local origin = plotOrigin()
	if not def or not origin then
		return nil
	end
	local pivot = model:GetPivot()
	local _, yaw, _ = pivot:ToOrientation()
	local r = math.floor(math.deg(yaw) / 90 + 0.5) % 4
	local fw, fd = Grid.footprint(def.size[1], def.size[2], r)
	local x, z = Grid.worldToCell(origin, pivot.Position, fw, fd)
	return x, z, fw, fd, r
end

local function rebuildOccupancy()
	table.clear(occupied)
	local folder = buildingsFolder()
	if not folder then
		return
	end
	for _, model in folder:GetChildren() do
		if model:IsA("Model") and model ~= moving then
			local x, z, fw, fd = footprintFromModel(model)
			if x and z and fw and fd then
				local uid = model:GetAttribute("Uid") :: number
				for cx = x, x + fw - 1 do
					for cz = z, z + fd - 1 do
						occupied[Grid.key(cx, cz)] = uid
					end
				end
			end
		end
	end
end

local function canPlaceLocal(def, x: number, z: number, r: number): boolean
	local fw, fd = Grid.footprint(def.size[1], def.size[2], r)
	if not Grid.inBounds(x, z, fw, fd) then
		return false
	end
	for cx = x, x + fw - 1 do
		for cz = z, z + fd - 1 do
			if occupied[Grid.key(cx, cz)] then
				return false
			end
		end
	end
	return true
end

---------------------------------------------------------------------------
-- Ghost visuals
---------------------------------------------------------------------------
local function clearGhost()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	if plate then
		plate:Destroy()
		plate = nil
	end
	highlight = nil
	for _, t in dragTiles do
		t:Destroy()
	end
	table.clear(dragTiles)
	lastCell = nil
end

local function makeGhost(def)
	clearGhost()
	local m = ModelBuilder.building(def)
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

	local p = Instance.new("Part")
	p.Name = "GhostPlate"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Transparency = 0.55
	p.Parent = workspace
	plate = p
end

local function tilePart(): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Transparency = 0.45
	p.Parent = workspace
	return p
end

---------------------------------------------------------------------------
-- Pointer -> world
---------------------------------------------------------------------------
local function groundHit(): Vector3?
	local ray = camera:ScreenPointToRay(pointer.X, pointer.Y)
	if math.abs(ray.Direction.Y) < 1e-4 then
		return nil
	end
	local t = -ray.Origin.Y / ray.Direction.Y
	if t < 0 or t > 3000 then
		return nil
	end
	return ray.Origin + ray.Direction * t
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
	local result = workspace:Raycast(ray.Origin, ray.Direction * 3000, params)
	if not result then
		return nil
	end
	local inst: Instance? = result.Instance
	while inst and inst.Parent ~= folder do
		inst = inst.Parent
	end
	return inst and inst:IsA("Model") and inst or nil
end

local function cellAt(def, r: number): (number?, number?)
	local origin = plotOrigin()
	local hit = groundHit()
	if not origin or not hit then
		return nil
	end
	local fw, fd = Grid.footprint(def.size[1], def.size[2], r)
	return Grid.worldToCell(origin, hit, fw, fd)
end

-- cells for a straight drag line from a to b (dominant axis), stepping by footprint
local function dragCells(def, a: Vector2, b: Vector2, r: number): { { number } }
	local fw, fd = Grid.footprint(def.size[1], def.size[2], r)
	local out = {}
	local dx, dz = b.X - a.X, b.Y - a.Y
	if math.abs(dx) >= math.abs(dz) then
		local steps = math.floor(math.abs(dx) / fw + 0.5)
		local dir = dx >= 0 and 1 or -1
		for i = 0, math.min(steps, 120) do
			table.insert(out, { a.X + i * fw * dir, a.Y })
		end
	else
		local steps = math.floor(math.abs(dz) / fd + 0.5)
		local dir = dz >= 0 and 1 or -1
		for i = 0, math.min(steps, 120) do
			table.insert(out, { a.X, a.Y + i * fd * dir })
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Per-frame update
---------------------------------------------------------------------------
local function cashOk(def): boolean
	return (ClientState.get("cash") or 0) >= def.cost
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
	if not active or not def or not ghost or not plate then
		return
	end
	local origin = plotOrigin()
	if not origin then
		return
	end
	local x, z = cellAt(def, rotation)
	if not x or not z then
		ghost.Parent = nil
		plate.Parent = nil
		return
	end
	ghost.Parent = workspace
	plate.Parent = workspace

	local valid = canPlaceLocal(def, x, z, rotation) and (moving ~= nil or cashOk(def))
	local cf = Grid.cframeFor(origin, x, z, def.size[1], def.size[2], rotation)
	ghost:PivotTo(cf)
	local fw, fd = Grid.footprint(def.size[1], def.size[2], rotation)
	plate.Size = Vector3.new(fw * Grid.CellSize - 0.2, 0.1, fd * Grid.CellSize - 0.2)
	plate.CFrame = CFrame.new(cf.Position + Vector3.new(0, 0.08, 0))
	local color = moving and (valid and MOVE or INVALID) or (valid and VALID or INVALID)
	plate.Color = color
	if highlight then
		highlight.FillColor = color
		highlight.OutlineColor = color
	end

	-- drag preview
	if dragStart then
		local cells = dragCells(def, dragStart, Vector2.new(x, z), rotation)
		for i, c in cells do
			local t = dragTiles[i]
			if not t then
				t = tilePart()
				dragTiles[i] = t
			end
			local tcf = Grid.cframeFor(origin, c[1], c[2], def.size[1], def.size[2], rotation)
			t.Size = Vector3.new(fw * Grid.CellSize - 0.4, 0.3, fd * Grid.CellSize - 0.4)
			t.CFrame = CFrame.new(tcf.Position + Vector3.new(0, 0.15, 0))
			t.Color = canPlaceLocal(def, c[1], c[2], rotation) and VALID or INVALID
		end
		for i = #cells + 1, #dragTiles do
			dragTiles[i]:Destroy()
			dragTiles[i] = nil
		end
	end
	lastCell = Vector2.new(x, z)
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
local function toast(res)
	if res and not res.ok and res.err then
		Notifications.show(res.err, "bad")
		return false
	end
	return true
end

function Placement.select(def)
	moving = nil
	tool = nil
	selected = def
	dragStart = nil
	rotation = rotation % 4
	if def then
		makeGhost(def)
		dragMode = def.drag == true
	else
		clearGhost()
		dragMode = false
	end
	notifyChanged()
end

function Placement.setTool(t: string?)
	if moving then
		moving = nil
		rebuildOccupancy()
	end
	if t == tool then
		t = nil
	end
	tool = t
	if t then
		selected = nil
		clearGhost()
	end
	notifyChanged()
end

-- Start moving a specific building (used by the building panel's Move button).
function Placement.beginMove(target: Model)
	local def = Buildings.get(target:GetAttribute("BuildingId") :: string)
	if not def then
		return
	end
	local _, _, _, _, r = footprintFromModel(target)
	rotation = r or 0
	tool = "move"
	selected = def
	makeGhost(def)
	moving = target
	rebuildOccupancy()
	notifyChanged()
end

function Placement.rotate()
	rotation = (rotation + 1) % 4
	notifyChanged()
end

function Placement.toggleDrag()
	dragMode = not dragMode
	notifyChanged()
end

function Placement.cancel()
	moving = nil
	selected = nil
	tool = nil
	dragStart = nil
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

local function placeAt(def, x: number, z: number)
	local res = Net.request("PlaceBuilding", def.id, x, z, rotation)
	if toast(res) then
		Sounds.play("Place")
	end
end

local function primaryDown()
	local mode = ClientState.mode
	if mode == "war" then
		return
	end
	if moving and selected then
		if not lastCell then
			return
		end
		local uid = moving:GetAttribute("Uid")
		local res = Net.request("MoveBuilding", uid, lastCell.X, lastCell.Y, rotation)
		if toast(res) then
			Sounds.play("Place")
			moving = nil
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
			local def = Buildings.get(target:GetAttribute("BuildingId") :: string)
			if def then
				local _, _, _, _, r = footprintFromModel(target)
				rotation = r or 0
				selected = def
				makeGhost(def)
				moving = target
				rebuildOccupancy()
				notifyChanged()
			end
		end
		return
	end
	if mode == "build" and selected then
		if not lastCell then
			return
		end
		if dragMode then
			dragStart = lastCell
		else
			placeAt(selected, lastCell.X, lastCell.Y)
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
	if dragStart and selected and lastCell then
		local cells = dragCells(selected, dragStart, lastCell, rotation)
		dragStart = nil
		for _, t in dragTiles do
			t:Destroy()
		end
		table.clear(dragTiles)
		if #cells == 1 then
			placeAt(selected, cells[1][1], cells[1][2])
		else
			local res = Net.request("PlaceMany", selected.id, cells, rotation)
			if toast(res) then
				Sounds.play("Place")
			end
		end
	end
	dragStart = nil
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
			if input.UserInputType == Enum.UserInputType.Touch then
				update() -- refresh the ghost under the finger first
			end
			primaryDown()
		elseif not processed and ClientState.mode == "build" then
			local key = input.KeyCode
			if key == Enum.KeyCode.R or key == Enum.KeyCode.Six then
				Placement.rotate()
			elseif key == Enum.KeyCode.Two then
				Placement.setTool("delete")
			elseif key == Enum.KeyCode.Three or (key == Enum.KeyCode.Z and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)) then
				Placement.undo()
			elseif key == Enum.KeyCode.Four then
				Placement.toggleDrag()
			elseif key == Enum.KeyCode.Five then
				Placement.setTool("move")
			elseif key == Enum.KeyCode.Q then
				Placement.cancel()
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			primaryUp()
		end
	end)

	RunService.RenderStepped:Connect(update)

	-- keep occupancy in sync with the plot
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

return Placement
