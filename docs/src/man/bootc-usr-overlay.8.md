# NAME

bootc-usr-overlay - Adds a writable overlayfs on `/usr`

# SYNOPSIS

**bootc usr-overlay** \[*OPTIONS...*\]

# DESCRIPTION

Adds a writable overlayfs on `/usr`, and on `/opt` when it is a directory of
the image rather than a symlink into `/var`. By default the overlay is
transient and discarded on reboot; with `--persist` it is kept for as long as
the current deployment stays booted. The overlayfs is read/write by default.

## USE CASES

A common pattern is wanting to use tracing/debugging tools, such as
`strace` that may not be in the base image. A system package manager
such as `apt` or `dnf` can apply changes into this transient overlay
that will be discarded on reboot.

## STORAGE AND MEMORY REQUIREMENTS

The transient overlay is backed by a `tmpfs` filesystem, which means all
data written to the overlay (i.e. installed packages) is stored in
**system memory (RAM)**, not on persistent disk.  By default the kernel
sizes this `tmpfs` at 50% of physical RAM.

On systems with limited memory, installing large packages into the
overlay can exhaust available RAM and result in `ENOSPC` ("No space left
on device") errors.  There is currently no pre-flight space check and no
early warning before the `tmpfs` is full.

Keep this in mind when using transient overlays in memory-constrained
environments such as CI runners or small virtual machines.  If the
combined size of the packages being installed approaches half of the
system's RAM, consider increasing the VM's memory allocation instead.

## PERSISTENT OVERLAYS

With `--persist`, the upper directories of the overlays are stored on disk in
the state directory of the booted deployment instead of a `tmpfs`, and
`bootc-root-setup` mounts them again on every boot of that deployment. Changes
therefore survive reboots, but `bootc upgrade` or `bootc switch` boot the new
deployment with a pristine `/usr`. The previous overlay stays on disk, where it
can be inspected (for example to fold local package installs back into the
container image), until garbage collection removes the old deployment.

On ostree-based hosts this is `ostree admin unlock --hotfix`. On composefs
hosts the same behaviour can be configured for every deployment with
`[usr] mount = "overlay"` (and `[opt]`) in `setup-root-conf.toml`; see
`bootc-setup-root-conf(5)`.

A writable `/usr` defeats the integrity guarantees of a sealed image.

## /ETC AND /VAR

However, this command has no effect on `/etc` and `/var` - changes
written there will persist. It is common for package installations to
modify these directories.

## UNMOUNTING

Almost always, a system process will hold a reference to the open mount
point. You can however invoke `umount -l /usr` to perform a "lazy
unmount".

# OPTIONS

<!-- BEGIN GENERATED OPTIONS -->
**--read-only**

    Mount the overlayfs as read-only. A read-only overlayfs is useful since it may be remounted as read/write in a private mount namespace and written to while the mount point remains read-only to the rest of the system

**--persist**

    Keep the overlay across reboots of the current deployment

<!-- END GENERATED OPTIONS -->

# VERSION

<!-- VERSION PLACEHOLDER -->

