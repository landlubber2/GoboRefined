-- Updates: the running version, both system versions (gobo-update --status), the free space of the
-- disk, install an update file, go back to the previous version, restart. All through
-- gobo-settings-helper. 0.10: one btrfs pool holds both versions and the user's files, so the free
-- space shown is the pool's (shared), not a fixed slot's.
local P = { id = "updates", title = "Updates", icon = "system-software-update" }

function P.build(C)
   local outer, box = C.page("Updates")
   local version = C.trim(C.read("/Programs/GoboSpin/Current/share/spin-version") or "?"):match("^[^\n]*")
   box:pack_start(C.text("This computer runs GoboRefined " .. version .. " (based on GoboLinux 017.01).", "gobo-value"), false, false, 0)
   box:pack_start(C.text("GoboRefined keeps two versions of the system (A and B). An update becomes the version that is not running; the computer starts it after the next restart. If it does not start, the computer goes back to the other version by itself. Files that did not change are shared by both versions, so the second version takes little space.", "dim-label"), false, false, 0)
   local avail = C.pread("df -h --output=avail /System/Data"):match("\n%s*(%S+)")
   if avail then
      box:pack_start(C.text("Free on the disk: about " .. avail .. " (shared by the system versions and your files)", "dim-label"), false, false, 0)
   end

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
