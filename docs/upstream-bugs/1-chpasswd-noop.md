# `chpasswd` exits 0 but does not change any password (017.01)

**Version:** GoboLinux 017.01 x86_64 live ISO, Shadow 4.2.1.

## Steps

From the live session, with a freshly installed system mounted at `/Mount/GoboLinux` (proc, sys, dev bound):

```sh
printf 'root:newpassword\n' | chroot /Mount/GoboLinux chpasswd; echo "rc=$?"
grep '^root:' /Mount/GoboLinux/System/Settings/shadow
printf 'nosuchuser:x\n' | chroot /Mount/GoboLinux chpasswd; echo "rc=$?"
```

## Result

Both commands print `rc=0`. The `root` line in `shadow` is unchanged (still the live image's default hash),
and a user that does not exist is accepted without any message.

## Expected

The password hash changes, and an unknown user gives an error and a non-zero exit code.

## Notes

- Only tested inside a chroot of the installed target, run from the live session. Not tested on a booted
  installed system.
- `usermod -p "$(openssl passwd -6 ...)" root` works in the same chroot, so the shadow file itself is writable.
- Suspect the PAM path (`/etc/pam.d/chpasswd` exists) rather than the tool, but this was not investigated.
