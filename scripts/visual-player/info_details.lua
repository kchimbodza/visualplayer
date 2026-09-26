-- Works out what the info panel says. See docs/plan.md, 5.5.
--
-- Each row of the panel has a short headline people can take in at a
-- glance, like "4K HDR10", and a quieter technical line underneath with
-- the specifics, like "HEVC · 3840×2160 · 60 fps · 10-bit".
--
-- This file only turns mpv's properties into words. info_panel.lua
-- decides how they look on screen.

local audio_output = require("outputs.audio")
local display_output = require("outputs.display")

local info_details = {}

-- Friendlier names for the codec names mpv uses.
local VIDEO_CODEC_NAMES = {
    hevc = "HEVC",
    h264 = "H.264",
    av1 = "AV1",
    vp9 = "VP9",
    vp8 = "VP8",
    mpeg2video = "MPEG-2",
    mpeg4 = "MPEG-4",
    vc1 = "VC-1",
    prores = "ProRes",
}

local AUDIO_CODEC_NAMES = {
    truehd = "TrueHD",
    eac3 = "Dolby Digital Plus",
    ac3 = "Dolby Digital",
    dts = "DTS",
    aac = "AAC",
    flac = "FLAC",
    opus = "Opus",
    vorbis = "Vorbis",
    mp3 = "MP3",
    alac = "ALAC",
    pcm_s16le = "PCM",
    pcm_s24le = "PCM",
}

-- Shorter codec names for the technical line, where space is tight.
local AUDIO_CODEC_SHORT_NAMES = {
    eac3 = "E-AC-3",
    ac3 = "AC-3",
}

local SUBTITLE_FORMAT_NAMES = {
    subrip = "SRT",
    ass = "ASS",
    ssa = "SSA",
    hdmv_pgs_subtitle = "PGS",
    dvd_subtitle = "VobSub",
    webvtt = "WebVTT",
    mov_text = "Text",
    dvb_subtitle = "DVB",
}

-- The languages most likely to appear. Anything else shows its code.
local LANGUAGE_NAMES = {
    eng = "English", en = "English",
    fra = "French", fre = "French", fr = "French",
    spa = "Spanish", es = "Spanish",
    deu = "German", ger = "German", de = "German",
    ita = "Italian", it = "Italian",
    por = "Portuguese", pt = "Portuguese",
    jpn = "Japanese", ja = "Japanese",
    kor = "Korean", ko = "Korean",
    zho = "Chinese", chi = "Chinese", zh = "Chinese",
    rus = "Russian", ru = "Russian",
    hin = "Hindi", hi = "Hindi",
    ara = "Arabic", ar = "Arabic",
    nld = "Dutch", dut = "Dutch", nl = "Dutch",
    swe = "Swedish", sv = "Swedish",
    pol = "Polish", pl = "Polish",
    tur = "Turkish", tr = "Turkish",
}

-- Joins the parts that exist with " · ", skipping any that are missing.
--
-- This checks every position up to the last one filled in. A plain
-- ipairs loop would stop at the first missing part, which blanked whole
-- lines whenever the first part was missing, like the Dolby Vision
-- profile on files without Dolby Vision (found in Phase 4, step 2).
local function join(parts)
    local present = {}
    for index = 1, table.maxn(parts) do
        local part = parts[index]
        if part and part ~= "" then
            table.insert(present, part)
        end
    end
    return table.concat(present, " · ")
end

local function describe_language(code)
    if code == nil or code == "" or code == "und" then
        return nil
    end
    return LANGUAGE_NAMES[code:lower()] or code:upper()
end

-- The everyday name for a resolution. Width counts as much as height,
-- because wide films are often 3840 pixels wide but only 1600 tall, and
-- still count as 4K.
local function describe_resolution(width, height)
    if width >= 3200 or height >= 2000 then
        return "4K"
    end
    if width >= 2400 or height >= 1400 then
        return "1440p"
    end
    if width >= 1800 or height >= 1000 then
        return "1080p"
    end
    if width >= 1200 or height >= 700 then
        return "720p"
    end
    return "SD"
