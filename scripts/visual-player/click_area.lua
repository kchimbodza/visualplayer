-- Routes mouse clicks and finger taps to the part of the interface under
-- the pointer.
--
-- Each part creates a click area and says, after every pointer move,
-- whether the pointer is over it (area:update()). One listener for the
-- left button is always active. When a press arrives, it first reads
-- where the pointer is right now and lets every part update, then gives
-- the press to the part under it with the highest priority.
--
-- A press where no part of the interface is, on the picture itself,
-- starts moving the window.
--
-- Reading the pointer at the moment of the press matters for touch. An
-- earlier version only started listening once the pointer had moved over
-- a part. A mouse always moves before clicking, but a finger lands and
-- presses at once, so the press arrived before anything was listening
-- and was lost (Phase 5, step 4, on the ASUS ProArt PX13).
--
-- Usage:
--   local clicks = click_area.create("top-bar", {
--       priority = click_area.PRIORITY_CONTROLS,
--       on_click = function() ... end,
--       on_release = function() ... end,        -- optional
--       on_double_click = function() ... end,   -- optional
--   })
--   clicks:update(pointer.is_inside(some_area))   -- after every move

local pointer = require("pointer")

local click_area = {}

-- When parts overlap, the higher priority gets the click. Open popups
-- and menus take every click, so a click outside them can close them.
click_area.PRIORITY_POPUP = 30
click_area.PRIORITY_PICTURE_IN_PICTURE = 20
click_area.PRIORITY_CONTROLS = 10
click_area.PRIORITY_VIDEO = 0

local areas = {}

-- The area that received the last press, so its release goes there too,
-- even if the pointer has moved off it by then.
local pressed_area = nil

-- True while a press on the picture is moving the window.
local is_dragging_window = false

function click_area.create(name, handlers)
    local area = {
        name = name,
        handlers = handlers,
        priority = handlers.priority or click_area.PRIORITY_CONTROLS,
        is_taking_clicks = false,
    }

    -- Call after every pointer move, saying whether the pointer is now
    -- over this part of the interface.
    function area:update(is_pointer_inside)
        self.is_taking_clicks = is_pointer_inside
    end

    table.insert(areas, area)
    return area
end

-- The area under the pointer with the highest priority, or nil.
local function find_area_under_pointer()
    local chosen = nil
    for _, area in ipairs(areas) do
        if area.is_taking_clicks and (chosen == nil or area.priority > chosen.priority) then
            chosen = area
        end
    end
    return chosen
end

local function on_left_button(event)
    if event.event == "down" then
        -- A drag hands the pointer to the desktop, so its release may never
        -- arrive; tidy up after one here instead.
        if is_dragging_window then
            is_dragging_window = false
            mp.set_property_bool("window-dragging", false)
        end
        pointer.set_pressed(true)
        pressed_area = find_area_under_pointer()
        if pressed_area then
            pressed_area.handlers.on_click()
        elseif pointer.is_over_window then
            -- A press on the picture itself, away from every control,
            -- moves the window, as in most players. (It used to be only
            -- the top bar.) With touch controls on, taps on the picture
            -- belong to video_taps.lua instead, which claims them first.
            --
            -- Moving the window needs mpv's window-dragging on, which is
            -- normally off so it can't fight the seek bar (see
            -- top_bar.lua), so it's switched on for this press only.
            is_dragging_window = true
            mp.set_property_bool("window-dragging", true)
            mp.commandv("begin-vo-dragging")
        end
    elseif event.event == "up" then
        if pressed_area and pressed_area.handlers.on_release then
            pressed_area.handlers.on_release()
        end
        pressed_area = nil
        if is_dragging_window then
            is_dragging_window = false
            mp.set_property_bool("window-dragging", false)
        end
        pointer.set_pressed(false)
    end
end

-- A double-click goes to the area under the pointer. If that area has no
-- double-click action, it's ignored, so clicking a button twice quickly
-- doesn't also switch to fullscreen. Over the picture itself, with no
-- area there, it keeps mpv's usual action: fullscreen.
local function on_double_click()
    pointer.refresh_now()
    local area = find_area_under_pointer()

    if area == nil then
        mp.command("cycle fullscreen")
    elseif area.handlers.on_double_click then
        area.handlers.on_double_click()
    end
end

function click_area.start()
    mp.add_forced_key_binding("MBTN_LEFT", "clicks", on_left_button, { complex = true })
    mp.add_forced_key_binding("MBTN_LEFT_DBL", "double-clicks", on_double_click)
end

return click_area
