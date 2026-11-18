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
-- The desktop window (PCManFM --desktop: type "desktop", not focusable) is skipped: it covers
-- the whole screen and can sit high in this list (it is drawn below everything by its layer),
-- and focusing it sends the keyboard nowhere (0.6 ISO test: window menu + click on a terminal).
function popups.client_at(x, y)
   local stack = client.get(nil, true)   -- bottom to top
   for i = #stack, 1, -1 do
      local c = stack[i]
      if c.valid and c:isvisible() and not c.minimized
         and c.type ~= "desktop" and c.focusable ~= false then
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
-- 0.8.2: is_open() says whether the popup the sheet belongs to is still on screen. A sheet
-- whose popup is gone swallows every click on the desktop while the pointer still moves (the
-- real-PC "clicks stopped working" report): the watchdog below hides such a sheet, and a click
-- on it hides it at once even when on_click fails.
local backdrops = {}
popups.backdrops = backdrops   -- lab tests
function popups.backdrop(on_click, bg, is_open)
   local b = wibox({ ontop = true, visible = false, bg = bg or "#00000000", type = "utility" })
   b.is_open = is_open
   b.strikes = 0
   local function clicked()
      local ok, err = pcall(on_click)
      if not ok then io.stderr:write("popups: backdrop click: " .. tostring(err) .. "\n") end
      if b.visible and b.is_open and not b.is_open() then b.visible = false end
      popups.focus_under_pointer()
   end
   b:buttons(gears.table.join(
      awful.button({}, 1, clicked), awful.button({}, 2, clicked), awful.button({}, 3, clicked)))
   function b.show_on(s)
      b:geometry((s or awful.screen.focused()).geometry)
      b.strikes = 0
      b.visible = true
   end
   table.insert(backdrops, b)
   return b
end

-- number of sheets on screen (lab tests)
function popups.visible_backdrops()
   local n = 0
   for _, b in ipairs(backdrops) do if b.visible then n = n + 1 end end
   return n
end

-- awful.menu: close others before showing, backdrop while open (top-level menus only;
-- submenus belong to their root). Called from rc.lua's awful.menu.new wrapper.
local menu_backdrop
local function any_menu_visible()
   for om in pairs(open_menus) do
      if om.wibox and om.wibox.visible then return true end
   end
   return false
end
function popups.manage_menu(m)
   if m.parent then return m end
   local show, hide = m.show, m.hide
   m.show = function(self, args)
      popups.close_all(self)
      if not menu_backdrop then
         menu_backdrop = popups.backdrop(function()
            for om in pairs(open_menus) do pcall(om.hide, om) end
            open_menus = {}
         end, nil, any_menu_visible)
         popups.menu_backdrop = menu_backdrop   -- lab tests
      end
      menu_backdrop.show_on(awful.screen.focused())
      open_menus[self] = true
      local ok, err = pcall(show, self, args)
      if not ok then io.stderr:write("popups: menu show: " .. tostring(err) .. "\n") end
      if not ok or not self.wibox.visible then   -- the menu refused to show (no items): no backdrop
         open_menus[self] = nil
         if not any_menu_visible() then menu_backdrop.visible = false end
      end
   end
   m.hide = function(self)
      local ok, err = pcall(hide, self)
      if not ok then io.stderr:write("popups: menu hide: " .. tostring(err) .. "\n") end
      open_menus[self] = nil
      if menu_backdrop and not any_menu_visible() then menu_backdrop.visible = false end
   end
   return m
end

-- 0.8.2 watchdog: twice a second, a sheet whose popup is not visible gets a strike; on the
-- second strike in a row (so a popup being drawn right now is never caught) it is hidden.
-- Menus that vanished without hide() are dropped from the open list.
gears.timer({ timeout = 0.5, autostart = true, callback = function()
   for om in pairs(open_menus) do
      if not (om.wibox and om.wibox.visible) then open_menus[om] = nil end
   end
   for _, b in ipairs(backdrops) do
      if b.visible and b.is_open then
         if b.is_open() then
            b.strikes = 0
         else
            b.strikes = b.strikes + 1
            if b.strikes >= 2 then
               b.visible = false
               b.strikes = 0
               popups.watchdog_hits = (popups.watchdog_hits or 0) + 1
               io.stderr:write("popups: watchdog hid a click sheet whose popup was gone\n")
            end
         end
      end
   end
end })

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
   for _, b in ipairs(backdrops) do b.visible = false end   -- 0.8.2: no sheet survives Win+Escape
   -- back to a window: the one under the pointer, else the last focused one
   if not popups.focus_under_pointer() and not client.focus then
      local c = awful.client.focus.history.get(awful.screen.focused(), 0)
      if c then client.focus = c; c:raise() end
   end
end

-- Win+Escape must work even while a popup holds the keyboard (root key bindings are not
-- seen then): every keyboard grab, ours or awful's, runs through this filter first.
-- 0.8.1: keys registered with popups.pass() (the screenshot keys) also get through: every
-- popup closes, the grabs are released, then the key's action runs.
-- 0.9.6: opts.keep_open = true: nothing is closed first; the action itself closes the popups
-- when it is done (the screenshot keys: the picture is taken with the popup on it). The list is
-- built again when the user's hotkeys change (clear_passes, then pass again).
local passes = {}
function popups.pass(mods, key, action, opts)
   table.insert(passes, { mods = mods, key = key:lower(), action = action, keep_open = opts and opts.keep_open })
end
function popups.clear_passes() passes = {} end
do
   local c_run = keygrabber.run
   local function has(mods, wanted)
      for _, m in ipairs(mods or {}) do if m == wanted then return true end end
      return false
   end
   local function same_mods(mods, wanted)
      for _, w in ipairs(wanted) do if not has(mods, w) then return false end end
      for _, m in ipairs(mods or {}) do   -- no extra modifier (Lock and NumLock do not count)
         if m ~= "Lock" and m ~= "Mod2" and not gears.table.hasitem(wanted, m) then return false end
      end
      return true
   end
   local function is_panic(mods, key, event)
      return key == "Escape" and event == "press" and has(mods, "Mod4")
   end
   local function pass_for(mods, key, event)
      if event ~= "press" or not key then return nil end
      for _, p in ipairs(passes) do
         if key:lower() == p.key and same_mods(mods, p.mods) then return p end
      end
   end
   rawset(keygrabber, "run", function(f)
      return c_run(function(mods, key, event)
         if is_panic(mods, key, event) then
            gears.timer.delayed_call(popups.panic)
            return
         end
         local p = pass_for(mods, key, event)
         if p then
            gears.timer.delayed_call(function()
               if not p.keep_open then
                  popups.close_all()
                  popups.release_grabs()
               end
               p.action()
            end)
            return
         end
         return f(mods, key, event)
      end)
   end)
end

return popups
