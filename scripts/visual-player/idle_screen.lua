-- The idle screen: shown when Visual Player is open with nothing playing,
-- as when it's opened from the app launcher. It disappears as soon as
-- something plays.
--
--                          ▷
--                    Visual Player
--     Your videos, in the picture and sound they were made with
--        ╭╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╮
--        ╎                  ☁                      ╎
--        ╎    Drop a video here to start watching   ╎
--        ╎             or click to browse          ╎
--        ╰╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╯
--   ─────────────────── Supported formats ───────────────────
--   🎞 Video                          │  🔊 Audio
--   8K  4K  HDR10  Dolby Vision  HLG  │  Dolby Atmos  Dolby TrueHD …
--
-- Clicking the drop area opens a file chooser, using zenity (GNOME) or
-- kdialog (KDE), whichever is installed. mpv has no file chooser of its
-- own. Without either, the second line suggests Open With in Files
-- instead, so it never promises something that won't work.
--
-- "Video" and "Audio" are the words people see on disc boxes and in
-- other players, and match the info panel's rows. Only formats Visual
-- Player both plays and labels are listed: not HDR10+, which mpv doesn't
-- report (it's labeled HDR10), or Dolby Surround, which is a soundbar's
-- upmixing mode rather than a format in the file.

local click_area = require("click_area")
local draw = require("draw")
local pointer = require("pointer")
local redraw = require("redraw")
local screen = require("screen")
local style = require("style")

local idle_screen = {}

-- Sizes in design pixels. See screen.lua.
local PLAY_ICON_SIZE = 64
local TITLE_SIZE = 40
local TAGLINE_SIZE = 18
local GAP_BELOW_ICON = 18
local GAP_BELOW_TITLE = 8

local DROP_BOX_SHARE_OF_WINDOW = 0.46
local DROP_BOX_HEIGHT = 124
local DROP_BOX_CORNER_RADIUS = 12
local GAP_ABOVE_DROP_BOX = 28
local DROP_ICON_SIZE = 34
local DROP_TEXT_SIZE = 17
local DROP_SUBTEXT_SIZE = 14

local DASH_LENGTH = 7
local DASH_GAP = 5
local DASH_THICKNESS = 1
local DASH_OPACITY = 0.35
local DASH_OPACITY_HOVERED = 0.6
local FILL_OPACITY = 0.04
local FILL_OPACITY_HOVERED = 0.07

local FORMATS_SHARE_OF_WINDOW = 0.74
local GAP_ABOVE_FORMATS = 40
local FORMATS_HEADING_SIZE = 16
local GAP_BESIDE_FORMATS_HEADING = 24
local GAP_ABOVE_GROUPS = 32
local GROUP_HEADING_SIZE = 18
local GROUP_ICON_SIZE = 22
local GAP_ABOVE_BADGES = 14
local GAP_BETWEEN_COLUMNS = 64
local LINE_OPACITY = 0.18

-- The format badges.
local BADGE_TEXT_SIZE = 15
local BADGE_PADDING_ACROSS = 14
local BADGE_PADDING_DOWN = 8
local BADGE_GAP = 10
local BADGE_CORNER_RADIUS = 8
local BADGE_OUTLINE_OPACITY = 0.35

local TAGLINE = "Your videos, in the picture and sound they were made with"
local DROP_TEXT = "Drop a video here to start watching"
local BROWSE_TEXT = "or click to browse"
local NO_BROWSER_TEXT = "or open one with Open With in Files"

local GROUPS = {
    {
        heading = "Video",
        icon = "movie",
        formats = { "8K", "4K", "HDR10", "Dolby Vision", "HLG", "AV1", "HEVC" },
    },
    {
        heading = "Audio",
        icon = "volume",
        formats = {
            "Dolby Atmos", "Dolby TrueHD", "Dolby Digital Plus", "Dolby Digital",
            "DTS-HD", "DTS", "7.1 Surround",
        },
    },
}

local VIDEO_EXTENSIONS = {
    "mkv", "mp4", "m4v", "webm", "mov", "avi", "ts", "m2ts", "mpg", "mpeg", "wmv", "flv",
}

local canvas = draw.create_canvas({ layer = 0 })
local is_idle = false
local is_box_hovered = false

-- Where the drop area was last drawn, for knowing when it's clicked.
local drop_box = nil

-- The file chooser to use, "zenity" or "kdialog", or nil if neither is
-- installed. Found once at startup.
local file_chooser = nil

function idle_screen.is_showing()
    return is_idle
end

-- Lines --------------------------------------------------------------------

local function add_line(area, opacity)
    canvas:add(draw.rectangle({ area = area, color = style.TEXT_COLOR, opacity = opacity }))
end

-- A dashed line from one point towards another, straight across or down,
-- as a row of short filled segments starting exactly at the first point.
local function add_dashed_line(from_x, from_y, to_x, to_y, opacity)
    local dash = screen.pixels(DASH_LENGTH)
    local step = dash + screen.pixels(DASH_GAP)
    local half = math.max(1, screen.pixels(DASH_THICKNESS)) / 2
    local length = math.abs(to_x - from_x) + math.abs(to_y - from_y)
    if length <= 0 then
        return
    end
    local dx = (to_x - from_x) / length
    local dy = (to_y - from_y) / length

    local position = 0
    while position < length do
        local dash_end = math.min(position + dash, length)
        local x1, y1 = from_x + dx * position, from_y + dy * position
        local x2, y2 = from_x + dx * dash_end, from_y + dy * dash_end
        add_line({
            left = math.min(x1, x2) - half,
            top = math.min(y1, y2) - half,
            right = math.max(x1, x2) + half,
            bottom = math.max(y1, y2) + half,
        }, opacity)
        position = position + step
    end
end

-- A quarter circle traced with tiny dots, for the drop area's rounded
-- corners, since mpv can't draw a dashed or open curve. start_angle is in
-- degrees, going clockwise from pointing right.
local function add_dotted_corner(center_x, center_y, radius, start_angle, opacity)
    local thickness = math.max(1, screen.pixels(DASH_THICKNESS))
    local steps = math.max(6, math.floor(radius * math.pi / 2 / thickness))
    for index = 0, steps do
        local angle = math.rad(start_angle + 90 * index / steps)
        local x = center_x + math.cos(angle) * radius
        local y = center_y + math.sin(angle) * radius
        add_line({
            left = x - thickness / 2,
            top = y - thickness / 2,
            right = x + thickness / 2,
            bottom = y + thickness / 2,
        }, opacity)
    end
end

-- The drop area's border: dashed straight edges, dashed from each end
-- towards the middle so both ends match, and dotted rounded corners.
local function add_dashed_rounded_box(box, radius, opacity)
    local middle_x = (box.left + box.right) / 2
    local middle_y = (box.top + box.bottom) / 2

    for _, y in ipairs({ box.top, box.bottom }) do
        add_dashed_line(box.left + radius, y, middle_x, y, opacity)
        add_dashed_line(box.right - radius, y, middle_x, y, opacity)
    end
    for _, x in ipairs({ box.left, box.right }) do
        add_dashed_line(x, box.top + radius, x, middle_y, opacity)
        add_dashed_line(x, box.bottom - radius, x, middle_y, opacity)
    end

    add_dotted_corner(box.left + radius, box.top + radius, radius, 180, opacity)
    add_dotted_corner(box.right - radius, box.top + radius, radius, 270, opacity)
    add_dotted_corner(box.right - radius, box.bottom - radius, radius, 0, opacity)
    add_dotted_corner(box.left + radius, box.bottom - radius, radius, 90, opacity)
end

-- Badges -------------------------------------------------------------------

-- Splits a group's badges into left-aligned rows no wider than its column.
local function arrange_badges(formats, column_width, text_size)
    local padding = screen.pixels(BADGE_PADDING_ACROSS)
    local gap = screen.pixels(BADGE_GAP)

    local rows = { { badges = {}, width = 0 } }
    for _, label in ipairs(formats) do
        local width = draw.estimate_text_width(label, text_size) + padding * 2
        local row = rows[#rows]
        local new_width = row.width + width
        if #row.badges > 0 then
            new_width = new_width + gap
        end

        if new_width > column_width and #row.badges > 0 then
            row = { badges = {}, width = width }
            table.insert(rows, row)
        else
            row.width = new_width
        end
        table.insert(row.badges, { label = label, width = width })
    end
    return rows
end

-- Draws one group from its column's left edge: the icon and heading, then
-- the badges. Returns how tall it was.
local function add_group(group, left, top, column_width)
    local heading_size = screen.pixels(GROUP_HEADING_SIZE)
    local icon_size = screen.pixels(GROUP_ICON_SIZE)
    local heading_middle = top + icon_size / 2

    canvas:add(draw.icon({
        name = group.icon,
        x = left + icon_size / 2,
        y = heading_middle,
        size = icon_size,
        color = style.TEXT_COLOR,
    }))
    canvas:add(draw.text({
        x = left + icon_size + screen.pixels(12),
        y = heading_middle,
        vertical = "middle",
        text = group.heading,
        size = heading_size,
        bold = true,
        color = style.TEXT_COLOR,
    }))

    local text_size = screen.pixels(BADGE_TEXT_SIZE)
    local badge_height = text_size + screen.pixels(BADGE_PADDING_DOWN) * 2
    local gap = screen.pixels(BADGE_GAP)
    local badges_top = top + icon_size + screen.pixels(GAP_ABOVE_BADGES)

    local rows = arrange_badges(group.formats, column_width, text_size)
    for row_index, row in ipairs(rows) do
        local row_top = badges_top + (row_index - 1) * (badge_height + gap)
        local badge_left = left

        for _, badge in ipairs(row.badges) do
            canvas:add(draw.rectangle({
                area = {
                    left = badge_left,
                    top = row_top,
                    right = badge_left + badge.width,
                    bottom = row_top + badge_height,
                },
                color = style.BACKGROUND_COLOR,
                opacity = 0,
                corner_radius = screen.pixels(BADGE_CORNER_RADIUS),
                outline = {
                    width = math.max(1, screen.pixels(1)),
                    color = style.TEXT_COLOR,
                    opacity = BADGE_OUTLINE_OPACITY,
                },
            }))
            canvas:add(draw.text({
                x = badge_left + badge.width / 2,
                y = row_top + badge_height / 2,
                align = "center",
                vertical = "middle",
                text = badge.label,
                size = text_size,
                color = style.TEXT_COLOR,
            }))
            badge_left = badge_left + badge.width + gap
        end
    end

    return badges_top - top + #rows * badge_height + (#rows - 1) * gap
end

-- Drawing ------------------------------------------------------------------

local function add_heading_block(middle_x)
    local title_size = screen.pixels(TITLE_SIZE)
    local icon_size = screen.pixels(PLAY_ICON_SIZE)

    -- Everything is laid out from here down; this top sits the whole
    -- screen roughly in the middle of the window.
    local top = screen.height * 0.12

    canvas:add(draw.icon({
        name = "player-play",
        x = middle_x,
        y = top + icon_size / 2,
        size = icon_size,
        color = style.TEXT_COLOR,
    }))

    local title_top = top + icon_size + screen.pixels(GAP_BELOW_ICON)
    canvas:add(draw.text({
        x = middle_x,
        y = title_top,
        align = "center",
        text = "Visual Player",
        size = title_size,
        bold = true,
        color = style.TEXT_COLOR,
    }))

    local tagline_top = title_top + title_size + screen.pixels(GAP_BELOW_TITLE)
    canvas:add(draw.text({
        x = middle_x,
        y = tagline_top,
        align = "center",
        text = TAGLINE,
        size = screen.pixels(TAGLINE_SIZE),
        color = style.MUTED_TEXT_COLOR,
    }))

    return tagline_top + screen.pixels(TAGLINE_SIZE)
end

local function add_drop_box(middle_x, top)
    local text_size = screen.pixels(DROP_TEXT_SIZE)
    local minimum_width = draw.estimate_text_width(DROP_TEXT, text_size) + screen.pixels(80)
    local width = math.max(screen.width * DROP_BOX_SHARE_OF_WINDOW, minimum_width)
    local height = screen.pixels(DROP_BOX_HEIGHT)

    drop_box = {
        left = middle_x - width / 2,
        top = top,
        right = middle_x + width / 2,
        bottom = top + height,
    }

    local radius = screen.pixels(DROP_BOX_CORNER_RADIUS)
    local fill = FILL_OPACITY
    local dashes = DASH_OPACITY
    if is_box_hovered then
        fill = FILL_OPACITY_HOVERED
        dashes = DASH_OPACITY_HOVERED
    end

    canvas:add(draw.rectangle({
        area = drop_box,
        color = style.TEXT_COLOR,
        opacity = fill,
        corner_radius = radius,
    }))
    add_dashed_rounded_box(drop_box, radius, dashes)

    local icon_size = screen.pixels(DROP_ICON_SIZE)
    local subtext_size = screen.pixels(DROP_SUBTEXT_SIZE)
    local content_height = icon_size + screen.pixels(12)
        + text_size + screen.pixels(8)
        + subtext_size
    local content_top = top + (height - content_height) / 2

    canvas:add(draw.icon({
        name = "cloud-upload",
        x = middle_x,
        y = content_top + icon_size / 2,
        size = icon_size,
        color = style.MUTED_TEXT_COLOR,
    }))

    local text_top = content_top + icon_size + screen.pixels(12)
    canvas:add(draw.text({
        x = middle_x,
        y = text_top,
        align = "center",
        text = DROP_TEXT,
        size = text_size,
        color = style.TEXT_COLOR,
    }))

    local subtext = NO_BROWSER_TEXT
    if file_chooser then
        subtext = BROWSE_TEXT
    end
    canvas:add(draw.text({
        x = middle_x,
        y = text_top + text_size + screen.pixels(8),
        align = "center",
        text = subtext,
        size = subtext_size,
        color = style.MUTED_TEXT_COLOR,
    }))

    return drop_box.bottom
end

local function add_formats(middle_x, top)
    local total_width = screen.width * FORMATS_SHARE_OF_WINDOW
    local left = middle_x - total_width / 2
    local right = middle_x + total_width / 2
    local thickness = math.max(1, screen.pixels(1))

    -- "Supported formats", with a line on either side.
    local heading_size = screen.pixels(FORMATS_HEADING_SIZE)
    local heading = "Supported formats"
    local heading_half = draw.estimate_text_width(heading, heading_size) / 2
        + screen.pixels(GAP_BESIDE_FORMATS_HEADING)
    local heading_middle = top + heading_size / 2

    canvas:add(draw.text({
        x = middle_x,
        y = heading_middle,
        align = "center",
        vertical = "middle",
        text = heading,
        size = heading_size,
        color = style.MUTED_TEXT_COLOR,
    }))
    add_line({
        left = left,
        top = heading_middle - thickness / 2,
        right = middle_x - heading_half,
        bottom = heading_middle + thickness / 2,
    }, LINE_OPACITY)
    add_line({
        left = middle_x + heading_half,
        top = heading_middle - thickness / 2,
        right = right,
        bottom = heading_middle + thickness / 2,
    }, LINE_OPACITY)

    -- The two groups, left-aligned in their columns, with a line between.
    local groups_top = top + heading_size + screen.pixels(GAP_ABOVE_GROUPS)
    local gap = screen.pixels(GAP_BETWEEN_COLUMNS)
    local column_width = (total_width - gap) / 2

    local video_height = add_group(GROUPS[1], left, groups_top, column_width)
    local audio_height = add_group(GROUPS[2], middle_x + gap / 2, groups_top, column_width)

    add_line({
        left = middle_x - thickness / 2,
        top = groups_top,
        right = middle_x + thickness / 2,
        bottom = groups_top + math.max(video_height, audio_height),
    }, LINE_OPACITY)
end

local function render()
    if not is_idle or not screen.is_ready() then
        canvas:clear()
        drop_box = nil
        return
    end

    draw.set_overall_opacity(1)
    local middle_x = screen.width / 2

    local heading_bottom = add_heading_block(middle_x)
    local box_bottom = add_drop_box(middle_x, heading_bottom + screen.pixels(GAP_ABOVE_DROP_BOX))
    add_formats(middle_x, box_bottom + screen.pixels(GAP_ABOVE_FORMATS))

    canvas:show(screen.width, screen.height)
end

-- Browsing -----------------------------------------------------------------

local function find_file_chooser()
    for _, name in ipairs({ "zenity", "kdialog" }) do
        local result = mp.command_native({
            name = "subprocess",
            args = { "sh", "-c", "command -v " .. name },
            playback_only = false,
            capture_stdout = true,
        })
        if result and result.status == 0 then
            return name
        end
    end
    return nil
end

local function file_chooser_command()
    local home = os.getenv("HOME") or "/"
    local patterns = {}
    for _, extension in ipairs(VIDEO_EXTENSIONS) do
        table.insert(patterns, "*." .. extension)
    end
    local pattern_list = table.concat(patterns, " ")

    if file_chooser == "zenity" then
        return {
            "zenity", "--file-selection", "--title=Open a video",
            "--filename=" .. home .. "/Videos/",
            "--file-filter=Videos | " .. pattern_list,
            "--file-filter=All files | *",
        }
    end
    return {
        "kdialog", "--getopenfilename", home .. "/Videos",
        pattern_list .. "|Videos",
        "--title", "Open a video",
    }
end

-- Opens the file chooser, and plays whatever's chosen. It runs in the
-- background, so the window keeps redrawing while the chooser is open.
local function browse()
    if file_chooser == nil then
        return
    end

    mp.command_native_async({
        name = "subprocess",
        args = file_chooser_command(),
        playback_only = false,
        capture_stdout = true,
    }, function(success, result)
        local path = success and result and result.stdout or ""
        path = path:gsub("%s+$", "")
        if path ~= "" then
            mp.commandv("loadfile", path)
        end
    end)
end

local clicks = click_area.create("idle-drop-box", {
    priority = click_area.PRIORITY_CONTROLS,
    on_click = browse,
})

local function on_pointer_moved()
    local is_inside = is_idle and drop_box ~= nil and pointer.is_inside(drop_box)
    clicks:update(is_inside and file_chooser ~= nil)

    if is_inside ~= is_box_hovered then
        is_box_hovered = is_inside
        redraw.request()
    end
end

function idle_screen.start()
    file_chooser = find_file_chooser()

    redraw.register(render)
    screen.on_change(redraw.request)
    pointer.on_move(on_pointer_moved)
    mp.observe_property("idle-active", "bool", function(_, idle)
        is_idle = idle == true
        if not is_idle then
            is_box_hovered = false
            clicks:update(false)
        end
        redraw.request()
    end)
end

return idle_screen
