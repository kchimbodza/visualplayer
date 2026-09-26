-- The controls along the bottom of the window. See docs/plan.md, 5.3.
--
-- This file handles the bottom area as a whole: the fade behind it, where
-- each row sits, drawing buttons, hover highlights, and clicks. What each
-- row contains is decided in its own file, starting with playback_row.lua.
-- The seek bar and tools row join it in Phase 2, steps 4 and 5.

local click_area = require("click_area")
local draw = require("draw")
local playback_row = require("playback_row")
local pointer = require("pointer")
local redraw = require("redraw")
local screen = require("screen")
local style = require("style")

local bottom_controls = {}

-- Sizes in design pixels. See screen.lua.
local BOTTOM_MARGIN = 12
local SIDE_MARGIN = 10
local ROW_HEIGHT = 44
local BUTTON_SIZE = 40
local ICON_SIZE = 24
local GAP_BETWEEN_CONTROLS = 4
local LABEL_SIZE = 16
local TIME_SIZE = 18
local LABEL_PADDING = 10

-- How tall the dark fade behind the controls is, and how it fades. Works
-- the same way as the top bar's background: one blurred rectangle.
local BACKGROUND_HEIGHT = 120
local BACKGROUND_FADE_CENTER = 0.55
local BACKGROUND_FADE_SPREAD = 0.45

-- How solid each look is. "dim" is for a setting that's switched off;
-- "disabled" is for a control that can't be used right now.
local OPACITY_FOR_LOOK = {
    normal = 1,
    dim = 0.45,
    disabled = 0.25,
}

local canvas = draw.create_canvas()

local is_visible = false
local hovered_control_name = nil

-- Text that isn't next to an icon, like the time, is drawn a little
-- larger, since it's read at a glance.
local function label_size_for(control)
    if control.icon then
        return screen.pixels(LABEL_SIZE)
    end
    return screen.pixels(TIME_SIZE)
end

-- How wide a control is: a square for its icon, plus room for its label.
local function measure_control(control)
    local width = 0

    if control.icon then
        width = screen.pixels(BUTTON_SIZE)
    else
        width = screen.pixels(LABEL_PADDING)
    end

    if control.label then
        width = width
            + draw.estimate_text_width(control.label, label_size_for(control))
            + screen.pixels(LABEL_PADDING)
    end

    return width
end

-- Places controls side by side, left to right from a starting point, and
-- returns each one with the area it covers.
local function place_from_left(controls, left, middle_y)
    local placed = {}
    local height = screen.pixels(BUTTON_SIZE)

    for _, control in ipairs(controls) do
        local width = measure_control(control)
        table.insert(placed, {
            control = control,
            area = {
                left = left,
                top = middle_y - height / 2,
                right = left + width,
                bottom = middle_y + height / 2,
            },
        })
        left = left + width + screen.pixels(GAP_BETWEEN_CONTROLS)
    end

    return placed
end

-- Same as place_from_left, but lines the controls up against a right edge.
local function place_from_right(controls, right, middle_y)
    local total_width = 0
    for index, control in ipairs(controls) do
        total_width = total_width + measure_control(control)
        if index > 1 then
            total_width = total_width + screen.pixels(GAP_BETWEEN_CONTROLS)
        end
    end

    return place_from_left(controls, right - total_width, middle_y)
end

-- Works out where everything goes for the current window size. Used both
-- for drawing and for knowing what the pointer is over.
local function calculate_layout()
    local row_bottom = screen.height - screen.pixels(BOTTOM_MARGIN)
    local row_top = row_bottom - screen.pixels(ROW_HEIGHT)
    local row_middle = (row_top + row_bottom) / 2

    local controls = playback_row.get_controls()
    local placed = place_from_left(controls.left, screen.pixels(SIDE_MARGIN), row_middle)

    local right_edge = screen.width - screen.pixels(SIDE_MARGIN)
    for _, item in ipairs(place_from_right(controls.right, right_edge, row_middle)) do
        table.insert(placed, item)
    end

    return {
        placed = placed,
        controls_area = {
            left = 0,
            top = row_top,
            right = screen.width,
            bottom = screen.height,
        },
    }
