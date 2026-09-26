-- Drawing helpers for Visual Player's on-screen interface.
--
-- mpv draws its on-screen display with ASS, the subtitle format. ASS can
-- draw almost anything, but it's very hard to read. These helpers turn
-- plain descriptions, like "a rounded rectangle here, 70% opaque", into
-- ASS, so the rest of the code never has to deal with it directly.
--
-- Positions and sizes are always real pixels. Use screen.pixels() to
-- convert design sizes first.

local icons = require("icons")

local draw = {}

-- A curve whose control handles are this fraction of the radius closely
-- matches a quarter circle. Used for rounded corners.
local QUARTER_CIRCLE_HANDLE = 0.5523

-- ASS numbers its text anchor points like a phone keypad, starting from
-- the bottom-left corner.
local ANCHOR_NUMBER = {
    top = { left = 7, center = 8, right = 9 },
    middle = { left = 4, center = 5, right = 6 },
    bottom = { left = 1, center = 2, right = 3 },
}

local function round(value)
    return math.floor(value + 0.5)
end

-- Turns "#RRGGBB" into ASS's color format, which lists the parts in the
-- opposite order: blue, green, then red.
local function to_ass_color(hex_color)
    local red = hex_color:sub(2, 3)
    local green = hex_color:sub(4, 5)
    local blue = hex_color:sub(6, 7)
    return "&H" .. blue .. green .. red .. "&"
end

-- How visible everything drawn right now should be, from 0 to 1. Every
-- shape, text, and icon is multiplied by this, which is how the whole
-- interface fades in and out together. See draw.set_overall_opacity().
local overall_opacity = 1

-- Sets how visible everything drawn from now on should be, from 0 to 1.
function draw.set_overall_opacity(opacity)
    overall_opacity = opacity
end

-- Turns an opacity from 0 (invisible) to 1 (solid) into ASS's
-- transparency, which runs the other way: 00 is solid, FF is invisible.
local function to_ass_transparency(opacity)
    local transparency = round((1 - opacity * overall_opacity) * 255)
    return string.format("&H%02X&", transparency)
end

-- Turns a character code into the bytes that represent it in UTF-8.
-- Lua 5.1, which mpv uses, has no built-in way to do this.
local function to_utf8(code)
    if code < 0x80 then
        return string.char(code)
    end

    if code < 0x800 then
        return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
    end

    if code < 0x10000 then
        return string.char(
            0xE0 + math.floor(code / 0x1000),
            0x80 + math.floor(code / 0x40) % 0x40,
            0x80 + code % 0x40
        )
    end

    return string.char(
        0xF0 + math.floor(code / 0x40000),
        0x80 + math.floor(code / 0x1000) % 0x40,
        0x80 + math.floor(code / 0x40) % 0x40,
        0x80 + code % 0x40
    )
end

-- Makes any text safe to show. Without this, a title containing a
-- backslash or curly brace would be read as ASS formatting commands.
-- An invisible character after each backslash breaks up any command.
function draw.escape_text(text)
    local escaped = text:gsub("\\", "\\\239\187\191")
    escaped = escaped:gsub("{", "\\{")
    escaped = escaped:gsub("\n", "\\N")
    return escaped
end

-- The start and end of every filled shape. A blur above zero softens
-- the shape's edges by that many pixels. An outline, if given, is a table
-- of { width, color, opacity }.
local function start_shape(color, opacity, blur, outline)
    local outline_part = "\\bord0"
    if outline then
        outline_part = string.format("\\bord%d", round(outline.width))
            .. "\\3c"
            .. to_ass_color(outline.color)
            .. "\\3a"
            .. to_ass_transparency(outline.opacity or 1)
    end

    return "{\\an7\\pos(0,0)" .. outline_part .. "\\shad0"
        .. string.format("\\blur%d", round(blur or 0))
        .. "\\1c"
        .. to_ass_color(color)
        .. "\\1a"
        .. to_ass_transparency(opacity)
        .. "\\p1}"
end

local END_SHAPE = "{\\p0}"

-- Joins drawing commands and numbers into ASS's drawing language,
-- rounding every number to a whole pixel along the way.
local function to_drawing_path(commands_and_numbers)
    local parts = {}

    for _, item in ipairs(commands_and_numbers) do
        if type(item) == "number" then
            table.insert(parts, tostring(round(item)))
        else
            table.insert(parts, item)
        end
    end

    return table.concat(parts, " ")
end

local function square_corner_path(area)
    return to_drawing_path({
        "m", area.left, area.top,
        "l", area.right, area.top,
        area.right, area.bottom,
        area.left, area.bottom,
    })
end

