-- Desktop icons (0.6): files in ~/Desktop are shown on the desktop by PCManFM's desktop
-- mode ("pcmanfm --desktop"), started here so it works the same after startx and LXDM.
--
-- PCManFM's desktop window covers the root window and draws its own background, so the
-- wallpaper Awesome draws is saved as a PNG (all screens in one picture) and given to
-- PCManFM ("screen" mode). The light/dark switch restarts Awesome: the picture, the text
-- colours and PCManFM's desktop are then renewed.
--
-- Menus: a right click on an empty spot of the desktop still opens Awesome's menu
-- (PCManFM passes it on: show_wm_menu=1); a right click on an icon opens PCManFM's file menu.
--
-- Also here: the Trash clean-up (gobo-trash-purge --auto) at login and once a day.
local awful = require("awful")
local gears = require("gears")
local beautiful = require("beautiful")

local M = {}

local home = os.getenv("HOME") or ""
local cache_dir = home .. "/.cache/gobo11"
local profile_dir = home .. "/.config/pcmanfm/default"

local function read_file(path)
   local f = io.open(path, "r")
   if not f then return nil end
   local s = f:read("*a")
   f:close()
   return s
end

local function write_file(path, text)
   local f = io.open(path, "w")
   if not f then return false end
   f:write(text)
   f:close()
   return true
end

-- the "*" group of desktop-items-N.conf for the current mode
local function desktop_group(wallpaper)
   local light = beautiful.mode == "light"
   return table.concat({
      "[*]",
      "wallpaper_mode=screen",
      "wallpaper_common=1",
      "wallpaper=" .. wallpaper,
      "desktop_bg=" .. (light and "#dfe6f2" or "#0b1630"),
      "desktop_fg=" .. (light and "#1b2230" or "#ffffff"),
      "desktop_shadow=" .. (light and "#f4f6fa" or "#000000"),
      "desktop_font=Inter 10",
      "show_wm_menu=1",
      "sort=mtime;ascending;",
      "show_documents=0",
      "show_trash=0",
      "show_mounts=0",
   }, "\n") .. "\n"
end

