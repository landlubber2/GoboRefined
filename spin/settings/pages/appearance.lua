-- Appearance: light/dark (the look's set-mode.sh through the power menu's switch, so Awesome,
-- GTK and the desktop icons change together) and the wallpaper.
--
-- Wallpaper choice: a copy of the picture at ~/.config/goborefined/wallpaper. That folder is
-- not touched by the look's apply.sh (which rewrites ~/.config/awesome after every system
-- update), so the choice survives light/dark switches, Awesome restarts and updates. rc.lua
-- draws it (set_wallpaper) and hands it on to PCManFM's desktop (spin/desktop_icons.lua).
local P = { id = "appearance", title = "Appearance", icon = "preferences-desktop-wallpaper" }

function P.build(C)
   local Gtk, Gio = C.Gtk, C.Gio
   local outer, box = C.page("Appearance")
   local dir = C.HOME .. "/.config/goborefined"
   local wp = dir .. "/wallpaper"

   local function mode()
      local m = C.trim(C.read(C.HOME .. "/.config/awesome/mode") or "")
      return m == "light" and "light" or "dark"
   end

   box:pack_start(C.heading("Colours"), false, false, 0)
   local light = Gtk.RadioButton.new_with_label(nil, "Light")
   local dark = Gtk.RadioButton.new_with_label_from_widget(light, "Dark")
   if mode() == "light" then light.active = true else dark.active = true end
   local function switch(to)
      if mode() == to then return end
      -- the power menu's switch: set-mode.sh, remember the desktop, restart Awesome
      C.desktop('require("spin.power").toggle_mode()')
      Gtk.Settings.get_default().gtk_application_prefer_dark_theme = (to == "dark")
   end
   light.on_toggled = function(b) if b.active then switch("light") end end
   dark.on_toggled = function(b) if b.active then switch("dark") end end
   box:pack_start(C.row(light, dark), false, false, 0)
   box:pack_start(C.text("Changes the desktop, the taskbar and the windows of programs. Programs that are open keep their colours until they are started again.", "dim-label"), false, false, 0)

   -- 0.9.5: where the start button and the running apps sit on the taskbar. Stored in
   -- ~/.config/goborefined/taskbar-align ("left"; no file = centre); rc.lua re-arranges every
   -- taskbar at once (spin_taskbar_align), no restart needed.
   box:pack_start(C.heading("Taskbar"), false, false, 0)
   local align_file = dir .. "/taskbar-align"
   local function align()
      return C.trim(C.read(align_file) or "") == "left" and "left" or "center"
   end
   local centre = Gtk.RadioButton.new_with_label(nil, "Centre")
   local left = Gtk.RadioButton.new_with_label_from_widget(centre, "Left")
   if align() == "left" then left.active = true else centre.active = true end
   local function set_align(to)
      if align() == to then return end
      if to == "left" then
         os.execute("mkdir -p " .. C.q(dir))
         local f = io.open(align_file, "w")
         if not f then C.error("Could not save the choice in " .. align_file) return end
         f:write("left\n"); f:close()
      else
         os.remove(align_file)
      end
      C.desktop("if spin_taskbar_align then spin_taskbar_align() end")
   end
   centre.on_toggled = function(b) if b.active then set_align("center") end end
   left.on_toggled = function(b) if b.active then set_align("left") end end
   box:pack_start(C.row(centre, left), false, false, 0)
   box:pack_start(C.text("Where the start button and the apps sit on the taskbar: in the middle, or at the left edge. The clock and the icons on the right stay where they are.", "dim-label"), false, false, 0)

   box:pack_start(C.heading("Wallpaper"), false, false, 0)
   local preview = Gtk.Image()
   local state = C.text("")
   local function refresh()
      if C.exists(wp) then
         local pix = C.GdkPixbuf.Pixbuf.new_from_file_at_scale(wp, 320, 180, true)
         if pix then preview:set_from_pixbuf(pix) else preview:clear() end
         state.label = "Your own picture."
      else
         preview:clear()
         state.label = "The GoboRefined wallpaper (drawn to fit the screen, light or dark)."
      end
   end
   local function apply()
      C.desktop("if spin_reload_wallpaper then spin_reload_wallpaper() end")
      refresh()
   end
   local choose = C.button("Choose a picture...", function()
      local file = C.choose_file("Choose a wallpaper", "Pictures", { "image/png", "image/jpeg", "image/webp", "image/bmp", "image/gif" },
                                 C.HOME .. "/Pictures")
      if not file then return end
      if not C.GdkPixbuf.Pixbuf.new_from_file_at_scale(file, 64, 64, true) then
         C.error("This file is not a picture that can be shown.")
         return
      end
      os.execute("mkdir -p " .. C.q(dir))
      local src, dst = Gio.File.new_for_path(file), Gio.File.new_for_path(wp)
      local ok, err = src:copy(dst, { "OVERWRITE" }, nil, nil)
      if not ok then C.error("Could not copy the picture:\n" .. tostring(err)) return end
      apply()
   end)
   local default = C.button("Use the GoboRefined wallpaper", function()
      os.remove(wp)
      apply()
   end)
   refresh()
   box:pack_start(preview, false, false, 0)
   box:pack_start(state, false, false, 0)
   box:pack_start(C.row(choose, default), false, false, 0)
   return outer
end

return P
