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
local current_output = nil

local change_listeners = {}

-- Only one pw-dump runs at a time. If something changes while one is
-- running, another check is made straight after it, so the answer is
-- never out of date.
local is_update_running = false
local is_another_update_needed = false

function audio_output.current()
    return current_output
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
        if report then
            if report.connection_type == "DisplayPort" then
                kind = "displayport"
            end
            name = report.monitor_name or name
        end

        return { kind = kind, name = name, channels = channels }
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

-- The PipeWire name of the output mpv is using. mpv's names look like
-- "pipewire/alsa_output..." or "pulse/alsa_output...", or just "auto".
local function output_name_in_use(objects)
    local device = mp.get_property("audio-device", "auto")
    if device == "auto" or device == "pipewire" or device == "pulse" then
        return find_default_output_name(objects)
    end
    return device:match("^[^/]+/(.+)$")
end

local function find_output(objects, wanted_name)
    local devices = {}
    for _, object in ipairs(objects) do
        if object.type == "PipeWire:Interface:Device" then
            devices[object.id] = (object.info or {}).props or {}
        end
    end

    for _, object in ipairs(objects) do
        local props = (object.info or {}).props or {}
        if object.type == "PipeWire:Interface:Node"
            and props["media.class"] == "Audio/Sink"
            and props["node.name"] == wanted_name
        then
            return describe_output(props, devices[props["device.id"]] or {})
        end
    end
    return nil
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
    local output = wanted_name and find_output(objects, wanted_name)
    if output == nil then
        return
    end

    -- Only announce real changes. Checks run at several moments, like
    -- playback starting and each file loading, and usually find nothing
    -- new (Phase 4, step 1 logged every result twice).
    local description = describe_for_log(output)
    if current_output and describe_for_log(current_output) == description then
        return
    end

    current_output = output
    mp.msg.info("Sound is going to: " .. description)

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

function audio_output.start()
    -- Check again whenever an output is plugged in or removed, or a
    -- different one is chosen.
    mp.observe_property("audio-device", "string", update)
    mp.observe_property("audio-device-list", "native", update)

    -- The desktop's default output can change without mpv noticing, so
    -- check again with each new file too.
    mp.register_event("file-loaded", update)
end

return audio_output
