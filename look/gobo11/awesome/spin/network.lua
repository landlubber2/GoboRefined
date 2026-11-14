-- Network status icon for the taskbar (0.6). Replaces the picture of GoboNet's widget,
-- whose recoloured icons all looked like "full signal", while keeping its menu:
-- a click opens GoboNet's list of networks (gobo.awesome.gobonet, kept running hidden).
--
-- States: disconnected (no address / no link), connecting (GoboNet or dhcpcd at work),
-- wired, Wi-Fi with 4 signal levels. Checked every 4 seconds and right after a click.
-- Icons are drawn with cairo in the theme's text colour, like the other status icons.
local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local beautiful = require("beautiful")
local cairo = require("lgi").cairo
local Gio = require("lgi").Gio

local network = {}

local SIZE = 48

local function color(cr, hex, alpha)
   local r, g, b, a = gears.color.parse_color(hex)
   cr:set_source_rgba(r, g, b, alpha or a)
end

local function read(path)
   local f = io.open(path, "r")
   if not f then return nil end
   local s = f:read("*a")
   f:close()
   return s
end

local function pread(cmd)
   local p = io.popen(cmd .. " 2>/dev/null", "r")
   if not p then return "" end
   local s = p:read("*a")
   p:close()
   return s or ""
end

-- Icons ---------------------------------------------------------------------------

local cache = {}
-- kind: "wifi" (level 0-4), "wired", "off", "connecting" (frame 0-3)
function network.icon(kind, level)
   local key = kind .. (level or "")
   if cache[key] then return cache[key] end
   local fg = beautiful.fg_normal
   local img = cairo.ImageSurface("ARGB32", SIZE, SIZE)
   local cr = cairo.Context(img)
   cr:set_line_cap(cairo.LineCap.ROUND)
   cr:set_line_join(cairo.LineJoin.ROUND)

   -- Wi-Fi fan: a dot (part 0) and three arcs (parts 1-3) around the point (24, 36);
   -- lit(part) says whether a part is drawn solid or faded
   local function fan(lit, dim_alpha)
      local a1, a2 = -math.pi * 0.75, -math.pi * 0.25
      color(cr, fg, lit(0) and 1 or dim_alpha)
      cr:arc(24, 36, 3.2, 0, 2 * math.pi)
      cr:fill()
      cr:set_line_width(3.4)
      for i = 1, 3 do
         color(cr, fg, lit(i) and 1 or dim_alpha)
         cr:arc(24, 36, 5 + i * 7, a1, a2)
         cr:stroke()
      end
   end
   local function cross()   -- a red cross at the lower right
      cr:set_line_width(3.2)
      color(cr, "#e5484d")
      cr:move_to(31, 29); cr:line_to(41, 39)
      cr:move_to(41, 29); cr:line_to(31, 39)
      cr:stroke()
   end
   local function plug(alpha)   -- network plug: three small boxes joined by lines
      color(cr, fg, alpha)
      cr:set_line_width(3)
      gears.shape.transform(gears.shape.rounded_rect):translate(17, 7)(cr, 14, 11, 2)
      cr:stroke()
      gears.shape.transform(gears.shape.rounded_rect):translate(6, 30)(cr, 14, 11, 2)
      cr:stroke()
      gears.shape.transform(gears.shape.rounded_rect):translate(28, 30)(cr, 14, 11, 2)
      cr:stroke()
      cr:move_to(24, 18); cr:line_to(24, 24)
      cr:move_to(13, 30); cr:line_to(13, 24); cr:line_to(35, 24); cr:line_to(35, 30)
      cr:stroke()
   end

   if kind == "wifi" then
      -- level 0 = dot only, 4 = everything
      local lit_parts = math.max(1, level or 4)
      fan(function(part) return part < lit_parts end, 0.25)
   elseif kind == "connecting" then
      -- one part at a time travels outwards (never all solid, unlike a full signal)
      fan(function(part) return part == (level or 0) end, 0.22)
   elseif kind == "off" then
      fan(function() return false end, 0.35)
      cross()
   elseif kind == "off_wired" then   -- no Wi-Fi adapter at all: the plug, crossed out
      plug(0.4)
      cross()
   elseif kind == "wired" then
      plug(1)
   end
   cache[key] = img
   return img