-- Traces a rectangle clockwise from its top-left corner, with a curve
-- ("b") at each corner and a straight line ("l") along each side.
local function rounded_corner_path(area, radius)
    local handle = radius * QUARTER_CIRCLE_HANDLE
    local left, top, right, bottom = area.left, area.top, area.right, area.bottom

    return to_drawing_path({
        -- Top edge, then the top-right corner
        "m", left + radius, top,
        "l", right - radius, top,
        "b", right - radius + handle, top,
        right, top + radius - handle,
        right, top + radius,
        -- Right edge, then the bottom-right corner
        "l", right, bottom - radius,
        "b", right, bottom - radius + handle,
        right - radius + handle, bottom,
        right - radius, bottom,
        -- Bottom edge, then the bottom-left corner
        "l", left + radius, bottom,
        "b", left + radius - handle, bottom,
        left, bottom - radius + handle,
        left, bottom - radius,
        -- Left edge, then back around the top-left corner
        "l", left, top + radius,
        "b", left, top + radius - handle,
        left + radius - handle, top,
        left + radius, top,
    })
end

-- Draws a filled rectangle.
--
-- options.area           { left, top, right, bottom } in pixels
-- options.color          "#RRGGBB"
-- options.opacity        0 to 1, default 1
-- options.corner_radius  pixels, default 0 for square corners
-- options.outline        optional { width, color, opacity }: a line around
--                        the edge, like the format badges' borders
-- options.blur           pixels, default 0; softens the edges into a
--                        smooth fade. Blurring costs more to draw than a
--                        plain shape, so use it for large, rarely changing
--                        things like backgrounds.
function draw.rectangle(options)
    local area = options.area
    local width = area.right - area.left
    local height = area.bottom - area.top

    -- A corner can't be rounder than half the shape, or the curves overlap.
    local radius = math.min(options.corner_radius or 0, width / 2, height / 2)

    local path
    if radius > 0 then
        path = rounded_corner_path(area, radius)
    else
        path = square_corner_path(area)
    end

    return start_shape(options.color, options.opacity or 1, options.blur, options.outline)
        .. path
        .. END_SHAPE
end

-- Draws a filled circle.
--
-- options.x, options.y   center, in pixels
-- options.radius         pixels
-- options.color          "#RRGGBB"
-- options.opacity        0 to 1, default 1
function draw.circle(options)
    return draw.rectangle({
        area = {
            left = options.x - options.radius,
            top = options.y - options.radius,
            right = options.x + options.radius,
            bottom = options.y + options.radius,
        },
        color = options.color,
        opacity = options.opacity,
        corner_radius = options.radius,
    })
end

-- Draws a line of text.
--
-- options.x, options.y   the anchor point, in pixels
-- options.text           what to show; it's escaped automatically
-- options.size           font size in pixels
-- options.color          "#RRGGBB", default white
-- options.opacity        0 to 1, default 1
-- options.bold           true for bold, default false
-- options.align          "left", "center", or "right" of the anchor
-- options.vertical       "top", "middle", or "bottom" of the anchor
-- options.outline        outline width in pixels, default 0; helps text
--                        stay readable over bright video
-- options.clip           an area { left, top, right, bottom }; any text
--                        outside it is cut off. Use it to stop long text
--                        running into something else.
function draw.text(options)
    local anchor = ANCHOR_NUMBER[options.vertical or "top"][options.align or "left"]
    local bold = 0
    if options.bold then
        bold = 1
    end

    local clip = ""
    if options.clip then
        clip = string.format(
            "\\clip(%d,%d,%d,%d)",
            round(options.clip.left),
            round(options.clip.top),
            round(options.clip.right),
            round(options.clip.bottom)
        )
    end

    return string.format(
        "{\\an%d\\pos(%d,%d)%s\\fs%d\\b%d\\bord%d\\shad0\\1c%s\\1a%s\\3c&H000000&}%s",
        anchor,
        round(options.x),
        round(options.y),
        clip,
        round(options.size),
        bold,
        round(options.outline or 0),
        to_ass_color(options.color or "#FFFFFF"),
        to_ass_transparency(options.opacity or 1),
        draw.escape_text(options.text)
    )
end

-- Inter's letters average a little over half their height in width. ASS
-- can't measure text, so this estimate is used wherever the interface
-- needs to know how much room some text will take.
local AVERAGE_CHARACTER_WIDTH = 0.56

-- Counts characters rather than bytes, since symbols like "·" and "×"
-- take several bytes in UTF-8. Continuation bytes (128 to 191) are
-- skipped.
local function count_characters(text)
    local _, count = text:gsub("[^\128-\191]", "")
    return count
end

