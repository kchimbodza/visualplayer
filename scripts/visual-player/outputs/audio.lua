-- Works out where the sound is going: what kind of output it is, its
-- name, and how many channels it takes. See docs/plan.md, section 7.
--
-- mpv only knows the name of the output it hands sound to, and on most
-- systems that's just "auto". The details come from PipeWire (through
-- its pw-dump tool) and from what a connected screen reports about
-- itself over the cable, which Linux keeps in /proc/asound.
--
-- Findings this is built on (Phase 4, step 1):
--   * Linux names DisplayPort audio "HDMI", but the screen's own report
--     says which it really is ("connection_type DisplayPort").
--   * The screen's report also has its name, like "PX277OLEDMAX".
--   * PipeWire's port name "hdmi-stereo-extra3" is port 3 of that sound
--     card, and matches the screen report in /proc/asound/card1/eld#0.3.
--   * PipeWire reports each output's channel count, which is how
--     downmixing can be spotted, since mpv can't see it (Phase 0).

local utils = require("mp.utils")

local audio_output = {}

-- A friendlier name for each Bluetooth codec PipeWire reports.
local BLUETOOTH_CODEC_NAMES = {
    sbc = "SBC",
    sbc_xq = "SBC-XQ",
    aac = "AAC",
    aptx = "aptX",
    aptx_hd = "aptX HD",
    aptx_ll = "aptX LL",
    ldac = "LDAC",
    lc3 = "LC3",
    opus_05 = "Opus",
}

-- What's currently known about the output in use, or nil if nothing's
-- been found yet. Fields:
--   kind       "bluetooth", "hdmi", "displayport", "usb", or "speakers"
--   name       what to call it, like "PX277OLEDMAX"
--   channels   how many channels it takes, if known
--   codec      the Bluetooth codec, like "LDAC", if it's Bluetooth
--   passthrough_formats   for screens and receivers, the formats they
--              can decode themselves, in mpv's names ("truehd", "eac3"),
--              so they can be passed through untouched. Empty when the
--              device only takes plain PCM.
--   pipewire_allowed_formats   the formats PipeWire currently lets
--              through untouched on this output, in PipeWire's names
--              ("PCM", "AC3", "DTS"). PipeWire only allows PCM until
--              passthrough is enabled for it (Phase 6: a monitor over
--              HDMI listed DTS, PipeWire allowed only PCM, and passing
--              DTS through gave silence).
--   pipewire_id   PipeWire's number for this output, used to change what
--              it allows
--   alsa_card, alsa_port   for screens and receivers, the sound card and
--              port, used to send passthrough audio straight to the port
--              (see outputs/passthrough.lua)
local current_output = nil

-- Every output PipeWire knows about, described the same way, plus
-- mpv_name: what mpv calls it, like "pipewire/alsa_output...". Used by
-- the output popup's list. The one in use has is_current set.
local all_outputs = {}

local change_listeners = {}

-- Only one pw-dump runs at a time. If something changes while one is
-- running, another check is made straight after it, so the answer is
-- never out of date.
local is_update_running = false
local is_another_update_needed = false

function audio_output.current()
    return current_output
end

function audio_output.list()
    return all_outputs
end


-- Registers a function to call whenever the output's details change.
function audio_output.on_change(listener)
    table.insert(change_listeners, listener)
end

-- Reads a screen's report about itself: lines of "key<tabs>value".
local function read_screen_report(path)
    local file = io.open(path, "r")
    if file == nil then
        return nil
    end

    local report = {}
    for line in file:lines() do
        local key, value = line:match("^(%S+)%s+(.-)%s*$")
        if key then
            report[key] = value
        end
    end
    file:close()
    return report
end

-- Finds the report from the screen connected to a sound card's port.
-- Reports are named like "eld#0.3": the last number is the port.
local function find_screen_report(card, port)
    local folder = "/proc/asound/card" .. card
    for _, file_name in ipairs(utils.readdir(folder, "files") or {}) do
        local report_port = file_name:match("^eld#%d+%.(%d+)$")
        if report_port and tonumber(report_port) == port then
            local report = read_screen_report(folder .. "/" .. file_name)
            if report and report.eld_valid == "1" then
                return report
            end
        end
    end
    return nil
end

-- The formats a screen or receiver reports it can decode, matched to the
-- names mpv uses for passing them through. The kernel's names come from
-- the device's report, like "[0x7] DTS" or "[0xc] MLP (Dolby TrueHD)".
-- DTS-HD is checked before DTS, since its name contains "DTS" too.
local PASSTHROUGH_FORMATS_BY_REPORTED_NAME = {
    { pattern = "^AC%-3", format = "ac3" },
    { pattern = "^E%-AC%-3", format = "eac3" },
    { pattern = "^DTS%-HD", format = "dts-hd" },
    { pattern = "^DTS", format = "dts" },
    { pattern = "^MLP", format = "truehd" },
}

