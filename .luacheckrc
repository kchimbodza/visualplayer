-- Checks for common mistakes in the Lua code. Run `luacheck .` before committing.

-- mpv runs scripts with LuaJIT (Lua 5.1 compatible).
std = "luajit"

-- mpv provides the `mp` object to every script.
read_globals = { "mp" }

-- Matches the StyLua line length so the two tools agree.
max_line_length = 100
