-- 0.9.6: the desktop's keyboard shortcuts that a user may change (Settings > Hotkeys), their
-- defaults, the keys that stay fixed, and the user's file. Plain Lua (no Awesome, no GTK): used by
-- rc.lua (it builds the key bindings from this) and by the Settings page (pages/hotkeys.lua reads
-- it from ~/.config/awesome/spin/hotkeys_list.lua).
--
-- A key combination is written as Awesome names joined by "+", modifiers first:
--   "Mod4+Shift+s"  (Mod4 = Win, Mod1 = Alt, Control = Ctrl), "Print", "Control+Mod1+Delete".
-- The key itself is an X key name ("s", "Return", "Tab", "F2", "comma", "Print", ...).
--
-- The user's file, ~/.config/goborefined/hotkeys (outside ~/.config/awesome, so a system update,
-- which rewrites the look, keeps it), one line each, TAB-separated:
--   key<TAB>ACTION-ID<TAB>COMBO          the action uses COMBO instead of its default key(s)
--   off<TAB>ACTION-ID                    the action has no key
--   custom<TAB>NAME<TAB>COMBO<TAB>app<TAB>DESKTOP-ID     own shortcut: start a program
--   custom<TAB>NAME<TAB>COMBO<TAB>cmd<TAB>COMMAND        own shortcut: run a command
-- Lines that do not parse, unknown actions and combinations already taken are ignored.
local M = {}

M.FILE_NAME = "/.config/goborefined/hotkeys"   -- under $HOME

-- id, label, group (Win+S help), default keys; window = acts on the focused window;
-- power = not bound for Simple accounts (0.9.1)
M.ACTIONS = {
   { id = "screenshot", label = "Screenshot: area, window or screen", group = "screenshots and clipboard", keys = { "Mod4+Shift+s" } },
   { id = "screenshot-screen", label = "Screenshot of the whole screen", group = "screenshots and clipboard", keys = { "Print" } },
   { id = "clipboard", label = "Clipboard history: pick an earlier copy", group = "screenshots and clipboard", keys = { "Mod4+Shift+v" } },
   { id = "help", label = "Show hotkeys", group = "awesome", keys = { "Mod4+s" } },
   { id = "start-menu", label = "Show the start menu", group = "awesome", keys = { "Mod4+w" } },
   { id = "search", label = "Search and start applications", group = "launcher", keys = { "Mod4+r", "Mod4+p", "Mod1+F2" } },
   { id = "desktops", label = "Desktops: list, switch, add, remove", group = "desktops", keys = { "Mod4+Shift+Tab" } },
   { id = "desktop-prev", label = "Previous desktop", group = "desktops", keys = { "Mod4+comma" } },
   { id = "desktop-next", label = "Next desktop", group = "desktops", keys = { "Mod4+period" } },
   { id = "previous-window", label = "Go back to the previous window", group = "client", keys = { "Mod4+Tab" } },
   { id = "lock", label = "Lock the screen", group = "awesome", keys = { "Mod4+l" } },
   { id = "power-menu", label = "Power menu", group = "awesome", keys = { "Control+Mod1+Delete" } },
   { id = "terminal", label = "Open a terminal", group = "launcher", keys = { "Mod4+Return" }, power = true },
   { id = "files", label = "Open the file manager", group = "launcher", keys = { "Mod4+e" } },
   { id = "browser", label = "Open a browser", group = "launcher", keys = { "Mod4+Shift+Return" } },
   { id = "restart-desktop", label = "Restart the desktop (Awesome)", group = "awesome", keys = { "Mod4+Control+r" }, power = true },
   { id = "quit-desktop", label = "Log out (quit Awesome)", group = "awesome", keys = { "Mod4+Shift+q" }, power = true },
   { id = "layout-next", label = "Next window layout", group = "layout", keys = { "Mod4+space" } },
   { id = "layout-prev", label = "Previous window layout", group = "layout", keys = { "Mod4+Shift+space" } },
   { id = "focus-next", label = "Focus the next window", group = "client", keys = { "Mod4+k" } },
   { id = "focus-prev", label = "Focus the previous window", group = "client", keys = { "Mod4+j" } },
   { id = "restore", label = "Restore a minimized window", group = "client", keys = { "Mod4+Control+n" } },
   -- window keys
   { id = "win-fullscreen", label = "Window: full screen on/off", group = "client", keys = { "Mod4+f" }, window = true },
   { id = "win-maximize", label = "Window: maximize", group = "client", keys = { "Mod4+m" }, window = true },
   { id = "win-minimize", label = "Window: minimize", group = "client", keys = { "Mod4+n" }, window = true },
   { id = "win-close", label = "Window: close", group = "client", keys = { "Mod4+Shift+c", "Mod1+F4" }, window = true },
   { id = "win-ontop", label = "Window: always on top on/off", group = "client", keys = { "Mod4+t" }, window = true },
   { id = "win-floating", label = "Window: always floating on/off", group = "client", keys = { "Mod4+Control+space" }, window = true },
   { id = "win-menu", label = "Window: open its menu", group = "client", keys = { "Mod1+space" }, window = true },
   { id = "win-screen", label = "Window: move to the other screen", group = "client", keys = { "Mod4+o" }, window = true },
}
M.BY_ID = {}
for _, a in ipairs(M.ACTIONS) do M.BY_ID[a.id] = a end

