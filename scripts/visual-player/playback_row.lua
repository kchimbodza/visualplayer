-- The row of playback controls: play/pause, previous, next, repeat, and
-- speed on the left, and the time on the right. See docs/plan.md, 5.3.
--
-- This file decides what each control shows and does. bottom_controls.lua
-- places the row on screen, draws it, and passes clicks on.
--
-- Each control is described as a table:
--   name     a unique name, used to track hovering
--   icon     an icon name from icons.lua (optional)
--   label    text shown after the icon, or on its own (optional)
--   look     "normal", "dim" for a setting that's off, or "disabled"
--   action   what to do when clicked

local redraw = require("redraw")
local time_format = require("time_format")

local playback_row = {}

-- The speeds the speed button steps through, in order.
local SPEEDS = { 1, 1.25, 1.5, 2, 0.5, 0.75 }

-- Show the time as remaining rather than elapsed. Clicking the time
-- switches between the two.
local is_showing_remaining_time = false

-- The time as last drawn, so the row only redraws when the displayed
-- text actually changes, about once a second, rather than on every frame.
local last_time_text = ""

-- True when there's more than one file to move between.
local function has_playlist()
    return mp.get_property_number("playlist-count", 1) > 1
end

local function has_chapters()
    return mp.get_property_number("chapters", 0) > 0
end

local function play_pause_control()
    local is_paused = mp.get_property_bool("pause", false)

    local icon = "player-pause"
    if is_paused then
        icon = "player-play"
    end

    return {
        name = "play-pause",
        icon = icon,
        look = "normal",
        action = function()
            mp.command("cycle pause")
        end,
    }
end

-- Previous and next move through the playlist when there is one, through
-- chapters when a single file has them, and are greyed out otherwise.
local function skip_control(name, icon, direction)
    local look = "normal"
    local action = function() end

    if has_playlist() then
        local command = "playlist-next"
        if direction < 0 then
            command = "playlist-prev"
        end
        action = function()
            mp.command(command)
        end
    elseif has_chapters() then
        action = function()
            mp.commandv("add", "chapter", tostring(direction))
        end
    else
        look = "disabled"
    end

    return { name = name, icon = icon, look = look, action = action }
end

-- Repeat has three settings: off, repeat this file, and repeat the whole
-- playlist. mpv calls these loop-file and loop-playlist.
local function current_repeat_setting()
    if mp.get_property("loop-file", "no") ~= "no" then
        return "file"
    end

    if mp.get_property("loop-playlist", "no") ~= "no" then
        return "playlist"
    end

    return "off"
end

local function step_to_next_repeat_setting()
    local setting = current_repeat_setting()

    if setting == "off" then
        mp.set_property("loop-file", "inf")
    elseif setting == "file" and has_playlist() then
        mp.set_property("loop-file", "no")
        mp.set_property("loop-playlist", "inf")
    else
        mp.set_property("loop-file", "no")
        mp.set_property("loop-playlist", "no")
    end
end

local function repeat_control()
    local setting = current_repeat_setting()

    local icon = "repeat"
    local look = "normal"
    if setting == "file" then
        icon = "repeat-once"
    elseif setting == "off" then
        look = "dim"
    end

    return {
        name = "repeat",
        icon = icon,
        look = look,
        action = step_to_next_repeat_setting,
    }
end

-- Shows a speed the way people write it: "1.5×" rather than "1.500000".
local function describe_speed(speed)
    local text = string.format("%.2f", speed):gsub("0+$", ""):gsub("%.$", "")
    return text .. "×"
end

local function step_to_next_speed()
    local speed = mp.get_property_number("speed", 1)

    -- Find the speed in the list closest to the current one, then take
    -- the one after it. The current speed may not be in the list exactly,
    -- for example if it was set with the [ and ] keys.
    local closest_index = 1
    for index, listed_speed in ipairs(SPEEDS) do
        if math.abs(listed_speed - speed) < math.abs(SPEEDS[closest_index] - speed) then
            closest_index = index
        end
    end

    local next_index = closest_index % #SPEEDS + 1
    mp.set_property_number("speed", SPEEDS[next_index])
end

local function speed_control()
    local speed = mp.get_property_number("speed", 1)

    -- The label only appears when playing at an unusual speed, so it's
    -- noticeable without cluttering normal playback.
    local label = nil
    if math.abs(speed - 1) > 0.001 then
        label = describe_speed(speed)
    end

    return {
        name = "speed",
        icon = "gauge",
        label = label,
        look = "normal",
        action = step_to_next_speed,
    }
end

local function describe_time()
    local position = mp.get_property_number("time-pos")
    local duration = mp.get_property_number("duration")

    if position == nil then
        return ""
    end

    -- Live streams have no known length, so just show the position.
    if duration == nil or duration <= 0 then
        return time_format.clock(position, position >= 3600)
    end

    local include_hours = duration >= 3600
    local total = time_format.clock(duration, include_hours)

    if is_showing_remaining_time then
        return "-" .. time_format.clock(duration - position, include_hours) .. " / " .. total
    end

    return time_format.clock(position, include_hours) .. " / " .. total
end

local function time_control()
    last_time_text = describe_time()

    return {
        name = "time",
        label = last_time_text,
        look = "normal",
        action = function()
            is_showing_remaining_time = not is_showing_remaining_time
            redraw.request()
        end,
    }
end

-- Returns the controls to show, in order, split into those on the left
-- and those on the right.
function playback_row.get_controls()
    return {
        left = {
            play_pause_control(),
            skip_control("previous", "player-skip-back", -1),
            skip_control("next", "player-skip-forward", 1),
            repeat_control(),
            speed_control(),
        },
        right = {
            time_control(),
        },
    }
end

local function on_time_changed()
    if describe_time() ~= last_time_text then
        redraw.request()
    end
end

function playback_row.start()
    local properties_that_change_the_row = {
        "pause",
        "loop-file",
        "loop-playlist",
        "speed",
        "playlist-count",
        "chapters",
        "duration",
    }

    for _, property in ipairs(properties_that_change_the_row) do
        mp.observe_property(property, "native", redraw.request)
    end

    mp.observe_property("time-pos", "number", on_time_changed)
end

return playback_row
