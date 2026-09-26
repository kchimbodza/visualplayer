-- A popup list with sections, used by Visual Player's menus: "Audio &
-- subtitles" and "Chapters & playlist". See menus.lua.
--
-- Each menu sits just above the bottom controls, like the output popup,
-- lists its items under section headings with a check on the current
-- one, scrolls with the mouse wheel when it's too tall for the window,
-- and closes on a click outside it, on its button again, or on Esc.
--
-- Usage:
--   local menu = list_menu.create("audio-and-subtitles", function()
--       return {
--           { heading = "Audio", items = {
--               { label = "English", details = "Dolby Atmos 7.1 · TrueHD",
--                 is_current = true, action = function() ... end },
--           } },
--       }
--   end)
--   menu.toggle()
--
-- Items can also set is_disabled, to show a note that can't be clicked,
-- like "No chapters in this file".

local click_area = require("click_area")
local draw = require("draw")
local pointer = require("pointer")
local popups = require("popups")
local redraw = require("redraw")
local screen = require("screen")
local style = require("style")
local visibility = require("visibility")

local list_menu = {}

-- Sizes in design pixels. See screen.lua.
local WIDTH = 400
local PADDING = 12
local HEADING_SIZE = 13
local HEADING_HEIGHT = 30
local GAP_BETWEEN_SECTIONS = 8
local ROW_HEIGHT = 36
local LABEL_SIZE = 15
local DETAILS_SIZE = 13
local GAP_BEFORE_DETAILS = 10
local CHECK_SIZE = 16
local CORNER_RADIUS = 10
local ROW_CORNER_RADIUS = 6
local GAP_ABOVE_CONTROLS = 8

-- A menu never grows taller than this share of the window. Anything
-- more scrolls.
local TALLEST_SHARE_OF_WINDOW = 0.6

local PANEL_OPACITY = 0.88

