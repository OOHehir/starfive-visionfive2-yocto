#!/bin/sh
# Build the bench initramfs (…-bench-wifi.cpio.gz) from core-image-weston plus the
# workarounds still to move into recipes (docs/PRODUCTIONIZE.md). VF2_GPU=0: no GPU.
# Needs scratch_fw/ECR6600U_transport.bin & wifi_ecr6600u.cfg.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMG="$ROOT/build/tmp/deploy/images/visionfive2"
TFTP="/media/dsCIFS/public/tftp/visionfive2"
WORK="$ROOT/scratch_rootfs"

SRC="$(readlink -f "$IMG/core-image-weston-visionfive2.rootfs.cpio.gz")"
echo "[*] source rootfs: $SRC"
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"
zcat "$SRC" | cpio -idm --quiet

# GPU on by default: the PVR mesa fork has no software fallback, so WebKit needs it.
# K links always go: rc.pvr's shutdown rmmod panics in pvr_exit on every reboot.
rm -f etc/rc[0-6].d/K??rc.pvr
if [ "${VF2_GPU:-1}" = 0 ]; then
    rm -f etc/rc[2-5].d/S??rc.pvr etc/modules-load.d/pvrsrvkm.conf
    echo "[*] VF2_GPU=0: GPU autoload disabled (weston -> pixman)"
fi

cp "$ROOT/scratch_fw/ECR6600U_transport.bin" "$ROOT/scratch_fw/wifi_ecr6600u.cfg" lib/firmware/

if [ "${VF2_GPU:-1}" = 0 ]; then
    printf '\n# GPU (pvrsrvkm) disabled in this image -> software renderer\nOPTARGS="--renderer=pixman"\n' >> etc/default/weston
fi

# Stock psplash exits without /dev/fb0, which DSI only provides ~18 s in; wait in the
# background. Its fb open also completes the 0006 VSG recovery. 270 matches Doom.
echo 270 > etc/rotation
cat > etc/init.d/psplash.sh <<'EOF'
#!/bin/sh
### BEGIN INIT INFO
# Provides:             psplash
# Required-Start:
# Required-Stop:
# Default-Start:        S
# Default-Stop:
### END INIT INFO
# Bench variant: the DSI /dev/fb0 appears ~18 s into boot, long after rcS S00,
# so wait for it in the background instead of the stock early-exit.
. /etc/default/rcS
export PSPLASH_FIFO_DIR
case "$(cat /proc/cmdline)" in *psplash=false*) exit 0;; esac
(
    n=0
    while [ ! -e /dev/fb0 ] && [ $n -lt 60 ]; do sleep 0.5; n=$((n+1)); done
    [ -e /dev/fb0 ] || exit 0
    if [ -n "${PSPLASH_FIFO_DIR}" ]; then
        [ -d "$PSPLASH_FIFO_DIR" ] || mkdir -p "$PSPLASH_FIFO_DIR"
        mountpoint -q "$PSPLASH_FIFO_DIR" || \
            mount tmpfs -t tmpfs "$PSPLASH_FIFO_DIR" -o,size=40k
    fi
    rotation=0
    [ -e /etc/rotation ] && read rotation < /etc/rotation
    /usr/bin/psplash --angle $rotation &
) &
exit 0
EOF
chmod +x etc/init.d/psplash.sh

# Bench SSH key: the serial console drops characters on long lines.
if [ -f "$ROOT/scratch_keys/vf2_key.pub" ]; then
    mkdir -p home/root/.ssh && chmod 700 home/root/.ssh
    cp "$ROOT/scratch_keys/vf2_key.pub" home/root/.ssh/authorized_keys
    chmod 600 home/root/.ssh/authorized_keys
fi

# HACK: no-touch probe of DSI VSG state to 130 s uptime, dumped to serial, to see if
# 0006 starts the panel unaided. Remove once M2 cold-boot determinism is settled.
cat > usr/sbin/vsg-probe.py <<'EOF'
import mmap, os, time
BASE = 0x295d0000            # cdns-dsi host
def up(): return float(open('/proc/uptime').read().split()[0])
f = os.open('/dev/mem', os.O_RDONLY | os.O_SYNC)
m = mmap.mmap(f, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ, offset=BASE)
def rd(off): return int.from_bytes(m[off:off+4], 'little')
log = open('/tmp/vsg-probe.log', 'w', buffering=1)
while up() < 130:
    t = up(); sts = rd(0xf0); v1 = rd(0xe8); time.sleep(0.02); v2 = rd(0xe8)
    w = 'y' if os.system('pidof weston >/dev/null 2>&1') == 0 else 'n'
    log.write("t=%7.2f sts=0x%08x vsg=%d vpos=0x%x->0x%x weston=%s\n"
              % (t, sts, sts & 1, v1, v2, w))
    time.sleep(3)
os.system('{ echo "===VSG-PROBE==="; cat /tmp/vsg-probe.log; echo "===VSG-PROBE-END==="; } >/dev/console 2>/dev/null')
os.system('udhcpc -b -i eth1 >/dev/null 2>&1')
EOF
cat > etc/init.d/vsg-probe <<'EOF'
#!/bin/sh
# TEMP bench diagnostic — see usr/sbin/vsg-probe.py
[ "$1" = start ] && /usr/bin/python3 /usr/sbin/vsg-probe.py >/dev/null 2>&1 &
exit 0
EOF
chmod +x etc/init.d/vsg-probe
ln -sf ../init.d/vsg-probe etc/rcS.d/S41vsg-probe

# Doom's autostart stops weston & redraws fb0 at ~30 s, confounding the VSG probe.
# VF2_DIAG=0 restores it.
if [ "${VF2_DIAG:-1}" = 1 ] && [ -e etc/rc5.d/S99doom ]; then
    rm -f etc/rc5.d/S99doom
    echo "[*] VF2_DIAG=1: removed Doom autostart (S99doom) for the probe run"
fi

OUT="$IMG/core-image-weston-visionfive2-bench-wifi.cpio.gz"
find . | cpio -o -H newc --owner=root:root --quiet | gzip -1 > "$OUT"
echo "[*] built: $(ls -la "$OUT")"
# Best-effort: the CIFS/autofs mount is sometimes down.
if [ -w "$TFTP" ] && cp "$OUT" "$TFTP/bench-wifi.cpio.gz" 2>/dev/null; then
    echo "[*] staged: $(ls -la "$TFTP/bench-wifi.cpio.gz")"
else
    echo "[!] TFTP ($TFTP) not writable — skipped staging. Copy manually:"
    echo "    cp $OUT $TFTP/bench-wifi.cpio.gz"
fi
echo "[*] sanity:"
echo "    iw:        $([ -e "$WORK/usr/sbin/iw" ] && echo yes)"
echo "    alsa:      $([ -e "$WORK/usr/bin/aplay" ] && echo yes)"
echo "    bluez:     $([ -e "$WORK/usr/bin/bluetoothctl" ] && echo yes)"
echo "    wifi fw:   $([ -e "$WORK/lib/firmware/ECR6600U_transport.bin" ] && echo yes)"
echo "    pvr start: $(ls "$WORK"/etc/rc?.d/*rc.pvr 2>/dev/null | grep -c S20) (want $([ "${VF2_GPU:-1}" = 0 ] && echo 0 || echo '>0'))"
