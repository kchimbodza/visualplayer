-- Decides when the interface is showing, and fades it in and out.
--
-- The controls appear when the mouse moves over the window, and fade out
-- after a couple of seconds without movement, so they're there when
-- needed and out of the way while watching. They stay while paused,
-- while the pointer is over them, and while something is being dragged.
-- See docs/plan.md, 5.1.
--
-- Parts of the interface ask this module how visible to be, rather than
-- each deciding for themselves, so they always appear and hide together.

local pointer = require("pointer")
local redraw = require("redraw")

local visibility = {}

-- How long the controls stay after the mouse stops moving.
local HIDE_AFTER_SECONDS = 2

-- How long fading in or out takes, and how many steps it's drawn in.
local FADE_SECONDS = 0.2
local FADE_STEPS_PER_SECOND = 30

-- Whether the controls should be showing, and how far through fading
-- they are: 0 is fully hidden, 1 fully shown.
local should_show = false
local fade = 0

-- Functions that return true while the controls must stay visible, for
-- example while the pointer is over them. Parts of the interface add
-- these with visibility.keep_shown_while().
local keep_shown_checks = {}

local hide_timer = nil
local fade_timer = nil

-- How visible the interface should be drawn right now, from 0 to 1.
function visibility.opacity()
    return fade
end

-- True while the interface is on screen at all, including mid-fade.
function visibility.is_shown()
    return fade > 0
end

-- Adds a check that keeps the controls visible while it returns true.
function visibility.keep_shown_while(check)
    table.insert(keep_shown_checks, check)
end

local function is_something_keeping_it_shown()
    for _, check in ipairs(keep_shown_checks) do
        if check() then
            return true
        end
    end
    return false
end

-- Moves the fade one step towards its target, and stops once there.
local function step_fade()
    local target = 0
    if should_show then
        target = 1
    end

    local step = 1 / (FADE_SECONDS * FADE_STEPS_PER_SECOND)
    if fade < target then
        fade = math.min(target, fade + step)
    else
        fade = math.max(target, fade - step)
    end

    redraw.request()

    if fade == target then
        fade_timer:kill()
    end
end

local function start_fading()
    fade_timer:kill()
    fade_timer:resume()
end

local function show()
    if not should_show then
        should_show = true
        start_fading()
    end

    -- Restart the countdown to hiding.
    hide_timer:kill()
    hide_timer:resume()
end

local function hide()
    if should_show then
        should_show = false
        start_fading()
    end
end

-- When the countdown runs out, hide, unless something needs the
-- controls to stay, in which case check again after another wait.
local function on_hide_countdown_finished()
    if mp.get_property_bool("pause", false) or is_something_keeping_it_shown() then
        hide_timer:resume()
        return
    end

    hide()
end

local function on_pointer_moved()
    if pointer.is_over_window then
        show()
        return
    end

    -- Leaving the window hides the controls straight away, unless
    -- something is being dragged, since the pointer often strays
    -- outside while dragging.
    if not is_something_keeping_it_shown() then
        hide_timer:kill()
        hide()
    end
end

-- Pausing shows the controls, so it's easy to see where playback is.
-- Resuming starts the countdown to hiding them again.
local function on_pause_changed(_, is_paused)
    if is_paused then
        show()
    elseif should_show then
        hide_timer:kill()
        hide_timer:resume()
    end
end

function visibility.start()
    hide_timer = mp.add_timeout(HIDE_AFTER_SECONDS, on_hide_countdown_finished)
    hide_timer:kill()

    fade_timer = mp.add_periodic_timer(1 / FADE_STEPS_PER_SECOND, step_fade)
    fade_timer:kill()

    pointer.on_move(on_pointer_moved)
    mp.observe_property("pause", "bool", on_pause_changed)
end

return visibility
