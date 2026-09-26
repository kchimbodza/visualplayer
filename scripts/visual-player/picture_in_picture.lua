-- Picture-in-picture: shrinks the window so the video can play in a
-- corner while you do something else. See docs/plan.md, Phase 5, step 3.
--
-- On Wayland, apps can't place their own windows, so Visual Player makes
-- the window small and you drag it where you like. Keeping it above other
-- windows depends on the desktop:
--   Hyprland: Visual Player floats and pins the window with hyprctl.
--   GNOME: apps can't do it themselves; press Alt+Space and choose
--          "Always on Top". mpv's ontop setting is set anyway, for
--          desktops that honor it.
--
-- While it's on, the normal controls step aside and a minimal set takes
-- over: play/pause in the middle, back to full size at the top left, and
-- close at the top right. Dragging anywhere else moves the window, since
-- there's no top bar to drag.

local click_area = require("click_area")
local display_output = require("outputs.display")
local draw = require("draw")
local pointer = require("pointer")
local redraw = require("redraw")
local screen = require("screen")
local style = require("style")
local visibility = require("visibility")

local picture_in_picture = {}

-- The window's width as a share of the screen's width.
local SHARE_OF_SCREEN_WIDTH = 0.25

-- Never smaller than the 240p minimum (see window_size.lua).
local NARROWEST_WIDTH = 426

-- Sizes in design pixels. See screen.lua.
local PLAY_BUTTON_SIZE = 64
local PLAY_ICON_SIZE = 34
local CORNER_BUTTON_SIZE = 36
local CORNER_ICON_SIZE = 20
local CORNER_MARGIN = 8

local BUTTON_BACKGROUND_OPACITY = 0.55

local canvas = draw.create_canvas({ layer = 1 })
local is_on = false
local hovered_button = nil

-- How the window was before picture-in-picture, to put it back after.
local saved = nil

function picture_in_picture.is_on()
    return is_on
end

local function is_hyprland()
    return os.getenv("HYPRLAND_INSTANCE_SIGNATURE") ~= nil
end

-- Runs a Hyprland command on the active window, in the background.
local function tell_hyprland(commands)
    mp.command_native_async({
        name = "subprocess",
        args = { "hyprctl", "--batch", commands },
        playback_only = false,
    }, function() end)
end

-- The screen's width in the desktop's own units, to size the window.
local function screen_width_in_desktop_units()
    local current_screen = display_output.current()
    if current_screen and current_screen.width then
        return current_screen.width / screen.hidpi_scale
    end
    return 1920
end

-- mpv sizes the window relative to the video, keeping its shape, and
-- applies the screen's scaling on top itself (as window_size.lua does).
local function set_window_width(width)
    local video = mp.get_property_native("video-params")
    if video and video.dw and video.dw > 0 then
        mp.set_property_number("window-scale", width / video.dw)
    end
end

local function turn_on()
    if mp.get_property_native("current-tracks/video") == nil then
        mp.osd_message("Picture-in-picture needs a video", 2)
        return
    end

    saved = {
        was_fullscreen = mp.get_property_bool("fullscreen", false),
        was_maximized = mp.get_property_bool("window-maximized", false),
        width = screen.width / screen.hidpi_scale,
    }

    mp.set_property_bool("fullscreen", false)
    mp.set_property_bool("window-maximized", false)

    local width = math.max(NARROWEST_WIDTH, screen_width_in_desktop_units() * SHARE_OF_SCREEN_WIDTH)
    set_window_width(width)
    mp.set_property_bool("ontop", true)

    -- With no top bar, the window is moved by dragging the picture, so
    -- mpv's window dragging is switched on (see top_bar.lua for why it's
    -- normally off).
    mp.set_property_bool("window-dragging", true)

    if is_hyprland() then
        tell_hyprland("dispatch setfloating active; dispatch pin active")
    end

    is_on = true
    visibility.show_now()
    redraw.request()
end

local function turn_off()
    if is_hyprland() then
        tell_hyprland("dispatch pin active")
    end
    mp.set_property_bool("ontop", false)
    mp.set_property_bool("window-dragging", false)

    if saved then
        set_window_width(saved.width)
        mp.set_property_bool("window-maximized", saved.was_maximized)
        mp.set_property_bool("fullscreen", saved.was_fullscreen)
    end

    is_on = false
    hovered_button = nil
    redraw.request()
