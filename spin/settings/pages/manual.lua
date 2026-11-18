-- Manual (0.9.5): the short offline GoboRefined manual, one HTML page on the image
-- (/Programs/GoboSpin/Current/share/doc/goborefined-manual/index.html), opened in the default
-- browser. The window manager's own reference (pinfo awesome) is a small button at the bottom.
local P = { id = "manual", title = "Manual", icon = "help-contents" }

P.FILE = "/Programs/GoboSpin/Current/share/doc/goborefined-manual/index.html"

function P.open(C)
   local uri = "file://" .. P.FILE
   if C.exists("/System/Index/bin/xdg-open") then C.spawn({ "xdg-open", uri })
   else C.spawn({ "firefox", uri }) end
end

function P.build(C)
   local outer, box = C.page("Manual")
   box:pack_start(C.text("A short guide to GoboRefined, on this computer (no internet needed): keyboard shortcuts, "
      .. "adding programs, system updates and going back, where settings are kept, and links to the "
      .. "GoboLinux documentation. It opens in your web browser."), false, false, 0)
   local open = C.button("Open the manual", function()
      if not C.exists(P.FILE) then C.error("The manual is missing:\n" .. P.FILE) return end
      P.open(C)
   end, "suggested-action")
   box:pack_start(open, false, false, 0)
   if C.kind() ~= "simple" then
      box:pack_start(C.heading("Window manager reference"), false, false, 0)
      box:pack_start(C.text("The technical manual of Awesome, the program that draws the desktop (in a terminal).", "dim-label"), false, false, 0)
      box:pack_start(C.button("Window manager reference", function()
         C.spawn({ "urxvt", "-title", "Awesome manual", "-e", "pinfo", "awesome" })
      end), false, false, 0)
   end
   return outer
end

return P
