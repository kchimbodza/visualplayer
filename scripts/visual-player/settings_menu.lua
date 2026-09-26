-- The settings menu, opened from the settings button in the tools row.
-- Each setting shows its current value on the right; clicking it steps
-- to the next value, and the menu stays open so the change can be seen.
-- See docs/plan.md, Phase 5, step 2.
--
-- This file also puts each setting into effect, when Visual Player
-- starts and whenever it's changed.

local list_menu = require("list_menu")
local screen = require("screen")
local settings = require("settings")
local version = require("version")
local visibility = require("visibility")

local settings_menu = {}

-- Each setting's choices, in the order clicking steps through them, with
-- what to call each one.
local CHOICES = {
    hardware_decoding = {
        { value = "automatic", name = "Automatic" },
        { value = "off", name = "Off" },
    },
    hide_controls_after_seconds = {
        { value = 2, name = "2 seconds" },
        { value = 4, name = "4 seconds" },
        { value = 8, name = "8 seconds" },
    },
    interface_size = {
        { value = "normal", name = "Normal" },
        { value = "large", name = "Large" },
        { value = "extra_large", name = "Extra large" },
    },
    remember_window_size = {
        { value = false, name = "Off" },
        { value = true, name = "On" },
    },
}

-- How much bigger each interface size draws everything. Large is meant
-- for touch screens and TVs (docs/plan.md, section 5.9).
local INTERFACE_SIZE_MULTIPLIERS = {
    normal = 1,
    large = 1.35,
    extra_large = 1.6,
}

local function name_of_current_choice(setting)
    local current = settings.get(setting)
    for _, choice in ipairs(CHOICES[setting]) do
        if choice.value == current then
            return choice.name
        end
    end
    return tostring(current)
end

local function step_to_next_choice(setting)
    local choices = CHOICES[setting]
    local current = settings.get(setting)

    local next_index = 1
    for index, choice in ipairs(choices) do
        if choice.value == current then
            next_index = index % #choices + 1
        end
    end

    settings.set(setting, choices[next_index].value)
end

local function setting_item(label, setting)
    return {
        label = label,
        value = name_of_current_choice(setting),
        keep_open = true,
        action = function()
            step_to_next_choice(setting)
        end,
    }
end

local function sections()
    return {
        {
            heading = "Settings",
            items = {
                setting_item("Hardware decoding", "hardware_decoding"),
                setting_item("Hide controls after", "hide_controls_after_seconds"),
                setting_item("Interface size", "interface_size"),
                setting_item("Remember window size", "remember_window_size"),
            },
        },
        {
            heading = "About",
            items = {
                {
                    label = "Visual Player " .. version,
                    details = "using " .. mp.get_property("mpv-version", "mpv"),
                    is_disabled = true,
                },
            },
        },
    }
end

local menu = list_menu.create("settings", sections)

settings_menu.toggle = menu.toggle
settings_menu.is_open = menu.is_open
settings_menu.place_above = menu.place_above

-- Puts one setting into effect.
local function apply(name)
    if name == "hardware_decoding" then
        local hwdec = "auto-safe"
        if settings.get(name) == "off" then
            hwdec = "no"
        end
        mp.set_property("hwdec", hwdec)
    elseif name == "hide_controls_after_seconds" then
        visibility.set_hide_delay(settings.get(name))
    elseif name == "interface_size" then
        screen.set_size_multiplier(INTERFACE_SIZE_MULTIPLIERS[settings.get(name)] or 1)
    end
end

-- Remembering the window size: saved when Visual Player closes, and used
-- as the starting size next time instead of the usual 70% of the screen.
-- Fullscreen and maximized windows aren't remembered, since they aren't
-- a size the person chose.
local function remember_window_size()
    if not settings.get("remember_window_size") or not screen.is_ready() then
        return
    end
    local is_fullscreen = mp.get_property_bool("fullscreen", false)
    local is_maximized = mp.get_property_bool("window-maximized", false)
    if is_fullscreen or is_maximized then
        return
    end

    -- Saved in the desktop's own units, so it reopens the same size on
    -- screens with different scaling.
    settings.set("remembered_window_width", math.floor(screen.width / screen.hidpi_scale))
    settings.set("remembered_window_height", math.floor(screen.height / screen.hidpi_scale))
end

local function use_remembered_window_size()
    local width = settings.get("remembered_window_width")
    local height = settings.get("remembered_window_height")
    if settings.get("remember_window_size") and width and height then
        mp.set_property("geometry", string.format("%dx%d", width, height))
    end
end

function settings_menu.start()
    apply("hardware_decoding")
    apply("hide_controls_after_seconds")
    apply("interface_size")
    use_remembered_window_size()

    settings.on_change(apply)
    mp.register_event("shutdown", remember_window_size)
end

return settings_menu
