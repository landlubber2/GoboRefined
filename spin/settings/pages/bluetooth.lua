-- Bluetooth (0.8.2, experimental). BlueZ 5.54 is part of 017.01: bluetoothd starts at boot (stock
-- task "Bluetooth Start", which also powers the adapter on) and the D-Bus policy lets every user
-- talk to it, so this page drives `bluetoothctl` as the user:
--   * one long-running bluetoothctl (stdin/stdout pipes) runs the commands (power, scan, pair,
--     trust, connect, disconnect, remove); its event lines ([NEW]/[CHG]/[DEL]) trigger a refresh.
--     0.8.4: it runs WITHOUT an agent; the session's pairing agent (gobo-bt-agent, started by
--     ~/.xinitrc) shows every pairing question, wherever pairing was started;
--   * the list itself comes from short runs (bluetoothctl show / devices / info MAC).
-- Root (gobo-settings-helper, administrators): bluetooth-service start|stop (start also lifts an
-- rfkill soft block), bluetooth-boot on|off (stay off after a restart).
-- Bluetooth audio is not on the image (PulseAudio 13 has no module-bluetooth here).
local P = { id = "bluetooth", title = "Bluetooth", icon = "bluetooth" }

local OFF_AT_BOOT = "/Data/Variable/lib/gobo-settings/bluetooth-off-at-boot"
local MAC = "^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$"

