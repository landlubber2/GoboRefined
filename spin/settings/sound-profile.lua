-- gobo-sound-profile (GoboRefined 0.8.5): switches on sound cards PulseAudio left "off".
--
-- Found on a ThinkPad (Intel Tiger Lake, SOF "sof-hda-dsp" card, UCM profile "HiFi"): PulseAudio 13
-- marks HiFi "available: no" (every jack reports "not available") and keeps the card on profile
-- "off", so only "Dummy Output" is offered; `pactl set-card-profile 0 HiFi` gives sound at once.
-- This program does that for every card, without knowing card names:
--   * a card whose active profile is "off" gets the profile with the highest priority among those
--     marked available, or, when none is marked available, the highest priority of all;
--   * then, if the default output is still the null sink (auto_null), one of that card's sinks
--     becomes the default (not HDMI when there is another);
--   * left alone: cards with any other profile (machines where sound works: nothing happens),
--     Bluetooth cards (module-bluetooth-policy decides), cards with only HDMI/DisplayPort profiles
--     (graphics cards), and cards the user set: Settings > Sound "Mode" writes the choice to
--     ~/.config/goborefined/sound-cards; a card switched to "off" while this program watches
--     (pavucontrol, pactl) is written there too, unless a jack changed at the same moment
--     (then it was PulseAudio's own reaction, and the rule runs again);
--   * 0.8.5 Bluetooth sound: a new Bluetooth output (bluez_sink.*) becomes the default output and
--     the playing streams move to it; when it goes away PulseAudio falls back by itself.
-- Started by ~/.xinitrc (one per user: flock in the launcher); it reads `pactl subscribe`, so a
-- card that appears later (USB, a restarted PulseAudio) is handled too.
--
--   gobo-sound-profile                 watch (the session)
--   gobo-sound-profile --once          apply the rule once and exit
--   gobo-sound-profile --dry-run       show what the rule would do, change nothing
--   gobo-sound-profile --fixture FILE [--choices FILE]
--                                      lab test: read `pactl list cards` output from FILE
--                                      (and the choices file), print the decisions, change nothing
-- Log: ~/.cache/gobo-sound-profile.log
local here = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local P = require("pactl")

local mode, fixture, choices_file = "watch", nil, nil
local i = 1
while arg[i] do
   local a = arg[i]
   if a == "--once" then mode = "once"
   elseif a == "--dry-run" then mode = "dry"
   elseif a == "--fixture" and arg[i + 1] then mode = "fixture"; fixture = arg[i + 1]; i = i + 1
   elseif a == "--choices" and arg[i + 1] then choices_file = arg[i + 1]; i = i + 1
   else io.stderr:write("usage: gobo-sound-profile [--once | --dry-run | --fixture FILE [--choices FILE]]\n"); os.exit(2)
   end
   i = i + 1
end

local LOG = (os.getenv("HOME") or "/tmp") .. "/.cache/gobo-sound-profile.log"
local function log(s)
   local line = os.date("%Y-%m-%d %H:%M:%S ") .. s
   if mode ~= "watch" and mode ~= "once" then print(s) return end
   if mode == "once" then print(s) end
   local f = io.open(LOG, "a")
   if f then
      if f:seek("end") > 65536 then f:close(); f = io.open(LOG, "w") end
      f:write(line, "\n")
      f:close()
   end
end

local function pactl(args) return P.read_cmd("pactl " .. args) end
local function run(args)
   if mode == "dry" or mode == "fixture" then log("would run: pactl " .. args) return true end
   local ok = os.execute("LC_ALL=C pactl " .. args .. " > /dev/null 2>&1")
   return ok == true or ok == 0
end

local last = {}   -- card name -> { active, ports } as last seen
local function ports_sig(card)
   local t = {}
   for _, p in ipairs(card.ports) do table.insert(t, p.name .. "=" .. p.available) end
   return table.concat(t, ",")
end

-- the rule, for every card (or only the card named `only`)
local function apply(cards_text, only)
   local cards = P.parse_cards(cards_text or pactl("list cards"))
   local choices = P.read_choices(choices_file)
   local switched = {}
   for _, card in ipairs(cards) do
      if not only or card.name == only then
         local profile, why = P.choose(card, choices)
         if profile then
            log(("card %s: off -> %s (%s; %s)"):format(card.name, profile.name, profile.description, why))
            if run("set-card-profile " .. P.q(card.name) .. " " .. P.q(profile.name)) then
               card.active = profile.name
               table.insert(switched, card)
            else
               log("card " .. card.name .. ": switching to " .. profile.name .. " failed")
            end
         else
            log(("card %s: left alone (%s)"):format(card.name, why))
         end
      end
      last[card.name] = { active = card.active, ports = ports_sig(card) }
   end
   if #switched > 0 and mode ~= "fixture" then
      local default = P.default_sink(pactl("info"))
      if mode == "dry" or default == "auto_null" then
         local sinks = P.parse_devices(pactl("list sinks"), "sink")
         for _, card in ipairs(switched) do
            local s = P.card_sink(card, sinks)
            if s then
               log("default output was " .. tostring(default) .. ": now " .. s)
               run("set-default-sink " .. P.q(s))
               break
            end
         end
      end
   end
end

-- a card changed while we watch: a switch to "off" that we did not make is the user's choice,
-- unless a jack changed at the same moment (PulseAudio's own reaction: run the rule again)
local function card_changed()
   local cards = P.parse_cards(pactl("list cards"))
   for _, card in ipairs(cards) do
      local before = last[card.name]
      local sig = ports_sig(card)
      if before and not card.name:match("^bluez_card%.") and card.active == "off" and before.active ~= "off" then
         if sig == before.ports then
            log("card " .. card.name .. ": switched off by the user, remembered (" .. (choices_file or P.CHOICES) .. ")")
            P.write_choice(card.name, "off", choices_file)
         else
            log("card " .. card.name .. ": went off together with a jack change; applying the rule")
            apply(nil, card.name)
         end
      end
      last[card.name] = { active = card.active, ports = sig }
   end
end

-- a new sink: a Bluetooth output becomes the default, the playing streams follow it
local function sink_added(index)
   for line in pactl("list short sinks"):gmatch("[^\n]+") do
      local idx, name = line:match("^(%d+)\t(%S+)")
      if tonumber(idx) == index and name:match("^bluez_sink%.") then
         log("Bluetooth output " .. name .. " appeared: default output, streams moved")
         run("set-default-sink " .. P.q(name))
         for l in pactl("list short sink-inputs"):gmatch("[^\n]+") do
            local input = l:match("^(%d+)")
            if input then run("move-sink-input " .. input .. " " .. P.q(name)) end
         end
      end
   end
end

if mode == "fixture" then
   local f = io.open(fixture, "r")
   if not f then io.stderr:write("cannot read " .. fixture .. "\n") os.exit(1) end
   local text = f:read("*a")
   f:close()
   apply(text)
   os.exit(0)
end
if mode == "dry" or mode == "once" then
   if not pactl("info"):match("Server Name") then log("PulseAudio is not running") os.exit(1) end
   apply()
   os.exit(0)
end

-- watch: PulseAudio may start a moment after us, or restart; give up after a minute without it
local misses = 0
while misses < 12 do
   if pactl("info"):match("Server Name") then
      misses = 0
      apply()
      local p = io.popen("LC_ALL=C pactl subscribe 2>/dev/null", "r")
      if p then
         for line in p:lines() do
            if line:match("^Event 'new' on card #") then
               apply()
            elseif line:match("^Event 'change' on card #") then
               card_changed()
            else
               local s = line:match("^Event 'new' on sink #(%d+)")
               if s then sink_added(tonumber(s)) end
            end
         end
         p:close()
      end
      log("lost the connection to PulseAudio")
   else
      misses = misses + 1
   end
   os.execute("sleep 5")
end
log("PulseAudio is not running: stopped")
