-- Taps on the video itself, when touch controls are on. See docs/plan.md,
-- section 5.9.
--
--   One tap                 shows or hides the controls
--   Two taps, left third    skips back 10 seconds
--   Two taps, right third   skips forward 10 seconds
--   Two taps, middle        switches fullscreen on or off
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

local single_tap_timer = nil

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

local clicks = click_area.create("video-taps", {
    priority = click_area.PRIORITY_VIDEO,
    on_click = on_tap,
    -- mpv's own double-click action (fullscreen) is replaced by the
    -- double tap above, so it's ignored here.
    on_double_click = function() end,
})

local function on_pointer_moved()
    clicks:update(touch.is_on() and is_pointer_over_video() and not is_any_popup_open())
end

function video_taps.start()
    single_tap_timer = mp.add_timeout(DOUBLE_TAP_SECONDS, on_single_tap)
    single_tap_timer:kill()

    pointer.on_move(on_pointer_moved)
end

return video_taps