-- Estimates how wide some text will be at a given size, in pixels.
-- Measures text exactly, by asking mpv to lay it out in a hidden overlay
-- and report its size, the same way it will be drawn. An estimate from
-- the number of characters was about half as wide again as the real
-- text, leaving gaps in the audio chip and track notice (Phase 6).
-- Results are remembered, since the same labels are measured on every
-- redraw.
local measuring_overlay = nil
local measured_widths = {}

local function measure_text_width(text, size, bold)
    local dimensions = mp.get_property_native("osd-dimensions") or {}
    if (dimensions.w or 0) <= 0 or (dimensions.h or 0) <= 0 then
        return nil
    end

    local bold_number = 0
    if bold then
        bold_number = 1
    end

    local key = string.format("%d|%d|%s", round(size), bold_number, text)
    if measured_widths[key] then
        return measured_widths[key]
    end

    if measuring_overlay == nil then
        measuring_overlay = mp.create_osd_overlay("ass-events")
        measuring_overlay.hidden = true
        measuring_overlay.compute_bounds = true
    end

    measuring_overlay.res_x = dimensions.w
    measuring_overlay.res_y = dimensions.h
    measuring_overlay.data = string.format(
        "{\\an7\\pos(0,0)\\fs%d\\b%d\\bord0\\shad0}%s",
        round(size),
        bold_number,
        draw.escape_text(text)
    )

    local bounds = measuring_overlay:update()
    if bounds == nil or bounds.x1 == nil or bounds.x0 == nil then
        return nil
    end

    local width = bounds.x1 - bounds.x0
    measured_widths[key] = width
    return width
end

-- How wide text will be when drawn, in pixels. Measured exactly when the
-- window is ready, and estimated from the number of characters before.
-- Pass bold = true for bold text, which is wider.
function draw.estimate_text_width(text, size, bold)
    local measured = measure_text_width(text, size, bold)
    if measured then
        return measured
    end
    return count_characters(text) * size * AVERAGE_CHARACTER_WIDTH
end

-- Icon names we've already warned about, so a missing icon is reported
-- once rather than every time the screen redraws.
local warned_icon_names = {}

-- Draws an icon from the icon font, centered on the given point.
--
-- options.name           an icon name from icons.lua, like "player-play"
-- options.x, options.y   center, in pixels
-- options.size           pixels
-- options.color          "#RRGGBB", default white
-- options.opacity        0 to 1, default 1
function draw.icon(options)
    local code = icons.codepoints[options.name]

    if code == nil then
        if not warned_icon_names[options.name] then
            warned_icon_names[options.name] = true
            mp.msg.warn("There's no icon called '" .. options.name .. "' in icons.lua")
        end
        return ""
    end

    -- Fonts center a character by its spacing, not its visible shape, so
    -- icons can land slightly off-center. icons.lua records how far off
    -- each one is (measured by tools/update-icon-font.py); shift it back.
    local offset = (icons.offsets or {})[options.name] or { x = 0, y = 0 }
    local x = options.x - offset.x * options.size
    local y = options.y - offset.y * options.size

    return string.format(
        "{\\an5\\pos(%d,%d)\\fn%s\\fs%d\\bord0\\shad0\\1c%s\\1a%s}%s",
        round(x),
        round(y),
        icons.font_family,
        round(options.size),
        to_ass_color(options.color or "#FFFFFF"),
        to_ass_transparency(options.opacity or 1),
        to_utf8(code)
    )
end

-- Creates a canvas: one layer of the on-screen display that can be drawn
-- on and cleared independently of the others.
--
-- Usage:
--   local canvas = draw.create_canvas()
--   canvas:add(draw.rectangle({ ... }))
--   canvas:add(draw.text({ ... }))
--   canvas:show(screen.width, screen.height)
--
-- Pass { layer = -1 } to draw a canvas underneath the others, or a higher
-- number to draw it on top. Canvases on the same layer are drawn in the
-- order they were created.
function draw.create_canvas(options)
    local overlay = mp.create_osd_overlay("ass-events")
    overlay.z = (options or {}).layer or 0
    local canvas = { parts = {} }

    -- Adds a shape, text, or icon to be shown next time show() is called.
    function canvas:add(part)
        table.insert(self.parts, part)
    end

    -- Puts everything added since the last show() on screen, replacing
    -- what was there before.
    function canvas:show(width, height)
        overlay.res_x = width
        overlay.res_y = height
        overlay.data = table.concat(self.parts, "\n")
        overlay:update()
        self.parts = {}
    end

    -- Removes everything this canvas has drawn.
    function canvas:clear()
        self.parts = {}
        overlay:remove()
    end

    return canvas
end

return draw
