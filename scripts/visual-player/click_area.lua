-- Lets a part of the interface take over mouse clicks while the pointer
-- is over it, and hands them back when the pointer leaves.
--
-- Taking clicks only while the pointer is over a part means clicks
-- everywhere else keep working as usual, such as double-clicking the
-- video to go fullscreen.
--
-- Usage:
--   local clicks = click_area.create("top-bar", {
--       on_click = function() ... end,
--       on_release = function() ... end,        -- optional
--       on_double_click = function() ... end,   -- optional
--   })
--   clicks:update(pointer.is_inside(some_area))   -- after every move

local click_area = {}

function click_area.create(name, handlers)
    local area = { is_taking_clicks = false }

    local function on_left_button(event)
        -- Act as soon as the button goes down, so dragging a window can
        -- start straight away.
        if event.event == "down" then
            handlers.on_click()
        elseif event.event == "up" and handlers.on_release then
            handlers.on_release()
        end
    end

    -- Without its own double-click handler, a part still takes double
    -- clicks and ignores them. Otherwise clicking a button twice quickly
    -- would also trigger mpv's double-click action and go fullscreen.
    local on_double_click = handlers.on_double_click or function() end

    local function start_taking_clicks()
        mp.add_forced_key_binding("MBTN_LEFT", name .. "-click", on_left_button, { complex = true })
        mp.add_forced_key_binding("MBTN_LEFT_DBL", name .. "-double-click", on_double_click)
        area.is_taking_clicks = true
    end

    local function stop_taking_clicks()
        mp.remove_key_binding(name .. "-click")
        mp.remove_key_binding(name .. "-double-click")
        area.is_taking_clicks = false
    end

    -- Call after every pointer move, saying whether the pointer is now
    -- over this part of the interface.
    function area:update(is_pointer_inside)
        if is_pointer_inside and not self.is_taking_clicks then
            start_taking_clicks()
        elseif not is_pointer_inside and self.is_taking_clicks then
            stop_taking_clicks()
        end
    end

    return area
end

return click_area
