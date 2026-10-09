FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# See files/randstruct.cfg & docs/GPU_VERIFY.md.
SRC_URI:append:visionfive2 = " file://randstruct.cfg"

# 10.1-DSI-TOUCH-A panel & GT9271 touch; each patch's header gives its reason.
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

KERNEL_DEVICETREE:append:visionfive2 = " starfive/jh7110-starfive-visionfive-2-v1.3b-dsi.dtb"

# The .dts #includes the in-tree base .dts, so it must be copied into the tree.
do_configure:prepend:visionfive2() {
    cp -f ${UNPACKDIR}/jh7110-starfive-visionfive-2-v1.3b-dsi.dts \
        ${S}/arch/riscv/boot/dts/starfive/
}
