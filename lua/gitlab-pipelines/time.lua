local M = {}

function M.format_started_at(value)
	if not value or value == vim.NIL then
		return "--:--:--"
	end

	local clock = value:match("^%d%d%d%d%-%d%d%-%d%dT(%d%d:%d%d:%d%d)")
	if not clock then
		return "--:--:--"
	end

	return clock
end

function M.format_duration(seconds)
	if not seconds or seconds == vim.NIL then
		return "--:--"
	end

	seconds = math.floor(seconds)
	local minutes = math.floor(seconds / 60)
	local hours = math.floor(minutes / 60)
	seconds = seconds % 60
	minutes = minutes % 60

	if hours > 0 then
		return ("%d:%02d:%02d"):format(hours, minutes, seconds)
	end

	return ("%02d:%02d"):format(minutes, seconds)
end

local function offset_seconds(value)
	local sign, hour, min = value:match("^([%+%-])(%d%d):?(%d%d)$")
	if not sign then
		return 0
	end

	local offset = tonumber(hour) * 3600 + tonumber(min) * 60
	if sign == "-" then
		offset = -offset
	end
	return offset
end

local function utc_epoch(parts)
	local local_epoch = os.time(parts)
	local local_offset = os.date("%z", local_epoch)
	if type(local_offset) ~= "string" then
		return local_epoch
	end
	return local_epoch + offset_seconds(local_offset)
end

function M.parse_gitlab_time(value)
	if not value or value == vim.NIL then
		return nil
	end

	local year, month, day, hour, min, sec, zone =
		value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)%.?%d*([Zz%+%-]?.*)$")
	if not year then
		return nil
	end

	local parts = {
		year = tonumber(year),
		month = tonumber(month),
		day = tonumber(day),
		hour = tonumber(hour),
		min = tonumber(min),
		sec = tonumber(sec),
	}

	if not zone or zone == "" then
		return os.time(parts)
	end

	if zone == "Z" or zone == "z" then
		return utc_epoch(parts)
	end

	if not zone:match("^[%+%-]%d%d:?%d%d$") then
		return os.time(parts)
	end

	return utc_epoch(parts) - offset_seconds(zone)
end

function M.elapsed(pipeline)
	local duration = tonumber(pipeline.duration)
	if duration and duration > 0 then
		return duration
	end

	local started = M.parse_gitlab_time(pipeline.started_at)
	if not started then
		return nil
	end

	return math.max(0, os.time() - started)
end

return M