-- keys that cannot be changed or taken (shown on the page; the safety net comes first)
M.FIXED = {
   { label = "Close all popups, free the keyboard (safety net)", keys = { "Mod4+Escape" } },
   { label = "Start menu (tap the Win key alone)", keys = { "Super_L" } },
   { label = "Switch between windows", keys = { "Mod1+Tab", "Mod1+Shift+Tab" } },
   { label = "Go to desktop 1-9 / also show / move window / window also on",
     keys = { "Mod4+1", "Mod4+2", "Mod4+3", "Mod4+4", "Mod4+5", "Mod4+6", "Mod4+7", "Mod4+8", "Mod4+9" },
     prefixes = { "Mod4+", "Mod4+Control+", "Mod4+Shift+", "Mod4+Control+Shift+" }, digits = true },
   { label = "Dock and move windows (arrows, number pad)",
     keys = { "Mod4+Left", "Mod4+Right", "Mod4+Up", "Mod4+Down",
              "Mod4+Mod1+Left", "Mod4+Mod1+Right", "Mod4+Mod1+Up", "Mod4+Mod1+Down",
              "Mod4+Control+Mod1+Left", "Mod4+Control+Mod1+Right", "Mod4+Control+Mod1+Up", "Mod4+Control+Mod1+Down",
              "Mod4+KP_Home", "Mod4+KP_Prior", "Mod4+KP_End", "Mod4+KP_Next",
              "Mod4+KP_Left", "Mod4+KP_Right", "Mod4+KP_Up", "Mod4+KP_Down" } },
   { label = "Tiled layouts: sizes, columns, swap, screens, urgent window",
     keys = { "Mod4+bracketright", "Mod4+bracketleft", "Mod4+Shift+h", "Mod4+Shift+l", "Mod4+Control+h",
              "Mod4+Control+l", "Mod4+Shift+j", "Mod4+Shift+k", "Mod4+Control+j", "Mod4+Control+k", "Mod4+u",
              "Mod4+Control+Return" } },
   { label = "Volume, brightness and browser keys of the keyboard",
     keys = { "XF86AudioRaiseVolume", "XF86AudioLowerVolume", "XF86AudioMute", "XF86MonBrightnessUp",
              "XF86MonBrightnessDown", "XF86HomePage" } },
}

local MOD_ORDER = { "Mod4", "Control", "Mod1", "Shift" }
local MOD_NAME = { Mod4 = "Win", Control = "Ctrl", Mod1 = "Alt", Shift = "Shift" }
local MOD_ALIAS = { mod4 = "Mod4", super = "Mod4", win = "Mod4", control = "Control", ctrl = "Control",
                    mod1 = "Mod1", alt = "Mod1", shift = "Shift" }
local KEY_ALIAS = { [","] = "comma", ["."] = "period", ["Escape"] = "Escape", ["ISO_Left_Tab"] = "Tab",
                    ["KP_Enter"] = "KP_Enter" }

-- "Mod4+Shift+s" -> { "Mod4", "Shift" }, "s" (canonical order; nil for nonsense)
function M.split(combo)
   if type(combo) ~= "string" or combo == "" or combo:find("[%s\t]") then return nil end
   local parts = {}
   for p in (combo .. "+"):gmatch("(.-)%+") do table.insert(parts, p) end
   if combo:sub(-1) == "+" then return nil end
   local key = table.remove(parts)
   if not key or key == "" then return nil end
   local have = {}
   for _, p in ipairs(parts) do
      local m = MOD_ALIAS[p:lower()]
      if not m then return nil end
      have[m] = true
   end
   local mods = {}
   for _, m in ipairs(MOD_ORDER) do if have[m] then table.insert(mods, m) end end
   key = KEY_ALIAS[key] or key
   if #key == 1 then key = key:lower() end
   if not key:match("^[%w_]+$") then return nil end
   return mods, key
end

function M.normalize(combo)
   local mods, key = M.split(combo)
   if not mods then return nil end
   table.insert(mods, key)
   return table.concat(mods, "+")
end

local KEY_SHOW = { comma = ",", period = ".", Return = "Enter", Prior = "PageUp", Next = "PageDown",
                   bracketleft = "[", bracketright = "]", space = "Space", Super_L = "Win" }
function M.display(combo)
   local mods, key = M.split(combo)
   if not mods then return tostring(combo) end
   local out = {}
   for _, m in ipairs(mods) do table.insert(out, MOD_NAME[m]) end
   local k = KEY_SHOW[key] or key
   if #k == 1 then k = k:upper() end
   table.insert(out, k)
   return table.concat(out, "+")
