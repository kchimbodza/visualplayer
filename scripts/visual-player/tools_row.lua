-- The tools row along the very bottom: subtitles, menu, info, rotate,
-- and settings on the left, and the audio output and volume on the
-- right. See docs/plan.md, 5.3 and 5.4.
--
-- Like playback_row.lua, this file decides what each control shows and
-- does, and bottom_controls.lua places and draws them. Controls are
-- described the same way; see the top of playback_row.lua. One extra
-- kind appears here: the volume slider, which has a "slider" table
-- describing how to draw it and how to respond to dragging.
--
-- The settings button opens the settings menu (settings_menu.lua).

local audio_output = require("outputs.audio")
local draw = require("draw")
local info_panel = require("info_panel")
local menus = require("menus")
local settings_menu = require("settings_menu")
local output_popup = require("output_popup")
local picture_in_picture = require("picture_in_picture")
local pointer = require("pointer")
local redraw = require("redraw")
local screen = require("screen")
local style = require("style")
local touch = require("touch")

local tools_row = {}

-- Sizes in design pixels. See screen.lua.
local VOLUME_SLIDER_WIDTH = 110
local SLIDER_THICKNESS = 4
local SLIDER_KNOB_RADIUS = 6

-- The highest volume the slider offers. mpv allows up to 130, but above
-- 100 it amplifies the audio and can distort it, so the slider stops at
-- 100. The keyboard can still go higher.
local LOUDEST_VOLUME = 100

-- How long placeholder notes stay on screen.
local NOTE_SECONDS = 2

-- Whether the volume slider is showing. It appears while the pointer is
-- over the volume icon or the slider, or while the slider is dragged.
local is_volume_expanded = false

local function show_note(text)
    mp.osd_message(text, NOTE_SECONDS)
end

-- The CC button opens the audio and subtitles menu. It's dimmed while
-- subtitles are off, as a reminder of their state.
local function subtitles_control()
    local look = "normal"
    if mp.get_property("sid", "no") == "no" then
        look = "dim"
    end

    return {
        name = "subtitles",
        icon = "badge-cc",
        look = look,
        action = menus.toggle_audio_and_subtitles,
    }
end

-- Opens and closes the info panel.
local function info_control()
    return {
        name = "info",
        icon = "info-circle",
        look = "normal",
        action = info_panel.toggle,
    }
end

-- Turns the picture a quarter turn each click, and briefly confirms the
-- new angle, since a rotation can be hard to notice on some scenes.
local function rotate_control()
    return {
        name = "rotate",
        icon = "rotate-clockwise",
        look = "normal",
        action = function()
            mp.command("cycle-values video-rotate 90 180 270 0")
            show_note(string.format("Rotation %d°", mp.get_property_number("video-rotate", 0)))
        end,
    }
end

-- The output chip's icon and short label for each kind of output, like
-- "DP" with a monitor icon. Bluetooth shows its codec instead, since
-- that says the most about the sound. Details come from
-- outputs/audio.lua. Clicking the chip opens the output popup.
local OUTPUT_ICON_AND_LABEL = {
    hdmi = { "device-tv", "HDMI" },
    displayport = { "device-desktop", "DP" },
    usb = { "usb", "USB" },
    speakers = { "device-laptop", "Speakers" },
    bluetooth = { "bluetooth", "Bluetooth" },
}

local function describe_output()
    local output = audio_output.current()
    if output == nil then
        return "device-desktop", "Auto"
    end

    local icon, label = unpack(OUTPUT_ICON_AND_LABEL[output.kind] or { "device-desktop", "Output" })
    if output.kind == "bluetooth" and output.codec then
        label = output.codec
    end
    return icon, label
end

local function output_control()
    local icon, label = describe_output()

    return {
        name = "output",
        icon = icon,
        label = label,
        look = "normal",
        action = output_popup.toggle,
    }
end

local function is_muted()
    return mp.get_property_bool("mute", false)
end

local function current_volume()
    return mp.get_property_number("volume", 100)
end

local function volume_icon_name()
    local volume = current_volume()

    if is_muted() or volume <= 0 then
        return "volume-3"
    end

    if volume < 50 then
        return "volume-2"
    end

    return "volume"
end