end

-- Describes the picture's brightness range from its brightness curve.
-- Always from the file itself, never from what's sent to the screen, so
-- an SDR file isn't called HDR when the screen is in HDR mode.
--
-- HDR10+ files show as "HDR10": mpv doesn't report whether HDR10+'s
-- extra information is present (checked in Phase 3, step 2), and it's
-- better to say "HDR10" accurately than to guess.
local function describe_dynamic_range(transfer)
    if transfer == "pq" then
        return "HDR10"
    end
    if transfer == "hlg" then
        return "HLG"
    end
    return "SDR"
end

-- Describes Dolby Vision, if the video has it. Returns the name for the
-- headline and the profile for the technical line, or nil for both if
-- the video isn't Dolby Vision.
--
-- The profile says how the picture is stored, which changes what can
-- honestly be claimed:
--   5    Dolby Vision only, with no fallback. mpv plays it in full.
--   7    Two layers, from UHD Blu-rays. mpv only plays the HDR10 base
--        layer, so it's labelled as such (confirmed in Phase 0).
--   8    One layer with a fallback: 8.1 falls back to HDR10, 8.4 to HLG,
--        and 8.2 to SDR. The fallback's brightness curve says which, but
--        only while it's still visible. When mpv applies the Dolby Vision
--        information, it converts the picture to PQ and marks its color
--        matrix "dolbyvision", so the original curve is gone (found in
--        Phase 4, step 2: Jellyfish, profile 8.4, showed as 8.1). Then
--        it's just "Profile 8", rather than a guess.
local function describe_dolby_vision(track, video)
    local profile = track["dolby-vision-profile"]
    local transfer = video.gamma
    if profile == nil then
        return nil, nil
    end

    if profile == 7 then
        return "Dolby Vision (HDR10 base layer)", "Profile 7"
    end

    if profile == 8 then
        if video.colormatrix == "dolbyvision" then
            return "Dolby Vision", "Profile 8"
        end
        if transfer == "pq" then
            return "Dolby Vision", "Profile 8.1"
        end
        if transfer == "hlg" then
            return "Dolby Vision", "Profile 8.4"
        end
        return "Dolby Vision", "Profile 8.2"
    end

    return "Dolby Vision", "Profile " .. profile
end

-- Works out bit depth from the pixel format mpv decodes into. "p010" and
-- similar mean 10-bit; plain formats like "nv12" mean 8-bit.
local function describe_bit_depth(video)
    local format = video["hw-pixelformat"] or video.pixelformat or ""

    if format:find("p010") or format:find("10") then
        return "10-bit"
    end
    if format:find("p012") or format:find("12") then
        return "12-bit"
    end
    if format ~= "" then
        return "8-bit"
    end
    return nil
end

local function describe_frame_rate()
    local fps = mp.get_property_number("container-fps")
        or mp.get_property_number("estimated-vf-fps")

    if fps == nil or fps <= 0 then
        return nil
    end

    -- Show whole numbers as "60 fps", and film rates as "23.976 fps".
    if math.abs(fps - math.floor(fps + 0.5)) < 0.01 then
        return string.format("%d fps", math.floor(fps + 0.5))
    end
    return string.format("%.3f fps", fps)
end

local function is_hdr_transfer(transfer)
    return transfer == "pq" or transfer == "hlg"
end

-- True when an HDR file is being shown on a screen that isn't in HDR
-- mode, so mpv converts it to SDR. That's normal, not a problem, and
-- worth saying plainly (Phase 0, Omarchy).
local function is_tone_mapped_to_sdr(source_transfer)
    if not is_hdr_transfer(source_transfer) then
        return false
    end

    local output = mp.get_property_native("video-target-params")
    if output == nil or output.gamma == nil or output.gamma == "auto" then
        return false
    end

    return not is_hdr_transfer(output.gamma)
end

