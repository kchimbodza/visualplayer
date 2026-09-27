-- Settings remembered for each sound output, in
-- ~/.config/visual-player/devices.json. For now:
--
--   passthrough   true when passthrough is on (outputs/passthrough.lua)
--   formats_off   passthrough formats the person switched off, like
--                 { "dts", "dts-hd" }, because the device lists them but
--                 can't decode them (outputs/passthrough.lua)
--   name          a name the person chose, used instead of the detected
--                 one (outputs/audio.lua). An HDMI extractor passes on the
--                 monitor's name, so an output that really goes to an
--                 EZCOO extractor and a Poseidon D80 soundbar was called
--                 "PX277OLEDMAX" (Phase 6); renaming it fixes that.
--
-- Shared by both, so the file is only read and written in one place.

local utils = require("mp.utils")

local device_settings = {}

-- mpv's "~~" means Visual Player's own settings folder.
local SETTINGS_FILE = "~~/devices.json"

local settings_by_device = nil

local function settings_path()
    return mp.command_native({ "expand-path", SETTINGS_FILE })
end

local function load()
    settings_by_device = {}
    local file = io.open(settings_path(), "r")
    if file == nil then
        return
    end

    local loaded = utils.parse_json(file:read("*a"))
    file:close()
    if type(loaded) == "table" then
        settings_by_device = loaded
    end
end

local function save()
    local file = io.open(settings_path(), "w")
    if file == nil then
        mp.msg.warn("Couldn't save output settings to " .. settings_path())
        return
    end
    file:write(utils.format_json(settings_by_device))
    file:close()
end

-- The part of an output's name that stays the same. PipeWire names HDMI
-- outputs after their current profile, like "...hdmi-stereo",
-- "...hdmi-surround", or "...hdmi-surround71", and the profile changes
-- when the device on the other end advertises something different, as an
-- EZCOO extractor does when its mode changes. Saving under the full name
-- made each profile a different device, so a chosen name like "ULTIMEA
-- D80" came and went (Phase 6). The sound card and HDMI port stay the
-- same, so HDMI outputs are saved under those, like
-- "alsa_output.pci-0000_c4_00.1.hdmi0". Other outputs keep their name.
local function stable_key(mpv_name)
    local name = (mpv_name or ""):gsub("^%w+/", "")
    local card, profile = name:match("^(.-)%.(hdmi%-[%w%-]+)$")
    if card then
        return card .. ".hdmi" .. (profile:match("extra(%d+)$") or "0")
    end
    return name
end

local function ensure_loaded()
    if settings_by_device == nil then
        load()
    end
end

-- The settings for an output, as a table. Settings saved before, under a
-- profile's full name, are carried over, with anything saved under the
-- stable name winning. Changing the table doesn't save it; use
-- device_settings.set().
function device_settings.get(output)
    ensure_loaded()
    local key = stable_key(output and output.mpv_name)

    local merged = {}
    for saved_key, saved in pairs(settings_by_device) do
        if saved_key ~= key and stable_key(saved_key) == key and type(saved) == "table" then
            for name, value in pairs(saved) do
                merged[name] = value
            end
        end
    end
    for name, value in pairs(settings_by_device[key] or {}) do
        merged[name] = value
    end
    return merged
end

-- Changes one setting for an output, and saves. A nil value removes it.
-- Everything is saved under the stable name from then on, and the old
-- per-profile entries are tidied away.
function device_settings.set(output, name, value)
    ensure_loaded()
    local key = stable_key(output and output.mpv_name)

    local settings = device_settings.get(output)
    settings[name] = value

    for saved_key in pairs(settings_by_device) do
        if saved_key ~= key and stable_key(saved_key) == key then
            settings_by_device[saved_key] = nil
        end
    end
    settings_by_device[key] = settings
    save()
end

return device_settings
