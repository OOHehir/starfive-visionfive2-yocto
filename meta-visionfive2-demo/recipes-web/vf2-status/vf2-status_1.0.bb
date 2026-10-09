SUMMARY = "VisionFive 2 demo status webserver"
DESCRIPTION = "Lightweight system status page served via lighttpd CGI on \
port 80. Shows uptime, memory, network (eth0/eth1/WiFi), storage, thermal, \
display state and a Doom start/stop control. Ported from the sibling \
luckfox-lyra-ultra-yocto status webserver; shown fullscreen on the DSI panel \
by vf2-kiosk and reachable over the LAN."
HOMEPAGE = "https://github.com/OOHehir/starfive-visionfive2-yocto"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "\
    file://status.cgi \
    file://lighttpd-status.conf \
"

RDEPENDS:${PN} = "lighttpd lighttpd-module-cgi"

S = "${UNPACKDIR}"

do_install() {
    install -d ${D}/www/pages
    install -m 0755 ${UNPACKDIR}/status.cgi ${D}/www/pages/status.cgi

    install -d ${D}${sysconfdir}/lighttpd.d
    install -m 0644 ${UNPACKDIR}/lighttpd-status.conf ${D}${sysconfdir}/lighttpd.d/status.conf
}

pkg_postinst:${PN}() {
    echo '<html><head><meta http-equiv="refresh" content="0;url=/status.cgi"></head></html>' \
        > $D/www/pages/index.html
}

FILES:${PN} = "/www/pages/status.cgi ${sysconfdir}/lighttpd.d"