-- Returns the video row, or nil if the file has no picture.
function info_details.video()
    local video = mp.get_property_native("video-params")
    local track = mp.get_property_native("current-tracks/video")

    if video == nil or track == nil or track.image then
        return nil
    end

    local width = video.dw or video.w or 0
    local height = video.dh or video.h or 0
    local codec = VIDEO_CODEC_NAMES[track.codec] or (track.codec or ""):upper()

    local dynamic_range, dolby_vision_profile = describe_dolby_vision(track, video)
    if dynamic_range == nil then
        dynamic_range = describe_dynamic_range(video.gamma)
    end

    local tone_mapping = nil
    if is_tone_mapped_to_sdr(video.gamma) then
        tone_mapping = "Tone mapped to SDR"
    end

    return {
        icon = "movie",
        headline = describe_resolution(width, height) .. " " .. dynamic_range,
        details = join({
            dolby_vision_profile,
            tone_mapping,
            codec,
            string.format("%d×%d", width, height),
            describe_frame_rate(),
            describe_bit_depth(video),
        }),
    }
end

-- Describes a number of channels the way it's usually written: "7.1",
-- "5.1", "Stereo", or "Mono".
local function channel_name(count)
    if count == nil then
        return nil
    end
    if count == 8 then
        return "7.1"
    end
    if count == 6 then
        return "5.1"
    end
    if count == 2 then
        return "Stereo"
    end
    if count == 1 then
        return "Mono"
    end
    return count .. " channels"
end

local function describe_channels(track)
    return channel_name(track["demux-channel-count"])
end

-- True if the track carries Dolby Atmos. mpv reports this in the codec
-- profile, like "Dolby TrueHD + Dolby Atmos".
local function has_atmos(track)
    local profile = track["codec-profile"] or ""
    return profile:find("Atmos") ~= nil
end

-- The codec's full name for the headline. For DTS, the profile says which
-- kind, such as "DTS-HD MA", which matters more than plain "DTS".
local function describe_audio_codec(track)
    local profile = track["codec-profile"] or ""
    if track.codec == "dts" and profile ~= "" then
        return profile
    end
    return AUDIO_CODEC_NAMES[track.codec] or (track.codec or ""):upper()
end

-- Returns the audio row, or nil if nothing is playing any sound.
function info_details.audio()
    local track = mp.get_property_native("current-tracks/audio")
    if track == nil then
        return nil
    end

    local codec = describe_audio_codec(track)
    local channels = describe_channels(track)

    -- The channels belong with the format name, like "Dolby Atmos 5.1",
    -- so they're joined with a space rather than " · ".
    local headline = codec
    if has_atmos(track) then
        headline = "Dolby Atmos"
    end
    if channels then
        headline = headline .. " " .. channels
    end

    local short_codec = AUDIO_CODEC_SHORT_NAMES[track.codec] or codec
    local sample_rate = nil
    if track["demux-samplerate"] then
        sample_rate = string.format("%g kHz", track["demux-samplerate"] / 1000)
    end

    return {
        icon = "volume",
        headline = headline,
        details = join({ short_codec, sample_rate, describe_language(track.lang) }),
    }
end

-- What to call each kind of output on the Output row, and its icon.
local OUTPUT_KIND_NAMES = {
    hdmi = "HDMI",
    displayport = "DisplayPort",
    usb = "USB audio",
    bluetooth = "Bluetooth",
}

local OUTPUT_ICONS = {
    hdmi = "device-tv",
    displayport = "device-desktop",
    usb = "usb",
    speakers = "device-laptop",
    bluetooth = "bluetooth",
}

