-- Works out what the info panel says. See docs/plan.md, 5.5.
--
-- Each row of the panel has a short headline people can take in at a
-- glance, like "4K HDR10", and a quieter technical line underneath with
-- the specifics, like "HEVC · 3840×2160 · 60 fps · 10-bit".
--
-- This file only turns mpv's properties into words. info_panel.lua
-- decides how they look on screen.

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
local function join(parts)
    local present = {}
    for _, part in ipairs(parts) do
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
--        and 8.2 to SDR. The fallback's brightness curve says which.
local function describe_dolby_vision(track, transfer)
    local profile = track["dolby-vision-profile"]
    if profile == nil then
        return nil, nil
    end

    if profile == 7 then
        return "Dolby Vision (HDR10 base layer)", "Profile 7"
    end

    if profile == 8 then
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

    local dynamic_range, dolby_vision_profile = describe_dolby_vision(track, video.gamma)
    if dynamic_range == nil then
        dynamic_range = describe_dynamic_range(video.gamma)
    end

    return {
        icon = "movie",
        headline = describe_resolution(width, height) .. " " .. dynamic_range,
        details = join({
            dolby_vision_profile,
            codec,
            string.format("%d×%d", width, height),
            describe_frame_rate(),
            describe_bit_depth(video),
        }),
    }
end

-- Describes channels the way they're usually written: "7.1", "5.1",
-- "Stereo", or "Mono".
local function describe_channels(track)
    local count = track["demux-channel-count"]

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
    if count then
        return count .. " channels"
    end
    return nil
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

-- A first, simple status row. Phase 3, step 3 turns this into the full
-- "Playing smoothly" status line.
function info_details.status()
    local headline = "Playing"
    if mp.get_property_bool("pause", false) then
        headline = "Paused"
    end

    local decoder = mp.get_property("hwdec-current", "")
    local decoding = "Software decoding"
    if decoder ~= "" and decoder ~= "no" then
        decoding = "Hardware decoding (" .. decoder .. ")"
    end

    local dropped = mp.get_property_number("frame-drop-count", 0)
    local dropped_text = string.format("%d dropped", dropped)

    return {
        dot = true,
        headline = headline,
        details = join({ decoding, dropped_text }),
    }
end

-- Returns every row that applies to the current file, in order.
function info_details.rows()
    local rows = {}
    for _, describe in ipairs({
        info_details.video,
        info_details.audio,
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
