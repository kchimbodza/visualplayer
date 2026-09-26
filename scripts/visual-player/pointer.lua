-- Keeps track of where the mouse pointer, or a finger, is over the video
-- window.
--
-- Parts of the interface ask this module whether the pointer is inside
-- them, and can be told whenever the pointer moves.
--
-- mpv's "hover" flag says whether a mouse pointer is over the window,
-- but a finger never enters the window the way a mouse does, so during
-- touches the flag stays off even though the position is right (Phase 5,
-- step 4, on the ASUS ProArt PX13). So while a press is happening, any
-- position inside the window counts as over the window.

local screen = require("screen")

local pointer = {
    x = -1,
    y = -1,
    is_over_window = false,
}

local move_listeners = {}

-- Whether a mouse button or finger is pressed down right now. Set by
-- click_area.lua.
local is_pressed = false

-- Registers a function to call whenever the pointer moves, or enters or
-- leaves the window.
function pointer.on_move(listener)
    table.insert(move_listeners, listener)
end

-- True if the pointer is over the window and inside the given area.
function pointer.is_inside(area)
    return pointer.is_over_window
        and pointer.x >= area.left
        and pointer.x <= area.right
        and pointer.y >= area.top
        and pointer.y <= area.bottom
end

local function is_within_window(x, y)
    return x >= 0 and y >= 0 and x <= screen.width and y <= screen.height
end

local function on_mouse_position_changed(_, position)
    if position == nil then
        return
    end

    pointer.x = position.x
    pointer.y = position.y
    pointer.is_over_window = position.hover
        or (is_pressed and is_within_window(position.x, position.y))

    for _, listener in ipairs(move_listeners) do
        listener()
    end
end

-- Reads where the pointer is right now and tells every listener, without
-- waiting for mpv's usual notice. Used when a click or tap arrives, since
-- a finger lands and presses at once, and the notice can come too late.
function pointer.refresh_now()
    on_mouse_position_changed(nil, mp.get_property_native("mouse-pos"))
end

-- Records whether a press is happening, then rechecks the position, so a
-- press inside the window always counts as over it.
function pointer.set_pressed(pressed)
    is_pressed = pressed
    pointer.refresh_now()
end

function pointer.start()
    mp.observe_property("mouse-pos", "native", on_mouse_position_changed)
end

return pointer
