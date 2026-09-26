-- Keeps track of the size of the video window and the screen's scaling.
--
-- Everything on screen is sized in "design pixels": the size it would be
-- on an ordinary 1080p screen at 100% scaling. screen.pixels() turns
-- those into real pixels for the current window, so the interface looks
-- the same size on a high-resolution laptop screen as on a regular one.

local screen = {
    width = 0,
    height = 0,
    scale = 1,
}

local change_listeners = {}

-- Converts a size in design pixels into real pixels on this screen.
function screen.pixels(design_pixels)
    return design_pixels * screen.scale
end

-- True once mpv has told us the window size, so there's room to draw.
function screen.is_ready()
    return screen.width > 0 and screen.height > 0
end

-- Registers a function to call whenever the window size or scaling changes.
function screen.on_change(listener)
    table.insert(change_listeners, listener)
end

local function tell_listeners()
    for _, listener in ipairs(change_listeners) do
        listener()
    end
end

local function on_window_size_changed(_, dimensions)
    if dimensions == nil then
        return
    end

    screen.width = dimensions.w
    screen.height = dimensions.h
    tell_listeners()
end

local function on_scaling_changed(_, scale)
    screen.scale = scale or 1
    tell_listeners()
end

function screen.start()
    mp.observe_property("osd-dimensions", "native", on_window_size_changed)
    mp.observe_property("display-hidpi-scale", "native", on_scaling_changed)
end

return screen
