-- pactl.lua (GoboRefined 0.8.5): reading PulseAudio's state from `pactl` output, and the rule
-- that picks a profile for a sound card PulseAudio left "off". Pure Lua (no lgi), used by the
-- session program sound-profile.lua (gobo-sound-profile) and by Settings > Sound.
-- pactl is always run with LC_ALL=C (the field names below are the English ones).
local M = {}

M.CHOICES = (os.getenv("HOME") or "") .. "/.config/goborefined/sound-cards"

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

function M.read_cmd(cmd)
   local p = io.popen("LC_ALL=C " .. cmd .. " 2>/dev/null", "r")
   if not p then return "" end
   local s = p:read("*a") or ""
   p:close()
   return s
end

function M.q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

-- `pactl list cards` -> { {index, name, description, active, profiles = {{name, description,
-- sinks, sources, priority, available}}, ports = {{name, description, available, direction}}} }
function M.parse_cards(text)
   local cards, card, section = {}, nil, nil
   for line in (text or ""):gmatch("[^\n]*") do
      local idx = line:match("^Card #(%d+)")
      if idx then
         card = { index = tonumber(idx), name = "", description = "", active = "", profiles = {}, ports = {} }
         table.insert(cards, card)
         section = nil
      elseif card then
         local key, value = line:match("^\t(%S[^:]*): ?(.*)$")
         if key then
            section = nil
            if key == "Name" then card.name = trim(value)
            elseif key == "Active Profile" then card.active = trim(value)
            elseif key == "Properties" then section = "properties"
            elseif key == "Profiles" then section = "profiles"
            elseif key == "Ports" then section = "ports"
            end
         elseif section == "properties" then
            local k, v = line:match('^\t\t(%S+) = "(.*)"$')
            if k == "device.description" then card.description = v end
         elseif section == "profiles" then
            local name, desc, sinks, sources, prio, avail =
               line:match("^\t\t(.-): (.*) %(sinks: (%d+), sources: (%d+), priority: (%d+), available: (%a+)%)%s*$")
            if name then
               table.insert(card.profiles, { name = name, description = desc, sinks = tonumber(sinks),
                  sources = tonumber(sources), priority = tonumber(prio), available = avail })
            end
         elseif section == "ports" then
            -- "\t\tname: Description (priority: N, latency offset: N usec[, available|not available])"
            local name, desc, rest = line:match("^\t\t([^\t:][^:]-): (.-) (%(priority:.*%))%s*$")
            if name then
               local avail = rest:match("not available") and "no" or rest:match("available") and "yes" or "unknown"
               table.insert(card.ports, { name = name, description = desc, available = avail })
            end
         end
      end
   end
   return cards
end

-- `pactl list sinks` / `pactl list sources` -> { {index, name, description, monitor, class, port} }
-- (monitor = a sink's monitor source, not a real input)
function M.parse_devices(text, kind)
   local list, dev, in_props = {}, nil, false
   local head = kind == "source" and "^Source #(%d+)" or "^Sink #(%d+)"
   for line in (text or ""):gmatch("[^\n]*") do
      local idx = line:match(head)
      if idx then
         dev = { index = tonumber(idx), name = "", description = "", monitor = false, class = "" }
         table.insert(list, dev)
         in_props = false
      elseif dev then
         local key, value = line:match("^\t(%S[^:]*): ?(.*)$")
         if key then
            in_props = key == "Properties"
            if key == "Name" then dev.name = trim(value)
            elseif key == "Description" then dev.description = trim(value)
            elseif key == "Monitor of Sink" and trim(value) ~= "n/a" then dev.monitor = true
            elseif key == "Active Port" then dev.port = trim(value)
            end
         elseif in_props then
            local k, v = line:match('^\t\t(%S+) = "(.*)"$')
            if k == "device.class" then dev.class = v
               if v == "monitor" then dev.monitor = true end
            end
         end
      end
   end
   return list
end

function M.default_sink(info) return (info or ""):match("Default Sink: ([^\n]+)") end
function M.default_source(info) return (info or ""):match("Default Source: ([^\n]+)") end

-- The user's own choices (Settings > Sound "Mode", or the card switched off while the session
-- watched): "card<TAB>profile" per line. A card listed here is never changed automatically.
function M.read_choices(path)
   local choices = {}
   local f = io.open(path or M.CHOICES, "r")
   if not f then return choices end
   for line in f:lines() do
      local card, profile = line:match("^([^#\t ][^\t]*)\t([^\t]+)$")
      if card then choices[card] = profile end
   end
   f:close()
   return choices
end

function M.write_choice(card, profile, path)
   path = path or M.CHOICES
   if not card:match("^[%w%._:%-]+$") or not profile:match("^[%w%._:+%-@]+$") then return false end
   local choices = M.read_choices(path)
   choices[card] = profile
   os.execute("mkdir -p " .. M.q(path:match("^(.*)/[^/]*$")))
   local tmp = path .. ".new"
   local f = io.open(tmp, "w")
   if not f then return false end
   f:write("# GoboRefined: sound card modes chosen by the user (gobo-sound-profile leaves these cards alone)\n")
   local names = {}
   for c in pairs(choices) do table.insert(names, c) end
   table.sort(names)
   for _, c in ipairs(names) do f:write(c, "\t", choices[c], "\n") end
   f:close()
   return os.rename(tmp, path)
end

local function hdmi_only(card)
   local any = false
   for _, p in ipairs(card.profiles) do
      if p.name ~= "off" then
         any = true
         if not (p.name .. " " .. p.description):lower():match("hdmi") and not p.description:match("DisplayPort") then
            return false
         end
      end
   end
   return any
end

-- The rule (0.8.5 brief, item 1a): for a card whose active profile is "off", the profile with
-- the highest priority among those marked available; when none is marked available, the
-- highest priority regardless of the flag. Returns profile (table) or nil, reason.
function M.choose(card, choices)
   if card.name:match("^bluez_card%.") then return nil, "Bluetooth device (left to module-bluetooth-policy)" end
   if choices and choices[card.name] then return nil, "the user chose \"" .. choices[card.name] .. "\"" end
   if card.active ~= "off" then return nil, "profile \"" .. card.active .. "\" is active" end
   if hdmi_only(card) then return nil, "only HDMI/DisplayPort profiles (graphics card sound)" end
   local best, best_any
   local function better(p, b) return not b or p.priority > b.priority end
   for _, p in ipairs(card.profiles) do
      if p.name ~= "off" and (p.sinks + p.sources) > 0 then
         if better(p, best_any) then best_any = p end
         if p.available ~= "no" and better(p, best) then best = p end
      end
   end
   if best then return best, "best available profile" end
   if best_any then return best_any, "no profile is marked available: highest priority" end
   return nil, "no other profile"
end

-- the sink to make default after a card was switched on: one of that card's sinks, not HDMI if
-- there is another; nil if none
function M.card_sink(card, sinks)
   local suffix = card.name:match("^alsa_card%.(.+)$")
   if not suffix then return nil end
   local pick
   for _, s in ipairs(sinks) do
      if not s.monitor and s.name:sub(1, #suffix + 13) == "alsa_output." .. suffix .. "." then
         local hdmi = (s.name .. " " .. s.description):lower():match("hdmi") ~= nil
         if not pick or (pick.hdmi and not hdmi) then pick = { name = s.name, hdmi = hdmi } end
      end
   end
   return pick and pick.name
end

return M
