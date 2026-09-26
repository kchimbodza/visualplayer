-- The controls along the bottom of the window. See docs/plan.md, 5.3.
--
-- This file handles the bottom area as a whole: the fade behind it, where
-- each row sits, drawing buttons, hover highlights, clicks, and drags.
-- What each row contains is decided in its own file: playback_row.lua,
-- seek_bar.lua, and tools_row.lua.
--
-- Rows are stacked upwards from the bottom of the window: the tools row
-- at the very bottom, the seek bar above it, and the playback row above
-- that.

local click_area = require("click_area")
local draw = require("draw")
local menus = require("menus")
local output_popup = require("output_popup")
local playback_row = require("playback_row")
local pointer = require("pointer")
local redraw = require("redraw")
local screen = require("screen")
local seek_bar = require("seek_bar")
local settings_menu = require("settings_menu")
local style = require("style")
local tools_row = require("tools_row")
local visibility = require("visibility")

local bottom_controls = {}

-- Sizes in design pixels. See screen.lua.
local BOTTOM_MARGIN = 8
local SIDE_MARGIN = 10
local ROW_HEIGHT = 44
local SEEK_BAR_HEIGHT = 24
local SEEK_BAR_SIDE_MARGIN = 20
local GAP_BETWEEN_ROWS = 2
local BUTTON_SIZE = 40
local ICON_SIZE = 24
local GAP_BETWEEN_CONTROLS = 4
local LABEL_SIZE = 16
local TIME_SIZE = 18
local LABEL_PADDING = 10

-- How tall the dark fade behind the controls is, and how it fades. Works
-- the same way as the top bar's background: one blurred rectangle.
local BACKGROUND_HEIGHT = 200
local BACKGROUND_FADE_CENTER = 0.6
local BACKGROUND_FADE_SPREAD = 0.4

-- How solid each look is. "dim" is for a setting that's switched off;
-- "disabled" is for a control that can't be used right now.
local OPACITY_FOR_LOOK = {
    normal = 1,
    dim = 0.45,
    disabled = 0.25,
}

local canvas = draw.create_canvas()

-- The dark fade behind the controls is the most expensive thing here to
-- draw, because of its blur, and it only changes when the window size
-- does. So it lives on its own layer underneath, and is left alone while
-- the controls on top redraw, for example while dragging the seek bar.
local background_canvas = draw.create_canvas({ layer = -1 })

-- The window size and fade level the background was last drawn for.
local background_drawn_for = nil

local hovered_control_name = nil

-- Where subtitles sit when the controls are hidden, as a percentage of
-- the window's height (100 is the bottom). Read from the person's own
-- settings when Visual Player starts, so their choice is respected.
local normal_subtitle_position = 100

-- The subtitle position Visual Player last set, so it's only changed when
-- it actually needs to move.
local current_subtitle_position = nil

-- The slider being dragged, if any, and the area it was in when the drag
-- started.
local dragged_slider = nil
local dragged_slider_area = nil

-- Text that isn't next to an icon, like the time, is drawn a little
-- larger, since it's read at a glance.
local function label_size_for(control)
    if control.icon then
        return screen.pixels(LABEL_SIZE)
    end
    return screen.pixels(TIME_SIZE)
end

-- How wide a control is: a slider's own width, or a square for its icon
-- plus room for its label.
local function measure_control(control)
    if control.slider then
        return screen.pixels(control.slider.width)
    end

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
-- adds each one, with the area it covers, to the placed list.
local function place_from_left(controls, left, middle_y, placed)
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
end

-- Same as place_from_left, but lines the controls up against a right edge.
local function place_from_right(controls, right, middle_y, placed)
    local total_width = 0
    for index, control in ipairs(controls) do
        total_width = total_width + measure_control(control)
        if index > 1 then
            total_width = total_width + screen.pixels(GAP_BETWEEN_CONTROLS)
        end
    end

    place_from_left(controls, right - total_width, middle_y, placed)
end

