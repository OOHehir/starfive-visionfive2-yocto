SUMMARY = "Fullscreen status-page kiosk for the DSI panel"
DESCRIPTION = "Tiny GTK4 + WebKitGTK (6.0 API) fullscreen web view that shows \
the vf2-status page on the panel at boot. No browser chrome; the page \
self-refreshes and carries the touch controls (e.g. Doom start/stop). \
Launched via sysvinit after weston; runs as the weston user on its \
wayland socket."
HOMEPAGE = "https://github.com/OOHehir/starfive-visionfive2-yocto"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "\
    file://vf2-kiosk.c \
    file://vf2-kiosk.init \
"

S = "${UNPACKDIR}"

DEPENDS = "gtk4 webkitgtk"
RDEPENDS:${PN} = "vf2-status"

inherit pkgconfig update-rc.d

INITSCRIPT_NAME = "vf2-kiosk"
# Start right after weston (S09 in rc5); the init script waits for the socket.
INITSCRIPT_PARAMS = "start 10 5 . stop 20 0 1 6 ."

do_compile() {
    ${CC} ${CFLAGS} ${LDFLAGS} -o vf2-kiosk ${UNPACKDIR}/vf2-kiosk.c \
        $(pkg-config --cflags --libs gtk4 webkitgtk-6.0)
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/vf2-kiosk ${D}${bindir}/vf2-kiosk
    install -d ${D}${sysconfdir}/init.d
    install -m 0755 ${UNPACKDIR}/vf2-kiosk.init ${D}${sysconfdir}/init.d/vf2-kiosk
}
