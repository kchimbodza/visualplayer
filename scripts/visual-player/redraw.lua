-- Limits how often the interface redraws.
--
-- While a window is being resized, mpv reports a new size dozens of times
-- a second. Redrawing the whole interface for every one of those keeps
-- mpv's main thread so busy that video frames arrive late and get
-- dropped (found in Phase 2, step 1). So instead of redrawing right away,
-- parts of the interface ask for a redraw, and requests that arrive close
-- together are combined into one.

local redraw = {}

-- Normally at most 30 redraws a second: fast enough to keep up with a
-- resize, slow enough to leave time for the video.
local NORMAL_TIME_BETWEEN_REDRAWS = 1 / 30

-- While something is being dragged, like the seek bar's handle, allow up
-- to 60 a second so it moves smoothly under the pointer. Only the parts
-- that actually change are redrawn while dragging, so this stays cheap.
local DRAGGING_TIME_BETWEEN_REDRAWS = 1 / 60

local draw_functions = {}
local is_redraw_waiting = false
local last_redraw_time = 0
local is_dragging = false

-- Registers a function that draws one part of the interface. All
-- registered functions run together on every redraw.
function redraw.register(draw_function)
    table.insert(draw_functions, draw_function)
end

-- Switches to faster redraws while something is being dragged, and back
-- again afterwards.
function redraw.set_dragging(dragging)
    is_dragging = dragging
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

    local shortest_gap = NORMAL_TIME_BETWEEN_REDRAWS
    if is_dragging then
        shortest_gap = DRAGGING_TIME_BETWEEN_REDRAWS
    end

    local time_since_last_redraw = mp.get_time() - last_redraw_time
    local wait = math.max(0, shortest_gap - time_since_last_redraw)
    mp.add_timeout(wait, redraw_now)
end

return redraw
