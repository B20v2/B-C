--[[
	Forge & Frontline - client bootstrap.
	Creates the UI layers (auto-scaled from a 1600x900 design to any screen),
	then starts every controller.
]]

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local Client = script.Parent
local Controllers = Client.Controllers
local ClientState = require(Client.ClientState)
local Lib = require(Client.UI.Lib)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local DESIGN = Vector2.new(1600, 900)

-- One ScreenGui per layer, each with a scaled root frame so every
-- controller can lay out in "design pixels".
local roots: { Frame } = {}
local scales: { UIScale } = {}

local function layer(name: string, order: number): Frame
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.DisplayOrder = order
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = root
	table.insert(roots, root)
	table.insert(scales, scale)
	return root
end

local hudLayer = layer("FF_HUD", 1)
local buildLayer = layer("FF_Build", 2)
local modalLayer = layer("FF_Modal", 5)
local toastLayer = layer("FF_Toasts", 8)

local function rescale()
	local vp = camera.ViewportSize
	local s = math.clamp(math.min(vp.X / DESIGN.X, vp.Y / DESIGN.Y), 0.5, 1.2)
	for i, root in roots do
		scales[i].Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
	end
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
rescale()

-- Controllers
local Sounds = require(Controllers.Sounds)
local Notifications = require(Controllers.Notifications)
local Modal = require(Controllers.Modal)
local HUD = require(Controllers.HUD)
local Placement = require(Controllers.Placement)
local BuildMenu = require(Controllers.BuildMenu)
local BuildingPanel = require(Controllers.BuildingPanel)
local ResearchUI = require(Controllers.ResearchUI)
local UnitView = require(Controllers.UnitView)
local WarView = require(Controllers.WarView)
local Effects = require(Controllers.Effects)
local Animator = require(Controllers.Animator)
local ShopUI = require(Controllers.ShopUI)
local RewardsUI = require(Controllers.RewardsUI)
local ArmyUI = require(Controllers.ArmyUI)
local Minimap = require(Controllers.Minimap)
local NationUI = require(Controllers.NationUI)
local NightLights = require(Controllers.NightLights)

Lib.setClickSound(Sounds.get("Click"))

Notifications.init(toastLayer)
Modal.init(modalLayer)
HUD.init(hudLayer)
Placement.init()
BuildMenu.init(buildLayer)
BuildingPanel.init()
ResearchUI.init()
UnitView.init()
WarView.init(hudLayer)
Effects.init()
Animator.init()
ShopUI.init()
RewardsUI.init()
ArmyUI.init()
Minimap.init(hudLayer)
NationUI.init(toastLayer)
NightLights.init()

ClientState.start()

-- VIP chat tag
TextChatService.OnIncomingMessage = function(message: TextChatMessage)
	local props = Instance.new("TextChatMessageProperties")
	local source = message.TextSource
	if source then
		local p = Players:GetPlayerByUserId(source.UserId)
		if p and p:GetAttribute("VIP") then
			props.PrefixText = "<font color='#F5C542'>[VIP]</font> " .. message.PrefixText
		end
	end
	return props
end