-- replace the "*" group in a desktop-items-N.conf, keep the icon positions PCManFM saved there;
-- returns true when the file changed
local function update_conf(path, group)
   local old = read_file(path) or ""
   local kept, skipping = {}, false
   for line in (old .. "\n"):gmatch("([^\n]*)\n") do
      if line:match("^%[") then skipping = (line == "[*]") end
      if not skipping then table.insert(kept, line) end
   end
   local rest = table.concat(kept, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
   local new = group .. (rest ~= "" and ("\n" .. rest .. "\n") or "")
   if new == old then return false end
   write_file(path, new)
   return true
end

local function save_wallpaper()
   local w, h = 0, 0   -- size of the whole root window = all screens
   for s in screen do
      w = math.max(w, s.geometry.x + s.geometry.width)
      h = math.max(h, s.geometry.y + s.geometry.height)
   end
   local name = string.format("%s/desktop-wallpaper-%s-%dx%d.png", cache_dir,
                              beautiful.mode or "dark", w, h)
   local raw = root.wallpaper()
   if not raw then return nil end
   local surf = gears.surface(raw)
   os.execute("mkdir -p '" .. cache_dir .. "'")
   -- write to a new file, then rename: PCManFM never reads half a picture
   local tmp = name .. ".tmp.png"
   surf:write_to_png(tmp)
   os.rename(tmp, name)
   return name
end

-- Awesome 4.3 does not publish _NET_WORKAREA; PCManFM's desktop reads it to keep icons out
-- of the taskbar. One rectangle (EWMH: per virtual desktop, over the whole root window):
-- full width, down to the highest taskbar top. Repeated for up to 16 desktops.
local function publish_workarea()
   local w, bottom = 0, nil
   for s in screen do
      w = math.max(w, s.geometry.x + s.geometry.width)
      local b = s.workarea.y + s.workarea.height
      bottom = bottom and math.min(bottom, b) or b
   end
   if not bottom or w == 0 then return end
   local top = 0
   for s in screen do top = math.max(top, s.workarea.y - s.geometry.y) end
   local one = string.format("0, %d, %d, %d", top, w, bottom - top)
   local vals = {}
   for _ = 1, 16 do table.insert(vals, one) end
   -- (the spin's PCManFM reads the property itself and follows its changes; GTK 3 would
   -- ignore it, as Awesome does not list it in _NET_SUPPORTED)
   awful.spawn({ "xprop", "-root", "-f", "_NET_WORKAREA", "32c", "-set", "_NET_WORKAREA",
                 table.concat(vals, ", ") }, false)
end

-- a right click on an empty spot of the desktop runs this (spin's PCManFM patch): Awesome's menu
local menu_env = "GOBO_DESKTOP_MENU_COMMAND=awesome-client 'spin_desktop_menu()'"

local function start_or_reload(changed)
   awful.spawn.easy_async_with_shell("pgrep -u \"$(id -u)\" -f '^pcmanfm --desktop' > /dev/null && echo yes",
      function(out)
         if not out:match("yes") then
            awful.spawn({ "env", menu_env, "pcmanfm", "--desktop", "--profile", "default" }, false)
         elseif changed then
            -- the running desktop re-reads its settings when it is switched off and on (when it
            -- has no file manager window open, the process ends and a new one starts: same
            -- environment needed)
            awful.spawn.with_shell("pcmanfm --desktop-off; sleep 1; env \"" .. menu_env ..
                                   "\" pcmanfm --desktop --profile default")
         end
      end)
end

local tidy

local function refresh()
   publish_workarea()
   local wp = save_wallpaper()
   if not wp then return end
   tidy(wp)
   os.execute("mkdir -p '" .. profile_dir .. "'")
   local group, changed = desktop_group(wp), false
   for i = 0, math.max(screen.count(), 1) - 1 do
      if update_conf(string.format("%s/desktop-items-%d.conf", profile_dir, i), group) then
         changed = true
      end
   end
   start_or_reload(changed)
end

-- pictures of an older mode or screen size are not needed any more
tidy = function(keep)
   local p = io.popen("ls '" .. cache_dir .. "' 2> /dev/null")
   local list = p and p:read("*a") or ""
   if p then p:close() end
   for f in list:gmatch("[^\n]+") do
      if f:match("^desktop%-wallpaper%-.*%.png$") and cache_dir .. "/" .. f ~= keep then
         os.remove(cache_dir .. "/" .. f)
      end
   end
end

-- args.menu: function opening the desktop menu (called for a right click on an empty spot)
function M.start(args)
   args = args or {}
   -- global, called by PCManFM's desktop through awesome-client
   spin_desktop_menu = function()
      if args.menu then args.menu() end
   end
   -- the wallpaper is drawn on a delayed call: save it a moment later
   gears.timer.start_new(1.5, function()
      refresh()
      return false
   end)
   -- screens added, removed or resized: new picture, new settings
   local pending
   screen.connect_signal("list", function()
      if pending then return end
      pending = gears.timer.start_new(3, function() pending = nil refresh() return false end)
   end)
   screen.connect_signal("property::workarea", function()
      gears.timer.delayed_call(publish_workarea)
   end)
   screen.connect_signal("property::geometry", function()
      if pending then return end
      pending = gears.timer.start_new(3, function() pending = nil refresh() return false end)
   end)

   -- Trash: delete items older than the chosen age (gobo-trash-purge), now and once a day
   local function purge() awful.spawn({ "gobo-trash-purge", "--auto" }, false) end
   gears.timer.start_new(20, function() purge() return false end)
   gears.timer({ timeout = 24 * 3600, autostart = true, callback = purge })
end

return M
