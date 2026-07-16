FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# Replace the stock init script: it hard-exits when /dev/fb0 is missing, and
# on this board the DSI framebuffer only appears ~18 s into boot (DRM probe +
# VSG self-heal). The variant waits for fb0 in the background (rcS stays
# non-blocking); the psplash fb open also completes the cdns-dsi 0006 VSG
# recovery. /etc/rotation = 270 -> landscape, matching weston + Doom.
SRC_URI:append:visionfive2 = " file://psplash-init-waitfb"

do_install:append:visionfive2() {
    install -m 0755 ${UNPACKDIR}/psplash-init-waitfb ${D}${sysconfdir}/init.d/psplash.sh
    echo 270 > ${D}${sysconfdir}/rotation
}

FILES:${PN}:append:visionfive2 = " ${sysconfdir}/rotation"
