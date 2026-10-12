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
	model: Model,
	buildings: Folder,
	sign: TextLabel,
	signSub: TextLabel,
	flag: BasePart,
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

-- Sea: terrain water (waves, reflections) covering the homeland and the
-- mainland, falling back to flat parts if terrain is unavailable.
local SEA_MIN = Vector2.new(-5000, -1400)
local SEA_MAX = Vector2.new(5000, 6600)

local function buildSea(world: Folder)
	local ok = pcall(function()
		local terrain = workspace.Terrain
		terrain.WaterColor = Color3.fromRGB(40, 118, 140)
		terrain.WaterTransparency = 0.55
		terrain.WaterReflectance = 0.5
		terrain.WaterWaveSize = 0.12
		terrain.WaterWaveSpeed = 8
		local chunk = 2000
		for x = SEA_MIN.X, SEA_MAX.X - 1, chunk do
			for z = SEA_MIN.Y, SEA_MAX.Y - 1, chunk do
				terrain:FillBlock(CFrame.new(x + chunk / 2, -10, z + chunk / 2), Vector3.new(chunk, 16, chunk), Enum.Material.Water)
			end
		end
		-- sandy sea floor so the water reads blue-green, not black
		for x = SEA_MIN.X, SEA_MAX.X - 1, chunk do
			for z = SEA_MIN.Y, SEA_MAX.Y - 1, chunk do
				terrain:FillBlock(CFrame.new(x + chunk / 2, -20, z + chunk / 2), Vector3.new(chunk, 4, chunk), Enum.Material.Sand)
			end
		end
	end)
	if ok then
		return
	end
	local tile = 2000
	for ix = -2, 2 do
		for iz = -1, 3 do
			local p = part(world, "Sea", Vector3.new(tile, 2, tile), CFrame.new(ix * tile, -3, iz * tile + 600), SEA)
			p.Reflectance = 0.05
			p.CanQuery = false
		end
	end
end

