-- The idle screen: shown when Visual Player is open with nothing playing,
-- as when it's opened from the app launcher. Visual Player's name in the
-- middle, and a hint underneath, since mpv plays files dragged onto its
-- window. It disappears as soon as something plays.

local draw = require("draw")
local redraw = require("redraw")
local screen = require("screen")
local style = require("style")

local idle_screen = {}

-- Sizes in design pixels. See screen.lua.
local ICON_SIZE = 56
local TITLE_SIZE = 28
local HINT_SIZE = 16
local GAP = 14

local canvas = draw.create_canvas({ layer = 0 })
local is_idle = false

function idle_screen.is_showing()
    return is_idle
end

local function render()
    if not is_idle or not screen.is_ready() then
        canvas:clear()
        return
    end

    draw.set_overall_opacity(1)

    local middle_x = screen.width / 2
    local middle_y = screen.height / 2

    canvas:add(draw.icon({
        name = "player-play",
        x = middle_x,
        y = middle_y - screen.pixels(TITLE_SIZE + GAP + ICON_SIZE / 2),
        size = screen.pixels(ICON_SIZE),
        color = style.TEXT_COLOR,
    }))
    canvas:add(draw.text({
        x = middle_x,
        y = middle_y,
        align = "center",
        vertical = "bottom",
        text = "Visual Player",
        size = screen.pixels(TITLE_SIZE),
        bold = true,
        color = style.TEXT_COLOR,
    }))
    canvas:add(draw.text({
        x = middle_x,
        y = middle_y + screen.pixels(GAP),
        align = "center",
        text = "Drop a video here to play it",
        size = screen.pixels(HINT_SIZE),
        color = style.MUTED_TEXT_COLOR,
    }))

    canvas:show(screen.width, screen.height)
end

function idle_screen.start()
    redraw.register(render)
    screen.on_change(redraw.request)
    mp.observe_property("idle-active", "bool", function(_, idle)
        is_idle = idle == true
        redraw.request()
    end)
end

return idle_screen
