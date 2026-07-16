# Productionization plan — fold runtime workarounds into the build

During hardware bring-up we use fast, throwaway runtime workarounds (DT overlays,
hand-modified initramfs, manually-set U-Boot env, kernel cmdline flags) so we can
iterate in seconds instead of full Yocto rebuilds. **None of these are the final
form.** This doc tracks each one and where it must land in the layer/recipes before
the image is reproducible from `bitbake` alone.

Status: `RUNTIME` = live hack in use · `TODO` = not yet productionized · `DONE` = baked in.

---

## 0. ★ Store-fault SOLVED → boot the full kernel DTB (obsoletes the overlays)  — DONE (runtime)
The u-boot loaded-DTB store-fault (see #1) is **fixed** by removing `usb start` from u-boot's
`preboot` env (VF2's xHCI is broken in u-boot 2025.01/2026.01; the handoff USB cleanup faults).
With that, mainline u-boot boots the **complete kernel DTB** — display, VPU (+512 MiB CMA), RTC,
audio, CAN, etc. all present natively → **the vf2-hdmi / vf2-peripherals overlays are obsolete.**
- **Proper fix:** bake `preboot` without `usb start` into u-boot's default env (bbappend /
  CONFIG_PREBOOT / boot script) so no manual `saveenv`. Then the boot flow is just
  `booti ${kernel_addr_r} ${ramdisk_addr_r}:${filesize} <full kernel dtb>` (no fdtcontroladdr,
  no fdt apply). Optionally investigate/fix the underlying VF2 xHCI bug so u-boot USB works.
- Items #1 and #4b below are superseded by this for the display/peripheral nodes; keep them as
  the historical record + the fallback overlay method.

## 1. HDMI / display device-tree nodes  — SUPERSEDED by #0 (overlay method kept as fallback)
- **Now:** `scripts/vf2-hdmi-overlay.dts` compiled to `.dtbo` and applied at boot with
  `fdt apply` onto U-Boot's `${fdtcontroladdr}` (works because that FDT carries
  `__symbols__`). Adds `dc8200`, `hdmi`, `dssctrl`, `hdmitx0-pixel-clock`,
  `display-subsystem`+`rgb-output`, `hdmi-0` pinmux, PMIC `ALDO5/ALDO3`.
- **Why it exists:** mainline u-boot 2026.01's control FDT is a minimal boot subset with
  no display nodes, and loading our full kernel DTB store-faults u-boot at handoff
  (PC 0x4022ca18). Our kernel DTB *does* have the nodes.
- **Proper fix (pick one, in order of preference):**
  1. **Fix the u-boot loaded-DTB store-fault** → then just `booti … ${fdt_addr_r}` with the
     full kernel DTB (which already has ALL nodes + /reserved-memory). Cleanest; removes the
     overlay entirely. **ROOT-CAUSED (2026-07-12):** recompiled u-boot for symbols;
     fault PC 0x4022ca18 = **`free()`** (return addr = **`xhci_cleanup`**). At kernel handoff
     `announce_and_cleanup()`→`usb_stop()`→`xhci_cleanup()`→`free()` store-faults because the
     malloc heap is corrupted on the loaded-DTB path. Adding `usb stop` before booti did NOT
     help — `usb stop` itself faults in `free()`, i.e. the heap is already poisoned *before*
     handoff (during the loaded-DTB tftp/fdt handling), not at the jump. The ${fdtcontroladdr}
     path never corrupts the heap, so it boots. This is a mainline u-boot 2026.01 jh7110 bug;
     fixing needs deeper u-boot malloc/LMB/FDT debugging (or the vendor u-boot, which the
     project rejected as a regression). **Deferred in favour of the overlay path (works).**
  2. **u-boot bbappend** adding a `jh7110-visionfive-2-*-u-boot.dtsi` (or SPL/patch) that
     merges the display nodes into u-boot's control FDT at build time → boot with
     `${fdtcontroladdr}`, no runtime `fdt apply`. Rebuild u-boot + reflash QSPI.
  3. **Ship the overlay as a build artifact** (compile `vf2-hdmi-overlay.dts` via a recipe,
     install the `.dtbo`, and have the boot script `fdt apply` it). Keeps the runtime
     mechanism but makes the artifact reproducible.
- Source of truth for the nodes: `scratch_dt/kernel-vf2.dts` (decompiled board DTB).