end

-- State ---------------------------------------------------------------------------

local function list_dir(path)
   local out = {}
   local dir = Gio.File.new_for_path(path)
   local ok, enum = pcall(dir.enumerate_children, dir, "standard::name", Gio.FileQueryInfoFlags.NONE)
   if not ok or not enum then return out end
   while true do
      local info = enum:next_file()
      if not info then break end
      table.insert(out, info:get_name())
   end
   enum:close()
   table.sort(out)
   return out
end

local function is_wireless(ifname)
   local base = "/sys/class/net/" .. ifname
   if Gio.File.new_for_path(base .. "/wireless"):query_exists()
      or Gio.File.new_for_path(base .. "/phy80211"):query_exists() then
      return true
   end
   return ((read(base .. "/uevent") or ""):match("DEVTYPE=wlan")) ~= nil
end

-- Signal level 0..4 from /proc/net/wireless (or iwconfig). Pure function of the text, so it
-- can be checked with sample values: network.level_from(wireless_text, ifname, iwconfig_text)
function network.level_from(proc, ifname, iwconfig)
   local quality, dbm
   for line in (proc or ""):gmatch("[^\n]+") do
      local name, q, l = line:match("^%s*([%w%._-]+):%s+%x+%s+([%-%d%.]+)%s+([%-%d%.]+)")
      if name == ifname then
         quality, dbm = tonumber(q), tonumber(l)
         break
      end
   end
   if (not dbm or dbm == 0) and iwconfig then
      dbm = tonumber(iwconfig:match("Signal level[=:]%s*(%-%d+)%s*dBm") or "")
      local cur, max = iwconfig:match("Link Quality[=:]%s*(%d+)/(%d+)")
      if cur then quality = 70 * tonumber(cur) / tonumber(max) end
   end
   -- level in dBm when the driver gives one (negative), else link quality out of 70
   if dbm and dbm < 0 then
      if dbm >= -55 then return 4
      elseif dbm >= -65 then return 3
      elseif dbm >= -75 then return 2
      elseif dbm >= -85 then return 1
      else return 0 end
   elseif dbm and dbm > 0 and dbm <= 100 and not quality then
      quality = 0.7 * dbm
   end
   if quality then
      local pct = math.max(0, math.min(100, quality / 70 * 100))
      if pct >= 80 then return 4 elseif pct >= 55 then return 3
      elseif pct >= 30 then return 2 elseif pct > 5 then return 1 else return 0 end
   end
   return nil
end

local function ipv4(ifname)
   return pread("ip -4 -o addr show dev " .. ifname):match("inet (%d+%.%d+%.%d+%.%d+)")
end

local function process_running(pattern)
   return pread("pgrep -f '" .. pattern .. "'") ~= ""
end

-- GoboNet writes this while it connects
local function gobonet_connecting()
   local pid = read((os.getenv("HOME") or "") .. "/.cache/GoboNet/wifi/.connecting.pid")
   pid = pid and pid:match("%d+")
   return pid ~= nil and Gio.File.new_for_path("/proc/" .. pid):query_exists()
end

