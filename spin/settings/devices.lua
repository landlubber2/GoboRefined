-- Device detection for the Device Manager (0.9.2): one library used by the Settings page
-- "Device Manager", by About and by gobo-report ("lua devices.lua --text").
--
-- On Linux "no driver" is one of four different things; this library tells them apart:
--   ok        a driver is bound to the device (and the cheap functional check agrees)
--   partial   a driver is bound, but what it should provide did not appear (no sound card, ...)
--   inactive  the running kernel has a driver for the device, but it is not active
--   firmware  the driver is active but a firmware file it asked for is missing
--   nodriver  the running kernel has no driver for this device
--   disabled  switched off (radio blocked)
--   info      nothing to judge (a bridge that needs no driver, a disk, a battery)
-- Data: gobo-devices-scan (sysfs in one pass; a ROOT argument reads a fixture tree: tests).
local D = {}

local here = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$")) or "."
D.SCAN = os.getenv("GOBO_DEVICES_SCAN") or "/System/Index/bin/gobo-devices-scan"
D.KNOWN_FILE = here .. "/known-drivers.tsv"
D.LOOKUP_FILE = here .. "/device-lookup.conf"
D.FIRMWARE_DIR = "/lib/firmware"

D.CATEGORIES = {   -- order of the tree; { id, title, icon }
   { "display", "Display adapters", "video-display" },
   { "sound", "Sound", "audio-card" },
   { "network", "Network (wired)", "network-wired" },
   { "wifi", "Wi-Fi", "network-wireless" },
   { "bluetooth", "Bluetooth", "bluetooth" },
   { "storage", "Storage controllers and disks", "drive-harddisk" },
   { "usb", "USB controllers", "drive-removable-media" },
   { "input", "Input (keyboard, mouse, touchpad)", "input-keyboard" },
   { "camera", "Cameras", "camera-web" },
   { "printer", "Printers and scanners", "printer" },
   { "power", "Battery and power", "battery" },
   { "system", "Sensors and system devices", "computer" },
   { "other", "Other / unknown", "dialog-question" },
}
D.STATE_TEXT = {
   ok = "working", partial = "driver loaded, not complete", inactive = "driver not active",
   firmware = "firmware missing", nodriver = "no driver", disabled = "switched off", info = "",
}
D.PROBLEM = { partial = true, inactive = true, firmware = true, nodriver = true }

local function read(path)
   local f = io.open(path, "r")
   if not f then return nil end
   local s = f:read("*a")
   f:close()
   return s