-- Says what happens to the sound on its way out, in plain words.
--
-- mpv can't see downmixing: it hands PipeWire all the file's channels,
-- and PipeWire squeezes them into however many the output takes (found
-- in Phase 0). So the file's channels are compared with the fewest
-- channels anywhere along the way: what mpv sends, and what the output
-- accepts.
local function describe_sound_path(output)
    local track = mp.get_property_native("current-tracks/audio")
    local sent = mp.get_property_native("audio-out-params") or {}

    -- Passthrough sends the audio untouched, for a receiver to decode.
    if (sent.format or ""):find("^spdif") then
        return "Passthrough"
    end

    local in_file = track and track["demux-channel-count"]
    if in_file == nil then
        return nil
    end

    local fewest = in_file
    for _, count in ipairs({ sent["channel-count"], output.channels }) do
        if count and count < fewest then
            fewest = count
        end
    end

    if fewest < in_file then
        return channel_name(fewest) .. " downmix from " .. channel_name(in_file)
    end

    if in_file <= 2 then
        return channel_name(in_file)
    end
    return "Full " .. channel_name(in_file)
end

-- Returns the Output row: where the sound is going and what happens to
-- it on the way. Nil if the output isn't known yet, or there's no sound.
function info_details.output()
    local output = audio_output.current()
    if output == nil or mp.get_property_native("current-tracks/audio") == nil then
        return nil
    end

    local kind = OUTPUT_KIND_NAMES[output.kind] or "Output"
    if output.kind == "bluetooth" and output.codec then
        kind = kind .. " " .. output.codec
    end

    -- "Built-in speakers" already says what it is, so don't repeat it.
    if output.kind == "speakers" then
        kind = nil
    end

    return {
        icon = OUTPUT_ICONS[output.kind] or "volume",
        headline = output.name,
        details = join({ kind, describe_sound_path(output) }),
    }
end

local SCREEN_KIND_NAMES = {
    hdmi = "HDMI",
    displayport = "DisplayPort",
    ["usb-c"] = "USB-C DisplayPort",
}

local SCREEN_ICONS = {
    ["built-in"] = "device-laptop",
    hdmi = "device-tv",
    displayport = "device-desktop",
    ["usb-c"] = "usb",
}

-- Shows a refresh rate as "240 Hz", or "59.94 Hz" when it isn't whole.
local function describe_refresh(refresh)
    if refresh == nil or refresh <= 0 then
        return nil
    end
    local rounded = math.floor(refresh + 0.5)
    if math.abs(refresh - rounded) < 0.05 then
        return rounded .. " Hz"
    end
    return string.format("%.2f Hz", refresh)
end

-- Returns the Screen row: which screen the picture is on, how it's
-- connected, its mode, and whether HDR is on. Nil until mpv says which
-- screen it is, or for files without a picture.
function info_details.screen()
    local screen = display_output.current()
    if screen == nil or mp.get_property_native("current-tracks/video") == nil then
        return nil
    end

    local resolution = nil
    if screen.width and screen.height and screen.width > 0 then
        resolution = string.format("%d×%d", screen.width, screen.height)
    end

    local dynamic_range = "SDR"
    if screen.is_hdr then
        dynamic_range = "HDR"
    end

    return {
        icon = SCREEN_ICONS[screen.kind] or "device-desktop",
        headline = screen.name,
        details = join({
            SCREEN_KIND_NAMES[screen.kind],
            resolution,
            describe_refresh(screen.refresh),
            dynamic_range,
        }),
    }
end

local function subtitle_tracks()
    local tracks = {}
    for _, track in ipairs(mp.get_property_native("track-list") or {}) do
        if track.type == "sub" then
            table.insert(tracks, track)
        end
    end
    return tracks
end

