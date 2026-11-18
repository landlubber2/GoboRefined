-- 0.9.6: Hotkeys (Customization): the desktop's keyboard shortcuts.
-- The list of actions, their default keys, the keys that stay fixed and the file format are in
-- the look: ~/.config/awesome/spin/hotkeys_list.lua (the same file rc.lua builds the keys from).
-- Changes are saved in ~/.config/goborefined/hotkeys and applied at once: the desktop builds its
-- keys again (spin_hotkeys_reload through awesome-client), no restart.
-- While the page waits for "press the new keys", the desktop stops acting on its keys
-- (spin_hotkeys_capture(true); back after the dialog, or after 30 s on its own). Win+Escape
-- always stays the desktop's.
-- Not for Simple accounts (main.lua).
local P = { id = "hotkeys", title = "Hotkeys", icon = "preferences-desktop-keyboard-shortcuts" }

function P.build(C)
   local Gtk, GLib, Gio = C.Gtk, C.GLib, C.Gio
   local Gdk = require("lgi").require("Gdk", "3.0")
   local outer, box = C.page("Hotkeys",
      "Keyboard shortcuts of the desktop. Change the keys of an action, turn one off, or add your own shortcut that starts a program or a command.")

   local list_file = C.HOME .. "/.config/awesome/spin/hotkeys_list.lua"
   local ok, H = pcall(dofile, list_file)
   if not ok or type(H) ~= "table" then
      box:pack_start(C.text("The desktop's list of shortcuts was not found (" .. list_file .. "). Log out and in again after a system update.", "dim-label"), false, false, 0)
      return outer
   end
   local file = C.HOME .. H.FILE_NAME
   local cfg = H.load(file)
   local status = Gtk.Label { xalign = 0 }
   status:get_style_context():add_class("dim-label")

   local function save()
      GLib.mkdir_with_parents(C.HOME .. "/.config/goborefined", tonumber("0755", 8))
      local tmp = file .. ".new"
      local f = io.open(tmp, "w")
      if not f then C.error("Could not save " .. file) return false end
      f:write(H.serialize(cfg))
      f:close()
      os.rename(tmp, file)
      C.desktop("if spin_hotkeys_reload then spin_hotkeys_reload() end")
      status.label = "Saved. The new keys work now."
      return true
   end

   -- "press the new keys": returns a combination or nil (cancelled). skip: what is being changed
   local function capture(title, skip)
      local d = Gtk.Dialog { title = title, transient_for = C.window, modal = true, destroy_with_parent = true }
      d:add_button("Cancel", Gtk.ResponseType.CANCEL)
      local area = d:get_content_area()
      local big = Gtk.Label { label = "Press the new keys now", margin = 18 }
      big:get_style_context():add_class("gobo-heading")
      local note = Gtk.Label { label = "For example Win+Shift+E or Ctrl+Alt+T. Escape cancels.", wrap = true,
                               max_width_chars = 50, margin_start = 18, margin_end = 18, margin_bottom = 18 }
      note:get_style_context():add_class("dim-label")
      area:pack_start(big, false, false, 0)
      area:pack_start(note, false, false, 0)
      area:show_all()
      local result
      local keymap = Gdk.Keymap.get_for_display(Gdk.Display.get_default())
      d.on_key_press_event = function(_, ev)
         local base
         -- the key's unshifted meaning (Shift+1 is "1", not "exclam"): level 0 of its keycode
         local okk, kv = pcall(function()
            local found, _, keyvals = keymap:get_entries_for_keycode(ev.hardware_keycode)
            return found and keyvals and keyvals[1] or nil
         end)
         base = (okk and kv and kv ~= 0) and kv or Gdk.keyval_to_lower(ev.keyval)
         local name = Gdk.keyval_name(base) or ""
         if name == "ISO_Left_Tab" then name = "Tab" end
         if name:match("^Super_") or name:match("^Shift_") or name:match("^Control_") or name:match("^Alt_")
            or name:match("^Meta_") or name:match("^ISO_Level") or name:match("^Hyper_") then
            return true   -- a modifier alone: wait for the key
         end
         local st = ev.state
         local mods = {}
         if st.SUPER_MASK or st.MOD4_MASK then table.insert(mods, "Mod4") end
         if st.CONTROL_MASK then table.insert(mods, "Control") end
         if st.MOD1_MASK then table.insert(mods, "Mod1") end
         if st.SHIFT_MASK then table.insert(mods, "Shift") end
         if name == "Escape" and #mods == 0 then d:response(Gtk.ResponseType.CANCEL) return true end
         table.insert(mods, name)
         if os.getenv("GOBO_HOTKEYS_DEBUG") then
            io.stderr:write("hotkeys capture: " .. table.concat(mods, "+") .. " keyval=" .. tostring(ev.keyval)
               .. " base=" .. tostring(base) .. "\n")
         end
         local combo = H.normalize(table.concat(mods, "+"))
         if not combo then note.label = "This key cannot be used." return true end
         local why = H.refuse(cfg, combo, skip)
         if why then
            big.label = H.display(combo) .. ": not possible"
            note.label = why
            return true
         end
         result = combo
         d:response(Gtk.ResponseType.OK)
         return true
      end
      C.desktop("if spin_hotkeys_capture then spin_hotkeys_capture(true) end")
      d:run()
      d:destroy()
      C.desktop("if spin_hotkeys_capture then spin_hotkeys_capture(false) end")
      return result
   end

   local function keys_text(list)
      if #list == 0 then return "(off)" end
      local out = {}
      for _, k in ipairs(list) do table.insert(out, H.display(k)) end
      return table.concat(out, ", ")
   end

   local actions_box = Gtk.Box { orientation = Gtk.Orientation.VERTICAL }
   local custom_box = Gtk.Box { orientation = Gtk.Orientation.VERTICAL }
   local fill   -- forward

   local function grid() return Gtk.Grid { row_spacing = 4, column_spacing = 12 } end
   local function small(label, fn)
      local b = Gtk.Button { label = label }
      b.on_clicked = function() fn() end
      return b
   end

   local function fill_actions()
      C.clear(actions_box)
      local g = grid()
      local kind = C.kind()
      for i, a in ipairs(H.ACTIONS) do
         local row = i - 1
         g:attach(Gtk.Label { label = a.label, xalign = 0, hexpand = true }, 0, row, 1, 1)
         local k = Gtk.Label { label = keys_text(H.keys_of(cfg, a.id)), xalign = 0, width_chars = 22 }
         k:get_style_context():add_class("gobo-value")
         g:attach(k, 1, row, 1, 1)
         g:attach(small("Change...", function()
            local combo = capture("Keys for: " .. a.label, { action = a.id })
            if combo then cfg.over[a.id] = combo; save(); fill() end
         end), 2, row, 1, 1)
         local off = cfg.over[a.id] == false
         g:attach(small(off and "Turn on" or "Turn off", function()
            if off then cfg.over[a.id] = nil else cfg.over[a.id] = false end
            -- turning back on: the default keys, unless something else took them meanwhile
            if off then
               for _, k2 in ipairs(H.keys_of(cfg, a.id)) do
                  local why = H.refuse(cfg, k2, { action = a.id })
                  if why then cfg.over[a.id] = false; C.error(why) return end
               end
            end
            save(); fill()
         end), 3, row, 1, 1)
         local def = small("Default", function()
            cfg.over[a.id] = nil
            for _, k2 in ipairs(H.keys_of(cfg, a.id)) do
               local why = H.refuse(cfg, k2, { action = a.id })
               if why then cfg.over[a.id] = false; C.error(why .. "\nThe action is off until you choose other keys.") break end
            end
            save(); fill()
         end)
         def.sensitive = cfg.over[a.id] ~= nil
         g:attach(def, 4, row, 1, 1)
         if a.power and kind == "simple" then g:get_child_at(0, row).sensitive = false end
      end
      actions_box:pack_start(g, false, false, 0)
      actions_box:show_all()
   end

   -- programs for "start a program": the desktop's application list
   local function app_list()
      local list = {}
      for _, ai in ipairs(Gio.AppInfo.get_all()) do
         if ai:should_show() and ai:get_id() then
            table.insert(list, { ai:get_id(), ai:get_display_name() or ai:get_id() })
         end
      end
      table.sort(list, function(x, y) return x[2]:lower() < y[2]:lower() end)
      return list
   end
   local function app_name(id)
      local ai = Gio.DesktopAppInfo.new(id)
      return ai and ai:get_display_name() or id
   end

   -- add or edit an own shortcut (index = nil: new)
   local function edit_custom(index)
      local c = index and cfg.custom[index] or { name = "", combo = nil, kind = "app", value = "" }
      local d = Gtk.Dialog { title = index and "Change your shortcut" or "Add a shortcut", transient_for = C.window,
                             modal = true, destroy_with_parent = true }
      d:add_button("Cancel", Gtk.ResponseType.CANCEL)
      d:add_button(index and "Save" or "Add", Gtk.ResponseType.OK)
      local g = Gtk.Grid { row_spacing = 10, column_spacing = 12, margin = 18 }
      local name = Gtk.Entry { text = c.name, width_chars = 30 }
      local combo = c.combo
      local keys_btn = Gtk.Button { label = combo and H.display(combo) or "Choose keys..." }
      keys_btn.on_clicked = function()
         local k = capture("Keys for your shortcut", { custom = index or -1 })
         if k then combo = k; keys_btn.label = H.display(k) end
      end
      local prog = Gtk.RadioButton.new_with_label(nil, "Start a program")
      local cmd = Gtk.RadioButton.new_with_label_from_widget(prog, "Run a command")
      local apps = Gtk.ComboBoxText()
      for _, a in ipairs(app_list()) do apps:append(a[1], a[2]) end
      local cmd_entry = Gtk.Entry { width_chars = 30, placeholder_text = "for example: urxvt -e htop" }
      if c.kind == "cmd" then cmd.active = true; cmd_entry.text = c.value
      else prog.active = true; if c.value ~= "" then apps:set_active_id(c.value) end end
      local function sync() apps.sensitive = prog.active; cmd_entry.sensitive = cmd.active end
      prog.on_toggled = sync
      sync()
      g:attach(Gtk.Label { label = "Name", xalign = 1 }, 0, 0, 1, 1); g:attach(name, 1, 0, 1, 1)
      g:attach(Gtk.Label { label = "Keys", xalign = 1 }, 0, 1, 1, 1); g:attach(keys_btn, 1, 1, 1, 1)
      g:attach(prog, 1, 2, 1, 1); g:attach(apps, 1, 3, 1, 1)
      g:attach(cmd, 1, 4, 1, 1); g:attach(cmd_entry, 1, 5, 1, 1)
      d:get_content_area():pack_start(g, true, true, 0)
      g:show_all()
      while true do
         if d:run() ~= Gtk.ResponseType.OK then d:destroy() return end
         local n = C.trim(name.text):gsub("[\t\r\n]", " ")
         local value = prog.active and (apps:get_active_id() or "") or C.trim(cmd_entry.text):gsub("[\t\r\n]", " ")
         local problem
         if n == "" then problem = "Give the shortcut a name."
         elseif not combo then problem = "Choose the keys."
         elseif value == "" then problem = prog.active and "Choose a program." or "Type the command."
         else problem = H.refuse(cfg, combo, { custom = index or -1 }) end
         if not problem then
            local entry = { name = n, combo = combo, kind = prog.active and "app" or "cmd", value = value }
            if index then cfg.custom[index] = entry else table.insert(cfg.custom, entry) end
            d:destroy()
            save(); fill()
            return
         end
         C.error(problem)
      end
   end

   local function fill_custom()
      C.clear(custom_box)
      if #cfg.custom == 0 then
         custom_box:pack_start(C.text("None yet.", "dim-label"), false, false, 0)
      else
         local g = grid()
         for i, c in ipairs(cfg.custom) do
            local row = i - 1
            local what = c.kind == "app" and ("starts " .. app_name(c.value)) or ("runs: " .. c.value)
            g:attach(Gtk.Label { label = c.name, xalign = 0 }, 0, row, 1, 1)
            local k = Gtk.Label { label = H.display(c.combo), xalign = 0, width_chars = 18 }
            k:get_style_context():add_class("gobo-value")
            g:attach(k, 1, row, 1, 1)
            g:attach(Gtk.Label { label = what, xalign = 0, hexpand = true, ellipsize = 3, max_width_chars = 34 }, 2, row, 1, 1)
            g:attach(small("Change...", function() edit_custom(i) end), 3, row, 1, 1)
            g:attach(small("Remove", function() table.remove(cfg.custom, i); save(); fill() end), 4, row, 1, 1)
         end
         custom_box:pack_start(g, false, false, 0)
      end
      custom_box:show_all()
   end

   fill = function() fill_actions(); fill_custom() end

   box:pack_start(C.heading("Desktop shortcuts"), false, false, 0)
   box:pack_start(actions_box, false, false, 0)
   box:pack_start(C.heading("Your own shortcuts"), false, false, 0)
   box:pack_start(custom_box, false, false, 0)
   box:pack_start(C.button("Add a shortcut...", function() edit_custom(nil) end), false, false, 0)

   box:pack_start(C.heading("Always the same"), false, false, 0)
   local fg = grid()
   for i, fx in ipairs(H.FIXED) do
      local shown = {}
      for j, k in ipairs(fx.keys) do
         if j > 4 then table.insert(shown, "...") break end
         table.insert(shown, H.display(k))
      end
      fg:attach(Gtk.Label { label = fx.label, xalign = 0, hexpand = true }, 0, i - 1, 1, 1)
      local k = Gtk.Label { label = table.concat(shown, ", "), xalign = 0 }
      k:get_style_context():add_class("dim-label")
      fg:attach(k, 1, i - 1, 1, 1)
   end
   box:pack_start(fg, false, false, 0)

   box:pack_start(C.button("Reset all to defaults", function()
      if C.confirm("Use the default keys for every action and remove your own shortcuts?", "Reset") then
         cfg = H.parse("")
         save(); fill()
         status.label = "All keys are back to the defaults."
      end
   end), false, false, 0)
   box:pack_start(status, false, false, 0)

   fill()
   return outer
end

return P
