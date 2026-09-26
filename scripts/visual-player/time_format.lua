-- Formats times for display, like "1:45", or "1:02:05" for an hour or more.

local time_format = {}

-- Formats seconds as minutes and seconds, adding hours when asked. Pass
-- include_hours as true for anything in a file an hour or longer, so
-- every time in that file has the same shape.
function time_format.clock(seconds, include_hours)
    seconds = math.max(0, math.floor(seconds))

    local hours = math.floor(seconds / 3600)
    local minutes = math.floor(seconds % 3600 / 60)
    local remaining_seconds = seconds % 60

    if include_hours then
        return string.format("%d:%02d:%02d", hours, minutes, remaining_seconds)
    end

    return string.format("%d:%02d", minutes, remaining_seconds)
end

return time_format
