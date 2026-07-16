#!/bin/sh
# Build the bench "bring-up" initramfs from the freshly-built core-image-weston
# rootfs by re-applying the runtime workarounds we iterate on (see
# docs/PRODUCTIONIZE.md — these should eventually move into recipes):
#   1. disable GPU (pvrsrvkm) autoload      -> boot doesn't soft-lock (docs #2)
#   2. add version-matched ECR6600U wifi fw  -> wlan0            (docs #4)
#   3. weston software (pixman) renderer     -> Weston on HDMI   (docs #1/M0)
# Output: core-image-weston-visionfive2-nogpu-wifi.cpio.gz, staged to TFTP.
#
# Requires scratch_fw/ECR6600U_transport.bin + wifi_ecr6600u.cfg (already fetched).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMG="$ROOT/build/tmp/deploy/images/visionfive2"
TFTP="/media/dsCIFS/public/tftp/visionfive2"
WORK="$ROOT/scratch_rootfs"

SRC="$(readlink -f "$IMG/core-image-weston-visionfive2.rootfs.cpio.gz")"
echo "[*] source rootfs: $SRC"
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"
zcat "$SRC" | cpio -idm --quiet

# 1. GPU (pvrsrvkm). The RANDSTRUCT soft-lock is fixed (M1: PowerVR renderer
#    confirmed), so the demo default is GPU ON — weston gets the GL renderer
#    and the webkit kiosk gets real GLES (the PVR mesa fork has no software
#    fallback; without the GPU webkit shows a white screen, "No provider of
#    glViewport"). VF2_GPU=0 reverts to the pixman/no-GPU bring-up config.
#    Always drop the stop/K links: rc.pvr's shutdown rmmod panics in pvr_exit
#    (broken DDK module) and turns every clean reboot into a kernel panic.
rm -f etc/rc[0-6].d/K??rc.pvr
if [ "${VF2_GPU:-1}" = 0 ]; then
    rm -f etc/rc[2-5].d/S??rc.pvr etc/modules-load.d/pvrsrvkm.conf
    echo "[*] VF2_GPU=0: GPU autoload disabled (weston -> pixman)"
fi

# 2. WiFi firmware (+cfg)
cp "$ROOT/scratch_fw/ECR6600U_transport.bin" "$ROOT/scratch_fw/wifi_ecr6600u.cfg" lib/firmware/

# 3. Weston renderer: GL on the PVR GPU by default; pixman when VF2_GPU=0.
if [ "${VF2_GPU:-1}" = 0 ]; then
    printf '\n# GPU (pvrsrvkm) disabled in this image -> software renderer\nOPTARGS="--renderer=pixman"\n' >> etc/default/weston
fi

# 3b. psplash: stock S00psplash.sh hard-exits when /dev/fb0 is missing — and on
#     this board the DSI fb only appears ~18 s in (DRM probe + VSG self-heal).
#     Replace it with a backgrounded wait-for-fb0 (rcS stays non-blocking); the
#     psplash fb open then doubles as the fb-client modeset that completes the
#     0006 VSG recovery. Rotated 270 to match Doom's landscape orientation
#     (90 came up 180 degrees off Doom's — user-verified on the glass).
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

# 4. Bench SSH key (serial drops chars on long lines; root home is /home/root)
if [ -f "$ROOT/scratch_keys/vf2_key.pub" ]; then
    mkdir -p home/root/.ssh && chmod 700 home/root/.ssh
    cp "$ROOT/scratch_keys/vf2_key.pub" home/root/.ssh/authorized_keys
    chmod 600 home/root/.ssh/authorized_keys
fi

# 5. TEMP bench diagnostic: no-touch VSG probe (JOURNAL 2026-07-15 22:05 step 1).
#    Samples the DSI host VID_MODE_STS (VSG_RUNNING bit0) + VID_VPOS every ~3 s
#    until uptime 130 s with ZERO manual interaction, then dumps the timeline to
#    the serial console and DHCPs eth1 so SSH is reachable. Settles whether the
#    0006 self-heal makes the panel start on its own (and when) vs only after
#    console/weston activity. Remove once M2 cold-boot determinism is settled.
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

# 5b. While diagnosing (VF2_DIAG=1, current default): keep Doom's autostart out
#     of the probe window — it stops weston + redraws fb0 at ~30 s, which would
#     confound the no-touch VSG timeline. Doom stays installed (run
#     /etc/init.d/doom start manually). VF2_DIAG=0 restores the demo autostart.
if [ "${VF2_DIAG:-1}" = 1 ] && [ -e etc/rc5.d/S99doom ]; then
    rm -f etc/rc5.d/S99doom
    echo "[*] VF2_DIAG=1: removed Doom autostart (S99doom) for the probe run"
fi

OUT="$IMG/core-image-weston-visionfive2-nogpu-wifi.cpio.gz"
find . | cpio -o -H newc --owner=root:root --quiet | gzip -1 > "$OUT"
echo "[*] built: $(ls -la "$OUT")"
# TFTP staging is best-effort: the CIFS/autofs mount is sometimes down. The
# artifact above is always produced; stage it when the mount is reachable.
if [ -w "$TFTP" ] && cp "$OUT" "$TFTP/nogpu-wifi.cpio.gz" 2>/dev/null; then
    echo "[*] staged: $(ls -la "$TFTP/nogpu-wifi.cpio.gz")"
else
    echo "[!] TFTP ($TFTP) not writable — skipped staging. Copy manually:"
    echo "    cp $OUT $TFTP/nogpu-wifi.cpio.gz"
fi
echo "[*] sanity:"
echo "    iw:        $([ -e "$WORK/usr/sbin/iw" ] && echo yes)"
echo "    alsa:      $([ -e "$WORK/usr/bin/aplay" ] && echo yes)"
echo "    bluez:     $([ -e "$WORK/usr/bin/bluetoothctl" ] && echo yes)"
echo "    wifi fw:   $([ -e "$WORK/lib/firmware/ECR6600U_transport.bin" ] && echo yes)"
echo "    pvr start: $(ls "$WORK"/etc/rc?.d/*rc.pvr 2>/dev/null | grep -c S20) (want 0)"
