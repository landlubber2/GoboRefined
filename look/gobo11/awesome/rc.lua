--
-- Standard awesome library
local gears = require("gears")
local awful = require("awful")
awful.rules = require("awful.rules")
require("awful.autofocus")
-- Widget and layout library
local wibox = require("wibox")
-- Notification library
local naughty = require("naughty")
local menubar = require("menubar")
local GLib = require("lgi").GLib

local gobonet = require("spin.gobonet_menu")   -- 0.8.1: patched copy of GoboNet's menu
local docking = require("gobo.awesome.docking")
-- The spin's own modules (in ~/.config/awesome/spin/)
local popups = require("spin.popups")   -- first: it filters every keyboard grab (Win+Escape)
spin_popups = popups                     -- (the lab's input test checks for it)
local status = require("spin.status")
local alttab = require("spin.alttab")
local launcher = require("spin.launcher")
local power = require("spin.power")
local usb = require("spin.usb")
local network = require("spin.network")
local wifi_switch = require("spin.wifi_switch")
local desktops = require("spin.desktops")
local screenshot = require("spin.screenshot")
local cliphist = require("spin.cliphist")
local desktop_icons = require("spin.desktop_icons")   -- 0.6: ~/Desktop icons (PCManFM), Trash clean-up
local bluetooth = require("gobo.awesome.bluetooth")
local window_menu = require("gobo.awesome.window_menu")
local menu_gen = require("menubar.menu_gen")
local icon_theme = require("menubar.icon_theme")
local hotkeys_popup = require("awful.hotkeys_popup.widget")

-- C API
local screen = screen
local mouse = mouse
local client = client
local awesome = awesome
local root = root

local terminal = "urxvt"
local editor = os.getenv("EDITOR") or "nano"
local editor_cmd = terminal .. " -e " .. editor
local browser = "firefox"

-- Programs added by the spin (stage 3). The sound control falls back to ncpamixer in a
-- terminal on a system without PaVuControl.
local function have(cmd)
   local ok = os.execute("command -v " .. cmd .. " > /dev/null 2>&1")
   return ok == true or ok == 0
end
local file_manager = "pcmanfm"
local mixer = have("pavucontrol") and "pavucontrol"
   or (terminal .. " -title ncpamixer -geometry 90x18 -e ncpamixer")
local displays_tool = "lxrandr"

local titlebars_enabled = true
local sloppy_focus = false

-- Theme handling library
local beautiful = require("beautiful")
beautiful.init(gears.filesystem.get_configuration_dir() .. "themes/gobo11/theme.lua")

local light_widget = status.brightness()
local sound_widget = status.volume(mixer)

awful.titlebar.enable_tooltip = false
hotkeys_popup.group_margin = 20

-- Variable definitions
-- Themes define colors, icons, font and wallpapers.

local ALT = "Mod1"

-- Default modkey.
-- Usually, Mod4 is the key with a logo between Control and Alt.
-- If you do not like this or do not have such a key,
-- I suggest you to remap Mod4 to another key using xmodmap or other tools.
-- However, you can use another modifier like Mod1, but it may interact with others.
local modkey = "Mod4"

-- Check if awesome encountered an error during startup and fell back to
-- another config (This code will only ever execute for the fallback config)
if awesome.startup_errors then
   naughty.notify({ preset = naughty.config.presets.critical,
                    title = "Oops, there were errors during startup!",
                    text = awesome.startup_errors })
end


-- Handle runtime errors after startup
do
   local in_error = false
   awesome.connect_signal("debug::error", function(err)
      -- Make sure we don't go into an endless error loop
      if in_error then return end
      in_error = true
      naughty.notify({ preset = naughty.config.presets.critical,
                       title = "Oops, an error happened!",
                       text = err })
      in_error = false
   end)
end

-- Table of layouts to cover with awful.layout.inc, order matters.
local layouts = {
   awful.layout.suit.floating,
   awful.layout.suit.tile,
   awful.layout.suit.tile.left,
   awful.layout.suit.tile.bottom,
   awful.layout.suit.tile.top,
   awful.layout.suit.fair,
   awful.layout.suit.fair.horizontal,
   awful.layout.suit.spiral,
   awful.layout.suit.spiral.dwindle,
   awful.layout.suit.max,
   awful.layout.suit.max.fullscreen,
   awful.layout.suit.magnifier
}

-- Wallpaper (drawn by the theme at each screen's size)
local function set_wallpaper(s)
   gears.wallpaper.maximized(beautiful.wallpaper(s), s, true)
end
awful.screen.connect_for_each_screen(set_wallpaper)
screen.connect_signal("property::geometry", set_wallpaper)


-- Tags = virtual desktops (0.6): one per screen to start with (also screens plugged in
-- later), more from the Win+Shift+Tab list; the count survives an Awesome restart.
awful.screen.connect_for_each_screen(function(s)
   desktops.setup_screen(s, layouts[1])
end)

-- Hotkeys help: closes on any key, and (0.6) on a click anywhere, like the other popups.
local function hotkeys_visible()
   local w = hotkeys_popup.default_widget
   local list = {}
   for _, per_screen in pairs(w and w._cached_wiboxes or {}) do
      for _, hw in pairs(per_screen) do
         if hw.wibox.visible then table.insert(list, hw) end
      end
   end
   return list
end
local hotkeys_backdrop
local function hide_help()
   for _, hw in ipairs(hotkeys_visible()) do hw:hide() end
   if hotkeys_backdrop then hotkeys_backdrop.visible = false end
end
popups.register("hotkeys", hide_help)
local function show_help()
   popups.close_all("hotkeys")
   hotkeys_backdrop = hotkeys_backdrop or popups.backdrop(hide_help)
   hotkeys_backdrop.show_on(awful.screen.focused())
   hotkeys_popup.show_help()
   for _, hw in ipairs(hotkeys_visible()) do
      if not hw.spin_wrapped then   -- a key or a click on the popup hides it: drop the backdrop too
         hw.spin_wrapped = true
         local hide = hw.hide
         hw.hide = function(self)
            hide(self)
            if hotkeys_backdrop then hotkeys_backdrop.visible = false end
         end
      end
   end
end

local function layout_fn(mode) return function() awful.layout.set(mode) end end

local function regenerate_wallpaper()
   for s in screen do
      set_wallpaper(s)
   end
end

-- Menu
-- Create a laucher widget and a main menu
local myawesomemenu = {
   { "Window control mode", {
      { "Floating windows", layout_fn(awful.layout.suit.floating), beautiful.layout_floating },
      { "Tiled", layout_fn(awful.layout.suit.tile), beautiful.layout_tile },
      { "Tiled left", layout_fn(awful.layout.suit.tile.left), beautiful.layout_tileleft },
      { "Tiled bottom", layout_fn(awful.layout.suit.tile.bottom), beautiful.layout_tilebottom },
      { "Tiled top", layout_fn(awful.layout.suit.tile.top), beautiful.layout_tiletop },
      { "Fair vertical", layout_fn(awful.layout.suit.fair), beautiful.layout_fairv },
      { "Fair horizontal", layout_fn(awful.layout.suit.fair.horizontal), beautiful.layout_fairh },
      { "Spiral", layout_fn(awful.layout.suit.spiral), beautiful.layout_spiral },
      { "Dwindle", layout_fn(awful.layout.suit.spiral.dwindle), beautiful.layout_dwindle },
      { "All windows maximized", layout_fn(awful.layout.suit.max), beautiful.layout_max },
      { "Full screen", layout_fn(awful.layout.suit.max.fullscreen), beautiful.layout_fullscreen },
      { "Magnifier", layout_fn(awful.layout.suit.magnifier), beautiful.layout_magnifier }}},
   { "Hotkeys", function() return false, show_help end},
   { "Manual", terminal .. " -e pinfo awesome" },
   { "Edit Config", editor_cmd .. " " .. awesome.conffile },
   { "Displays...", displays_tool },
   { "Detect Displays", function() awful.spawn.with_shell("sh ~/.config/awesome/displays.sh --auto") end },
   { "Restart Awesome", awesome.restart },
   { "Quit", function() awesome.quit() end }
}

-- Menus: rounded corners, and rows with padded, evenly sized icons
-- (the stock rows stretch each icon to the full row height).
do
   local new_menu = awful.menu.new
   awful.menu.new = function(...)
      local m = new_menu(...)
      if m and m.wibox and beautiful.menu_shape then
         m.wibox.shape = beautiful.menu_shape
      end
      -- one popup at a time; a click outside closes the menu (it holds the keyboard)
      return m and popups.manage_menu(m)
   end

   local ICON, PAD = 20, 12
   awful.menu.entry = function(parent, args)
      args = args or {}
      args.text = args[1] or args.text or ""
      args.cmd = args[2] or args.cmd
      args.icon = args[3] or args.icon

      local label = wibox.widget.textbox()
      label:set_font(parent.theme.font)
      label:set_text(args.text)

      local iconbox
      if args.icon then
         iconbox = wibox.widget.imagebox()
         iconbox.forced_width, iconbox.forced_height = ICON, ICON
         if not iconbox:set_image(gears.surface.load_silently(args.icon)) then iconbox = nil end
      end

      local left = wibox.layout.fixed.horizontal()
      local slot = wibox.container.place(iconbox)   -- an empty slot keeps labels aligned
      slot.forced_width = ICON
      left:add(wibox.container.margin(slot, PAD, PAD, 0, 0))
      left:add(label)

      local submenu
      if type(args.cmd) == "table" then
         submenu = wibox.widget.imagebox()
         submenu.forced_width, submenu.forced_height = 14, 14
         submenu:set_image(parent.theme.submenu_icon)
      end

      local layout = wibox.layout.align.horizontal()
      layout:set_left(left)
      if submenu then
         layout:set_right(wibox.container.margin(wibox.container.place(submenu), 0, PAD, 0, 0))
      end

      return {
         label = label, sep = submenu, icon = iconbox, widget = layout,
         cmd = args.cmd, theme = args.theme, akey = "",
      }
   end
end

local mymainmenu = awful.menu({
   items = awful.util.table.join({
      { "Search applications...", function() launcher.show() end, beautiful.search_icon },
      { "Terminal", terminal, menubar.utils.lookup_icon("utilities-terminal") or beautiful.default_app_icon },
   }),
   theme = { width = beautiful.menu_width, height = beautiful.menu_height },
})

menu_gen.generate(function(entries)
   local cat_keys = {}
   local cat_submenus = {}

   for k, _ in pairs(menu_gen.all_categories) do
      table.insert(cat_keys, k)
      cat_submenus[k] = {}
   end

   for _, entry in ipairs(entries) do
      if entry.category ~= nil and entry.name ~= nil and entry.cmdline ~= nil then
         -- entries whose icon is not found keep their place, with the generic icon
         table.insert(cat_submenus[entry.category], { entry.name, entry.cmdline, entry.icon or beautiful.default_app_icon })
      end
   end
   table.sort(cat_keys)
   for _, k in ipairs(cat_keys) do
      if #cat_submenus[k] > 0 then
         local cat = menu_gen.all_categories[k]
         mymainmenu:add({ cat.name, cat_submenus[k], icon_theme():find_icon_path(cat.icon_name) })
      end
   end
   mymainmenu:add({ "Desktop", myawesomemenu, beautiful.desktop_icon })
   mymainmenu:add({ "Power...", function() power.show() end, beautiful.power_icon })
end)


-- Menubar configuration
menubar.utils.terminal = terminal -- Set the terminal for applications that require it

-- Taskbar: launcher, pinned apps and running windows centred at the bottom;
-- status icons and the clock on the right.

-- A widget on a rounded background that lights up under the mouse.
local function hoverable(widget, margin)
   local bg = wibox.container.background(wibox.container.margin(widget, margin, margin, margin, margin))
   bg.shape = beautiful.button_shape
   bg:connect_signal("mouse::enter", function() bg.bg = beautiful.hover_bg end)
   bg:connect_signal("mouse::leave", function() bg.bg = nil end)
   return bg
end

local function find_icon(...)
   for _, name in ipairs({ ... }) do
      local path = menubar.utils.lookup_icon(name)
      if path then return path end
   end
   return beautiful.default_app_icon
end

local function pinned(icon, command, tip)
   local w = hoverable(wibox.widget.imagebox(icon), 8)
   w:buttons(awful.button({}, 1, function() awful.spawn(command) end))
   awful.tooltip({ objects = { w }, text = tip })
   return w
end

local start_button = hoverable(wibox.widget.imagebox(beautiful.start_icon), 4)
launcher.setup({ on_power = power.show })
popups.register("alttab", function() alttab.cancel() end)
start_button:buttons(awful.util.table.join(
   awful.button({}, 1, function() mymainmenu:toggle() end),   -- left click: the category menu
   awful.button({}, 3, function() launcher.toggle() end)      -- right click: search
))

local mytextclock = wibox.widget.textclock("%H:%M\n%d.%m.%Y", 5)
mytextclock.align = "right"
mytextclock.font = beautiful.font_small

local function status_icon(widget)
   return wibox.container.margin(widget, 4, 4, 14, 14)
end

local mywibox = {}
-- Taskbar widgets by name, for the lab's input tests (vm/input-test.lua finds them on screen).
spin_debug = { start = start_button, bars = mywibox, launcher_power_xy = launcher.power_xy }
local mytaglist = {}
mytaglist.buttons = awful.util.table.join(
   awful.button({}, 1, awful.tag.viewonly),
   awful.button({ modkey }, 1, awful.client.movetotag),
   awful.button({}, 3, awful.tag.viewtoggle),
   awful.button({ modkey }, 3, awful.client.toggletag)
)
local mytasklist = {}
local clients_menu
mytasklist.buttons = awful.util.table.join(
   awful.button({}, 1, function(c)
      if clients_menu then
         clients_menu:hide()
         clients_menu = nil
      end
      if c == client.focus then
         c.minimized = true
      else
         c.minimized = false
         if not c:isvisible() then
            awful.tag.viewonly(c:tags()[1])
         end
         client.focus = c
         c:raise()
      end
   end),
   awful.button({}, 2, function(c) c:kill() end),
   awful.button({}, 3, function()
      if clients_menu and clients_menu.wibox.visible then
         clients_menu:hide()
         clients_menu = nil
      else
         clients_menu = awful.menu.clients({ theme = { width = 280, height = 30 } })
      end
   end)
)

-- One taskbar button: the window's icon, with a short accent line under it
-- (longer for the focused window).
-- Windows without an icon of their own (urxvt, xterm, ...) get one from the
-- icon theme by window class, so they do not all show the generic icon.
local class_icon_alias = { urxvt = "utilities-terminal", xterm = "utilities-terminal", zenity = "gnome-info" }
local class_icons = {}
local function client_icon(c)
   if c.icon then return c.icon end
   local class = (c.class or ""):lower()
   if class_icons[class] == nil then
      local names = {}
      for _, n in ipairs({ class_icon_alias[class] or "", class, (c.instance or ""):lower() }) do
         if n ~= "" then table.insert(names, n) end
      end
      class_icons[class] = find_icon((table.unpack or unpack)(names))
   end
   return class_icons[class]
end

desktops.icon_for = client_icon   -- the desktops list shows the same icons as the taskbar

local function update_task(self, c)
   self:get_children_by_id("icon")[1].image = client_icon(c)
   local line = self:get_children_by_id("line")[1]
   line.forced_width = (c == client.focus) and 16 or 6
   line.color = c.minimized and "#00000000" or (c == client.focus and beautiful.accent or beautiful.fg_normal .. "80")
end

local task_template = {
   {
      {
         { id = "icon", widget = wibox.widget.imagebox },
         left = 8, right = 8, top = 6, bottom = 8,
         widget = wibox.container.margin,
      },
      {
         {
            id = "line", forced_height = 3, forced_width = 6,
            orientation = "horizontal", thickness = 3, span_ratio = 1,
            widget = wibox.widget.separator,
         },
         valign = "bottom", halign = "center",
         widget = wibox.container.place,
      },
      layout = wibox.layout.stack,
   },
   id = "background_role",
   widget = wibox.container.background,
   create_callback = update_task,
   update_callback = update_task,
}

awful.screen.connect_for_each_screen(function(s)
   mytaglist[s] = awful.widget.taglist(s, awful.widget.taglist.filter.all, mytaglist.buttons)

   mytasklist[s] = awful.widget.tasklist({
      screen = s,
      filter = awful.widget.tasklist.filter.currenttags,
      buttons = mytasklist.buttons,
      layout = { spacing = 4, layout = wibox.layout.fixed.horizontal },
      widget_template = task_template,
   })

   mywibox[s] = awful.wibar({
      position = "bottom", screen = s, ontop = true, -- stays above windows; fullscreen still covers it
      height = beautiful.bar_height, bg = beautiful.bar_bg,
   })

   local center_layout = wibox.layout.fixed.horizontal()
   center_layout.spacing = 4
   center_layout:add(start_button)
   center_layout:add(pinned(find_icon("utilities-terminal", "terminal"), terminal, "Terminal"))
   center_layout:add(pinned(find_icon("system-file-manager", "folder"), file_manager, "Files"))
   center_layout:add(pinned(find_icon("firefox"), browser, "Firefox"))
   center_layout:add(mytasklist[s])

   local right_layout = wibox.layout.fixed.horizontal()
   if s == screen.primary then
      right_layout:add(status_icon(wibox.widget.systray()))
      right_layout:add(status_icon(bluetooth.new()))
      spin_debug.usb = usb.new({ icon = icon_theme():find_icon_path("drive-removable-media-usb", 48) or find_icon("drive-removable-media"), file_manager = file_manager })
      right_layout:add(status_icon(spin_debug.usb))
      -- our own icon (real state, drawn in the theme); GoboNet's widget runs hidden for its menu
      spin_debug.net = network.new({ menu_widget = gobonet.new() })
      right_layout:add(status_icon(spin_debug.net))
      right_layout:add(status_icon(status.battery()))
      right_layout:add(status_icon(light_widget))
      right_layout:add(status_icon(sound_widget))
   end
   right_layout:add(wibox.container.margin(mytextclock, 8, 12, 0, 0))

   local layout = wibox.layout.align.horizontal()
   layout.expand = "none"
   -- desktop numbers on the left, only while the screen has more than one desktop
   local tag_area = wibox.container.margin(mytaglist[s], 10, 0, 12, 12)
   tag_area.visible = #s.tags > 1
   desktops.on_change(function(changed_s)
      if changed_s == s then tag_area.visible = #s.tags > 1 end
   end)
   spin_debug.tag_area = spin_debug.tag_area or {}
   spin_debug.tag_area[s] = tag_area
   layout:set_left(tag_area)
   layout:set_middle(wibox.container.margin(center_layout, 0, 0, 4, 4))
   layout:set_right(right_layout)

   mywibox[s]:set_widget(layout)
end)


-- Realtek USB Wi-Fi adapters that start as a "driver CD": switch them from the session too,
-- in case udev's rule did not (spin/wifi_switch.lua, /var/log/gobo-wifi-switch.log).
wifi_switch.start({ icon = find_icon("network-wireless", "network-wireless-symbolic") })

-- Files in ~/Desktop on the desktop (PCManFM --desktop, spin/desktop_icons.lua); Trash clean-up
desktop_icons.start({ menu = function() mymainmenu:toggle() end })   -- same as a root right click

-- 0.8: "System updated" / "System update undone" notice after a system update (spin/updates.lua)
require("spin.updates").start()

-- 0.8.1: after the light/dark switch (spin/power.lua) show the desktop that was shown before
do
   local path = (os.getenv("HOME") or "") .. "/.cache/awesome-restart-desktop"
   local f = io.open(path, "r")
   if f then
      local i = tonumber(f:read("*l") or "")
      f:close()
      os.remove(path)
      local t = i and screen.primary.tags[i]
      if t then gears.timer.delayed_call(function() t:view_only() end) end
   end
end

-- Mouse bindings
root.buttons(awful.util.table.join(
   awful.button({}, 1, function() popups.close_all() end),
   awful.button({}, 3, function() mymainmenu:toggle() end)
   --awful.button({}, 4, awful.tag.viewnext),
   --awful.button({}, 5, awful.tag.viewprev)
))


-- 0.8.1: the screenshot keys also work while a menu or popup holds the keyboard
-- (spin/popups.lua closes it first)
popups.pass({}, "Print", function() screenshot.take("screen") end)
popups.pass({ modkey, "Shift" }, "s", function() screenshot.show() end)

-- Key bindings
local globalkeys = awful.util.table.join(

   -- Screenshots (0.6): saved to ~/Pictures/Screenshots and copied to the clipboard
   awful.key({}, "Print",
      function() screenshot.take("screen") end,
      { description = "Screenshot of the whole screen", group = "screenshots and clipboard" }),

   awful.key({ modkey, "Shift" }, "s",
      function() screenshot.show() end,
      { description = "Screenshot: area, window or screen", group = "screenshots and clipboard" }),

   -- Clipboard history (0.6)
   awful.key({ modkey, "Shift" }, "v",
      function() cliphist.show() end,
      { description = "Clipboard history: pick an earlier copy", group = "screenshots and clipboard" }),

   awful.key({ modkey }, "s",
      show_help,
      { description = "Show hotkeys", group = "awesome" }),

   -- Virtual desktops (0.6)
   awful.key({ modkey, "Shift" }, "Tab",
      function() desktops.show() end,
      { description = "Desktops: list, switch, add, remove", group = "desktops" }),

   awful.key({ modkey }, ",",
      awful.tag.viewprev,
      { description = "Previous desktop", group = "desktops" }),

   awful.key({ modkey }, ".",
      awful.tag.viewnext,
      { description = "Next desktop", group = "desktops" }),

   -- Safety net (0.6): closes every popup and menu, releases keyboard and mouse grabs and
   -- focuses the window under the pointer. Also works inside a grab (spin/popups.lua).
   awful.key({ modkey }, "Escape",
      function() popups.panic() end,
      { description = "Close all popups, free the keyboard", group = "awesome" }),

   awful.key({ modkey }, "j",
      function()
         awful.client.focus.byidx(-1)
         if client.focus then client.focus:raise() end
      end,
      { description = "Focus previous by index", group = "client" }),

   awful.key({ modkey }, "k",
      function()
         awful.client.focus.byidx(1)
         if client.focus then client.focus:raise() end
      end,
      { description = "Focus next by index", group = "client" }),

   awful.key({ modkey }, "w",
      function()
         mymainmenu:show()
      end,
      { description = "Show main menu", group = "awesome" }),

   -- Layout manipulation
   awful.key({ modkey, "Shift" }, "j",
      function()
         awful.client.swap.byidx(1) 
      end,
      { description = "Swap with next client by index", group = "client" }),

   awful.key({ modkey, "Shift" }, "k",
      function()
         awful.client.swap.byidx(-1)
      end,
      { description = "Swap with previous client by index", group = "client" }),
   
   awful.key({ modkey, "Control" }, "j",
      function()
         awful.screen.focus_relative(1)
      end,
      { description = "Focus the next screen", group = "screen" }),
   
   awful.key({ modkey, "Control" }, "k",
      function() 
         awful.screen.focus_relative(-1)
      end,
      { description = "Focus the previous screen", group = "screen" }),
   
   awful.key({ modkey }, "u",
      awful.client.urgent.jumpto,
      { description = "Jump to urgent client", group = "client" }),

   awful.key({ modkey }, "Tab",
      function()
         awful.client.focus.history.previous()
         if client.focus then
            client.focus:raise()
         end
      end,
      { description = "Go back to previous client", group = "client" }),

   -- Lock and power
   awful.key({ modkey }, "l",
      function() power.lock() end,
      { description = "Lock the screen", group = "awesome" }),

   awful.key({ "Control", ALT }, "Delete",
      function() power.show() end,
      { description = "Power menu", group = "awesome" }),

   -- Standard program
   awful.key({ modkey }, "Return",
      function()
         awful.spawn(terminal)
      end,
      { description = "Open a terminal", group = "launcher" }),

   awful.key({ modkey }, "e",
      function()
         awful.spawn(file_manager)
      end,
      { description = "Open the file manager", group = "launcher" }),

   awful.key({ modkey, "Shift" }, "Return",
      function()
         awful.util.spawn(browser)
      end,
      { description = "Open a browser", group = "launcher" }),

   awful.key({ modkey, "Control" }, "r",
      awesome.restart,
      { description = "Reload Awesome", group = "awesome" }),

   awful.key({ modkey, "Shift" }, "q",
      awesome.quit,
      { description = "Quit Awesome", group = "awesome" }),

   awful.key({ modkey }, "bracketright",
      function()
         awful.tag.incmwfact(0.05)
      end,
      { description = "Increase master width factor", group = "layout" }),

   awful.key({ modkey }, "bracketleft",
      function()
         awful.tag.incmwfact(-0.05)
      end,
      { description = "Decrease master width factor", group = "layout" }),

   awful.key({ modkey, "Shift" }, "h",
      function()
         awful.tag.incnmaster( 1, nil, true)
      end,
      { description = "Increase the number of master clients", group = "layout" }),

   awful.key({ modkey, "Shift" }, "l",
      function()
         awful.tag.incnmaster(-1, nil, true)
      end,
      { description = "Decrease the number of master clients", group = "layout" }),

   awful.key({ modkey, "Control" }, "h",
      function()
         awful.tag.incncol( 1, nil, true)
      end,
      { description = "Increase the number of columns", group = "layout" }),

   awful.key({ modkey, "Control" }, "l",
      function()
         awful.tag.incncol(-1, nil, true)
      end,
      { description = "Decrease the number of columns", group = "layout" }),

   awful.key({ modkey }, "space",
      function()
         awful.layout.inc(layouts, 1)
      end,
      { description = "Select next", group = "layout" }),

   awful.key({ modkey, "Shift" }, "space",
      function()
         awful.layout.inc(layouts, -1)
      end,
      { description = "Select previous", group = "layout" }),

   awful.key({ modkey, "Control" }, "n",
      function()
         local c = awful.client.restore()
         -- Focus restored client
         if c then
            client.focus = c
            c:raise()
         end
      end,
      { description = "Restore minimized", group = "client" }),

   -- Prompt
   awful.key({ modkey }, "r",
      function()
         launcher.show()
      end,
      { description = "Search and start applications", group = "launcher" }),

   awful.key({ ALT }, "F2",
      function()
         launcher.show()
      end,
      { description = "Search and start applications", group = "launcher" }),

   --[[
   awful.key({ modkey }, "x",
      function()
         awful.prompt.run({ prompt = "Run Lua code: " },
         mypromptbox[mouse.screen].widget,
         awful.util.eval, nil,
         awful.util.getdir("cache") .. "/history_eval")
      end
      { description = "Run Lua code", group = "awesome" }),
   ]]

   -- Menubar
   awful.key({ modkey }, "p",
      function() launcher.show() end,
      { description = "Search and start applications", group = "launcher" }),

   -- Switch windows
   awful.key({ ALT, }, "Tab",
      function()
         alttab.switch(1, "Alt_L", "Tab", "ISO_Left_Tab")
      end,
      { description = "Switch between windows", group = "awesome gobolinux" }),
   
   awful.key({ ALT, "Shift" }, "Tab",
      function()
         alttab.switch(-1, "Alt_L", "Tab", "ISO_Left_Tab")
      end,
      { description = "Switch between windows backwards", group = "awesome gobolinux" }),

   -- Multimedia keys    
   awful.key({}, "XF86HomePage",
      function()
         awful.util.spawn(browser)
      end,
      { description = "Open a browser", group = "multimedia" }),
   
   awful.key({}, "XF86AudioRaiseVolume",
      function()
         sound_widget:set_volume(5, "+")
      end,
      { description = "Raise audio volume", group = "multimedia" }),
   
   awful.key({}, "XF86AudioLowerVolume",
      function()
         sound_widget:set_volume(5, "-") 
      end,
      { description = "Lower audio volume", group = "multimedia" }),
   
   awful.key({}, "XF86AudioMute",
      function() 
         sound_widget:toggle_mute() 
      end,
      { description = "Toggle mute", group = "multimedia" }),
   
   awful.key({}, "XF86MonBrightnessDown", function() light_widget:dec_brightness(5) end,
      { description = "Lower screen brightness", group = "multimedia" }
   ),
   
   awful.key({}, "XF86MonBrightnessUp", function() light_widget:inc_brightness(5) end,
      { description = "Raise screen brightness", group = "multimedia" }
   )
)

local delta = 64

local clientkeys = awful.util.table.join(

   awful.key({ modkey }, "f",
      function(c)
         c.fullscreen = not c.fullscreen
      end,
      { description = "Toggle fullscreen", group = "client" }),
   
   awful.key({ modkey, "Shift" }, "c",
      function(c)
         c:kill()
      end,
      { description = "Close", group = "client" }),
   
   awful.key({ modkey, "Control" }, "space",
      awful.client.floating.toggle,
      { description = "Window always floating", group = "client" }),

   awful.key({ modkey, "Control" }, "Return",
      function(c)
         c:swap(awful.client.getmaster())
      end,
      { description = "Move to master", group = "client" }),

   awful.key({ modkey }, "o",
      function(c)
         c:move_to_screen() 
      end,
      { description = "Move to screen", group = "client" }),

   awful.key({ modkey }, "t",
      function(c)
         c.ontop = not c.ontop
      end,
      { description = "Toggle always-on-top", group = "client" }),

   awful.key({ modkey }, "n",
      function(c)
         -- The client currently has the input focus, so it cannot be
         -- minimized, since minimized clients can't have the focus.
         c.minimized = true
      end,
      { description = "Minimize", group = "client" }),

   awful.key({ modkey }, "m",
      function(c)
         c.maximized_vertical   = not c.maximized_vertical
         c.maximized_horizontal = not c.maximized_horizontal
      end,
      { description = "Maximize", group = "client" }),

   awful.key({ ALT }, "F4",
      function(c)
         window_menu.hide(c)
         c:kill()
      end,
      { description = "Close", group = "client" }),

   awful.key({ ALT }, "space",
      function(c)
         local geo = c:geometry()
         window_menu.show(c, { coords = { x = geo.x, y = geo.y } })
      end,
      { description = "Open window menu", group = "client" }),

   docking.move_key("vertical",   -delta, { modkey, ALT }, "Up"),
   docking.move_key("vertical",    delta, { modkey, ALT }, "Down"),
   docking.move_key("horizontal", -delta, { modkey, ALT }, "Left"),
   docking.move_key("horizontal",  delta, { modkey, ALT }, "Right"),

   docking.resize_key("vertical",   -delta, { modkey, ALT, "Ctrl" }, "Up"),
   docking.resize_key("vertical",    delta, { modkey, ALT, "Ctrl" }, "Down"),
   docking.resize_key("horizontal", -delta, { modkey, ALT, "Ctrl" }, "Left"),
   docking.resize_key("horizontal",  delta, { modkey, ALT, "Ctrl" }, "Right"),

   docking.corner_key("top",    "left",  { modkey }, "KP_Home"),
   docking.corner_key("top",    "right", { modkey }, "KP_Prior"),
   docking.corner_key("bottom", "left",  { modkey }, "KP_End"),
   docking.corner_key("bottom", "right", { modkey }, "KP_Next"),

   awful.key({ modkey }, "KP_Left",  docking.dock_left),
   awful.key({ modkey }, "KP_Right", docking.dock_right),
   awful.key({ modkey }, "KP_Up",    docking.dock_up),
   awful.key({ modkey }, "KP_Down",  docking.dock_down),

   awful.key({ modkey }, "Left",  docking.dock_left,  { description = "Dock / move docked window", group = "awesome gobolinux" }),
   awful.key({ modkey }, "Right", docking.dock_right, { description = "Dock / move docked window", group = "awesome gobolinux" }),
   awful.key({ modkey }, "Up",    docking.dock_up,    { description = "Dock / move docked window", group = "awesome gobolinux" }),
   awful.key({ modkey }, "Down",  docking.dock_down,  { description = "Dock / move docked window", group = "awesome gobolinux" })
)

-- Bind all key numbers to tags.
-- Be careful: we use keycodes to make it works on any keyboard layout.
-- Win+1..9 = desktop 1..9 (those that exist); only the first is listed in the hotkeys help.
for i = 1, 9 do
   local function d(text) return i == 1 and { description = text, group = "desktops" } or nil end
   globalkeys = awful.util.table.join(globalkeys,

   awful.key({ modkey }, "#" .. i + 9,
      function()
         local screen = mouse.screen
         local tag = awful.tag.gettags(screen)[i]
         if tag then
            awful.tag.viewonly(tag)
         end
      end,
      d("Go to desktop 1 (Win+1 ... Win+9)")),

   awful.key({ modkey, "Control" }, "#" .. i + 9,
      function()
         local screen = mouse.screen
         local tag = awful.tag.gettags(screen)[i]
         if tag then
            awful.tag.viewtoggle(tag)
         end
      end,
      d("Also show desktop 1 (Win+Ctrl+1 ... 9)")),

   awful.key({ modkey, "Shift" }, "#" .. i + 9,
      function()
         if client.focus then
            local tag = awful.tag.gettags(client.focus.screen)[i]
            if tag then
               awful.client.movetotag(tag)
            end
         end
      end,
      d("Move window to desktop 1 (Win+Shift+1 ... 9)")),

   awful.key({ modkey, "Control", "Shift" }, "#" .. i + 9,
      function()
         if client.focus then
            local tag = awful.tag.gettags(client.focus.screen)[i]
            if tag then
               awful.client.toggletag(tag)
            end
         end
      end,
      d("Window also on desktop 1 (Win+Ctrl+Shift+1 ... 9)")))
end

local clientbuttons = awful.util.table.join(

   awful.button({}, 1,
      function(c)
         client.focus = c
         c:raise()
      end),

   awful.button({ ALT }, 1,
      function(c) client.focus = c
         c:raise()
         docking.smart_mouse_move(c)
      end),

   awful.button({ "Control", ALT }, 1, 
      function(c) client.focus = c
         c:raise()
         awful.mouse.client.resize(c)
      end),

   awful.button({ ALT }, 3, 
      function(c) 
         client.focus = c
         c:raise()
         awful.mouse.client.resize(c)
      end)
)

-- 0.8.1: a tap on the Win key alone (press and release, nothing else in between, under
-- 0.6 s) opens the dots menu; holding Win for a shortcut does not.
-- Binding Super_L makes X send every key to that grab (the root window) while Win is held,
-- so the window keys with Win (Win+F, Win+arrows, ...) would no longer reach the window's
-- own bindings: they are mirrored as global keys acting on the focused window.
local function tap_used() end
do
   local GLib = require("lgi").GLib
   local tap = { down = false, used = false, t = 0 }
   local function now() return GLib.get_monotonic_time() / 1e6 end
   tap_used = function() tap.used = true end
   for _, k in ipairs(globalkeys) do k:connect_signal("press", tap_used) end
   for _, k in ipairs(clientkeys) do k:connect_signal("press", tap_used) end
   local extra = {}
   for _, k in ipairs(clientkeys) do
      local mods = k.modifiers or {}
      if gears.table.hasitem(mods, modkey) and not gears.table.hasitem(mods, "Lock")
         and not gears.table.hasitem(mods, "Mod2") then
         for _, g in ipairs(awful.key(mods, k.key, function()
            local c = client.focus
            if c then k:emit_signal("press", c) end
         end)) do table.insert(extra, g) end
      end
   end
   for _, g in ipairs(awful.key({}, "Super_L", function()
      if not tap.down then tap.down, tap.used, tap.t = true, false, now() end
   end)) do table.insert(extra, g) end
   for _, g in ipairs(awful.key({ modkey }, "Super_L", nil, function()
      local open = tap.down and not tap.used and now() - tap.t < 0.6
      tap.down = false
      if open then mymainmenu:toggle() end
   end)) do table.insert(extra, g) end
   globalkeys = awful.util.table.join(globalkeys, extra)
   spin_debug.mainmenu = mymainmenu   -- lab input test (win-tap scenarios)
   -- a click with Win held also counts (the click still reaches the window)
   for _, b in ipairs({ 1, 2, 3 }) do
      clientbuttons = awful.util.table.join(clientbuttons, awful.button({ modkey }, b, tap_used))
   end
end

-- Set keys
root.keys(globalkeys)

-- Rules to apply to new clients (through the "manage" signal).

local default_properties = {
   border_width = beautiful.border_width,
   focus = awful.client.focus.filter,
   raise = true,
   keys = clientkeys,
   screen = awful.screen.focused,
   buttons = clientbuttons
}

awful.rules.rules = {
   { rule = {}, properties = default_properties },  -- All clients will match this rule.
   { rule = { class = "MPlayer" }, properties = { floating = true } },
   { rule = { class = "pinentry" }, properties = { floating = true } },
   { rule = { class = "gimp" }, properties = { floating = true } },
   -- Sound control opens above the volume icon; display settings in the middle of the screen.
   { rule = { class = "Pavucontrol" }, properties = { floating = true, width = 660, height = 480,
      placement = function(c) awful.placement.bottom_right(c, { honor_workarea = true, margins = 8 }) end } },
   { rule = { class = "Lxrandr" }, properties = { floating = true, placement = awful.placement.centered } },
   -- Add titlebars to normal clients and dialogs
   { rule_any = {type = { "normal", "dialog" } }, properties = { titlebars_enabled = true } },
   -- 0.6: PCManFM's desktop window (icons of ~/Desktop): on every desktop, never in the taskbar,
   -- and it never takes the keyboard focus (a click on an icon or the desktop leaves it where it was)
   { rule = { type = "desktop" }, properties = { sticky = true, border_width = 0, titlebars_enabled = false,
      skip_taskbar = true, focusable = false, below = true } },
   -- Its dialogs (Move to Trash?, Rename, Properties...) are transient for it, and Awesome gives a
   -- transient window its parent's desktop: the sticky desktop window's own tag, desktop 1. Open
   -- them on the desktop being looked at (0.6 ISO test: from desktop 2 they appeared on desktop 1).
   { rule = {}, callback = function(c)
        if c.transient_for and c.transient_for.type == "desktop" then
           c:tags(c.transient_for.screen.selected_tags)
        end
     end },}

local no_decorations = {
    ["plugin-container"] = true,
    ["Audacious"] = true,
    ["alsamixer"] = true,
    ["ncpamixer"] = true,
}

for name, _ in pairs(no_decorations) do
   table.insert(awful.rules.rules, { rule = { class = name }, properties = { floating = true, border_width = 0, titlebars_enabled = false }})
   table.insert(awful.rules.rules, { rule = { name  = name }, properties = { floating = true, border_width = 0, titlebars_enabled = false }})
end

local function hover_bright(name, w)
   local hover_img = beautiful["titlebar_"..name.."_button_hover"]
   if hover_img then
      w:connect_signal( "mouse::enter", function() w:set_image(hover_img) end )
      w:connect_signal( "mouse::leave", w.update )
   end
   return w
end

local function adjust_border_width(c)
   if c.maximized or (no_decorations[c.name] or no_decorations[c.class]) then
      c.border_width = 0
   else
      c.border_width = beautiful.border_width
   end
end

local function normal_border(c)
   if c == client.focus then
      c.border_color = beautiful.border_focus
   else
      c.border_color = beautiful.border_normal
   end
end

-- Signals
-- Signal function to execute when a new client appears.
client.connect_signal("manage", function(c, startup)

   adjust_border_width(c)
    
   -- When we only have one screen and we are restoring
   -- windows that were closed in the second screen,
   -- move them to the first screen.
   if screen.count() == 1 then
      local geo = screen[1].geometry
      if c.x > geo.width or c.x < geo.x then
         c.x = geo.x
      end
      if c.y > geo.height or c.y < geo.y then
         c.y = geo.y
      end
   end

   if sloppy_focus then
      c:connect_signal("mouse::enter", function(c)
         if awful.layout.get(c.screen) ~= awful.layout.suit.magnifier
            and awful.client.focus.filter(c) then
            client.focus = c
         end
      end)
   end

   -- Border resize
   c:connect_signal("button::press", function(c, x, y, button)
      if not c.maximized and button == 1 and (x < 0 or x >= c.width or y < 0 or y >= c.height) then
         awful.mouse.client.resize(c)
      end
   end)

   if not startup then
      -- Put windows in a smart way, only if they does not set an initial position.
      if not c.size_hints.user_position and not c.size_hints.program_position then
         awful.placement.no_overlap(c)
         awful.placement.no_offscreen(c)
      end
   end

end)

client.connect_signal("request::titlebars", function(c, context, hints)
   if not titlebars_enabled then
      return
   end

   -- buttons for the titlebar: press + drag moves the window, a second press
   -- within 300 ms (a double click) maximizes or restores it
   local last_press = 0
   local buttons = awful.util.table.join(
      awful.button({}, 1,
         function()
            client.focus = c
            c:raise()
            window_menu.hide(c)
            local now = GLib.get_monotonic_time()   -- microseconds
            if now - last_press < 300000 then
               last_press = 0
               c.maximized = not c.maximized
               return
            end
            last_press = now
            -- Start moving only once the pointer really moves (> 3 px): a plain click
            -- must not trigger awful's edge snapping when the window touches the top.
            local start = mouse.coords()
            mousegrabber.run(function(m)
               if not m.buttons[1] then return false end
               if math.abs(m.x - start.x) > 3 or math.abs(m.y - start.y) > 3 then
                  gears.timer.delayed_call(function()
                     if c.valid and mouse.coords().buttons[1] then docking.smart_mouse_move(c) end
                  end)
                  return false
               end
               return true
            end, "fleur")
         end),
      awful.button({}, 3,
         function()
            client.focus = c
            c:raise()
            window_menu.show(c)
         end)
   )

   -- Icon and title on the left
   local title = awful.titlebar.widget.titlewidget(c)
   title:set_align("left")
   title.font = beautiful.font_title
   local left_layout = wibox.layout.fixed.horizontal()
   left_layout:add(wibox.container.margin(awful.titlebar.widget.iconwidget(c), 10, 8, 8, 8))
   left_layout:add(title)
   left_layout:buttons(buttons)

   -- Minimise, maximise, close on the right
   local right_layout = wibox.layout.fixed.horizontal()
   right_layout:add(hover_bright("minimize", awful.titlebar.widget.minimizebutton(c)))
   right_layout:add(hover_bright("maximized", awful.titlebar.widget.maximizedbutton(c)))
   right_layout:add(hover_bright("close", awful.titlebar.widget.closebutton(c)))

   -- Empty space in the middle still drags the window
   local middle = wibox.widget.base.empty_widget()
   middle:buttons(buttons)

   local layout = wibox.layout.align.horizontal()
   layout:set_left(left_layout)
   layout:set_middle(middle)
   layout:set_right(right_layout)

   awful.titlebar(c, { size = beautiful.titlebar_height }):set_widget(layout)

   -- Highlight the border while the mouse is on it (that is where resizing works)
   c:connect_signal("mouse::move", function(c, x, y)
      if x < 0 or x >= c.width or y < 0 or y >= c.height then
         c.border_color = beautiful.border_hover
      else
         normal_border(c)
      end
   end)
   c:connect_signal("mouse::enter", normal_border)
   c:connect_signal("mouse::leave", normal_border)

end)

-- Rounded corners, except when a window fills the screen.
local function update_shape(c)
   if c.fullscreen or c.maximized then
      c.shape = gears.shape.rectangle
   else
      c.shape = beautiful.client_shape
   end
end
client.connect_signal("manage", update_shape)
client.connect_signal("property::maximized", update_shape)
client.connect_signal("property::fullscreen", update_shape)

client.connect_signal("focus", function(c) c.border_color = beautiful.border_focus end)
client.connect_signal("unfocus", function(c) c.border_color = beautiful.border_normal end)
client.connect_signal("property::maximized", adjust_border_width)


-- devmon (USB automounter, started in ~/.xinitrc) belongs to this session: stop it when
-- the desktop ends (not on a restart), so it unmounts the drives it mounted.
awesome.connect_signal("exit", function(restart)
   if not restart then
      awful.spawn.with_shell("pkill -u \"$(id -u)\" -x devmon")
   end
end)
