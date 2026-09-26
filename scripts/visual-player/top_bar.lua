-- The bar across the top of the window: title, subtitle, clock, and
-- window buttons. See docs/plan.md, section 5.2.
--
-- It also acts as the window's title bar. mpv can't draw a real one on
-- GNOME (Nobara's mpv is built without libdecor), so dragging the bar
-- moves the window, double-clicking it maximizes, and on GNOME it shows
-- minimize, maximize, and close buttons.

local click_area = require("click_area")
local draw = require("draw")
local picture_in_picture = require("picture_in_picture")
local pointer = require("pointer")
local redraw = require("redraw")
local screen = require("screen")
local style = require("style")
local visibility = require("visibility")

local top_bar = {}

-- Sizes in design pixels. See screen.lua.
local BAR_HEIGHT = 72
local SIDE_MARGIN = 20
local TOP_MARGIN = 14
local TITLE_SIZE = 20
local SUBTITLE_SIZE = 15
local GAP_BETWEEN_LINES = 4
local CLOCK_SIZE = TITLE_SIZE
local WINDOW_BUTTON_SIZE = 32
local WINDOW_BUTTON_ICON_SIZE = 18
local GAP_BETWEEN_WINDOW_BUTTONS = 4
local GAP_BEFORE_WINDOW_BUTTONS = 16
local GAP_BETWEEN_TITLE_AND_CLOCK = 24

-- The background darkens the top of the video so white text stays
-- readable, fading out towards the bottom of the bar. ASS can't draw
-- gradients, so this is one dark rectangle with a blurred bottom edge.
-- (Stacked strips were tried first, but showed thin seams where the
-- strips met.) The rectangle reaches past the top and sides of the
-- window, so only its bottom edge fades within view. Its color and
-- strength come from style.lua.
--
-- Where the fade is centered, and how far it spreads, as fractions of
-- the bar's height.
local BACKGROUND_FADE_CENTER = 0.55
local BACKGROUND_FADE_SPREAD = 0.45

local DAY_NAMES = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local MONTH_NAMES = {
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
}

-- How often to check whether the clock's minute has changed.
local CLOCK_CHECK_SECONDS = 5

local canvas = draw.create_canvas()

-- Whether mpv's window dragging is switched on. It's on only while the
-- pointer is over the bar. Everywhere else it has to be off, or it grabs
-- the mouse before the seek bar and volume slider can be dragged (Phase
-- 2, step 4). But with it off, mpv also ignores the bar's own request to
-- move the window (Phase 4, step 3), so the bar turns it back on.
local is_window_dragging_on = false

local hovered_button_name = nil

local title_text = ""
local subtitle_text = ""
local clock_text = ""

-- Window buttons only make sense on desktops that expect apps to draw
-- their own title bars. Tiling desktops like Hyprland don't use them.
local function should_show_window_buttons()
    local desktop = os.getenv("XDG_CURRENT_DESKTOP") or ""
    return desktop:find("GNOME") ~= nil
end

local WINDOW_BUTTONS = {
    {
        name = "minimize",
        icon = "minus",
        action = function()
            mp.set_property_bool("window-minimized", true)
        end,
    },
    {
        name = "maximize",
        icon = "square",
        action = function()
            mp.commandv("cycle", "window-maximized")
        end,
    },
    {
        name = "close",
        icon = "x",
        action = function()
            mp.command("quit")
        end,
    },
}

local function format_clock()
    local now = os.date("*t")

    local hour = now.hour % 12
    if hour == 0 then
        hour = 12
    end

    local period = "AM"
    if now.hour >= 12 then
        period = "PM"
    end

    return string.format(
        "%s, %s %d · %d:%02d %s",
        DAY_NAMES[now.wday],
        MONTH_NAMES[now.month],
        now.day,
        hour,
        now.min,
        period
    )
end

-- Finds a season and episode in names like "Show.S01E04" or "Show 1x04",
-- and returns them as "S1 · E4", or nil if there isn't one.
local function find_episode(text)
    local season, episode = text:match("[Ss](%d+)[%s%._-]*[Ee](%d+)")

    -- The %f frontiers stop this matching inside numbers like 1920x1080.
    if season == nil then
        season, episode = text:match("%f[%d](%d%d?)x(%d%d)%f[%D]")
    end

    if season == nil then
        return nil
    end

    return string.format("S%d · E%d", tonumber(season), tonumber(episode))
end

-- Returns the current chapter's name, "Chapter 3" if it has none, or nil
-- if the file has no chapters.
local function describe_current_chapter()
    local chapter_index = mp.get_property_number("chapter")
    local chapters = mp.get_property_native("chapter-list") or {}

    if chapter_index == nil or chapter_index < 0 or #chapters == 0 then
        return nil
    end

    -- mpv counts chapters from 0, Lua lists from 1.
    local chapter = chapters[chapter_index + 1]
    if chapter and chapter.title and chapter.title ~= "" then
        return chapter.title
    end

    return "Chapter " .. (chapter_index + 1)
end

-- Uses the file's own title when it has one. When mpv falls back to the
-- file name, the extension is dropped, since ".mkv" isn't part of a title.
local function update_title()
    local title = mp.get_property("media-title", "")

    if title == mp.get_property("filename") then
        title = mp.get_property("filename/no-ext", title)
    end

    title_text = title
end

local function update_subtitle()
    local parts = {}

    local episode = find_episode(mp.get_property("filename", ""))
    if episode then
        table.insert(parts, episode)
    end

    local chapter = describe_current_chapter()
    if chapter then
        table.insert(parts, chapter)
    end

    subtitle_text = table.concat(parts, " · ")
end

-- Works out where everything goes for the current window size. Used both
-- for drawing and for knowing what the pointer is over.
local function calculate_layout()
    local layout = {}

    layout.bar = {
        left = 0,
        top = 0,
        right = screen.width,
        bottom = screen.pixels(BAR_HEIGHT),
    }

    local right_edge = screen.width - screen.pixels(SIDE_MARGIN)
    local first_line_middle = screen.pixels(TOP_MARGIN + TITLE_SIZE / 2)

    -- Window buttons sit at the far right, laid out from right to left.
    layout.buttons = {}
    if should_show_window_buttons() then
        local size = screen.pixels(WINDOW_BUTTON_SIZE)
        local gap = screen.pixels(GAP_BETWEEN_WINDOW_BUTTONS)

        for index = #WINDOW_BUTTONS, 1, -1 do
            local button = WINDOW_BUTTONS[index]
            layout.buttons[index] = {
                button = button,
                area = {
                    left = right_edge - size,
                    top = first_line_middle - size / 2,
                    right = right_edge,
                    bottom = first_line_middle + size / 2,
                },
            }
            right_edge = right_edge - size - gap
        end

        right_edge = right_edge + gap - screen.pixels(GAP_BEFORE_WINDOW_BUTTONS)
    end

    layout.clock_right = right_edge
    layout.clock_middle = first_line_middle

    local clock_width = draw.estimate_text_width(clock_text, screen.pixels(CLOCK_SIZE))
    layout.title_area = {
        left = screen.pixels(SIDE_MARGIN),
        top = 0,
        right = right_edge - clock_width - screen.pixels(GAP_BETWEEN_TITLE_AND_CLOCK),
        bottom = layout.bar.bottom,
    }

    return layout
end

local function find_hovered_button(layout)
    for _, placed in ipairs(layout.buttons) do
        if pointer.is_inside(placed.area) then
            return placed.button.name
        end
    end
    return nil
end

local function add_background(bar)
    local bar_height = bar.bottom - bar.top
    local blur = bar_height * BACKGROUND_FADE_SPREAD

    canvas:add(draw.rectangle({
        area = {
            left = bar.left - blur,
            top = bar.top - bar_height,
            right = bar.right + blur,
            bottom = bar.top + bar_height * BACKGROUND_FADE_CENTER,
        },
        color = style.BACKGROUND_COLOR,
        opacity = style.BACKGROUND_OPACITY,
        blur = blur,
    }))
end

local function add_title_and_subtitle(title_area)
    local title_top = screen.pixels(TOP_MARGIN)

    canvas:add(draw.text({
        x = title_area.left,
        y = title_top,
        text = title_text,
        size = screen.pixels(TITLE_SIZE),
        color = style.TEXT_COLOR,
        clip = title_area,
    }))

    if subtitle_text ~= "" then
        canvas:add(draw.text({
            x = title_area.left,
            y = title_top + screen.pixels(TITLE_SIZE + GAP_BETWEEN_LINES),
            text = subtitle_text,
            size = screen.pixels(SUBTITLE_SIZE),
            color = style.MUTED_TEXT_COLOR,
            clip = title_area,
        }))
    end
end

local function add_window_buttons(buttons)
    for _, placed in ipairs(buttons) do
        local area = placed.area
        local middle_x = (area.left + area.right) / 2
        local middle_y = (area.top + area.bottom) / 2

        if placed.button.name == hovered_button_name then
            canvas:add(draw.circle({
                x = middle_x,
                y = middle_y,
                radius = (area.right - area.left) / 2,
                color = style.HOVER_COLOR,
                opacity = style.HOVER_OPACITY,
            }))
        end

        canvas:add(draw.icon({
            name = placed.button.icon,
            x = middle_x,
            y = middle_y,
            size = screen.pixels(WINDOW_BUTTON_ICON_SIZE),
            color = style.TEXT_COLOR,
        }))
    end
end

local function render()
    -- Picture-in-picture has its own minimal controls instead.
    local is_hidden = not visibility.is_shown() or picture_in_picture.is_on()
    if is_hidden or not screen.is_ready() then
        canvas:clear()
        return
    end

    draw.set_overall_opacity(visibility.opacity())

    local layout = calculate_layout()

    add_background(layout.bar)
    add_title_and_subtitle(layout.title_area)

    canvas:add(draw.text({
        x = layout.clock_right,
        y = layout.clock_middle,
        align = "right",
        vertical = "middle",
        text = clock_text,
        size = screen.pixels(CLOCK_SIZE),
        color = style.MUTED_TEXT_COLOR,
    }))

    add_window_buttons(layout.buttons)

    canvas:show(screen.width, screen.height)
end

-- A click on a window button runs it; a click anywhere else on the bar
-- starts moving the window, like a normal title bar.
local function on_click()
    local layout = calculate_layout()
    for _, placed in ipairs(layout.buttons) do
        if pointer.is_inside(placed.area) then
            placed.button.action()
            return
        end
    end

    mp.commandv("begin-vo-dragging")
end

local function on_double_click()
    mp.commandv("cycle", "window-maximized")
end

-- The bar takes over mouse clicks only while the pointer is over it.
local clicks = click_area.create("top-bar", {
    priority = click_area.PRIORITY_CONTROLS,
    on_click = on_click,
    on_double_click = on_double_click,
})

-- Mouse movement happens constantly, so only ask for a redraw when
-- something visible actually changes.
local function on_pointer_moved()
    local layout = calculate_layout()

    local now_hovered = find_hovered_button(layout)
    if now_hovered ~= hovered_button_name then
        hovered_button_name = now_hovered
        redraw.request()
    end

    -- Hidden controls don't take clicks.
    local is_over_bar = visibility.is_shown()
        and not picture_in_picture.is_on()
        and pointer.is_inside(layout.bar)
    clicks:update(is_over_bar)

    -- In picture-in-picture, picture_in_picture.lua looks after it.
    if is_over_bar ~= is_window_dragging_on and not picture_in_picture.is_on() then
        mp.set_property_bool("window-dragging", is_over_bar)
        is_window_dragging_on = is_over_bar
    end
end

-- Keeps the controls from hiding while the pointer rests on the bar.
local function is_pointer_over_bar()
    return pointer.is_inside(calculate_layout().bar)
end

local function on_title_changed()
    update_title()
    update_subtitle()
    redraw.request()
end

local function on_chapter_changed()
    update_subtitle()
    redraw.request()
end

local function check_clock()
    local new_clock_text = format_clock()
    if new_clock_text ~= clock_text then
        clock_text = new_clock_text
        redraw.request()
    end
end

-- Where the bar ends, so taps below it count as taps on the video.
function top_bar.bottom_edge()
    return screen.pixels(BAR_HEIGHT)
end

function top_bar.start()
    clock_text = format_clock()

    redraw.register(render)
    screen.on_change(redraw.request)
    pointer.on_move(on_pointer_moved)
    visibility.keep_shown_while(is_pointer_over_bar)

    mp.observe_property("media-title", "string", on_title_changed)
    mp.observe_property("chapter", "number", on_chapter_changed)
    mp.observe_property("chapter-list", "native", on_chapter_changed)
    mp.add_periodic_timer(CLOCK_CHECK_SECONDS, check_clock)
end

return top_bar
