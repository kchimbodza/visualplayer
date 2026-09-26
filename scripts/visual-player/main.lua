-- Visual Player: main script.
--
-- mpv loads this file first. It starts each part of Visual Player in turn.
-- The parts themselves live in their own files next to this one.

local audio_output = require("outputs.audio")
local passthrough = require("outputs.passthrough")
local bottom_controls = require("bottom_controls")
local click_area = require("click_area")
local info_panel = require("info_panel")
local menus = require("menus")
local output_popup = require("output_popup")
local picture_in_picture = require("picture_in_picture")
local playback_log = require("playback_log")
local pointer = require("pointer")
local screen = require("screen")
local settings = require("settings")
local settings_menu = require("settings_menu")
local top_bar = require("top_bar")
local touch = require("touch")
local visibility = require("visibility")
local version = require("version")
local video_taps = require("video_taps")
local window_size = require("window_size")

mp.msg.info("Visual Player " .. version .. " started, using " .. mp.get_property("mpv-version"))

-- Saved settings are loaded first, since other parts read them.
settings.load()
touch.start()

screen.start()
pointer.start()
click_area.start()
playback_log.start()
audio_output.start()
passthrough.start()
top_bar.start()
bottom_controls.start()
info_panel.start()
output_popup.start()
menus.start()
picture_in_picture.start()
window_size.start()
visibility.start()
settings_menu.start()
video_taps.start()
