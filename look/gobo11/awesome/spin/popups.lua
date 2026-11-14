-- One place that knows every popup of the look (0.6).
--
-- Why: while a popup grabs the keyboard, no window gets any key, even the one that has the
-- focus (its cursor keeps blinking). 0.5 had three ways to end up there:
--   * awful.menu (category menu, window menu, network menu, USB menu, taskbar window list)
--     grabs the keyboard for as long as it is open, and nothing closed it when the user
--     clicked a window, the taskbar or the desktop;
--   * the search closed itself with awful.keygrabber.stop() without naming its grabber,
--     which removes the OLDEST grabber on awful's stack: with the category menu open
--     underneath, the menu's grabber went and the hidden search prompt kept the keyboard;
--   * the hotkeys popup closes only on a key or a click on itself.
--
-- What this module does:
--   * register(name, hide): popups announce themselves; close_all(except) hides all others,
--     so only one popup is ever open (every show() calls it first);
--   * every top-level awful.menu gets a transparent backdrop: a click anywhere outside the
--     menu closes it, and if the click was on a window, that window gets the focus;
--   * panic() (Win+Escape, also inside any keyboard grab): close everything, drop every
--     keyboard and mouse grab, focus the window under the pointer.
local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")

local popups = {}
local registry = {}        -- name -> hide function
local open_menus = {}      -- top-level awful.menu objects that are visible

function popups.register(name, hide)
   registry[name] = hide
end

-- The window under (x, y): the topmost visible client whose frame contains the point.
function popups.client_at(x, y)
   local stack = client.get(nil, true)   -- bottom to top
   for i = #stack, 1, -1 do
      local c = stack[i]
      if c.valid and c:isvisible() and not c.minimized then
         local g = c:geometry()
         if x >= g.x and x < g.x + g.width + 2 * c.border_width
            and y >= g.y and y < g.y + g.height + 2 * c.border_width then
            return c
         end
      end
   end
end

-- Give the focus to the window under the pointer (after a click on a backdrop, which the
-- window itself never sees).
function popups.focus_under_pointer()
   local m = mouse.coords()
   local c = popups.client_at(m.x, m.y)
   if c then
      client.focus = c
      c:raise()
   end
   return c
end

function popups.close_all(except)
   for name, hide in pairs(registry) do
      if name ~= except then
         local ok, err = pcall(hide)
         if not ok then io.stderr:write("popups: closing " .. name .. ": " .. tostring(err) .. "\n") end
      end
   end
   for m in pairs(open_menus) do
      if m ~= except then m:hide() end
   end
end

-- A transparent sheet over a whole screen, below the popup: a click on it calls on_click.
-- Shown before the popup, so the popup is stacked above it.
function popups.backdrop(on_click, bg)
   local b = wibox({ ontop = true, visible = false, bg = bg or "#00000000", type = "utility" })
   local function clicked()
      on_click()
      popups.focus_under_pointer()
   end
   b:buttons(gears.table.join(
      awful.button({}, 1, clicked), awful.button({}, 2, clicked), awful.button({}, 3, clicked)))
   function b.show_on(s)
      b:geometry((s or awful.screen.focused()).geometry)
      b.visible = true
   end
   return b
end

-- awful.menu: close others before showing, backdrop while open (top-level menus only;
-- submenus belong to their root). Called from rc.lua's awful.menu.new wrapper.
local menu_backdrop
function popups.manage_menu(m)
   if m.parent then return m end
   local show, hide = m.show, m.hide
   m.show = function(self, args)
      popups.close_all(self)
      if not menu_backdrop then
         menu_backdrop = popups.backdrop(function()
            for om in pairs(open_menus) do om:hide() end
         end)
      end
      menu_backdrop.show_on(awful.screen.focused())
      open_menus[self] = true
      show(self, args)
      if not self.wibox.visible then   -- the menu refused to show (no items): no backdrop
         open_menus[self] = nil
         if next(open_menus) == nil then menu_backdrop.visible = false end
      end
   end
   m.hide = function(self)
      hide(self)
      open_menus[self] = nil
      if menu_backdrop and next(open_menus) == nil then menu_backdrop.visible = false end
   end
   return m
end

-- awful.keygrabber keeps its stack in a local table; reach it for panic().
local function awful_grabbers()
   local kg = awful.keygrabber
   for i = 1, 30 do
      local name, value = debug.getupvalue(kg.stop, i)
      if not name then break end
      if name == "grabbers" then return value end
   end
   return {}
end

function popups.release_grabs()
   local stack = awful_grabbers()
   for i = #stack, 1, -1 do
      if stack[i] then awful.keygrabber.stop(stack[i]) end
   end
   if keygrabber.isrunning() then keygrabber.stop() end
   if mousegrabber.isrunning() then mousegrabber.stop() end
end

function popups.panic()
   popups.close_all()
   popups.release_grabs()
   -- back to a window: the one under the pointer, else the last focused one
   if not popups.focus_under_pointer() and not client.focus then
      local c = awful.client.focus.history.get(awful.screen.focused(), 0)
      if c then client.focus = c; c:raise() end
   end
end

-- Win+Escape must work even while a popup holds the keyboard (root key bindings are not
-- seen then): every keyboard grab, ours or awful's, runs through this filter first.
do
   local c_run = keygrabber.run
   local function is_panic(mods, key, event)
      if key ~= "Escape" or event ~= "press" then return false end
      for _, m in ipairs(mods or {}) do
         if m == "Mod4" then return true end
      end
      return false
   end
   rawset(keygrabber, "run", function(f)
      return c_run(function(mods, key, event)
         if is_panic(mods, key, event) then
            gears.timer.delayed_call(popups.panic)
            return
         end
         return f(mods, key, event)
      end)
   end)
end

return popups