-- Clicking the volume icon mutes and unmutes. With touch controls on,
-- the first tap opens the volume slider instead, since a finger can't
-- hover to open it, and tapping again mutes.
local function volume_control()
    return {
        name = "volume",
        icon = volume_icon_name(),
        look = "normal",
        action = function()
            if touch.is_on() and not is_volume_expanded then
                is_volume_expanded = true
                redraw.request()
                return
            end
            mp.command("cycle mute")
        end,
    }
end

-- The part of the slider the knob can move along, leaving room at each
-- end so the knob never pokes outside the slider.
local function slider_track(area)
    local knob_radius = screen.pixels(SLIDER_KNOB_RADIUS)
    return area.left + knob_radius, area.right - knob_radius
end

local function draw_volume_slider(canvas, area)
    local track_left, track_right = slider_track(area)
    local middle_y = (area.top + area.bottom) / 2
    local thickness = screen.pixels(SLIDER_THICKNESS)

    local fraction = math.max(0, math.min(1, current_volume() / LOUDEST_VOLUME))
    local knob_x = track_left + fraction * (track_right - track_left)

    -- While muted, the level still shows, but dimmed, so it's clear the
    -- volume setting is kept for when sound comes back.
    local fill_opacity = 1
    if is_muted() then
        fill_opacity = 0.45
    end

    canvas:add(draw.rectangle({
        area = {
            left = track_left,
            top = middle_y - thickness / 2,
            right = track_right,
            bottom = middle_y + thickness / 2,
        },
        color = style.TRACK_COLOR,
        opacity = style.TRACK_OPACITY,
        corner_radius = thickness / 2,
    }))
    canvas:add(draw.rectangle({
        area = {
            left = track_left,
            top = middle_y - thickness / 2,
            right = knob_x,
            bottom = middle_y + thickness / 2,
        },
        color = style.TEXT_COLOR,
        opacity = fill_opacity,
        corner_radius = thickness / 2,
    }))
    canvas:add(draw.circle({
        x = knob_x,
        y = middle_y,
        radius = screen.pixels(SLIDER_KNOB_RADIUS),
        color = style.TEXT_COLOR,
        opacity = fill_opacity,
    }))
end

-- Sets the volume to match where the pointer is along the slider. Moving
-- the slider also unmutes, since that's clearly what's wanted.
local function set_volume_from_pointer(area)
    local track_left, track_right = slider_track(area)
    local fraction = (pointer.x - track_left) / (track_right - track_left)
    fraction = math.max(0, math.min(1, fraction))

    mp.set_property_number("volume", math.floor(fraction * LOUDEST_VOLUME + 0.5))
    if is_muted() then
        mp.set_property_bool("mute", false)
    end
end

local function volume_slider_control()
    return {
        name = "volume-slider",
        look = "normal",
        slider = {
            width = VOLUME_SLIDER_WIDTH,
            draw = draw_volume_slider,
            on_press = set_volume_from_pointer,
            on_drag = set_volume_from_pointer,
        },
    }
end

-- Returns the controls to show, in order, split into those on the left
-- and those on the right.
function tools_row.get_controls()
    local right = { output_control() }
    if is_volume_expanded then
        table.insert(right, volume_slider_control())
    end
    table.insert(right, volume_control())

    return {
        left = {
            subtitles_control(),
            {
                name = "menu",
                icon = "list",
                look = "normal",
                action = menus.toggle_chapters_and_playlist,
            },
            info_control(),
            rotate_control(),
            {
                name = "picture-in-picture",
                icon = "picture-in-picture",
                look = "normal",
                action = picture_in_picture.toggle,
            },
            {
                name = "settings",
                icon = "settings",
                look = "normal",
                action = settings_menu.toggle,
            },
        },
        right = right,
    }
end

-- Shows or hides the volume slider. Returns true if that changed, so a
-- redraw is needed.
function tools_row.set_volume_expanded(expanded)
    if expanded == is_volume_expanded then
        return false
    end

    is_volume_expanded = expanded
    return true
end

function tools_row.start()
    audio_output.on_change(redraw.request)

    local properties_that_change_the_row = {
        "sid",
        "track-list",
        "volume",
        "mute",
    }

    for _, property in ipairs(properties_that_change_the_row) do
        mp.observe_property(property, "native", redraw.request)
    end
end

return tools_row
