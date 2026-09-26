-- Keeps track of the size of the video window and how big to draw things.
--
-- Everything on screen is sized in "design pixels": the size it would be
-- in a window 1080 pixels tall. The interface grows and shrinks with the
-- window, like mpv's own controls, so it looks the same relative to the
-- picture whether the window is small, fullscreen at 1080p, or
-- fullscreen at 4K. screen.pixels() converts design sizes to real pixels.

local screen = {
    width = 0,
    height = 0,
    scale = 1,

    -- The desktop's scaling for this screen, such as 2 on a screen set to
    -- 200%. Used for sizes that should look the same on every screen,
    -- like the smallest allowed window.
    hidpi_scale = 1,
}

-- The window height the interface is designed for.
local DESIGN_HEIGHT = 1080

-- Small windows shrink the interface, but never below this fraction of
-- its design size (adjusted for the screen's HiDPI setting), so text
-- stays readable.
local SMALLEST_SCALE = 0.6

local change_listeners = {}

-- Converts a size in design pixels into real pixels in this window.
function screen.pixels(design_pixels)
    return design_pixels * screen.scale
end

-- True once mpv has told us the window size, so there's room to draw.
function screen.is_ready()
    return screen.width > 0 and screen.height > 0
end

-- Registers a function to call whenever the window size or scale changes.
function screen.on_change(listener)
    table.insert(change_listeners, listener)
end

local function update_scale()
    local scale_for_window = screen.height / DESIGN_HEIGHT
    local smallest_allowed = SMALLEST_SCALE * screen.hidpi_scale
    screen.scale = math.max(scale_for_window, smallest_allowed)
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
    update_scale()
    tell_listeners()
end

local function on_hidpi_scale_changed(_, scale)
    screen.hidpi_scale = scale or 1
    update_scale()
    tell_listeners()
end

function screen.start()
    mp.observe_property("osd-dimensions", "native", on_window_size_changed)
    mp.observe_property("display-hidpi-scale", "native", on_hidpi_scale_changed)
end

return screen
