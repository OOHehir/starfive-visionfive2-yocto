# First boot — what to expect

From a clean flash of `visionfive2-demo-image` (see README "Flash and first
boot"), a cold power-on with **no interaction** reaches the full demo. All
timings measured on hardware (VisionFive 2 v1.3B, class-10 microSD).

## Timeline

| t (from power) | What you see |
|---|---|
| 0–5 s | U-Boot (2 s prompt window) → GRUB → kernel. Serial console on the debug UART (115200 8N1) |
| ~5 s | GT9271 touch controller binds (poll mode) |
| ~9 s | DSI panel self-heals its first-enable race and lights |
| ~19 s | **psplash** boot splash on the panel (landscape) |
| ~25 s | **Weston** starts, GPU-composited (PowerVR), rotated landscape |
| ~30 s | **Status dashboard** fullscreen — live stats, 5 s refresh |
| ~23 s onward | eth1 DHCPs; `http://visionfive2.local/` reachable on the LAN |

## The dashboard

- **Touch** scrolls the page; all controls are touch targets.
- **Doom card → Start** stops Weston and hands the panel to the game
  (doomgeneric + freedoom, software-rendered to the framebuffer, rotated to
  landscape). A USB keyboard plays it: arrows move, Ctrl fires, Space uses,
  Esc for the menu. Plug the keyboard in **before** starting Doom (input
  devices are scanned once at launch).
- **Doom card → Stop** (tap from another device's browser at
  `http://visionfive2.local/status.cgi` while the game owns the panel)
  returns to the dashboard.

## Networking

- Both GbE ports come up automatically; on this board only **eth1** has a
  working PHY (`docs/PRODUCTIONIZE.md` #7) — use the RJ45 closer to the HDMI
  connector if in doubt, or just try both.
- The page is advertised via mDNS (`visionfive2.local`) and by IP.
- WiFi (ECR6600U USB) has firmware in the image; associate at runtime with
  `wpa_supplicant` — no credentials are ever baked in.

## If something is off

- **Panel black but backlight on:** check the serial log for
  `VSG re-armed; next fb-client modeset completes recovery` — normal. If the
  panel stays black past 30 s, see the MIPI-DSI section of `DEV-NOTES.md`.
- **Dashboard white or "Connection terminated unexpectedly":** lighttpd came
  up late once — the kiosk retries every 2 s and recovers by itself.
- **No `visionfive2.local`:** your network may block mDNS; find the IP on
  the dashboard's Network card (or the DHCP server's lease table).
- **Login:** `root`, no password, on serial or SSH (no keys shipped — add
  your own `authorized_keys`).