## 2. GPU (pvrsrvkm) autoload disabled  — DONE (obsolete: GPU works; see #3)
**Resolution (2026-07-16):** #3's RANDSTRUCT fix made the GPU safe to load, so
autoload is back ON in the demo image. What survives in recipes: rc.pvr ships
**start-only** init links (`visionfive2-pvr-graphics` bbappend) because the
DDK's shutdown rmmod panics in `pvr_exit`. Historical detail below.
- **Now:** `nogpu` initramfs = original rootfs with `etc/rc[2-5].d/S20rc.pvr` start links
  and `etc/modules-load.d/pvrsrvkm.conf` removed, repacked
  (`core-image-weston-visionfive2-nogpu.cpio.gz`). Plus `modprobe.blacklist=pvrsrvkm` on
  the kernel cmdline. Needed because pvrsrvkm soft-locks the kernel in
  `ccache_flush_range` at module init (see #4).
- **Proper fix:** a `core-image`/pvr **bbappend** that either (a) does not install the pvr
  sysv autostart + modules-load.d entry while the GPU is unfixed, or (b) is dropped once #4
  lands. Do NOT ship the hand-repacked cpio.

## 3. GPU (pvrsrvkm) ccache_flush_range soft-lock  — DONE (2026-07-14)
**Resolution:** root cause was `CONFIG_RANDSTRUCT_FULL` (silently enabled via
the defconfig's `COMPILE_TEST=y`) corrupting the out-of-tree DDK —
`randstruct.cfg` in the kernel bbappend disables it. PowerVR renderer
confirmed; GL-composited weston shipped in the demo image (needs
`WESTON_DISABLE_GBM_MODIFIERS`, see the weston-init bbappend). Original
hypothesis below, kept for the record.
- **Symptom:** `modprobe pvrsrvkm` spins forever in the SiFive L2 flush during
  `SysDevHost_Cache_Maintenance` → RCU stalls, one CPU pinned.
- **Root cause (hypothesis):** mainline treats the GPU as non-coherent and runs the slow
  CCACHE MMIO flush per line; StarFive's vendor kernel treats the GPU DMA as **cache
  coherent** so the maintenance is a no-op.
- **Proper fix:** configure the DDK/GPU as coherent — `dma-coherent` on the GPU DT node
  and/or the DDK build's cache-op backend, or the vendor CMO hooks. This unblocks GPU
  accel (and lets #2 be reverted). Deferred until other hardware is up.

## 4. WiFi / Bluetooth (ESWIN ECR6600U) firmware + userspace  — DONE for WiFi (recipe, 2026-07-16); BT out of scope
**Resolution:** `recipes-bsp/ecr6600u-firmware` packages the version-matched
blob + cfg into /lib/firmware; `iw`/`wpa-supplicant` are in the demo image.
BT remains out of scope (vendor BLE only, no HCI). Details below.
- **Done at runtime:** added the **version-matched** firmware to the initramfs
  (`ECR6600U_transport.bin` V1.1.0B04P05T01 == driver V1.1.0B04P05) + `wifi_ecr6600u.cfg`
  → firmware downloads 100%, `wlan0` created with real MAC, `ip link set wlan0 up` works.
  Image built as `…-nogpu-wifi.cpio.gz`.
  - Firmware source (authoritative, matches our starfive-tech kernel):
    `starfive-tech/buildroot` @ `JH7110_VisionFive2_devel`
    `package/starfive/starfive-firmware/ECR6600U-usb-wifi/ECR6600U_transport.bin`.
    NOTE: the eswincomputing/eswin_6600u repo firmware is reported NOT to work — use the
    buildroot/official-image blob. cfg comes from the kernel repo
    `drivers/net/wireless/eswin/wifi_ecr6600u.cfg`.
- **Userspace: DONE in image** — `CORE_IMAGE_EXTRA_INSTALL += "iw wpa-supplicant"` in
  `build/conf/local.conf` (rebuilt). Verified: scan → WPA2 associate → DHCP → internet
  (`ping 8.8.8.8` over wlan0, eth1 down, 0% loss). Creds live in git-ignored `wifi.yaml`,
  configured at runtime (never baked in).
- **Still TODO:**
  - **Firmware recipe:** package `ECR6600U_transport.bin` + `wifi_ecr6600u.cfg` into
    `/lib/firmware` via a proper recipe (currently hand-injected into the cpio).
  - Optional: a `wpa_supplicant@wlan0` service + `wpa_supplicant.conf` (or connman) for
    auto-connect at boot; busybox `udhcpc` already handles DHCP on wlan0.
  - **Bluetooth:** ECR6600U BT needs its fw + `btattach`/init + `bluez` if in scope.
  - MAC: driver first reports placeholder `00:11:22:33:44:5f` then a real MAC
    `2c:05:47:a1:20:2d` — confirm MAC provisioning (EEPROM/cfg) for production.

## 4b. Extra peripheral DT nodes (RTC done; VPU/audio/CAN pending)  — RUNTIME → TODO
- **Now:** `scripts/vf2-peripherals-overlay.dts` (applied alongside the HDMI overlay via
  netboot `--overlay a,b`). Contains **RTC** (`rtc@17040000` → `/dev/rtc0`, works).
- **Missing from u-boot's control FDT (20 /soc nodes; providers aoncrg/syscrg/pwrc/sys-syscon
  all present):** display (done), rtc (done), and still-TODO: `vpu_dec/vpu_enc/jpu` (+mailbox),
  `spdif/pdm/i2srx` audio, `can`×2, `mipi`/`mipi-dphy` (DSI), `vin_sysctl` (camera), `gpu`,
  `timer`, `xrp`/`e24` (DSP).
- **VPU (wave5 vdec):** clocks/resets/`&pwrc` resolve, but needs a **`/reserved-memory`
  `linux,cma` pool** (u-boot FDT has none) or `cma=<size>` bootarg — else DMA alloc oopses at
  probe. Fold into the eventual proper DT.
- **Audio spdif/pdm/i2srx:** `status="disabled"` upstream + need sound-card/codec/DMA — real
  board audio work, not a transplant. PWMDAC already provides audio out.
- **Proper fix (all):** same as #1 — either fix the u-boot loaded-DTB store-fault (use the full
  kernel DTB, which has all of these), or bake the nodes into u-boot's control FDT via bbappend.

## 5. U-Boot env: QSPI boot + halt-at-prompt  — PARTLY DONE (bootdelay=2 saved 2026-07-16)
**Update:** `bootdelay=2` is `saveenv`ed, so the QSPI U-Boot now distro-boots
the SD's GRUB unattended (the shipped first-boot path) while the bench netboot
scripts still catch the countdown. Still TODO: bake the env (incl. the
no-`usb start` preboot) into the U-Boot build itself.
- **Now:** `bootdelay=-1` set via `saveenv` by hand (fixes the prior bad-CRC default env);
  boot is driven by host scripts over serial.
- **Proper fix:** a sane default boot environment / boot script (distro-boot / extlinux /
  a `boot.scr`) so the board boots the intended target (netboot, or SD/eMMC) unattended,
  with a normal short bootdelay for production.

## 6. Kernel: enable CONFIG_MAGIC_SYSRQ  — TODO
- **Why:** a hung kernel with no shell currently needs the physical RST button; magic-sysrq
  is OFF. Enable it (defconfig fragment / kernel bbappend) so `SysRq-B` over serial reboots
  even a wedged kernel — fully remote bring-up.

## 7. eth0 (EQOS 16030000) failure  — TODO
- U-Boot: `EQOS_DMA_MODE_SWR stuck / FAILED -110`. eth1 (16040000) works fine. Investigate
  DT/PHY/driver for eth0; fix or document as unused.

## 8. Already captured elsewhere (keep, don't regress)
- DDK fetch `PREMIRRORS` redirect to canonical github + host `git-lfs` prereq
  (see `docs/DEV_SETUP.md`). Ensure these stay in layer config /
  documented host setup.

---

## Dev tooling (stays in `scripts/`, not shipped to target)
- `vf2-uart-boot.py` — XMODEM/YMODEM UART recovery + `--flash-qspi`.
- `vf2-flash-qspi.py` — standalone QSPI flasher (superseded by `--flash-qspi`).
- `vf2-netboot.py` — drive tftpboot/booti from a live U-Boot (`--dtb`, `--blacklist`,
  `--initramfs`, `fdt apply` for the overlay).
- `vf2-shell.py` — auto-login serial console command runner.
- `scratch_dt/` — DT comparison artifacts (u-boot vs kernel), overlay build.