end

-- A combination a user may give an action: it must have Win, Ctrl or Alt, except the function
-- keys, Print, Pause, Scroll Lock and the keyboard's media keys (a plain letter would stop typing).
function M.usable(combo)
   local mods, key = M.split(combo)
   if not mods then return false, "This is not a key combination." end
   if key:match("^Super_") or key:match("^Shift_") or key:match("^Control_") or key:match("^Alt_")
      or key:match("^Meta_") or key:match("^ISO_Level") or key == "Caps_Lock" or key == "Num_Lock" then
      return false, "Press a key together with the modifier keys, not the modifier keys alone."
   end
   local strong = false
   for _, m in ipairs(mods) do if m ~= "Shift" then strong = true end end
   if not strong and not (key:match("^F%d+$") or key == "Print" or key == "Pause" or key == "Scroll_Lock"
                          or key:match("^XF86")) then
      return false, "Use Win, Ctrl or Alt with this key (otherwise it could not be typed any more)."
   end
   return true
end

-- the user's file -------------------------------------------------------------------------
-- returns { over = { id = combo | false }, custom = { { name, combo, kind, value } } }
function M.parse(text)
   local cfg = { over = {}, custom = {} }
   for line in (text or ""):gmatch("[^\n]+") do
      local f = {}
      for field in (line .. "\t"):gmatch("([^\t]*)\t") do table.insert(f, field) end
      if f[1] == "key" and M.BY_ID[f[2] or ""] and M.normalize(f[3]) then
         cfg.over[f[2]] = M.normalize(f[3])
      elseif f[1] == "off" and M.BY_ID[f[2] or ""] then
         cfg.over[f[2]] = false
      elseif f[1] == "custom" and (f[2] or "") ~= "" and M.normalize(f[3]) and (f[4] == "app" or f[4] == "cmd")
         and (f[5] or "") ~= "" then
         table.insert(cfg.custom, { name = f[2], combo = M.normalize(f[3]), kind = f[4], value = f[5] })
      end
   end
   return cfg
end

local function clean(s) return (tostring(s or ""):gsub("[\t\r\n]", " ")) end

function M.serialize(cfg)
   local out = { "# GoboRefined hotkeys (Settings > Hotkeys). key|off|custom, fields separated by TAB.\n" }
   for _, a in ipairs(M.ACTIONS) do
      local v = cfg.over[a.id]
      if v == false then table.insert(out, "off\t" .. a.id .. "\n")
      elseif v then table.insert(out, "key\t" .. a.id .. "\t" .. v .. "\n") end
   end
   for _, c in ipairs(cfg.custom) do
      table.insert(out, table.concat({ "custom", clean(c.name), c.combo, c.kind, clean(c.value) }, "\t") .. "\n")
   end
   return table.concat(out)
end

function M.load(path)
   local f = io.open(path, "r")
   if not f then return M.parse("") end
   local s = f:read("*a")
   f:close()
   return M.parse(s)
end

-- the keys of an action after the user's changes (a list, empty when switched off)
function M.keys_of(cfg, id)
   local v = cfg.over[id]
   if v == false then return {} end
   if v then return { v } end
   local list = {}
   for _, k in ipairs(M.BY_ID[id].keys) do table.insert(list, M.normalize(k)) end
   return list
end

-- every combination in use: combo -> label of what has it. skip = { action = id } or
-- { custom = index } leaves that one out (the one being changed). opts.simple: power actions unbound
-- the fixed combinations: combo -> label
function M.fixed_combos()
   local used = {}
   for _, fx in ipairs(M.FIXED) do
      if fx.digits then
         for _, p in ipairs(fx.prefixes) do
            for d = 1, 9 do used[M.normalize(p .. d)] = fx.label .. " (fixed)" end
         end
      end
      for _, k in ipairs(fx.keys) do
         local n = M.normalize(k)
         if n then used[n] = fx.label .. " (fixed)" end
      end
   end
   return used
end

function M.in_use(cfg, skip, opts)
   skip = skip or {}
   local used = M.fixed_combos()
   for _, a in ipairs(M.ACTIONS) do
      if skip.action ~= a.id and not (opts and opts.simple and a.power) then
         for _, k in ipairs(M.keys_of(cfg, a.id)) do used[k] = used[k] or a.label end
      end
   end
   for i, c in ipairs(cfg.custom) do
      if skip.custom ~= i then used[c.combo] = used[c.combo] or (c.name .. " (your shortcut)") end
   end
   return used
end

-- nil when `combo` can be given to the action/custom entry in `skip`, else the reason
function M.refuse(cfg, combo, skip, opts)
   local ok, why = M.usable(combo)
   if not ok then return why end
   local n = M.normalize(combo)
   local owner = M.in_use(cfg, skip, opts)[n]
   if owner then return M.display(n) .. " is already used by: " .. owner end
   return nil
end

return M
