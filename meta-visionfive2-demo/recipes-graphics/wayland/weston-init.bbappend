FILESEXTRAPATHS:prepend := "${THISDIR}/weston-init:"

# Landscape to match Doom & psplash; Weston rotates touch input with the output.
# idle-time=0: a kiosk must not blank (the display stops at the 300 s default).
do_install:append:visionfive2() {
    sed -i -e "/^\[core\]/a idle-time=0" ${D}${sysconfdir}/xdg/weston/weston.ini
    cat >> ${D}${sysconfdir}/xdg/weston/weston.ini <<WESTONEOF

[output]
name=DSI-1
transform=rotate-270
WESTONEOF
    # dc8200 cannot scan out the PVR GPU's tiled buffers (a column of dots).
    cat >> ${D}${sysconfdir}/default/weston <<WESTONEOF

# dc8200 cannot scan out PVR tiled buffers; see weston-init.bbappend.
export WESTON_DISABLE_GBM_MODIFIERS=true
WESTONEOF
}
