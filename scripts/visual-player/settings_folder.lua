-- Where Visual Player keeps its own settings files: settings.json and
-- devices.json, in ~/.config/visual-player/ (or $XDG_CONFIG_HOME/
-- visual-player/), the same folder the launcher gives mpv.
--
-- The path is built directly rather than with mpv's "~~/" shortcut. That
-- shortcut saved the files into whatever folder Visual Player was started
-- from, so settings ended up in the project folder, got committed to git,
-- and a name chosen when starting from one folder was missing when
-- starting from another (Phase 6, found on the Framework 13).

local settings_folder = {}

local function folder()
    local config_home = os.getenv("XDG_CONFIG_HOME")
    if config_home == nil or config_home == "" then
        config_home = (os.getenv("HOME") or "") .. "/.config"
    end
    return config_home .. "/visual-player"
end

local has_made_folder = false

-- The full path of a settings file, making the folder the first time if
-- it isn't there yet, like "/home/kc/.config/visual-player/devices.json".
function settings_folder.path(file_name)
    local path = folder()
    if not has_made_folder then
        mp.command_native({
            name = "subprocess",
            args = { "mkdir", "-p", path },
            playback_only = false,
        })
        has_made_folder = true
    end
    return path .. "/" .. file_name
end

return settings_folder