end

function picture_in_picture.toggle()
    if is_on then
        turn_off()
    else
        turn_on()
    end
end

-- The three buttons and where they go in the small window.
local function calculate_buttons()
    local play_size = screen.pixels(PLAY_BUTTON_SIZE)
    local corner_size = screen.pixels(CORNER_BUTTON_SIZE)
    local margin = screen.pixels(CORNER_MARGIN)
    local middle_x = screen.width / 2
    local middle_y = screen.height / 2

    local play_icon = "player-pause"
    if mp.get_property_bool("pause", false) then
        play_icon = "player-play"
    end

    return {
        {
            name = "play-pause",
            icon = play_icon,
            icon_size = screen.pixels(PLAY_ICON_SIZE),
            area = {
                left = middle_x - play_size / 2,
                top = middle_y - play_size / 2,
                right = middle_x + play_size / 2,
                bottom = middle_y + play_size / 2,
            },
            action = function()
                mp.command("cycle pause")
            end,
        },
        {
            name = "full-size",
            icon = "picture-in-picture-off",
            icon_size = screen.pixels(CORNER_ICON_SIZE),
            area = {
                left = margin,
                top = margin,
                right = margin + corner_size,
                bottom = margin + corner_size,
            },
            action = turn_off,
        },
        {
            name = "close",
            icon = "x",
            icon_size = screen.pixels(CORNER_ICON_SIZE),
            area = {
                left = screen.width - margin - corner_size,
                top = margin,
                right = screen.width - margin,
                bottom = margin + corner_size,
            },
            action = function()
                mp.command("quit")
            end,
        },
    }
end

local function render()
    if not is_on or not visibility.is_shown() or not screen.is_ready() then
        canvas:clear()
        return
    end

    draw.set_overall_opacity(visibility.opacity())

    for _, button in ipairs(calculate_buttons()) do
        local area = button.area
        local opacity = BUTTON_BACKGROUND_OPACITY
        if button.name == hovered_button then
            opacity = BUTTON_BACKGROUND_OPACITY + 0.25
        end

        -- A dark circle behind each button keeps it visible over any
        -- picture, bright or dark.
        canvas:add(draw.circle({
            x = (area.left + area.right) / 2,
            y = (area.top + area.bottom) / 2,
            radius = (area.right - area.left) / 2,
            color = style.BACKGROUND_COLOR,
            opacity = opacity,
        }))
        canvas:add(draw.icon({
            name = button.icon,
            x = (area.left + area.right) / 2,
            y = (area.top + area.bottom) / 2,
            size = button.icon_size,
            color = style.TEXT_COLOR,
        }))
    end

    canvas:show(screen.width, screen.height)
end

local function find_button_under_pointer()
    for _, button in ipairs(calculate_buttons()) do
        if pointer.is_inside(button.area) then
            return button
        end
    end
    return nil
end

-- A click on a button runs it; anywhere else starts moving the window.
local function on_click()
    local button = find_button_under_pointer()
    if button then
        button.action()
    else
        mp.commandv("begin-vo-dragging")
    end
end

local clicks = click_area.create("picture-in-picture", { on_click = on_click })

local function on_pointer_moved()
    if not is_on then
        clicks:update(false)
        return
    end

    local button = nil
    if visibility.is_shown() then
        button = find_button_under_pointer()
    end

    local now_hovered = nil
    if button then
        now_hovered = button.name
    end

    if now_hovered ~= hovered_button then
        hovered_button = now_hovered
        redraw.request()
    end

    -- The whole small window takes clicks, for its buttons and for
    -- dragging it around.
    clicks:update(pointer.is_over_window)
end

function picture_in_picture.start()
    redraw.register(render)
    screen.on_change(redraw.request)
    pointer.on_move(on_pointer_moved)
    mp.observe_property("pause", "bool", function()
        if is_on then
            redraw.request()
        end
    end)

    -- Named so input.conf can bind a key to it:
    --   Alt+p  script-binding visual_player/toggle-picture-in-picture
    mp.add_key_binding(nil, "toggle-picture-in-picture", picture_in_picture.toggle)
end

return picture_in_picture
