-- Passthrough: sending surround formats like Dolby TrueHD, Atmos, and
-- DTS:X to a receiver or soundbar untouched, so it decodes them itself.
-- See docs/plan.md, section 8.
--
-- How it works, kept deliberately simple:
--
--   * It's only offered when the device says it can decode those
--     formats, in its own report (see outputs/audio.lua). Sending a
--     format to a device that can't decode it gives silence (Phase 0).
--
--   * Audio goes straight to the HDMI port, skipping PipeWire, the way
--     VLC does it. That's what worked for Dolby TrueHD and E-AC-3 Atmos
--     on a Poseidon D80 soundbar behind an EZCOO extractor (Phase 6).
--
--   * The route is chosen when Visual Player starts, before any audio
--     plays. Once PipeWire has used the port, it won't reliably let go
--     of it mid-playback ("Device or resource busy"), so switching
--     passthrough on while something plays takes effect next time.
--     Switching it off works straight away.
--
-- Whether passthrough is on is remembered for each device, in
-- ~/.config/visual-player/devices.json.

local audio_output = require("outputs.audio")
local utils = require("mp.utils")

local passthrough = {}

-- mpv's "~~" means Visual Player's own settings folder.
local SETTINGS_FILE = "~~/devices.json"

local FRIENDLY_NAMES = {
    ac3 = "AC-3",
    eac3 = "E-AC-3",
    dts = "DTS",
    ["dts-hd"] = "DTS-HD",
    truehd = "TrueHD",
}

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

-- True if the device says it can decode at least one surround format.
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

-- The sound card's short name, like "NVidia", which ALSA uses in the
-- names of its ports.
local function read_card_name(card)
    local file = io.open("/proc/asound/card" .. card .. "/id", "r")
    if file == nil then
        return nil
    end
    local name = file:read("*l")
    file:close()
    return name
end

-- The name mpv uses to send audio straight to the output's HDMI port,
-- like "alsa/hdmi:CARD=NVidia,DEV=0", or nil if there isn't one. The
-- port number matches the one in PipeWire's name for the output.
local function find_direct_port(output)
    if output.alsa_card == nil or output.alsa_port == nil then
        return nil
    end

    local card_name = read_card_name(output.alsa_card)
    if card_name == nil then
        return nil
    end

    local wanted = string.format("alsa/hdmi:CARD=%s,DEV=%d", card_name, output.alsa_port)
    for _, device in ipairs(mp.get_property_native("audio-device-list") or {}) do
        if device.name == wanted then
            return wanted
        end
    end
    return nil
end

-- True once audio has started playing through PipeWire, after which the
-- port can't be taken over until Visual Player starts again.
local function is_playing_through_pipewire()
    return mp.get_property("current-ao") == "pipewire"
end

local function set_if_different(property, value)
    if mp.get_property(property, "") ~= value then
        mp.set_property(property, value)
    end
end

-- Goes back to playing through PipeWire, decoding as usual.
local function use_pipewire(output)
    if audio_output.direct_route_name() then
        audio_output.stop_direct_route()
        if output and output.mpv_name then
            set_if_different("audio-device", output.mpv_name)
        end
    end
    set_if_different("audio-spdif", "")
end

-- Sets up the output in use: straight to its port with every format the
-- device lists when passthrough is on, and through PipeWire otherwise.
local function apply(output)
    if not passthrough.is_on(output) then
        use_pipewire(output)
        return
    end

    -- Already on the direct route: nothing to change.
    if audio_output.direct_route_name() then
        return
    end

    -- Too late to take over the port this time.
    if is_playing_through_pipewire() then
        return
    end

    local direct_port = find_direct_port(output)
    if direct_port == nil then
        mp.msg.warn("Passthrough: couldn't find a direct port for " .. output.name)
        return
    end

    mp.msg.info("Passthrough: sending audio straight to " .. direct_port)
    audio_output.use_direct_route(direct_port, output.mpv_name)
    set_if_different("audio-device", direct_port)
    set_if_different("audio-spdif", table.concat(output.passthrough_formats, ","))
end

-- Switches passthrough on or off for the output in use, and remembers
-- the choice for that device.
function passthrough.toggle()
    local output = audio_output.current()
    if not passthrough.is_possible(output) then
        return
    end

    local turning_on = not passthrough.is_on(output)
    settings_by_device[output.mpv_name] = settings_by_device[output.mpv_name] or {}
    settings_by_device[output.mpv_name].passthrough = turning_on
    save_settings()

    if turning_on and is_playing_through_pipewire() then
        mp.osd_message("Passthrough starts next time you open Visual Player", 3)
        return
    end

    apply(output)
end

-- A short list of the formats a device can decode, for showing people,
-- like "TrueHD, E-AC-3, DTS-HD".
function passthrough.describe_formats(output)
    local described = {}
    for _, format in ipairs(output.passthrough_formats or {}) do
        table.insert(described, FRIENDLY_NAMES[format] or format)
    end
    return table.concat(described, ", ")
end

function passthrough.start()
    load_settings()

    -- Whenever the output changes, set up its route.
    audio_output.on_change(function()
        apply(audio_output.current())
    end)
end

return passthrough
