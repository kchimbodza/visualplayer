-- Visual Player's own settings, saved between sessions in
-- ~/.config/visual-player/settings.json. See docs/plan.md, Phase 5.
--
-- Other parts of the interface read a setting with settings.get(), and
-- can ask to hear about changes with settings.on_change(). The settings
-- menu (settings_menu.lua) is where people change them.

local utils = require("mp.utils")

local settings = {}

-- mpv's "~~" means Visual Player's own settings folder.
local SETTINGS_FILE = "~~/settings.json"

-- Every setting and its value when it's never been changed.
local DEFAULTS = {
    hardware_decoding = "automatic",
    hide_controls_after_seconds = 2,
    -- Large by default, so text reads comfortably from a sofa or on a
    -- touchscreen. Normal and Extra large are in the settings menu.
    interface_size = "large",
    remember_window_size = false,
    touch_controls = "automatic",
    format_badges = "at_start",
    remembered_window_width = nil,
    remembered_window_height = nil,
}

local values = {}
local change_listeners = {}

local function settings_path()
    return mp.command_native({ "expand-path", SETTINGS_FILE })
end

local function save()
    local file = io.open(settings_path(), "w")
    if file == nil then
        mp.msg.warn("Couldn't save settings to " .. settings_path())
        return
    end
    file:write(utils.format_json(values))
    file:close()
end

function settings.get(name)
    if values[name] ~= nil then
        return values[name]
    end
    return DEFAULTS[name]
end

-- Changes a setting, saves it, and tells anything listening.
function settings.set(name, value)
    values[name] = value
    save()

    for _, listener in ipairs(change_listeners) do
        listener(name, value)
    end
end

-- Registers a function to call whenever a setting changes. It's given the
-- setting's name and new value.
function settings.on_change(listener)
    table.insert(change_listeners, listener)
end

-- Loads saved settings. Called first, before anything reads them.
function settings.load()
    local file = io.open(settings_path(), "r")
    if file == nil then
        return
    end

    local loaded = utils.parse_json(file:read("*a"))
    file:close()

    if type(loaded) == "table" then
        values = loaded
    end
end

return settings
