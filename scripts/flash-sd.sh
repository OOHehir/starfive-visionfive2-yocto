#!/usr/bin/env bash
# Write the VF2 wic image to an SD card; refuses any target that is not removable,
# not USB or over 64 GB, so a fixed disk is never written.
#   ./scripts/flash-sd.sh /dev/sdb    (VF2_WIC=/path/to.wic.gz overrides the image)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; source "$here/netboot.env" 2>/dev/null || true
DEV="${1:?usage: flash-sd.sh /dev/sdX}"
TOP="${VF2_TOP:-$(cd "$here/.." && pwd)}"
DEPLOY="${VF2_DEPLOY:-$TOP/build/tmp/deploy/images/visionfive2}"
WIC="${VF2_WIC:-$DEPLOY/core-image-weston-visionfive2.rootfs.wic.gz}"
BMAP="${WIC%.gz}.bmap"; [ -f "$BMAP" ] || BMAP="${WIC%.wic.gz}.wic.bmap"

base="$(basename "$DEV")"
rm=$(cat "/sys/block/$base/removable" 2>/dev/null || echo 0)
tran=$(lsblk -ndo TRAN "$DEV" 2>/dev/null || echo "")
sectors=$(cat "/sys/block/$base/size" 2>/dev/null || echo 0)
gb=$(( sectors / 2 / 1024 / 1024 ))

echo "target : $DEV  (removable=$rm tran=$tran size=${gb}GB)"
echo "image  : $WIC"
[ "$rm" = "1" ]      || { echo "REFUSE: $DEV is not removable"; exit 1; }
[ "$tran" = "usb" ]  || { echo "REFUSE: $DEV is not USB (tran=$tran)"; exit 1; }
[ "$gb" -le 64 ]     || { echo "REFUSE: $DEV is ${gb}GB (>64GB) — looks like a fixed disk"; exit 1; }
[ "$base" != "sda" ] || { echo "REFUSE: never write sda"; exit 1; }
[ -f "$WIC" ]        || { echo "REFUSE: image not found: $WIC"; exit 1; }

echo ">> flashing (bmaptool)…"
if [ -f "$BMAP" ]; then bmaptool copy --bmap "$BMAP" "$WIC" "$DEV"
else                    bmaptool copy "$WIC" "$DEV"; fi
sync

echo ">> read-back verify (guards against the flaky reader)…"
# The bench's Super Top reader corrupts writes on xHCI; trust nothing unverified.
img_bytes=$(gzip -l "$WIC" | awk 'NR==2{print $2}')
if cmp -n "$img_bytes" <(gunzip -c "$WIC") "$DEV"; then
    echo "VERIFY OK — $DEV matches the image."
else
    echo "VERIFY FAILED — do NOT boot this card (reader corruption? try a USB-2 port)."; exit 1
fi
echo "Done. Set VF2 boot-mode DIP switches to SDIO, insert the card, power on."
