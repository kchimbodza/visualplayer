-- The output popup: opened from the output chip, it shows where the
-- sound is going and what happens to it on the way, and lets you switch
-- to a different output. See docs/plan.md, 5.6.
--
-- Laid out as a card for the output in use, then the others (design B of
-- three, Phase 6, replacing a taller layout that showed the name twice,
-- had three dividers, and gave renaming a row of its own):
--
--   🖥  Ultimea D80 ✎                        [on]
--       Passthrough · Dolby Atmos 7.1
--       TrueHD  E-AC-3  AC-3  DTS-HD  DTS
--   Switch to
--   💻  Built-in speakers
--
-- Clicking the name or pencil renames the output in place: the name
-- becomes a text field, Enter saves, Esc cancels, and clicking outside it
-- saves. An empty name goes back to the detected one. The chips switch
-- passthrough formats on or off one by one, and the switch turns
-- passthrough itself on or off.
--
-- It's only about sound; the info panel's Screen row covers the picture.
-- It sits just above the controls on the right; bottom_controls.lua says
-- where.

local audio_output = require("outputs.audio")
local click_area = require("click_area")
local device_settings = require("outputs.device_settings")
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
local WIDTH = 340
local PADDING = 12
local GAP_ABOVE_CONTROLS = 8
local CORNER_RADIUS = 12

local CARD_ICON_SIZE = 22
local TEXT_LEFT = 42
local NAME_SIZE = 17
local STATUS_SIZE = 13
local GAP_BELOW_NAME = 4
local PENCIL_SIZE = 14
local GAP_BEFORE_PENCIL = 8

local SWITCH_WIDTH = 36
local SWITCH_HEIGHT = 20

local CHIP_HEIGHT = 24
local CHIP_TEXT_SIZE = 12
local CHIP_PADDING = 8
local CHIP_GAP = 5
local CHIP_CORNER_RADIUS = 6
local GAP_ABOVE_CHIPS = 10

local SWITCH_TO_SIZE = 12
local GAP_ABOVE_SWITCH_TO = 14
local ROW_HEIGHT = 34
local ROW_ICON_SIZE = 18
local ROW_TEXT_SIZE = 15
local ROW_CORNER_RADIUS = 6

local FIELD_PADDING = 6
local HINT_SIZE = 11

local PANEL_OPACITY = 0.9
local GOOD_COLOR = "#5DCAA5"
local WARNING_COLOR = "#EF9F27"
local SWITCH_OFF_COLOR = "#5F5E5A"

local OUTPUT_ICONS = {
    hdmi = "device-tv",
    displayport = "device-desktop",
    usb = "usb",
    speakers = "device-laptop",
    bluetooth = "bluetooth",
}

local canvas = draw.create_canvas({ layer = 2 })
local is_open = false
local hovered = nil

-- While renaming, the text typed so far; nil otherwise.
local editing_text = nil

-- Where the popup's bottom-right corner goes, set by bottom_controls.lua.
local anchor_bottom = 0
local anchor_right = 0

function output_popup.place_above(controls_top, right_edge)
    anchor_bottom = controls_top - screen.pixels(GAP_ABOVE_CONTROLS)
    anchor_right = right_edge
end

function output_popup.is_open()
    return is_open
end

-- The status line's color: green when the sound arrives in full or
-- untouched, amber when it's being squeezed into fewer channels.
local function status_color(status)
    if status:find("downmix") then
        return WARNING_COLOR
    end
    if status:find("^Full") or status:find("^Passthrough") then
        return GOOD_COLOR
    end
    return style.MUTED_TEXT_COLOR
end

-- The status line: what happens to the sound on its way, and when it's
-- passed through untouched, what's arriving, like "Passthrough · Dolby
-- Atmos 7.1".
local function describe_status(output)
    local path = info_details.describe_sound_path(output) or ""
    if path == "Passthrough" then
        local track = mp.get_property_native("current-tracks/audio")
        if track then
            return path .. " · " .. info_details.describe_audio_for_people(track)
        end
    end
    return path
end

-- Layout -------------------------------------------------------------------

