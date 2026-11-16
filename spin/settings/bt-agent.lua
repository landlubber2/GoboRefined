-- gobo-bt-agent (0.8.4): the Bluetooth pairing agent of the desktop session.
--
-- BlueZ asks a registered "agent" whenever pairing needs the user (confirm a 6-digit number,
-- type a PIN or passkey, allow an incoming pairing or a service). Without one, phones report
-- "incorrect PIN or passkey" and nothing appears on the computer. ~/.xinitrc starts this once per
-- desktop session (flock in the launcher); it works no matter where pairing starts: the phone,
-- Settings > Bluetooth, or the taskbar menu.
--
-- How: one long-running `bluetoothctl` (BlueZ 5.54 on the image) registers its agent with the
-- capability KeyboardDisplay when it reaches bluetoothd; we make it the default agent and turn
-- its prompts into GTK dialogs:
--   "Confirm passkey 123456 (yes/no):"   -> "Does <device> show 123456?"  Pair / Cancel
--   "Accept pairing (yes/no):"           -> "Pair with <device>?"          Pair / Cancel
--   "Authorize service UUID (yes/no):"   -> "Allow <device> to connect?"   Allow / Deny
--   "Enter PIN code:" / "Enter passkey"  -> a text field
--   "[agent] Passkey: 123456", "PIN code: 1234" (shown on this computer) -> a notice to type it
--     on the device, closed when pairing ends
-- Devices that need no questions (most speakers, headphones, mice: "just works") pair without a
-- dialog. A device that becomes paired is trusted at once, so it may reconnect by itself.
-- Without an adapter or bluetoothd nothing is shown: bluetoothctl just waits for the service.
package.path = "/System/Aliens/LuaRocks/share/lua/5.3/?.lua;/System/Aliens/LuaRocks/share/lua/5.3/?/init.lua;" .. package.path
package.cpath = "/System/Aliens/LuaRocks/lib/lua/5.3/?.so;" .. package.cpath

local lgi = require("lgi")
lgi.GLib.set_prgname("gobo-bt-agent")
lgi.GLib.set_application_name("Bluetooth")
local Gtk = lgi.require("Gtk", "3.0")
local GLib, Gio = lgi.GLib, lgi.Gio

local TEST = os.getenv("GOBO_BT_AGENT_CTL")   -- lab tests: a fake bluetoothctl (argv as one string)
local LOG = os.getenv("GOBO_BT_AGENT_LOG")    -- lab tests: answers are written here
local MAC = "%x%x:%x%x:%x%x:%x%x:%x%x:%x%x"

local function log(s)
   if not LOG then return end
   local f = io.open(LOG, "a")
   if f then f:write(s, "\n") f:close() end
end

local ctl = {}          -- proc, input
local names = {}        -- MAC -> name, from bluetoothctl's event lines
local last_mac, last_time = nil, 0
local notice            -- the "type this number on the device" dialog
local current           -- the open question dialog { dialog = , canceled = }
local queue = {}        -- prompts waiting for the open dialog

local function send(line)
   log("SEND " .. line)
   if not ctl.input then return end
   pcall(function() ctl.input:write_all(line .. "\n", nil) ctl.input:flush(nil) end)
end

local function device_name()
   if last_mac and os.time() - last_time < 60 then
      local n = names[last_mac]
      if n and n ~= "" and not n:match("^" .. MAC .. "$") and not n:match("^%x%x%-%x%x%-") then return n end
      return "the device " .. last_mac
   end
   return "a device"
end

local function close_notice()
   if notice then notice:destroy() notice = nil end
end

local function show_notice(text)
   close_notice()
   notice = Gtk.MessageDialog {
      title = "Bluetooth pairing", icon_name = "bluetooth", message_type = Gtk.MessageType.INFO, buttons = Gtk.ButtonsType.CLOSE,
      text = text, window_position = Gtk.WindowPosition.CENTER,
   }
   notice.on_response = function() close_notice() end
   notice:set_keep_above(true)
   notice:show_all()
