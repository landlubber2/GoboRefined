#!/usr/bin/env bash
# Keyboard-focus regression test for the lab desktop (0.6, item 1: "keyboard input gets stuck").
# Opens and closes every popup of the look in different orders, with clicks and keys, while a
# terminal (urxvt) and a GTK window (zenity) are open, then clicks the terminal and types
# "touch /tmp/kb-<scenario>" + Enter. A scenario passes when that file appears.
#   vm/input-test.sh [scenario...]      (default: all; needs SSH into the VM and a running desktop)
#
# Mouse: Awesome's root.fake_input (vm/input-test.lua). Keyboard: VirtualBox's virtual PS/2
# keyboard (keyboardputscancode / keyboardputstring), i.e. the same path as a real keyboard.
# (Keys sent with root.fake_input confused urxvt: after a shortcut, the next typed letter
# sometimes arrived as the shortcut's letter. Real keyboard input never showed that.)
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VB="${VBOXMANAGE:-/c/Program Files/Oracle/VirtualBox/VBoxManage.exe}"
VM="${VM:-GoboLinux-017.01}"
export MSYS_NO_PATHCONV=1
L() { "$here/lua.sh" "$1"; }
S() { "$here/ssh.sh" "$1"; }
pause() { sleep "${1:-1}"; }

# key chords as PS/2 set-1 scancodes: press all in order, release in reverse order
declare -A SC=( [win]="e0 5b" [ctrl]="1d" [alt]="38" [shift]="2a" [esc]="01" [tab]="0f"
                [enter]="1c" [del]="e0 53" [print]="e0 37" [down]="e0 50" [up]="e0 48" [r]="13" [s]="1f" [v]="2f" [p]="19" )
rel() { local out=""; for b in $1; do if [ "$b" = e0 ]; then out="$out e0"; else out="$out $(printf '%02x' $((0x$b | 0x80)))"; fi; done; echo $out; }
keys() {   # keys win shift tab
   local down="" up=""
   for k in "$@"; do down="$down ${SC[$k]}"; up="$(rel "${SC[$k]}") $up"; done
   "$VB" controlvm "$VM" keyboardputscancode $down $up
}
typeline() { "$VB" controlvm "$VM" keyboardputstring "$1"; keys enter; }

setup() {
   S 'cat > /tmp/input-test.lua; chmod 644 /tmp/input-test.lua' < "$here/input-test.lua"
   L 'return dofile("/tmp/input-test.lua")' > /dev/null
   L 'if not T.find("inputtest") then require("awful").spawn("urxvt -name inputtest -geometry 80x20+20+20") end
      if not T.find("zenity") then require("awful").spawn("zenity --entry --title=gtktest --text=gtk") end
      return 1' > /dev/null
   pause 3
   S 'find /tmp -maxdepth 1 -name "kb-*" -delete'
}

# release everything before the next scenario (Win+Escape safety net when it exists)
reset() {
   # (0.5 and older bound Win+Escape to "previous desktop": only press it where it is the safety net)
   if L 'return tostring(spin_popups ~= nil)' | grep -q true; then keys win esc; pause 1; fi
   L 'for _, t in ipairs(screen.primary.tags) do if #t:clients() > 0 then t:view_only() break end end
      return 1' > /dev/null
   if L 'return tostring(keygrabber.isrunning())' | grep -q true; then keys esc; pause 1; fi
   if L 'return tostring(keygrabber.isrunning())' | grep -q true
   then
      echo "     (keyboard still grabbed after Win+Escape and Escape: restarting Awesome)"
      L 'awesome.restart()' > /dev/null 2>&1; pause 4
      L 'return dofile("/tmp/input-test.lua")' > /dev/null
   fi
}