-- Works out where everything goes. Used for drawing and for knowing what
-- the pointer is over.
local function calculate_layout()
    local padding = screen.pixels(PADDING)
    local current = audio_output.current()
    local has_switch = passthrough.is_possible(current)

    local others = {}
    for _, output in ipairs(audio_output.list()) do
        if not output.is_current then
            table.insert(others, output)
        end
    end

    -- The chips' widths, so the popup can be wide enough for them.
    local chips = {}
    local chips_width = 0
    if has_switch then
        for _, format in ipairs(passthrough.device_formats(current)) do
            local width = draw.estimate_text_width(
                passthrough.format_name(format),
                screen.pixels(CHIP_TEXT_SIZE)
            ) + screen.pixels(CHIP_PADDING) * 2
            table.insert(chips, { format = format, width = width })
            chips_width = chips_width + width + screen.pixels(CHIP_GAP)
        end
    end

    local text_left_offset = screen.pixels(TEXT_LEFT)
    local width = math.max(screen.pixels(WIDTH), padding + text_left_offset + chips_width + padding)
    width = math.min(width, screen.width - padding * 2)

    -- Heights, top to bottom.
    local name_size = screen.pixels(NAME_SIZE)
    local status_size = screen.pixels(STATUS_SIZE)
    if editing_text then
        name_size = name_size + screen.pixels(FIELD_PADDING) * 2
        status_size = screen.pixels(HINT_SIZE)
    end
    local card_height = name_size + screen.pixels(GAP_BELOW_NAME) + status_size
    local chips_height = 0
    if has_switch then
        chips_height = screen.pixels(GAP_ABOVE_CHIPS + CHIP_HEIGHT)
    end
    local others_height = 0
    if #others > 0 then
        others_height = screen.pixels(GAP_ABOVE_SWITCH_TO + SWITCH_TO_SIZE)
            + #others * screen.pixels(ROW_HEIGHT)
    end
    local height = padding * 2 + card_height + chips_height + others_height

    local panel = {
        left = anchor_right - width,
        top = anchor_bottom - height,
        right = anchor_right,
        bottom = anchor_bottom,
    }

    local text_left = panel.left + padding + text_left_offset
    local card_top = panel.top + padding

    -- The name, or the text field while renaming, and the pencil after it.
    local name_text = editing_text or (current and current.name) or "No output"
    local name_width = draw.estimate_text_width(name_text, screen.pixels(NAME_SIZE), true)
    local name_area = {
        left = text_left,
        top = card_top,
        right = text_left + name_width + screen.pixels(GAP_BEFORE_PENCIL + PENCIL_SIZE),
        bottom = card_top + name_size,
    }
    local field_area = nil
    if editing_text then
        field_area = {
            left = text_left - screen.pixels(FIELD_PADDING),
            top = card_top,
            right = panel.right - padding - screen.pixels(SWITCH_WIDTH) - padding,
            bottom = card_top + name_size,
        }
    end

    local switch_area = nil
    if has_switch then
        local middle = card_top + name_size / 2
        switch_area = {
            left = panel.right - padding - screen.pixels(SWITCH_WIDTH),
            top = middle - screen.pixels(SWITCH_HEIGHT) / 2,
            right = panel.right - padding,
            bottom = middle + screen.pixels(SWITCH_HEIGHT) / 2,
        }
    end

    local chips_top = card_top + card_height + screen.pixels(GAP_ABOVE_CHIPS)
    local chip_left = text_left
    for _, chip in ipairs(chips) do
        chip.area = {
            left = chip_left,
            top = chips_top,
            right = chip_left + chip.width,
            bottom = chips_top + screen.pixels(CHIP_HEIGHT),
        }
        chip_left = chip_left + chip.width + screen.pixels(CHIP_GAP)
    end

    local switch_to_top = card_top + card_height + chips_height + screen.pixels(GAP_ABOVE_SWITCH_TO)
    local rows_top = switch_to_top + screen.pixels(SWITCH_TO_SIZE)
    local rows = {}
    for index, output in ipairs(others) do
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

    return {
        panel = panel,
        current = current,
        card_top = card_top,
        name_size = name_size,
        text_left = text_left,
        name_text = name_text,
        name_width = name_width,
        name_area = name_area,
        field_area = field_area,
        switch_area = switch_area,
        chips = chips,
        switch_to_top = switch_to_top,
        rows = rows,
    }
