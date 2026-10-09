SUMMARY = "Freedoom — free (BSD) Doom-compatible game data (IWAD)"
DESCRIPTION = "Freedoom provides freely-licensed IWAD files (freedoom1.wad / \
freedoom2.wad) usable by any Doom engine. Installed under ${datadir}/games/doom \
for the doomgeneric launcher."
HOMEPAGE = "https://freedoom.github.io/"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://COPYING.txt;md5=038918b78710d44563f923bd8119f814"

SRC_URI = "https://github.com/freedoom/freedoom/releases/download/v${PV}/freedoom-${PV}.zip"
SRC_URI[sha256sum] = "f42c6810fc89b0282de1466c2c9c7c9818031a8d556256a6db1b69f6a77b5806"

S = "${UNPACKDIR}/freedoom-${PV}"

# Game data only — architecture-independent.
inherit allarch

do_install() {
    install -d ${D}${datadir}/games/doom
    install -m0644 ${S}/freedoom1.wad ${D}${datadir}/games/doom/freedoom1.wad
    install -m0644 ${S}/freedoom2.wad ${D}${datadir}/games/doom/freedoom2.wad
}

FILES:${PN} = "${datadir}/games/doom"
