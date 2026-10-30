#!/usr/bin/env bash
# Stage a kernel (+ DTB, optional initramfs) for the ens4 netboot & write the
# boot.scr that U-Boot fetches. No boot.scr = U-Boot boots the SD card instead.
# Usage: stage-ens4-netboot.sh KERNEL DTB [INITRAMFS] [-- EXTRA_BOOTARGS...]
#        stage-ens4-netboot.sh --off       remove boot.scr (next boot: SD card)
# Without INITRAMFS the rootfs is the SD card's (root=PARTLABEL=root).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
top="$(cd "$here/.." && pwd)"
TFTP_ROOT="${TFTP_ROOT:-$top/tftp}"
dir="$TFTP_ROOT/visionfive2"

if [ "${1:-}" = "--off" ]; then
    rm -f "$dir/boot.scr" && echo "[stage] boot.scr removed; next boot is from SD"; exit 0
fi
[ $# -ge 2 ] || { sed -n 4,6p "$0" >&2; exit 2; }
kernel="$1" dtb="$2"; shift 2
initrd=""
if [ $# -gt 0 ] && [ "$1" != "--" ]; then initrd="$1"; shift; fi
[ "${1:-}" = "--" ] && shift
extra="$*"

# Temp name then mv, so a half-copied file is never booted.
put() { cp -L "$1" "$dir/.$2.tmp" && mv -f "$dir/.$2.tmp" "$dir/$2"; }
mkdir -p "$dir"
put "$kernel" Image
put "$dtb" board.dtb
rm -f "$dir/initrd"
args="console=ttyS0,115200 earlycon=sbi panic=10"
if [ -n "$initrd" ]; then
    put "$initrd" initrd
else
    args="$args root=PARTLABEL=root rootwait"
fi
args="$args $extra"

# bootm_size keeps a large initrd in low RAM (see vf2-netboot.py). Any failed
# transfer returns non-zero, so bootcmd falls through to the SD card.
# shellcheck disable=SC2016  # ${...} are U-Boot variables, expanded on the board
{
    echo "setenv bootm_size 0x30000000"
    echo "setenv bootargs '$args'"
    echo 'tftpboot ${kernel_addr_r} visionfive2/Image || exit'
    echo 'tftpboot ${fdt_addr_r} visionfive2/board.dtb || exit'
    if [ -n "$initrd" ]; then
        echo 'tftpboot ${ramdisk_addr_r} visionfive2/initrd || exit'
        echo 'booti ${kernel_addr_r} ${ramdisk_addr_r}:${filesize} ${fdt_addr_r}'
    else
        echo 'booti ${kernel_addr_r} - ${fdt_addr_r}'
    fi
} > "$dir/boot.cmd"
# U-Boot legacy script image, as `mkimage -A riscv -T script -C none` writes it;
# no mkimage on the host, & the Yocto-native one needs its own sysroot libs.
python3 - "$dir/boot.cmd" "$dir/.boot.scr.tmp" <<'EOF_PY'
import struct, sys, time, zlib
cmd = open(sys.argv[1], "rb").read()
data = struct.pack(">II", len(cmd), 0) + cmd          # multi-file table, then the script
# os=linux(5) arch=riscv(26) type=script(6) comp=none(0)
now = int(time.time())
hdr = lambda hcrc: struct.pack(">7I4B32s", 0x27051956, hcrc, now, len(data),
                               0, 0, zlib.crc32(data), 5, 26, 6, 0, b"ens4 netboot")
open(sys.argv[2], "wb").write(hdr(zlib.crc32(hdr(0))) + data)
EOF_PY
mv -f "$dir/.boot.scr.tmp" "$dir/boot.scr"

echo "[stage] $dir:"
ls -la --time-style=+%H:%M "$dir"
echo "[stage] bootargs: $args"