end
local function split(line, sep)
   local t = {}
   for field in (line .. sep):gmatch("(.-)" .. sep) do t[#t + 1] = field end
   return t
end
local function words(s)
   local t = {}
   for w in (s or ""):gmatch("%S+") do t[#t + 1] = w end
   return t
end
local function strip_id(s) return (s:gsub("%s*%[%x%x%x%x%]$", "")) end

function D.known()   -- hardware ID -> { kind, text }
   local t = {}
   for line in (read(D.KNOWN_FILE) or ""):gmatch("[^\n]+") do
      if not line:match("^#") then
         local id, kind, text = line:match("^(%S+)\t(%S+)\t(.+)$")
         if id then t[id:lower()] = { kind = kind, text = text } end
      end
   end
   return t
end

local function pci_category(class, flags)
   local cc, sub = class:sub(1, 2), class:sub(1, 4)
   if flags.wifi or sub == "0280" then return "wifi" end
   if sub == "0d11" or flags.bt then return "bluetooth" end
   if cc == "03" then return "display" end
   if cc == "04" then return "sound" end
   if cc == "02" then return "network" end
   if cc == "0d" then return "wifi" end
   if cc == "01" then return "storage" end
   if sub == "0c03" then return "usb" end
   if cc == "09" then return "input" end
   if cc == "05" or cc == "06" or cc == "07" or cc == "08" or cc == "0b" or cc == "0c"
      or cc == "10" or cc == "11" or cc == "12" then return "system" end
   return "other"
end
-- PCI classes where a missing driver is a problem (bridges and the like work without one)
local function pci_needs_driver(class)
   local cc, sub = class:sub(1, 2), class:sub(1, 4)
   return cc == "01" or cc == "02" or cc == "03" or cc == "04" or cc == "09" or cc == "0d" or sub == "0c03"
end
local function usb_category(devclass, ifs, flags)
   local has = {}
   for _, i in ipairs(ifs) do has[i.class:sub(1, 2)] = true; has[i.class] = true end
   if flags.wifi then return "wifi" end
   if flags.bt or has["e0/01/01"] then return "bluetooth" end
   if has["0e"] then return "camera" end
   if has["01"] then return "sound" end
   if has["07"] or has["06"] then return "printer" end
   if has["08"] then return "storage" end
   if has["03"] then return "input" end
   if has["02"] or has["0a"] or flags.net then return "network" end
   if devclass == "09" or has["09"] then return "usb" end
   if has["0b"] then return "system" end
   return "other"
end

local function firmware_of(lines)   -- firmware files named in kernel messages
   local list, seen = {}, {}
   for _, l in ipairs(lines) do
      local f = l:match("Direct firmware load for (%S+) failed") or l:match("firmware: failed to load (%S+)")
         or l:match("[Ff]ailed to load firmware (%S+)") or l:match("[Uu]nable to load firmware (%S+)")
         or l:match("request_firmware%S* failed for (%S+)")
      if f then
         f = f:gsub("[,;:)]+$", ""):gsub("^['\"(]", ""):gsub("['\"]$", "")
         if not seen[f] then
            seen[f] = true
            local present = false
            for _, ext in ipairs({ "", ".zst", ".xz" }) do
               local h = io.open(D.FIRMWARE_DIR .. "/" .. f .. ext, "r")
               if h then h:close(); present = true end
            end
            list[#list + 1] = { file = f, present = present }
         end
      end
   end
   return list
end
local function is_firmware_line(l)
   return l:match("[Ff]irmware") and (l:match("fail") or l:match("missing") or l:match("not found") or l:match("[Uu]nable")) and true or false
end

-- parse the scan's text into a model: { devices = {...}, kernel =, sound_cards =, problems = n }
function D.parse(text)
   local M = { devices = {}, kernel = "?", sound_cards = 0, problems = 0 }
   local pci_names, usb_names, aliases, rfkill, hci, kmsg = {}, {}, {}, {}, {}, {}
   local raw = {}
   for line in text:gmatch("[^\n]+") do
      local f = split(line, "\t")
      local kind = f[1]
      if kind == "lspci" then
         local slot, cls, ven, dev = (f[2] or ""):match('^(%S+) "([^"]*)" "([^"]*)" "([^"]*)"')
         if slot then pci_names[slot] = { class = strip_id(cls), vendor = strip_id(ven), device = strip_id(dev) } end
      elseif kind == "lsusb" then
         local id, name = (f[2] or ""):match("ID (%x%x%x%x:%x%x%x%x)%s*(.*)$")
         if id and name ~= "" then usb_names[id:lower()] = name end
      elseif kind == "alias" then aliases[f[2]] = words(f[3])
      elseif kind == "rfkill" then rfkill[#rfkill + 1] = { path = f[2] or "", type = f[3], soft = f[4] == "1", hard = f[5] == "1" }
      elseif kind == "hci" then hci[f[2]] = f[3] or ""
      elseif kind == "kmsg" then kmsg[#kmsg + 1] = f[2] or ""
      elseif kind == "kernel" then M.kernel = f[2] or "?"
      elseif kind == "sound" then M.sound_cards = tonumber(f[2]) or 0
      else raw[#raw + 1] = f end
   end
   local known = D.known()

   local function messages(dev)   -- kernel messages that mention this device
      local out = {}
      for _, l in ipairs(kmsg) do
         local hit = false
         if dev.bus == "pci" then hit = l:find(dev.addr, 1, true) ~= nil
         else hit = l:find("usb " .. dev.addr .. ":", 1, true) ~= nil or l:find(" " .. dev.addr .. ":", 1, true) ~= nil end
         if not hit then
            for name, path in pairs(hci) do
               if path:find("/" .. dev.addr .. "/", 1, true) or path:match("/" .. dev.addr:gsub("%p", "%%%0") .. "$") then
                  if l:find(name .. ":", 1, true) then hit = true end
               end
            end
         end
         if hit then out[#out + 1] = l end
      end
      return out
   end
   local function blocked(dev)
      for _, r in ipairs(rfkill) do
         if r.path:find("/" .. dev.addr .. "/", 1, true) and (r.soft or r.hard) then return r.hard and "hard" or "soft" end
      end
   end
   local function finish(dev)
      dev.messages = messages(dev)
      dev.firmware = firmware_of(dev.messages)
      dev.known = known[dev.id]
      local fw_trouble = false
      for _, l in ipairs(dev.messages) do if is_firmware_line(l) then fw_trouble = true end end
      local block = blocked(dev)
      if dev.known and dev.known.kind == "cdmode" then
         dev.state, dev.why = "inactive", "cdmode"
      elseif block then
         dev.state, dev.why = "disabled", block
      elseif dev.state == "ok" and fw_trouble then
         dev.state = "firmware"
      elseif dev.state == "ok" then
         if dev.category == "sound" and dev.bus == "pci" and not dev.flags.sound then
            dev.state, dev.why = "partial", "no sound card registered"
         elseif dev.category == "network" and dev.bus == "pci" and not dev.flags.net then
            dev.state, dev.why = "partial", "no network interface appeared"
         elseif dev.category == "wifi" and not dev.flags.net then
            dev.state, dev.why = "partial", "no Wi-Fi interface appeared"
         end
      elseif (dev.state == "inactive" or dev.state == "nodriver") and fw_trouble then
         dev.state = "firmware"
      end
      if D.PROBLEM[dev.state] then M.problems = M.problems + 1 end
      M.devices[#M.devices + 1] = dev
   end

   for _, f in ipairs(raw) do
      if f[1] == "pci" then
         local flags = {}
         for _, w in ipairs(words(f[8])) do local k, v = w:match("^(%w+)=?(.*)$"); flags[k] = v ~= "" and v or true end
         local n = pci_names[f[2]] or {}
         local dev = { bus = "pci", addr = f[2], id = (f[3] .. ":" .. f[4]):lower(), vendor = f[3]:lower(), product = f[4]:lower(),
                       class = f[5], flags = flags, modalias = f[7],
                       driver = f[6] ~= "-" and f[6] or nil, modules = aliases[f[7]] or {},
                       vendor_name = n.vendor, name = n.device, class_name = n.class,
                       where = "inside the computer (PCI " .. f[2] .. ")" }
         dev.category = pci_category(dev.class, flags)
         if not dev.name or dev.name == "" or dev.name:match("^Device$") then
            dev.name = (dev.class_name or "Device") .. " (model not in the name list)"
         end
         -- bridges and the like work without a driver (an alias match there means nothing:
         -- intel_agp names every Intel host bridge)
         if dev.driver then dev.state = "ok"
         elseif not pci_needs_driver(dev.class) then dev.state = "info"
         elseif #dev.modules > 0 then dev.state = "inactive"
         else dev.state = "nodriver" end
         finish(dev)
      elseif f[1] == "usb" then
         local flags, ifs = {}, {}
         for _, w in ipairs(words(f[9])) do local k, v = w:match("^(%w+)=?(.*)$"); flags[k] = v ~= "" and v or true end
         for _, w in ipairs(words(f[6])) do
            local class, driver, modalias = w:match("^([^=]*)=([^=]*)=(.*)$")
            if class then ifs[#ifs + 1] = { class = class, driver = driver ~= "-" and driver or nil, modalias = modalias } end
         end
         local id = (f[3] .. ":" .. f[4]):lower()
         local dev = { bus = "usb", addr = f[2], id = id, vendor = f[3]:lower(), product = f[4]:lower(), class = f[5],
                       flags = flags, interfaces = ifs, modules = {}, vendor_name = f[8] ~= "" and f[8] or nil,
                       where = (f[10] == "fixed" and "inside the computer" or "plugged in") .. " (USB port " .. f[2] .. ")" }
         dev.name = usb_names[id] or ((f[8] ~= "" and (f[8] .. " ") or "") .. (f[7] or ""))
         if dev.name:match("^%s*$") then dev.name = "USB device (no name given by the device)" end
         dev.category = usb_category(dev.class, ifs, flags)
         local bound, drivers, seen = 0, {}, {}
         for _, i in ipairs(ifs) do
            if i.driver then
               bound = bound + 1
               if not seen[i.driver] then seen[i.driver] = true; drivers[#drivers + 1] = i.driver end
            else
               for _, m in ipairs(aliases[i.modalias] or {}) do
                  if not seen["m:" .. m] then seen["m:" .. m] = true; dev.modules[#dev.modules + 1] = m end
               end
            end
         end
         dev.driver = #drivers > 0 and table.concat(drivers, ", ") or nil
         dev.unbound_interfaces = #ifs - bound
         if dev.class == "09" or bound > 0 then dev.state = "ok"
         elseif #ifs == 0 then dev.state = "info"
         elseif #dev.modules > 0 then dev.state = "inactive"
         else dev.state = "nodriver" end
         finish(dev)
      elseif f[1] == "block" then
         local gb = (tonumber(f[4]) or 0) * 512 / 1e9
         M.devices[#M.devices + 1] = { bus = "disk", addr = f[2], id = "", category = "storage", state = "info",
            name = ((f[3] or "") ~= "" and f[3] or "Disk") .. (gb >= 1 and string.format(" (%s, %.0f GB)", f[2], gb) or string.format(" (%s, %.0f MB)", f[2], gb * 1000)),
            where = f[5] == "1" and "removable" or "fixed", flags = {}, modules = {}, messages = {}, firmware = {} }
      elseif f[1] == "power" then
         local t = f[3] or ""
         local label = t == "Battery" and ("Battery " .. f[2] .. ((f[5] or "") ~= "" and (" (" .. f[5] .. " %, " .. (f[4] or "") .. ")") or ""))
            or (t == "Mains" and ("Power adapter " .. f[2]) or (t .. " " .. f[2]))
         M.devices[#M.devices + 1] = { bus = "power", addr = f[2], id = "", category = "power", state = "info", name = label,
            where = "", flags = {}, modules = {}, messages = {}, firmware = {} }
      end
   end
   return M
end

function D.scan(root)
   local cmd = D.SCAN .. (root and (" '" .. root:gsub("'", "'\\''") .. "'") or "") .. " 2>/dev/null"
   local p = io.popen(cmd, "r")
   local text = p and p:read("*a") or ""
   if p then p:close() end
   return D.parse(text), text
end

-- what the state means for this device, in plain words (one paragraph)
function D.explain(dev, M)
   local mods = table.concat(dev.modules or {}, ", ")
   if dev.state == "ok" then
      return "This device has a driver and the driver is active."
   elseif dev.state == "info" then
      if dev.bus == "pci" then return "This part of the computer works without a driver of its own." end
      return ""
   elseif dev.state == "disabled" then
      return dev.why == "hard" and "The radio is switched off by a switch or key on the computer. Switch it on there."
         or "The radio is switched off in software. An administrator can switch it on with \"Unblock\"."
   elseif dev.state == "partial" then
      return "A driver is loaded for this device, but " .. (dev.why or "it did not finish starting")
         .. ". Often a firmware file or a second driver is missing. The kernel messages below (administrators) say more; please save the report and send it to the maintainer."
   elseif dev.state == "firmware" then
      local names = {}
      for _, f in ipairs(dev.firmware or {}) do names[#names + 1] = f.file .. (f.present and " (present now)" or " (not on this system)") end
      return "The driver is there, but it asked for a firmware file that is missing"
         .. (#names > 0 and (": " .. table.concat(names, ", ")) or "")
         .. ". Firmware comes with GoboRefined updates: a newer update is the way to get it. Please save the report and send it to the maintainer."
   elseif dev.state == "inactive" then
      if dev.why == "cdmode" then return dev.known.text end
      return "This system has a driver for the device (" .. mods .. "), but it is not active. An administrator can use \"Try to start the driver\"; if that does not help, the kernel messages say why."
   elseif dev.state == "nodriver" then
      local k = dev.known and (" What is known: " .. dev.known.text) or ""
      return "The running kernel (" .. (M and M.kernel or "?") .. ") has no driver for this device. It needs a newer kernel or a separate driver, or no Linux driver exists." .. k
   end
   return ""
end

-- web lookups: URL templates in device-lookup.conf; only vendor and device ID go into the URL
function D.lookup_templates()
   local t = {}
   for line in (read(D.LOOKUP_FILE) or ""):gmatch("[^\n]+") do
      local k, v = line:match("^([%w-]+)=(%S+)$")
      if k then t[k] = v end
   end
   return t
end
function D.lookup_url(kind, bus, vendor, product)
   if not (tostring(vendor):match("^%x%x%x%x$") and tostring(product):match("^%x%x%x%x$")) then return nil end
   if bus ~= "pci" and bus ~= "usb" then return nil end
   local tpl = D.lookup_templates()[kind]
   if not tpl then return nil end
   return (tpl:gsub("{bus}", bus):gsub("{vendor}", vendor:lower()):gsub("{device}", product:lower()))
end
function D.search_url(text)   -- a typed ID ("8086:9a49") or plain words; nil when it is neither
   text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
   local v, p = text:match("^(%x%x%x%x)[: -](%x%x%x%x)$")
   if v then return D.lookup_url("hardware", "usb", v, p), D.lookup_url("hardware", "pci", v, p) end
   if #text < 2 or #text > 60 or not text:match("^[%w][%w .+_-]*$") then return nil end
   local tpl = D.lookup_templates()["search"]
   if not tpl then return nil end
   return (tpl:gsub("{words}", (text:gsub(" ", "+"):gsub("%+%+", "+"))))
end

-- the device list as text (gobo-report, "Copy details", "Save report")
function D.device_text(dev, M)
   local lines = { dev.name .. (dev.vendor_name and dev.bus == "pci" and (" — " .. dev.vendor_name) or "") }
   local function add(k, v) if v and v ~= "" then lines[#lines + 1] = "  " .. k .. ": " .. v end end
   add("State", D.STATE_TEXT[dev.state] ~= "" and D.STATE_TEXT[dev.state] or nil)
   add("Hardware ID", dev.id ~= "" and (dev.bus .. " " .. dev.id) or nil)
   add("Connected", dev.where)
   add("Driver", dev.driver)
   add("Driver available", (not dev.driver and #(dev.modules or {}) > 0) and table.concat(dev.modules, ", ") or nil)
   for _, f in ipairs(dev.firmware or {}) do add("Firmware asked for", f.file .. (f.present and " (present)" or " (MISSING)")) end
   if D.PROBLEM[dev.state] or dev.state == "disabled" then add("What this means", D.explain(dev, M)) end
   for _, l in ipairs(dev.messages or {}) do lines[#lines + 1] = "  kernel: " .. l end
   return table.concat(lines, "\n")
end
function D.report(M)
   local out = { "Devices (kernel " .. M.kernel .. "): "
      .. (M.problems == 0 and "all devices have a driver" or (M.problems .. " need attention")) }
   for pass = 1, 2 do   -- problems first
      for _, c in ipairs(D.CATEGORIES) do
         for _, dev in ipairs(M.devices) do
            if dev.category == c[1] and ((pass == 1) == (D.PROBLEM[dev.state] == true)) then
               out[#out + 1] = "[" .. c[2] .. "] " .. D.device_text(dev, M)
            end
         end
      end
   end
   return table.concat(out, "\n")
end

-- command line: lua devices.lua --text [ROOT] | --states [ROOT]
if arg and arg[0] and arg[0]:match("devices%.lua$") and (...) ~= "devices" then
   local M = D.scan(arg[2])
   if arg[1] == "--states" then
      for _, dev in ipairs(M.devices) do print(dev.bus .. " " .. dev.addr .. " " .. dev.category .. " " .. dev.state) end
      print("problems " .. M.problems)
   else
      print(D.report(M))
   end
end

return D
