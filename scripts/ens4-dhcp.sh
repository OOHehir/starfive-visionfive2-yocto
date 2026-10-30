#!/usr/bin/env bash
# DHCP + TFTP for a VF2 cabled straight to this host's ens4 (no LAN, no NAS).
# Pins ens4 to a static address via NetworkManager, then runs dnsmasq in the
# foreground (Ctrl-C to stop). Run as root: binding ports 67 & 69 needs it.
# Usage: sudo scripts/ens4-dhcp.sh        Env: IFACE HOST_IP BOARD_MAC BOARD_IP TFTP_ROOT
# The board netboots only if TFTP_ROOT/visionfive2/boot.scr exists; see
# scripts/stage-ens4-netboot.sh. Without it, U-Boot falls back to the SD card.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

IFACE="${IFACE:-ens4}"
HOST_IP="${HOST_IP:-192.168.50.1}"
BOARD_MAC="${BOARD_MAC:-ea:da:4c:41:09:9c}"   # Linux on the board: random MAC (no local-mac-address)
BOARD_MAC_UBOOT="${BOARD_MAC_UBOOT:-6c:cf:39:00:69:82}"  # U-Boot: ethaddr from EEPROM (gmac0)
BOARD_IP="${BOARD_IP:-192.168.50.20}"
TFTP_ROOT="${TFTP_ROOT:-$(cd "$here/.." && pwd)/tftp}"

[ "$(id -u)" = 0 ] || { echo "run as root (sudo $0)" >&2; exit 1; }

# A DHCP-client profile on ens4 times out and strips any hand-added address,
# so make the profile itself static.
con="$(nmcli -g GENERAL.CONNECTION device show "$IFACE")"
if [ -n "$con" ] && [ "$(nmcli -g ipv4.method con show "$con")" != manual ]; then
    nmcli con mod "$con" ipv4.method manual ipv4.addresses "$HOST_IP/24" ipv6.method link-local
    nmcli con up "$con" >/dev/null
fi
ip -4 addr show dev "$IFACE" | grep -q "inet $HOST_IP/" \
    || ip addr add "$HOST_IP/24" dev "$IFACE"

mkdir -p "$TFTP_ROOT/visionfive2"
# Staging runs unprivileged, so the invoking user keeps ownership.
[ -n "${SUDO_USER:-}" ] && chown -R "$SUDO_USER:" "$TFTP_ROOT"
echo "[ens4-dhcp] $IFACE $HOST_IP, board -> $BOARD_IP, tftp-root $TFTP_ROOT"

# --port=0: no DNS. Both board MACs get the same address, so U-Boot and Linux
# agree. dhcp-boot sets next-server, which U-Boot copies to ${serverip}.
exec dnsmasq --no-daemon --port=0 --interface="$IFACE" --bind-interfaces \
    --dhcp-range="${HOST_IP%.*}.10,${HOST_IP%.*}.50,12h" \
    --dhcp-host="$BOARD_MAC,$BOARD_MAC_UBOOT,$BOARD_IP" \
    --dhcp-boot="visionfive2/boot.scr,,$HOST_IP" \
    --enable-tftp --tftp-root="$TFTP_ROOT" --log-dhcp
