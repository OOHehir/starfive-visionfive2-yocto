SUMMARY = "Doom (doomgeneric) — direct-framebuffer port for the 10.1-DSI-TOUCH-A"
DESCRIPTION = "doomgeneric built against its Linux VT/framebuffer backend, \
patched to rotate 90 CCW and 2x-scale the 640x400 Doom frame so it fills the \
portrait 800x1280 DSI panel as a 1280x800 landscape image. Software-rendered to \
/dev/fb0 (no GPU/SDL/X needed). Run with the bundled `doom` launcher (pulls in \
the freedoom IWAD). Autostarts via sysvinit (VF2 image is sysvinit, not systemd)."
HOMEPAGE = "https://github.com/ozkl/doomgeneric"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=b234ee4d69f5fce4486a80fdaf4a4263"

SRC_URI = "git://github.com/ozkl/doomgeneric.git;protocol=https;branch=master \
           file://0001-fbdev-rotate-scale-guard-input.patch \
           file://doom \
           file://doom.init"
SRCREV = "dcb7a8dbc7a16ce3dda29382ac9aae9d77d21284"

# freedoom supplies the IWAD the launcher points at.
RDEPENDS:${PN} = "freedoom"

# No autostart: the demo image boots into the status-page kiosk instead.
# /etc/init.d/doom is still installed for manual runs (`/etc/init.d/doom
# start` hands the panel from Weston to the game; `stop` gives it back).

# Makefile.linuxvt hardcodes CC=clang and appends its own -DNORMALUNIX/-DLINUX
# via CFLAGS+=, so override only CC (leaving CFLAGS to the env + the Makefile).
do_compile() {
    oe_runmake -C ${S}/doomgeneric -f Makefile.linuxvt CC="${CC}"
}

do_install() {
    install -d ${D}${bindir}
    install -m0755 ${S}/doomgeneric/doomgeneric ${D}${bindir}/doomgeneric
    install -m0755 ${UNPACKDIR}/doom ${D}${bindir}/doom

    install -d ${D}${sysconfdir}/init.d
    install -m0755 ${UNPACKDIR}/doom.init ${D}${sysconfdir}/init.d/doom
}

# Doom is for /dev/fb0; no GL/X deps.
INSANE_SKIP:${PN} += "already-stripped"
