-- Updates: browser updates (Firefox ESR, P3) and A/B system updates (gobo-update).
-- All mutating actions go through gobo-settings-helper. 0.10: one btrfs pool holds both versions
-- and the user's files, so the free space shown is the pool's (shared), not a fixed slot's.
local P = { id = "updates", title = "Updates", icon = "system-software-update" }

local function read_browser_status(C)
   local s = {}
   local out = C.pread("/System/Index/bin/gobo-browser-update status")
   for line in out:gmatch("[^\r\n]+") do
      local k, v = line:match("^([a-z_]+)=(.*)$")
      if k then s[k] = v end
   end
   return s
end

function P.build(C)
   local Gtk = C.Gtk
   local outer, box = C.page("Updates")
   local version = C.trim(C.read("/Programs/GoboSpin/Current/share/spin-version") or "?"):match("^[^\n]*")
   local scroll, append, clear = C.output_view(200)
   local busy = false
   local restart_btn

   local function run(args, title, after)
      if busy then return end
      busy = true
      clear()
      append(title .. "\n")
      C.helper(args, nil, function(ok, out, code)
         busy = false
         if not ok and code ~= 0 and not out:match("\n") then append(C.clean_error(out) .. "\n") end
         if after then after(ok, out) end
      end, function(line) append(line .. "\n") end)
   end

   -- Web browser (Firefox ESR, P3) ---------------------------------------------------------
   box:pack_start(C.text("Web browser (Firefox ESR)", "gobo-section"), false, false, 0)
   local ff_info = C.text("", "gobo-value")
   local ff_detail = C.text("", "dim-label")
   box:pack_start(ff_info, false, false, 0)
   box:pack_start(ff_detail, false, false, 0)

   local ff_auto = Gtk.CheckButton { label = "Update Firefox automatically (daily check)" }
   local ff_undo_btn
   local ignore_toggle = false

   local function refresh_browser()
      local st = read_browser_status(C)
      local inst = (st.installed and st.installed ~= "") and st.installed or "unknown"
      ff_info.label = "Installed: Firefox " .. inst
      local parts = {}
      if st.last_check and st.last_check ~= "" then
         parts[#parts + 1] = "Last check: " .. st.last_check .. (st.last_status ~= "" and (" (" .. st.last_status .. ")") or "")
      else
         parts[#parts + 1] = "Not checked yet"
      end
      if st.undo and st.undo ~= "" then
         parts[#parts + 1] = "Previous version kept: " .. st.undo
      end
      if st.last_error and st.last_error ~= "" then
         parts[#parts + 1] = "Last error: " .. st.last_error
      end
      ff_detail.label = table.concat(parts, "  ·  ")
      ignore_toggle = true
      ff_auto.active = (st.auto ~= "off")
      ignore_toggle = false
      if ff_undo_btn then
         ff_undo_btn.sensitive = C.is_admin() and (st.undo ~= nil and st.undo ~= "")
      end
   end

   ff_auto.sensitive = C.is_admin()
   ff_auto.on_toggled = function()
      if ignore_toggle then return end
      local want = ff_auto.active and "on" or "off"
      run({ "browser-auto", want }, "Saving Firefox automatic update setting (" .. want .. ")...", function()
         refresh_browser()
      end)
   end

   local ff_update_btn = C.button("Check & update Firefox", function()
      run({ "browser-update" }, "Checking Mozilla for Firefox ESR updates...", function()
         refresh_browser()
      end)
   end)
   ff_undo_btn = C.button("Undo last browser update", function()
      local st = read_browser_status(C)
      if not st.undo or st.undo == "" then return end
      if not C.confirm("Switch Firefox back to " .. st.undo .. "?", "Undo") then return end
      run({ "browser-undo" }, "Switching Firefox back to " .. st.undo .. "...", function()
         refresh_browser()
      end)
   end)
   ff_update_btn.sensitive = C.is_admin()
   refresh_browser()

   box:pack_start(ff_auto, false, false, 0)
   box:pack_start(C.row(ff_update_btn, ff_undo_btn), false, false, 0)

   -- System (A/B slots) --------------------------------------------------------------------
   box:pack_start(C.text("System (GoboRefined)", "gobo-section"), false, false, 4)
   box:pack_start(C.text("This computer runs GoboRefined " .. version .. " (based on GoboLinux 017.01).", "gobo-value"), false, false, 0)
   box:pack_start(C.text("GoboRefined keeps two versions of the system (A and B). An update becomes the version that is not running; the computer starts it after the next restart. If it does not start, the computer goes back to the other version by itself. Files that did not change are shared by both versions, so the second version takes little space.", "dim-label"), false, false, 0)
   local avail = C.pread("df -h --output=avail /System/Data"):match("\n%s*(%S+)")
   if avail then
      box:pack_start(C.text("Free on the disk: about " .. avail .. " (shared by the system versions and your files)", "dim-label"), false, false, 0)
   end

   local status = C.button("Show both system versions", function()
      run({ "update-status" }, "Asking for the system versions...")
   end)
   local install = C.button("Install update from file...", function()
      local file = C.choose_file("Choose an update file", "GoboRefined updates (*.update)", { "*.update" }, C.HOME .. "/Downloads")
      if not file then return end
      if not C.confirm("Install the update\n" .. file .. "?\nThis takes about a minute. You can keep working meanwhile.", "Install") then return end
      run({ "update-install", file }, "Installing " .. file .. " ...", function(ok)
         if ok then
            append("\nThe update is installed. It starts after a restart.\n")
            restart_btn.sensitive = true
            C.message("The update is installed. Restart the computer to start it.")
         else
            append("\nThe update was NOT installed (see above). Nothing was changed on the running system.\n")
         end
      end)
   end, "suggested-action")
   local rollback = C.button("Go back to the previous version...", function()
      if not C.confirm("Start the other system version (the previous one) from the next restart on?\nYour files and settings are kept.", "Go back") then return end
      run({ "update-rollback" }, "Choosing the previous version...", function(ok)
         if ok then restart_btn.sensitive = true end
      end)
   end)
   restart_btn = C.button("Restart now", function()
      if C.confirm("Restart the computer now? Save your work first.", "Restart") then
         C.spawn({ "sudo", "-n", "/System/Index/bin/shutdown", "-r", "now" })
      end
   end)
   box:pack_start(C.row(status, install), false, false, 0)
   box:pack_start(C.row(rollback, restart_btn), false, false, 0)
   box:pack_start(scroll, true, true, 0)
   if not C.is_admin() then
      box:pack_start(C.text("Installing updates and going back can only be done from an administrator's account.", "dim-label"), false, false, 0)
   end
   return outer
end

return P
