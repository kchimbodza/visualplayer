-- Keeps track of where the mouse pointer is over the video window.
--
-- Parts of the interface ask this module whether the pointer is inside
-- them, and can be told whenever the pointer moves.

local pointer = {
    x = -1,
    y = -1,
    is_over_window = false,
}

local move_listeners = {}

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

local function on_mouse_position_changed(_, position)
    if position == nil then
        return
    end

    pointer.x = position.x
    pointer.y = position.y
    pointer.is_over_window = position.hover

    for _, listener in ipairs(move_listeners) do
        listener()
    end
end

function pointer.start()
    mp.observe_property("mouse-pos", "native", on_mouse_position_changed)
end

return pointer