-- Returns { kind = "wifi"|"wired"|"connecting"|"off", level = 0-4, ifname, ip, essid }
function network.state()
   local default_dev = pread("ip route show default"):match("dev (%S+)")
   local wired, wireless = {}, {}
   for _, ifname in ipairs(list_dir("/sys/class/net")) do
      if ifname ~= "lo" and not ifname:match("^veth") and not ifname:match("^docker") then
         if is_wireless(ifname) then table.insert(wireless, ifname) else table.insert(wired, ifname) end
      end
   end
   local function up(ifname)
      return (read("/sys/class/net/" .. ifname .. "/carrier") or ""):match("1") ~= nil
   end
   local function wifi_state(ifname, ip)
      local iw = pread("iwconfig " .. ifname)
      local level = network.level_from(read("/proc/net/wireless"), ifname, iw) or 0
      return { kind = "wifi", level = level, ifname = ifname, ip = ip, essid = iw:match('ESSID:"([^"]*)"') }
   end
   -- the interface with the default route wins, then any with an address
   local order = {}
   if default_dev then table.insert(order, default_dev) end
   for _, i in ipairs(wired) do table.insert(order, i) end
   for _, i in ipairs(wireless) do table.insert(order, i) end
   for _, ifname in ipairs(order) do
      local ip = up(ifname) and ipv4(ifname)
      if ip then
         if is_wireless(ifname) then return wifi_state(ifname, ip) end
         return { kind = "wired", ifname = ifname, ip = ip }
      end
   end
   -- nothing connected: connecting if GoboNet, wpa_supplicant or dhcpcd is at work on a link
   if gobonet_connecting() then return { kind = "connecting" } end
   for _, ifname in ipairs(order) do
      if up(ifname) and process_running("dhcpcd.*" .. ifname) then
         return { kind = "connecting", ifname = ifname }
      end
   end
   return { kind = "off", wireless = #wireless > 0 }
end

local function describe(st)
   if st.kind == "wifi" then
      return string.format("Wi-Fi%s: connected (%s), signal %d of 4\n%s",
         st.essid and st.essid ~= "" and (" " .. st.essid) or "", st.ifname, st.level, st.ip or "")
   elseif st.kind == "wired" then
      return string.format("Wired network (%s): connected\n%s", st.ifname, st.ip or "")
   elseif st.kind == "connecting" then
      return "Connecting..."
   end
   return "Not connected" .. (st.wireless and "\nClick to pick a Wi-Fi network" or "\nNo network cable, no Wi-Fi adapter found")
end

-- Widget --------------------------------------------------------------------------

-- args.menu_widget: GoboNet's widget (gobonet.new()); its click handler opens the list
function network.new(args)
   args = args or {}
   local widget = wibox.widget.imagebox()
   local tip = awful.tooltip({ objects = { widget } })
   local frame = 0
   local last

   function widget:refresh()
      local ok, st = pcall(network.state)
      if not ok then st = { kind = "off" } end
      if st.kind == "connecting" then
         frame = (frame + 1) % 4
         widget:set_image(network.icon("connecting", frame))
      elseif st.kind == "off" and not st.wireless then
         widget:set_image(network.icon("off_wired"))
      else
         widget:set_image(network.icon(st.kind, st.level))
      end
      tip.text = describe(st)
      last = st
      return st
   end
   function widget:get_state() return last end

   local function open_menu(button)
      local m = args.menu_widget
      if m then
         -- GoboNet's widget reacts to its own button press signal
         m:emit_signal("button::press", 0, 0, button, {}, {})
         m:emit_signal("button::release", 0, 0, button, {}, {})
      else
         awful.spawn({ "urxvt", "-e", "sh", "-c", "gobonet list; read x" })
      end
      gears.timer.delayed_call(function() widget:refresh() end)
   end
   widget:buttons(gears.table.join(
      awful.button({}, 1, function() open_menu(1) end),
      awful.button({}, 3, function() open_menu(3) end)))

   widget:refresh()
   local fast   -- while connecting, animate faster
   gears.timer({ timeout = 4, autostart = true, callback = function()
      local st = widget:refresh()
      if st.kind == "connecting" and not fast then
         fast = gears.timer({ timeout = 0.5, autostart = true, callback = function()
            if widget:refresh().kind ~= "connecting" then fast:stop(); fast = nil end
         end })
      end
   end })
   return widget
end

return network
