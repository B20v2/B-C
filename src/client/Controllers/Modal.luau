--[[
	Modal
	One centered window at a time (building panel, research, shop, daily...).
	Builds the shared window chrome: header with icon, title, subtitle and an
	X button, plus a scrolling body.
]]

local UserInputService = game:GetService("UserInputService")

local UI = script.Parent.Parent.UI
local Lib = require(UI.Lib)
local Theme = require(UI.Theme)
local Icons = require(UI.Icons)

local New = Lib.New

local Modal = {}

export type Window = {
	root: Frame,
	header: Frame,
	iconHolder: Frame,
	title: TextLabel,
	subtitle: TextLabel,
	body: Frame,
	close: () -> (),
	onClose: ((() -> ()) -> ()),
}

local layer: GuiObject
local dim: TextButton
local current: Window? = nil
local closeCallbacks: { () -> () } = {}

function Modal.isOpen(): boolean
	return current ~= nil
end

function Modal.close()
	if not current then
		return
	end
	local w = current
	current = nil
	local cbs = closeCallbacks
	closeCallbacks = {}
	for _, cb in cbs do
		task.spawn(cb)
	end
	Lib.tween(w.root, 0.12, { Position = UDim2.new(0.5, 0, 0.5, 14) })
	task.delay(0.1, function()
		w.root:Destroy()
	end)
	dim.Visible = false
end

-- width/height in pixels at UIScale 1.
function Modal.open(title: string, subtitle: string?, width: number?, height: number?): Window
	Modal.close()
	dim.Visible = true
	local w, h = width or 640, height or 540
	local root = Lib.panel({
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 14),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = Theme.Color.Panel,
		ZIndex = 10,
		Parent = layer,
	})
	Lib.tween(root, 0.16, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Back)

	local header = New("Frame", {
		Name = "Header",
		BackgroundColor3 = Theme.Color.Header,
		Size = UDim2.new(1, 0, 0, 64),
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = root,
	}, { Lib.corner(Theme.Radius.Panel) })
	-- square off the header's bottom corners
	New("Frame", {
		BackgroundColor3 = Theme.Color.Header,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -10),
		Size = UDim2.new(1, 0, 0, 10),
		ZIndex = 10,
		Parent = header,
	})
	New("Frame", {
		BackgroundColor3 = Theme.Color.PanelStroke,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 1),
		ZIndex = 11,
		Parent = header,
	})
	local iconHolder = New("Frame", {
		Name = "IconHolder",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.fromOffset(52, 48),
		ZIndex = 11,
		Parent = header,
	})
	local titleLabel = Lib.text({
		Text = title,
		FontFace = Theme.Font.Bold,
		TextSize = Theme.TextSize.Title,
		Position = UDim2.fromOffset(78, 12),
		Size = UDim2.new(1, -140, 0, 24),
		ZIndex = 11,
		Parent = header,
	})
	local subtitleLabel = Lib.text({
		Text = subtitle or "",
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.Muted,
		FontFace = Theme.Font.Regular,
		Position = UDim2.fromOffset(78, 35),
		Size = UDim2.new(1, -140, 0, 18),
		ZIndex = 11,
		Parent = header,
	})
	local closeBtn = Lib.button({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(36, 36),
		BackgroundColor3 = Theme.Color.Header,
		ZIndex = 11,
		Parent = header,
		Activated = function()
			Modal.close()
		end,
	}, { Lib.corner(8) })
	local x = Icons.close(14, Theme.Color.Text)
	x.AnchorPoint = Vector2.new(0.5, 0.5)
	x.Position = UDim2.fromScale(0.5, 0.5)
	x.ZIndex = 12
	for _, d in x:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 12
		end
	end
	x.Parent = closeBtn

	local body = New("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 65),
		Size = UDim2.new(1, 0, 1, -65),
		ZIndex = 10,
		Parent = root,
	}, { Lib.pad(14) })

	local win: Window
	win = {
		root = root,
		header = header,
		iconHolder = iconHolder,
		title = titleLabel,
		subtitle = subtitleLabel,
		body = body,
		close = function()
			if current == win then
				Modal.close()
			end
		end,
		onClose = function(cb)
			table.insert(closeCallbacks, cb)
		end,
	}
	current = win
	return win
end

-- Make every GuiObject under `root` render above the dim layer.
function Modal.lift(root: Instance, z: number?)
	local zi = z or 11
	if root:IsA("GuiObject") then
		root.ZIndex = math.max(root.ZIndex, zi)
	end
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = math.max(d.ZIndex, zi)
		end
	end
end

function Modal.init(gui: GuiObject)
	layer = gui
	dim = New("TextButton", {
		Name = "Dim",
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 9,
		Parent = gui,
		Activated = function()
			Modal.close()
		end,
	})
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Escape then
			Modal.close()
		end
	end)
end

return Modal
