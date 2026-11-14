-- USB sticks and other removable drives (spin 0.5).
-- devmon (from udevil, started in ~/.xinitrc) mounts them under /Mount/Media/<label>.
-- This module watches /proc/mounts and
--   * shows a notification when a drive appears (click it to open the file manager
--     there; its only button, "Safely remove", unmounts it),
--   * shows a taskbar icon while any drive is mounted; clicking it lists the drives
--     with "Open" and "Safely remove" entries.
-- Unmounting uses `udevil umount`, which works for normal users without polkit.

local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local naughty = require("naughty")

local usb = {}

local MEDIA = "/Mount/Media/"

-- /proc/mounts escapes spaces and a few other characters as \ooo
local function unescape(s)
   return (s:gsub("\\(%d%d%d)", function(o) return string.char(tonumber(o, 8)) end))
end

local function current_mounts()
   local list = {}
   local fd = io.open("/proc/mounts", "r")
   if not fd then return list end
   for line in fd:lines() do
      local dev, dir = line:match("^(%S+) (%S+) ")
      if dir then
         dir = unescape(dir)
         if dir:sub(1, #MEDIA) == MEDIA and #dir > #MEDIA then
            table.insert(list, { dev = unescape(dev), dir = dir, label = dir:sub(#MEDIA + 1) })
         end
      end
   end
   fd:close()
   table.sort(list, function(a, b) return a.dir < b.dir end)
   return list
end

-- args: icon (path), file_manager (command name)
function usb.new(args)
   local icon = args.icon
   local file_manager = args.file_manager or "pcmanfm"
   local widget = wibox.widget.imagebox(icon)
   widget.visible = false
   local known = nil   -- mount points seen at the last check (nil before the first one)
   local menu
   local refresh

   local function open(m)
      awful.spawn({ file_manager, m.dir })
   end

   local function remove(m)
      awful.spawn.easy_async({ "udevil", "umount", m.dir }, function(_, err, _, code)
         if code == 0 then
            naughty.notify({ title = "Safe to remove", text = m.label .. " can now be unplugged.", icon = icon })
         else
            naughty.notify({ title = "Could not remove " .. m.label,
               text = "It is still in use. Close the files and windows that use it, then try again.\n"
                  .. (err or ""):gsub("%s+$", ""),
               icon = icon, timeout = 10 })
         end
         refresh()
      end)
   end

   refresh = function()
      local list = current_mounts()
      widget.visible = #list > 0
      local now = {}
      for _, m in ipairs(list) do
         now[m.dir] = true
         if known and not known[m.dir] then
            naughty.notify({
               title = "USB drive connected",
               text = m.label .. " is ready. Click to open it.",
               icon = icon, timeout = 15,
               run = function(n) open(m) naughty.destroy(n) end,
               -- One button only (0.6): Awesome 4.3 lays out notification actions in
               -- random order (pairs()), and a click meant for "Open" once hit
               -- "Safely remove". Clicking the notification itself opens the drive.
               actions = {
                  ["Safely remove"] = function() remove(m) end,
               },
            })
         end
      end
      known = now
   end

   local function show_menu()
      if menu and menu.wibox.visible then menu:hide() menu = nil return end
      local items = {}
      for _, m in ipairs(current_mounts()) do
         table.insert(items, { "Open " .. m.label, function() open(m) end })
         table.insert(items, { "Safely remove " .. m.label, function() remove(m) end })
      end
      if #items == 0 then return end
      menu = awful.menu({ items = items, theme = { width = 260 } })
      menu:show()
   end

   widget:buttons(gears.table.join(
      awful.button({}, 1, show_menu),
      awful.button({}, 3, show_menu)))
   awful.tooltip({ objects = { widget }, text = "USB drives: open or safely remove" })

   gears.timer({ timeout = 2, autostart = true, call_now = true, callback = refresh })
   return widget
end

return usb
