-- Passthrough: sending surround formats like Dolby TrueHD, Atmos, and
-- DTS:X to a receiver untouched, so the receiver decodes them itself.
-- See docs/plan.md, section 8.
--
-- It's only ever offered for devices that report they can decode those
-- formats. Sending them to a device that can't, like a monitor's
-- speakers, gives silence or noise (Phase 0). And only the formats the
-- device lists are passed through; anything else is decoded as usual.
--
-- Whether passthrough is on is remembered for each device, in
-- ~/.config/visual-player/devices.json.

local audio_output = require("outputs.audio")
local utils = require("mp.utils")

local passthrough = {}

-- mpv's "~~" means Visual Player's own settings folder.
local SETTINGS_FILE = "~~/devices.json"

-- Each device's settings, by its mpv name, like
--   { ["pipewire/alsa_output..."] = { passthrough = true } }
local settings_by_device = {}

local function settings_path()
    return mp.command_native({ "expand-path", SETTINGS_FILE })
end

local function load_settings()
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

local function save_settings()
    local file = io.open(settings_path(), "w")
    if file == nil then
        mp.msg.warn("Couldn't save passthrough settings to " .. settings_path())
        return
    end

    file:write(utils.format_json(settings_by_device))
    file:close()
end

-- True if the output can take at least one format untouched.
function passthrough.is_possible(output)
    return output ~= nil
        and output.passthrough_formats ~= nil
        and #output.passthrough_formats > 0
end

function passthrough.is_on(output)
    if not passthrough.is_possible(output) then
        return false
    end
    local settings = settings_by_device[output.mpv_name] or {}
    return settings.passthrough == true
end

-- Tells mpv which formats to pass through for the output in use: the
-- ones it accepts if passthrough is on, and none otherwise.
local function apply(output)
    local formats = ""
    if passthrough.is_on(output) then
        formats = table.concat(output.passthrough_formats, ",")
    end

    if mp.get_property("audio-spdif", "") ~= formats then
        mp.set_property("audio-spdif", formats)
    end
end

-- Switches passthrough on or off for the output in use, and remembers
-- the choice for that device.
function passthrough.toggle()
    local output = audio_output.current()
    if not passthrough.is_possible(output) then
        return
    end

    settings_by_device[output.mpv_name] = settings_by_device[output.mpv_name] or {}
    settings_by_device[output.mpv_name].passthrough = not passthrough.is_on(output)
    save_settings()
    apply(output)
end

-- A short list of the formats a device accepts, for showing people, like
-- "TrueHD, E-AC-3, DTS-HD".
function passthrough.describe_formats(output)
    local names = {
        ac3 = "AC-3",
        eac3 = "E-AC-3",
        dts = "DTS",
        ["dts-hd"] = "DTS-HD",
        truehd = "TrueHD",
    }

    local described = {}
    for _, format in ipairs(output.passthrough_formats or {}) do
        table.insert(described, names[format] or format)
    end
    return table.concat(described, ", ")
end

function passthrough.start()
    load_settings()

    -- Whenever the output changes, pass through what that output takes.
    audio_output.on_change(function()
        apply(audio_output.current())
    end)
end

return passthrough
