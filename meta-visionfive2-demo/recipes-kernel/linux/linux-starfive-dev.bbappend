FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# Disable RANDSTRUCT so the closed PowerVR DDK (pvrsrvkm) doesn't soft-lock at
# GPU bring-up. See files/randstruct.cfg for the full rationale.
SRC_URI:append:visionfive2 = " file://randstruct.cfg"

# --- M2: 10.1-DSI-TOUCH-A (ILI9881C 800x1280, 2-lane) on the DSI port ---
# .cfg enables the mainline ILI9881C panel driver + waveshare backlight;
# 0001 lets the DT set the DSI lane count + HS rate (this panel is 2-lane, the
# driver hardcodes 4); 0002 adds the I2C backlight-MCU driver (@0x45); 0003
# bounds the M31 DPHY PLL-lock spin; 0004 adds the Luckfox "10inch1" ILI9881C
# descriptor (register-0xE0 bank init, verbatim from the vendor SDK); 0005 gives
# the cdns-dsi host a .pre_enable so the link/PHY are up before the panel's init
# DCS (the panel sets prepare_prev_first) — without it the glass stays black; the .dts is
# a board DTB that wires the panel + GT9271 touch (@0x5d) + backlight and is
# selected at netboot/flash time (KERNEL_DEVICETREE below). See docs/DSI_TOUCH.md.
SRC_URI:append:visionfive2 = " \
    file://dsi-panel.cfg \
    file://0001-ili9881c-dsi-lanes-from-dt.patch \
    file://0002-waveshare-backlight.patch \
    file://0003-m31-dphy-bound-pll-lock.patch \
    file://0004-ili9881c-add-luckfox-10inch1-panel.patch \
    file://0005-cdns-dsi-pre-enable-ordering.patch \
    file://0006-cdns-dsi-vsg-selfheal.patch \
    file://0007-goodix-touch-poll-mode.patch \
    file://jh7110-starfive-visionfive-2-v1.3b-dsi.dts \
"

# Build + deploy the DSI DTB alongside the stock HDMI-only one.
KERNEL_DEVICETREE:append:visionfive2 = " starfive/jh7110-starfive-visionfive-2-v1.3b-dsi.dtb"

# The out-of-tree .dts #includes the in-tree base .dts, so stage it into the
# kernel dts dir before the DTBs are built. (do_patch has already applied the
# driver patches to the fetched source by this point.)
# Modern Yocto unpacks file:// sources into ${UNPACKDIR} (= ${WORKDIR}/sources),
# not ${WORKDIR} directly.
do_configure:prepend:visionfive2() {
    cp -f ${UNPACKDIR}/jh7110-starfive-visionfive-2-v1.3b-dsi.dts \
        ${S}/arch/riscv/boot/dts/starfive/
}
