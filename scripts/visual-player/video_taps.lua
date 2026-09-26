-- Taps on the video itself, when touch controls are on. See docs/plan.md,
-- section 5.9.
--
--   One tap                 shows or hides the controls
--   Two taps, left third    skips back 10 seconds
--   Two taps, right third   skips forward 10 seconds
--   Two taps, middle        switches fullscreen on or off
--
-- Pressing and moving instead drags the window, the way most players
-- work. A tap and a drag are told apart by whether the pointer moves while
-- pressed, which works the same for a finger and a mouse (mpv can't tell
-- them apart). Before this, a press on the picture was always a tap, so
-- with a touchscreen detected, the window couldn't be dragged by the
-- picture even with a mouse (Phase 6, on the ASUS ProArt PX13).
--
-- A finger can't hover, so moving the pointer doesn't show the controls
-- when touch controls are on (see visibility.lua); a tap does instead.
-- After a tap, this waits briefly to see whether a second tap follows,
-- so a double tap isn't mistaken for two single taps.

local bottom_controls = require("bottom_controls")
local click_area = require("click_area")
local menus = require("menus")
local output_popup = require("output_popup")
local picture_in_picture = require("picture_in_picture")
local pointer = require("pointer")
local screen = require("screen")
local settings_menu = require("settings_menu")
local top_bar = require("top_bar")
local touch = require("touch")
local visibility = require("visibility")

local video_taps = {}

-- How long to wait for a second tap.
local DOUBLE_TAP_SECONDS = 0.3

local SKIP_SECONDS = 10

-- How far the pointer moves while pressed before it's a drag rather than
-- a tap, in design pixels (see screen.lua).
local DRAG_DISTANCE = 10

local single_tap_timer = nil

-- Where the current press started, and whether it's turned into a drag.
local press = nil

local function is_any_popup_open()
    return output_popup.is_open()
        or menus.is_any_open()
        or settings_menu.is_open()
        or picture_in_picture.is_on()
end

-- True while the pointer is over the picture rather than the controls.
-- Hidden controls don't count, so a tap anywhere brings them back.
local function is_pointer_over_video()
    if not pointer.is_over_window then
        return false
    end
    if not visibility.is_shown() then
        return true
    end
    return pointer.y > top_bar.bottom_edge() and pointer.y < bottom_controls.top_edge()
end

local function on_single_tap()
    visibility.toggle()
end

local function on_double_tap(x)
    local third = screen.width / 3

    if x < third then
        mp.commandv("seek", tostring(-SKIP_SECONDS), "relative")
    elseif x > third * 2 then
        mp.commandv("seek", tostring(SKIP_SECONDS), "relative")
    else
        mp.command("cycle fullscreen")
    end
end

local function on_tap()
    if single_tap_timer and single_tap_timer:is_enabled() then
        single_tap_timer:kill()
        on_double_tap(pointer.x)
        return
    end

    single_tap_timer:kill()
    single_tap_timer:resume()
end

-- A press starts either a tap or a drag; which one is decided by whether
-- the pointer moves (on_pointer_moved) before it's released.
local function on_press()
    -- A drag hands the pointer to the desktop, so its release may never
    -- arrive; tidy up after one here instead.
    if press and press.is_drag then
        mp.set_property_bool("window-dragging", false)
    end
    press = { x = pointer.x, y = pointer.y, is_drag = false }
end

local function on_release()
    local was_drag = press and press.is_drag
    press = nil

    if was_drag then
        mp.set_property_bool("window-dragging", false)
        return
    end
    on_tap()
end

-- Moving far enough while pressed turns the press into a drag of the
-- window. mpv's window-dragging is switched on just for it, since it's
-- normally off so it can't fight the seek bar (see top_bar.lua).
local function start_drag_if_moved()
    if press == nil or press.is_drag then
        return
    end

    local distance = math.sqrt((pointer.x - press.x) ^ 2 + (pointer.y - press.y) ^ 2)
    if distance < screen.pixels(DRAG_DISTANCE) then
        return
    end

    press.is_drag = true
    mp.set_property_bool("window-dragging", true)
    mp.commandv("begin-vo-dragging")
end

local clicks = click_area.create("video-taps", {
    priority = click_area.PRIORITY_VIDEO,
    on_click = on_press,
    on_release = on_release,
    -- mpv's own double-click action (fullscreen) is replaced by the
    -- double tap above, so it's ignored here.
    on_double_click = function() end,
})

local function on_pointer_moved()
    start_drag_if_moved()

    -- While a press is under way, keep taking it, so its release comes
    -- back here.
    if press == nil then
        clicks:update(touch.is_on() and is_pointer_over_video() and not is_any_popup_open())
    end
end

function video_taps.start()
    single_tap_timer = mp.add_timeout(DOUBLE_TAP_SECONDS, on_single_tap)
    single_tap_timer:kill()

    pointer.on_move(on_pointer_moved)
end

return video_taps
