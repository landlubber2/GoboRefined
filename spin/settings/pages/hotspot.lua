-- PLACEHOLDER (0.8.2 part 2, NOT implemented): the Wi-Fi hotspot page of the Settings app.
-- To implement: fill in build() below, then add "hotspot" to PAGES in main.lua (between
-- "network" and "sound"). Anything that needs root becomes a new, strictly checked sub-command
-- of gobo-settings-helper ("How to add a page", HANDOFF.md, 0.8.2 part 1).
local P = { id = "hotspot", title = "Hotspot", icon = "network-wireless-hotspot" }

function P.build(C)
   local outer, box = C.page("Hotspot", "Not available yet.")
   return outer
end

return P
