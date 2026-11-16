-- Device Manager (0.9.2): every device by category, whether it has a driver, and for the ones
-- that do not: which of the four cases it is and where to look (devices.lua has the logic).
-- Administrators get three actions through gobo-settings-helper; everyone else reads.
local P = { id = "devices", title = "Device Manager", icon = "preferences-desktop-peripherals" }

local MARK = { ok = "●", partial = "●", inactive = "●", firmware = "●", nodriver = "●", disabled = "●", info = "" }
local COLOR = { ok = "#2e9e4f", partial = "#d99a00", inactive = "#d99a00", firmware = "#d99a00", nodriver = "#d63b3b", disabled = "#8a8a8a" }

function P.build(C)
   local Gtk, GLib = C.Gtk, C.GLib
   local lgi = require("lgi")
   local GObject, Gdk = lgi.GObject, lgi.require("Gdk", "3.0")
   local D = require("devices")
   local admin = C.kind() == "admin"
   local function esc(s) return GLib.markup_escape_text(tostring(s or ""), -1) end

   local outer = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 10, margin = 22 }
   local title = Gtk.Label { label = "Device Manager", xalign = 0 }
   title:get_style_context():add_class("gobo-title")
   outer:pack_start(title, false, false, 0)
   local summary = Gtk.Label { xalign = 0, use_markup = true }
   outer:pack_start(summary, false, false, 0)
   local notebook = Gtk.Notebook()
   outer:pack_start(notebook, true, true, 0)

   -- tab 1: the tree and the details -------------------------------------------------
   local COL = { ICON = 1, TEXT = 2, STATE = 3, KEY = 4 }
   local store = Gtk.TreeStore.new { GObject.Type.STRING, GObject.Type.STRING, GObject.Type.STRING, GObject.Type.STRING }
   local view = Gtk.TreeView { model = store, headers_visible = false, enable_search = true, search_column = COL.TEXT - 1 }
   view:append_column(Gtk.TreeViewColumn { title = "", { Gtk.CellRendererPixbuf {}, { icon_name = COL.ICON } } })
   view:append_column(Gtk.TreeViewColumn { title = "Device", expand = true,
      { Gtk.CellRendererText { ellipsize = "END" }, { markup = COL.TEXT }, expand = true } })
   view:append_column(Gtk.TreeViewColumn { title = "State", { Gtk.CellRendererText {}, { markup = COL.STATE } } })
   local tree_scroll = Gtk.ScrolledWindow { hscrollbar_policy = Gtk.PolicyType.NEVER, width_request = 430 }
   tree_scroll:add(view)

   local details = Gtk.Label { xalign = 0, yalign = 0, wrap = true, selectable = true, use_markup = true, max_width_chars = 46 }
   local actions = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 8 }
   local detail_box = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 12, margin = 14 }
   detail_box:pack_start(details, false, false, 0)
   detail_box:pack_start(actions, false, false, 0)
   local detail_scroll = Gtk.ScrolledWindow { hscrollbar_policy = Gtk.PolicyType.NEVER }
   detail_scroll:add(detail_box)
   local tab1 = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL }
   tab1:pack_start(tree_scroll, false, false, 0)
   tab1:pack_start(Gtk.Separator { orientation = Gtk.Orientation.VERTICAL }, false, false, 0)
   tab1:pack_start(detail_scroll, true, true, 0)
   notebook:append_page(tab1, Gtk.Label { label = "Devices" })

   -- tab 2: find a driver --------------------------------------------------------------
   local cards = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 14, margin = 16 }
   local cards_scroll = Gtk.ScrolledWindow { hscrollbar_policy = Gtk.PolicyType.NEVER }
   cards_scroll:add(cards)
   notebook:append_page(cards_scroll, Gtk.Label { label = "Find a driver" })

   local M, last_text, by_key, selected_key = nil, nil, {}, nil
   local refresh

   local function open_url(url)
      if url then C.spawn({ "firefox", url }) end
   end
   local function helper_action(args, done_text)
      C.helper(args, nil, function(ok, out)
         if ok then
            if done_text then C.message(done_text .. (C.trim(out) ~= "" and ("\n\n" .. C.trim(out)) or "")) end
         else C.error(C.clean_error(out)) end
         last_text = nil
         refresh()
      end)
   end
   local function action_buttons(dev, box)
      if not admin then return end
      if dev.state == "inactive" and dev.why ~= "cdmode" and (dev.bus == "pci" or dev.bus == "usb") then
         box:pack_start(C.button("Try to start the driver", function()
            helper_action({ "device-start", dev.bus, dev.addr }, "The driver was asked to start. The list shows whether it took the device.")
         end, "suggested-action"), false, false, 0)
      end
      if dev.state == "disabled" and dev.why == "soft" then
         box:pack_start(C.button("Unblock", function() helper_action({ "device-unblock", dev.bus, dev.addr }) end, "suggested-action"), false, false, 0)
      end
   end
   local function lookup_buttons(dev, box)
      if dev.bus ~= "pci" and dev.bus ~= "usb" then return end
      box:pack_start(C.button("Look up on linux-hardware.org", function()
         open_url(D.lookup_url("hardware", dev.bus, dev.vendor, dev.product))
      end), false, false, 0)
      box:pack_start(C.button("Search the kernel driver database", function()
         open_url(D.lookup_url("lkddb", dev.bus, dev.vendor, dev.product))
      end), false, false, 0)
   end

   local function show_details(dev)
      C.clear(actions)
      if not dev then
         details.label = "<span alpha='60%'>Choose a device on the left.</span>"
         return
      end
      local t = { "<span size='large' weight='bold'>" .. esc(dev.name) .. "</span>" }
      local function add(k, v) if v and v ~= "" then t[#t + 1] = "<b>" .. esc(k) .. "</b>  " .. esc(v) end end
      if dev.state ~= "info" then
         t[#t + 1] = "<span foreground='" .. COLOR[dev.state] .. "'>●</span> " .. esc(D.STATE_TEXT[dev.state])
            .. ((dev.state == "partial" and dev.why) and (": " .. esc(dev.why)) or "")
      end
      add("Maker", dev.vendor_name)
      add("Hardware ID", dev.id ~= "" and dev.id or nil)
      add("Connected", dev.where)
      add("Driver", dev.driver and (dev.driver .. (dev.unbound_interfaces and dev.unbound_interfaces > 0
         and "  (a part of the device has no driver)" or "")) or nil)
      if dev.driver and not dev.driver:match(",") then
         local info = C.pread("modinfo -F description " .. C.q(dev.driver) .. " 2>/dev/null | head -n 1")
         local ver = C.pread("modinfo -F version " .. C.q(dev.driver) .. " 2>/dev/null | head -n 1")
         if C.trim(info) ~= "" then add("About the driver", C.trim(info) .. (C.trim(ver) ~= "" and (", version " .. C.trim(ver)) or ""))
         else add("About the driver", "built into the kernel") end
      end
      if not dev.driver and #dev.modules > 0 then add("Driver on this system", table.concat(dev.modules, ", ")) end
      for _, f in ipairs(dev.firmware) do add("Firmware asked for", f.file .. (f.present and " (present)" or " (missing)")) end
      if dev.known and dev.why ~= "cdmode" then add("Known", dev.known.text) end
      local why = D.explain(dev, M)
      if why ~= "" and dev.state ~= "ok" then t[#t + 1] = "\n" .. esc(why) end
      if #dev.messages > 0 then
         t[#t + 1] = "\n<b>Kernel messages</b>"
         for i = math.max(1, #dev.messages - 5), #dev.messages do t[#t + 1] = "<tt><small>" .. esc(dev.messages[i]) .. "</small></tt>" end
      end
      details.label = table.concat(t, "\n")
      action_buttons(dev, actions)
      actions:pack_start(C.button("Copy details", function()
         Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD):set_text(D.device_text(dev, M), -1)
      end), false, false, 0)
      actions:show_all()
   end

   view:get_selection().on_changed = function(sel)
      local model, iter = sel:get_selected()
      if not iter then return end
      selected_key = model[iter][COL.KEY]
      show_details(by_key[selected_key])
   end

   local function build_cards()
      C.clear(cards)
      local n = 0
      for _, dev in ipairs(M.devices) do
         if D.PROBLEM[dev.state] then
            n = n + 1
            local frame = Gtk.Frame()
            local box = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 8, margin = 12 }
            local head = Gtk.Label { xalign = 0, use_markup = true, wrap = true,
               label = "<b>" .. esc(dev.name) .. "</b>   <span foreground='" .. COLOR[dev.state] .. "'>● " .. esc(D.STATE_TEXT[dev.state]) .. "</span>   <tt>" .. esc(dev.id) .. "</tt>" }
            box:pack_start(head, false, false, 0)
            box:pack_start(C.text(D.explain(dev, M)), false, false, 0)
            for _, f in ipairs(dev.firmware) do
               box:pack_start(C.text("Firmware file the kernel asked for: " .. f.file .. (f.present and " (it is on this system now: restart, or use Rescan devices)" or " (not on this system)"), "dim-label"), false, false, 0)
            end
            if #dev.messages > 0 then box:pack_start(C.text("Kernel: " .. dev.messages[#dev.messages], "dim-label"), false, false, 0) end
            local row = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 8 }
            action_buttons(dev, row)
            lookup_buttons(dev, row)
            box:pack_start(row, false, false, 0)
            frame:add(box)
            cards:pack_start(frame, false, false, 0)
         end
      end
      if n == 0 then
         cards:pack_start(C.text("Every device that needs a driver has one. Nothing to look for."), false, false, 0)
      end
      cards:pack_start(C.heading("Look up any device on the web"), false, false, 0)
      cards:pack_start(C.text("Linux has no driver download service like Windows: drivers are part of the kernel and come with GoboRefined updates. These buttons open the web browser at public hardware databases. Nothing is sent by itself; when you press a button, only the hardware ID (or the words you typed) goes to that web site.", "dim-label"), false, false, 0)
      local entry = Gtk.Entry { placeholder_text = "Hardware ID (8086:9a49) or a name", width_chars = 34 }
      local function search()
         local a, b = D.search_url(entry.text)
         if not a then C.error("Type a hardware ID like 8086:9a49, or a name made of letters, digits and spaces.") return end
         open_url(a)
         if b then
            if C.confirm("An ID alone does not say whether the device is USB or built in (PCI). The USB page was opened. Open the PCI page too?", "Open") then open_url(b) end
         end
      end
      entry.on_activate = search
      cards:pack_start(C.row(entry, C.button("Search", search)), false, false, 0)
      cards:show_all()
   end

   refresh = function()
      local model, text = D.scan()
      if text == last_text then return end
      last_text, M, by_key = text, model, {}
      store:clear()
      local first_problem, reselect
      for _, c in ipairs(D.CATEGORIES) do
         local list, bad = {}, 0
         for _, dev in ipairs(M.devices) do
            if dev.category == c[1] then
               list[#list + 1] = dev
               if D.PROBLEM[dev.state] then bad = bad + 1 end
            end
         end
         if #list > 0 then
            local parent = store:append(nil, { [COL.ICON] = c[3], [COL.TEXT] = "<b>" .. esc(c[2]) .. "</b>",
               [COL.STATE] = bad > 0 and ("<span foreground='#d63b3b'><b>" .. bad .. " !</b></span>") or "", [COL.KEY] = "" })
            for _, dev in ipairs(list) do
               local key = dev.bus .. " " .. dev.addr
               by_key[key] = dev
               local iter = store:append(parent, { [COL.ICON] = "", [COL.TEXT] = esc(dev.name),
                  [COL.STATE] = dev.state == "info" and "" or ("<span foreground='" .. COLOR[dev.state] .. "'>" .. MARK[dev.state] .. "</span> " .. esc(D.STATE_TEXT[dev.state])),
                  [COL.KEY] = key })
               if D.PROBLEM[dev.state] and not first_problem then first_problem = iter end
               if key == selected_key then reselect = iter end
            end
            if bad > 0 then view:expand_row(store:get_path(parent), false) end
         end
      end
      summary.label = M.problems == 0 and "<span foreground='#2e9e4f'>●</span> All devices have a driver."
         or ("<span foreground='#d99a00'>●</span> <b>" .. M.problems .. (M.problems == 1 and " device needs" or " devices need") .. " attention.</b>")
      local target = reselect or first_problem
      if target then
         local path = store:get_path(target)
         view:expand_to_path(path)
         view:get_selection():select_iter(target)
         view:scroll_to_cell(path, nil, true, 0.3, 0)
      else
         show_details(nil)
      end
      build_cards()
   end

   -- bottom row ----------------------------------------------------------------------
   local bottom = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 8 }
   if admin then
      bottom:pack_start(C.button("Rescan devices", function() helper_action({ "device-rescan" }) end), false, false, 0)
      bottom:pack_start(C.button("Read kernel messages", function() helper_action({ "device-log" }) end), false, false, 0)
   end
   local report_btn
   report_btn = C.button("Save report", function()
      report_btn.sensitive = false
      C.run({ "gobo-report" }, nil, function(_, out)
         report_btn.sensitive = true
         local path = out:match("written to (%S+)")
         if path then C.message("The report (the device list on top) was saved as\n" .. path .. "\n\nFor a device marked yellow or red, please send this file to the maintainer.")
         else C.error("The report could not be written:\n" .. out) end
      end)
   end)
   bottom:pack_start(report_btn, false, false, 0)
   if not admin then
      bottom:pack_start(C.text("Starting a driver and rescanning need an administrator's account.", "dim-label"), false, false, 0)
   end
   outer:pack_start(bottom, false, false, 0)

   refresh()
   local alive = true
   outer.on_destroy = function() alive = false end
   GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT_IDLE, 5, function()
      if not alive then return false end
      if outer:get_mapped() then pcall(refresh) end
      return true
   end)
   return outer
end

return P
