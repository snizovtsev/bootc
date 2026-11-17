# number: 69
# tmt:
#   summary: Test install to-filesystem on a ZFS root
#   duration: 30m
#   require:
#     - dosfstools
# extra:
#   # The ostree backend needs a UUID for /boot or the root, which a dataset
#   # doesn't have, and a UKI brings its own kernel arguments
#   skip_if_ostree: true
#   fixme_skip_if_uki: true
#
# A ZFS root is a dataset. Its mount source is a name such as `tank/root`,
# not a block device, and it has no filesystem UUID. Installing to one, bootc
# has to
#
# - resolve the dataset to the devices of its pool, and find the ESP on
#   whichever device's disk carries it: here the last of a three-device raidz;
# - write `root=ZFS=<dataset>` as the default root argument;
# - finish without freezing the filesystem, which ZFS doesn't support.
#
# Booting a disk installed inside the VM isn't possible here, so the test
# stops at inspecting what was installed. ZFS is not in the mainline kernel:
# the test is skipped without the module or the ZFS utilities.

use std assert
use tap.nu

const ESP_TYPE = "C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
const DISKS = ["/var/tmp/zfs-a.img" "/var/tmp/zfs-b.img" "/var/tmp/zfs-c.img"]
const POOL = "bootc-test-pool"
const DATASET = "bootc-test-pool/root"
const ROOT = "/var/mnt/zfs-root"
const ESP = "/var/mnt/zfs-esp"

def cleanup [loops: list<string>] {
    # Unmount the dataset first: `zpool destroy` gives up if it is also
    # mounted elsewhere, e.g. where /mnt and /var/mnt are the same directory.
    for mnt in [$ESP $ROOT] {
        do { umount -l $mnt } | complete | ignore
    }
    do { zpool destroy -f $POOL } | complete | ignore
    for loop in $loops {
        do { losetup -d $loop } | complete | ignore
    }
    rm -f ...$DISKS
}

def install_and_check [loops: list<string>] {
    let esp_part = $"($loops.2)p1"
    let devices = [$loops.0 $loops.1 $"($loops.2)p2"]

    $"label: gpt\nsize=1G, type=($ESP_TYPE)\ntype=linux\n" | sfdisk $loops.2
    udevadm settle
    mkfs.vfat -F 32 $esp_part

    # The altroot mounts the dataset, whose mountpoint is /, at $ROOT. The
    # members differ in size, hence -f.
    (zpool create -f -R $ROOT -O mountpoint=none -O acltype=posix -O xattr=sa
        $POOL raidz1 ...$devices)
    zfs create -o mountpoint=/ $DATASET
    udevadm settle
    zpool list -v -P $POOL
    findmnt --output SOURCE,FSTYPE,UUID $ROOT

    (podman run --rm --privileged --pid=host
        --security-opt label=type:unconfined_t
        -v /dev:/dev -v /run/udev:/run/udev:ro
        -v /usr/share/empty:/usr/lib/bootc/bound-images.d
        -v $"($ROOT):/target"
        localhost/bootc
        bootc install to-filesystem --disable-selinux /target)

    assert ($"($ROOT)/composefs" | path exists) "No composefs repository in the ZFS root"

    mkdir $ESP
    mount -o ro $esp_part $ESP
    assert (glob $"($ESP)/EFI/systemd/*.efi" | is-not-empty) $"systemd-boot is not on ($esp_part)"
    let entries = (glob $"($ESP)/loader/entries/*.conf")
    assert ($entries | is-not-empty) $"No boot entries on ($esp_part)"
    for entry in $entries {
        let options = (open --raw $entry | lines | where { |l| $l | str starts-with "options " } | first)
        print $"($entry): ($options)"
        assert ($options | str contains $"root=ZFS=($DATASET) ") $"($entry) doesn't mount ($DATASET) as the root"
    }
}

def main [] {
    tap begin "install to-filesystem on a ZFS root"

    if (which zpool | is-empty) or (do { modprobe zfs } | complete).exit_code != 0 {
        print "SKIP: needs the ZFS utilities and a kernel with ZFS"
        tap ok
        return
    }
    let st = bootc status --json | from json
    let bootloader = $st.status.booted.composefs.bootloader | str downcase
    if $bootloader != "systemd" {
        print $"SKIP: only covered with systemd-boot, not ($bootloader)"
        tap ok
        return
    }

    bootc image copy-to-storage

    let loops = ($DISKS | each { |disk|
        truncate -s 5G $disk
        losetup --find --show --partscan $disk | str trim
    })
    try {
        install_and_check $loops
    } catch { |e|
        cleanup $loops
        error make {msg: $"ZFS install failed: ($e)"}
    }
    cleanup $loops

    tap ok
}
