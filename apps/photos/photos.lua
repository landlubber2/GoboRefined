-- Photos for GoboRefined: one simple window for pictures and videos.
--   gobo-photos [FILE]
-- Pictures are shown by GdkPixbuf (JPEG, PNG, GIF, BMP, TIFF, SVG ...). Videos (MP4, MKV, WebM,
-- MOV, AVI ...) are played through FFmpeg, which is on the image: one ffmpeg process hands the
-- frames to this window as a stream of JPEG pictures, a second one plays the sound through
-- PulseAudio (pacat). No other libraries are needed.
-- Keys: Left/Right previous/next file in the folder, Space play/pause, + - 0 zoom, R rotate,
-- Delete moves the file to the Trash, F or F11 full screen, Escape leaves full screen / closes,
-- Ctrl+O open.
package.path = "/System/Aliens/LuaRocks/share/lua/5.3/?.lua;/System/Aliens/LuaRocks/share/lua/5.3/?/init.lua;" .. package.path
package.cpath = "/System/Aliens/LuaRocks/lib/lua/5.3/?.so;" .. package.cpath
local lgi = require("lgi")
lgi.GLib.set_prgname("gobo-photos")
lgi.GLib.set_application_name("Photos")
local Gtk = lgi.require("Gtk", "3.0")
local Gdk = lgi.require("Gdk", "3.0")
local GLib, Gio = lgi.GLib, lgi.Gio
local GdkPixbuf = lgi.require("GdkPixbuf", "2.0")

local IMAGE = { jpg = 1, jpeg = 1, jpe = 1, png = 1, gif = 1, bmp = 1, tif = 1, tiff = 1, svg = 1, ico = 1, xpm = 1, pnm = 1, tga = 1 }
local VIDEO = { mp4 = 1, m4v = 1, mkv = 1, webm = 1, mov = 1, avi = 1, mpg = 1, mpeg = 1, wmv = 1, flv = 1, ["3gp"] = 1, ogv = 1, ts = 1 }
local MAX_W, MAX_H, MAX_FPS = 1280, 720, 30

local function ext_of(name) return (name:match("%.([%w]+)$") or ""):lower() end
local function kind_of(name) local e = ext_of(name); return IMAGE[e] and "image" or (VIDEO[e] and "video" or nil) end
local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
local function pread(cmd)
   local p = io.popen(cmd .. " 2>/dev/null", "r")
   if not p then return "" end
   local s = p:read("*a") or ""
   p:close()
   return s