function list_menu.create(name, build_sections)
    local menu = {}

    local canvas = draw.create_canvas({ layer = 2 })
    local is_open = false
    local hovered_line = nil
    local scroll = 0

    -- Where the menu's bottom-left corner goes, set by bottom_controls.lua.
    local anchor_bottom = 0
    local anchor_left = 0

    function menu.place_above(controls_top, left_edge)
        anchor_bottom = controls_top - screen.pixels(GAP_ABOVE_CONTROLS)
        anchor_left = left_edge
    end

    function menu.is_open()
        return is_open
    end

    -- Turns the sections into a list of lines, headings and items, each
    -- with its distance from the top of the list's content.
    local function build_lines()
        local lines = {}
        local offset = 0

        for section_index, section in ipairs(build_sections()) do
            if section_index > 1 then
                offset = offset + screen.pixels(GAP_BETWEEN_SECTIONS)
            end

            table.insert(lines, { heading = section.heading, offset = offset })
            offset = offset + screen.pixels(HEADING_HEIGHT)

            for _, item in ipairs(section.items) do
                table.insert(lines, { item = item, offset = offset })
                offset = offset + screen.pixels(ROW_HEIGHT)
            end
        end

        return lines, offset
    end

    -- Works out where everything goes. Used for drawing and for knowing
    -- which item the pointer is over.
    local function calculate_layout()
        local padding = screen.pixels(PADDING)
        local lines, content_height = build_lines()

        local tallest = screen.height * TALLEST_SHARE_OF_WINDOW
        local visible_height = math.min(content_height, tallest - padding * 2)

        -- Keep the scroll position within the content.
        scroll = math.max(0, math.min(scroll, content_height - visible_height))

        local width = math.min(screen.pixels(WIDTH), screen.width - anchor_left - padding)
        local panel = {
            left = anchor_left,
            top = anchor_bottom - visible_height - padding * 2,
            right = anchor_left + width,
            bottom = anchor_bottom,
        }
        local content_top = panel.top + padding
        local content_bottom = panel.bottom - padding

        -- Place each line, leaving out any that aren't fully in view.
        local placed = {}
        for index, line in ipairs(lines) do
            local height = screen.pixels(ROW_HEIGHT)
            if line.heading then
                height = screen.pixels(HEADING_HEIGHT)
            end

            local top = content_top + line.offset - scroll
            if top >= content_top - 1 and top + height <= content_bottom + 1 then
                line.index = index
                line.area = {
                    left = panel.left + padding / 2,
                    top = top,
                    right = panel.right - padding / 2,
                    bottom = top + height,
                }
                table.insert(placed, line)
            end
        end

        return { panel = panel, lines = placed }
    end

    local function add_heading(line)
        canvas:add(draw.text({
            x = line.area.left + screen.pixels(PADDING) / 2,
            y = line.area.bottom - screen.pixels(6),
            vertical = "bottom",
            text = line.heading,
            size = screen.pixels(HEADING_SIZE),
            bold = true,
            color = style.MUTED_TEXT_COLOR,
        }))
    end

    local function add_item(line)
        local item = line.item
        local area = line.area
        local middle_y = (area.top + area.bottom) / 2
        local padding = screen.pixels(PADDING)

        local is_hovered = line.index == hovered_line and not item.is_disabled
        local is_highlighted = item.is_current or is_hovered
        if is_highlighted then
            canvas:add(draw.rectangle({
                area = area,
                color = style.HOVER_COLOR,
                opacity = style.HOVER_OPACITY / 2,
                corner_radius = screen.pixels(ROW_CORNER_RADIUS),
            }))
        end

        local check_space = screen.pixels(CHECK_SIZE) + padding
        local clip = {
            left = area.left,
            top = area.top,
            right = area.right - check_space,
            bottom = area.bottom,
        }

        local label_left = area.left + padding / 2
        local label_size = screen.pixels(LABEL_SIZE)
        local label_color = style.TEXT_COLOR
        if item.is_disabled then
            label_color = style.MUTED_TEXT_COLOR
        end

        canvas:add(draw.text({
            x = label_left,
            y = middle_y,
            vertical = "middle",
            text = item.label,
            size = label_size,
            color = label_color,
            clip = clip,
        }))

        -- The details follow the label on the same line, in quieter text.
        if item.details and item.details ~= "" then
            local details_left = label_left
                + draw.estimate_text_width(item.label, label_size)
                + screen.pixels(GAP_BEFORE_DETAILS)
            canvas:add(draw.text({
                x = details_left,
                y = middle_y,
                vertical = "middle",
                text = item.details,
                size = screen.pixels(DETAILS_SIZE),
                color = style.MUTED_TEXT_COLOR,
                clip = clip,
            }))
        end

        if item.is_current then
            canvas:add(draw.icon({
                name = "check",
                x = area.right - padding / 2 - screen.pixels(CHECK_SIZE) / 2,
                y = middle_y,
                size = screen.pixels(CHECK_SIZE),
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

        for _, line in ipairs(layout.lines) do
            if line.heading then
                add_heading(line)
            else
                add_item(line)
            end
        end

        canvas:show(screen.width, screen.height)
    end

    local clicks

    local function close()
        if not is_open then
            return
        end
        is_open = false
        hovered_line = nil
        clicks:update(false)
        mp.remove_key_binding(name .. "-close")
        mp.remove_key_binding(name .. "-scroll-up")
        mp.remove_key_binding(name .. "-scroll-down")
        redraw.request()
    end

    -- While open, the menu takes every click: an item runs its action and
    -- closes the menu, and a click outside closes it.
    local function on_click()
        local layout = calculate_layout()

        for _, line in ipairs(layout.lines) do
            if line.item and pointer.is_inside(line.area) then
                if not line.item.is_disabled then
                    line.item.action()
                    close()
                end
                return
            end
        end

        if not pointer.is_inside(layout.panel) then
            close()
        end
    end

    clicks = click_area.create(name, { on_click = on_click })

    local function scroll_by(rows)
        scroll = scroll + rows * screen.pixels(ROW_HEIGHT)
        redraw.request()
    end

    local function open()
        popups.close_all_except(name)

        -- The menu sits just above the controls, so bring them back if
        -- they had faded out, for example when it's opened with a key.
        visibility.show_now()

        is_open = true
        scroll = 0
        clicks:update(true)
        mp.add_forced_key_binding("ESC", name .. "-close", close)

        -- While open, the mouse wheel scrolls the menu instead of
        -- changing the volume.
        mp.add_forced_key_binding("WHEEL_UP", name .. "-scroll-up", function()
            scroll_by(-1)
        end, { repeatable = true })
        mp.add_forced_key_binding("WHEEL_DOWN", name .. "-scroll-down", function()
            scroll_by(1)
        end, { repeatable = true })

        redraw.request()
    end

    function menu.toggle()
        if is_open then
            close()
        else
            open()
        end
    end


    -- Only redraw when the item under the pointer changes.
    local function on_pointer_moved()
        if not is_open then
            return
        end

        local now_hovered = nil
        for _, line in ipairs(calculate_layout().lines) do
            if line.item and pointer.is_inside(line.area) then
                now_hovered = line.index
            end
        end

        if now_hovered ~= hovered_line then
            hovered_line = now_hovered
            redraw.request()
        end
    end

    popups.register(name, close)
    redraw.register(render)
    screen.on_change(redraw.request)
    pointer.on_move(on_pointer_moved)

    -- Keep the controls showing while the menu is open, so it never
    -- floats on its own over the picture.
    visibility.keep_shown_while(menu.is_open)

    return menu
end

return list_menu
