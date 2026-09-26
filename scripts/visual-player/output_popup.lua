-- The output popup: opened from the output chip next to the volume, it
-- shows where the sound is going and what happens to it on the way, and
-- lets you switch to a different output. See docs/plan.md, 5.6.
--
-- It's only about sound. An earlier version also had a line for the
-- screen, but sitting under the sound device's name it read as if it
-- described that device (Phase 4, step 4). The info panel's Screen row
-- covers the picture instead.
--
-- It sits just above the playback row on the right, so the time, seek
-- bar, and controls stay visible while it's open. bottom_controls.lua
-- tells it where that is.

local audio_output = require("outputs.audio")
local click_area = require("click_area")
local draw = require("draw")
local info_details = require("info_details")
local passthrough = require("outputs.passthrough")
local pointer = require("pointer")
local popups = require("popups")
local redraw = require("redraw")
local screen = require("screen")
local style = require("style")
local visibility = require("visibility")

local output_popup = {}

-- Sizes in design pixels. See screen.lua.
local WIDTH = 360
local PADDING = 12
local GAP_ABOVE_CONTROLS = 8
local HEADER_ICON_SIZE = 22
local HEADER_ICON_COLUMN = 34
local NAME_SIZE = 17
local STATUS_SIZE = 14
local GAP_BETWEEN_LINES = 4
local DIVIDER_GAP = 10
local ROW_HEIGHT = 36
local ROW_ICON_SIZE = 18
local ROW_ICON_COLUMN = 30
local ROW_TEXT_SIZE = 15
local CHECK_SIZE = 16
local CORNER_RADIUS = 10
local ROW_CORNER_RADIUS = 6

local PANEL_OPACITY = 0.88
local DIVIDER_OPACITY = 0.2
local GOOD_COLOR = "#5DCAA5"
local WARNING_COLOR = "#EF9F27"

local OUTPUT_ICONS = {
    hdmi = "device-tv",
    displayport = "device-desktop",
    usb = "usb",
    speakers = "device-laptop",
    bluetooth = "bluetooth",
}

local canvas = draw.create_canvas({ layer = 2 })
local is_open = false
local hovered_row = nil

-- Where the popup's bottom-right corner goes, set by bottom_controls.lua.
local anchor_bottom = 0
local anchor_right = 0

-- Tells the popup where the top of the bottom controls is, so it can sit
-- just above them.
function output_popup.place_above(controls_top, right_edge)
    anchor_bottom = controls_top - screen.pixels(GAP_ABOVE_CONTROLS)
    anchor_right = right_edge
end

function output_popup.is_open()
    return is_open
end

-- The status line's color: green when the sound arrives in full or
-- untouched, amber when it's being squeezed into fewer channels.
local function sound_path_color(sound_path)
    if sound_path and sound_path:find("downmix") then
        return WARNING_COLOR
    end
    if sound_path and (sound_path:find("^Full") or sound_path == "Passthrough") then
        return GOOD_COLOR
    end
    return style.MUTED_TEXT_COLOR
end

-- Works out where everything goes. Used for drawing and for knowing
-- which row the pointer is over.
--
-- When the current output can take surround formats untouched, a
-- passthrough switch is added below the devices, after a second divider.
local function calculate_layout()
    local padding = screen.pixels(PADDING)
    local outputs = audio_output.list()
    local has_passthrough_switch = passthrough.is_possible(audio_output.current())

    local header_height = screen.pixels(NAME_SIZE + GAP_BETWEEN_LINES + STATUS_SIZE)
    local rows_height = #outputs * screen.pixels(ROW_HEIGHT)
    local switch_height = 0
    if has_passthrough_switch then
        switch_height = screen.pixels(DIVIDER_GAP * 2 + ROW_HEIGHT)
    end
    local height = padding * 2 + header_height + screen.pixels(DIVIDER_GAP * 2)
        + rows_height + switch_height

    -- Wide enough for the passthrough switch's list of formats, so it's
    -- never cut off (it was, at "TrueHI", in Phase 6).
    local width = screen.pixels(WIDTH)
    if has_passthrough_switch then
        local formats = passthrough.describe_formats(audio_output.current())
        local switch_text = "Passthrough · " .. formats
        local needed = draw.estimate_text_width(switch_text, screen.pixels(ROW_TEXT_SIZE))
            + screen.pixels(40) + padding * 3
        width = math.max(width, needed)
    end
    width = math.min(width, screen.width - padding * 2)
    local panel = {
        left = anchor_right - width,
        top = anchor_bottom - height,
        right = anchor_right,
        bottom = anchor_bottom,
    }

    local divider_y = panel.top + padding + header_height + screen.pixels(DIVIDER_GAP)
    local rows_top = divider_y + screen.pixels(DIVIDER_GAP)

    local rows = {}
    for index, output in ipairs(outputs) do
        local top = rows_top + (index - 1) * screen.pixels(ROW_HEIGHT)
        table.insert(rows, {
            output = output,
            area = {
                left = panel.left + padding / 2,
                top = top,
                right = panel.right - padding / 2,
                bottom = top + screen.pixels(ROW_HEIGHT),
            },
        })
    end

    local switch = nil
    if has_passthrough_switch then
        local switch_divider_y = rows_top + rows_height + screen.pixels(DIVIDER_GAP)
        local switch_top = switch_divider_y + screen.pixels(DIVIDER_GAP)
        switch = {
            divider_y = switch_divider_y,
            area = {
                left = panel.left + padding / 2,
                top = switch_top,
                right = panel.right - padding / 2,
                bottom = switch_top + screen.pixels(ROW_HEIGHT),
            },
        }
    end

    return { panel = panel, divider_y = divider_y, rows = rows, switch = switch }