-- Reads which formats a device can decode itself from its report, which
-- lists each one as "sad0_coding_type", "sad1_coding_type", and so on.
-- (Phase 4, step 5: the PX277OLEDMAX monitor lists only 2-channel PCM.)
local function read_passthrough_formats(report)
    local formats = {}
    local count = tonumber(report.sad_count) or 0

    for index = 0, count - 1 do
        local coding_type = report["sad" .. index .. "_coding_type"] or ""
        local reported_name = coding_type:match("^%[.-%]%s*(.+)$") or coding_type

        for _, known in ipairs(PASSTHROUGH_FORMATS_BY_REPORTED_NAME) do
            if reported_name:find(known.pattern) then
                table.insert(formats, known.format)
                break
            end
        end
    end

    return formats
end

-- Which port of a sound card a PipeWire output uses. PipeWire names them
-- "hdmi-stereo" for the first, then "hdmi-stereo-extra1", "-extra2"...
local function screen_port_from_name(node_name)
    return tonumber(node_name:match("%-extra(%d+)$") or "0")
end

-- Turns what PipeWire says about an output into the details above.
local function describe_output(node, device)
    local node_name = node["node.name"] or ""
    local channels = tonumber(node["audio.channels"])

    if node["device.api"] == "bluez5" then
        local codec = node["api.bluez5.codec"]
        return {
            kind = "bluetooth",
            name = node["node.description"] or "Bluetooth",
            channels = channels,
            codec = BLUETOOTH_CODEC_NAMES[codec] or (codec and codec:upper()),
        }
    end

    if device["device.bus"] == "usb" then
        return {
            kind = "usb",
            name = device["device.description"] or node["node.description"] or "USB audio",
            channels = channels,
        }
    end

    if node_name:find("hdmi") then
        local card = node["api.alsa.pcm.card"]
        local report = card and find_screen_report(card, screen_port_from_name(node_name))

        local kind = "hdmi"
        local name = node["node.description"] or "HDMI"
        local passthrough_formats = {}
        if report then
            if report.connection_type == "DisplayPort" then
                kind = "displayport"
            end
            name = report.monitor_name or name
            passthrough_formats = read_passthrough_formats(report)
        end

        return {
            kind = kind,
            name = name,
            channels = channels,
            passthrough_formats = passthrough_formats,
            alsa_card = card,
            alsa_port = screen_port_from_name(node_name),
        }
    end

    return { kind = "speakers", name = "Built-in speakers", channels = channels }
end

-- Finds PipeWire's default output, which is what mpv's "auto" uses.
local function find_default_output_name(objects)
    for _, object in ipairs(objects) do
        local props = object.props or {}
        if object.type == "PipeWire:Interface:Metadata" and props["metadata.name"] == "default" then
            for _, entry in ipairs(object.metadata or {}) do
                if entry.key == "default.audio.sink" and type(entry.value) == "table" then
                    return entry.value.name
                end
            end
        end
    end
    return nil
end

-- When passthrough sends audio straight to an HDMI port, mpv's output is
-- the port's direct name, like "alsa/hdmi:CARD=NVidia,DEV=0". That's
-- still the same device as far as people are concerned, so this records
-- which PipeWire output it stands in for.
local direct_route = nil

-- Records that mpv is sending audio straight to a port, standing in for
-- the given PipeWire output (its mpv name, "pipewire/...").
function audio_output.use_direct_route(direct_name, pipewire_mpv_name)
    direct_route = { direct_name = direct_name, pipewire_mpv_name = pipewire_mpv_name }
end

function audio_output.stop_direct_route()
    direct_route = nil
end

-- The direct name mpv is using, or nil when audio goes through PipeWire.
function audio_output.direct_route_name()
    return direct_route and direct_route.direct_name
end

-- The PipeWire name of the output mpv is using. mpv's names look like
-- "pipewire/alsa_output..." or "pulse/alsa_output...", or just "auto".
local function output_name_in_use(objects)
    local device = mp.get_property("audio-device", "auto")

    if direct_route and device == direct_route.direct_name then
        device = direct_route.pipewire_mpv_name
    end

    if device == "auto" or device == "pipewire" or device == "pulse" then
        return find_default_output_name(objects)
    end
    return device:match("^[^/]+/(.+)$")
end

-- Describes every audio output PipeWire knows about, marking the one
-- with the wanted name as the one in use.
local function describe_all_outputs(objects, wanted_name)
    local devices = {}
    for _, object in ipairs(objects) do
        if object.type == "PipeWire:Interface:Device" then
            devices[object.id] = (object.info or {}).props or {}
        end
    end

    local outputs = {}
    for _, object in ipairs(objects) do
        local props = (object.info or {}).props or {}
        if object.type == "PipeWire:Interface:Node" and props["media.class"] == "Audio/Sink" then
            local output = describe_output(props, devices[props["device.id"]] or {})
            output.mpv_name = "pipewire/" .. (props["node.name"] or "")
            output.is_current = props["node.name"] == wanted_name
            output.pipewire_id = object.id

            -- What PipeWire currently allows through untouched is in the
            -- output's "Props" settings, as "iec958Codecs".
            output.pipewire_allowed_formats = {}
            local params = (object.info or {}).params or {}
            for _, setting in ipairs(params.Props or {}) do
                if type(setting.iec958Codecs) == "table" then
                    output.pipewire_allowed_formats = setting.iec958Codecs
                end
            end
            table.insert(outputs, output)
        end
    end
    return outputs
