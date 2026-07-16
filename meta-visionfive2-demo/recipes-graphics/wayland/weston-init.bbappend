FILESEXTRAPATHS:prepend := "${THISDIR}/weston-init:"

# Rotate the portrait-mounted 800x1280 DSI panel to landscape so the desktop /
# kiosk match the Doom + psplash orientation. Weston also transforms touch
# input with the output, so GT9271 coordinates stay correct.
# idle-time=0: never DPMS-blank — this is a kiosk (observed: display STOPs at
# the 300 s default idle timeout).
do_install:append:visionfive2() {
    sed -i -e "/^\[core\]/a idle-time=0" ${D}${sysconfdir}/xdg/weston/weston.ini
    cat >> ${D}${sysconfdir}/xdg/weston/weston.ini <<WESTONEOF

[output]
name=DSI-1
transform=rotate-270
WESTONEOF
    # dc8200 KMS advertises GBM modifiers the display can't scan out from the
    # PVR GPU (panel shows a column of dots); force linear buffers.
    # weston-start sources /etc/default/weston.
    cat >> ${D}${sysconfdir}/default/weston <<WESTONEOF

# dc8200 can't scan out PVR modifier/tiled buffers -> force linear (see
# meta-visionfive2-demo weston-init.bbappend).
export WESTON_DISABLE_GBM_MODIFIERS=true
WESTONEOF
}
