#!/bin/bash
# Copy the kernel Image, DTB & bench-wifi initramfs to the bench TFTP dir.
# Safe to re-run; needs the CIFS/autofs mount writable.
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
cp    "$IMG/core-image-weston-visionfive2-bench-wifi.cpio.gz" "$TFTP/bench-wifi.cpio.gz"
sync
set +x
echo "[*] staged to $TFTP:"
ls -la --time-style=+%H:%M "$TFTP/Image" "$TFTP/$DTB" "$TFTP/bench-wifi.cpio.gz"
