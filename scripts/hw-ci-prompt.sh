#!/usr/bin/env bash
# Login-time reminder for hw-ci-run.sh, started from ~/.config/autostart. Asks at
# most once a day, & only when no leg has run for HW_CI_EVERY_DAYS (default 7).
# Usage: hw-ci-prompt.sh [--now]     --now: skip the login delay & the once-a-day limit
set -uo pipefail
top="$(cd "$(dirname "$0")/.." && pwd)"
RUNS="${RUNS:-$top/private-notes/ci-runner/runs}"
days="${HW_CI_EVERY_DAYS:-7}"
asked="${XDG_CACHE_HOME:-$HOME/.cache}/vf2-hw-ci-asked"

if [ "${1:-}" != --now ]; then
    # Let the desktop's notification daemon start before asking.
    sleep 90
    [ -n "$(find "$asked" -mmin -1440 2>/dev/null)" ] && exit 0
fi

last=0
for l in "$RUNS"/latest-*; do
    [ -e "$l" ] || continue
    t="$(stat -L -c %Y "$l")"
    [ "$t" -gt "$last" ] && last="$t"
done
age=$(( ($(date +%s) - last) / 86400 ))
[ "$last" -gt 0 ] && [ "$age" -lt "$days" ] && [ "${1:-}" != --now ] && exit 0

mkdir -p "$(dirname "$asked")" && touch "$asked"
if [ "$last" -gt 0 ]; then when="Last run $age days ago."; else when="No run yet."; fi
choice="$(notify-send -a "VF2 bench" -i computer -A run="Run now" -A later="Later" \
    "VisionFive 2 hardware CI" "$when Build meta-riscv master & linux-next, then test them on the board?")"
[ "$choice" = run ] || exit 0
exec gnome-terminal --title "VF2 hardware CI" -- bash -c \
    "'$top/scripts/hw-ci-run.sh' all; echo; read -rp 'Finished. Press Enter to close. '"
