-- Visual Player: main script.
--
-- mpv loads this file first. It starts each part of Visual Player in turn.
-- The parts themselves live in their own files next to this one.

local VERSION = "0.2.0-dev"

local bottom_controls = require("bottom_controls")
local playback_log = require("playback_log")
local pointer = require("pointer")
local screen = require("screen")
local toolkit_preview = require("toolkit_preview")
local top_bar = require("top_bar")
local window_size = require("window_size")

mp.msg.info("Visual Player " .. VERSION .. " started, using " .. mp.get_property("mpv-version"))

screen.start()
pointer.start()
playback_log.start()
top_bar.start()
bottom_controls.start()
window_size.start()
toolkit_preview.start()
