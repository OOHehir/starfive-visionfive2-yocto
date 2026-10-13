meta-visionfive2-demo
=====================

Demo layer for the StarFive VisionFive 2 v1.3B (JH7110): a 10.1in MIPI-DSI touch
panel, a GPU-composited Weston touch dashboard & Doom on demand. Build
instructions & the hardware list are in the [top-level README](../README.md).

Dependencies
------------

- openembedded-core (`core`), branch master
- meta-riscv (`riscv-layer`), branch master

Every change is gated on `MACHINE = "visionfive2"`, so adding the layer changes
no other machine's recipes.

Contents
--------

- `visionfive2-demo-image`: core-image-weston plus the demo stack.
- `linux-starfive-dev` bbappend: DSI panel, DPHY & touch patches & config
  fragments.
- `vf2-status`, `vf2-kiosk`: the dashboard & its WebKit kiosk client.
- `doomgeneric`, `freedoom`: Doom on the framebuffer.
- `ecr6600u-firmware`: firmware for the ECR6600U USB WiFi module.

Maintainer
----------

OOHehir (https://github.com/OOHehir)

Send patches & issues to https://github.com/OOHehir/starfive-visionfive2-yocto.
