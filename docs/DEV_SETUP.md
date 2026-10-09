# DEV_SETUP — build host & bench

Working notes for reproducing the VisionFive 2 demo build. Expanded as
the project matures.

## Host prerequisites

Standard Yocto host packages (see the Yocto Project quick-start), plus:

- **git-lfs** — REQUIRED. The closed StarFive GPU/VPU userspace
  (`soft_3rdpart`) is served from GitHub via Git LFS. Without it the
  `visionfive2-pvr-graphics` fetch fails with *"has LFS content, install
  git-lfs"*.
  ```bash
  sudo apt install git-lfs && git lfs install
  ```
  (If you can't use sudo: drop the `git-lfs` binary in `~/.local/bin`, run
  `git lfs install`, and ensure it's on PATH before `bitbake` starts — OE
  links it in via `HOSTTOOLS_NONFATAL`.)

Build host used for bring-up: Intel Xeon E5-1680 v3 (8c/16t), 125 GB RAM,
~1.2 TB free. `BB_NUMBER_THREADS=16`, `PARALLEL_MAKE=-j16`.

## Layers

Yocto master (blacksail dev series), pinned in `setup-layers.json`. The last
known-good wrynose (April 2026 LTS) setup is on the `wrynose` branch. Reproduce with:
```bash
./setup-layers --destdir sources     # clones sources/ at the pinned SHAs
source sources/oe-core/oe-init-build-env build
bitbake visionfive2-demo-image       # the demo image (core-image-weston also works)
```
`build/conf/{local.conf,bblayers.conf}` are provided as `*.sample` at the repo
root — copy them into `build/conf/` (oe-init seeds a build dir; overwrite with
the samples).

## Shared caches

`DL_DIR` and `SSTATE_DIR` can point at a host-wide shared cache (reused with the
other boards on this host). Hash equivalence is on, with the DB at
`${SSTATE_DIR}/hashserv` so sstate is reused across builds.

## Bench (discovered 2026-07-11 — TO-VERIFY marked)

| item | value |
|---|---|
| Board debug UART | `/dev/ttyUSB0` @ 115200 (`/dev/ttyACM0` = PPK2) |
| LAN | host `eno1` 192.168.178.113/24 (Fritz!Box; board via DHCP) |
| TFTP root (CIFS mount) | `/media/dsCIFS/public/tftp` |
| NAS LAN IP | **TO-VERIFY** |
| NFS export path | **TO-VERIFY** |
| Automatable reset | PPK2 source-mode DUT power (5 V GPIO feed), via `ppk2` MCP tools |

## Flash (release path)

VF2 has a microSD slot. `bmaptool copy <img>.wic.gz /dev/sdX` (or
`gunzip | dd`), set boot-mode DIP switches to **SDIO**, insert, power via USB-C.
Boot-mode DIP table (QSPI NOR / SDIO / eMMC / UART) and debug-UART pinout:
**per the product brief.**

## Bench gotchas (learned the hard way)

- **Sandbox strips write privileges.** In the sandboxed build shell all `//ds.local/*`
  CIFS shares mount read-only, NAS SSH is refused, and the user is not in the
  `disk` group (sudo is `nosuid`-blocked). To flash a device or stage to the NAS
  TFTP dir, run outside the sandbox or grant: `usermod -aG disk owen` (device
  flash) and/or a read-write TFTP mount.
- **The "Super Top" USB card reader (`14cd:1212`, SY-T18) is flaky.** Known
  Linux kernel bug: on xHCI (USB 3.0) it resets, reports **0-byte capacity**,
  and **corrupts writes**. Use a USB 2.0 (EHCI) port, and always read-back-verify
  after flashing (`scripts/flash-sd.sh` does this).
- **Prefer in-place eMMC flash over the USB-eMMC adapter.** On the VF2 the
  on-board eMMC is `/dev/mmcblk0` (SD slot = `/dev/mmcblk1`). The reliable way to
  image the eMMC is to boot the board (SD or UART recovery) and write to
  `/dev/mmcblk0` in-place — avoids fragile eMMC→microSD adapter chains.

## Flashing an SD/eMMC (dev)

`scripts/flash-sd.sh /dev/sdX` — bmaptool-writes the wic with guard rails
(refuses anything not removable+USB+≤64 GB, never `sda`) and a read-back verify.

## Autonomous dev loop (netboot)

See `scripts/netboot.sh` + `scripts/netboot.env`.
NB: netboot presumes U-Boot/SPL is already resident (SPI-NOR or a boot SD) —
flash the boot chain once.