end

local function find_hovered_control(layout)
    for _, item in ipairs(layout.placed) do
        if item.control.look ~= "disabled" and pointer.is_inside(item.area) then
            return item.control.name
        end
    end
    return nil
end

local function add_background()
    local height = screen.pixels(BACKGROUND_HEIGHT)
    local blur = height * BACKGROUND_FADE_SPREAD

    canvas:add(draw.rectangle({
        area = {
            left = -blur,
            top = screen.height - height * BACKGROUND_FADE_CENTER,
            right = screen.width + blur,
            bottom = screen.height + height,
        },
        color = style.BACKGROUND_COLOR,
        opacity = style.BACKGROUND_OPACITY,
        blur = blur,
    }))
end

-- Icon-only controls get a round highlight; wider ones with a label get
-- a rounded rectangle.
local function add_hover_highlight(area, control)
    local height = area.bottom - area.top

    if control.label then
        canvas:add(draw.rectangle({
            area = area,
            color = style.HOVER_COLOR,
            opacity = style.HOVER_OPACITY,
            corner_radius = height / 2,
        }))
    else
        canvas:add(draw.circle({
            x = (area.left + area.right) / 2,
            y = (area.top + area.bottom) / 2,
            radius = height / 2,
            color = style.HOVER_COLOR,
            opacity = style.HOVER_OPACITY,
        }))
    end
end

local function add_control(item)
    local control = item.control
    local area = item.area
    local middle_y = (area.top + area.bottom) / 2
    local opacity = OPACITY_FOR_LOOK[control.look] or 1

    if control.name == hovered_control_name then
        add_hover_highlight(area, control)
    end

    local text_left = area.left + screen.pixels(LABEL_PADDING)

    if control.icon then
        local icon_middle_x = area.left + screen.pixels(BUTTON_SIZE) / 2
        canvas:add(draw.icon({
            name = control.icon,
            x = icon_middle_x,
            y = middle_y,
            size = screen.pixels(ICON_SIZE),
            color = style.TEXT_COLOR,
            opacity = opacity,
        }))
        text_left = area.left + screen.pixels(BUTTON_SIZE)
    end

    if control.label then
        canvas:add(draw.text({
            x = text_left,
            y = middle_y,
            vertical = "middle",
            text = control.label,
            size = label_size_for(control),
            color = style.TEXT_COLOR,
            opacity = opacity,
        }))
    end
end

local function render()
    if not is_visible or not screen.is_ready() then
        canvas:clear()
        return
    end

    local layout = calculate_layout()

    add_background()
    for _, item in ipairs(layout.placed) do
        add_control(item)
    end

    canvas:show(screen.width, screen.height)
end

local function on_click()
    local layout = calculate_layout()

    for _, item in ipairs(layout.placed) do
        if item.control.look ~= "disabled" and pointer.is_inside(item.area) then
            item.control.action()
            return
        end
    end
end

-- The bottom area takes over mouse clicks only while the pointer is over
-- it. Double-clicks there are ignored, so clicking a button twice quickly
-- doesn't also switch to fullscreen.
local clicks = click_area.create("bottom-controls", { on_click = on_click })

-- Mouse movement happens constantly, so only ask for a redraw when
-- something visible actually changes.
local function on_pointer_moved()
    local layout = calculate_layout()

    local should_be_visible = pointer.is_over_window
    local now_hovered = find_hovered_control(layout)

    if should_be_visible ~= is_visible or now_hovered ~= hovered_control_name then
        is_visible = should_be_visible
        hovered_control_name = now_hovered
        redraw.request()
    end

    clicks:update(pointer.is_inside(layout.controls_area))
end

function bottom_controls.start()
    redraw.register(render)
    screen.on_change(redraw.request)
    pointer.on_move(on_pointer_moved)
    playback_row.start()
end

return bottom_controls
