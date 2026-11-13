#!/bin/sh
# Lock the screen with XSecureLock, styled to match the desktop.
# Used by the power menu, Mod4+L, and automatically after a while without input.
export XSECURELOCK_FONT="Inter:size=13"
export XSECURELOCK_BACKGROUND_COLOR="#0b1630"
export XSECURELOCK_AUTH_BACKGROUND_COLOR="#0b1630"
export XSECURELOCK_AUTH_FOREGROUND_COLOR="#ffffff"
export XSECURELOCK_AUTH_WARNING_COLOR="#e5484d"
export XSECURELOCK_SHOW_DATETIME=1
export XSECURELOCK_DATETIME_FORMAT="%H:%M   %A, %d %B"
export XSECURELOCK_SHOW_HOSTNAME=0
export XSECURELOCK_SHOW_USERNAME=1
export XSECURELOCK_PASSWORD_PROMPT=asterisks
# With a compositor running, the default overlay mode leaves the taskbar area
# showing through; this mode covers the whole screen. (Trade-off: a desktop
# notification can briefly appear above the lock screen.)
export XSECURELOCK_NO_COMPOSITE=1
exec xsecurelock
