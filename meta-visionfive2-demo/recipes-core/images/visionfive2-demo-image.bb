SUMMARY = "VisionFive 2 demo image — DSI touch dashboard, Doom on demand"
DESCRIPTION = "core-image-weston plus the demo stack: 10.1in DSI panel with \
GT9271 touch (kernel patches in the linux-starfive-dev bbappend), \
GPU-composited weston (PowerVR), psplash boot splash, the vf2-status \
webserver shown fullscreen by the vf2-kiosk WebKit client, and doomgeneric \
launchable from the status page by touch. Boots from a clean SD flash with \
zero manual steps."

require recipes-graphics/images/core-image-weston.bb

# The demo boots the DSI board DTB (panel + touch + backlight nodes); the
# wks bakes it into the GRUB config on the /boot partition.
WKS_FILE = "visionfive2-demo.wks"

IMAGE_INSTALL += " \
    vf2-status \
    vf2-kiosk \
    doomgeneric \
    psplash \
    ecr6600u-firmware \
    iw \
    wpa-supplicant \
    alsa-utils \
    i2c-tools \
    evtest \
    libinput \
"