-- Places one row's controls: those on its left against the left edge,
-- and those on its right against the right edge.
local function place_row(controls, middle_y, placed)
    place_from_left(controls.left, screen.pixels(SIDE_MARGIN), middle_y, placed)
    place_from_right(controls.right, screen.width - screen.pixels(SIDE_MARGIN), middle_y, placed)
end

-- Works out where everything goes for the current window size. Used both
-- for drawing and for knowing what the pointer is over.
local function calculate_layout()
    local tools_row_bottom = screen.height - screen.pixels(BOTTOM_MARGIN)
    local tools_row_top = tools_row_bottom - screen.pixels(ROW_HEIGHT)

    local seek_bar_bottom = tools_row_top - screen.pixels(GAP_BETWEEN_ROWS)
    local seek_bar_top = seek_bar_bottom - screen.pixels(SEEK_BAR_HEIGHT)

    local playback_row_bottom = seek_bar_top - screen.pixels(GAP_BETWEEN_ROWS)
    local playback_row_top = playback_row_bottom - screen.pixels(ROW_HEIGHT)

    local placed = {}
    place_row(playback_row.get_controls(), (playback_row_top + playback_row_bottom) / 2, placed)
    place_row(tools_row.get_controls(), (tools_row_top + tools_row_bottom) / 2, placed)

    return {
        placed = placed,
        seek_bar_area = {
            left = screen.pixels(SEEK_BAR_SIDE_MARGIN),
            top = seek_bar_top,
            right = screen.width - screen.pixels(SEEK_BAR_SIDE_MARGIN),
            bottom = seek_bar_bottom,
        },
        controls_area = {
            left = 0,
            top = playback_row_top,
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

-- True if the pointer is over the volume icon, the volume slider, or the
-- small gap between them. Including the gap stops the slider flickering
-- closed while the pointer moves from the icon onto it.
local function is_pointer_over_volume(layout)
    local area = nil

    for _, item in ipairs(layout.placed) do
        local name = item.control.name
        if name == "volume" or name == "volume-slider" then
            if area == nil then
                area = {
                    left = item.area.left,
                    top = item.area.top,
                    right = item.area.right,
                    bottom = item.area.bottom,
                }
            else
                area.left = math.min(area.left, item.area.left)
                area.right = math.max(area.right, item.area.right)
            end
        end
    end

    return area ~= nil and pointer.is_inside(area)
end

local function add_background()
    local height = screen.pixels(BACKGROUND_HEIGHT)
    local blur = height * BACKGROUND_FADE_SPREAD

    background_canvas:add(draw.rectangle({
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

-- Redraws the background only if the window size or the fade level has
-- changed since it was last drawn.
local function update_background()
    local drawn_for = screen.width .. "x" .. screen.height .. " at " .. visibility.opacity()
    if drawn_for == background_drawn_for then
        return
    end

    add_background()
    background_canvas:show(screen.width, screen.height)
    background_drawn_for = drawn_for
end

local function hide_background()
    background_canvas:clear()
    background_drawn_for = nil
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

    -- Sliders draw themselves.
    if control.slider then
        control.slider.draw(canvas, area)
        return
    end

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

-- Moves subtitles, but only if they're not already there.
local function set_subtitle_position(position)
    if position == current_subtitle_position then
        return
    end

    mp.set_property_number("sub-pos", position)
    current_subtitle_position = position
end

-- While the controls are showing, subtitles would sit behind them (found
-- in Phase 2, step 5), so lift them to just above the controls. They're
-- only ever lifted higher than the person's own setting, never lower.
local function lift_subtitles_above(layout)
    local controls_top_percent = layout.controls_area.top / screen.height * 100
    local lifted_position = math.floor(controls_top_percent) - 1
    set_subtitle_position(math.min(normal_subtitle_position, lifted_position))
end

local function put_subtitles_back()
    set_subtitle_position(normal_subtitle_position)
end

local function render()
    if not visibility.is_shown() or not screen.is_ready() then
        canvas:clear()
        hide_background()
        seek_bar.forget_drawn_area()
        put_subtitles_back()
        return
    end

    draw.set_overall_opacity(visibility.opacity())

    local layout = calculate_layout()

    -- The output popup sits just above the controls on the right, and
    -- the menus just above them on the left.
    output_popup.place_above(layout.controls_area.top, screen.width - screen.pixels(SIDE_MARGIN))
    menus.place_above(layout.controls_area.top, screen.pixels(SIDE_MARGIN))
    settings_menu.place_above(layout.controls_area.top, screen.pixels(SIDE_MARGIN))

    update_background()
    lift_subtitles_above(layout)
    for _, item in ipairs(layout.placed) do
        add_control(item)
    end
    seek_bar.render_into(canvas, layout.seek_bar_area)

    canvas:show(screen.width, screen.height)
end

local function is_dragging_anything()
    return seek_bar.is_dragging() or dragged_slider ~= nil
end

local function on_click()
    local layout = calculate_layout()

    if pointer.is_inside(layout.seek_bar_area) then
        seek_bar.start_dragging(layout.seek_bar_area)
        redraw.request()
        return
    end

    for _, item in ipairs(layout.placed) do
        local control = item.control
        if control.look ~= "disabled" and pointer.is_inside(item.area) then
            if control.slider then
                dragged_slider = control.slider
                dragged_slider_area = item.area
                redraw.set_dragging(true)
                control.slider.on_press(item.area)
            else
                control.action()
            end
            redraw.request()
            return
        end
    end
end

local function on_release()
    if seek_bar.is_dragging() then
        seek_bar.stop_dragging()
    end

    if dragged_slider then
        dragged_slider = nil
        dragged_slider_area = nil
        redraw.set_dragging(false)
    end

    redraw.request()
end

-- The bottom area takes over mouse clicks only while the pointer is over
-- it. Double-clicks there are ignored, so clicking a button twice quickly
-- doesn't also switch to fullscreen.
local clicks = click_area.create("bottom-controls", {
    on_click = on_click,
    on_release = on_release,
})

-- Mouse movement happens constantly, so only ask for a redraw when
-- something visible actually changes.
local function on_pointer_moved()
    -- While dragging, keep following the pointer and keep hold of mouse
    -- clicks, even if the pointer strays outside the controls, so letting
    -- go still ends the drag.
    if seek_bar.is_dragging() then
        seek_bar.continue_dragging()
        redraw.request()
        return
    end

    if dragged_slider then
        dragged_slider.on_drag(dragged_slider_area)
        redraw.request()
        return
    end

    local layout = calculate_layout()

    local now_hovered = find_hovered_control(layout)
    local seek_bar_changed = seek_bar.update_hover(layout.seek_bar_area)
    local volume_changed = tools_row.set_volume_expanded(is_pointer_over_volume(layout))

    if now_hovered ~= hovered_control_name or seek_bar_changed or volume_changed then
        hovered_control_name = now_hovered
        redraw.request()
    end

    -- Hidden controls don't take clicks, and neither do these while a
    -- popup or menu is open, since it takes every click itself (clicking
    -- anywhere outside it closes it).
    local is_pointer_over_controls = pointer.is_inside(layout.controls_area)
    local is_popup_open = output_popup.is_open() or menus.is_any_open() or settings_menu.is_open()
    clicks:update(visibility.is_shown() and is_pointer_over_controls and not is_popup_open)
end

-- Keeps the controls from hiding while the pointer rests on them, or
-- while something is being dragged.
local function should_stay_shown()
    return is_dragging_anything() or pointer.is_inside(calculate_layout().controls_area)
end

function bottom_controls.start()
    normal_subtitle_position = mp.get_property_number("sub-pos", 100)
    current_subtitle_position = normal_subtitle_position

    redraw.register(render)
    screen.on_change(redraw.request)
    pointer.on_move(on_pointer_moved)
    visibility.keep_shown_while(should_stay_shown)
    playback_row.start()
    seek_bar.start()
    tools_row.start()
end

return bottom_controls