pass=0 fail=0 failed=""
result() {   # result NAME FILE
   local state
   state=$(L 'return T.state()' | sed 's/^ *string //')
   if S "test -e $2"
   then echo "PASS $1   $state"; pass=$((pass + 1))
   else echo "FAIL $1   $state"; fail=$((fail + 1)); failed="$failed $1"
   fi
}
check() {
   L 'return T.click_client("inputtest")' > /dev/null
   pause 1
   typeline "touch /tmp/kb-$1"
   pause 2
   result "$1" "/tmp/kb-$1"
   reset
}

# steps, one second apart: "@k win r" = key chord, "@t text" = type text + Enter, else Lua
steps() {
   for step in "$@"; do
      case $step in
         "@k "*) keys ${step#@k } ;;
         "@t "*) typeline "${step#@t }" ;;
         *) L "$step" > /dev/null ;;
      esac
      pause 1
   done
}
run() { local name=$1; shift; steps "$@"; check "$name"; }

# screenshots saved by the look (0.8.1 scenarios): count before and after
shots() { S "ls /Users/${LAB_LOGIN:-lab}/Pictures/Screenshots 2>/dev/null | wc -l" | tr -d ' '; }
shots_before() { SHOTS0=$(shots); }
shots_after() {   # shots_after NAME
   sleep 2
   if [ "$(shots)" -gt "${SHOTS0:-0}" ]
   then echo "PASS $1"; pass=$((pass + 1))
   else echo "FAIL $1"; fail=$((fail + 1)); failed="$failed $1"
   fi
}

menu_open() {   # menu_open NAME true|false : is the dots menu (category menu) open?
   if L 'return tostring(spin_debug.mainmenu ~= nil and spin_debug.mainmenu.wibox.visible)' | grep -q "$2"
   then echo "PASS $1"; pass=$((pass + 1))
   else echo "FAIL $1"; fail=$((fail + 1)); failed="$failed $1"
   fi
}