function P.build(C)
   local Gtk, GLib, Gio = C.Gtk, C.GLib, C.Gio
   local outer, box = C.page("Bluetooth", "Connect mice, keyboards, phones and other devices without a cable.")
   box:pack_start(C.text("Experimental: not yet tested on real hardware.", "dim-label"), false, false, 0)

   local sw = Gtk.Switch { valign = Gtk.Align.CENTER }
   local status = C.text("")
   local note = C.text("", "dim-label")
   local search_button, service_button
   local list = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 6 }
   local boot_check = Gtk.CheckButton { label = "Switch Bluetooth on at every start" }
   local name_label = C.text("", "dim-label")
   local others_open = false
   local setting, searching = false, false
   local refresh, schedule_refresh

   local function adapter_present()
      return C.pread("ls -1 /sys/class/bluetooth 2>/dev/null"):match("hci%d") ~= nil
   end
   local function daemon_running() return C.trim(C.pread("pgrep -x bluetoothd")) ~= "" end
   local function rfkill_blocked()
      for name in C.pread("ls -1 /sys/class/rfkill"):gmatch("[^\n]+") do
         local base = "/sys/class/rfkill/" .. name
         if C.trim(C.read(base .. "/type") or "") == "bluetooth" and C.trim(C.read(base .. "/soft") or "0") == "1" then
            return true
         end
      end
      return false
   end

   -- the long-running bluetoothctl -------------------------------------------------------
   local ctl = {}
   local function clean(s)
      s = s:gsub("\27%[[%d;?]*[A-Za-z]", ""):gsub("\1", ""):gsub("\2", "")
      local last = s
      for part in s:gmatch("[^\r]+") do
         if part:match("%S") then last = part end
      end
      last = last:gsub(".\b", ""):gsub("\b", "")
      last = last:gsub("^%s*%[[^%]]*%]#%s*", "")
      return C.trim(last)
   end
   local function send(cmd)
      if not ctl.input then return false end
      local ok = pcall(function() ctl.input:write_all(cmd .. "\n", nil) ctl.input:flush(nil) end)
      return ok
   end
   local function handle_line(l)
      if l == "" then return end
      -- 0.8.4: this bluetoothctl runs without an agent (--agent off: "Failed to register agent");
      -- the session's gobo-bt-agent answers every pairing question
      if l:match("register agent") or l:match("^Agent ") then return end
      if l:match("^%[NEW%]") or l:match("^%[CHG%]") or l:match("^%[DEL%]") then
         if l:match("Discovering: no") then searching = false end
         schedule_refresh()
         return
      end
      local pk = l:match("Passkey: (%d+)")
      if pk then status.label = "Type " .. pk .. " on the device (keyboard: then press Enter)." return end
      local what, why = l:match("^Failed to (.-): (.*)$")
      if what then
         local reason = why:gsub("^org%.bluez%.Error%.", "")
         if reason == "Blocked" then reason = "Bluetooth is blocked (rfkill): use the switch again, an administrator can lift the block" end
         if reason == "NotReady" then reason = "Bluetooth is off" end
         status.label = "Could not " .. what .. ": " .. reason .. "."
         if what:match("discovery") then searching = false end
         schedule_refresh()
      elseif l:match("Pairing successful") then status.label = "Paired." schedule_refresh()
      elseif l:match("Connection successful") then status.label = "Connected." schedule_refresh()
      elseif l:match("Successful disconnected") then status.label = "Disconnected." schedule_refresh()
      elseif l:match("Device has been removed") then status.label = "Forgotten." schedule_refresh()
      elseif l:match("No default controller available") then schedule_refresh()
      end
   end
   local function start_ctl()
      if ctl.proc then return end
      local launcher = Gio.SubprocessLauncher.new({ "STDIN_PIPE", "STDOUT_PIPE", "STDERR_MERGE" })
      launcher:setenv("LC_ALL", "C", true)
      local proc = launcher:spawnv({ "bluetoothctl", "--agent", "off" })
      if not proc then return end
      ctl.proc, ctl.input = proc, proc:get_stdin_pipe()
      local out = proc:get_stdout_pipe()
      local buf = ""
      local function more()
         out:read_bytes_async(4096, GLib.PRIORITY_DEFAULT, nil, function(s, res)
            local bytes = s:read_bytes_finish(res)
            local data = bytes and bytes.data
            if not data or #data == 0 then
               ctl.proc, ctl.input = nil, nil
               return
            end
            buf = buf .. data
            while true do
               local i = buf:find("\n", 1, true)
               if not i then break end
               local line = clean(buf:sub(1, i - 1))
               buf = buf:sub(i + 1)
               handle_line(line)
            end
            more()
         end)
      end
      more()
   end

   -- state from short runs ------------------------------------------------------------
   local QUERY = [[t() { timeout 6 bluetoothctl "$@" 2>/dev/null; }
t show; echo "==DEVICES"
for m in $(t devices | grep -o 'Device [0-9A-F:]\{17\}' | cut -d' ' -f2 | sort -u); do echo "==DEV $m"; t info "$m"; done]]

   local function device_row(d)
      local row = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 10 }
      row:pack_start(Gtk.Image { icon_name = (d.icon ~= "" and d.icon) or "bluetooth", pixel_size = 24 }, false, false, 0)
      local label = Gtk.Box { orientation = Gtk.Orientation.VERTICAL }
      label:pack_start(C.text(d.name, "gobo-value"), false, false, 0)
      label:pack_start(C.text((d.connected and "Connected" or d.paired and "Paired, not connected" or "Not paired") .. "   " .. d.mac, "dim-label"), false, false, 0)
      row:pack_start(label, true, true, 0)
      local function act(text, cmds)
         return C.button(text, function()
            if not d.mac:match(MAC) then return end
            start_ctl()
            status.label = text .. ": " .. d.name .. "..."
            for _, c in ipairs(cmds) do send(c .. " " .. d.mac) end
         end)
      end
      if not d.paired then
         row:pack_start(act("Pair", { "pair" }), false, false, 0)
      elseif d.connected then
         row:pack_start(act("Disconnect", { "disconnect" }), false, false, 0)
      else
         row:pack_start(act("Connect", { "trust", "connect" }), false, false, 0)
      end
      if d.paired then
         row:pack_start(C.button("Forget", function()
            if d.mac:match(MAC) and C.confirm("Forget " .. d.name .. "? You will have to pair it again to use it.", "Forget") then
               start_ctl(); send("remove " .. d.mac)
            end
         end), false, false, 0)
      end
      return row
   end

   local function show_state(out)
      local powered = out:match("Powered: yes") ~= nil
      local no_ctrl = out:match("No default controller") ~= nil or not out:match("Controller %x%x:")
      local devices = {}
      for piece in (out:match("==DEVICES(.*)$") or ""):gmatch("==DEV ([^=]*)") do
         local mac = piece:match("^(%S+)")
         local info = "\n" .. piece
         if mac and mac:match(MAC) then
            local name = info:match("\n%s*Alias: ([^\n]+)") or info:match("\n%s*Name: ([^\n]+)") or mac
            name = C.trim(name)
            -- 0.8.4: a device without a name has its address as alias ("39-C6-4E-7B-4D-AB")
            local nameless = not info:match("\n%s*Name: ") or name:upper():gsub("-", ":") == mac:upper()
            table.insert(devices, { mac = mac, name = name, paired = info:match("Paired: yes") ~= nil,
               connected = info:match("Connected: yes") ~= nil, icon = C.trim(info:match("Icon: ([^\n]+)") or ""),
               nameless = nameless })
         end
      end
      table.sort(devices, function(a, b)
         if a.paired ~= b.paired then return a.paired end
         if a.nameless ~= b.nameless then return b.nameless end
         return a.name:lower() < b.name:lower()
      end)
      local alias = out:match("\n%s*Alias: ([^\n]+)")
      setting = true
      sw.active = powered and not no_ctrl
      sw.state = sw.active
      setting = false
      sw.sensitive = true
      search_button.sensitive = powered
      search_button.label = searching and "Stop searching" or "Search for devices"
      C.clear(list)
      if no_ctrl then
         status.label = "The Bluetooth service does not see the adapter yet."
      elseif not powered then
         if not status.label:match("^Could not") then status.label = "Bluetooth is off." end
      elseif status.label == "" or status.label:match("^Bluetooth is") or status.label:match("^Checking") then
         status.label = searching and "Searching... (devices must be in pairing mode)" or "Bluetooth is on."
      end
      if alias and not no_ctrl then
         name_label.label = "Other devices see this computer as \"" .. C.trim(alias) .. "\"."
      else
         name_label.label = ""
      end
      if powered then
         -- named and paired devices first; unpaired devices without a name (mostly nearby
         -- phones and beacons that only show an address) in a closed "Other devices" section
         local others = {}
         for _, d in ipairs(devices) do
            if d.nameless and not d.paired then table.insert(others, d)
            else list:pack_start(device_row(d), false, false, 0) end
         end
         if #devices == #others then
            list:pack_start(C.text(searching and "No devices with a name found yet." or "No devices yet: press \"Search for devices\" and put the device into pairing mode.", "dim-label"), false, false, 0)
         end
         if #others > 0 then
            local inner = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 6, margin_top = 6 }
            for _, d in ipairs(others) do inner:pack_start(device_row(d), false, false, 0) end
            local exp = Gtk.Expander { label = "Other devices without a name (" .. #others .. ")", expanded = others_open }
            exp.on_activate = function(e) others_open = not e.expanded end
            exp:add(inner)
            list:pack_start(exp, false, false, 0)
         end
      end
      list:show_all()
   end

   local refreshing, again = false, false
   refresh = function()
      if refreshing then again = true return end
      boot_check.active = not C.exists(OFF_AT_BOOT)
      if not adapter_present() then
         C.clear(list)
         sw.sensitive, search_button.sensitive = false, false
         setting = true; sw.active = false; sw.state = false; setting = false
         status.label = "No Bluetooth adapter found."
         note.label = "If this computer has Bluetooth, it may be switched off with a key or in the firmware (BIOS) settings. A USB Bluetooth stick is noticed when it is plugged in."
         service_button.visible = false
         return
      end
      if not daemon_running() then
         sw.sensitive, search_button.sensitive = false, false
         status.label = "The Bluetooth service (bluetoothd) is not running."
         service_button.visible = true
         C.clear(list)
         return
      end
      service_button.visible = false
      note.label = "When a device asks for a code or a confirmation, a \"Bluetooth pairing\" window appears; pairing can also be started on the phone. Paired devices are trusted and may reconnect by themselves.\n\nHeadphones and speakers can be paired, but sound over Bluetooth is not available yet (PulseAudio's Bluetooth module is not on the system)."
      start_ctl()
      refreshing = true
      C.run({ "sh", "-c", QUERY }, "", function(_, out)
         refreshing = false
         show_state(out or "")
         if again then again = false; refresh() end
      end)
   end
   local pending = false
   schedule_refresh = function()
      if pending then return end
      pending = true
      GLib.timeout_add(GLib.PRIORITY_DEFAULT, 500, function() pending = false; refresh(); return false end)
   end

   sw.on_state_set = function(_, want)
      if setting then return false end
      if want and rfkill_blocked() then
         status.label = "Lifting the block (administrator password)..."
         C.helper({ "bluetooth-service", "start" }, nil, function(ok, out)
            if not ok then C.error(C.clean_error(out)) refresh() return end
            start_ctl(); send("power on"); schedule_refresh()
         end)
      else
         start_ctl()
         if not want and searching then send("scan off"); searching = false end
         send(want and "power on" or "power off")
         schedule_refresh()
      end
      return true
   end

   search_button = C.button("Search for devices", function()
      start_ctl()
      if searching then
         send("scan off"); searching = false
      else
         searching = true
         status.label = "Searching... (devices must be in pairing mode)"
         send("scan on")
         GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 40, function()
            if searching then send("scan off"); searching = false; schedule_refresh() end
            return false
         end)
      end
      schedule_refresh()
   end, "suggested-action")
   service_button = C.button("Start the Bluetooth service", function()
      C.helper({ "bluetooth-service", "start" }, nil, function(ok, out)
         if not ok then C.error(C.clean_error(out)) end
         schedule_refresh()
      end)
   end)
   boot_check.on_toggled = function()
      local want = boot_check.active
      if want == (not C.exists(OFF_AT_BOOT)) then return end
      C.helper({ "bluetooth-boot", want and "on" or "off" }, nil, function(ok, out)
         if not ok then C.error(C.clean_error(out)) end
         boot_check.active = not C.exists(OFF_AT_BOOT)
      end)
   end

   local line = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 12 }
   line:pack_start(sw, false, false, 0)
   line:pack_start(Gtk.Label { label = "Bluetooth", xalign = 0 }, false, false, 0)
   box:pack_start(line, false, false, 0)
   box:pack_start(status, false, false, 0)
   box:pack_start(name_label, false, false, 0)
   box:pack_start(C.row(search_button, service_button, C.button("Refresh", function() refresh() end)), false, false, 0)
   box:pack_start(C.heading("Devices"), false, false, 0)
   box:pack_start(list, false, false, 0)
   box:pack_start(boot_check, false, false, 0)
   box:pack_start(note, false, false, 0)
   status.label = "Checking..."
   service_button.no_show_all = true   -- refresh() decides (main.lua calls show_all)
   refresh()

   -- a USB Bluetooth stick plugged in or out, the service started or stopped
   local had = tostring(adapter_present()) .. tostring(daemon_running())
   GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 3, function()
      local has = tostring(adapter_present()) .. tostring(daemon_running())
      if has ~= had then had = has; refresh() end
      return true
   end)
   return outer
end

return P
