-- Phase 0 button test for Visual Player.
--
-- Draws a play/pause button and a title bar on top of the video using
-- mpv's on-screen display, then checks that hovering, clicking, and
-- dragging all work. These are the building blocks the whole UI needs.

-- Sizes are in screen pixels.
local BUTTON_SIZE = 96
local BUTTON_MARGIN = 48
local TITLE_BAR_HEIGHT = 64
local TEXT_SIZE = 28

-- ASS colors are written blue-green-red, so "FFFFFF" is white and
-- "141414" is near-black.
local BUTTON_COLOR = "FFFFFF"
local ICON_COLOR = "141414"
local TEXT_COLOR = "FFFFFF"
local TITLE_BAR_COLOR = "000000"

-- ASS transparency runs from "00" (solid) to "FF" (invisible).
local BUTTON_TRANSPARENCY_NORMAL = "90"
local BUTTON_TRANSPARENCY_HOVERED = "10"
local TITLE_BAR_TRANSPARENCY = "60"

local overlay = mp.create_osd_overlay("ass-events")

local screen = { width = 0, height = 0 }
local mouse = { x = -1, y = -1 }
local button_click_count = 0
local last_action = "Nothing clicked yet"

-- The button sits in the bottom-left corner.
local function get_button_area()
    return {
        left = BUTTON_MARGIN,
        top = screen.height - BUTTON_MARGIN - BUTTON_SIZE,
        right = BUTTON_MARGIN + BUTTON_SIZE,
        bottom = screen.height - BUTTON_MARGIN,
    }
end

-- The title bar runs across the full width of the top edge.
local function get_title_bar_area()
    return { left = 0, top = 0, right = screen.width, bottom = TITLE_BAR_HEIGHT }
end

-- Rounds to a whole pixel. Some Lua versions refuse to print fractions
-- with %d, so every drawing position goes through this first.
local function to_pixel(value)
    return math.floor(value + 0.5)
end

local function is_mouse_inside(area)
    return mouse.x >= area.left
        and mouse.x <= area.right
        and mouse.y >= area.top
        and mouse.y <= area.bottom
end

-- Starts an ASS drawing in the given color and transparency. Positions
-- inside the drawing are then plain screen pixels.
local function start_drawing(color, transparency)
    return "{\\an7\\pos(0,0)\\bord0\\shad0"
        .. "\\1c&H" .. color .. "&"
        .. "\\1a&H" .. transparency .. "&"
        .. "\\p1}"
end

local function draw_rectangle(area, color, transparency)
    return start_drawing(color, transparency)
        .. string.format(
            "m %d %d l %d %d %d %d %d %d",
            to_pixel(area.left), to_pixel(area.top),
            to_pixel(area.right), to_pixel(area.top),
            to_pixel(area.right), to_pixel(area.bottom),
            to_pixel(area.left), to_pixel(area.bottom)
        )
        .. "{\\p0}"
end

-- A triangle pointing right, shown while the video is paused.
local function draw_play_icon(area)
    local inset = BUTTON_SIZE / 4
    local middle_y = (area.top + area.bottom) / 2

    return start_drawing(ICON_COLOR, "00")
        .. string.format(
            "m %d %d l %d %d %d %d",
            to_pixel(area.left + inset * 1.2), to_pixel(area.top + inset),
            to_pixel(area.right - inset), to_pixel(middle_y),
            to_pixel(area.left + inset * 1.2), to_pixel(area.bottom - inset)
        )
        .. "{\\p0}"
end

-- Two vertical bars, shown while the video is playing.
local function draw_pause_icon(area)
    local inset = BUTTON_SIZE / 4
    local bar_width = BUTTON_SIZE / 7
    local middle_x = (area.left + area.right) / 2
    local gap = bar_width / 2

    local left_bar = {
        left = middle_x - gap - bar_width,
        top = area.top + inset,
        right = middle_x - gap,
        bottom = area.bottom - inset,
    }
    local right_bar = {
        left = middle_x + gap,
        top = area.top + inset,
        right = middle_x + gap + bar_width,
        bottom = area.bottom - inset,
    }

    return draw_rectangle(left_bar, ICON_COLOR, "00")
        .. "\n"
        .. draw_rectangle(right_bar, ICON_COLOR, "00")
end

local function draw_text(x, y, text)
    return string.format(
        "{\\an7\\pos(%d,%d)\\fs%d\\bord2\\shad0\\1c&H%s&}%s",
        to_pixel(x), to_pixel(y), TEXT_SIZE, TEXT_COLOR, text
    )
end

-- Redraws the whole test interface. Called whenever anything changes.
local function render()
    if screen.width == 0 or screen.height == 0 then
        return
    end

    local button_area = get_button_area()
    local title_bar_area = get_title_bar_area()
    local is_paused = mp.get_property_bool("pause", false)

    local button_transparency = BUTTON_TRANSPARENCY_NORMAL
    if is_mouse_inside(button_area) then
        button_transparency = BUTTON_TRANSPARENCY_HOVERED
    end

    local icon
    if is_paused then
        icon = draw_play_icon(button_area)
    else
        icon = draw_pause_icon(button_area)
    end

    local text_top = TITLE_BAR_HEIGHT + 16
    local line_spacing = TEXT_SIZE + 10

    local drawing_parts = {
        draw_rectangle(title_bar_area, TITLE_BAR_COLOR, TITLE_BAR_TRANSPARENCY),
        draw_text(16, (TITLE_BAR_HEIGHT - TEXT_SIZE) / 2, "Drag this bar to move the window"),
        draw_rectangle(button_area, BUTTON_COLOR, button_transparency),
        icon,
        draw_text(16, text_top, "Button clicks: " .. button_click_count),
        draw_text(16, text_top + line_spacing, "Last action: " .. last_action),
        draw_text(16, text_top + line_spacing * 2, string.format(
            "Mouse: %d, %d   Screen: %d x %d",
            to_pixel(mouse.x), to_pixel(mouse.y), screen.width, screen.height
        )),
    }

    overlay.res_x = screen.width
    overlay.res_y = screen.height
    overlay.data = table.concat(drawing_parts, "\n")
    overlay:update()
end

-- Decides what a left click means based on where the mouse is.
local function handle_left_click(event)
    -- Act when the button goes down, so dragging starts immediately.
    if event.event ~= "down" then
        return
    end

    if is_mouse_inside(get_button_area()) then
        mp.command("cycle pause")
        button_click_count = button_click_count + 1
        last_action = "Clicked the button"
    elseif is_mouse_inside(get_title_bar_area()) then
        mp.commandv("begin-vo-dragging")
        last_action = "Started dragging the window"
    else
        last_action = "Clicked the video, outside the button"
    end

    mp.msg.info(last_action)
    render()
end

mp.observe_property("osd-dimensions", "native", function(_, dimensions)
    if dimensions then
        screen.width = dimensions.w
        screen.height = dimensions.h
        render()
    end
end)

mp.observe_property("mouse-pos", "native", function(_, position)
    if position and position.hover then
        mouse.x = position.x
        mouse.y = position.y
    else
        mouse.x = -1
        mouse.y = -1
    end
    render()
end)

mp.observe_property("pause", "bool", render)

mp.add_forced_key_binding("MBTN_LEFT", "button-test-click", handle_left_click, { complex = true })
