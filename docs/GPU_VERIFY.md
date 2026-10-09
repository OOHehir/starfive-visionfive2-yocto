# GPU verification — PowerVR acceleration on the VisionFive 2

**Pass criterion:** `pvrsrvkm` loads, `rgx.fw` loads with **no
firmware-load failure** and **no `ccache_flush_range` soft-lock** in `dmesg`,
and a GLES2 renderer reports the **PowerVR / IMG BXE-4-32** renderer — **not**
`softpipe`/`llvmpipe`.

The JH7110 GPU is an **Imagination PowerVR B-Series BXE-4-32** (`GC7000`-class).

---

## The root cause this project hit: RANDSTRUCT

The board **soft-locked at GPU bring-up** (kernel spinning in
`ccache_flush_range`) whenever `pvrsrvkm` was loaded.

Cause: the yocto security kernel feature plus the vendor defconfig's
`CONFIG_COMPILE_TEST=y` silently turn on **`CONFIG_RANDSTRUCT_FULL`** (the
Kconfig.hardening choice defaults to FULL when `COMPILE_TEST && GCC_PLUGINS`).
RANDSTRUCT randomizes kernel struct layouts at compile time; the closed,
out-of-tree PowerVR DDK (`pvrsrvkm`) is compiled against a fixed layout, reads a
bogus range on init, and `ccache_flush_range()` spins forever. StarFive's own
image ships the vendor defconfig **without** the yocto security fragment, which
is why it never hangs.

**Fix:** `meta-visionfive2-demo/recipes-kernel/linux/files/randstruct.cfg`
pins `CONFIG_RANDSTRUCT_NONE=y` (same as sibling board
`linux-milkv-megrez-dev`). Verify after a kernel build:

```
CFG=build/tmp/work/visionfive2-poky-linux/linux-starfive-dev/6.12.5+git/linux-visionfive2-standard-build/.config
grep -i RANDSTRUCT $CFG
#   CONFIG_RANDSTRUCT_NONE=y          <- want this
#   # CONFIG_RANDSTRUCT_FULL is not set
# and CONFIG_GCC_PLUGIN_RANDSTRUCT must be ABSENT
```

Any kernel rebuild that reintroduces `RANDSTRUCT_FULL` reopens the soft-lock.

---

## On-target verification

Boot the RANDSTRUCT-off `Image` + full kernel DTB + a rootfs carrying the
matching `pvrsrvkm.ko` (built from the *same* kernel — a mismatched module is
itself a hang risk). Boot with `pvrsrvkm` **not** autoloaded (safe boot), then
load it by hand so any regression is isolated to one command, not the boot:

```sh
dmesg -c >/dev/null                      # clear the ring buffer
/etc/init.d/rc.pvr start                 # modprobe pvrsrvkm + drm_starfive + fw
dmesg | grep -iE 'pvr|rgx|powervr|ccache|firmware'
```

Want to see (and NOT a hang):

```
PVR_K: ... RGX Firmware image 'rgx.fw' loaded
[drm] Initialized pvr ...
```

Failure signature (the soft-lock): the `rc.pvr start` command **never returns**,
`dmesg` stops, console dead — RANDSTRUCT is back on (or the module doesn't match
the kernel). Power-cycle and re-check the `.config`.

Then the renderer string. **The monitor-free check is `eglinfo`** — it queries
the DDK's EGL/GLES over a surfaceless context and needs no display connector:

```sh
eglinfo 2>&1 | grep -iE 'renderer|vendor|OpenGL ES profile version'
```

**PASS** (confirmed on hardware 2026-07-14):

```
EGL vendor string:          Mesa Project
OpenGL ES profile vendor:   Imagination Technologies
OpenGL ES profile renderer: PowerVR B-Series BXE-4-32
OpenGL ES profile version:  OpenGL ES 3.2 build 1.19@6345021
```

A GLES-3.2-on-BXE-4-32 context is impossible without `rgx.fw` loaded, so a correct
renderer string *is* proof the firmware is live even when the `PVR_K … rgx.fw
loaded` dmesg line is suppressed by the console loglevel.

**FAIL (softpipe fallback):** `renderer: softpipe` / `llvmpipe` — the DDK
userspace (mesa-pvr / visionfive2-pvr-graphics) isn't being used; the demo would
"run" at single-digit FPS. Treat as a build-breaking regression (PLAN R1).

For a numeric **throughput score**, `glmark2-es2-drm` renders straight on KMS/GBM
(no compositor needed) — but it **requires a connected DRM connector**:

```sh
/etc/init.d/weston stop                  # free card0 from the compositor first
glmark2-es2-drm 2>&1 | grep -iE 'GL_RENDERER|glmark2 Score'
```

⚠️ With **no HDMI monitor plugged in** this fails `Error: Failed to find a
suitable connector` (even with `--off-screen` — the drm canvas still needs a
connector), and the weston **headless** backend is not in the image, so there is
no display-free score path. Plug a monitor in to capture the FPS number; the
`eglinfo` renderer string above is the acceleration proof regardless.

Cross-check the DRM binding (also monitor-free):

```sh
cat /sys/kernel/debug/dri/*/name    # want: pvr dev=18000000.gpu
```

For the Wayland path (Weston on GL, not Pixman): once `pvrsrvkm` is up, restart
Weston without `--renderer=pixman` and run `glmark2-es2-wayland`.
