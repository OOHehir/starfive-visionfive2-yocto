FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# The stock script exits if /dev/fb0 is missing, which on DSI appears ~18 s into
# boot. Opening fb0 also completes the 0006 VSG recovery, so psplash is load-bearing.
SRC_URI:append:visionfive2 = " file://psplash-init-waitfb"

do_install:append:visionfive2() {
    install -m 0755 ${UNPACKDIR}/psplash-init-waitfb ${D}${sysconfdir}/init.d/psplash.sh
    echo 270 > ${D}${sysconfdir}/rotation
}

FILES:${PN}:append:visionfive2 = " ${sysconfdir}/rotation"
