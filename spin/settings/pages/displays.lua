-- Displays: opens the displays tool (LXRandR) or extends the desktop across every display
-- (the look's displays.sh --auto, also in the dots menu: Desktop > Detect Displays).
local P = { id = "displays", title = "Displays", icon = "video-display" }

function P.build(C)
   local outer, box = C.page("Displays", "Resolution and arrangement of the screens.")
   local list = {}
   for line in C.pread("xrandr --query"):gmatch("[^\n]+") do
      local name = line:match("^(%S+) connected")
      if name then
         local mode = line:match(" (%d+x%d+)%+%d+%+%d+")
         table.insert(list, name .. (mode and ("  " .. mode) or "  (not in use)"))
      end
   end
   if #list > 0 then box:pack_start(C.text("Connected: " .. table.concat(list, ",  ")), false, false, 0) end
   box:pack_start(C.row(
      C.button("Open the displays tool", function() C.spawn({ "lxrandr" }) end, "suggested-action"),
      C.button("Use every connected display", function()
         C.spawn({ "sh", C.HOME .. "/.config/awesome/displays.sh", "--auto" })
      end)), false, false, 0)
   return outer
end

return P
