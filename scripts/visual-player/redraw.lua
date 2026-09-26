-- Limits how often the interface redraws.
--
-- While a window is being resized, mpv reports a new size dozens of times
-- a second. Redrawing the whole interface for every one of those keeps
-- mpv's main thread so busy that video frames arrive late and get
-- dropped (found in Phase 2, step 1). So instead of redrawing right away,
-- parts of the interface ask for a redraw, and requests that arrive close
-- together are combined into one.

local redraw = {}

-- At most 30 redraws a second. Fast enough that the interface keeps up
-- smoothly with a resize, slow enough to leave time for the video.
local SHORTEST_TIME_BETWEEN_REDRAWS = 1 / 30

local draw_functions = {}
local is_redraw_waiting = false
local last_redraw_time = 0

-- Registers a function that draws one part of the interface. All
-- registered functions run together on every redraw.
function redraw.register(draw_function)
    table.insert(draw_functions, draw_function)
end

local function redraw_now()
    is_redraw_waiting = false
    last_redraw_time = mp.get_time()

    for _, draw_function in ipairs(draw_functions) do
        draw_function()
    end
end

-- Asks for the interface to be redrawn soon. Safe to call as often as you
-- like: extra requests before the redraw happens are simply ignored.
function redraw.request()
    if is_redraw_waiting then
        return
    end
    is_redraw_waiting = true

    local time_since_last_redraw = mp.get_time() - last_redraw_time
    local wait = math.max(0, SHORTEST_TIME_BETWEEN_REDRAWS - time_since_last_redraw)
    mp.add_timeout(wait, redraw_now)
end

return redraw
