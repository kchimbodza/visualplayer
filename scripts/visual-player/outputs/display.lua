-- Works out which screen the picture is on, and how it's connected. See
-- docs/plan.md, section 7.
--
-- mpv reports the screen's connector name (like "DP-3"), resolution,
-- and refresh rate. The screen's own name comes from its ID data (EDID),
-- which Linux keeps in /sys/class/drm. Findings this is built on (Phase
-- 4, step 3):
--   * EDID files report their size as 0, but reading them works.
--   * mpv's display-width and display-height gave 3340×3240 on a
--     2880×1620 laptop screen, apparently the whole desktop's size. So
--     the resolution comes from the connector's list of modes instead,
--     where the screen's native mode is listed first.
--   * USB-C ports can show whether they're carrying DisplayPort, but not
--     every laptop reports it. When it isn't confirmed, the connection is
--     simply called DisplayPort, rather than guessed.

local utils = require("mp.utils")

local display_output = {}

-- DisplayPort's ID in USB-C's list of "alternate modes": the extra kinds
-- of signal a USB-C cable can carry.
local DISPLAYPORT_ALTERNATE_MODE_ID = "ff01"

-- Screen names and native resolutions already read, by connector, so
-- each is read once per screen rather than every time the info panel
-- refreshes.
local screen_names_by_connector = {}
local native_modes_by_connector = {}

local function read_file(path)
    local file = io.open(path, "rb")
    if file == nil then
        return nil
    end
    local contents = file:read("*a")
    file:close()
    return contents
end

-- Laptop screens are connected inside the laptop, with connector names
-- like "eDP-1".
local function is_built_in(connector)
    return connector:find("^eDP") ~= nil
        or connector:find("^LVDS") ~= nil
        or connector:find("^DSI") ~= nil
end

-- Finds the folder Linux keeps for a connector, like
-- /sys/class/drm/card1-DP-3 for "DP-3".
local function find_connector_folder(connector)
    for _, name in ipairs(utils.readdir("/sys/class/drm", "dirs") or {}) do
        if name:match("^card%d+%-(.+)$") == connector then
            return "/sys/class/drm/" .. name
        end
    end
    return nil
end

-- Reads the screen's name from its ID data. The first 128 bytes hold
-- four 18-byte descriptions, starting at byte 54. The one whose fourth
-- byte is 0xFC is the name, up to 13 characters, ending at a line break.
local function read_screen_name(connector)
    local folder = find_connector_folder(connector)
    local edid = folder and read_file(folder .. "/edid")
    if edid == nil or #edid < 128 then
        return nil
    end

    for _, start in ipairs({ 54, 72, 90, 108 }) do
        -- Lua counts bytes from 1, so byte N of the description is at
        -- position start + N + 1.
        local is_description = edid:byte(start + 1) == 0 and edid:byte(start + 2) == 0
        if is_description and edid:byte(start + 4) == 0xFC then
            local name = edid:sub(start + 6, start + 18)
            name = name:gsub("\n.*$", ""):gsub("%s+$", "")
            if name ~= "" then
                return name
            end
        end
    end

    return nil
end

local function screen_name(connector)
    if screen_names_by_connector[connector] == nil then
        screen_names_by_connector[connector] = read_screen_name(connector) or false
    end
    return screen_names_by_connector[connector] or nil
end

-- Reads the screen's native resolution: the first line of the
-- connector's list of modes, like "2880x1620". Returns width and height.
local function read_native_mode(connector)
    local folder = find_connector_folder(connector)
    local modes = folder and read_file(folder .. "/modes")
    if modes == nil then
        return nil
    end

    local width, height = modes:match("^(%d+)x(%d+)")
    if width == nil then
        return nil
    end
    return { width = tonumber(width), height = tonumber(height) }
end

local function native_mode(connector)
    if native_modes_by_connector[connector] == nil then
        native_modes_by_connector[connector] = read_native_mode(connector) or false
    end
    return native_modes_by_connector[connector] or nil
end

-- True if a USB-C port confirms it's carrying DisplayPort right now.
local function is_usb_c_carrying_displayport()
    for _, port in ipairs(utils.readdir("/sys/class/typec", "dirs") or {}) do
        if port:find("%-partner$") then
            local folder = "/sys/class/typec/" .. port
            for _, mode in ipairs(utils.readdir(folder, "dirs") or {}) do
                local mode_folder = folder .. "/" .. mode
                local id = (read_file(mode_folder .. "/svid") or ""):match("%x+")
                local active = (read_file(mode_folder .. "/active") or ""):match("%a+")
                if id == DISPLAYPORT_ALTERNATE_MODE_ID and active == "yes" then
                    return true
                end
            end
        end
    end
    return false
end

-- Returns what's known about the screen the picture is on, or nil if mpv
-- hasn't said yet. Fields:
--   kind        "built-in", "hdmi", "displayport", "usb-c", or "other"
--   name        what to call it, like "PX277OLEDMAX"
--   connector   mpv's name for the connector, like "DP-3"
--   width, height   the screen's native resolution, when known
--   refresh         the screen's refresh rate, when mpv reports it
--   is_hdr      whether the picture is being sent in HDR
function display_output.current()
    local connectors = mp.get_property_native("display-names") or {}
    local connector = connectors[1]
    if connector == nil then
        return nil
    end

    local kind = "other"
    local name = connector
    if is_built_in(connector) then
        kind = "built-in"
        name = "Built-in screen"
    elseif connector:find("^HDMI") then
        kind = "hdmi"
        name = screen_name(connector) or connector
    elseif connector:find("^DP") then
        kind = "displayport"
        if is_usb_c_carrying_displayport() then
            kind = "usb-c"
        end
        name = screen_name(connector) or connector
    end

    local output = mp.get_property_native("video-target-params") or {}
    local mode = native_mode(connector) or {}

    return {
        kind = kind,
        name = name,
        connector = connector,
        width = mode.width,
        height = mode.height,
        refresh = mp.get_property_number("display-fps"),
        is_hdr = output.gamma == "pq" or output.gamma == "hlg",
    }
end

return display_output
