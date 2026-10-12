--[[
	PlotService
	Builds the homeland islands (one per player slot), the sea, assigns a plot
	to each joining player and keeps their character spawning on it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Grid = require(ReplicatedStorage.Shared.Util.Grid)
local Flag = require(ReplicatedStorage.Shared.Util.Flag)

local PlotService = {}

type Plot = {
	index: number,
	origin: Vector3,
	frame: CFrame,
	model: Model,
	buildings: Folder,
	sign: { TextLabel },
	signSub: { TextLabel },
	flags: { BasePart },
	owner: Player?,
}

local plots: { Plot } = {}
local byPlayer: { [Player]: Plot } = {}

local GRASS = Color3.fromRGB(100, 138, 76)
local SAND = Color3.fromRGB(214, 190, 140)
local SEA = Color3.fromRGB(88, 156, 196)
local BORDER = Color3.fromRGB(96, 204, 255)

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Sea: terrain water (waves, reflections) under the whole map, falling back
-- to flat parts if terrain is unavailable.
local SEA_HALF = 2300

local function buildSea(world: Folder)
	local ok = pcall(function()
		local terrain = workspace.Terrain
		terrain.WaterColor = Color3.fromRGB(40, 118, 140)
		terrain.WaterTransparency = 0.55
		terrain.WaterReflectance = 0.5
		terrain.WaterWaveSize = 0.12
		terrain.WaterWaveSpeed = 8
		local chunk = 1150
		for x = -SEA_HALF, SEA_HALF - 1, chunk do
			for z = -SEA_HALF, SEA_HALF - 1, chunk do
				local c = Config.MainlandOrigin + Vector3.new(x + chunk / 2, 0, z + chunk / 2)
				terrain:FillBlock(CFrame.new(c.X, -10, c.Z), Vector3.new(chunk, 16, chunk), Enum.Material.Water)
				-- sandy sea floor so the water reads blue-green, not black
				terrain:FillBlock(CFrame.new(c.X, -20, c.Z), Vector3.new(chunk, 4, chunk), Enum.Material.Sand)
			end
		end
	end)
	if ok then
		return
	end
	local tile = SEA_HALF * 2 / 3
	for ix = -1, 1 do
		for iz = -1, 1 do
			local c = Config.MainlandOrigin + Vector3.new(ix * tile, -3, iz * tile)
			local p = part(world, "Sea", Vector3.new(tile, 2, tile), CFrame.new(c), SEA)
			p.Reflectance = 0.05
			p.CanQuery = false
		end
	end
end

local FONT = Font.new("rbxasset://fonts/families/Sarpanch.json", Enum.FontWeight.Bold)

local function signFace(board: BasePart, face: Enum.NormalId): (TextLabel, TextLabel)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign" .. face.Name
	gui.Face = face
	gui.CanvasSize = Vector2.new(600, 110)
	gui.LightInfluence = 0.4
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.Position = UDim2.fromScale(0.03, 0.06)
	label.Size = UDim2.fromScale(0.94, 0.6)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(240, 238, 228)
	label.TextScaled = true
	label.FontFace = FONT
	label.Text = "UNCLAIMED LAND"
	label.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.Position = UDim2.fromScale(0.03, 0.68)
	sub.Size = UDim2.fromScale(0.94, 0.26)
	sub.BackgroundTransparency = 1
	sub.TextColor3 = Color3.fromRGB(255, 180, 54)
	sub.TextScaled = true
	sub.FontFace = FONT
	sub.Text = "FREE TERRITORY"
	sub.Parent = gui
	return label, sub
end

local function flagpole(model: Model, name: string, base: CFrame): BasePart
	part(model, "FlagBase", Vector3.new(3, 1, 3), base * CFrame.new(0, 0.5, 0), Color3.fromRGB(150, 150, 140), Enum.Material.Concrete)
	local pole = part(model, "FlagPole", Vector3.new(26, 0.5, 0.5), base * CFrame.new(0, 13, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(200, 204, 206), Enum.Material.Metal)
	pole.Shape = Enum.PartType.Cylinder
	part(model, "FlagCap", Vector3.new(0.9, 0.9, 0.9), base * CFrame.new(0, 26.2, 0), Color3.fromRGB(255, 180, 54), Enum.Material.Metal).Shape = Enum.PartType.Ball
	local cloth = part(model, name, Vector3.new(9, 6, 0.15), base * CFrame.new(4.8, 22.6, 0), Color3.fromRGB(240, 240, 236), Enum.Material.Fabric)
	cloth.CanCollide = false
	cloth.Transparency = 1
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local fg = Instance.new("SurfaceGui")
		fg.Name = "Flag" .. face.Name
		fg.Face = face
		fg.CanvasSize = Vector2.new(180, 120)
		fg.LightInfluence = 0.6
		fg.Enabled = false
		fg.Parent = cloth
	end
	return cloth
end

-- Bridge from the island's beach to the battlefield shore.
local function buildBridge(model: Model, index: number)
	local W = Config.BridgeWidth
	local toCenter = -Grid.direction(index)
	local a = Grid.gate(index) - toCenter * 6
	local b = Grid.shore(index) - Grid.direction(index) * 14
	local len = (b - a).Magnitude
	local frame = CFrame.lookAt((a + b) / 2, b)
	local concrete = Color3.fromRGB(150, 152, 148)
	local deck = part(model, "BridgeDeck", Vector3.new(W, 1.6, len), frame * CFrame.new(0, -0.75, 0), Color3.fromRGB(58, 62, 64), Enum.Material.Asphalt)
	deck:SetAttribute("Bridge", index)
	local line = part(model, "BridgeLine", Vector3.new(0.5, 0.05, len - 4), frame * CFrame.new(0, 0.08, 0), Color3.fromRGB(236, 196, 64))
	line.CanCollide = false
	line.CanQuery = false
	for _, side in { -1, 1 } do
		local x = side * (W / 2 - 0.4)
		part(model, "Railing", Vector3.new(0.8, 1.2, len), frame * CFrame.new(x, 1.6, 0), concrete, Enum.Material.Concrete)
		part(model, "Curb", Vector3.new(1.6, 0.6, len), frame * CFrame.new(side * (W / 2 - 0.8), 0.3, 0), concrete, Enum.Material.Concrete)
		local n = math.max(2, math.floor(len / 36))
		for i = 0, n do
			local z = -len / 2 + 6 + (len - 12) * i / n
			part(model, "Post", Vector3.new(0.9, 2.2, 0.9), frame * CFrame.new(x, 1.1, z), concrete, Enum.Material.Concrete)
			if i % 2 == 0 then
				local lamp = part(model, "LampPost", Vector3.new(0.4, 7, 0.4), frame * CFrame.new(x, 3.5, z), Color3.fromRGB(70, 74, 76), Enum.Material.Metal)
				lamp.CanCollide = false
				local head = part(model, "Lamp", Vector3.new(1.4, 0.5, 1.4), frame * CFrame.new(x - side * 0.6, 7, z), Color3.fromRGB(255, 220, 160), Enum.Material.Neon)
				head.CanCollide = false
				head.Transparency = 1
				head:SetAttribute("NightGlow", true)
			end
		end
	end
	local piers = math.max(2, math.floor(len / 50))
	for i = 1, piers do
		local z = -len / 2 + len * i / (piers + 1)
		for _, side in { -1, 1 } do
			part(model, "Pier", Vector3.new(3.2, 24, 3.2), frame * CFrame.new(side * (W / 2 - 3), -13.5, z), concrete, Enum.Material.Concrete)
		end
		part(model, "PierCap", Vector3.new(W, 1.4, 3.6), frame * CFrame.new(0, -2.2, z), concrete, Enum.Material.Concrete)
	end
end

local function buildPlot(world: Folder, index: number): Plot
	local frame = Grid.plotCFrame(index)
	local origin = frame.Position
	local size = Grid.PlotSize
	local rim = Grid.Rim
	local model = Instance.new("Model")
	model.Name = "Plot_" .. index

	local ground = part(model, "Ground", Vector3.new(size, 6, size), frame * CFrame.new(0, -3, 0), GRASS, Enum.Material.Grass)
	ground:SetAttribute("PlotIndex", index)
	part(model, "Sand", Vector3.new(size + rim * 2, 6, size + rim * 2), frame * CFrame.new(0, -3.6, 0), SAND, Enum.Material.Sand)

	-- thin light-blue border line marking the buildable area
	local h = 0.15
	for _, s in { -1, 1 } do
		local a = part(model, "Border", Vector3.new(size, h, 0.5), frame * CFrame.new(0, h / 2, s * size / 2), BORDER, Enum.Material.Neon)
		local b = part(model, "Border", Vector3.new(0.5, h, size), frame * CFrame.new(s * size / 2, h / 2, 0), BORDER, Enum.Material.Neon)
		a.Transparency, b.Transparency = 0.25, 0.25
		a.CanCollide, b.CanCollide = false, false
		a.CanQuery, b.CanQuery = false, false
	end

	-- border gate over the bridge: nation name on both faces, flags either side
	local gateCF = frame * CFrame.new(0, 0, -(size / 2 + rim * 0.5))
	local steel = Color3.fromRGB(62, 66, 64)
	local W = Config.BridgeWidth
	for _, side in { -1, 1 } do
		part(model, "GatePillar", Vector3.new(2.4, 18, 2.4), gateCF * CFrame.new(side * (W / 2 + 2), 9, 0), steel, Enum.Material.Metal)
	end
	local board = part(model, "SignBoard", Vector3.new(W + 8, 7, 1.2), gateCF * CFrame.new(0, 19, 0), Color3.fromRGB(30, 34, 32))
	part(model, "SignStripe", Vector3.new(W + 8, 0.6, 1.3), gateCF * CFrame.new(0, 15.8, 0), Color3.fromRGB(255, 180, 54), Enum.Material.Neon)
	local titles, subs = {}, {}
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local t, sub = signFace(board, face)
		table.insert(titles, t)
		table.insert(subs, sub)
	end
	local flags = {
		flagpole(model, "FlagCloth", gateCF * CFrame.new(-(W / 2 + 12), 0, 0)),
		flagpole(model, "FlagCloth2", gateCF * CFrame.new(W / 2 + 12, 0, 0)),
	}
	buildBridge(model, index)

	local buildings = Instance.new("Folder")
	buildings.Name = "Buildings"
	buildings.Parent = model

	model.PrimaryPart = ground
	model.Parent = world
	return { index = index, origin = origin, frame = frame, model = model, buildings = buildings, sign = titles, signSub = subs, flags = flags, owner = nil }
end

-- Spawn just inside the front edge, facing into the city.
function PlotService.spawnCFrame(index: number): CFrame
	return Grid.plotCFrame(index) * CFrame.new(0, 4, -(Grid.PlotSize / 2 - 14)) * CFrame.Angles(0, math.pi, 0)
end

function PlotService.claim(player: Player): Plot?
	for _, plot in plots do
		if plot.owner == nil then
			plot.owner = player
			byPlayer[player] = plot
			PlotService.setIdentity(player, nil, nil)
			plot.model:SetAttribute("OwnerId", player.UserId)
			player:SetAttribute("PlotIndex", plot.index)
			return plot
		end
	end
	return nil
end

function PlotService.release(player: Player)
	local plot = byPlayer[player]
	if not plot then
		return
	end
	byPlayer[player] = nil
	plot.owner = nil
	for i, t in plot.sign do
		t.Text = "UNCLAIMED LAND"
		plot.signSub[i].Text = "FREE TERRITORY"
	end
	for _, cloth in plot.flags do
		cloth.Transparency = 1
		for _, g in cloth:GetChildren() do
			if g:IsA("SurfaceGui") then
				g.Enabled = false
				g:ClearAllChildren()
			end
		end
	end
	plot.model:SetAttribute("OwnerId", nil)
	plot.buildings:ClearAllChildren()
end

-- Sign text and flag for the player's plot (name/flag nil = not founded yet).
function PlotService.setIdentity(player: Player, name: string?, flag: string?)
	local plot = byPlayer[player]
	if not plot then
		return
	end
	for i, t in plot.sign do
		t.Text = name and string.upper(name) or (string.upper(player.DisplayName) .. "'S NATION")
		plot.signSub[i].Text = "EST. BY COMMANDER " .. string.upper(player.DisplayName)
	end
	for _, cloth in plot.flags do
		cloth.Transparency = 0
		for _, g in cloth:GetChildren() do
			if g:IsA("SurfaceGui") then
				g:ClearAllChildren()
				Flag.draw(g, flag)
				g.Enabled = true
			end
		end
	end
end

function PlotService.get(player: Player): Plot?
	return byPlayer[player]
end

-- Which player's plot contains this world position?
function PlotService.ownerAt(pos: Vector3): Player?
	for _, plot in plots do
		if plot.owner and Grid.insidePlot(plot.index, pos, 0) then
			return plot.owner
		end
	end
	return nil
end

local function bindCharacter(player: Player)
	local function place(character: Model)
		local plot = byPlayer[player]
		if not plot then
			return
		end
		character:WaitForChild("HumanoidRootPart", 10)
		task.defer(function()
			if character.Parent then
				character:PivotTo(PlotService.spawnCFrame(plot.index))
			end
		end)
	end
	player.CharacterAdded:Connect(place)
	if player.Character then
		place(player.Character)
	end
end

function PlotService.init(_S)
	local world = Instance.new("Folder")
	world.Name = "Homeland"
	world.Parent = workspace
	buildSea(world)
	for i = 1, Config.MaxPlots do
		table.insert(plots, buildPlot(world, i))
	end
end

function PlotService.start()
	Players.PlayerAdded:Connect(bindCharacter)
	for _, p in Players:GetPlayers() do
		bindCharacter(p)
	end
end

return PlotService
