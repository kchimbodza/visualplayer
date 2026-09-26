-- The track notice: when the audio track changes, a small one-line card
-- appears just above the controls on the left for a few seconds, saying
-- which track it is and what happens to its sound, like
--
--   Audio 2 of 5 · English   Dolby Digital 5.1 · AC-3 · Passthrough
--
-- The first part is in bright text, the rest in quieter text.
--
-- It appears however the track changed: the a key, the menu, or anything
-- else. The controls come up with it, so the audio chip beside the
-- output chip shows the new track too.

local audio_output = require("outputs.audio")
local bottom_controls = require("bottom_controls")
local draw = require("draw")
local info_details = require("info_details")
local menus = require("menus")
local picture_in_picture = require("picture_in_picture")
local redraw = require("redraw")
local screen = require("screen")
local style = require("style")
local visibility = require("visibility")

local track_notice = {}

-- Sizes in design pixels. See screen.lua.
local SIDE_MARGIN = 16
local GAP_ABOVE_CONTROLS = 8
local PADDING_ACROSS = 14
local PADDING_DOWN = 8
local ICON_SIZE = 20
local GAP_AFTER_ICON = 10
local TEXT_SIZE = 15
local GAP_BEFORE_DETAILS = 10
local CORNER_RADIUS = 8

local PANEL_OPACITY = 0.8

local SECONDS_SHOWN = 3
local FADE_SECONDS = 0.4
local FADE_STEPS_PER_SECOND = 30

local canvas = draw.create_canvas({ layer = 2 })
local opacity = 0
local is_fading_in = false
local fade_timer = nil
local hide_timer = nil

-- The track being played when the file started, so the first choice of
-- track isn't announced as a change.
local is_file_starting = true

local function describe_current_track()
    local track = mp.get_property_native("current-tracks/audio")
    local position, count = info_details.audio_track_position()
    if track == nil or position == nil then
        return nil
    end

    local headline = string.format("Audio %d of %d", position, count)
    local language = info_details.describe_language(track.lang)
    if language then
        headline = headline .. " · " .. language
    end

    local format, short_codec = info_details.describe_audio_format(track)
    local parts = { format }
    if short_codec and not format:find(short_codec, 1, true) then
        table.insert(parts, short_codec)
    end
    local output = audio_output.current()
    if output then
        table.insert(parts, info_details.describe_sound_path(output))
    end

    return { headline = headline, details = table.concat(parts, " · ") }
end

local function render()
    if opacity <= 0 or picture_in_picture.is_on() or not screen.is_ready() then
        canvas:clear()
        return
    end

    -- An open menu already shows which track is chosen.
    if menus.is_any_open() then
        canvas:clear()
        return
    end

    local notice = describe_current_track()
    if notice == nil then
        canvas:clear()
        return
    end

    draw.set_overall_opacity(opacity)

    local text_size = screen.pixels(TEXT_SIZE)
    local padding_across = screen.pixels(PADDING_ACROSS)
    local padding_down = screen.pixels(PADDING_DOWN)
    local icon_space = screen.pixels(ICON_SIZE + GAP_AFTER_ICON)
    local gap_before_details = screen.pixels(GAP_BEFORE_DETAILS)

    local headline_width = draw.estimate_text_width(notice.headline, text_size, true)
    local details_width = draw.estimate_text_width(notice.details, text_size)
    local height = padding_down * 2 + math.max(text_size, screen.pixels(ICON_SIZE))

    local left = screen.pixels(SIDE_MARGIN)
    local bottom = bottom_controls.top_edge() - screen.pixels(GAP_ABOVE_CONTROLS)
    local area = {
        left = left,
        top = bottom - height,
        right = left + padding_across * 2 + icon_space
            + headline_width + gap_before_details + details_width,
        bottom = bottom,
    }
    local middle_y = (area.top + area.bottom) / 2

    canvas:add(draw.rectangle({
        area = area,
        color = style.BACKGROUND_COLOR,
        opacity = PANEL_OPACITY,
        corner_radius = screen.pixels(CORNER_RADIUS),
    }))

    canvas:add(draw.icon({
        name = "volume",
        x = area.left + padding_across + screen.pixels(ICON_SIZE) / 2,
        y = middle_y,
        size = screen.pixels(ICON_SIZE),
        color = style.TEXT_COLOR,
    }))

    local text_left = area.left + padding_across + icon_space
    canvas:add(draw.text({
        x = text_left,
        y = middle_y,
        vertical = "middle",
        text = notice.headline,
        size = text_size,
        bold = true,
        color = style.TEXT_COLOR,
    }))
    canvas:add(draw.text({
        x = text_left + headline_width + gap_before_details,
        y = middle_y,
        vertical = "middle",
        text = notice.details,
        size = text_size,
        color = style.MUTED_TEXT_COLOR,
    }))

    canvas:show(screen.width, screen.height)
end

local function step_fade()
    local step = 1 / (FADE_SECONDS * FADE_STEPS_PER_SECOND)
    if is_fading_in then
        opacity = math.min(1, opacity + step)
    else
        opacity = math.max(0, opacity - step)
    end

    redraw.request()

    if (is_fading_in and opacity >= 1) or (not is_fading_in and opacity <= 0) then
        fade_timer:kill()
    end
end

local function fade(direction_in)
    is_fading_in = direction_in
    fade_timer:kill()
    fade_timer:resume()
end

local function on_audio_track_changed()
    if is_file_starting then
        return
    end

    visibility.show_now()
    fade(true)
    hide_timer:kill()
    hide_timer:resume()
end

function track_notice.start()
    fade_timer = mp.add_periodic_timer(1 / FADE_STEPS_PER_SECOND, step_fade)
    fade_timer:kill()
    hide_timer = mp.add_timeout(SECONDS_SHOWN, function()
        fade(false)
    end)
    hide_timer:kill()

    -- Changes while a file is starting are its first choice of track, not
    -- a change worth announcing.
    mp.register_event("start-file", function()
        is_file_starting = true
        opacity = 0
        redraw.request()
    end)
    mp.register_event("playback-restart", function()
        is_file_starting = false
    end)

    mp.observe_property("aid", "string", on_audio_track_changed)

    -- The sound path (passthrough, downmix) settles a moment after the
    -- track changes, so redraw while the notice shows.
    mp.observe_property("audio-out-params", "native", function()
        if opacity > 0 then
            redraw.request()
        end
    end)

    redraw.register(render)
    screen.on_change(redraw.request)
end

return track_notice
