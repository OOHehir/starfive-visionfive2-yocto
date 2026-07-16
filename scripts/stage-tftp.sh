#!/bin/bash
# Stage the current netboot artifacts to the bench TFTP dir. Idempotent: run it
# whenever the CIFS/autofs mount is writable. Stages the freshly-built kernel
# Image, the full kernel DTB, and the safe-boot GPU-test initramfs.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMG="$ROOT/build/tmp/deploy/images/visionfive2"
TFTP="${TFTP:-/media/dsCIFS/public/tftp/visionfive2}"
DTB="jh7110-starfive-visionfive-2-v1.3b.dtb"

if [ ! -w "$TFTP" ]; then
    echo "[!] $TFTP not writable — remount/refresh the NAS mount first." >&2
    exit 1
fi

set -x
cp -L "$IMG/Image"                                        "$TFTP/Image"
cp -L "$IMG/$DTB"                                         "$TFTP/$DTB"
cp    "$IMG/core-image-weston-visionfive2-nogpu-wifi.cpio.gz" "$TFTP/nogpu-wifi.cpio.gz"
sync
set +x
echo "[*] staged to $TFTP:"
ls -la --time-style=+%H:%M "$TFTP/Image" "$TFTP/$DTB" "$TFTP/nogpu-wifi.cpio.gz"