end

local next_prompt
-- one question at a time: p = { kind, text, ok, cancel_label, entry, pattern, hint }
local function ask(p)
   local d, entry, err
   if p.entry then
      d = Gtk.Dialog { title = "Bluetooth pairing", icon_name = "bluetooth", window_position = Gtk.WindowPosition.CENTER }
      d:add_button("Cancel", Gtk.ResponseType.CANCEL)
      d:add_button(p.ok, Gtk.ResponseType.OK)
      d:set_default_response(Gtk.ResponseType.OK)
      local box = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 10, margin = 18 }
      box:pack_start(Gtk.Label { label = p.text, xalign = 0, wrap = true, max_width_chars = 50 }, false, false, 0)
      entry = Gtk.Entry { activates_default = true, width_chars = 20, max_length = 16 }
      box:pack_start(entry, false, false, 0)
      err = Gtk.Label { label = "", xalign = 0 }
      box:pack_start(err, false, false, 0)
      d:get_content_area():pack_start(box, true, true, 0)
   else
      d = Gtk.MessageDialog {
         title = "Bluetooth pairing", icon_name = "bluetooth", message_type = Gtk.MessageType.QUESTION, buttons = Gtk.ButtonsType.NONE,
         text = p.text, window_position = Gtk.WindowPosition.CENTER,
      }
      d:add_button(p.cancel_label or "Cancel", Gtk.ResponseType.CANCEL)
      d:add_button(p.ok, Gtk.ResponseType.OK)
      d:set_default_response(Gtk.ResponseType.OK)
   end
   current = { dialog = d }
   local me = current
   d.on_response = function(_, r)
      local answer
      if p.entry then
         if r == Gtk.ResponseType.OK then
            local v = entry.text
            if not v:match(p.pattern) then err.label = p.hint return end
            answer = v
         else
            answer = ""   -- an empty answer refuses (bluetoothctl replies Rejected)
         end
      else
         answer = (r == Gtk.ResponseType.OK) and "yes" or "no"
      end
      d:destroy()
      if current == me then current = nil end
      if not me.canceled then send(answer) end
      log("ANSWER " .. p.kind .. " " .. (me.canceled and "canceled" or answer))
      next_prompt()
   end
   d:set_keep_above(true)
   d:show_all()
   d:present()
end

next_prompt = function()
   if current or #queue == 0 then return end
   ask(table.remove(queue, 1))
end

local function prompt(text)
   log("PROMPT " .. text)
   local who = device_name()
   local p
   local passkey = text:match("[Cc]onfirm passkey (%d+)")
   if passkey then
      p = { kind = "confirm", text = "Pairing with " .. who .. ".\n\nDoes it show the number " .. passkey .. "?", ok = "Pair" }
   elseif text:match("[Aa]ccept pairing") then
      p = { kind = "authorize", text = "Pair with " .. who .. "?", ok = "Pair" }
   elseif text:match("[Aa]uthorize service") then
      p = { kind = "service", text = who:gsub("^%l", string.upper) .. " wants to connect to this computer. Allow it?",
            ok = "Allow", cancel_label = "Deny" }
   elseif text:match("[Ee]nter PIN code") then
      p = { kind = "pin", entry = true, ok = "Pair", pattern = "^[%w]+$", hint = "Letters and digits only, at most 16.",
            text = "Pairing with " .. who .. ".\n\nType the PIN code the device asks for (often 0000 or 1234, see its manual)." }
   elseif text:match("[Ee]nter passkey") then
      p = { kind = "passkey", entry = true, ok = "Pair", pattern = "^%d%d?%d?%d?%d?%d?$", hint = "A number, at most 6 digits.",
            text = "Pairing with " .. who .. ".\n\nType the number shown on the device." }
   elseif text:match("%(yes/no%)") then
      p = { kind = "other", text = "Bluetooth: " .. text:gsub("%s*%(yes/no%):?%s*$", "") .. "?", ok = "Yes", cancel_label = "No" }
   else
      return
   end
   table.insert(queue, p)
   next_prompt()