end

local function add_header(panel)
    local current = audio_output.current()
    if current == nil then
        return
    end

    local padding = screen.pixels(PADDING)
    local left = panel.left + padding
    local top = panel.top + padding
    local name_size = screen.pixels(NAME_SIZE)
    local text_left = left + screen.pixels(HEADER_ICON_COLUMN)
    local clip = {
        left = panel.left,
        top = panel.top,
        right = panel.right - padding,
        bottom = panel.bottom,
    }

    canvas:add(draw.icon({
        name = OUTPUT_ICONS[current.kind] or "volume",
        x = left + screen.pixels(HEADER_ICON_COLUMN) / 2 - screen.pixels(4),
        y = top + (name_size + screen.pixels(GAP_BETWEEN_LINES + STATUS_SIZE)) / 2,
        size = screen.pixels(HEADER_ICON_SIZE),
        color = style.TEXT_COLOR,
    }))
    canvas:add(draw.text({
        x = text_left,
        y = top,
        text = current.name,
        size = name_size,
        bold = true,
        color = style.TEXT_COLOR,
        clip = clip,
    }))

    local sound_path = info_details.describe_sound_path(current) or ""
    canvas:add(draw.text({
        x = text_left,
        y = top + name_size + screen.pixels(GAP_BETWEEN_LINES),
        text = sound_path,
        size = screen.pixels(STATUS_SIZE),
        color = sound_path_color(sound_path),
        clip = clip,
    }))
end

local function add_row(row)
    local area = row.area
    local middle_y = (area.top + area.bottom) / 2
    local padding = screen.pixels(PADDING)

    if row.output.is_current or row.output.mpv_name == hovered_row then
        canvas:add(draw.rectangle({
            area = area,
            color = style.HOVER_COLOR,
            opacity = style.HOVER_OPACITY / 2,
            corner_radius = screen.pixels(ROW_CORNER_RADIUS),
        }))
    end

    local icon_left = area.left + padding / 2
    canvas:add(draw.icon({
        name = OUTPUT_ICONS[row.output.kind] or "volume",
        x = icon_left + screen.pixels(ROW_ICON_COLUMN) / 2 - screen.pixels(4),
        y = middle_y,
        size = screen.pixels(ROW_ICON_SIZE),
        color = style.MUTED_TEXT_COLOR,
    }))

    local check_space = screen.pixels(CHECK_SIZE) + padding
    canvas:add(draw.text({
        x = icon_left + screen.pixels(ROW_ICON_COLUMN),
        y = middle_y,
        vertical = "middle",
        text = row.output.name,
        size = screen.pixels(ROW_TEXT_SIZE),
        color = style.TEXT_COLOR,
        clip = {
            left = area.left,
            top = area.top,
            right = area.right - check_space,
            bottom = area.bottom,
        },
    }))

    if row.output.is_current then
        canvas:add(draw.icon({
            name = "check",
            x = area.right - padding / 2 - screen.pixels(CHECK_SIZE) / 2,
            y = middle_y,
            size = screen.pixels(CHECK_SIZE),
            color = style.TEXT_COLOR,
        }))
    end
end

local function add_divider(panel, y)
    canvas:add(draw.rectangle({
        area = {
            left = panel.left + screen.pixels(PADDING),
            top = y,
            right = panel.right - screen.pixels(PADDING),
            bottom = y + math.max(1, screen.pixels(1)),
        },
        color = style.TEXT_COLOR,
        opacity = DIVIDER_OPACITY,
    }))
end

