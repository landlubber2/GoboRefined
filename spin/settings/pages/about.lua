-- About: versions and hardware facts; "Save system report" runs gobo-report (the same command
-- works in a terminal when the mouse does not).
local P = { id = "about", title = "About", icon = "help-about" }

local function graphics(C)
   local lspci = C.pread("lspci -k")
   local card, kdriver = lspci:match("VGA compatible controller: ([^\n]+)\n.-Kernel driver in use: ([^\n]+)")
   card = card or lspci:match("VGA compatible controller: ([^\n]+)")
   local xlog = C.read(C.HOME .. "/.local/share/xorg/Xorg.0.log") or C.read("/Data/Variable/log/Xorg.0.log") or ""
   local xdriver = xlog:match("%(II%) (%a[%w_]*)%(0%): ")
   local parts = {}
   if card then table.insert(parts, card) end
   if kdriver then table.insert(parts, "kernel driver " .. kdriver) end
   if xdriver then table.insert(parts, "X driver " .. xdriver) end
   return #parts > 0 and table.concat(parts, ", ") or "unknown"
end

function P.build(C)
   local Gtk = C.Gtk
   local outer, box = C.page("About this computer")
   local version = C.trim(C.read("/Programs/GoboSpin/Current/share/spin-version") or "?"):match("^[^\n]*")
   local mem = tonumber((C.read("/proc/meminfo") or ""):match("MemTotal:%s+(%d+)")) or 0
   local size, used, avail = C.pread("df -h /System/Data"):match("\n%S+%s+(%S+)%s+(%S+)%s+(%S+)")
   local facts = {
      { "System", "GoboRefined " .. version .. ", based on GoboLinux 017.01" },
      { "Computer name", C.trim(C.read("/proc/sys/kernel/hostname") or "") },
      { "Kernel", C.trim(C.pread("uname -r")) },
      { "Processor", C.trim(((C.read("/proc/cpuinfo") or ""):match("model name%s*:%s*([^\n]+)")) or "?")
                     .. " (" .. C.trim(C.pread("nproc")) .. " threads)" },
      { "Memory", string.format("%.1f GB", mem / 1024 / 1024) },
      { "Data partition (your files, settings, added programs)", size and string.format("%s used of %s, %s free", used, size, avail) or "?" },
      { "Graphics", graphics(C) },
   }
   local grid = Gtk.Grid { row_spacing = 8, column_spacing = 18 }
   for i, f in ipairs(facts) do
      grid:attach(Gtk.Label { label = f[1], xalign = 1, valign = Gtk.Align.START, wrap = true, max_width_chars = 24 }, 0, i - 1, 1, 1)
      grid:attach(C.text(f[2], "gobo-value"), 1, i - 1, 1, 1)
   end
   box:pack_start(grid, false, false, 0)

   -- 0.9.2: one line from the Device Manager's detection, and the way there
   do
      local ok, D = pcall(require, "devices")
      if ok and C.kind() ~= "simple" then
         local M = D.scan()
         box:pack_start(C.heading("Devices and drivers"), false, false, 0)
         box:pack_start(C.text(M.problems == 0 and "All devices have a driver." or (M.problems .. (M.problems == 1 and " device needs" or " devices need") .. " attention."), M.problems == 0 and "dim-label" or "gobo-value"), false, false, 0)
         box:pack_start(C.button("Open Device Manager", function() C.spawn({ "gobo-settings", "devices" }) end), false, false, 0)
      end
   end
   box:pack_start(C.heading("When something does not work"), false, false, 0)
   box:pack_start(C.text("A system report collects what helps to find the cause (devices, network, the latest system messages, logs) in one text file in your home folder. Without a mouse: open a terminal (Win+Enter) and type  gobo-report", "dim-label"), false, false, 0)
   local btn
   btn = C.button("Save system report", function()
      btn.sensitive = false
      btn.label = "Writing the report..."
      C.run({ "gobo-report" }, nil, function(_, out)
         btn.sensitive = true
         btn.label = "Save system report"
         local path = out:match("written to (%S+)")
         if path then C.message("The system report was saved as\n" .. path)
         else C.error("The report could not be written:\n" .. out) end
      end)
   end, "suggested-action")
   box:pack_start(btn, false, false, 0)
   return outer
end

return P
