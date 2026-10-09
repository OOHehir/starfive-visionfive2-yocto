#!/bin/sh
# Status page (lighttpd CGI), ported from luckfox-lyra-ultra-yocto.
case "$QUERY_STRING" in
    doom=start)
        /etc/init.d/doom start >/dev/null 2>&1
        echo "Status: 303 See Other"; echo "Location: /status.cgi"; echo ""
        exit 0
        ;;
    doom=stop)
        /etc/init.d/doom stop >/dev/null 2>&1
        # Starting Doom stopped Weston & with it the kiosk: bring both back.
        /etc/init.d/weston start >/dev/null 2>&1
        /etc/init.d/vf2-kiosk start >/dev/null 2>&1
        echo "Status: 303 See Other"; echo "Location: /status.cgi"; echo ""
        exit 0
        ;;
esac

echo "Content-Type: text/html"
echo ""

HOSTNAME=$(hostname)
UPTIME=$(uptime -p 2>/dev/null || uptime | sed 's/.*up /up /' | sed 's/,.*load.*//')
LOAD=$(cat /proc/loadavg | cut -d' ' -f1-3)
NPROC=$(nproc)

MEM_TOTAL=$(awk '/^MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo)
MEM_AVAIL=$(awk '/^MemAvailable/ {printf "%.0f", $2/1024}' /proc/meminfo)
MEM_USED=$((MEM_TOTAL - MEM_AVAIL))
MEM_PCT=$((MEM_USED * 100 / MEM_TOTAL))
CMA_TOTAL=$(awk '/^CmaTotal/ {printf "%.0f", $2/1024}' /proc/meminfo)
CMA_FREE=$(awk '/^CmaFree/  {printf "%.0f", $2/1024}' /proc/meminfo)

WIFI_IF=$(ls /sys/class/net/ 2>/dev/null | grep -E '^wl' | head -n1)
if [ -n "$WIFI_IF" ]; then
    WIFI_IP=$(ip -4 addr show "$WIFI_IF" 2>/dev/null | awk '/inet / {print $2}')
    WIFI_SSID=$(iw dev "$WIFI_IF" link 2>/dev/null | awk '/SSID/ {print $2}')
    WIFI_STATE=$(cat /sys/class/net/"$WIFI_IF"/operstate 2>/dev/null)
fi

KERNEL=$(uname -r)
MODEL=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null)
TEMP=$(awk '{printf "%.1f", $1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
CPU_FREQ=$(awk '{printf "%.0f", $1/1000}' /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)

ROOT_DEV=$(mount | awk '/ on \/ / {print $1; exit}')
if grep -q 'root=/dev/ram' /proc/cmdline 2>/dev/null; then
    BOOT_MEDIA="initramfs (netboot)"
    MEDIA_SIZE="RAM"
elif echo "$ROOT_DEV" | grep -q 'mmcblk'; then
    BOOT_MEDIA="SD card"
    MEDIA_SIZE=$(awk '{printf "%.1f GB", $1 * 512 / 1073741824}' /sys/class/block/mmcblk1/size 2>/dev/null)
else
    BOOT_MEDIA="unknown"
    MEDIA_SIZE="n/a"
fi
DISK_USED=$(df / | awk 'NR==2 {printf "%.0f", $3/1024}')
DISK_TOTAL=$(df / | awk 'NR==2 {printf "%.0f", $2/1024}')
DISK_PCT=$(df / | awk 'NR==2 {gsub(/%/,""); print $5}')

FB_RES=$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null | tr ',' 'x')
DSI_STATUS=$(cat /sys/class/drm/card*-DSI-1/status 2>/dev/null | head -n1)
WESTON_STATE=$(pidof weston >/dev/null 2>&1 && echo running || echo stopped)
DOOM_STATE=$(pidof doomgeneric >/dev/null 2>&1 && echo running || echo stopped)
TOUCH_DEV=$(grep -l Goodix /sys/class/input/input*/name 2>/dev/null | head -n1)
TOUCH_STATE=$([ -n "$TOUCH_DEV" ] && echo present || echo absent)

