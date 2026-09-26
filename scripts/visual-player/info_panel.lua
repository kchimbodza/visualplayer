-- The info panel: a small panel docked to the right edge of the window
-- that says what's playing and how well. See docs/plan.md, 5.5.
--
-- Each row has an icon, a headline, and a quieter technical line. What
-- the rows say comes from info_details.lua; this file draws them.
--
-- The panel opens and closes with the info button or the I key, and
-- stays open until closed, rather than hiding with the other controls,
-- since it's opened to keep an eye on something.

local audio_output = require("outputs.audio")
local draw = require("draw")
local info_details = require("info_details")
local redraw = require("redraw")
local screen = require("screen")
local style = require("style")

local info_panel = {}

-- Sizes in design pixels. See screen.lua.
local TOP_OFFSET = 80
local PADDING = 14
local ICON_SIZE = 18
local ICON_COLUMN_WIDTH = 28
local HEADLINE_SIZE = 17
local DETAILS_SIZE = 14
local GAP_BETWEEN_LINES = 3
local GAP_BETWEEN_ROWS = 12
local CORNER_RADIUS = 10
local STATUS_DOT_RADIUS = 5
local NARROWEST_WIDTH = 260

-- The panel never takes up more than this share of the window's width.
local WIDEST_SHARE_OF_WINDOW = 0.45

local PANEL_OPACITY = 0.78

-- How often to check for changes while the panel is open.
local REFRESH_SECONDS = 1

local canvas = draw.create_canvas()
local is_open = false
local refresh_timer = nil

-- The rows as last drawn, so the panel only redraws when they change.
local drawn_rows_text = nil

local function rows_as_text(rows)
    local lines = {}
    for _, row in ipairs(rows) do
        table.insert(lines, row.headline .. "|" .. row.details)
    end
    return table.concat(lines, "\n")
end

local function measure_width(rows)
    local text_width = 0
    for _, row in ipairs(rows) do
        text_width = math.max(
            text_width,
            draw.estimate_text_width(row.headline, screen.pixels(HEADLINE_SIZE)),
            draw.estimate_text_width(row.details, screen.pixels(DETAILS_SIZE))
        )
    end

    local width = screen.pixels(PADDING * 2 + ICON_COLUMN_WIDTH) + text_width
    width = math.max(width, screen.pixels(NARROWEST_WIDTH))
    return math.min(width, screen.width * WIDEST_SHARE_OF_WINDOW)
end

local function row_height()
    return screen.pixels(HEADLINE_SIZE + GAP_BETWEEN_LINES + DETAILS_SIZE)
end

-- Draws a row's icon, or the colored dot for the status row.
local function add_row_marker(row, x, y)
    if row.dot then
        canvas:add(draw.circle({
            x = x,
            y = y,
            radius = screen.pixels(STATUS_DOT_RADIUS),
            color = row.dot_color,
        }))
        return
    end

    canvas:add(draw.icon({
        name = row.icon,
        x = x,
        y = y,
        size = screen.pixels(ICON_SIZE),
        color = style.MUTED_TEXT_COLOR,
    }))
end

local function add_row(row, left, top, text_clip)
    local headline_size = screen.pixels(HEADLINE_SIZE)
    local marker_x = left + screen.pixels(ICON_COLUMN_WIDTH) / 2
    local text_left = left + screen.pixels(ICON_COLUMN_WIDTH)

    add_row_marker(row, marker_x, top + headline_size / 2)

    canvas:add(draw.text({
        x = text_left,
        y = top,
        text = row.headline,
        size = headline_size,
        color = style.TEXT_COLOR,
        clip = text_clip,
    }))
    canvas:add(draw.text({
        x = text_left,
        y = top + headline_size + screen.pixels(GAP_BETWEEN_LINES),
        text = row.details,
        size = screen.pixels(DETAILS_SIZE),
        color = style.MUTED_TEXT_COLOR,
        clip = text_clip,
    }))
end

local function render()
    if not is_open or not screen.is_ready() then
        canvas:clear()
        drawn_rows_text = nil
        return
    end

    -- The panel stays fully visible while open, even while the other
    -- controls fade out.
    draw.set_overall_opacity(1)

    local rows = info_details.rows()
    local padding = screen.pixels(PADDING)
    local width = measure_width(rows)
    local height = padding * 2
        + #rows * row_height()
        + math.max(0, #rows - 1) * screen.pixels(GAP_BETWEEN_ROWS)

    local panel = {
        left = screen.width - width,
        top = screen.pixels(TOP_OFFSET),
        right = screen.width,
        bottom = screen.pixels(TOP_OFFSET) + height,
    }

    -- The panel sits flush against the right edge, so its right-hand
    -- corners are pushed just past the edge, leaving only the left-hand
    -- corners rounded.
    local radius = screen.pixels(CORNER_RADIUS)
    canvas:add(draw.rectangle({
        area = {
            left = panel.left,
            top = panel.top,
            right = panel.right + radius,
            bottom = panel.bottom,
        },
        color = style.BACKGROUND_COLOR,
        opacity = PANEL_OPACITY,
        corner_radius = radius,
    }))

    -- Long text is cut off at the panel's inner edge rather than
    -- running past it.
    local text_clip = {
        left = panel.left,
        top = panel.top,
        right = panel.right - padding,
        bottom = panel.bottom,
    }

    local row_top = panel.top + padding
    for _, row in ipairs(rows) do
        add_row(row, panel.left + padding, row_top, text_clip)
        row_top = row_top + row_height() + screen.pixels(GAP_BETWEEN_ROWS)
    end

    canvas:show(screen.width, screen.height)
    drawn_rows_text = rows_as_text(rows)
end

-- Redraws only if something the panel shows has changed.
local function refresh()
    if not is_open then
        return
    end

    if rows_as_text(info_details.rows()) ~= drawn_rows_text then
        redraw.request()
    end
end

-- Opens the panel if it's closed, and closes it if it's open.
function info_panel.toggle()
    is_open = not is_open

    if is_open then
        refresh_timer:resume()
    else
        refresh_timer:kill()
    end

    redraw.request()
end

function info_panel.start()
    refresh_timer = mp.add_periodic_timer(REFRESH_SECONDS, refresh)
    refresh_timer:kill()

    info_details.start()

    redraw.register(render)
    screen.on_change(redraw.request)

    -- Changes that should show straight away, rather than at the next
    -- once-a-second check.
    mp.register_event("file-loaded", refresh)
    mp.observe_property("current-tracks/audio", "native", refresh)
    mp.observe_property("current-tracks/sub", "native", refresh)
    mp.observe_property("video-params", "native", refresh)
    mp.observe_property("audio-out-params", "native", refresh)
    audio_output.on_change(refresh)

    -- Named so input.conf can bind a key to it:
    --   i  script-binding visual_player/toggle-info-panel
    mp.add_key_binding(nil, "toggle-info-panel", info_panel.toggle)
end

return info_panel
