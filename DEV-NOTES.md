# Dev notes — problems found on this board and their fixes

Hard-won findings from bringing this image up on real hardware. Each entry:
symptom → root cause → fix, with the in-repo artifact where one exists.
Kept because most of these cost days and none were documented anywhere else.

## Boot chain

### Mainline U-Boot 2026.01 store-faults at kernel handoff when booting a loaded DTB
- **Symptom:** `booti ... ${fdt_addr_r}` (a TFTP-loaded device tree) crashes
  U-Boot with a store fault; booting with `${fdtcontroladdr}` works.
- **Root cause:** the fault PC resolves to `free()` called from
  `xhci_cleanup` — at handoff `announce_and_cleanup()` → `usb_stop()` walks
  a malloc heap that the loaded-DTB path has already corrupted, and VF2's
  xHCI is broken in mainline U-Boot to begin with. `preboot`'s default
  `usb start` is what arms the trap.
- **Fix:** remove `usb start` from the `preboot` env (`setenv preboot; saveenv`).
  With that, the **complete kernel DTB** boots — display, VPU, RTC, CMA and
  all — no overlays needed.

### QSPI U-Boot env is shared with SD boot
The env lives in SPI flash, so an SD-booted U-Boot (or GRUB via distro boot)
still sees whatever `bootdelay`/`preboot` the bench left there. A
`bootdelay=-1` bench setting silently breaks unattended SD boot.

## GPU (Imagination BXE-4-32, closed DDK 1.19)

### pvrsrvkm soft-locks the kernel at module init
- **Symptom:** `modprobe pvrsrvkm` pins one CPU forever in
  `ccache_flush_range` (SiFive L2 flush loop); RCU stalls.
- **Root cause:** `CONFIG_RANDSTRUCT_FULL`, silently enabled through the
  vendor defconfig's `COMPILE_TEST=y`, breaks the out-of-tree closed module.
- **Fix:** `meta-visionfive2-demo/recipes-kernel/linux/files/randstruct.cfg`
  (`RANDSTRUCT_NONE`). After that the DDK loads and `eglinfo` reports
  `PowerVR B-Series BXE-4-32` (GLES 3.2).

### rmmod pvrsrvkm panics — every clean reboot died
- **Symptom:** `reboot` → `Kernel panic ... pvr_exit` (fatal exception in
  interrupt) via the rc.pvr shutdown K-link's rmmod.
- **Fix:** ship start-only init links
  (`visionfive2-pvr-graphics_%.bbappend`: `INITSCRIPT_PARAMS = "start 20 2 3 4 5 ."`).

### dc8200 cannot scan out PVR-tiled GBM buffers
- **Symptom:** GL-composited weston "works" but the panel shows a thin
  column of dots — the display controller interprets a GPU-tiled/modifier
  buffer as linear.
- **Fix:** `WESTON_DISABLE_GBM_MODIFIERS=true` (exported from
  `/etc/default/weston`, see the weston-init bbappend). Any KMS/GBM client
  on this SoC needs linear scanout buffers.