-- The passthrough switch: "Passthrough" and the formats the device takes
-- on the left, and whether it's on at the right.
local function add_passthrough_switch(panel, switch)
    add_divider(panel, switch.divider_y)

    local area = switch.area
    local middle_y = (area.top + area.bottom) / 2
    local padding = screen.pixels(PADDING)
    local current = audio_output.current()
    local is_on = passthrough.is_on(current)

    if hovered_row == "passthrough" then
        canvas:add(draw.rectangle({
            area = area,
            color = style.HOVER_COLOR,
            opacity = style.HOVER_OPACITY / 2,
            corner_radius = screen.pixels(ROW_CORNER_RADIUS),
        }))
    end

    local state = "Off"
    local state_color = style.MUTED_TEXT_COLOR
    if is_on then
        state = "On"
        state_color = GOOD_COLOR
    end

    local state_right = area.right - padding / 2
    canvas:add(draw.text({
        x = state_right,
        y = middle_y,
        align = "right",
        vertical = "middle",
        text = state,
        size = screen.pixels(ROW_TEXT_SIZE),
        color = state_color,
    }))

    canvas:add(draw.text({
        x = area.left + padding / 2,
        y = middle_y,
        vertical = "middle",
        text = "Passthrough · " .. passthrough.describe_formats(current),
        size = screen.pixels(ROW_TEXT_SIZE),
        color = style.TEXT_COLOR,
        clip = {
            left = area.left,
            top = area.top,
            right = state_right - screen.pixels(40),
            bottom = area.bottom,
        },
    }))
end

local function render()
    if not is_open or not screen.is_ready() then
        canvas:clear()
        return
    end

    draw.set_overall_opacity(1)
    local layout = calculate_layout()
    local panel = layout.panel

    canvas:add(draw.rectangle({
        area = panel,
        color = style.BACKGROUND_COLOR,
        opacity = PANEL_OPACITY,
        corner_radius = screen.pixels(CORNER_RADIUS),
    }))

    add_header(panel)

    add_divider(panel, layout.divider_y)

    for _, row in ipairs(layout.rows) do
        add_row(row)
    end

    if layout.switch then
        add_passthrough_switch(panel, layout.switch)
    end

    canvas:show(screen.width, screen.height)
end

local clicks

local function close()
    if not is_open then
        return
    end
    is_open = false
    hovered_row = nil
    clicks:update(false)
    mp.remove_key_binding("output-popup-close")
    redraw.request()
end

-- While open, the popup takes every click. A click on an output switches
-- to it, a click elsewhere in the popup does nothing, and a click
-- anywhere else closes it, including on the output chip, which makes the
-- chip open and close it.
local function on_click()
    local layout = calculate_layout()

    -- The switch stays open after a click, so the change can be seen.
    if layout.switch and pointer.is_inside(layout.switch.area) then
        passthrough.toggle()
        redraw.request()
        return
    end

    for _, row in ipairs(layout.rows) do
        if pointer.is_inside(row.area) then
            if not row.output.is_current then
                audio_output.switch_to(row.output.mpv_name)
            end
            close()
            return
        end
    end

    if not pointer.is_inside(layout.panel) then
        close()
    end
end

clicks = click_area.create("output-popup", {
    priority = click_area.PRIORITY_POPUP,
    on_click = on_click,
})

local function open()
    popups.close_all_except("output-popup")

    -- The popup sits just above the controls, so bring them back if they
    -- had faded out, for example when it's opened with the o key.
    visibility.show_now()

    is_open = true
    clicks:update(true)
    mp.add_forced_key_binding("ESC", "output-popup-close", close)
    redraw.request()
end

-- Opens the popup if it's closed, and closes it if it's open.
function output_popup.toggle()
    if is_open then
        close()
    else
        open()
    end
end

-- Mouse movement happens constantly, so only redraw when the row under
-- the pointer changes.
local function on_pointer_moved()
    if not is_open then
        return
    end

    local layout = calculate_layout()
    local now_hovered = nil
    for _, row in ipairs(layout.rows) do
        if pointer.is_inside(row.area) then
            now_hovered = row.output.mpv_name
        end
    end
    if layout.switch and pointer.is_inside(layout.switch.area) then
        now_hovered = "passthrough"
    end

    if now_hovered ~= hovered_row then
        hovered_row = now_hovered
        redraw.request()
    end
end

function output_popup.start()
    popups.register("output-popup", close)
    redraw.register(render)
    screen.on_change(redraw.request)
    pointer.on_move(on_pointer_moved)
    audio_output.on_change(redraw.request)

    -- mpv's audio format changes after switching outputs, which can
    -- change the status line, so redraw when it does.
    mp.observe_property("audio-out-params", "native", function()
        if is_open then
            redraw.request()
        end
    end)

    -- Keep the controls showing while the popup is open, so it never
    -- floats on its own over the picture.
    visibility.keep_shown_while(output_popup.is_open)

    -- Named so input.conf can bind a key to it:
    --   o  script-binding visual_player/toggle-output-popup
    mp.add_key_binding(nil, "toggle-output-popup", output_popup.toggle)
end

return output_popup
