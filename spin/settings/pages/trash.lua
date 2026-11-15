-- Trash: how long deleted files are kept (gobo-trash-purge --set-months 1|3|6, saved in
-- ~/.config/gobo-trash.conf; the desktop deletes older items at login and once a day).
local P = { id = "trash", title = "Trash", icon = "user-trash" }

function P.build(C)
   local Gtk = C.Gtk
   local outer, box = C.page("Trash", "Deleted files stay in the Trash until it is emptied, or until they are older than this:")
   local current = tonumber(C.trim(C.pread("gobo-trash-purge --months"))) or 6
   local first
   for _, m in ipairs({ 1, 3, 6 }) do
      local label = m == 1 and "1 month" or (m .. " months")
      local b = first and Gtk.RadioButton.new_with_label_from_widget(first, label) or Gtk.RadioButton.new_with_label(nil, label)
      first = first or b
      b.active = (m == current)
      b.on_toggled = function(btn)
         if btn.active then
            C.run({ "gobo-trash-purge", "--set-months", tostring(m) }, nil, function(ok, out)
               if not ok then C.error("Could not save: " .. out) end
            end)
         end
      end
      box:pack_start(b, false, false, 0)
   end
   box:pack_start(C.button("Open the Trash", function() C.spawn({ "gobo-trash" }) end), false, false, 0)
   return outer
end

return P