end

-- Drawing ------------------------------------------------------------------

local function add_switch(area, is_on)
    local color = SWITCH_OFF_COLOR
    if is_on then
        color = GOOD_COLOR
    end
    local height = area.bottom - area.top
    canvas:add(draw.rectangle({
        area = area,
        color = color,
        opacity = 1,
        corner_radius = height / 2,
    }))

    local knob_radius = height / 2 - screen.pixels(2)
    local knob_x = area.left + height / 2
    if is_on then
        knob_x = area.right - height / 2
    end
    canvas:add(draw.circle({
        x = knob_x,
        y = (area.top + area.bottom) / 2,
        radius = knob_radius,
        color = style.TEXT_COLOR,
        opacity = 1,
    }))
end

local function add_card(layout)
    local current = layout.current
    local padding = screen.pixels(PADDING)
    local name_middle = layout.card_top + layout.name_size / 2

    canvas:add(draw.icon({
        name = OUTPUT_ICONS[current and current.kind] or "volume",
        x = layout.panel.left + padding + screen.pixels(CARD_ICON_SIZE) / 2,
        y = name_middle,
        size = screen.pixels(CARD_ICON_SIZE),
        color = style.TEXT_COLOR,
    }))

    local status_top = layout.card_top + layout.name_size + screen.pixels(GAP_BELOW_NAME)

    if editing_text then
        -- The text field: a box round the name, with a cursor after it.
        canvas:add(draw.rectangle({
            area = layout.field_area,
            color = style.BACKGROUND_COLOR,
            opacity = 0,
            corner_radius = screen.pixels(5),
            outline = {
                width = math.max(1, screen.pixels(1)),
                color = style.TEXT_COLOR,
                opacity = 0.6,
            },
        }))
        canvas:add(draw.text({
            x = layout.text_left,
            y = name_middle,
            vertical = "middle",
            text = editing_text,
            size = screen.pixels(NAME_SIZE),
            bold = true,
            color = style.TEXT_COLOR,
            clip = layout.field_area,
        }))
        local cursor_x = layout.text_left + layout.name_width + screen.pixels(1)
        canvas:add(draw.rectangle({
            area = {
                left = cursor_x,
                top = name_middle - screen.pixels(NAME_SIZE) / 2,
                right = cursor_x + math.max(1, screen.pixels(1.5)),
                bottom = name_middle + screen.pixels(NAME_SIZE) / 2,
            },
            color = style.TEXT_COLOR,
            opacity = 1,
        }))

        local detected = (current and current.detected_name) or ""
        canvas:add(draw.text({
            x = layout.text_left,
            y = status_top,
            text = "Enter to save · Esc to cancel · empty for " .. detected,
            size = screen.pixels(HINT_SIZE),
            color = style.MUTED_TEXT_COLOR,
        }))
    else
        canvas:add(draw.text({
            x = layout.text_left,
            y = name_middle,
            vertical = "middle",
            text = layout.name_text,
            size = screen.pixels(NAME_SIZE),
            bold = true,
            color = style.TEXT_COLOR,
        }))

        local pencil_opacity = 0.55
        if hovered == "name" then
            pencil_opacity = 1
        end
        canvas:add(draw.icon({
            name = "pencil",
            x = layout.text_left + layout.name_width
                + screen.pixels(GAP_BEFORE_PENCIL + PENCIL_SIZE / 2),
            y = name_middle,
            size = screen.pixels(PENCIL_SIZE),
            color = style.TEXT_COLOR,
            opacity = pencil_opacity,
        }))

        if current then
            local status = describe_status(current)
            canvas:add(draw.text({
                x = layout.text_left,
                y = status_top,
                text = status,
                size = screen.pixels(STATUS_SIZE),
                color = status_color(status),
            }))
        end
    end

    if layout.switch_area then
        add_switch(layout.switch_area, passthrough.is_on(current))
    end
