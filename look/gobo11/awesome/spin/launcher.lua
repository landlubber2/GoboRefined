-- A Start-style launcher: a popup above the taskbar with a search box and a
-- list of installed applications. Type to filter, Up/Down to choose, Enter to
-- start, Escape (or a click outside) to close. If nothing matches, Enter runs
-- what was typed as a command.

local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local beautiful = require("beautiful")
local menu_gen = require("menubar.menu_gen")

local launcher = {}

local WIDTH, ROWS, ROW_H = 520, 8, 44
local apps = {}        -- { name, cmdline, icon }
local matches = {}
local selected, offset = 1, 0
local popup, backdrop, prompt_box, list_layout, hint
local on_power         -- callback for the power button
local open = false

local function p() return beautiful.palette end

local function load_apps()
   menu_gen.generate(function(entries)
      local seen, list = {}, {}
      for _, e in ipairs(entries) do
         if e.name and e.cmdline and not seen[e.name] then
            seen[e.name] = true
            table.insert(list, { name = e.name, cmdline = e.cmdline, icon = e.icon })
         end
      end
      table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
      apps = list
   end)
end

local function filter(query)
   query = (query or ""):lower()
   matches = {}
   if query == "" then
      for _, app in ipairs(apps) do table.insert(matches, app) end
   else
      local starts, contains = {}, {}
      for _, app in ipairs(apps) do
         local at = app.name:lower():find(query, 1, true)
         if at == 1 then table.insert(starts, app)
         elseif at then table.insert(contains, app) end
      end
      for _, app in ipairs(starts) do table.insert(matches, app) end
      for _, app in ipairs(contains) do table.insert(matches, app) end
      if #matches == 0 then
         table.insert(matches, { name = "Run command: " .. query, cmdline = query, shell = true })
      end
   end
   selected, offset = 1, 0
end

local function start(app)
   launcher.hide()
   if not app then return end
   if app.shell then awful.spawn.with_shell(app.cmdline) else awful.spawn(app.cmdline) end
end

local function redraw()
   list_layout:reset()
   for i = offset + 1, math.min(offset + ROWS, #matches) do
      local app = matches[i]
      local row = wibox.widget {
         {
            {
               {
                  image = app.icon or beautiful.default_app_icon,
                  forced_width = 28, forced_height = 28,
                  widget = wibox.widget.imagebox,
               },
               { text = app.name, font = beautiful.font, widget = wibox.widget.textbox },
               spacing = 14,
               layout = wibox.layout.fixed.horizontal,
            },
            left = 14, right = 14, top = 8, bottom = 8,
            widget = wibox.container.margin,
         },
         forced_height = ROW_H,
         bg = (i == selected) and beautiful.active_bg or nil,
         shape = beautiful.button_shape,
         widget = wibox.container.background,
      }
      row:connect_signal("mouse::enter", function()
         if selected ~= i then selected = i; redraw() end
      end)
      row:buttons(awful.button({}, 1, function() start(app) end))
      list_layout:add(row)
   end
   hint.text = (#matches > ROWS)
      and string.format("%d of %d  -  Up/Down to scroll", selected, #matches)
      or (#matches == 0 and "No applications found" or "")
end

local function move(delta)
   if #matches == 0 then return end
   selected = math.max(1, math.min(#matches, selected + delta))
   if selected <= offset then offset = selected - 1 end
   if selected > offset + ROWS then offset = selected - ROWS end
   redraw()
end

local function build()
   prompt_box = wibox.widget.textbox()
   prompt_box.font = beautiful.font
   list_layout = wibox.layout.fixed.vertical()
   list_layout.spacing = 2
   hint = wibox.widget.textbox()
   hint.font = beautiful.font_small

   local power = wibox.widget {
      {
         { image = beautiful.power_icon, forced_width = 22, forced_height = 22, widget = wibox.widget.imagebox },
         margins = 9, widget = wibox.container.margin,
      },
      shape = beautiful.button_shape,
      widget = wibox.container.background,
   }
   power:connect_signal("mouse::enter", function() power.bg = beautiful.hover_bg end)
   power:connect_signal("mouse::leave", function() power.bg = nil end)
   power:buttons(awful.button({}, 1, function()
      launcher.hide()
      if on_power then on_power() end
   end))

   local height = 62 + ROWS * (ROW_H + 2) + 16 + 56
   popup = wibox({
      width = WIDTH, height = height, ontop = true, visible = false,
      bg = beautiful.menu_bg_normal, fg = beautiful.fg_normal,
      border_width = 1, border_color = beautiful.menu_border_color,
      shape = function(cr, w, h) gears.shape.rounded_rect(cr, w, h, 10) end,
      type = "popup_menu",
   })
   popup:setup {
      {
         {
            { -- search box
               {
                  {
                     { text = "Search: ", font = beautiful.font, widget = wibox.widget.textbox },
                     prompt_box,
                     layout = wibox.layout.fixed.horizontal,
                  },
                  left = 14, right = 14, top = 9, bottom = 9,
                  widget = wibox.container.margin,
               },
               bg = p().surface2, shape = beautiful.button_shape,
               shape_border_width = 1, shape_border_color = p().border,
               forced_height = 40,
               widget = wibox.container.background,
            },
            { list_layout, top = 10, widget = wibox.container.margin },
            layout = wibox.layout.fixed.vertical,
         },
         nil,
         { -- footer: user name, scroll hint, power button
            {
               {
                  { text = os.getenv("USER") or "", font = beautiful.font, widget = wibox.widget.textbox },
                  left = 6, widget = wibox.container.margin,
               },
               { hint, halign = "center", widget = wibox.container.place },
               power,
               layout = wibox.layout.align.horizontal,
            },
            top = 8,
            widget = wibox.container.margin,
         },
         layout = wibox.layout.align.vertical,
      },
      left = 14, right = 14, top = 14, bottom = 10,
      widget = wibox.container.margin,
   }

   -- A transparent sheet behind the popup: a click anywhere outside closes it.
   backdrop = wibox({ ontop = true, visible = false, bg = "#00000000", type = "utility" })
   backdrop:buttons(awful.util.table.join(
      awful.button({}, 1, function() launcher.hide() end),
      awful.button({}, 3, function() launcher.hide() end)
   ))
end

function launcher.hide()
   if not open then return end
   open = false
   popup.visible = false
   backdrop.visible = false
   keygrabber.stop()
end

function launcher.show()
   if not popup then build() end
   if open then launcher.hide(); return end
   open = true
   local s = awful.screen.focused()
   local wa = s.workarea
   backdrop:geometry(s.geometry)
   popup.x = wa.x + math.floor((wa.width - WIDTH) / 2)
   popup.y = wa.y + wa.height - popup.height - 10
   filter("")
   redraw()
   backdrop.visible = true
   popup.visible = true

   awful.prompt.run {
      prompt = "",
      textbox = prompt_box,
      bg_cursor = beautiful.accent,
      changed_callback = function(input) filter(input); redraw() end,
      keypressed_callback = function(_, key)
         if key == "Down" then move(1)
         elseif key == "Up" then move(-1)
         elseif key == "Next" then move(ROWS)
         elseif key == "Prior" then move(-ROWS) end
      end,
      exe_callback = function() start(matches[selected]) end,
      done_callback = function() launcher.hide() end,
   }
end

function launcher.toggle() launcher.show() end

function launcher.setup(args)
   on_power = args and args.on_power
   load_apps()
end

return launcher
