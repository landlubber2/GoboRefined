/* gobo-udev-dev.so (GoboRefined 0.8.1): libudev subscribes to udevd's device events only if
 * "/dev" is a devtmpfs mount. It asks with name_to_handle_at("/dev", flags 0), which does not
 * follow the link /dev -> /System/Kernel/Devices on GoboLinux, so every libudev "udev" monitor
 * (Xorg's input hot-plug among them) stays deaf. This preload follows the link for exactly
 * that path and changes nothing else. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <string.h>

int name_to_handle_at(int dirfd, const char *path, struct file_handle *handle, int *mount_id, int flags)
{
   static int (*real)(int, const char *, struct file_handle *, int *, int);
   if (!real)
      real = (int (*)(int, const char *, struct file_handle *, int *, int)) dlsym(RTLD_NEXT, "name_to_handle_at");
   if (!real)
      return -1;
   if (path && strcmp(path, "/dev") == 0)
      flags |= AT_SYMLINK_FOLLOW;
   return real(dirfd, path, handle, mount_id, flags);
}