end
local function clock(sec)
   sec = math.max(0, math.floor(sec + 0.5))
   if sec >= 3600 then return string.format("%d:%02d:%02d", sec // 3600, sec % 3600 // 60, sec % 60) end
   return string.format("%d:%02d", sec // 60, sec % 60)
end

-- state ------------------------------------------------------------------------------
local files, index = {}, 0          -- the folder's pictures and videos (full paths), the current one
local current = nil                 -- { path, kind, pixbuf, ... }
local zoom, fit, pan_x, pan_y, rotation = 1, true, 0, 0, 0
local video = nil                   -- playback state of the current video
local fullscreen = false

local css = Gtk.CssProvider()
css:load_from_data([[
.photos-area { background-color: #111111; }
.photos-bar { padding: 4px 6px; }
.photos-side { border-radius: 24px; min-width: 44px; min-height: 44px; opacity: 0.75; }
.photos-hint { font-size: 13pt; color: #cfcfcf; }
]])
Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

-- the window fits the screen: on a small screen a fixed size would push the video controls under the taskbar
local screen = Gdk.Screen.get_default()
local window = Gtk.Window { title = "Photos", icon_name = "image-viewer",
   default_width = math.floor(math.min(1100, screen:get_width() * 0.8)), default_height = math.floor(math.min(760, screen:get_height() * 0.75)) }
window.on_destroy = function() Gtk.main_quit() end
local area = Gtk.DrawingArea { hexpand = true, vexpand = true, can_focus = true }
area:get_style_context():add_class("photos-area")
area:add_events(Gdk.EventMask.SCROLL_MASK | Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
   | Gdk.EventMask.BUTTON1_MOTION_MASK | Gdk.EventMask.SMOOTH_SCROLL_MASK)

local function icon_button(icon, tip, fn)
   local b = Gtk.Button { tooltip_text = tip, relief = Gtk.ReliefStyle.NONE, can_focus = false }
   b:add(Gtk.Image { icon_name = icon, pixel_size = 20 })
   b.on_clicked = function() fn() end
   return b
end
local hint = Gtk.Label { label = "", halign = Gtk.Align.CENTER, valign = Gtk.Align.CENTER, justify = Gtk.Justification.CENTER }
hint:get_style_context():add_class("photos-hint")
local title_label = Gtk.Label { label = "", ellipsize = "MIDDLE", xalign = 0, hexpand = true, margin_start = 8 }

local show, open_dialog, stop_video, start_video   -- forward

-- video ------------------------------------------------------------------------------
local play_btn_image = Gtk.Image { icon_name = "media-playback-start-symbolic", pixel_size = 20 }
local play_btn = Gtk.Button { relief = Gtk.ReliefStyle.NONE, can_focus = false, tooltip_text = "Play / pause (Space)" }
play_btn:add(play_btn_image)
local time_label = Gtk.Label { label = "0:00 / 0:00", width_chars = 15 }
local seek = Gtk.Scale { orientation = Gtk.Orientation.HORIZONTAL, draw_value = false, hexpand = true, can_focus = false }
seek:set_range(0, 1)
local mute_btn_image = Gtk.Image { icon_name = "audio-volume-high-symbolic", pixel_size = 20 }
local mute_btn = Gtk.Button { relief = Gtk.ReliefStyle.NONE, can_focus = false, tooltip_text = "Sound on / off" }
mute_btn:add(mute_btn_image)
local muted, seek_guard, seeking = false, false, false
local video_bar = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 6 }
video_bar:get_style_context():add_class("photos-bar")
video_bar:pack_start(play_btn, false, false, 0)
video_bar:pack_start(time_label, false, false, 0)
video_bar:pack_start(seek, true, true, 0)
video_bar:pack_start(mute_btn, false, false, 0)

local function kill_group(proc)
   if not proc then return end
   local pid = proc:get_identifier()
   if pid then os.execute("kill -TERM -- -" .. pid .. " 2>/dev/null") end
   proc:force_exit()
end
local function start_audio(v)
   if muted or not v.has_audio then return end
   local script = 'ffmpeg -v quiet -ss "$1" -i "$0" -vn -f s16le -ar 48000 -ac 2 - | '
      .. 'pacat --raw --format=s16le --rate=48000 --channels=2 --latency-msec=120 --client-name=Photos'
   local launcher = Gio.SubprocessLauncher.new({ "STDOUT_SILENCE", "STDERR_SILENCE" })
   v.audio = launcher:spawnv({ "setsid", "sh", "-c", script, v.path, string.format("%.3f", v.base + v.shown / v.fps) })
end
local function position(v) return v.base + v.shown / v.fps end
local function update_time(v)
   time_label.label = clock(position(v)) .. " / " .. clock(v.duration)
   if not seeking then
      seek_guard = true
      seek:set_value(position(v))
      seek_guard = false
   end
end

stop_video = function()
   local v = video
   if not v then return end
   v.gen = v.gen + 1
   v.playing = false
   if v.proc then v.proc:force_exit(); v.proc = nil end
   kill_group(v.audio); v.audio = nil
   if v.timer then GLib.source_remove(v.timer); v.timer = nil end
   play_btn_image.icon_name = "media-playback-start-symbolic"
end

-- start (or restart) playing the current video at "at" seconds
start_video = function(at)
   local v = video
   if not v then return end
   stop_video()
   if at >= v.duration - 0.2 then at = 0 end
   v.base, v.shown, v.t0, v.queue, v.buf, v.ended, v.reading = math.max(0, at), 0, nil, {}, "", false, true
   v.playing = true
   local gen = v.gen
   play_btn_image.icon_name = "media-playback-pause-symbolic"
   local launcher = Gio.SubprocessLauncher.new({ "STDOUT_PIPE", "STDERR_SILENCE" })
   v.proc = launcher:spawnv({ "ffmpeg", "-v", "quiet", "-ss", string.format("%.3f", v.base), "-i", v.path, "-an",
      "-vf", string.format("fps=%.3f,scale=w=%d:h=%d:force_original_aspect_ratio=decrease,scale=trunc(iw/2)*2:trunc(ih/2)*2", v.fps, MAX_W, MAX_H),
      "-f", "image2pipe", "-c:v", "mjpeg", "-q:v", "4", "-" })
   if not v.proc then v.playing = false; hint.label = "This video could not be started (ffmpeg is missing?)." return end
   local stream = v.proc:get_stdout_pipe()
   local read
   read = function()
      stream:read_bytes_async(262144, GLib.PRIORITY_DEFAULT, nil, function(s, res)
         if not video or video.gen ~= gen then return end
         local ok, bytes = pcall(s.read_bytes_finish, s, res)
         if not ok or not bytes or bytes:get_size() == 0 then
            v.eof = true
            v.reading = false
            return
         end
         v.buf = v.buf .. bytes.data
         while true do   -- cut complete JPEG pictures (they end with FF D9) off the buffer
            local e = v.buf:find("\255\217", 1, true)
            if not e then break end
            v.queue[#v.queue + 1] = v.buf:sub(1, e + 1)
            v.buf = v.buf:sub(e + 2)
         end
         if #v.queue < 6 then read() else v.reading = false end
      end)
   end
   v.eof = false
   v.resume_reading = function() if not v.reading and not v.eof then v.reading = true; read() end end
   read()
   v.timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 10, function()
      if not video or video.gen ~= gen then return false end
      if #v.queue == 0 then
         if v.eof then   -- the end
            v.timer = nil
            v.ended = true
            v.shown = math.floor((v.duration - v.base) * v.fps)
            stop_video()
            update_time(v)
            return false
         end
         return true
      end
      local now = GLib.get_monotonic_time()
      if not v.t0 then
         v.t0 = now
         start_audio(v)
      end
      local due = math.floor((now - v.t0) / 1e6 * v.fps) + 1
      local frame
      while v.shown < due and #v.queue > 0 do
         frame = table.remove(v.queue, 1)
         v.shown = v.shown + 1
      end
      if frame then
         local loader = GdkPixbuf.PixbufLoader()
         local ok = pcall(function() loader:write(frame) loader:close() end)
         local pb = ok and loader:get_pixbuf()
         if pb then
            current.pixbuf = pb
            hint.label = ""
            area:queue_draw()
         end
         if v.shown % 5 == 0 then update_time(v) end
      end
      if #v.queue < 3 then v.resume_reading() end
      return true
   end)
end

local function toggle_play()
   local v = video
   if not v then return end
   if v.playing then
      stop_video()
   else
      start_video(v.ended and 0 or position(v))
   end
end
play_btn.on_clicked = toggle_play
mute_btn.on_clicked = function()
   muted = not muted
   mute_btn_image.icon_name = muted and "audio-volume-muted-symbolic" or "audio-volume-high-symbolic"
   local v = video
   if v and v.playing then
      if muted then kill_group(v.audio); v.audio = nil else start_audio(v) end
   end
end
seek.on_button_press_event = function() seeking = true return false end
seek.on_button_release_event = function()
   seeking = false
   if video then start_video(seek:get_value()) end
   return false
end
seek.on_value_changed = function()
   if seek_guard or not video then return end
   time_label.label = clock(seek:get_value()) .. " / " .. clock(video.duration)
end

-- showing a file ---------------------------------------------------------------------
local function list_folder(path)
   local dir = path:match("^(.*)/[^/]*$")
   if dir == "" then dir = "/" end
   local list = {}
   for name in pread("ls -1A -- " .. q(dir)):gmatch("[^\n]+") do
      if kind_of(name) then list[#list + 1] = (dir == "/" and "" or dir) .. "/" .. name end
   end
   table.sort(list, function(a, b) return a:lower() < b:lower() end)
   files, index = list, 0
   for i, f in ipairs(list) do if f == path then index = i end end
   if index == 0 then table.insert(files, 1, path); index = 1 end
end

show = function(path)
   stop_video()
   video = nil
   zoom, fit, pan_x, pan_y, rotation = 1, true, 0, 0, 0
   local name = path:match("[^/]*$")
   current = { path = path, kind = kind_of(name) or "image" }
   window.title = name .. " - Photos"
   title_label.label = name .. (#files > 1 and string.format("   (%d of %d)", index, #files) or "")
   hint.label = ""
   if current.kind == "video" then
      local info = pread("ffprobe -v error -show_entries stream=codec_type,r_frame_rate:format=duration -of default=nw=1 " .. q(path))
      local duration = tonumber(info:match("duration=([%d.]+)")) or 0
      local has_video, has_audio, fps = false, false, 25
      local kind
      for line in info:gmatch("[^\n]+") do
         local n, d = line:match("^r_frame_rate=(%d+)/(%d+)")
         if n and tonumber(d) > 0 and tonumber(n) > 0 and not has_video then fps = tonumber(n) / tonumber(d) end
         local t = line:match("^codec_type=(%w+)")
         if t == "video" then has_video = true elseif t == "audio" then has_audio = true end
         kind = t or kind
      end
      if not has_video or duration <= 0 then
         hint.label = "This video cannot be played\n(" .. name .. ")"
         video_bar:hide()
      else
         if fps > MAX_FPS or fps < 1 then fps = MAX_FPS end
         video = { path = path, duration = duration, fps = fps, has_audio = has_audio, gen = 0, base = 0, shown = 0 }
         seek_guard = true
         seek:set_range(0, duration)
         seek:set_value(0)
         seek_guard = false
         video_bar:show_all()
         video_bar:show()
         start_video(0)
      end
   else
      video_bar:hide()
      local ok, pb = pcall(GdkPixbuf.Pixbuf.new_from_file, path)
      if ok and pb then
         current.pixbuf = pb:apply_embedded_orientation() or pb
      else
         hint.label = "This file cannot be shown\n(" .. name .. ")"
      end
   end
   area:queue_draw()
end

local function go(step)
   if #files < 2 then return end
   index = (index - 1 + step) % #files + 1
   show(files[index])
end
local function open(path)
   local real = pread("readlink -f -- " .. q(path)):gsub("\n$", "")
   if real == "" then real = path end
   list_folder(real)
   show(real)
end
open_dialog = function()
   local d = Gtk.FileChooserDialog { title = "Open a picture or video", action = Gtk.FileChooserAction.OPEN, transient_for = window, modal = true }
   d:add_button("Cancel", Gtk.ResponseType.CANCEL)
   d:add_button("Open", Gtk.ResponseType.ACCEPT)
   local filter = Gtk.FileFilter()
   filter:set_name("Pictures and videos")
   for e in pairs(IMAGE) do filter:add_pattern("*." .. e); filter:add_pattern("*." .. e:upper()) end
   for e in pairs(VIDEO) do filter:add_pattern("*." .. e); filter:add_pattern("*." .. e:upper()) end
   d:add_filter(filter)
   local start = current and current.path:match("^(.*)/[^/]*$") or ((os.getenv("HOME") or "") .. "/Pictures")
   if pread("test -d " .. q(start) .. " && echo d") == "" then start = os.getenv("HOME") or "/" end
   d:set_current_folder(start)
   local file
   if d:run() == Gtk.ResponseType.ACCEPT then file = d:get_filename() end
   d:destroy()
   if file then open(file) end
end

local function set_zoom(z)
   if not current or current.kind ~= "image" or not current.pixbuf then return end
   fit = false
   zoom = math.max(0.05, math.min(16, z))
   area:queue_draw()
end
local function fit_scale(pw, ph)
   local w, h = area:get_allocated_width(), area:get_allocated_height()
   return math.min(w / pw, h / ph)
end
local function current_scale()
   local pb = current and current.pixbuf
   if not pb then return 1 end
   local pw, ph = pb:get_width(), pb:get_height()
   if rotation % 180 ~= 0 then pw, ph = ph, pw end
   local f = fit_scale(pw, ph)
   if current.kind == "video" then return f end
   return fit and math.min(f, 1) or zoom
end
local function rotate()
   if not current or current.kind ~= "image" then return end
   rotation = (rotation + 90) % 360
   area:queue_draw()
end
local function delete_current()
   if not current or #files == 0 then return end
   local name = current.path:match("[^/]*$")
   local d = Gtk.MessageDialog { transient_for = window, modal = true, message_type = Gtk.MessageType.QUESTION,
      buttons = Gtk.ButtonsType.NONE, text = "Move \"" .. name .. "\" to the Trash?" }
   d:add_button("Cancel", Gtk.ResponseType.CANCEL)
   d:add_button("Move to Trash", Gtk.ResponseType.OK)
   local yes = d:run() == Gtk.ResponseType.OK
   d:destroy()
   if not yes then return end
   stop_video()
   local ok, err = pcall(function() return assert(Gio.File.new_for_path(current.path):trash(nil)) end)
   if not ok then
      local e = Gtk.MessageDialog { transient_for = window, modal = true, message_type = Gtk.MessageType.ERROR,
         buttons = Gtk.ButtonsType.OK, text = "The file could not be moved to the Trash.\n" .. tostring(err):gsub("^.-: ", "") }
      e:run(); e:destroy()
      return
   end
   table.remove(files, index)
   if #files == 0 then
      current, video = nil, nil
      video_bar:hide()
      window.title = "Photos"
      title_label.label = ""
      hint.label = "No more pictures or videos in this folder."
      area:queue_draw()
   else
      if index > #files then index = 1 end
      show(files[index])
   end
end
local function toggle_fullscreen()
   fullscreen = not fullscreen
   if fullscreen then window:fullscreen() else window:unfullscreen() end
end

-- drawing ----------------------------------------------------------------------------
area.on_draw = function(_, cr)
   local w, h = area:get_allocated_width(), area:get_allocated_height()
   cr:set_source_rgb(0.067, 0.067, 0.067)
   cr:paint()
   local pb = current and current.pixbuf
   if not pb then return true end
   local s = current_scale()
   local pw, ph = pb:get_width(), pb:get_height()
   cr:translate(w / 2 + pan_x, h / 2 + pan_y)
   if current.kind == "image" and rotation ~= 0 then cr:rotate(math.rad(rotation)) end
   cr:scale(s, s)
   Gdk.cairo_set_source_pixbuf(cr, pb, -pw / 2, -ph / 2)
   pcall(function() cr:get_source():set_filter(s < 1 and "GOOD" or "BILINEAR") end)
   cr:paint()
   return true
end
area.on_scroll_event = function(_, ev)
   if not current or current.kind ~= "image" then return false end
   local up = ev.direction == "UP" or (ev.direction == "SMOOTH" and ev.delta_y < 0)
   local down = ev.direction == "DOWN" or (ev.direction == "SMOOTH" and ev.delta_y > 0)
   if up then set_zoom(current_scale() * 1.15) elseif down then set_zoom(current_scale() / 1.15) end
   return true
end
local drag
area.on_button_press_event = function(_, ev)
   area:grab_focus()
   if ev.type == "DOUBLE_BUTTON_PRESS" or ev.type == "2BUTTON_PRESS" then toggle_fullscreen() return true end
   if ev.button == 1 then
      if current and current.kind == "video" then toggle_play() return true end
      drag = { x = ev.x, y = ev.y, px = pan_x, py = pan_y }
   end
   return true
end
area.on_button_release_event = function() drag = nil return true end
area.on_motion_notify_event = function(_, ev)
   if drag and current and current.kind == "image" and not fit then
      pan_x, pan_y = drag.px + ev.x - drag.x, drag.py + ev.y - drag.y
      area:queue_draw()
   end
   return true
end

-- layout -----------------------------------------------------------------------------
local bar = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 2 }
bar:get_style_context():add_class("photos-bar")
bar:pack_start(icon_button("document-open-symbolic", "Open... (Ctrl+O)", function() open_dialog() end), false, false, 0)
bar:pack_start(title_label, true, true, 0)
bar:pack_start(icon_button("zoom-out-symbolic", "Smaller (-)", function() set_zoom(current_scale() / 1.25) end), false, false, 0)
bar:pack_start(icon_button("zoom-fit-best-symbolic", "Fit to the window (0)", function() fit = true; pan_x, pan_y = 0, 0; area:queue_draw() end), false, false, 0)
bar:pack_start(icon_button("zoom-in-symbolic", "Larger (+)", function() set_zoom(current_scale() * 1.25) end), false, false, 0)
bar:pack_start(icon_button("object-rotate-right-symbolic", "Turn (R) - only how it is shown, the file is not changed", rotate), false, false, 0)
bar:pack_start(icon_button("user-trash-symbolic", "Move to the Trash (Delete)", delete_current), false, false, 0)
bar:pack_start(icon_button("view-fullscreen-symbolic", "Full screen (F11)", toggle_fullscreen), false, false, 0)

local overlay = Gtk.Overlay()
overlay:add(area)
overlay:add_overlay(hint)
overlay:set_overlay_pass_through(hint, true)
local function side(icon, align, step)
   local b = Gtk.Button { halign = align, valign = Gtk.Align.CENTER, margin = 10, can_focus = false }
   b:add(Gtk.Image { icon_name = icon, pixel_size = 24 })
   b:get_style_context():add_class("photos-side")
   b.on_clicked = function() go(step) end
   overlay:add_overlay(b)
end
side("go-previous-symbolic", Gtk.Align.START, -1)
side("go-next-symbolic", Gtk.Align.END, 1)

local root = Gtk.Box { orientation = Gtk.Orientation.VERTICAL }
root:pack_start(bar, false, false, 0)
root:pack_start(overlay, true, true, 0)
root:pack_start(video_bar, false, false, 0)
window:add(root)

window.on_key_press_event = function(_, ev)
   local k = ev.keyval
   local ctrl = ev.state.CONTROL_MASK
   if k == Gdk.KEY_Escape then
      if fullscreen then toggle_fullscreen() else window:destroy() end
   elseif k == Gdk.KEY_Left or k == Gdk.KEY_Page_Up or k == Gdk.KEY_BackSpace then go(-1)
   elseif k == Gdk.KEY_Right or k == Gdk.KEY_Page_Down then go(1)
   elseif k == Gdk.KEY_space then if video then toggle_play() else go(1) end
   elseif k == Gdk.KEY_plus or k == Gdk.KEY_equal or k == Gdk.KEY_KP_Add then set_zoom(current_scale() * 1.25)
   elseif k == Gdk.KEY_minus or k == Gdk.KEY_KP_Subtract then set_zoom(current_scale() / 1.25)
   elseif k == Gdk.KEY_0 or k == Gdk.KEY_KP_0 then fit = true; pan_x, pan_y = 0, 0; area:queue_draw()
   elseif k == Gdk.KEY_1 then set_zoom(1)
   elseif k == Gdk.KEY_r or k == Gdk.KEY_R then rotate()
   elseif k == Gdk.KEY_Delete then delete_current()
   elseif k == Gdk.KEY_F11 or k == Gdk.KEY_f or k == Gdk.KEY_F then toggle_fullscreen()
   elseif (k == Gdk.KEY_o or k == Gdk.KEY_O) and ctrl then open_dialog()
   else return false end
   return true
end

window:show_all()
video_bar:hide()
area:grab_focus()
if arg[1] and arg[1] ~= "" then
   local p = arg[1]:gsub("^file://", "")
   open(p)
else
   hint.label = "Open a picture or a video:  the folder button on the top left, or Ctrl+O"
end
Gtk.main()
stop_video()
