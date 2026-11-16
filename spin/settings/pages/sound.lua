-- Sound (0.8.5): output and input device, and a "Mode" chooser per sound card, plus the full
-- sound control (pavucontrol). Everything goes through `pactl` as the user (PulseAudio 13 of the
-- session); a `pactl subscribe` keeps the page current (devices plugged in, Bluetooth audio
-- connecting, changes made in pavucontrol).
--   * output/input: the default sink/source; choosing one also moves what is playing/recording
--     (PulseAudio remembers the default itself: module-default-device-restore);
--   * Mode: every profile of the card by its description, "(not detected)" for profiles PulseAudio
--     marks unavailable (still selectable: on the ThinkPad the working "HiFi" profile is one).
--     PulseAudio remembers it (module-card-restore) and the choice goes into
--     ~/.config/goborefined/sound-cards, so gobo-sound-profile never changes that card again.
local P = { id = "sound", title = "Sound", icon = "audio-volume-high" }

function P.build(C)
   local Gtk, GLib, Gio = C.Gtk, C.GLib, C.Gio
   local A = require("pactl")
   local outer, box = C.page("Sound", "Where sound plays and which microphone records. The volume of each program is in the full sound control.")
   local status = C.text("")
   local out_box = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 4 }
   local in_box = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 4 }
   local card_grid = Gtk.Grid { row_spacing = 8, column_spacing = 12 }
   local setting = false

   local function pactl(args, on_done)
      local argv = { "pactl" }
      for _, a in ipairs(args) do table.insert(argv, a) end
      C.run(argv, "", function(ok, out)
         if not ok then status.label = "Could not change it: " .. C.trim(out) end
         if on_done then on_done(ok) end
      end)
   end

   -- the default device, and what is playing (recording) moves along
   local function make_default(kind, name)
      pactl({ kind == "sink" and "set-default-sink" or "set-default-source", name }, function(ok)
         if not ok then return end
         local list = A.read_cmd("pactl list short " .. (kind == "sink" and "sink-inputs" or "source-outputs"))
         for line in list:gmatch("[^\n]+") do
            local idx = line:match("^(%d+)")
            if idx then pactl({ kind == "sink" and "move-sink-input" or "move-source-output", idx, name }) end
         end
      end)
   end

   local function device_list(container, kind, devices, default)
      C.clear(container)
      local group
      local n = 0
      for _, d in ipairs(devices) do
         if not d.monitor and d.name ~= "auto_null" then
            n = n + 1
            local label = d.description ~= "" and d.description or d.name
            local rb = Gtk.RadioButton { label = label, group = group }
            group = group or rb
            rb.active = d.name == default
            rb.on_toggled = function(b)
               if setting or not b.active then return end
               status.label = ""
               make_default(kind, d.name)
            end
            container:pack_start(rb, false, false, 0)
         end
      end
      if n == 0 then
         container:pack_start(C.text(kind == "sink"
            and "No sound output is working. If a sound card is listed below, try another Mode."
            or "No microphone or other input found.", "dim-label"), false, false, 0)
      end
      container:show_all()
   end

   local function card_rows(cards)
      C.clear(card_grid)
      if #cards == 0 then
         card_grid:attach(C.text("PulseAudio sees no sound card.", "dim-label"), 0, 0, 2, 1)
      end
      for i, card in ipairs(cards) do
         local name = card.description ~= "" and card.description or card.name
         local l = C.text(name, "gobo-value")
         l.max_width_chars = 34
         card_grid:attach(l, 0, i - 1, 1, 1)
         local combo = Gtk.ComboBoxText { hexpand = false }
         for _, p in ipairs(card.profiles) do
            local text = p.description ~= "" and p.description or p.name
            if p.available == "no" and p.name ~= "off" then text = text .. " (not detected)" end
            combo:append(p.name, text)
         end
         combo:set_active_id(card.active)
         combo.on_changed = function(cb)
            if setting then return end
            local id = cb:get_active_id()
            if not id or id == card.active then return end
            status.label = ""
            A.write_choice(card.name, id)
            pactl({ "set-card-profile", card.name, id })
         end
         card_grid:attach(C.row(Gtk.Label { label = "Mode", xalign = 0 }, combo), 1, i - 1, 1, 1)
      end
      card_grid:show_all()
   end

   local function refresh()
      setting = true
      local info = A.read_cmd("pactl info")
      if not info:match("Server Name") then
         status.label = "The sound service (PulseAudio) is not running for this session."
         C.clear(out_box); C.clear(in_box); C.clear(card_grid)
         setting = false
         return
      end
      if status.label:match("^The sound service") then status.label = "" end
      device_list(out_box, "sink", A.parse_devices(A.read_cmd("pactl list sinks"), "sink"), A.default_sink(info))
      device_list(in_box, "source", A.parse_devices(A.read_cmd("pactl list sources"), "source"), A.default_source(info))
      card_rows(A.parse_cards(A.read_cmd("pactl list cards")))
      setting = false
   end

   -- follow PulseAudio's changes (debounced)
   local pending = false
   local function schedule()
      if pending then return end
      pending = true
      GLib.timeout_add(GLib.PRIORITY_DEFAULT, 400, function() pending = false; refresh(); return false end)
   end
   local watcher
   local function watch()
      local launcher = Gio.SubprocessLauncher.new({ "STDOUT_PIPE", "STDERR_SILENCE" })
      launcher:setenv("LC_ALL", "C", true)
      watcher = launcher:spawnv({ "pactl", "subscribe" })
      if not watcher then return end
      local stream = Gio.DataInputStream.new(watcher:get_stdout_pipe())
      local function next_line()
         stream:read_line_async(GLib.PRIORITY_DEFAULT, nil, function(s, res)
            local line = s:read_line_finish_utf8(res)
            if not line then watcher = nil return end
            if line:match("on card") or line:match("on sink #") or line:match("on source #") or line:match("on server") then
               schedule()
            end
            next_line()
         end)
      end
      next_line()
   end
   if C.window then
      C.window.on_destroy:connect(function() if watcher then pcall(function() watcher:force_exit() end) end end)
   end

   box:pack_start(status, false, false, 0)
   box:pack_start(C.heading("Output"), false, false, 0)
   box:pack_start(out_box, false, false, 0)
   box:pack_start(C.heading("Input"), false, false, 0)
   box:pack_start(in_box, false, false, 0)
   box:pack_start(C.heading("Sound cards"), false, false, 0)
   box:pack_start(C.text("If a card plays nothing, try another Mode. \"(not detected)\" only means PulseAudio could not check it; such a mode often works.", "dim-label"), false, false, 0)
   box:pack_start(card_grid, false, false, 0)
   box:pack_start(C.button("Open the full sound control", function() C.spawn({ "pavucontrol" }) end, "suggested-action"), false, false, 0)
   box:pack_start(C.text("The speaker icon on the taskbar: scroll for the volume, right click to switch the output.", "dim-label"), false, false, 0)
   refresh()
   watch()
   return outer
end

return P
