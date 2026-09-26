-- A temporary test card for the drawing toolkit (Phase 2, step 1).
--
-- Shows every icon Visual Player uses, plus sample shapes and text, so we
-- can check that the icon font loads and that everything is sized
-- correctly on each screen. Press Ctrl+t to hide or show it.
--
-- This file goes away once the real controls arrive.

local draw = require("draw")
local icons = require("icons")
local screen = require("screen")

local toolkit_preview = {}

-- Sizes in design pixels. See screen.lua.
local PANEL_PADDING = 24
local ICON_SIZE = 28
local ICON_CELL_SIZE = 48
local ICONS_PER_ROW = 12
local TITLE_SIZE = 20
local LABEL_SIZE = 16
local SECTION_GAP = 20

local PANEL_COLOR = "#000000"
local PANEL_OPACITY = 0.75
local TEXT_COLOR = "#F2F2F2"
local MUTED_TEXT_COLOR = "#9A9A9A"
local SMOOTH_COLOR = "#5DCAA5"
local WARNING_BACKGROUND = "#633806"
local WARNING_TEXT = "#FAC775"

local canvas = draw.create_canvas()
local is_visible = true

local function get_icon_names_in_order()
    local names = {}
    for name in pairs(icons.codepoints) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

-- Draws the icons in a grid starting at the given top-left point, and
-- returns the height the grid took up.
local function add_icon_grid(icon_names, left, top)
    local cell = screen.pixels(ICON_CELL_SIZE)

    for index, name in ipairs(icon_names) do
        local column = (index - 1) % ICONS_PER_ROW
        local row = math.floor((index - 1) / ICONS_PER_ROW)

        canvas:add(draw.icon({
            name = name,
            x = left + column * cell + cell / 2,
            y = top + row * cell + cell / 2,
            size = screen.pixels(ICON_SIZE),
            color = TEXT_COLOR,
        }))
    end

    local row_count = math.ceil(#icon_names / ICONS_PER_ROW)
    return row_count * cell
end

-- Draws the sample status line and warning pill, like the ones in the
-- info panel and output popup designs.
local function add_samples(left, top)
    local dot_radius = screen.pixels(5)
    local label_size = screen.pixels(LABEL_SIZE)
    local middle = top + label_size / 2

    canvas:add(draw.circle({
        x = left + dot_radius,
        y = middle,
        radius = dot_radius,
        color = SMOOTH_COLOR,
    }))
    canvas:add(draw.text({
        x = left + dot_radius * 2 + screen.pixels(8),
        y = middle,
        vertical = "middle",
        text = "Playing smoothly",
        size = label_size,
        color = TEXT_COLOR,
    }))

    local pill_left = left + screen.pixels(190)
    local pill_padding = screen.pixels(8)
    local pill_width = screen.pixels(128)
    canvas:add(draw.rectangle({
        area = {
            left = pill_left,
            top = middle - label_size / 2 - pill_padding / 2,
            right = pill_left + pill_width,
            bottom = middle + label_size / 2 + pill_padding / 2,
        },
        color = WARNING_BACKGROUND,
        corner_radius = screen.pixels(4),
    }))
    canvas:add(draw.text({
        x = pill_left + pill_width / 2,
        y = middle,
        align = "center",
        vertical = "middle",
        text = "Stereo downmix",
        size = label_size,
        color = WARNING_TEXT,
    }))
end

local function render()
    if not is_visible or not screen.is_ready() then
        canvas:clear()
        return
    end

    local icon_names = get_icon_names_in_order()
    local padding = screen.pixels(PANEL_PADDING)
    local gap = screen.pixels(SECTION_GAP)
    local title_size = screen.pixels(TITLE_SIZE)
    local label_size = screen.pixels(LABEL_SIZE)
    local grid_width = ICONS_PER_ROW * screen.pixels(ICON_CELL_SIZE)
    local grid_height = math.ceil(#icon_names / ICONS_PER_ROW) * screen.pixels(ICON_CELL_SIZE)

    local panel_width = padding * 2 + grid_width
    local panel_height = padding * 2 + title_size + gap + label_size + gap
        + grid_height + gap + label_size
    local panel = {
        left = (screen.width - panel_width) / 2,
        top = (screen.height - panel_height) / 2,
        right = (screen.width + panel_width) / 2,
        bottom = (screen.height + panel_height) / 2,
    }

    canvas:add(draw.rectangle({
        area = panel,
        color = PANEL_COLOR,
        opacity = PANEL_OPACITY,
        corner_radius = screen.pixels(12),
    }))

    local left = panel.left + padding
    local next_top = panel.top + padding

    canvas:add(draw.text({
        x = left,
        y = next_top,
        text = "Drawing toolkit preview",
        size = title_size,
        bold = true,
        color = TEXT_COLOR,
    }))
    next_top = next_top + title_size + gap

    local font_summary = string.format(
        "%d icons from %s %s · Ctrl+T to hide",
        #icon_names,
        icons.font_family,
        icons.font_version
    )
    if #icon_names == 0 then
        font_summary = "No icons yet: run ./tools/update-icon-font.py"
    end
    canvas:add(draw.text({
        x = left,
        y = next_top,
        text = font_summary,
        size = label_size,
        color = MUTED_TEXT_COLOR,
    }))
    next_top = next_top + label_size + gap

    next_top = next_top + add_icon_grid(icon_names, left, next_top) + gap
    add_samples(left, next_top)

    canvas:show(screen.width, screen.height)
end

local function toggle()
    is_visible = not is_visible
    render()
end

function toolkit_preview.start()
    screen.on_change(render)
    mp.add_key_binding("Ctrl+t", "toggle-toolkit-preview", toggle)
end

return toolkit_preview
