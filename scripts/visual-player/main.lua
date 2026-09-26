-- Visual Player: main script.
--
-- mpv loads this file first. It starts each part of Visual Player in turn.
-- The parts themselves live in their own files next to this one.

local VERSION = "0.4.0-dev"

local audio_output = require("outputs.audio")
local passthrough = require("outputs.passthrough")
local bottom_controls = require("bottom_controls")
local info_panel = require("info_panel")
local output_popup = require("output_popup")
local playback_log = require("playback_log")
local pointer = require("pointer")
local screen = require("screen")
local top_bar = require("top_bar")
local visibility = require("visibility")
local window_size = require("window_size")

mp.msg.info("Visual Player " .. VERSION .. " started, using " .. mp.get_property("mpv-version"))

screen.start()
pointer.start()
playback_log.start()
audio_output.start()
passthrough.start()
top_bar.start()
bottom_controls.start()
info_panel.start()
output_popup.start()
window_size.start()
visibility.start()