cat <<HTML
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="5">
<title>${HOSTNAME}</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: -apple-system, sans-serif; background: #0d1117; color: #c9d1d9; padding: 2rem; }
  h1 { color: #58a6ff; margin-bottom: 0.5rem; }
  .subtitle { color: #8b949e; margin-bottom: 2rem; }
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 1rem; }
  .card { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 1.2rem; }
  .card h2 { color: #58a6ff; font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 0.8rem; }
  .stat { display: flex; justify-content: space-between; padding: 0.4rem 0; border-bottom: 1px solid #21262d; }
  .stat:last-child { border-bottom: none; }
  .label { color: #8b949e; }
  .value { color: #f0f6fc; font-family: monospace; }
  .bar { background: #21262d; border-radius: 4px; height: 8px; margin-top: 0.5rem; }
  .bar-fill { background: #58a6ff; border-radius: 4px; height: 100%; }
  .btn { display: inline-block; padding: 0.6rem 1.4rem; border: 1px solid #30363d; border-radius: 6px; background: #21262d; color: #c9d1d9; text-decoration: none; font-size: 1rem; margin-right: 0.5rem; }
  .btn.active { background: #1f6feb; border-color: #1f6feb; color: #fff; }
</style>
</head>
<body>
<h1>${HOSTNAME}</h1>
<p class="subtitle">${MODEL}</p>
<div class="grid">
  <div class="card">
    <h2>System</h2>
    <div class="stat"><span class="label">Uptime</span><span class="value">${UPTIME}</span></div>
    <div class="stat"><span class="label">Kernel</span><span class="value">${KERNEL}</span></div>
    <div class="stat"><span class="label">CPUs</span><span class="value">${NPROC}</span></div>
    <div class="stat"><span class="label">CPU Freq</span><span class="value">${CPU_FREQ:-?} MHz</span></div>
    <div class="stat"><span class="label">Load (1/5/15 min)</span><span class="value">${LOAD}</span></div>
    <div class="stat"><span class="label">Temperature</span><span class="value">${TEMP:-n/a} &deg;C</span></div>
  </div>
  <div class="card">
    <h2>Memory</h2>
    <div class="stat"><span class="label">Used / Total</span><span class="value">${MEM_USED} / ${MEM_TOTAL} MB</span></div>
    <div class="bar"><div class="bar-fill" style="width:${MEM_PCT}%"></div></div>
    <div class="stat"><span class="label">CMA Total</span><span class="value">${CMA_TOTAL:-n/a} MB</span></div>
    <div class="stat"><span class="label">CMA Free</span><span class="value">${CMA_FREE:-n/a} MB</span></div>
  </div>
HTML

for ETH_IF in eth0 eth1; do
    [ -d /sys/class/net/$ETH_IF ] || continue
    IP_ADDR=$(ip -4 addr show "$ETH_IF" 2>/dev/null | awk '/inet / {print $2}')
    MAC_ADDR=$(cat /sys/class/net/"$ETH_IF"/address 2>/dev/null)
    LINK_SPEED=$(cat /sys/class/net/"$ETH_IF"/speed 2>/dev/null)
    LINK_STATE=$(cat /sys/class/net/"$ETH_IF"/operstate 2>/dev/null)
cat <<HTML
  <div class="card">
    <h2>Network (${ETH_IF})</h2>
    <div class="stat"><span class="label">State</span><span class="value">${LINK_STATE:-n/a}</span></div>
    <div class="stat"><span class="label">IP Address</span><span class="value">${IP_ADDR:-down}</span></div>
    <div class="stat"><span class="label">MAC</span><span class="value">${MAC_ADDR:-n/a}</span></div>
    <div class="stat"><span class="label">Link Speed</span><span class="value">${LINK_SPEED:-?} Mbps</span></div>
  </div>
HTML
done

if [ -n "$WIFI_IF" ]; then
cat <<HTML
  <div class="card">
    <h2>WiFi (${WIFI_IF})</h2>
    <div class="stat"><span class="label">State</span><span class="value">${WIFI_STATE:-n/a}</span></div>
    <div class="stat"><span class="label">IP Address</span><span class="value">${WIFI_IP:-down}</span></div>
    <div class="stat"><span class="label">SSID</span><span class="value">${WIFI_SSID:-n/a}</span></div>
  </div>
HTML
fi

cat <<HTML
  <div class="card">
    <h2>Storage</h2>
    <div class="stat"><span class="label">Boot Media</span><span class="value">${BOOT_MEDIA}</span></div>
    <div class="stat"><span class="label">Device</span><span class="value">${ROOT_DEV} (${MEDIA_SIZE})</span></div>
    <div class="stat"><span class="label">Rootfs Used</span><span class="value">${DISK_USED} / ${DISK_TOTAL} MB</span></div>
    <div class="bar"><div class="bar-fill" style="width:${DISK_PCT}%"></div></div>
  </div>
  <div class="card">
    <h2>Display</h2>
    <div class="stat"><span class="label">DSI Panel</span><span class="value">${DSI_STATUS:-n/a}</span></div>
    <div class="stat"><span class="label">Framebuffer</span><span class="value">${FB_RES:-none}</span></div>
    <div class="stat"><span class="label">Touch (GT9271)</span><span class="value">${TOUCH_STATE}</span></div>
    <div class="stat"><span class="label">Weston</span><span class="value">${WESTON_STATE}</span></div>
  </div>
  <div class="card">
    <h2>Doom (${DOOM_STATE})</h2>
    <div class="stat" style="border:none">
      <span>
        <a class="btn$([ "$DOOM_STATE" = running ] && echo ' active')" href="/status.cgi?doom=start">Start</a>
        <a class="btn" href="/status.cgi?doom=stop">Stop</a>
      </span>
    </div>
    <div class="stat" style="border:none"><span class="label">Start hands the panel to the game; Stop returns to this page.</span></div>
  </div>
</div>
</body>
</html>
HTML
