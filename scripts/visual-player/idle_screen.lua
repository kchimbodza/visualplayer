-- The idle screen: shown when Visual Player is open with nothing playing,
-- as when it's opened from the app launcher. Visual Player's name in the
-- middle, a hint underneath, since mpv plays files dragged onto its
-- window, and the formats it handles, as outlined badges like the ones
-- shown when a file starts. It disappears as soon as something plays.
--
-- Only formats Visual Player both plays and labels are listed, picture on
-- one row and sound on the next. HDR10+ files play, but mpv doesn't
-- report HDR10+, so they're labeled HDR10, and listing a badge that never
-- appears would mislead. Dolby Surround isn't listed either: it's an
-- upmixing mode on the receiver or soundbar, not a format in the file.

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

local HINT = "Your videos, in the picture and sound they were made with"

-- A quieter hint at the bottom of the window, since dropping a video onto
-- the window isn't obvious the first time.
local DROP_HINT = "Drop a video here to start watching"
local DROP_HINT_SIZE = 14
local DROP_HINT_BOTTOM_MARGIN = 32
local FORMAT_GROUPS = {
    { "4K", "HDR10", "Dolby Vision", "HLG", "AV1", "HEVC" },
    {
        "Dolby Atmos", "Dolby TrueHD", "Dolby Digital Plus", "Dolby Digital",
        "DTS-HD", "DTS", "7.1 Surround",
    },
}

-- The format badges, matching badges.lua.
local BADGE_TEXT_SIZE = 15
local BADGE_PADDING_ACROSS = 10
local BADGE_PADDING_DOWN = 5
local BADGE_GAP = 8
local BADGE_CORNER_RADIUS = 5
local GAP_ABOVE_BADGES = 28

-- Badges wrap onto another row rather than growing wider than this share
-- of the window.
local WIDEST_SHARE_OF_WINDOW = 0.8

local canvas = draw.create_canvas({ layer = 0 })
local is_idle = false

function idle_screen.is_showing()
    return is_idle
end

-- Splits the badges into centered rows that fit the window, starting a
-- new row for each group.
local function arrange_badges(text_size)
    local padding = screen.pixels(BADGE_PADDING_ACROSS)
    local gap = screen.pixels(BADGE_GAP)
    local widest = screen.width * WIDEST_SHARE_OF_WINDOW

    local rows = {}
    for _, group in ipairs(FORMAT_GROUPS) do
        table.insert(rows, { badges = {}, width = 0 })
        for _, label in ipairs(group) do
            local width = draw.estimate_text_width(label, text_size) + padding * 2
            local row = rows[#rows]
            local new_width = row.width + width
            if #row.badges > 0 then
                new_width = new_width + gap
            end

            if new_width > widest and #row.badges > 0 then
                row = { badges = {}, width = width }
                table.insert(rows, row)
            else
                row.width = new_width
            end
            table.insert(row.badges, { label = label, width = width })
        end
    end
    return rows
end

local function add_badges(top)
    local text_size = screen.pixels(BADGE_TEXT_SIZE)
    local height = text_size + screen.pixels(BADGE_PADDING_DOWN) * 2
    local gap = screen.pixels(BADGE_GAP)

    for row_index, row in ipairs(arrange_badges(text_size)) do
        local row_top = top + (row_index - 1) * (height + gap)
        local left = (screen.width - row.width) / 2

        for _, badge in ipairs(row.badges) do
            canvas:add(draw.rectangle({
                area = {
                    left = left,
                    top = row_top,
                    right = left + badge.width,
                    bottom = row_top + height,
                },
                color = style.BACKGROUND_COLOR,
                opacity = 0,
                corner_radius = screen.pixels(BADGE_CORNER_RADIUS),
                outline = {
                    width = math.max(1, screen.pixels(1)),
                    color = style.TEXT_COLOR,
                    opacity = 0.45,
                },
            }))
            canvas:add(draw.text({
                x = left + badge.width / 2,
                y = row_top + height / 2,
                align = "center",
                vertical = "middle",
                text = badge.label,
                size = text_size,
                color = style.MUTED_TEXT_COLOR,
            }))
            left = left + badge.width + gap
        end
    end
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
        text = HINT,
        size = screen.pixels(HINT_SIZE),
        color = style.MUTED_TEXT_COLOR,
    }))

    add_badges(middle_y + screen.pixels(GAP + HINT_SIZE + GAP_ABOVE_BADGES))

    canvas:add(draw.text({
        x = middle_x,
        y = screen.height - screen.pixels(DROP_HINT_BOTTOM_MARGIN),
        align = "center",
        vertical = "bottom",
        text = DROP_HINT,
        size = screen.pixels(DROP_HINT_SIZE),
        color = style.MUTED_TEXT_COLOR,
        opacity = 0.8,
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
