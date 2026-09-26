-- The seek bar: shows how far through the file playback is, split into
-- sections at each chapter, and lets you click or drag to jump around.
-- See docs/plan.md, 5.3.
--
-- bottom_controls.lua decides where the bar goes and passes on clicks and
-- pointer movement. This file draws the bar and does the seeking.

local draw = require("draw")
local pointer = require("pointer")
local redraw = require("redraw")
local screen = require("screen")
local style = require("style")
local time_format = require("time_format")

local seek_bar = {}

-- Sizes in design pixels. See screen.lua.
local TRACK_THICKNESS = 4
local TRACK_THICKNESS_WHEN_HOVERED = 6
local SCRUBBER_RADIUS = 7
local GAP_BETWEEN_CHAPTERS = 3
local PREVIEW_TEXT_SIZE = 15
local PREVIEW_PADDING = 8
local PREVIEW_GAP_ABOVE_BAR = 12

-- While dragging, the next seek is only sent once the previous one has
-- finished, always to wherever the pointer is by then. Sending seeks on a
-- timer instead made mpv throw away half-decoded 4K frames, so the
-- picture updated unevenly (Phase 2, step 4). If a seek somehow never
-- reports finishing, stop waiting for it after this long.
local LONGEST_WAIT_FOR_SEEK = 0.5

local is_hovered = false
local is_dragging = false
local pointer_x = nil

-- While dragging: whether a seek is still being carried out, when it was
-- sent, and the pointer position it was sent for.
local is_seek_in_progress = false
local seek_sent_time = 0
local seek_sent_for_x = nil

-- The area the bar was last drawn in, and where its fill ended, so it
-- only redraws when the fill has moved by at least a whole pixel.
local drawn_area = nil
local drawn_fill_pixel = nil

local function get_duration()
    local duration = mp.get_property_number("duration")
    if duration == nil or duration <= 0 then
        return nil
    end
    return duration
end

-- Turns a position across the bar into a time in the file.
local function time_at(area, x)
    local duration = get_duration()
    if duration == nil then
        return nil
    end

    local fraction = (x - area.left) / (area.right - area.left)
    fraction = math.max(0, math.min(1, fraction))
    return fraction * duration
end

-- Where the played part of the bar ends.
local function fill_edge(area)
    local duration = get_duration()
    local position = mp.get_property_number("time-pos", 0)

    if duration == nil then
        return area.left
    end

    local fraction = math.max(0, math.min(1, position / duration))
    return area.left + fraction * (area.right - area.left)
end

-- The times where chapters start, leaving out a chapter at the very
-- beginning, since that doesn't split the bar.
local function chapter_start_times()
    local duration = get_duration()
    local times = {}

    for _, chapter in ipairs(mp.get_property_native("chapter-list") or {}) do
        if duration and chapter.time > 0 and chapter.time < duration then
            table.insert(times, chapter.time)
        end
    end

    table.sort(times)
    return times
end

-- Returns the title of the chapter playing at the given time, or nil if
-- the file has no chapters or the chapter has no title.
local function chapter_title_at(time)
    local title = nil

    for _, chapter in ipairs(mp.get_property_native("chapter-list") or {}) do
        if chapter.time <= time and chapter.title and chapter.title ~= "" then
            title = chapter.title
        end
    end

    return title
end

-- Splits the bar into sections, one per chapter, with a small gap
-- between each. A file without chapters gets one section.
local function split_into_sections(area)
    local duration = get_duration()
    local half_gap = screen.pixels(GAP_BETWEEN_CHAPTERS) / 2
    local width = area.right - area.left

    local sections = {}
    local section_left = area.left

    for _, time in ipairs(chapter_start_times()) do
        local boundary = area.left + (time / duration) * width
        table.insert(sections, { left = section_left, right = boundary - half_gap })
        section_left = boundary + half_gap
    end

    table.insert(sections, { left = section_left, right = area.right })
    return sections
end

local function add_track(canvas, sections, fill_x, middle_y)
    local thickness = screen.pixels(TRACK_THICKNESS)
    if is_hovered or is_dragging then
        thickness = screen.pixels(TRACK_THICKNESS_WHEN_HOVERED)
    end

    local top = middle_y - thickness / 2
    local bottom = middle_y + thickness / 2

    for _, section in ipairs(sections) do
        if section.right > section.left then
            canvas:add(draw.rectangle({
                area = { left = section.left, top = top, right = section.right, bottom = bottom },
                color = style.TRACK_COLOR,
                opacity = style.TRACK_OPACITY,
                corner_radius = thickness / 2,
            }))
        end

        -- The played part of this section, if playback has reached it.
        local played_right = math.min(fill_x, section.right)
        if played_right > section.left then
            canvas:add(draw.rectangle({
                area = { left = section.left, top = top, right = played_right, bottom = bottom },
                color = style.TEXT_COLOR,
                corner_radius = thickness / 2,
            }))
        end
    end
end

