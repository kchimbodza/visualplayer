-- Makes sure only one popup or menu is open at a time.
--
-- Each popup registers a function that closes it. Opening any popup then
-- closes the others first. Without this, opening one with a key while
-- another was already open left both showing (Phase 5, step 1).

local popups = {}

local close_functions_by_name = {}

-- Registers a popup under a name, with the function that closes it.
function popups.register(name, close)
    close_functions_by_name[name] = close
end

-- Closes every popup except the one with the given name. Call this just
-- before opening a popup.
function popups.close_all_except(name)
    for other_name, close in pairs(close_functions_by_name) do
        if other_name ~= name then
            close()
        end
    end
end

return popups
