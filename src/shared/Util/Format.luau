--[[
	Format
	Number / time formatting helpers shared by client UI and server messages.
]]

local Format = {}

local SUFFIXES = { "", "k", "M", "B", "T", "Qd", "Qn" }

-- 1234 -> "1.2k", 24100000 -> "24.1M"
function Format.short(n: number): string
	local negative = n < 0
	n = math.abs(n)
	local index = 1
	while n >= 1000 and index < #SUFFIXES do
		n /= 1000
		index += 1
	end
	local text
	if index == 1 then
		text = tostring(math.floor(n + 0.5))
	elseif n >= 100 then
		text = string.format("%d%s", math.floor(n), SUFFIXES[index])
	else
		text = string.format("%.1f%s", math.floor(n * 10) / 10, SUFFIXES[index])
		text = text:gsub("%.0" .. SUFFIXES[index] .. "$", SUFFIXES[index])
	end
	return (negative and "-" or "") .. text
end

function Format.cash(n: number): string
	if n < 0 then
		return "-$" .. Format.short(-n)
	end
	return "$" .. Format.short(n)
end

-- 12000 -> "12,000"
function Format.commas(n: number): string
	local s = tostring(math.floor(math.abs(n) + 0.5))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return (n < 0 and "-" or "") .. formatted
end

function Format.money(n: number): string
	return "$" .. Format.commas(n)
end

-- 83 -> "01:23"
function Format.clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%02d:%02d", m, s)
end

-- 48 -> "48s", 130 -> "2m 10s"
function Format.duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds < 60 then
		return seconds .. "s"
	elseif seconds < 3600 then
		local s = seconds % 60
		return (seconds // 60) .. "m" .. (s > 0 and (" " .. s .. "s") or "")
	end
	local m = (seconds % 3600) // 60
	return (seconds // 3600) .. "h" .. (m > 0 and (" " .. m .. "m") or "")
end

function Format.rate(n: number): string
	local sign = n >= 0 and "+" or ""
	return sign .. Format.short(n) .. " / Min"
end

function Format.percent(n: number): string
	return math.floor(n + 0.5) .. "%"
end

return Format