end

-- The format chips: bright with an outline when that format is passed
-- through, dim when it's switched off and decoded instead. While
-- passthrough itself is off, they're all dim.
local function add_chips(layout)
    local is_on = passthrough.is_on(layout.current)
    for _, chip in ipairs(layout.chips) do
        local is_passed = is_on and not passthrough.is_format_off(layout.current, chip.format)
        local text_color = style.MUTED_TEXT_COLOR
        local outline_opacity = 0.2
        if is_passed then
            text_color = style.TEXT_COLOR
            outline_opacity = 0.55
        end
        if hovered == "chip:" .. chip.format then
            outline_opacity = outline_opacity + 0.25
        end

        canvas:add(draw.rectangle({
            area = chip.area,
            color = style.BACKGROUND_COLOR,
            opacity = 0,
            corner_radius = screen.pixels(CHIP_CORNER_RADIUS),
            outline = {
                width = math.max(1, screen.pixels(1)),
                color = style.TEXT_COLOR,
                opacity = outline_opacity,
            },
        }))
        canvas:add(draw.text({
            x = (chip.area.left + chip.area.right) / 2,
            y = (chip.area.top + chip.area.bottom) / 2,
            align = "center",
            vertical = "middle",
            text = passthrough.format_name(chip.format),
            size = screen.pixels(CHIP_TEXT_SIZE),
            color = text_color,
        }))
    end
end

local function add_other_outputs(layout)
    if #layout.rows == 0 then
        return
    end
    local padding = screen.pixels(PADDING)

    canvas:add(draw.text({
        x = layout.panel.left + padding,
        y = layout.switch_to_top,
        vertical = "bottom",
        text = "Switch to",
        size = screen.pixels(SWITCH_TO_SIZE),
        color = style.MUTED_TEXT_COLOR,
    }))

    for _, row in ipairs(layout.rows) do
        local area = row.area
        local middle_y = (area.top + area.bottom) / 2
        if hovered == row.output.mpv_name then
            canvas:add(draw.rectangle({
                area = area,
                color = style.HOVER_COLOR,
                opacity = style.HOVER_OPACITY / 2,
                corner_radius = screen.pixels(ROW_CORNER_RADIUS),
            }))
        end
        canvas:add(draw.icon({
            name = OUTPUT_ICONS[row.output.kind] or "volume",
            x = layout.panel.left + padding + screen.pixels(CARD_ICON_SIZE) / 2,
            y = middle_y,
            size = screen.pixels(ROW_ICON_SIZE),
            color = style.MUTED_TEXT_COLOR,
        }))
        canvas:add(draw.text({
            x = layout.text_left,
            y = middle_y,
            vertical = "middle",
            text = row.output.name,
            size = screen.pixels(ROW_TEXT_SIZE),
            color = style.TEXT_COLOR,
        }))
    end
end

local function render()
    if not is_open or not screen.is_ready() then
        canvas:clear()
        return
    end

    draw.set_overall_opacity(1)
    local layout = calculate_layout()

    canvas:add(draw.rectangle({
        area = layout.panel,
        color = style.BACKGROUND_COLOR,
        opacity = PANEL_OPACITY,
        corner_radius = screen.pixels(CORNER_RADIUS),
    }))
    add_card(layout)
    add_chips(layout)
    add_other_outputs(layout)

    canvas:show(screen.width, screen.height)
end

-- Renaming -----------------------------------------------------------------

local EDIT_KEYS = { "any_unicode", "BS", "ENTER", "KP_ENTER", "ESC", "Ctrl+u" }

local function stop_editing()
    for _, key in ipairs(EDIT_KEYS) do
        mp.remove_key_binding("output-popup-edit-" .. key)
    end
    editing_text = nil
    mp.add_forced_key_binding("ESC", "output-popup-close", function()
        output_popup.close()
    end)
    redraw.request()
end