-- Returns the subtitles row, or nil if the file has no subtitles at all.
function info_details.subtitles()
    local tracks = subtitle_tracks()
    if #tracks == 0 then
        return nil
    end

    local current = mp.get_property_native("current-tracks/sub")
    if current == nil then
        local available = string.format("%d available", #tracks)
        if #tracks == 1 then
            available = "1 available"
        end
        return { icon = "badge-cc", headline = "Off", details = available }
    end

    local position = 1
    for index, track in ipairs(tracks) do
        if track.id == current.id then
            position = index
        end
    end

    -- An external subtitle file's title is its file name. Drop the
    -- extension, the same way the top bar does for titles.
    local title = current.title
    if title and current.external then
        title = title:gsub("%.%w+$", "")
    end

    local headline = describe_language(current.lang) or title or "On"
    local format = SUBTITLE_FORMAT_NAMES[current.codec] or (current.codec or ""):upper()

    return {
        icon = "badge-cc",
        headline = headline,
        details = join({ format, string.format("track %d of %d", position, #tracks) }),
    }
end

-- The status row: a colored dot and a plain-language summary of how
-- playback is going, with the reason underneath when something's wrong.
-- See docs/plan.md, 5.5, and the frame timing findings from Phase 0.

local SMOOTH_COLOR = "#5DCAA5"
local WARNING_COLOR = "#EF9F27"
local PROBLEM_COLOR = "#E24B4A"
local PAUSED_COLOR = "#9A9A9A"

-- Dropped frames are judged over the last few seconds, not the whole
-- file, so one bad moment, like a seek or a window drag, clears on its
-- own. A couple of drops now and then are normal and not worth a
-- warning.
local SECONDS_OF_HISTORY = 5
local DROPS_BEFORE_WARNING = 2

-- When rendering a frame takes more than this share of the time
-- available for it, the graphics are the likely cause of drops.
local BUSY_GRAPHICS_SHARE = 0.8

-- Frame counters sampled once a second, newest last.
local counter_history = {}

local function read_counters()
    return {
        decoder_drops = mp.get_property_number("decoder-frame-drop-count", 0),
        output_drops = mp.get_property_number("frame-drop-count", 0),
    }
end

local function sample_counters()
    table.insert(counter_history, read_counters())
    while #counter_history > SECONDS_OF_HISTORY + 1 do
        table.remove(counter_history, 1)
    end
end

-- How many frames were dropped over the last few seconds, by the decoder
-- and on the way to the screen.
local function recent_drops()
    local newest = read_counters()
    local oldest = counter_history[1] or newest
    return newest.decoder_drops - oldest.decoder_drops, newest.output_drops - oldest.output_drops
end

-- How long rendering one frame takes on average, in milliseconds, from
-- mpv's per-pass timings, which are in nanoseconds. Returns nil if mpv
-- hasn't measured any yet.
local function render_time_ms()
    local passes = mp.get_property_native("vo-passes")
    if passes == nil or passes.fresh == nil or #passes.fresh == 0 then
        return nil
    end

    local total = 0
    for _, pass in ipairs(passes.fresh) do
        total = total + (pass.avg or 0)
    end
    return total / 1e6
end

-- The time available to render each frame, in milliseconds: one frame's
-- worth of the video's frame rate.
local function frame_budget_ms()
    local fps = mp.get_property_number("container-fps")
        or mp.get_property_number("estimated-vf-fps")
    if fps == nil or fps <= 0 then
        return nil
    end
    return 1000 / fps
end

-- Shows a bitrate the way people usually write it: "58.6 Mb/s", or
-- "320 kb/s" for anything under a megabit.
local function describe_bitrate(bits_per_second)
    if bits_per_second >= 1e6 then
        return string.format("%.1f Mb/s", bits_per_second / 1e6)
    end
    return string.format("%d kb/s", math.floor(bits_per_second / 1000))
end

-- The average bitrate most MKV files record for their video track, when
-- they were made with mkvmerge (found in Phase 3, step 2). The tag may
-- carry a language suffix, like "BPS-eng".
local function recorded_video_bitrate()
    local track = mp.get_property_native("current-tracks/video")
    if track == nil or track.metadata == nil then
        return nil
    end
    return tonumber(track.metadata.BPS or track.metadata["BPS-eng"])
end

-- Where the file is coming from. Local files show their container and
-- recorded bitrate, like "MKV · 58.6 Mb/s". Streams show their format,
-- the bitrate right now, and how much is buffered ahead.
local function describe_source()
    if mp.get_property_bool("demuxer-via-network", false) then
        local format = (mp.get_property("file-format", ""):match("^[^,]+") or ""):upper()
        if format == "" then
            format = "Stream"
        end

        local bitrate = mp.get_property_number("video-bitrate")
        local buffered = mp.get_property_number("demuxer-cache-duration")

        local bitrate_text = nil
        if bitrate and bitrate > 0 then
            bitrate_text = describe_bitrate(bitrate)
        end

        local buffered_text = nil
        if buffered then
            buffered_text = string.format("%d s buffered", math.floor(buffered))
        end

        return join({ format, bitrate_text, buffered_text })
    end

    local extension = mp.get_property("filename", ""):match("%.(%w+)$")
    local bitrate = recorded_video_bitrate()

    local bitrate_text = nil
    if bitrate and bitrate > 0 then
        bitrate_text = describe_bitrate(bitrate)
    end

    local container = nil
    if extension then
        container = extension:upper()
    end

    return join({ container, bitrate_text })
end

local function describe_decoding()
    local decoder = mp.get_property("hwdec-current", "")
    if decoder ~= "" and decoder ~= "no" then
        return "Hardware decoding (" .. decoder .. ")"
    end
    return "Software decoding"
end

-- Explains why frames are being dropped, in plain words.
local function describe_drop_cause(decoder_drops, output_drops)
    local dropped = string.format(
        "%d dropped in %d s",
        decoder_drops + output_drops,
        SECONDS_OF_HISTORY
    )

    if decoder_drops > 0 then
        return join({ "Decoding can't keep up", describe_decoding(), dropped })
    end

    local render_ms = render_time_ms()
    local budget_ms = frame_budget_ms()
    if render_ms and budget_ms and render_ms > budget_ms * BUSY_GRAPHICS_SHARE then
        local timing = string.format("%.1f of %.1f ms per frame", render_ms, budget_ms)
        return join({ "Graphics can't keep up", timing, dropped })
    end

    -- Rendering is quick, yet frames still miss their moment on screen.
    -- Phase 0 traced this to the screen's refresh timing.
    return join({ "Screen timing is uneven", dropped })
end

function info_details.status()
    if mp.get_property_bool("paused-for-cache", false) then
        local filled = mp.get_property_number("cache-buffering-state", 0)
        return {
            dot = true,
            dot_color = PROBLEM_COLOR,
            headline = "Buffering",
            details = string.format("Waiting for the stream · %d%% ready", filled),
        }
    end

    local total_dropped = string.format(
        "%d dropped",
        mp.get_property_number("frame-drop-count", 0)
            + mp.get_property_number("decoder-frame-drop-count", 0)
    )

    if mp.get_property_bool("pause", false) then
        return {
            dot = true,
            dot_color = PAUSED_COLOR,
            headline = "Paused",
            details = join({ describe_decoding(), total_dropped, describe_source() }),
        }
    end

    local decoder_drops, output_drops = recent_drops()
    if decoder_drops + output_drops > DROPS_BEFORE_WARNING then
        return {
            dot = true,
            dot_color = WARNING_COLOR,
            headline = "Dropping frames",
            details = describe_drop_cause(decoder_drops, output_drops),
        }
    end

    return {
        dot = true,
        dot_color = SMOOTH_COLOR,
        headline = "Playing smoothly",
        details = join({ describe_decoding(), total_dropped, describe_source() }),
    }
end

-- Starts sampling the frame counters, so the status is accurate as soon
-- as the panel opens.
function info_details.start()
    mp.add_periodic_timer(1, sample_counters)

    -- A new file starts its counters from zero, so start the history
    -- afresh too.
    mp.register_event("file-loaded", function()
        counter_history = {}
    end)
end

-- Returns every row that applies to the current file, in order.
function info_details.rows()
    local rows = {}
    for _, describe in ipairs({
        info_details.video,
        info_details.screen,
        info_details.audio,
        info_details.output,
        info_details.subtitles,
        info_details.status,
    }) do
        local row = describe()
        if row then
            table.insert(rows, row)
        end
    end
    return rows
end

return info_details