local function buildPlot(world: Folder, index: number): Plot
	local origin = Grid.plotOrigin(index)
	local size = Grid.PlotSize
	local model = Instance.new("Model")
	model.Name = "Plot_" .. index

	local ground = part(model, "Ground", Vector3.new(size, 6, size), CFrame.new(origin - Vector3.new(0, 3, 0)), GRASS, Enum.Material.Grass)
	ground:SetAttribute("PlotIndex", index)
	local rim = 34
	part(model, "Sand", Vector3.new(size + rim * 2, 6, size + rim * 2), CFrame.new(origin - Vector3.new(0, 3.6, 0)), SAND, Enum.Material.Sand)

	-- thin light-blue border line marking the buildable area
	local h = 0.15
	for _, s in { -1, 1 } do
		local a = part(model, "Border", Vector3.new(size, h, 0.5), CFrame.new(origin + Vector3.new(0, h / 2, s * size / 2)), BORDER, Enum.Material.Neon)
		local b = part(model, "Border", Vector3.new(0.5, h, size), CFrame.new(origin + Vector3.new(s * size / 2, h / 2, 0)), BORDER, Enum.Material.Neon)
		a.Transparency, b.Transparency = 0.25, 0.25
		a.CanCollide, b.CanCollide = false, false
		a.CanQuery, b.CanQuery = false, false
	end

	-- nation sign + flagpole on the sand at the south edge
	local signPos = origin + Vector3.new(0, 0, size / 2 + rim * 0.55)
	local steel = Color3.fromRGB(62, 66, 64)
	part(model, "SignPostL", Vector3.new(1, 10, 1), CFrame.new(signPos + Vector3.new(-13, 5, 0)), steel, Enum.Material.Metal)
	part(model, "SignPostR", Vector3.new(1, 10, 1), CFrame.new(signPos + Vector3.new(13, 5, 0)), steel, Enum.Material.Metal)
	local board = part(model, "SignBoard", Vector3.new(30, 6.5, 0.8), CFrame.new(signPos + Vector3.new(0, 9.5, 0)), Color3.fromRGB(30, 34, 32))
	part(model, "SignStripe", Vector3.new(30, 0.6, 0.9), CFrame.new(signPos + Vector3.new(0, 6.6, 0)), Color3.fromRGB(255, 180, 54), Enum.Material.Neon)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front -- faces into the plot
	gui.CanvasSize = Vector2.new(600, 130)
	gui.LightInfluence = 0.4
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.Position = UDim2.fromScale(0.03, 0.08)
	label.Size = UDim2.fromScale(0.94, 0.58)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(240, 238, 228)
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/Sarpanch.json", Enum.FontWeight.Bold)
	label.Text = "UNCLAIMED LAND"
	label.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.Position = UDim2.fromScale(0.03, 0.68)
	sub.Size = UDim2.fromScale(0.94, 0.24)
	sub.BackgroundTransparency = 1
	sub.TextColor3 = Color3.fromRGB(255, 180, 54)
	sub.TextScaled = true
	sub.FontFace = Font.new("rbxasset://fonts/families/Sarpanch.json", Enum.FontWeight.Bold)
	sub.Text = "FREE TERRITORY"
	sub.Parent = gui

	local polePos = signPos + Vector3.new(24, 0, 0)
	part(model, "FlagBase", Vector3.new(3, 1, 3), CFrame.new(polePos + Vector3.new(0, 0.5, 0)), Color3.fromRGB(150, 150, 140), Enum.Material.Concrete)
	local pole = part(model, "FlagPole", Vector3.new(30, 0.5, 0.5), CFrame.new(polePos + Vector3.new(0, 15, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(200, 204, 206), Enum.Material.Metal)
	pole.Shape = Enum.PartType.Cylinder
	part(model, "FlagCap", Vector3.new(0.9, 0.9, 0.9), CFrame.new(polePos + Vector3.new(0, 30.2, 0)), Color3.fromRGB(255, 180, 54), Enum.Material.Metal).Shape = Enum.PartType.Ball
	local cloth = part(model, "FlagCloth", Vector3.new(9, 6, 0.15), CFrame.new(polePos + Vector3.new(4.8, 26.6, 0)), Color3.fromRGB(240, 240, 236), Enum.Material.Fabric)
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

	local buildings = Instance.new("Folder")
	buildings.Name = "Buildings"
	buildings.Parent = model

	model.PrimaryPart = ground
	model.Parent = world
	return { index = index, origin = origin, model = model, buildings = buildings, sign = label, signSub = sub, flag = cloth, owner = nil }
end

function PlotService.spawnCFrame(index: number): CFrame
	local origin = Grid.plotOrigin(index)
	return CFrame.new(origin + Vector3.new(0, 4, Grid.PlotSize / 2 - 12)) * CFrame.Angles(0, 0, 0)
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
	plot.sign.Text = "UNCLAIMED LAND"
	plot.signSub.Text = "FREE TERRITORY"
	plot.flag.Transparency = 1
	for _, g in plot.flag:GetChildren() do
		if g:IsA("SurfaceGui") then
			g.Enabled = false
			g:ClearAllChildren()
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
	plot.sign.Text = name and string.upper(name) or (string.upper(player.DisplayName) .. "'S NATION")
	plot.signSub.Text = "EST. BY COMMANDER " .. string.upper(player.DisplayName)
	plot.flag.Transparency = 0
	for _, g in plot.flag:GetChildren() do
		if g:IsA("SurfaceGui") then
			g:ClearAllChildren()
			Flag.draw(g, flag)
			g.Enabled = true
		end
	end
end

function PlotService.get(player: Player): Plot?
	return byPlayer[player]
end

-- Which player's plot contains this world position?
function PlotService.ownerAt(pos: Vector3): Player?
	for _, plot in plots do
		if plot.owner and Grid.insidePlot(plot.origin, pos, 0) then
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
