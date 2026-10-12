--[[
	PlotService
	Builds the homeland islands (one per player slot), the sea, assigns a plot
	to each joining player and keeps their character spawning on it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Grid = require(ReplicatedStorage.Shared.Util.Grid)

local PlotService = {}

type Plot = {
	index: number,
	origin: Vector3,
	model: Model,
	buildings: Folder,
	sign: TextLabel,
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

local function buildSea(world: Folder)
	-- Sea tiles covering the homeland and the mainland (parts max out at 2048 studs).
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

	-- nation sign on the sand at the south edge
	local signPos = origin + Vector3.new(0, 0, size / 2 + rim * 0.55)
	part(model, "SignPostL", Vector3.new(0.8, 9, 0.8), CFrame.new(signPos + Vector3.new(-10, 4.5, 0)), Color3.fromRGB(80, 84, 90))
	part(model, "SignPostR", Vector3.new(0.8, 9, 0.8), CFrame.new(signPos + Vector3.new(10, 4.5, 0)), Color3.fromRGB(80, 84, 90))
	local board = part(model, "SignBoard", Vector3.new(26, 5, 0.6), CFrame.new(signPos + Vector3.new(0, 9, 0)), Color3.fromRGB(245, 245, 240))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front -- faces into the plot
	gui.CanvasSize = Vector2.new(520, 100)
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(28, 34, 46)
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.Bold)
	label.Text = "UNCLAIMED LAND"
	label.Parent = gui

	local buildings = Instance.new("Folder")
	buildings.Name = "Buildings"
	buildings.Parent = model

	model.PrimaryPart = ground
	model.Parent = world
	return { index = index, origin = origin, model = model, buildings = buildings, sign = label, owner = nil }
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
			plot.sign.Text = string.upper(player.DisplayName) .. "'S NATION"
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
	plot.model:SetAttribute("OwnerId", nil)
	plot.buildings:ClearAllChildren()
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