-- Saves the typed name for the output in use. An empty name, or the
-- detected one, goes back to the detected name.
local function save_name()
    local output = audio_output.current()
    if output and editing_text then
        local name = editing_text:match("^%s*(.-)%s*$")
        if name == "" or name == output.detected_name then
            name = nil
        end
        device_settings.set(output, "name", name)
    end
    stop_editing()
    audio_output.refresh()
end

-- Removes the last character, which may be more than one byte in UTF-8.
local function without_last_character(text)
    return (text:gsub("[%z\1-\127\194-\244][\128-\191]*$", ""))
end

local function start_editing()
    local output = audio_output.current()
    if output == nil then
        return
    end
    editing_text = output.name or ""

    -- While renaming, the keyboard types into the name: letters are added,
    -- Backspace removes one, Ctrl+U clears it, Enter saves, Esc cancels.
    mp.remove_key_binding("output-popup-close")
    mp.add_forced_key_binding("any_unicode", "output-popup-edit-any_unicode", function(event)
        if event.event ~= "up" and event.key_text and editing_text then
            editing_text = editing_text .. event.key_text
            redraw.request()
        end
    end, { complex = true, repeatable = true })
    mp.add_forced_key_binding("BS", "output-popup-edit-BS", function()
        if editing_text then
            editing_text = without_last_character(editing_text)
            redraw.request()
        end
    end, { repeatable = true })
    mp.add_forced_key_binding("Ctrl+u", "output-popup-edit-Ctrl+u", function()
        editing_text = ""
        redraw.request()
    end)
    mp.add_forced_key_binding("ENTER", "output-popup-edit-ENTER", save_name)
    mp.add_forced_key_binding("KP_ENTER", "output-popup-edit-KP_ENTER", save_name)
    mp.add_forced_key_binding("ESC", "output-popup-edit-ESC", stop_editing)

    redraw.request()
end

-- Opening and closing ------------------------------------------------------

local clicks

function output_popup.close()
    if not is_open then
        return
    end
    if editing_text then
        save_name()
    end
    is_open = false
    hovered = nil
    clicks:update(false)
    mp.remove_key_binding("output-popup-close")
    redraw.request()
end

local function close()
    output_popup.close()
end

-- While open, the popup takes every click: the name starts renaming, the
-- switch and chips change passthrough, another output switches to it, and
-- a click outside closes the popup (saving a name being typed).
local function on_click()
    local layout = calculate_layout()

    if editing_text then
        if layout.field_area and pointer.is_inside(layout.field_area) then
            return
        end
        save_name()
        if pointer.is_inside(layout.panel) then
            return
        end
        close()
        return
    end

    if pointer.is_inside(layout.name_area) then
        start_editing()
        return
    end

    if layout.switch_area and pointer.is_inside(layout.switch_area) then
        passthrough.toggle()
        redraw.request()
        return
    end

    for _, chip in ipairs(layout.chips) do
        if pointer.is_inside(chip.area) then
            passthrough.toggle_format(chip.format)
            redraw.request()
            return
        end
    end

    for _, row in ipairs(layout.rows) do
        if pointer.is_inside(row.area) then
            audio_output.switch_to(row.output.mpv_name)
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

-- Mouse movement happens constantly, so only redraw when what's under the
-- pointer changes.
local function on_pointer_moved()
    if not is_open then
        return
    end

    local layout = calculate_layout()
    local now_hovered = nil
    if not editing_text and pointer.is_inside(layout.name_area) then
        now_hovered = "name"
    end
    for _, chip in ipairs(layout.chips) do
        if pointer.is_inside(chip.area) then
            now_hovered = "chip:" .. chip.format
        end
    end
    for _, row in ipairs(layout.rows) do
        if pointer.is_inside(row.area) then
            now_hovered = row.output.mpv_name
        end
    end

    if now_hovered ~= hovered then
        hovered = now_hovered
        redraw.request()
    end
end

function output_popup.start()
    popups.register("output-popup", close)
    redraw.register(render)
    screen.on_change(redraw.request)
    pointer.on_move(on_pointer_moved)
    audio_output.on_change(redraw.request)

    -- mpv's audio format changes after switching outputs or tracks, which
    -- can change the status line, so redraw when it does.
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
