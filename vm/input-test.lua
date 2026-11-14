-- Lab helper loaded into the running Awesome by vm/input-test.sh (dofile).
-- Simulates mouse and keyboard input with root.fake_input. Defines the global table T.
local awful = require("awful")
T = T or {}

local names = { [" "] = "space", ["/"] = "slash", ["-"] = "minus", ["."] = "period", ["_"] = "underscore" }

function T.move(x, y) root.fake_input("motion_notify", false, x, y) end

function T.click(x, y, button)
   button = button or 1
   if x then T.move(x, y) end
   root.fake_input("button_press", button)
   root.fake_input("button_release", button)
end

-- T.key({"Mod4"}, "Escape"): press modifiers, tap the key, release modifiers
function T.key(mods, key)
   for _, m in ipairs(mods or {}) do root.fake_input("key_press", m) end
   root.fake_input("key_press", key)
   root.fake_input("key_release", key)
   for i = #(mods or {}), 1, -1 do root.fake_input("key_release", mods[i]) end
end

-- type lower-case letters, digits, space, / - . (no shift needed on a US layout), one key
-- every 40 ms (a burst lands in the X queue before Awesome can react to the first keys);
-- "\n" = Return
function T.type(s)
   local keys = {}
   for ch in s:gmatch(".") do table.insert(keys, ch == "\n" and "Return" or (names[ch] or ch)) end
   local i = 0
   require("gears").timer.start_new(0.04, function()
      i = i + 1
      if not keys[i] then return false end
      root.fake_input("key_press", keys[i])
      root.fake_input("key_release", keys[i])
      return true
   end)
end

-- geometry of the first client whose class matches (lower-case compare)
function T.find(class)
   for _, c in ipairs(client.get()) do
      if (c.class or ""):lower() == class:lower() or (c.instance or ""):lower() == class:lower() then
         return c
      end
   end
end

-- click into the middle of a client's content area
function T.click_client(class)
   local c = T.find(class)
   if not c then return "no client " .. class end
   local g = c:geometry()
   T.click(g.x + math.floor(g.width / 2), g.y + math.floor(g.height / 2) + 10)
   return "clicked " .. class
end

-- centre of a taskbar widget exposed by rc.lua in _G.spin_debug (start, net, usb, desktops),
-- found by scanning the primary screen's taskbar
function T.pos(name)
   local w = spin_debug and spin_debug[name]
   local bar = spin_debug and spin_debug.bars and spin_debug.bars[screen.primary]
   if not w or not bar then return nil end
   for x = 0, bar.width - 1, 2 do
      for _, info in ipairs(bar._drawable:find_widgets(x, math.floor(bar.height / 2))) do
         if info.widget == w then
            return math.floor(bar.x + info.x + info.width / 2), math.floor(bar.y + info.y + info.height / 2)
         end
      end
   end
end

function T.click_pos(name, button)
   local x, y = T.pos(name)
   if not x then return "no widget " .. name end
   T.click(x, y, button)
   return string.format("clicked %s at %d,%d", name, x, y)
end

-- an empty spot of the desktop (top right corner area, left of nothing)
function T.click_desktop(button)
   local g = screen.primary.geometry
   T.click(g.x + g.width - 60, g.y + 60, button)
end

-- state summary: is a keygrabber running, which client has focus, open popups
function T.state()
   local f = client.focus
   local open = {}
   for _, d in ipairs(T.visible_wiboxes and T.visible_wiboxes() or {}) do table.insert(open, d) end
   return string.format("grab=%s mgrab=%s focus=%s", tostring(keygrabber.isrunning()),
      tostring(mousegrabber.isrunning()), f and (f.class or "?") or "none")
end

return "input-test loaded"
