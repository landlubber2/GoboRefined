# The `XRandR` package on 017.01 contains only the library — there is no `xrandr` command

**Version:** GoboLinux 017.01 x86_64 live ISO.

## Steps

```sh
which xrandr
find /Programs/XRandR /Programs/LibXRandR -name 'xrandr*'
```

## Result

`xrandr` is not found. `/Programs/XRandR/1.5.1` holds `lib/libXrandr.so*`, `lib/pkgconfig/xrandr.pc` and
`man3` pages — the same library that `/Programs/LibXRandR` provides. No `bin/` directory.

## Expected

A package called XRandR provides the `xrandr` program. Without it nothing on the image can enable, arrange
or change the resolution of an output, so a second monitor cannot be used.

## Notes

The upstream `xrandr` 1.5.2 source builds on 017.01 with a plain `./configure && make` (GCC 14.2, the shipped
libXrandr), so this looks like a recipe mix-up rather than a build problem.
