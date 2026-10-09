#!/usr/bin/env bash
# Build -> deploy -> power-cycle -> capture loop for netbooting the VF2 over TFTP+NFS.
# Usage: netboot.sh {build|deploy|capture [LOG]|cycle|loop}   See docs/DEV_SETUP.md.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/netboot.env"
log() { printf '[netboot %s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

do_build() {
    log "bitbake $VF2_IMAGE (MACHINE=$VF2_MACHINE)"
    ( cd "$VF2_TOP/sources/oe-core" \
      && source oe-init-build-env "$VF2_TOP/build" >/dev/null \
      && bitbake "$VF2_IMAGE" )
}

# Copy to a temp name, then mv, so a half-copied kernel or DTB is never booted.
do_deploy() {
    [ -d "$VF2_DEPLOY" ] || { log "ERROR: deploy dir missing: $VF2_DEPLOY"; exit 1; }
    mkdir -p "$TFTP_LOCAL"
    for f in "$VF2_KERNEL" "$VF2_DTB"; do
        src="$VF2_DEPLOY/$f"
        [ -e "$src" ] || { log "ERROR: missing artifact $src"; exit 1; }
        log "stage $f"
        cp -f "$src" "$TFTP_LOCAL/.$f.tmp" && mv -f "$TFTP_LOCAL/.$f.tmp" "$TFTP_LOCAL/$f"
    done
    # Extract beside the live rootfs & swap in; the previous one is kept as rootfs.old.
    if [ -e "$VF2_DEPLOY/$VF2_ROOTFS_TAR" ]; then
        log "extract rootfs -> $TFTP_LOCAL/rootfs"
        rm -rf "$TFTP_LOCAL/rootfs.new"
        mkdir -p "$TFTP_LOCAL/rootfs.new"
        sudo tar -C "$TFTP_LOCAL/rootfs.new" -xzf "$VF2_DEPLOY/$VF2_ROOTFS_TAR"
        rm -rf "$TFTP_LOCAL/rootfs.old"
        [ -d "$TFTP_LOCAL/rootfs" ] && mv "$TFTP_LOCAL/rootfs" "$TFTP_LOCAL/rootfs.old"
        mv "$TFTP_LOCAL/rootfs.new" "$TFTP_LOCAL/rootfs"
    fi
    log "deploy complete -> $TFTP_LOCAL"
}

do_capture() {
    local out="${1:-$VF2_TOP/build/serial-$(date +%Y%m%d-%H%M%S).log}"
    log "capturing $SERIAL_DEV @ $SERIAL_BAUD -> $out (Ctrl-C to stop)"
    command -v stty >/dev/null && stty -F "$SERIAL_DEV" "$SERIAL_BAUD" raw -echo 2>/dev/null || true
    exec cat "$SERIAL_DEV" | tee "$out"
}

do_cycle() {
    case "$POWER_METHOD" in
      ppk2)
        # No CLI drives the PPK2; power is cycled out of band via the ppk2 MCP tools.
        log "PPK2 power-cycle: toggle DUT power off->on (voltage ${PPK2_VOLTAGE_MV}mV)"
        log "  (agent: call ppk2_configure dut_power off, wait 2s, then on)"
        ;;
      manual)
        log "MANUAL: power-cycle the board now, then press Enter"; read -r ;;
      *) log "ERROR: unknown POWER_METHOD=$POWER_METHOD"; exit 1 ;;
    esac
}

case "${1:-loop}" in
    build)   do_build ;;
    deploy)  do_deploy ;;
    capture) shift; do_capture "${1:-}" ;;
    cycle)   do_cycle ;;
    loop)    do_build && do_deploy && do_cycle && do_capture ;;
    *) echo "usage: $0 {build|deploy|capture|cycle|loop}"; exit 2 ;;
esac
