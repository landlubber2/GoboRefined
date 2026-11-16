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
-- 0.8.5: "Visible to other devices" (discoverable): on while this page is shown (renewed every
-- 2.5 minutes) and for 3 minutes after "Search for devices"; BlueZ hides the computer again by
-- itself 3 minutes later (DiscoverableTimeout 180), so it is never left visible. Switching it off
-- here stops the automatic visibility until the page is opened again.
-- 0.8.5: Bluetooth audio (PulseAudio 13.0's Bluetooth modules): speakers and headphones connect
-- with "Connect"; a connected one shows whether sound plays there; BlueZ's error is said in plain words.
local P = { id = "bluetooth", title = "Bluetooth", icon = "bluetooth" }

local OFF_AT_BOOT = "/Data/Variable/lib/gobo-settings/bluetooth-off-at-boot"
local MAC = "^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$"
local VISIBLE_SECONDS = 180
local AUDIO_MODULE = "/System/Index/lib/pulse-13.0/modules/module-bluez5-device.so"

-- BlueZ's reasons ("Failed to connect: org.bluez.Error.Failed Host is down") in plain words
local REASONS = {
   { "Host is down", "the device did not answer. Is it switched on, nearby, and not connected to another phone or computer?" },
   { "Page Timeout", "the device did not answer. Is it switched on and nearby?" },
   { "Connection refused", "the device refused. Put it into pairing mode, or forget it here and pair it again." },
   { "Protocol not available", "this computer has no sound service for the device (PulseAudio's Bluetooth support is not running: log out and in again)." },
   { "profile%-unavailable", "this computer has no sound service for the device (PulseAudio's Bluetooth support is not running: log out and in again)." },
   { "Input/output error", "the connection broke off. Try again closer to the device." },
   { "Software caused connection abort", "the connection was dropped. Try again." },
   { "Connection timed out", "the device did not answer in time. Try again." },
   { "AuthenticationFailed", "pairing was refused (wrong code, or cancelled on the device)." },
   { "AuthenticationCanceled", "pairing was cancelled." },
   { "AuthenticationRejected", "the device rejected pairing." },
   { "AlreadyExists", "it is already paired." },
   { "InProgress", "it is busy (connecting or pairing already). Wait a moment." },
   { "Blocked", "Bluetooth is blocked (rfkill): use the switch again, an administrator can lift the block" },
   { "NotReady", "Bluetooth is off" },
   { "DoesNotExist", "the device is not known any more. Search for it again." },
}
local function plain(why)
   for _, r in ipairs(REASONS) do
      if why:match(r[1]) then return r[2] end
   end
   return (why:gsub("^org%.bluez%.Error%.", ""))
end

function P.build(C)
   local Gtk, GLib, Gio = C.Gtk, C.GLib, C.Gio
   local outer, box = C.page("Bluetooth", "Connect mice, keyboards, phones and other devices without a cable.")
   box:pack_start(C.text("Experimental: pairing is confirmed on one laptop; sound over Bluetooth (new in 0.8.5) is not yet tested on real hardware.", "dim-label"), false, false, 0)

   local sw = Gtk.Switch { valign = Gtk.Align.CENTER }
   local vis_sw = Gtk.Switch { valign = Gtk.Align.CENTER }
   local status = C.text("")
   local note = C.text("", "dim-label")
   local search_button, service_button
   local list = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 6 }
   local boot_check = Gtk.CheckButton { label = "Switch Bluetooth on at every start" }
   local name_label = C.text("", "dim-label")
   local others_open = false
   local setting, searching = false, false
   local refresh, schedule_refresh
   local audio_ok = C.exists(AUDIO_MODULE)
   local default_sink
   local audio_wait = 0
   -- visibility: shown = this page is on screen; hidden_by_user = switched off here this visit
   local shown, hidden_by_user, powered_now = false, false, false

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
         local reason = plain(why)
         status.label = "Could not " .. what .. ": " .. reason:gsub("%.$", "") .. "."
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

   -- discoverable for VISIBLE_SECONDS (BlueZ switches it off by itself afterwards); sending it
   -- again restarts the time
   local last_visible = 0
   local function make_visible()
      start_ctl()
      last_visible = os.time()
      send("discoverable-timeout " .. VISIBLE_SECONDS)
      send("discoverable on")
   end

   -- state from short runs ------------------------------------------------------------
   local QUERY = [[t() { timeout 6 bluetoothctl "$@" 2>/dev/null; }
t show; echo "==PULSE"; LC_ALL=C timeout 4 pactl info 2>/dev/null | grep '^Default Sink'
LC_ALL=C timeout 4 pactl list short sinks 2>/dev/null | cut -f2 | sed 's/^/SINK /'; echo "==DEVICES"
for m in $(t devices | grep -o 'Device [0-9A-F:]\{17\}' | cut -d' ' -f2 | sort -u); do echo "==DEV $m"; t info "$m"; done]]

   local function device_row(d)
      local row = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 10 }
      row:pack_start(Gtk.Image { icon_name = (d.icon ~= "" and d.icon) or "bluetooth", pixel_size = 24 }, false, false, 0)
      local label = Gtk.Box { orientation = Gtk.Orientation.VERTICAL }
      label:pack_start(C.text(d.name, "gobo-value"), false, false, 0)
      local state = d.connected and "Connected" or d.paired and "Paired, not connected" or "Not paired"
      if d.connected and d.audio and audio_ok then
         -- PulseAudio names the device's output bluez_sink.<address with _>
         if d.sink and d.sink == default_sink then state = "Connected — playing sound here"
         elseif d.sink then state = "Connected — sound output ready (choose it in Settings > Sound)"
         else state = "Connected — no sound output yet (connecting the audio part...)" end
      end
      label:pack_start(C.text(state .. "   " .. d.mac, "dim-label"), false, false, 0)
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
      local discoverable = out:match("Discoverable: yes") ~= nil
      local pulse = out:match("==PULSE(.-)==DEVICES") or ""
      default_sink = pulse:match("Default Sink: (%S+)")
      local sinks = {}
      for s in pulse:gmatch("SINK (%S+)") do sinks[s] = true end
      local devices = {}
      for piece in (out:match("==DEVICES(.*)$") or ""):gmatch("==DEV ([^=]*)") do
         local mac = piece:match("^(%S+)")
         local info = "\n" .. piece
         if mac and mac:match(MAC) then
            local name = info:match("\n%s*Alias: ([^\n]+)") or info:match("\n%s*Name: ([^\n]+)") or mac
            name = C.trim(name)
            -- 0.8.4: a device without a name has its address as alias ("39-C6-4E-7B-4D-AB")
            local nameless = not info:match("\n%s*Name: ") or name:upper():gsub("-", ":") == mac:upper()
            local icon = C.trim(info:match("Icon: ([^\n]+)") or "")
            -- an audio device: speaker/headphones (A2DP "Audio Sink", headset profiles) or its icon
            local audio = info:match("UUID: Audio Sink") ~= nil or info:match("UUID: Headset") ~= nil
               or info:match("UUID: Handsfree") ~= nil or icon:match("^audio") ~= nil
            local sink
            for s in pairs(sinks) do
               if s:match("^bluez_sink%.") and s:upper():find(mac:upper():gsub(":", "_"), 1, true) then sink = s end
            end
            table.insert(devices, { mac = mac, name = name, paired = info:match("Paired: yes") ~= nil,
               connected = info:match("Connected: yes") ~= nil, icon = icon,
               nameless = nameless, audio = audio, sink = sink })
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
      powered_now = powered and not no_ctrl
      setting = true
      vis_sw.active = discoverable and powered_now
      vis_sw.state = vis_sw.active
      setting = false
      vis_sw.sensitive = powered_now
      if powered_now and shown and not hidden_by_user and not discoverable and os.time() - last_visible > 20 then
         make_visible()
      end
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
      -- PulseAudio makes the device's output a moment after BlueZ reports "Connected": look
      -- again a few times (at most 10, every 2 s) until it is there
      local waiting = false
      for _, d in ipairs(devices) do
         if d.connected and d.audio and audio_ok and not d.sink then waiting = true end
      end
      if waiting and audio_wait < 10 then
         audio_wait = audio_wait + 1
         GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 2, function() schedule_refresh(); return false end)
      elseif not waiting then
         audio_wait = 0
      end
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
      note.label = "When a device asks for a code or a confirmation, a \"Bluetooth pairing\" window appears; pairing can also be started on the phone while this computer is visible. Paired devices are trusted and may reconnect by themselves.\n\n"
         .. (audio_ok and "Speakers and headphones: pair, then Connect; sound then plays there and returns to this computer's speakers when they disconnect (Settings > Sound chooses the output). Headset microphones work only in the old \"headset\" mode (HSP), not for calls in high quality."
             or "Headphones and speakers can be paired, but sound over Bluetooth is not available (PulseAudio's Bluetooth module is not on the system).")
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

   vis_sw.on_state_set = function(_, want)
      if setting then return false end
      start_ctl()
      if want then
         hidden_by_user = false
         make_visible()
      else
         hidden_by_user = true
         send("discoverable off")
      end
      schedule_refresh()
      return true
   end
   -- while the page is on screen: visible, renewed before BlueZ's 3 minutes run out
   outer.on_map = function()
      shown, hidden_by_user = true, false
      if powered_now then make_visible() end
      schedule_refresh()
   end
   outer.on_unmap = function() shown = false end
   GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 150, function()
      if shown and powered_now and not hidden_by_user then make_visible() end
      return true
   end)

   search_button = C.button("Search for devices", function()
      start_ctl()
      if searching then
         send("scan off"); searching = false
      else
         searching = true
         if not hidden_by_user then make_visible() end
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
   local vis_line = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 12 }
   vis_line:pack_start(vis_sw, false, false, 0)
   vis_line:pack_start(Gtk.Label { label = "Visible to other devices", xalign = 0 }, false, false, 0)
   vis_line:pack_start(C.text("(phones can find this computer; on while this page is open and for 3 minutes after a search)", "dim-label"), false, false, 0)
   box:pack_start(vis_line, false, false, 0)
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