end

local function event(l)
   -- [NEW] Device AA:BB:..  Name   /  [CHG] Device AA:BB:.. Name: x / Alias: x / Paired: yes
   local tag, mac, rest = l:match("^%[(%u+)%] Device (" .. MAC .. ")%s*(.*)$")
   if not mac then return false end
   last_mac, last_time = mac, os.time()
   if tag == "NEW" and rest ~= "" then names[mac] = rest end
   local key, val = rest:match("^(%a+): (.*)$")
   if key == "Alias" or key == "Name" then names[mac] = val end
   if key == "Paired" and val == "yes" then
      send("trust " .. mac)   -- paired devices may reconnect by themselves
      close_notice()
   end
   if tag == "DEL" then names[mac] = nil end
   return true
end

local function line(l)
   log("LINE " .. l)
   if l == "" then return end
   if l:match("^Agent registered") then send("default-agent") return end
   if event(l) then return end
   local pk = l:match("Passkey: (%d+)")
   if pk then show_notice("Type " .. pk .. " on " .. device_name() .. " (on a keyboard: then press Enter).") return end
   local pin = l:match("PIN code: (%w+)")
   if pin then show_notice("Type the PIN code " .. pin .. " on " .. device_name() .. ".") return end
   if l:match("[Rr]equest canceled") then
      close_notice()
      queue = {}
      if current then current.canceled = true current.dialog:response(Gtk.ResponseType.CANCEL) end
   elseif l:match("Pairing successful") or l:match("Failed to pair") then
      close_notice()
   end
end

local function clean(s)
   s = s:gsub("\27%[[%d;?]*[A-Za-z]", ""):gsub("\1", ""):gsub("\2", "")
   local last = s
   for part in s:gmatch("[^\r]+") do
      if part:match("%S") then last = part end
   end
   last = last:gsub(".\b", ""):gsub("\b", "")
   last = last:gsub("^%s*%[[^%]]*%]#%s*", "")
   return (last:gsub("^%s+", ""):gsub("%s+$", ""))
end

local start
start = function()
   local launcher = Gio.SubprocessLauncher.new({ "STDIN_PIPE", "STDOUT_PIPE", "STDERR_MERGE" })
   launcher:setenv("LC_ALL", "C", true)
   local argv = TEST and { "sh", "-c", TEST } or { "bluetoothctl", "--agent", "KeyboardDisplay" }
   local proc = launcher:spawnv(argv)
   if not proc then
      GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 30, function() start() return false end)
      return
   end
   ctl.proc, ctl.input = proc, proc:get_stdin_pipe()
   local out = proc:get_stdout_pipe()
   local buf = ""
   local function more()
      out:read_bytes_async(4096, GLib.PRIORITY_DEFAULT, nil, function(s, res)
         local bytes = s:read_bytes_finish(res)
         local data = bytes and bytes.data
         if not data or #data == 0 then
            -- bluetoothctl ended (it should not): start it again a little later
            ctl.proc, ctl.input = nil, nil
            log("EXIT")
            if TEST then Gtk.main_quit() return end
            GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 5, function() start() return false end)
            return
         end
         buf = buf .. data
         while true do
            local i = buf:find("\n", 1, true)
            if not i then break end
            local l = clean(buf:sub(1, i - 1))
            buf = buf:sub(i + 1)
            line(l)
         end
         -- agent questions are prompts without a newline
         local tail = clean(buf)
         if tail:match("%(yes/no%):?%s*$") or tail:match("Enter PIN code:%s*$") or tail:match("Enter passkey.-:%s*$") then
            buf = ""
            prompt(tail:gsub("^%[agent%]%s*", ""))
         end
         more()
      end)
   end
   more()
end

start()
Gtk.main()
