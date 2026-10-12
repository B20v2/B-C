--[[
	Modal
	Window system. One window at a time:
	  Modal.open(...)      centered window, world blurred behind it
	  Modal.openSide(...)  inspector docked on the right, world stays visible
	Both share the Field Command chrome: stencil title, amber accent bar,
	hazard strip, corner brackets and an X button.
]]

local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")

local UI = script.Parent.Parent.UI
local Lib = require(UI.Lib)
local Theme = require(UI.Theme)
local Icons = require(UI.Icons)

local New = Lib.New
local C = Theme.Color

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
	kind: string,
}

local layer: GuiObject
local dim: TextButton
local blur: BlurEffect? = nil
local current: Window? = nil
local closeCallbacks: { () -> () } = {}

function Modal.isOpen(): boolean
	return current ~= nil
end

function Modal.current(): Window?
	return current
end

local function setBlur(on: boolean)
	if not blur then
		local ok, b = pcall(function()
			local e = Instance.new("BlurEffect")
			e.Name = "FF_ModalBlur"
			e.Size = 0
			e.Parent = Lighting
			return e
		end)
		blur = ok and b or nil
	end
	if blur then
		Lib.tween(blur, 0.18, { Size = on and 12 or 0 })
	end
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
	if w.kind == "side" then
		Lib.tween(w.root, 0.14, { Position = UDim2.new(1, 40, 0, w.root.Position.Y.Offset) })
	else
		Lib.tween(w.root, 0.12, { Position = UDim2.new(0.5, 0, 0.5, 16) })
	end
	task.delay(0.13, function()
		w.root:Destroy()
	end)
	dim.Visible = false
	setBlur(false)
end

local function chrome(root: Frame, title: string, subtitle: string?, kind: string): Window
	local header = New("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 66),
		Parent = root,
	})
	-- amber accent bar + hazard strip
	New("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 14), Size = UDim2.fromOffset(4, 38), Parent = header })
	Lib.hazard({ Position = UDim2.new(0, 0, 1, -4), Size = UDim2.new(0, 120, 0, 4), BackgroundTransparency = 0.2, Parent = header }, C.Accent, C.Panel, 9)
	Lib.divider({ Position = UDim2.new(0, 120, 1, -2), Size = UDim2.new(1, -120, 0, 1), Parent = header })
	local iconHolder = New("Frame", {
		Name = "IconHolder",
		BackgroundColor3 = C.Inset,
		Position = UDim2.fromOffset(16, 9),
		Size = UDim2.fromOffset(52, 48),
		Parent = header,
	}, { Lib.corner(4) })
	local titleLabel = Lib.display({
		Text = string.upper(title),
		TextSize = 22,
		Position = UDim2.fromOffset(80, 10),
		Size = UDim2.new(1, -140, 0, 26),
		Parent = header,
	})
	local subtitleLabel = Lib.text({
		Text = subtitle or "",
		TextSize = Theme.TextSize.Small,
		TextColor3 = C.Muted,
		Position = UDim2.fromOffset(80, 36),
		Size = UDim2.new(1, -140, 0, 18),
		Parent = header,
	})
	local closeBtn = Lib.button({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(36, 36),
		BackgroundColor3 = C.Raised,
		Parent = header,
		Activated = function()
			Modal.close()
		end,
	}, { Lib.corner(4), Lib.stroke(C.Line, 1, 0.4) })
	local x = Icons.close(13, C.Text)
	x.AnchorPoint = Vector2.new(0.5, 0.5)
	x.Position = UDim2.fromScale(0.5, 0.5)
	x.Parent = closeBtn

	local body = New("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 68),
		Size = UDim2.new(1, 0, 1, -68),
		Parent = root,
	}, { Lib.pad(14, 16, 16, 16) })

	local win: Window
	win = {
		root = root,
		header = header,
		iconHolder = iconHolder,
		title = titleLabel,
		subtitle = subtitleLabel,
		body = body,
		kind = kind,
		close = function()
			if current == win then
				Modal.close()
			end
		end,
		onClose = function(cb)
			table.insert(closeCallbacks, cb)
		end,
	}
	return win
end

-- Centered window (width/height in design pixels).
function Modal.open(title: string, subtitle: string?, width: number?, height: number?): Window
	Modal.close()
	dim.Visible = true
	setBlur(true)
	local w, h = width or 640, height or 540
	local root = Lib.panel({
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 18),
		Size = UDim2.fromOffset(w, h),
		BackgroundTransparency = 0.02,
		ZIndex = 10,
		Parent = layer,
	})
	Lib.brackets(root, C.Accent, 14, 2, 4)
	Lib.tween(root, 0.18, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Back)
	local win = chrome(root, title, subtitle, "center")
	current = win
	return win
end

-- Inspector docked on the right (no blur, world stays interactive).
function Modal.openSide(title: string, subtitle: string?, width: number?): Window
	Modal.close()
	local w = width or 440
	local top = 124
	local root = Lib.panel({
		Name = "Inspector",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, w, 0, top),
		Size = UDim2.new(0, w, 1, -top - 112),
		BackgroundTransparency = 0.04,
		ZIndex = 10,
		Parent = layer,
	})
	Lib.brackets(root, C.Accent, 12, 2, 3)
	Lib.tween(root, 0.2, { Position = UDim2.new(1, -16, 0, top) }, Enum.EasingStyle.Quint)
	local win = chrome(root, title, subtitle, "side")
	current = win
	return win
end

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
		BackgroundTransparency = 0.45,
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
