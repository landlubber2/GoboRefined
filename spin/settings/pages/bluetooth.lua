-- PLACEHOLDER (0.8.2 part 2, NOT implemented): the Bluetooth page of the Settings app
-- (on/off, pair, connect). To implement: fill in build() below, then add "bluetooth" to PAGES in
-- main.lua (between "network" and "sound"). Anything that needs root becomes a new, strictly
-- checked sub-command of gobo-settings-helper ("How to add a page", HANDOFF.md, 0.8.2 part 1).
local P = { id = "bluetooth", title = "Bluetooth", icon = "bluetooth" }

function P.build(C)
   local outer, box = C.page("Bluetooth", "Not available yet.")
   return outer
end

return P
