-- GoboRefined 0.10.8: what kind of program file is this? Shared by gobo-install-app (install-app.lua,
-- the file manager's "Install" action and Settings > Software) — plain Lua, no GTK, so the file
-- manager's menu can ask quickly ("lua app-detect.lua offer FILE" prints true or false).
--
-- Kinds (by content and name, not only by the ending):
--   "appimage"  an ELF program with the AppImage magic ("AI" 1 or 2 at byte 8), or an ELF program
--               named *.AppImage
--   "package"   a GoboLinux package: Name--Version--arch.tar.(bz2|gz|xz|zst) whose first entries
--               are Name/Version/...
--   "archive"   an archive (anything bsdtar reads) holding a ready program: one top folder (or loose
--               files) with an executable file at the top or in bin/; candidates ranked (a file named
--               like the folder first)
--   "files"     an archive that holds no program (photos, documents ...)
--   "windows"   an archive with .exe files and no Linux program
--   "other"     anything else (with a description)
local M = {}

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$")) or "."
M.ARCHIVE = "/System/Index/bin/gobo-archive"

local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
M.q = q
local function pread(cmd)
   local p = io.popen(cmd .. " 2>/dev/null", "r")
   if not p then return "" end
   local s = p:read("*a") or ""
   p:close()
   return s
end
M.pread = pread

function M.head(path, n)
   local f = io.open(path, "rb")
   if not f then return nil end
   local s = f:read(n or 64) or ""
   f:close()
   return s
end

local function is_elf(h) return h and h:sub(1, 4) == "\127ELF" end
function M.is_elf_file(path) return is_elf(M.head(path, 4)) end

-- Gobo package file name: Name--Version--arch.tar.ext
function M.package_name(base)
   local n, v, a, ext = base:match("^([%w][%w+_.~-]*)%-%-([%w][%w+_.~-]*)%-%-([%w_]+)%.tar%.(%w+)$")
   if n and (ext == "bz2" or ext == "gz" or ext == "xz" or ext == "zst") then return n, v, a end
end

-- archive endings worth a look by the file manager's menu (content decides afterwards)
function M.archive_name(base)
   local b = base:lower()
   for _, e in ipairs({ "%.tar%.gz$", "%.tgz$", "%.tar%.xz$", "%.txz$", "%.tar%.bz2$", "%.tbz2?$", "%.tar%.zst$",
                        "%.tzst$", "%.tar$", "%.zip$", "%.7z$", "%.rar$" }) do
      if b:match(e) then return true end
   end
   return false
end

-- "mode<TAB>size<TAB>name" lines from gobo-archive list
function M.list(path, max)
   local entries = {}
   local out = pread(q(M.ARCHIVE) .. " list " .. q(path) .. (max and (" " .. max) or ""))
   for line in out:gmatch("[^\n]+") do
      local mode, size, name = line:match("^(%S+)\t(%d*)\t(.+)$")
      if mode then
         name = name:gsub("^%./", ""):gsub("/+$", "")
         if name ~= "" and name ~= "." then
            table.insert(entries, { mode = mode, size = tonumber(size) or 0, name = name })
         end
      end
   end
   return entries
end

-- strip versions, architectures and "linux" from a folder or file name: "Antigravity-x64" -> "Antigravity"
function M.simplify(name)
   local n = name:gsub("%.[Aa][Pp][Pp][Ii][Mm][Aa][Gg][Ee]$", "")
   for _ = 1, 4 do
      n = n:gsub("[-_. ]+[Xx]86[-_]64$", ""):gsub("[-_. ]+[Aa][Mm][Dd]64$", ""):gsub("[-_. ]+[Xx]64$", "")
           :gsub("[-_. ]+[Ll]inux%d*$", ""):gsub("[-_. ]+[Ss]table$", ""):gsub("[-_. ]+v?%d[%w.+~]*$", "")
   end
   return n
end
function M.version_in(name)
   return name:match("[-_ v](%d+%.%d+[%d.]*%d)") or name:match("[-_ v](%d+%.%d+)")
end

local SKIP_EXE = { ["chrome-sandbox"] = true, ["chrome_crashpad_handler"] = true, ["crashpad_handler"] = true,
                   ["xdg-open"] = true, ["update"] = true, ["uninstall"] = true }

-- the executables an archive's listing offers, best first: { {rel=, score=}, ... }, top folder
function M.analyse(entries)
   local tops, top = {}, nil
   for _, e in ipairs(entries) do
      local t = e.name:match("^([^/]+)")
      if t then tops[t] = (tops[t] or 0) + 1 end
   end
   local ntops, only = 0, nil
   for t in pairs(tops) do ntops = ntops + 1; only = t end
   if ntops == 1 then
      for _, e in ipairs(entries) do
         if e.name:find("/", 1, true) or e.mode:sub(1, 1) == "d" then top = only break end
      end
   end
   local want = top and M.simplify(top):lower() or nil
   local cands, has_exe, files = {}, false, 0
   for _, e in ipairs(entries) do
      local rel = e.name
      if top then rel = rel:sub(#top + 2) end
      local kind = e.mode:sub(1, 1)
      if kind == "-" then files = files + 1 end
      if rel:lower():match("%.exe$") then has_exe = true end
      local base = rel:match("([^/]+)$") or rel
      local depth_ok = not rel:find("/", 1, true) or rel:match("^bin/[^/]+$")
      if kind == "-" and e.mode:sub(4, 4) == "x" and rel ~= "" and depth_ok and not SKIP_EXE[base:lower()]
         and not base:match("%.so[%.%d]*$") and not base:match("%.so$") then
         local score = 10
         local low = M.simplify(base):lower()
         if want and low == want then score = 100
         elseif want and want:sub(1, #low) == low and #low >= 3 then score = 80
         elseif want and low:sub(1, #want) == want and #want >= 3 then score = 70 end
         if not rel:find("/", 1, true) then score = score + 5 end
         if base:match("%.sh$") then score = score - 3 end
         table.insert(cands, { rel = rel, score = score, size = e.size })
      end
   end
   table.sort(cands, function(a, b)
      if a.score ~= b.score then return a.score > b.score end
      return a.size > b.size
   end)
   return { top = top, candidates = cands, windows = has_exe, files = files }
end

-- M.detect(path [, max]) -> info table { kind=..., ... }
function M.detect(path, max)
   local base = path:match("([^/]+)$") or path
   local h = M.head(path, 64)
   if not h then return { kind = "missing" } end
   if is_elf(h) then
      local magic = h:sub(9, 11)
      if magic == "AI\2" or magic == "AI\1" or base:lower():match("%.appimage$") then
         return { kind = "appimage", type = magic == "AI\1" and 1 or 2 }
      end
      return { kind = "other", elf = true }
   end
   local pn, pv, pa = M.package_name(base)
   if pn then
      local first = M.list(path, 4)
      if first[1] and (first[1].name == pn or first[1].name:sub(1, #pn + #pv + 2) == pn .. "/" .. pv .. "/"
                       or first[1].name == pn .. "/" .. pv) then
         return { kind = "package", name = pn, version = pv, arch = pa }
      end
   end
   local entries = M.list(path, max)
   if #entries == 0 then return { kind = "other" } end
   local a = M.analyse(entries)
   a.entries = entries
   if #a.candidates > 0 then a.kind = "archive"
   elseif a.windows then a.kind = "windows"
   else a.kind = "files" end
   return a
end

-- what a file is, in words (for "this is not a program file")
function M.describe(path)
   local d = pread("file -b -- " .. q(path)):gsub("%s+$", "")
   if d == "" then return "a file of unknown type" end
   d = d:gsub(",.*$", "")
   if #d > 80 then d = d:sub(1, 80) .. "..." end
   return d
end

-- the file manager's menu: is "Install" offered for FILE?
function M.offer(path)
   local home = os.getenv("HOME") or ""
   if path:sub(1, #home + 14) == home .. "/Applications/" then return false end
   local base = path:match("([^/]+)$") or path
   if base:lower():match("%.appimage$") then return true end
   local h = M.head(path, 12)
   if is_elf(h) and (h:sub(9, 11) == "AI\2" or h:sub(9, 11) == "AI\1") then return true end
   if M.package_name(base) then return true end
   if not M.archive_name(base) then return false end
   -- the menu must open quickly: the first 150 entries, at most 0.8 s (a big .tar.gz is read from
   -- the start); when that is not enough to tell, "Install" is offered and the installer decides
   local p = io.popen("timeout 0.8 " .. q(M.ARCHIVE) .. " list " .. q(path) .. " 150 2>/dev/null", "r")
   if not p then return false end
   local out = p:read("*a") or ""
   local _, _, code = p:close()
   if code == 124 then return true end
   local entries = {}
   for line in out:gmatch("[^\n]+") do
      local mode, size, name = line:match("^(%S+)\t(%d*)\t(.+)$")
      if mode then
         name = name:gsub("^%./", ""):gsub("/+$", "")
         if name ~= "" then table.insert(entries, { mode = mode, size = tonumber(size) or 0, name = name }) end
      end
   end
   return #M.analyse(entries).candidates > 0
end

if arg and arg[0] and arg[0]:match("app%-detect%.lua$") and arg[1] == "offer" and arg[2] then
   local yes = M.offer(arg[2])
   print(yes and "true" or "false")
   os.exit(yes and 0 or 1)   -- libfm's ShowIfTrue looks at the exit status
end
if arg and arg[0] and arg[0]:match("app%-detect%.lua$") and arg[1] == "kind" and arg[2] then
   local info = M.detect(arg[2])
   io.write(info.kind, "\t", info.top or info.name or "", "\t", (info.candidates and info.candidates[1] and info.candidates[1].rel) or "", "\n")
   os.exit(0)
end

return M
