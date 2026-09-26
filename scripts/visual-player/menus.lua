-- Visual Player's two menus, both opened from the tools row:
--
--   "Audio & subtitles", from the CC button: every audio track and every
--   subtitle track, to pick from. The c and a keys still cycle quickly.
--
--   "Chapters & playlist", from the menu button or the m key: jump to a
--   chapter, or to another file when more than one is open.
--
-- See docs/plan.md, Phase 5, step 1. The popup itself is list_menu.lua.

local info_details = require("info_details")
local list_menu = require("list_menu")
local time_format = require("time_format")

local menus = {}

local function tracks_of_type(track_type)
    local tracks = {}
    for _, track in ipairs(mp.get_property_native("track-list") or {}) do
        if track.type == track_type then
            table.insert(tracks, track)
        end
    end
    return tracks
end

-- Joins the parts that exist with " · ".
local function join(parts)
    local present = {}
    for index = 1, table.maxn(parts) do
        if parts[index] and parts[index] ~= "" then
            table.insert(present, parts[index])
        end
    end
    return table.concat(present, " · ")
end

-- What to call a track: its language if known, otherwise its title,
-- otherwise its number. An external subtitle file's title is its file
-- name, so the extension is dropped.
local function name_track(track, number, kind)
    local language = info_details.describe_language(track.lang)
    if language then
        return language
    end

    local title = track.title
    if title and track.external then
        title = title:gsub("%.%w+$", "")
    end
    if title and title ~= "" then
        return title
    end

    return kind .. " " .. number
end

local function audio_items()
    local items = {}

    for number, track in ipairs(tracks_of_type("audio")) do
        local format, short_codec = info_details.describe_audio_format(track)
        local details = format
        if short_codec and not format:find(short_codec, 1, true) then
            details = format .. " · " .. short_codec
        end

        table.insert(items, {
            label = name_track(track, number, "Track"),
            details = details,
            is_current = track.selected,
            action = function()
                mp.set_property_number("aid", track.id)
            end,
        })
    end

    return items
end

local function subtitle_items()
    local tracks = tracks_of_type("sub")
    local current_id = mp.get_property("sid", "no")

    local items = {
        {
            label = "Off",
            is_current = current_id == "no",
            action = function()
                mp.set_property("sid", "no")
            end,
        },
    }

    if #tracks == 0 then
        table.insert(items, { label = "None in this file", is_disabled = true })
        return items
    end

    for number, track in ipairs(tracks) do
        local flags = {}
        if track.forced then
            table.insert(flags, "Forced")
        end
        if track["hearing-impaired"] then
            table.insert(flags, "SDH")
        end
        if track.external then
            table.insert(flags, "External")
        end

        table.insert(items, {
            label = name_track(track, number, "Subtitle"),
            details = join({
                info_details.describe_subtitle_format(track),
                table.concat(flags, " · "),
            }),
            is_current = track.selected,
            action = function()
                mp.set_property_number("sid", track.id)
            end,
        })
    end

    return items
end

local function audio_and_subtitle_sections()
    local sections = {}

    local audio = audio_items()
    if #audio > 0 then
        table.insert(sections, { heading = "Audio", items = audio })
    end
    table.insert(sections, { heading = "Subtitles", items = subtitle_items() })

    return sections
end

local function chapter_items()
    local chapters = mp.get_property_native("chapter-list") or {}
    local current = mp.get_property_number("chapter", -1)
    local include_hours = (mp.get_property_number("duration", 0) or 0) >= 3600

    local items = {}
    for index, chapter in ipairs(chapters) do
        local title = chapter.title
        if title == nil or title == "" then
            title = "Chapter " .. index
        end

        table.insert(items, {
            label = title,
            details = time_format.clock(chapter.time, include_hours),
            -- mpv counts chapters from 0, Lua lists from 1.
            is_current = index - 1 == current,
            action = function()
                mp.set_property_number("chapter", index - 1)
            end,
        })
    end
    return items
end

-- Names a playlist entry by its title, or its file name without the
-- folder or extension.
local function name_playlist_entry(entry)
    if entry.title and entry.title ~= "" then
        return entry.title
    end
    local file_name = (entry.filename or ""):match("([^/]+)$") or entry.filename or ""
    return (file_name:gsub("%.%w+$", ""))
end

local function playlist_items()
    local items = {}
    for index, entry in ipairs(mp.get_property_native("playlist") or {}) do
        table.insert(items, {
            label = name_playlist_entry(entry),
            is_current = entry.current == true,
            action = function()
                -- mpv counts playlist entries from 0, Lua lists from 1.
                mp.commandv("playlist-play-index", tostring(index - 1))
            end,
        })
    end
    return items
end

local function chapter_and_playlist_sections()
    local sections = {}

    local chapters = chapter_items()
    if #chapters > 0 then
        table.insert(sections, { heading = "Chapters", items = chapters })
    end

    -- A playlist of one file isn't worth listing.
    local playlist = playlist_items()
    if #playlist > 1 then
        table.insert(sections, { heading = "Playlist", items = playlist })
    end

    if #sections == 0 then
        table.insert(sections, {
            heading = "Chapters & playlist",
            items = { { label = "This file has no chapters", is_disabled = true } },
        })
    end

    return sections
end

local audio_and_subtitles_menu = list_menu.create(
    "audio-and-subtitles",
    audio_and_subtitle_sections
)
local chapters_and_playlist_menu = list_menu.create(
    "chapters-and-playlist",
    chapter_and_playlist_sections
)

-- Opening either menu closes any other popup first (see popups.lua).
-- The side says where the button that opened it is: "left" for the CC
-- button, "right" for the audio chip.
function menus.toggle_audio_and_subtitles(side)
    audio_and_subtitles_menu.toggle(side)
end

function menus.toggle_chapters_and_playlist()
    chapters_and_playlist_menu.toggle()
end

function menus.is_any_open()
    return audio_and_subtitles_menu.is_open() or chapters_and_playlist_menu.is_open()
end

-- Tells both menus where the top of the bottom controls is, and where
-- their left and right edges are, so they sit just above them.
function menus.place_above(controls_top, left_edge, right_edge)
    audio_and_subtitles_menu.place_above(controls_top, left_edge, right_edge)
    chapters_and_playlist_menu.place_above(controls_top, left_edge, right_edge)
end

function menus.start()
    -- Named so input.conf can bind a key to it:
    --   m  script-binding visual_player/toggle-chapters-and-playlist
    mp.add_key_binding(
        nil,
        "toggle-chapters-and-playlist",
        menus.toggle_chapters_and_playlist
    )
    mp.add_key_binding(nil, "toggle-audio-and-subtitles", menus.toggle_audio_and_subtitles)
end

return menus
