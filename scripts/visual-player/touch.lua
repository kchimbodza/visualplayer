-- Whether touch controls are on. See docs/plan.md, section 5.9.
--
-- The "Touch controls" setting can be Automatic, On, or Off. Automatic
-- turns them on only when a touchscreen is connected. On is also handy
-- for testing with a mouse, since a finger tap reaches mpv as a click.
--
-- Nothing here draws anything; other parts ask touch.is_on() to decide
-- how to behave.

local settings = require("settings")

local touch = {}

local is_touchscreen_found = false

-- Linux marks each input device with properties, listed in hexadecimal
-- as "B: PROP=" under the device's name in /proc/bus/input/devices. The
-- value 2 means "direct": you touch the screen itself, as with a
-- touchscreen or pen, rather than moving a pointer, as with a touchpad
-- or mouse.
--
-- Names can't be trusted for this. The ASUS ProArt PX13's touchscreen is
-- called just "ELAN9008:00 04F3:4359", with no "touch" in it, so an
-- earlier check by name missed it (Phase 5, step 4). Its touchpad has
-- properties 5, which doesn't include "direct", so it's rightly left out.
local DIRECT_INPUT_PROPERTY = 2

local function has_property(properties, property)
    return math.floor(properties / property) % 2 == 1
end

-- Returns the name of the first touchscreen or pen found, or nil.
local function find_touchscreen()
    local file = io.open("/proc/bus/input/devices", "r")
    if file == nil then
        return nil
    end

    local current_name = nil
    local found_name = nil

    for line in file:lines() do
        local name = line:match('^N: Name="([^"]*)"')
        if name then
            current_name = name
        end

        local properties = line:match("^B: PROP=(%x+)")
        if properties and has_property(tonumber(properties, 16), DIRECT_INPUT_PROPERTY) then
            found_name = current_name or "a touchscreen"
            break
        end
    end

    file:close()
    return found_name
end

function touch.is_touchscreen_found()
    return is_touchscreen_found
end

function touch.is_on()
    local setting = settings.get("touch_controls")
    if setting == "on" then
        return true
    end
    if setting == "off" then
        return false
    end
    return is_touchscreen_found
end

function touch.start()
    local touchscreen_name = find_touchscreen()
    is_touchscreen_found = touchscreen_name ~= nil

    if is_touchscreen_found then
        mp.msg.info("Touchscreen found (" .. touchscreen_name .. "), so touch controls can be on")
    end
end

return touch
