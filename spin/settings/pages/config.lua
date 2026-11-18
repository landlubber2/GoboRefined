-- Config (0.9.5, advanced): the desktop's own configuration file, Awesome's rc.lua in
-- ~/.config/awesome. A warning first; "Open in text editor" and "Restart desktop" only after the
-- user ticks "I understand". "Restore default" is always there: it copies the look's default
-- (/Programs/GoboSpin/Current/share/gobo11/awesome/rc.lua) back and keeps the user's file as
-- rc.lua.backup-YYYYMMDD-HHMMSS next to it.
--
-- A broken rc.lua does not lock the user out: Awesome then starts its built-in configuration
-- (plain taskbar, no GoboRefined menus); this page is still reachable with "gobo-settings config"
-- from a terminal (Win+Enter in that configuration too) or from Awesome's own menu.
-- Not for Simple accounts (main.lua).
local P = { id = "config", title = "Config", icon = "text-x-script" }

local DEFAULT = "/Programs/GoboSpin/Current/share/gobo11/awesome/rc.lua"

function P.build(C)
   local Gtk, GLib = C.Gtk, C.GLib
   local file = C.HOME .. "/.config/awesome/rc.lua"
   local outer, box = C.page("Desktop configuration (advanced)")

   local bar = Gtk.InfoBar { message_type = Gtk.MessageType.WARNING, show_close_button = false }
   local warn = Gtk.Label { label = "The desktop's own configuration file. A mistake here can stop the desktop from starting. For advanced users.",
                            xalign = 0, wrap = true, max_width_chars = 70 }
   local bar_box = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 12 }
   bar_box:pack_start(Gtk.Image { icon_name = "dialog-warning", pixel_size = 32 }, false, false, 0)
   bar_box:pack_start(warn, true, true, 0)
   bar:get_content_area():add(bar_box)
   box:pack_start(bar, false, false, 0)
   box:pack_start(C.text("File: " .. file .. "\nA system update puts the default file back (copy your changes somewhere else first). "
      .. "If the desktop does not start properly after a change, it starts a plain built-in desktop instead: "
      .. "open a terminal there (Win+Enter), type  gobo-settings config  and press Restore default.", "dim-label"), false, false, 0)

   local understand = Gtk.CheckButton { label = "I understand; show the editing tools" }
   box:pack_start(understand, false, false, 0)

   local edit = C.button("Open in text editor", function()
      if C.exists("/System/Index/bin/l3afpad") then C.spawn({ "l3afpad", file })
      else C.spawn({ "xdg-open", file }) end
   end)
   local restart = C.button("Restart desktop (apply)", function()
      local p = io.popen("awesome -k -c " .. C.q(file) .. " 2>&1", "r")
      local out = p and p:read("*a") or ""
      if p then p:close() end
      if not out:lower():match("syntax ok") then
         if not C.confirm("Awesome reports a problem in the file:\n\n" .. C.trim(out) ..
                          "\n\nRestart anyway? The desktop will then start its plain built-in configuration.", "Restart anyway") then
            return
         end
      end
      C.desktop("awesome.restart()")
   end)
   edit.sensitive, restart.sensitive = false, false
   understand.on_toggled = function(b) edit.sensitive = b.active; restart.sensitive = b.active end
   box:pack_start(C.row(edit, restart), false, false, 0)

   box:pack_start(C.heading("Restore the default"), false, false, 0)
   box:pack_start(C.text("Puts the GoboRefined default file back. Your current file is kept next to it as rc.lua.backup-<date>.", "dim-label"), false, false, 0)
   local restore = C.button("Restore default", function()
      if not C.exists(DEFAULT) then C.error("The default file is missing:\n" .. DEFAULT) return end
      if not C.confirm("Replace your desktop configuration file with the default?\nYour current file is kept as a backup.", "Restore default") then return end
      local backup
      if C.exists(file) then
         backup = file .. ".backup-" .. os.date("%Y%m%d-%H%M%S")
         local ok, err = os.rename(file, backup)
         if not ok then C.error("Could not keep the old file:\n" .. tostring(err)) return end
      end
      GLib.mkdir_with_parents(C.HOME .. "/.config/awesome", tonumber("0755", 8))
      local i, o = io.open(DEFAULT, "rb"), io.open(file, "wb")
      if not (i and o) then
         if i then i:close() end
         if o then o:close() end
         if backup then os.rename(backup, file) end
         C.error("Could not write " .. file)
         return
      end
      o:write(i:read("*a")); i:close(); o:close()
      if C.confirm("The default file is back" .. (backup and (" (old file: " .. backup:match("[^/]*$") .. ")") or "") ..
                   ".\nRestart the desktop now to use it?", "Restart desktop") then
         C.desktop("awesome.restart()")
      end
   end, "suggested-action")
   box:pack_start(restore, false, false, 0)
   return outer
end

return P
