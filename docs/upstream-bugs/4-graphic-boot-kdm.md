# The `Graphic` boot script starts `kdm`, which 017.01 does not ship

**Version:** GoboLinux 017.01 x86_64, BootScripts 017.01.

## Where

`/System/Settings/BootScripts/Graphic`:

```sh
#!/bin/sh
source BootUp
Exec "Loading login manager..." kdm
```

## Result

`kdm` is not on the image, and neither is any other display manager (xdm, lightdm, slim, sddm, lxdm were
looked for). Switching the default runlevel script from `Console` to `Graphic` therefore cannot bring up a
graphical login. An installed system always lands on a text login, and the desktop has to be started by
hand with `startx`.

## Expected

Either a display manager is shipped and `Graphic` starts it, or `Graphic` falls back to something that works
(for example starting X for a chosen user), or the script is removed so it does not suggest a working option.

## Related

The stock installed boot (`BootUp`) also only configures the loopback interface, so a wired connection is
not brought up at boot on an installed system; the live session does get one.
