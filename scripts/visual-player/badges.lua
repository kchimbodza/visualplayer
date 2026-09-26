-- Format badges: small outlined labels under the clock that sum up what's
-- playing, like "4K · HDR10 · HEVC · Dolby Atmos · TrueHD · 7.1". They
-- come from the original sketch. See docs/plan.md, Phase 6.
--
-- By default they appear a moment after a file starts, stay for a few
-- seconds, then fade out, like the moment a streaming service shows what
-- you're about to watch. The "Format badges" setting can instead show
-- them whenever the controls are showing, or turn them off. They also
-- show whenever the info panel is open.
--
-- They say what's actually being played, the same as the info panel:
-- Dolby Vision profile 7 plays as HDR10, so it gets an HDR10 badge.

local draw = require("draw")
local info_details = require("info_details")
local info_panel = require("info_panel")
local picture_in_picture = require("picture_in_picture")
local redraw = require("redraw")
local screen = require("screen")
local settings = require("settings")
local style = require("style")
local top_bar = require("top_bar")
local visibility = require("visibility")

local badges = {}

-- Sizes in design pixels. See screen.lua.
local TEXT_SIZE = 18
local HORIZONTAL_PADDING = 11
local VERTICAL_PADDING = 6
local GAP_BETWEEN_BADGES = 8
local CORNER_RADIUS = 5
local OUTLINE_WIDTH = 1

-- Badges never take more than this share of the window's width. Any that
-- don't fit are left off the end.
local WIDEST_SHARE_OF_WINDOW = 0.6

local FILL_OPACITY = 0.35
local OUTLINE_OPACITY = 0.6

-- When a file starts: wait for mpv to work out the picture's details,
-- show the badges this long, then fade them out.
local SECONDS_BEFORE_SHOWING = 1
local SECONDS_SHOWN = 5
local FADE_SECONDS = 0.5
local FADE_STEPS_PER_SECOND = 30

local canvas = draw.create_canvas({ layer = 1 })

-- How visible the badges are when shown at the start of a file, from 0
-- to 1, and the timers that bring them in and out.
local start_opacity = 0
local fade_timer = nil
local show_timer = nil
local hide_timer = nil
local is_fading_in = false

-- The labels for the current file, in order: picture, then sound.
local function labels_for_current_file()
    local labels = {}

    local picture = info_details.picture_summary()
    if picture then
        if picture.resolution ~= "SD" then
            table.insert(labels, picture.resolution)
        end
        if picture.dynamic_range ~= "SDR" then
            table.insert(labels, picture.dynamic_range)
        end
        table.insert(labels, picture.codec)
    end

    if mp.get_property_bool("demuxer-via-network", false) then
        local format = (mp.get_property("file-format", ""):match("^[^,]+") or ""):upper()
        if format ~= "" then
            table.insert(labels, format)
        end
    end

    -- Sound is one badge naming the format with its channels, the way a
    -- soundbar would: "Dolby Digital 5.1", "DTS-HD MA 5.1", "Opus
    -- Stereo". Atmos gets its own badge in front: "Dolby Atmos", then
    -- "Dolby TrueHD 7.1".
    local sound = info_details.sound_summary()
    if sound then
        if sound.is_atmos then
            table.insert(labels, "Dolby Atmos")
            table.insert(labels, sound.format_with_channels or sound.for_people)
        else
            table.insert(labels, sound.for_people)
        end
    end

    return labels
end

-- How visible the badges should be right now, depending on the setting.
-- While the info panel is open, they always show, whatever the setting,
-- as a quick summary above the panel's details.
local function current_opacity()
    if info_panel.is_open() then
        return 1
    end

    local setting = settings.get("format_badges")
    if setting == "off" then
        return 0
    end
    if setting == "with_controls" then
        return visibility.opacity()
    end
    return start_opacity
end

local function render()
    local opacity = current_opacity()

    -- The small picture-in-picture window has no room for them.
    if opacity <= 0 or picture_in_picture.is_on() or not screen.is_ready() then
        canvas:clear()
        return
    end

    draw.set_overall_opacity(opacity)

    local text_size = screen.pixels(TEXT_SIZE)
    local horizontal_padding = screen.pixels(HORIZONTAL_PADDING)
    local height = text_size + screen.pixels(VERTICAL_PADDING) * 2
    local gap = screen.pixels(GAP_BETWEEN_BADGES)
    local right, top = top_bar.badges_anchor()
    local leftmost_allowed = right - screen.width * WIDEST_SHARE_OF_WINDOW

    -- Work out each badge's width, dropping any that won't fit.
    local placed = {}
    local total_width = 0
    for _, label in ipairs(labels_for_current_file()) do
        local width = draw.estimate_text_width(label, text_size) + horizontal_padding * 2
        local new_total = total_width + width
        if #placed > 0 then
            new_total = new_total + gap
        end
        if right - new_total < leftmost_allowed then
            break
        end
        table.insert(placed, { label = label, width = width })
        total_width = new_total
    end

    -- Draw them left to right, ending at the window's right margin.
    local left = right - total_width
    for _, badge in ipairs(placed) do
        canvas:add(draw.rectangle({
            area = {
                left = left,
                top = top,
                right = left + badge.width,
                bottom = top + height,
            },
            color = style.BACKGROUND_COLOR,
            opacity = FILL_OPACITY,
            corner_radius = screen.pixels(CORNER_RADIUS),
            outline = {
                width = math.max(1, screen.pixels(OUTLINE_WIDTH)),
                color = style.TEXT_COLOR,
                opacity = OUTLINE_OPACITY,
            },
        }))
        canvas:add(draw.text({
            x = left + badge.width / 2,
            y = top + height / 2,
            align = "center",
            vertical = "middle",
            text = badge.label,
            size = text_size,
            color = style.TEXT_COLOR,
        }))
        left = left + badge.width + gap
    end

    canvas:show(screen.width, screen.height)
end

-- Moves the start-of-file fade one step, and stops once there.
local function step_fade()
    local step = 1 / (FADE_SECONDS * FADE_STEPS_PER_SECOND)
    if is_fading_in then
        start_opacity = math.min(1, start_opacity + step)
    else
        start_opacity = math.max(0, start_opacity - step)
    end

    redraw.request()

    if (is_fading_in and start_opacity >= 1) or (not is_fading_in and start_opacity <= 0) then
        fade_timer:kill()
    end
end

local function fade(direction_in)
    is_fading_in = direction_in
    fade_timer:kill()
    fade_timer:resume()
end

-- A new file: show its badges after a moment, then fade them out.
local function on_file_loaded()
    show_timer:kill()
    hide_timer:kill()
    start_opacity = 0
    redraw.request()

    if settings.get("format_badges") == "at_start" then
        show_timer:resume()
    end
end

function badges.start()
    fade_timer = mp.add_periodic_timer(1 / FADE_STEPS_PER_SECOND, step_fade)
    fade_timer:kill()

    show_timer = mp.add_timeout(SECONDS_BEFORE_SHOWING, function()
        fade(true)
        hide_timer:kill()
        hide_timer:resume()
    end)
    show_timer:kill()

    hide_timer = mp.add_timeout(SECONDS_SHOWN, function()
        fade(false)
    end)
    hide_timer:kill()

    redraw.register(render)
    screen.on_change(redraw.request)
    mp.register_event("file-loaded", on_file_loaded)
    settings.on_change(redraw.request)
end

return badges
