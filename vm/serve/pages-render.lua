-- Lab check (0.9.5; 0.9.6: + hotkeys): build every Settings page off screen as the desktop user; prints ok/FAIL per page.
package.path = "/System/Aliens/LuaRocks/share/lua/5.3/?.lua;/System/Aliens/LuaRocks/share/lua/5.3/?/init.lua;" .. package.path
package.cpath = "/System/Aliens/LuaRocks/lib/lua/5.3/?.so;" .. package.cpath
local here = "/Programs/GoboSpin/Current/share/gobo-settings"
package.path = here .. "/?.lua;" .. package.path
local lgi = require("lgi")
local Gtk = lgi.require("Gtk", "3.0")
local C = require("common")
C.window = Gtk.Window {}
for _, id in ipairs({ "network", "bluetooth", "hotspot", "remote", "appearance", "hotkeys", "trash", "displays", "sound",
                      "devices", "updates", "apps", "accounts", "about", "manual", "config" }) do
   local ok, page = pcall(require, "pages." .. id)
   local ok2, w = false, page
   if ok then ok2, w = pcall(page.build, C) end
   print(string.format("%-11s %s", id, (ok and ok2 and w) and "ok" or ("FAIL " .. tostring(w))))
end
