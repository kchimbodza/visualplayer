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
-- Formats can also be switched off one by one, for devices that list
-- more than they can decode: an EZCOO extractor in its Atmos 7.1 mode
-- lists DTS and DTS-HD, but the Poseidon D80 soundbar behind it can't
-- decode DTS at all, so passing DTS through gave silence (Phase 6). A
-- format that's switched off is decoded to PCM as usual instead.
--
-- Whether passthrough is on is remembered for each device, in
-- ~/.config/visual-player/devices.json (see outputs/device_settings.lua).

local audio_output = require("outputs.audio")
local device_settings = require("outputs.device_settings")

local passthrough = {}

-- What to call each format when showing people, like in the output
-- popup's passthrough switch.
local FRIENDLY_NAMES = {
    ac3 = "AC-3",
    eac3 = "E-AC-3",
    dts = "DTS",
    ["dts-hd"] = "DTS-HD",
    truehd = "TrueHD",
}

-- True if the device says it can decode at least one surround format.
function passthrough.is_possible(output)
    return output ~= nil
        and output.passthrough_formats ~= nil
        and #output.passthrough_formats > 0
end

-- Sensible starting choices for a device nobody has set up, so it works
-- on any computer without setting up (Phase 6):
--
--   * Passthrough is on if the device lists a Dolby format, since passing
--     Dolby TrueHD or E-AC-3 through is the only way to get Atmos.
--   * DTS and DTS-HD are decoded rather than passed through. Decoding DTS
--     loses almost nothing (DTS-HD MA is lossless, so the decoded 7.1 is
--     the same; only DTS:X's height effects are lost), while many
--     soundbars, like the Poseidon D80, can't decode DTS at all and would
--     be silent.
--
-- Choices made in the output popup replace these for that device.
local DOLBY_FORMATS = { truehd = true, eac3 = true, ac3 = true }
local FORMATS_OFF_TO_START_WITH = { "dts", "dts-hd" }

local function lists_dolby(output)
    for _, format in ipairs(output.passthrough_formats or {}) do
        if DOLBY_FORMATS[format] then
            return true
        end
    end
    return false
end

-- The formats switched off for a device: the ones chosen in the popup,
-- or the starting choice if there aren't any yet.
local function formats_off(output)
    local chosen = device_settings.get(output).formats_off
    if chosen == nil then
        return FORMATS_OFF_TO_START_WITH
    end
    return chosen
end

function passthrough.is_on(output)
    if not passthrough.is_possible(output) then
        return false
    end
    local chosen = device_settings.get(output).passthrough
    if chosen == nil then
        return lists_dolby(output)
    end
    return chosen == true
end

-- Listed best first, rather than in the device's own order.
local FORMAT_ORDER = { "truehd", "eac3", "dts-hd", "ac3", "dts" }

-- The formats the device lists, best first.
function passthrough.device_formats(output)
    local formats = {}
    for _, format in ipairs(FORMAT_ORDER) do
        for _, device_format in ipairs(output.passthrough_formats or {}) do
            if device_format == format then
                table.insert(formats, format)
            end
        end
    end
    return formats
end

-- True if the person has switched this format off for this device.
function passthrough.is_format_off(output, format)
    for _, off in ipairs(formats_off(output)) do
        if off == format then
            return true
        end
    end
    return false
end

-- The formats actually passed through: the device's, minus any switched
-- off.
local function formats_to_pass(output)
    local formats = {}
    for _, format in ipairs(passthrough.device_formats(output)) do
        if not passthrough.is_format_off(output, format) then
            table.insert(formats, format)
        end
    end
    return formats
end

-- What to call a format when showing people.
function passthrough.format_name(format)
    return FRIENDLY_NAMES[format] or format
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

-- The output passthrough is sending straight to, while it is.
local output_on_direct_route = nil

-- mpv's usual channel setting, "auto-safe", asks for the layout the
-- output calls safe. A direct HDMI port calls stereo safe, so decoded
-- surround (DTS on a soundbar that can't decode it, or LPCM 5.1) came out
-- as stereo (Phase 6). The port could do 2 to 8 channels, but ALSA also
-- offers a speaker layout, built from the speakers the device advertises,
-- and the EZCOO extractor advertises only front left and right ("got
-- ALSA chmap: FL FR (FIXED) -> stereo"), even while listing 8-channel
-- PCM. So the direct route asks for surround outright (7.1, then 5.1,
-- then stereo, mpv picking the best match for each track) and ignores
-- ALSA's speaker layout, as VLC and Kodi do. Both settings are put back
-- when the route ends.
local SURROUND_CHANNELS = "7.1,5.1,stereo"
local channels_before_direct_route = nil
local ignore_chmap_before_direct_route = nil

-- Goes back to playing through PipeWire, decoding as usual, following
-- the system's output (see audio_output.switch_to).
local function use_pipewire()
    if audio_output.direct_route_name() then
        audio_output.stop_direct_route()
        output_on_direct_route = nil
        set_if_different("audio-device", "auto")
        if channels_before_direct_route then
            set_if_different("audio-channels", channels_before_direct_route)
            channels_before_direct_route = nil
        end
        if ignore_chmap_before_direct_route then
            set_if_different("alsa-ignore-chmap", ignore_chmap_before_direct_route)
            ignore_chmap_before_direct_route = nil
        end
    end
    set_if_different("audio-spdif", "")
end

-- Sets up the output in use: straight to its port with every format the
-- device lists when passthrough is on, and through PipeWire otherwise.
local function apply(output)
    if not passthrough.is_on(output) then
        use_pipewire()
        return
    end

    -- Already on the direct route: just keep the formats up to date,
    -- since some may have been switched on or off.
    if audio_output.direct_route_name() then
        set_if_different("audio-spdif", table.concat(formats_to_pass(output), ","))
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
    output_on_direct_route = output
    channels_before_direct_route = mp.get_property("audio-channels")
    set_if_different("audio-channels", SURROUND_CHANNELS)
    ignore_chmap_before_direct_route = mp.get_property("alsa-ignore-chmap")
    set_if_different("alsa-ignore-chmap", "yes")
    mp.msg.info("Passthrough: decoded audio uses up to 7.1 ("
        .. mp.get_property("audio-channels", "?") .. ")")
    set_if_different("audio-device", direct_port)
    set_if_different("audio-spdif", table.concat(formats_to_pass(output), ","))
end

-- Switches passthrough on or off for the output in use, and remembers
-- the choice for that device.
function passthrough.toggle()
    local output = audio_output.current()
    if not passthrough.is_possible(output) then
        return
    end

    local turning_on = not passthrough.is_on(output)
    device_settings.set(output, "passthrough", turning_on)

    if turning_on and is_playing_through_pipewire() then
        mp.osd_message("Passthrough starts next time you open Visual Player", 3)
        return
    end

    apply(output)
end

-- Switches one format on or off for the output in use, remembers it, and
-- takes effect straight away.
function passthrough.toggle_format(format)
    local output = audio_output.current()
    if not passthrough.is_possible(output) then
        return
    end

    local off = {}
    local was_off = passthrough.is_format_off(output, format)
    for _, existing in ipairs(formats_off(output)) do
        if existing ~= format then
            table.insert(off, existing)
        end
    end
    if not was_off then
        table.insert(off, format)
    end

    -- Saved even when empty, since an empty list is a choice too: every
    -- format passed through, rather than the starting choice.
    device_settings.set(output, "formats_off", off)
    apply(output)
end

-- A short list of the formats a device can decode, for showing people,
-- like "TrueHD, E-AC-3, DTS-HD".
function passthrough.describe_formats(output)
    local described = {}
    for _, format in ipairs(FORMAT_ORDER) do
        for _, device_format in ipairs(output.passthrough_formats or {}) do
            if device_format == format then
                table.insert(described, FRIENDLY_NAMES[format])
            end
        end
    end
    return table.concat(described, ", ")
end

-- While Visual Player holds the HDMI port directly, PipeWire can't use it,
-- and moves the system's output elsewhere, to the laptop's speakers, so
-- the next start began there, without passthrough (Phase 6). On closing,
-- give the system's output back to the passthrough device.
local function give_back_system_output()
    if output_on_direct_route == nil then
        return
    end
    local name = (output_on_direct_route.mpv_name or ""):match("^[^/]+/(.+)$")
    if name == nil then
        return
    end
    mp.command_native({
        name = "subprocess",
        args = { "pactl", "set-default-sink", name },
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
    })
end

function passthrough.start()
    mp.register_event("shutdown", give_back_system_output)


    -- Whenever the output changes, set up its route.
    audio_output.on_change(function()
        apply(audio_output.current())
    end)
end

return passthrough
