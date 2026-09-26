-- Logs what mpv is doing in plain English.
--
-- Added in Phase 1 to confirm Visual Player is wired up correctly. It
-- stays useful while developing: the terminal shows what the player
-- detected about each file, screen, and audio output.

local playback_log = {}

-- How long the list of screens must stay the same before we report it.
-- While a window is moved or resized, the compositor can report it
-- entering and leaving screens many times a second.
local SCREEN_CHANGE_SETTLE_SECONDS = 1

-- True between a file finishing loading and it closing. Outside that
-- window, mpv's properties are empty or half-filled, so we ignore them.
local is_file_loaded = false

-- Remembers whether the current file is HDR, so we can tell when an HDR
-- file is being tone mapped for an SDR screen.
local is_source_hdr = false

-- The last message logged for each topic, so the same thing isn't
-- repeated every time mpv updates a property with an unchanged value.
local last_message_for_topic = {}

-- Logs a message, but only while a file is loaded, and only if it's
-- different from the last one logged for the same topic.
local function log_if_changed(topic, message)
    if not is_file_loaded then
        return
    end

    if last_message_for_topic[topic] == message then
        return
    end

    last_message_for_topic[topic] = message
    mp.msg.info(message)
end

-- mpv uses "auto" or leaves the value empty until it has worked out the
-- video's brightness curve.
local function is_transfer_known(transfer)
    return transfer ~= nil and transfer ~= "" and transfer ~= "auto"
end

local function is_hdr(transfer)
    return transfer == "pq" or transfer == "hlg"
end

-- Turns mpv's short names for brightness curves into familiar words.
local function describe_transfer(transfer)
    if transfer == "pq" then
        return "HDR (PQ)"
    end

    if transfer == "hlg" then
        return "HDR (HLG)"
    end

    return "SDR"
end

local function on_title_changed(_, title)
    if title then
        log_if_changed("title", "Now playing: " .. title)
    end
end

-- Describes the file's own video format. This comes from the source, not
-- the output, so an SDR file is never mislabeled as HDR on an HDR screen.
local function on_source_video_changed(_, video)
    if video == nil or not is_transfer_known(video.gamma) then
        return
    end

    is_source_hdr = is_hdr(video.gamma)

    log_if_changed(
        "source video",
        string.format("Video: %d×%d, %s", video.w, video.h, describe_transfer(video.gamma))
    )
end

-- Describes what's actually being sent to the screen.
local function on_output_video_changed(_, output)
    if output == nil or not is_transfer_known(output.gamma) then
        return
    end

    local message
    if is_hdr(output.gamma) then
        message = "Sending to screen: " .. describe_transfer(output.gamma)
    elseif is_source_hdr then
        message = "Sending to screen: SDR, tone mapped from HDR"
    else
        message = "Sending to screen: SDR"
    end

    log_if_changed("output video", message)
end

local function on_decoder_changed(_, decoder)
    -- An empty value means the decoder hasn't started yet.
    if decoder == nil or decoder == "" then
        return
    end

    if decoder == "no" then
        log_if_changed("decoder", "Decoding: on the CPU")
    else
        log_if_changed("decoder", "Decoding: hardware (" .. decoder .. ")")
    end
end

local function on_audio_track_changed(_, track)
    if track == nil then
        return
    end

    local channel_count = track["demux-channel-count"] or "unknown"
    log_if_changed(
        "audio track",
        string.format("Audio: %s, %s channels", track.codec or "unknown", channel_count)
    )
end

local function on_audio_device_changed(_, device)
    if device then
        log_if_changed("audio device", "Audio output: " .. device)
    end
end

-- Waits for the list of screens to settle before reporting it, and
-- counts how often it changed in the meantime, since frequent changes
-- are worth knowing about.
local screen_settle_timer = nil
local latest_screen_names = {}
local screen_changes_while_settling = 0
local last_reported_screens = nil

local function report_settled_screens()
    if not is_file_loaded then
        return
    end

    local screens = table.concat(latest_screen_names, ", ")
    local change_count = screen_changes_while_settling
    screen_changes_while_settling = 0

    -- Moving a window around and back can settle on the same screens as
    -- before, which isn't worth reporting again.
    if screens == last_reported_screens then
        return
    end
    last_reported_screens = screens

    local message = "Screen: " .. screens
    if change_count > 1 then
        message = message .. string.format(" (after %d changes while settling)", change_count)
    end

    log_if_changed("screen", message)
end

local function on_screens_changed(_, screen_names)
    if screen_names == nil or #screen_names == 0 then
        return
    end

    latest_screen_names = screen_names
    screen_changes_while_settling = screen_changes_while_settling + 1

    if screen_settle_timer then
        screen_settle_timer:kill()
    end
    screen_settle_timer = mp.add_timeout(SCREEN_CHANGE_SETTLE_SECONDS, report_settled_screens)
end

local function on_file_loaded()
    is_file_loaded = true

    -- Start fresh for each file, so its details are all logged again.
    last_message_for_topic = {}
    last_reported_screens = nil

    -- mpv only notifies us when a value changes, and some values were
    -- already set before the file finished loading, while we were
    -- ignoring them. So read everything once now.
    on_title_changed(nil, mp.get_property("media-title"))
    on_source_video_changed(nil, mp.get_property_native("video-params"))
    on_output_video_changed(nil, mp.get_property_native("video-target-params"))
    on_decoder_changed(nil, mp.get_property("hwdec-current"))
    on_audio_track_changed(nil, mp.get_property_native("current-tracks/audio"))
    on_audio_device_changed(nil, mp.get_property("audio-device"))

    local screen_names = mp.get_property_native("display-names") or {}
    if #screen_names > 0 then
        latest_screen_names = screen_names
        report_settled_screens()
    end
end

local function on_file_closed()
    is_file_loaded = false
end

function playback_log.start()
    mp.register_event("file-loaded", on_file_loaded)
    mp.register_event("end-file", on_file_closed)

    mp.observe_property("media-title", "string", on_title_changed)
    mp.observe_property("video-params", "native", on_source_video_changed)
    mp.observe_property("video-target-params", "native", on_output_video_changed)
    mp.observe_property("hwdec-current", "string", on_decoder_changed)
    mp.observe_property("current-tracks/audio", "native", on_audio_track_changed)
    mp.observe_property("audio-device", "string", on_audio_device_changed)
    mp.observe_property("display-names", "native", on_screens_changed)
end

return playback_log
