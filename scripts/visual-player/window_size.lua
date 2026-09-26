-- Keeps the window from being resized smaller than 240p.
--
-- Below about 240 pixels tall, the picture is too small to watch and the
-- controls crowd it. mpv has no setting for a smallest window size
-- (checked in Phase 2), so this undoes a too-small resize instead: if
-- the window stays below the minimum for a moment, it's resized back up,
-- keeping the video's shape.
--
-- It waits before fixing the size because the window is usually still
-- being dragged while it's too small, and snapping back mid-drag would
-- fight the person dragging it.

local screen = require("screen")

local window_size = {}

-- The smallest window, in the screen's own scaling, so it looks the same
-- size on a 200% laptop screen as on a 100% monitor. 426 by 240 is 240p
-- at the usual 16:9 shape.
local SMALLEST_WIDTH = 426
local SMALLEST_HEIGHT = 240

local SECONDS_TO_WAIT_BEFORE_FIXING = 0.5

local fix_timer = nil

-- Fullscreen and maximized windows are sized by the desktop, not the
-- person, so they're left alone.
local function is_size_controlled_by_desktop()
    return mp.get_property_bool("fullscreen", false)
        or mp.get_property_bool("window-maximized", false)
end

local function is_too_small()
    return screen.width < SMALLEST_WIDTH * screen.hidpi_scale
        or screen.height < SMALLEST_HEIGHT * screen.hidpi_scale
end

local function fix_size()
    fix_timer = nil

    if is_size_controlled_by_desktop() or not is_too_small() then
        return
    end

    -- Audio files have no picture to size the window around.
    local video = mp.get_property_native("video-params")
    if video == nil or not video.dw or video.dw == 0 or video.dh == 0 then
        return
    end

    -- window-scale sizes the window relative to the video, keeping its
    -- shape. Pick the scale that makes the window just big enough in both
    -- directions. mpv applies the screen's scaling on top of this itself.
    local scale = math.max(SMALLEST_HEIGHT / video.dh, SMALLEST_WIDTH / video.dw)
    mp.set_property_number("window-scale", scale)

    mp.msg.info("Window was smaller than 240p, so it was resized back up")
end

local function on_window_size_changed()
    if not screen.is_ready() then
        return
    end

    -- Every size change restarts the wait, so the fix only happens once
    -- the window has stayed too small for the whole wait.
    if fix_timer then
        fix_timer:kill()
        fix_timer = nil
    end

    if is_too_small() and not is_size_controlled_by_desktop() then
        fix_timer = mp.add_timeout(SECONDS_TO_WAIT_BEFORE_FIXING, fix_size)
    end
end

function window_size.start()
    screen.on_change(on_window_size_changed)
end

return window_size