end

local function describe_for_log(output)
    local parts = { output.kind }
    if output.codec then
        table.insert(parts, output.codec)
    end
    if output.channels then
        table.insert(parts, output.channels .. " channels")
    end
    return output.name .. " (" .. table.concat(parts, ", ") .. ")"
end

-- The outputs in the list, as one line of text, to notice when a device
-- is plugged in or removed.
local last_list_summary = nil

local function summarize_list(outputs)
    -- Includes what PipeWire allows, so allowing passthrough counts as a
    -- change worth announcing.
    local names = {}
    for _, output in ipairs(outputs) do
        local allowed = table.concat(output.pipewire_allowed_formats, ",")
        table.insert(names, output.mpv_name .. " " .. allowed)
    end
    return table.concat(names, "|")
end

local update

local function on_pw_dump_finished(success, result)
    is_update_running = false
    if is_another_update_needed then
        is_another_update_needed = false
        update()
    end

    if not success or result == nil or result.status ~= 0 then
        mp.msg.warn("Couldn't ask PipeWire about audio outputs. Is pw-dump installed?")
        return
    end

    local objects = utils.parse_json(result.stdout)
    if type(objects) ~= "table" then
        return
    end

    local wanted_name = output_name_in_use(objects)
    all_outputs = describe_all_outputs(objects, wanted_name)

    local output = nil
    for _, listed in ipairs(all_outputs) do
        if listed.is_current then
            output = listed
        end
    end
    if output == nil then
        return
    end

    -- Only announce real changes. Checks run at several moments, like
    -- playback starting and each file loading, and usually find nothing
    -- new (Phase 4, step 1 logged every result twice). A change is either
    -- a different output in use, or a device plugged in or removed.
    local description = describe_for_log(output)
    local list_summary = summarize_list(all_outputs)
    local is_same_output = current_output and describe_for_log(current_output) == description
    if is_same_output and list_summary == last_list_summary then
        return
    end

    last_list_summary = list_summary
    current_output = output
    if not is_same_output then
        mp.msg.info("Sound is going to: " .. description)
    end

    for _, listener in ipairs(change_listeners) do
        listener()
    end
end

-- Asks PipeWire for the current details. pw-dump runs in the background,
-- so playback is never held up while it answers.
update = function()
    if is_update_running then
        is_another_update_needed = true
        return
    end
    is_update_running = true

    mp.command_native_async({
        name = "subprocess",
        args = { "pw-dump" },
        capture_stdout = true,
        playback_only = false,
    }, on_pw_dump_finished)
end

-- Switches the sound to another output, by making it the system's
-- output, exactly as choosing it in GNOME's Sound Output menu does, and
-- following the system's choice. Pinning mpv to the chosen device made
-- the player and the system disagree: after choosing the speakers in the
-- popup, choosing Bluetooth in GNOME left Visual Player on the speakers
-- (Phase 6). With one shared choice, they can't drift apart.
--
-- It's defined down here, below update(), since Lua only finds a local
-- function defined above the one using it.
function audio_output.switch_to(mpv_name)
    local pipewire_name = mpv_name:match("^[^/]+/(.+)$")
    if pipewire_name then
        mp.command_native({
            name = "subprocess",
            args = { "pactl", "set-default-sink", pipewire_name },
            playback_only = false,
            capture_stdout = true,
            capture_stderr = true,
        })
    end

    if mp.get_property("audio-device") ~= "auto" then
        mp.set_property("audio-device", "auto")
    end
    update()
end

-- Checks the outputs again straight away, for example after changing
-- what PipeWire allows.
function audio_output.refresh()
    update()
end

-- Checks the outputs straight away and waits for the answer, which takes
-- a fraction of a second. Used once at startup, so passthrough can choose
-- its route before the first file's audio starts. Otherwise playback
-- starts through PipeWire, which then holds the HDMI port, and switching
-- to it directly fails with "Device or resource busy" (Phase 6).
local function update_and_wait()
    local result = mp.command_native({
        name = "subprocess",
        args = { "pw-dump" },
        capture_stdout = true,
        playback_only = false,
    })
    on_pw_dump_finished(result ~= nil, result)
end

function audio_output.start()
    update_and_wait()

    -- Check again whenever an output is plugged in or removed, or a
    -- different one is chosen.
    mp.observe_property("audio-device", "string", update)
    mp.observe_property("audio-device-list", "native", update)

    -- The desktop's default output can change without mpv noticing, so
    -- check again with each new file too.
    mp.register_event("file-loaded", update)
end

return audio_output
