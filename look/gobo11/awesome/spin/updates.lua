-- System update notices (spin 0.8, A/B system).
-- gobo-update --boot-task (run by the boot scripts as root) writes
-- /Data/Variable/lib/gobo-update/notice when a new system version started for the first time
-- ("updated") or when it did not start and the computer went back to the old one ("rolled-back").
-- Each user sees a notice once: its id is remembered in ~/.cache/gobo11/update-notice-seen.

local naughty = require("naughty")
local gears = require("gears")

local updates = {}

local NOTICE = "/Data/Variable/lib/gobo-update/notice"

local function read_notice()
   local fd = io.open(NOTICE, "r")
   if not fd then return nil end
   local t = {}
   for line in fd:lines() do
      local k, v = line:match("^([%w_]+)=(.*)$")
      if k then t[k] = v end
   end
   fd:close()
   if not t.id or not t.kind then return nil end
   return t
end

local function seen_file()
   return (os.getenv("HOME") or "/tmp") .. "/.cache/gobo11/update-notice-seen"
end

local function already_seen(id)
   local fd = io.open(seen_file(), "r")
   if not fd then return false end
   local seen = fd:read("*l")
   fd:close()
   return seen == id
end

local function remember(id)
   os.execute("mkdir -p \"$HOME/.cache/gobo11\"")
   local fd = io.open(seen_file(), "w")
   if fd then fd:write(id, "\n"); fd:close() end
end

function updates.check()
   local n = read_notice()
   if not n or already_seen(n.id) then return end
   -- 0.8.2: notices name the accounts that existed when they were written; someone whose
   -- account was made later has nothing to be told (first login of a new user)
   local me = os.getenv("USER") or os.getenv("LOGNAME") or ""
   if n.users and me ~= "" and not n.users:find("," .. me .. ",", 1, true) then
      remember(n.id)
      return
   end
   if n.kind == "rolled-back" then
      naughty.notify({
         title = "System update undone",
         text = ("GoboRefined %s did not start, so the computer went back to %s.\n" ..
                 "Your files and settings are unchanged. Details: sudo gobo-update --status")
                :format(n.failed_version or "?", n.running_version or "the previous version"),
         timeout = 0,
         preset = naughty.config.presets.critical,
      })
   elseif n.kind == "updated" then
      naughty.notify({
         title = "System updated",
         text = ("GoboRefined %s is running%s. If something is wrong: sudo gobo-update --rollback")
                :format(n.running_version or "?",
                        (n.previous_version and n.previous_version ~= "") and
                           (" (was " .. n.previous_version .. ")") or ""),
         timeout = 20,
      })
   else
      return
   end
   remember(n.id)
end

function updates.start()
   -- a moment after start-up, so the notice is not lost among the start-up windows
   gears.timer.start_new(4, function() updates.check(); return false end)
end

return updates