### PVR mesa fork has no software fallback
`/usr/lib/dri` is empty — with the GPU module absent there is **no** EGL at
all (epoxy: "No provider of glViewport"). GTK4's GL renderer segfaults in
that state; `GSK_RENDERER=cairo` is the escape hatch (the kiosk init script
applies it automatically when `pvrsrvkm` isn't loaded).

## MIPI-DSI panel (10.1″ 800×1280 ILI9881C via 22→15-pin converter)

### The mainline ILI9881C page model is wrong for this glass
The panel ("10inch1" class) needs the vendor's **register-0xE0 bank** init
sequence, not the `0xFF,0x98,0x81` page-switch writes mainline emits — with
the wrong model the panel ACKs everything and stays black. Verbatim vendor
init: kernel patch `0004-ili9881c-add-luckfox-10inch1-panel.patch`.

### Panel init ran before the DSI link was up
The StarFive cdns-dsi fork has only `.enable` (no `.pre_enable`), while the
panel sets `prepare_prev_first` — so its init DCS went out on an unconfigured
link. Fix: give the host a real `.pre_enable` that brings up link + PHY
first (`0005-cdns-dsi-pre-enable-ordering.patch`).

### First-enable video-stream race (upstream-known cdns-dsi defect)
- **Symptom:** everything reports success (PLL locked, video "streaming",
  backlight on) but the glass is black on cold boot; any later DPMS
  off/on fixes it. Register truth: `VID_MODE_STS` bit0 (`VSG_RUNNING`)
  stays 0, `VID_VPOS` frozen.
- **Root cause:** the video stream generator is armed after dc8200's DPI is
  already streaming and misses the first vsync — the same defect the
  "drm/bridge: cdns-dsi: Fix the color-shift issue" series fixed upstream;
  the proper fix needs a DRM-core CRTC/bridge reorder that only landed in
  6.17 (unreachable on the DDK-locked 6.12 vendor kernel).
- **Fix:** in-driver self-heal (`0006-cdns-dsi-vsg-selfheal.patch`): if the
  VSG hasn't started, runtime-PM power-cycle the host (re-inits the PHY),
  re-arm, and return — the next fb-client modeset (psplash/fbcon/weston)
  completes the recovery. Polling longer in-line never helps; it only blocks
  the DRM commit queue.
- **Debug tip:** on this host, DCS **reads work only in HS mode** — clear
  `MIPI_DSI_MODE_LPM` around the read. An LP read always returns -110 and
  proves nothing about the panel or the cable.

### GT9271 touch with no INT line
The 22→15-pin converter routes no touch interrupt, so the mainline goodix
driver fails probe (`gpiod_to_irq(NULL)` → -EINVAL). Fix: 60 fps I2C poll
fallback when no int-gpio is present
(`0007-goodix-touch-poll-mode.patch`); the DT node then needs only
`compatible` + `reg`.

### psplash vs a late framebuffer
`/dev/fb0` only appears ~18 s into boot (DRM probe + the VSG self-heal), so
stock psplash exits at rcS with "Framebuffer not detected". The bbappend
ships a wait-for-fb0 variant — and psplash's fb open doubles as the modeset
that completes the display recovery.

## Networking / peripherals

### ECR6600U USB WiFi: firmware must be the buildroot blob, version-matched
`ECR6600U_transport.bin` **from `starfive-tech/buildroot`**
(`JH7110_VisionFive2_devel`) works with the 6.12 `ecrnx` driver
(V1.1.0B04P05T01 == driver V1.1.0B04P05); the blob in the
`eswincomputing/eswin_6600u` repo does not. Packaged in
`recipes-bsp/ecr6600u-firmware`. The module's Bluetooth is vendor BLE only —
no standard HCI, BlueZ can't drive it.

### eth0 vs eth1
On this board eth0's PHY never links (U-Boot: `EQOS_DMA_MODE_SWR stuck`,
autoneg timeout); eth1 works. The stock `/etc/network/interfaces` only
`auto`s eth0 — the init-ifupdown bbappend autos both. Related bench
signature: **both** PHYs timing out at once = check the cable/switch, not
the board.

## Web kiosk (WebKitGTK on the panel)

### "Connection terminated unexpectedly" stuck on screen
lighttpd's default keep-alive idle (~5 s) races the status page's 5 s
meta-refresh: libsoup occasionally reuses a connection the server just
closed, surfaces this error, and WebKit's error page never retries — the
kiosk parks there forever. Two-ended fix: `server.max-keep-alive-idle = 30`
(vf2-status lighttpd conf) + a `load-failed` handler in vf2-kiosk that
suppresses the error page and retries.

### Debugging "what is actually on the panel"
Under GL weston, `/dev/fb0` shows a stale black buffer — dumping it proves
nothing. `weston --debug` + `weston-screenshooter` captures the real
composited output. Triangulate display state with: the VSG bit
(`/dev/mem` 0x295d00f0 bit0), `/sys/class/backlight/*`, and a screenshot.

## Yocto specifics

- **wic kickstart search path** is `<layer>/files/wic/`, not `<layer>/wic/`.
- The demo `.wks` selects the DSI device tree via the `bootimg-efi`
  `dtb=` sourceparam — that's what GRUB hands the kernel.
- Current oe-core hard-fails recipes with `S = "${WORKDIR}/..."`
  (use `${UNPACKDIR}`), bare `S = "${WORKDIR}/git"` (delete the line), and
  patches without an `Upstream-Status:` header.
- `weston-init`: `/etc/default/weston` is sourced by the init script, so
  `export`ed variables there reach the compositor — the clean way to inject
  env like `WESTON_DISABLE_GBM_MODIFIERS`.

## Bench / flashing

- **doomgeneric input is scanned once at launch** — plug the USB keyboard in
  before starting the game.
- **bmaptool `O_EXCL` loses to udisks auto-probing** on desktop hosts;
  plain `dd` + a `cmp` read-back verify is the reliable path
  (`scripts/flash-sd.sh`). Wiping the GPT head doesn't kill partitions —
  the backup table at the end of the disk resurrects them.
- **Never swap the SD under a live system**: the old session keeps running
  from RAM but can exec nothing, and without `CONFIG_MAGIC_SYSRQ` (off in
  the vendor config) only a power-cycle recovers.