-- The label that floats above the pointer, showing the time at that spot
-- and the chapter's name when it has one.
local function add_preview(canvas, area)
    local time = time_at(area, pointer_x)
    if time == nil then
        return
    end

    local include_hours = get_duration() >= 3600
    local text = time_format.clock(time, include_hours)

    local chapter_title = chapter_title_at(time)
    if chapter_title then
        text = text .. " · " .. chapter_title
    end

    local text_size = screen.pixels(PREVIEW_TEXT_SIZE)
    local padding = screen.pixels(PREVIEW_PADDING)
    local width = draw.estimate_text_width(text, text_size) + padding * 2
    local height = text_size + padding * 2

    -- Center the label on the pointer, but keep it inside the window.
    local left = pointer_x - width / 2
    left = math.max(0, math.min(screen.width - width, left))

    local bottom = area.top - screen.pixels(PREVIEW_GAP_ABOVE_BAR)
    local label_area = { left = left, top = bottom - height, right = left + width, bottom = bottom }

    canvas:add(draw.rectangle({
        area = label_area,
        color = style.BACKGROUND_COLOR,
        opacity = style.TOOLTIP_OPACITY,
        corner_radius = screen.pixels(6),
    }))
    canvas:add(draw.text({
        x = left + width / 2,
        y = bottom - height / 2,
        align = "center",
        vertical = "middle",
        text = text,
        size = text_size,
        color = style.TEXT_COLOR,
    }))
end

-- Where the handle should be drawn. While dragging, that's the pointer:
-- playback only catches up after each seek finishes, and keyframe seeks
-- can land a second or two away, so following playback made the handle
-- jump and lag behind the pointer (Phase 2, step 4).
local function handle_position(area)
    if is_dragging and pointer_x then
        return math.max(area.left, math.min(area.right, pointer_x))
    end
    return fill_edge(area)
end

-- Draws the bar into the given canvas and area.
function seek_bar.render_into(canvas, area)
    local middle_y = (area.top + area.bottom) / 2
    local fill_x = handle_position(area)

    add_track(canvas, split_into_sections(area), fill_x, middle_y)

    if get_duration() then
        canvas:add(draw.circle({
            x = fill_x,
            y = middle_y,
            radius = screen.pixels(SCRUBBER_RADIUS),
            color = style.TEXT_COLOR,
        }))
    end

    if (is_hovered or is_dragging) and pointer_x then
        add_preview(canvas, area)
    end

    drawn_area = area
    drawn_fill_pixel = math.floor(fill_x)
end

-- Tells the bar it isn't on screen, so it stops asking for redraws as
-- playback moves along.
function seek_bar.forget_drawn_area()
    drawn_area = nil
end

-- Updates whether the pointer is over the bar. Returns true if that
-- changes what the bar looks like, so a redraw is needed.
function seek_bar.update_hover(area)
    local now_hovered = pointer.is_inside(area)
    local now_x = nil
    if now_hovered then
        now_x = pointer.x
    end

    if now_hovered == is_hovered and now_x == pointer_x then
        return false
    end

    is_hovered = now_hovered
    pointer_x = now_x
    return true
end

function seek_bar.is_dragging()
    return is_dragging
end

local function seek_to(area, x, is_final)
    local time = time_at(area, x)
    if time == nil then
        return
    end

    -- While dragging, jump to the nearest keyframe, which is fast. When
    -- the drag ends, seek to the exact spot.
    local precision = "absolute+keyframes"
    if is_final then
        precision = "absolute+exact"
    end

    mp.commandv("seek", tostring(time), precision)
end

-- Sends a seek to where the pointer is now, unless one is still being
-- carried out, or the pointer hasn't moved since the last one.
local function seek_to_pointer_if_ready(area)
    local is_waiting_too_long = mp.get_time() - seek_sent_time > LONGEST_WAIT_FOR_SEEK
    if is_seek_in_progress and not is_waiting_too_long then
        return
    end

    if pointer_x == seek_sent_for_x then
        return
    end

    seek_to(area, pointer_x, false)
    is_seek_in_progress = true
    seek_sent_time = mp.get_time()
    seek_sent_for_x = pointer_x
end

-- Starts a click or drag on the bar, jumping to the pointer straight away.
function seek_bar.start_dragging(area)
    is_dragging = true
    pointer_x = pointer.x
    seek_sent_for_x = nil
    is_seek_in_progress = false
    redraw.set_dragging(true)
    seek_to_pointer_if_ready(area)
end

-- Follows the pointer while dragging.
function seek_bar.continue_dragging()
    if not is_dragging or drawn_area == nil then
        return
    end

    pointer_x = pointer.x
    seek_to_pointer_if_ready(drawn_area)
end

-- mpv reports "playback-restart" when a seek has finished and the new
-- frame is showing. That's the moment to send the next one, if the
-- pointer has moved on since.
local function on_seek_finished()
    is_seek_in_progress = false

    if is_dragging and drawn_area then
        seek_to_pointer_if_ready(drawn_area)
    end
end

-- Ends a drag, seeking to exactly where the pointer was let go.
function seek_bar.stop_dragging()
    if not is_dragging then
        return
    end

    if drawn_area then
        seek_to(drawn_area, pointer.x, true)
    end
    is_dragging = false
    redraw.set_dragging(false)
end

local function on_time_changed()
    if drawn_area == nil or is_dragging then
        return
    end

    if math.floor(fill_edge(drawn_area)) ~= drawn_fill_pixel then
        redraw.request()
    end
end

function seek_bar.start()
    mp.register_event("playback-restart", on_seek_finished)
    mp.observe_property("time-pos", "number", on_time_changed)
    mp.observe_property("duration", "number", redraw.request)
    mp.observe_property("chapter-list", "native", redraw.request)
end

return seek_bar
