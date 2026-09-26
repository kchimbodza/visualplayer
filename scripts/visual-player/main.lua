-- Visual Player: main script.
--
-- mpv loads this file first. It starts each part of Visual Player in turn.
-- The parts themselves live in their own files next to this one.

local VERSION = "0.2.0-dev"

local playback_log = require("playback_log")
local screen = require("screen")
local toolkit_preview = require("toolkit_preview")

mp.msg.info("Visual Player " .. VERSION .. " started, using " .. mp.get_property("mpv-version"))

screen.start()
playback_log.start()
toolkit_preview.start()
