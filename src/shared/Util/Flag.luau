--[[
	Flag
	Nation flags: a pattern, three colours and an emblem, stored compactly
	as "p,c1,c2,c3,e". Drawn with plain Frames so it works in any GUI:
	the HUD badge, the war map, unit tags and SurfaceGuis on flagpoles.
]]

local Flag = {}

local rgb = Color3.fromRGB

Flag.Colors = {
	rgb(232, 232, 226), rgb(28, 30, 34), rgb(210, 52, 46), rgb(38, 92, 196),
	rgb(46, 150, 82), rgb(250, 196, 48), rgb(240, 128, 36), rgb(120, 70, 180),
	rgb(64, 176, 196), rgb(140, 32, 46), rgb(26, 54, 110), rgb(120, 132, 70),
}

Flag.Patterns = { "Tricolour", "Vertical", "Cross", "Quartered", "Canton", "Band" }
Flag.Emblems = { "None", "Disc", "Diamond", "Star", "Ring" }

export type Data = { p: number, c: { number }, e: number }

Flag.Default = { p = 1, c = { 4, 1, 3 }, e = 1 } :: Data

function Flag.encode(d: Data): string
	return ("%d,%d,%d,%d,%d"):format(d.p, d.c[1], d.c[2], d.c[3], d.e)
end

function Flag.decode(s: string?): Data
	if type(s) ~= "string" then
		return Flag.Default
	end
	local p, a, b, c, e = string.match(s, "^(%d+),(%d+),(%d+),(%d+),(%d+)$")
	if not p then
		return Flag.Default
	end
	return Flag.sanitize({ p = tonumber(p) :: number, c = { tonumber(a) :: number, tonumber(b) :: number, tonumber(c) :: number }, e = tonumber(e) :: number })
end

function Flag.sanitize(d: any): Data
	local function clamp(v: any, hi: number, def: number): number
		if type(v) ~= "number" or v ~= v then
			return def
		end
		return math.clamp(math.floor(v), 1, hi)
	end
	if type(d) ~= "table" then
		return Flag.Default
	end
	local c = type(d.c) == "table" and d.c or {}
	return {
		p = clamp(d.p, #Flag.Patterns, 1),
		c = { clamp(c[1], #Flag.Colors, 4), clamp(c[2], #Flag.Colors, 1), clamp(c[3], #Flag.Colors, 3) },
		e = (type(d.e) == "number" and d.e >= 0) and math.clamp(math.floor(d.e), 0, #Flag.Emblems - 1) or 0,
	}
end

local function rect(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, z: number?): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.ZIndex = z or 1
	f.Parent = parent
	return f
end

-- Draw the flag inside `parent` (fills it). Returns the container frame.
function Flag.draw(parent: Instance, data: Data | string | nil): Frame
	local d = typeof(data) == "string" and Flag.decode(data :: string) or Flag.sanitize(data or Flag.Default)
	local c1, c2, c3 = Flag.Colors[d.c[1]], Flag.Colors[d.c[2]], Flag.Colors[d.c[3]]
	local holder = Instance.new("Frame")
	holder.Name = "Flag"
	holder.BackgroundColor3 = c1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromScale(1, 1)
	holder.ClipsDescendants = true
	holder.Parent = parent
	local p = d.p
	if p == 1 then
		rect(holder, 0, 0, 1, 1 / 3, c1)
		rect(holder, 0, 1 / 3, 1, 1 / 3 + 0.005, c2)
		rect(holder, 0, 2 / 3, 1, 1 / 3, c3)
	elseif p == 2 then
		rect(holder, 0, 0, 1 / 3, 1, c1)
		rect(holder, 1 / 3, 0, 1 / 3 + 0.005, 1, c2)
		rect(holder, 2 / 3, 0, 1 / 3, 1, c3)
	elseif p == 3 then
		rect(holder, 0.28, 0, 0.16, 1, c3)
		rect(holder, 0, 0.4, 1, 0.2, c3)
		rect(holder, 0.31, 0, 0.1, 1, c2, 2)
		rect(holder, 0, 0.44, 1, 0.12, c2, 2)
	elseif p == 4 then
		rect(holder, 0.5, 0, 0.5, 0.5, c2)
		rect(holder, 0, 0.5, 0.5, 0.5, c2)
		rect(holder, 0, 0, 0.5, 0.5, c1)
		rect(holder, 0.5, 0.5, 0.5, 0.5, c3)
	elseif p == 5 then
		rect(holder, 0, 0.7, 1, 0.3, c3)
		rect(holder, 0, 0, 0.45, 0.55, c2, 2)
	else
		rect(holder, 0, 0, 1, 0.12, c3)
		rect(holder, 0, 0.88, 1, 0.12, c3)
		rect(holder, 0, 0.3, 1, 0.4, c2)
	end
	-- emblem
	if d.e > 0 then
		local emColor = (p == 3 or p == 5) and c1 or (d.c[1] == d.c[3] and c2 or c3)
		if p == 1 or p == 2 or p == 6 then
			emColor = (d.c[2] == 1 or d.c[2] == 6) and Flag.Colors[2] or Flag.Colors[1]
		end
		local cx, cy = 0.5, 0.5
		if p == 5 then
			cx, cy = 0.225, 0.275
		elseif p == 3 then
			cx, cy = 0.36, 0.5
		end
		local size = (p == 5) and 0.32 or 0.36
		local e = Instance.new("Frame")
		e.BorderSizePixel = 0
		e.BackgroundColor3 = emColor
		e.AnchorPoint = Vector2.new(0.5, 0.5)
		e.Position = UDim2.fromScale(cx, cy)
		e.Size = UDim2.fromScale(size * 0.66, size)
		e.ZIndex = 3
		e.Parent = holder
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = 1
		ar.Parent = e
		if d.e == 1 then
			local cr = Instance.new("UICorner")
			cr.CornerRadius = UDim.new(1, 0)
			cr.Parent = e
		elseif d.e == 2 then
			e.Rotation = 45
			e.Size = UDim2.fromScale(size * 0.5, size * 0.75)
		elseif d.e == 3 then
			e.BackgroundTransparency = 1
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Size = UDim2.fromScale(1.6, 1.6)
			t.AnchorPoint = Vector2.new(0.5, 0.5)
			t.Position = UDim2.fromScale(0.5, 0.5)
			t.Text = "★"
			t.TextScaled = true
			t.TextColor3 = emColor
			t.ZIndex = 3
			t.Parent = e
		else
			e.BackgroundTransparency = 1
			local cr = Instance.new("UICorner")
			cr.CornerRadius = UDim.new(1, 0)
			cr.Parent = e
			local st = Instance.new("UIStroke")
			st.Color = emColor
			st.Thickness = 3
			st.Parent = e
		end
	end
	return holder
end

return Flag