scenario() {
   case $1 in
   plain)               run plain 'return 1' ;;
   menu-click-client)   run menu-click-client 'return T.click_pos("start")' ;;
   menu-click-desktop)  run menu-click-desktop 'return T.click_pos("start")' 'T.click_desktop() return 1' ;;
   menu-click-gtk)      run menu-click-gtk 'return T.click_pos("start")' 'return T.click_client("zenity")' ;;
   menu-click-taskbar)  run menu-click-taskbar 'return T.click_pos("start")' 'local x, y = T.pos("start") T.click(x + 177, y) return 1' ;;
   menu-escape)         run menu-escape 'return T.click_pos("start")' '@k esc' ;;
   menu-then-search)    run menu-then-search 'return T.click_pos("start")' 'return T.click_pos("start", 3)' 'T.click_desktop() return 1' ;;
   menu-rightclick-desktop) run menu-rightclick-desktop 'T.click_desktop(3) return 1' ;;
   search-click-out)    run search-click-out 'return T.click_pos("start", 3)' 'T.click_desktop() return 1' ;;
   search-click-client) run search-click-client 'return T.click_pos("start", 3)' ;;
   search-escape)       run search-escape '@k win r' '@k esc' ;;
   search-types)        # the search must take typing after the terminal had focus: run a command from it
                        L 'return T.click_client("inputtest")' > /dev/null; pause 1
                        steps '@k win r' '@t touch /tmp/kb-search-typed'; pause 1
                        result search-types /tmp/kb-search-typed; reset ;;
   search-from-menu)    L 'return T.click_client("inputtest")' > /dev/null; pause 1
                        steps 'return T.click_pos("start")' '@k down' '@k enter' '@t touch /tmp/kb-search-from-menu'; pause 1
                        result search-from-menu /tmp/kb-search-from-menu; reset ;;
   search-twice)        run search-twice '@k win r' 'T.click_desktop() return 1' '@k win r' '@k esc' ;;
   search-power)        run search-power 'return T.click_pos("start", 3)' 'local p = spin_debug.launcher_power_xy() if p then T.click(p.x, p.y) end return 1' 'T.click_desktop() return 1' ;;
   power-click-out)     run power-click-out '@k ctrl alt del' 'T.click_desktop() return 1' ;;
   power-escape)        run power-escape '@k ctrl alt del' '@k esc' ;;
   tasklist-menu)       run tasklist-menu 'local x, y = T.pos("start") T.click(x + 177, y, 3) return 1' ;;
   net-menu)            run net-menu 'return T.click_pos("net")' ;;
   usb-menu)            run usb-menu 'return T.click_pos("usb")' ;;
   window-menu)         run window-menu 'local c = T.find("inputtest") local g = c:geometry() T.click(g.x + 200, g.y + 14, 3) return 1' ;;
   hotkeys-click)       run hotkeys-click '@k win s' ;;
   hotkeys-key)         run hotkeys-key '@k win s' '@k esc' ;;
   alttab)              run alttab '@k alt tab' ;;
   alttab-twice)        run alttab-twice '@k alt tab' '@k alt tab' ;;
   desktops)            run desktops '@k win shift tab' 'T.click_desktop() return 1' ;;
   desktops-escape)     run desktops-escape '@k win shift tab' '@k esc' ;;
   shot-menu)           run shot-menu '@k win shift s' 'T.click_desktop() return 1' ;;
   shot-escape)         run shot-escape '@k win shift s' '@k esc' ;;
   clip-menu)           run clip-menu '@k win shift v' '@k esc' ;;
   two-popups)          run two-popups 'return T.click_pos("start")' 'return T.click_pos("net")' '@k ctrl alt del' 'T.click_desktop() return 1' ;;
   panic-in-menu)       # Win+Escape while the category menu holds the keyboard
                        run panic-in-menu 'return T.click_pos("start")' '@k win esc' ;;
   shot-print-in-menu)  # 0.8.1: Print while the category menu holds the keyboard: menu closes, screenshot saved
                        shots_before
                        run shot-print-in-menu 'return T.click_pos("start")' '@k print'
                        shots_after shot-print-in-menu-saved ;;
   shot-card-in-menu)   # 0.8.1: Win+Shift+S while the category menu is open: the card opens ("s" = whole screen)
                        shots_before
                        run shot-card-in-menu 'return T.click_pos("start")' '@k win shift s' '@k s'
                        shots_after shot-card-in-menu-saved ;;
   win-tap)             # 0.8.1: Win tapped alone opens the dots menu; Escape closes it
                        steps '@k win'
                        menu_open win-tap-opens true
                        run win-tap '@k esc' ;;
   win-hold)            # 0.8.1: Win held for a shortcut (Win+Up on the terminal) does not open the menu,
                        # and the window key still works while Win is bound
                        L 'return T.click_client("inputtest")' > /dev/null; pause 1
                        local g0 g1
                        g0=$(L 'local g = client.focus:geometry() return g.width .. "x" .. g.height')
                        steps '@k win up'
                        g1=$(L 'local g = client.focus:geometry() return g.width .. "x" .. g.height')
                        menu_open win-hold-no-menu false
                        if [ "$g0" != "$g1" ]; then echo "PASS win-hold-window-key"; pass=$((pass + 1))
                        else echo "FAIL win-hold-window-key ($g0)"; fail=$((fail + 1)); failed="$failed win-hold-window-key"; fi
                        steps '@k win up'   # back
                        check win-hold ;;
   *) echo "unknown scenario $1"; return 1 ;;
   esac
}

ALL="plain menu-click-client menu-click-desktop menu-click-gtk menu-click-taskbar menu-escape menu-then-search
     menu-rightclick-desktop search-click-out search-click-client search-escape search-types search-from-menu
     search-twice search-power power-click-out power-escape tasklist-menu net-menu usb-menu window-menu
     hotkeys-click hotkeys-key alttab alttab-twice desktops desktops-escape shot-menu shot-escape clip-menu
     two-popups panic-in-menu shot-print-in-menu shot-card-in-menu win-tap win-hold"

setup
for s in ${*:-$ALL}; do scenario "$s"; done
echo "passed $pass, failed $fail${failed:+:$failed}"
