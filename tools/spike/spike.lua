-- Phase 0 spike for Visual Player.
--
-- Waits until the video is actually playing, reads the properties
-- Visual Player depends on, writes a plain-English report, then quits.
-- Launched by run-spike.sh, which tells it where to write the report.

local mp_options = require("mp.options")
local mp_utils = require("mp.utils")

-- How long to let the video play before reading the results. Hardware
-- decoding and HDR output can take a moment to settle after playback starts.
local SECONDS_TO_PLAY_BEFORE_CHECKING = 6

local settings = {
    report = "spike-report.txt",
}
mp_options.read_options(settings, "spike")

local has_written_report = false

-- Turns any mpv property value into readable text for the report.
local function describe(value)
    if value == nil then
        return "(not available)"
    end

    if type(value) == "table" then
        return mp_utils.format_json(value)
    end

    return tostring(value)
end

-- Returns true when mpv knows a command with the given name, which tells
-- us whether this mpv version is new enough for a feature.
local function mpv_has_command(command_name)
    local all_commands = mp.get_property_native("command-list") or {}

    for _, command in ipairs(all_commands) do
        if command.name == command_name then
            return true
        end
    end

    return false
end

-- HDR output is active when mpv sends a PQ or HLG signal to the display.
local function is_hdr_output_active(target_params)
    if target_params == nil then
        return false
    end

    return target_params.gamma == "pq" or target_params.gamma == "hlg"
end

-- Passthrough is active when the audio leaves mpv still encoded, which
-- mpv reports as an output format starting with "spdif".
local function is_passthrough_active(audio_output_params)
    if audio_output_params == nil or audio_output_params.format == nil then
        return false
    end

    return audio_output_params.format:find("^spdif") ~= nil
end

-- Formats a yes/no answer with a short explanation for the summary.
local function answer(is_yes, yes_text, no_text)
    if is_yes then
        return "YES  " .. yes_text
    end

    return "NO   " .. no_text
end

local function write_report()
    if has_written_report then
        return
    end
    has_written_report = true

    local video_params = mp.get_property_native("video-params")
    local target_params = mp.get_property_native("video-target-params")
    local audio_output_params = mp.get_property_native("audio-out-params")
    local display_names = mp.get_property_native("display-names") or {}
    local hardware_decoder = mp.get_property("hwdec-current", "no")

    local is_hdr_source = video_params ~= nil
        and (video_params.gamma == "pq" or video_params.gamma == "hlg")
    local is_hardware_decoding = hardware_decoder ~= "no" and hardware_decoder ~= ""

    local hdr_source_answer = answer(
        is_hdr_source,
        "the file is HDR",
        "the file is SDR, so HDR output can't be tested with it"
    )
    local hdr_output_answer = answer(
        is_hdr_output_active(target_params),
        "mpv is sending HDR to the display",
        "mpv is sending SDR (check that HDR is on in display settings)"
    )
    local decoding_answer = answer(
        is_hardware_decoding,
        "using " .. hardware_decoder,
        "decoding on the CPU"
    )
    local passthrough_answer = answer(
        is_passthrough_active(audio_output_params),
        "audio is sent to the receiver untouched",
        "audio is decoded by mpv"
    )
    local display_names_answer = answer(
        #display_names > 0,
        table.concat(display_names, ", "),
        "mpv can't see the display connector name"
    )
    local dragging_answer = answer(
        mpv_has_command("begin-vo-dragging"),
        "this mpv supports begin-vo-dragging",
        "this mpv is too old for begin-vo-dragging"
    )

    local lines = {
        "== Summary ==",
        "HDR source file:     " .. hdr_source_answer,
        "HDR output active:   " .. hdr_output_answer,
        "Hardware decoding:   " .. decoding_answer,
        "Audio passthrough:   " .. passthrough_answer,
        "Display names found: " .. display_names_answer,
        "Window dragging:     " .. dragging_answer,
        "",
        "== Details ==",
        "mpv version:         " .. describe(mp.get_property("mpv-version")),
        "Video output:        " .. describe(mp.get_property("current-vo")),
        "GPU API:             " .. describe(mp.get_property("current-gpu-context")),
        "Video codec:         " .. describe(mp.get_property("video-codec")),
        "Video params:        " .. describe(video_params),
        "Video target params: " .. describe(target_params),
        "Display refresh:     " .. describe(mp.get_property("display-fps")),
        "Audio codec:         " .. describe(mp.get_property("audio-codec-name")),
        "Audio params:        " .. describe(mp.get_property_native("audio-params")),
        "Audio output params: " .. describe(audio_output_params),
        "Audio device:        " .. describe(mp.get_property("audio-device")),
        "Dropped frames:      " .. describe(mp.get_property("frame-drop-count")),
        "",
        "== Audio devices mpv can see ==",
    }

    for _, device in ipairs(mp.get_property_native("audio-device-list") or {}) do
        local description = device.description or "no description"
        table.insert(lines, device.name .. "  (" .. description .. ")")
    end

    local report_file = io.open(settings.report, "a")
    if report_file == nil then
        mp.msg.error("Couldn't write the report to " .. settings.report)
    else
        report_file:write(table.concat(lines, "\n"), "\n")
        report_file:close()
    end

    mp.command("quit")
end

-- "playback-restart" fires once the first frame is actually shown,
-- which is a better starting point than when the file merely opens.
mp.register_event("playback-restart", function()
    mp.add_timeout(SECONDS_TO_PLAY_BEFORE_CHECKING, write_report)
end)

-- If the video is shorter than the wait time, still write what we can
-- before mpv closes.
mp.register_event("end-file", write_report)
