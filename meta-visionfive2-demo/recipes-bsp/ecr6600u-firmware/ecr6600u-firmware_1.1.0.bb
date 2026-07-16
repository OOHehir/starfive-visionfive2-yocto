SUMMARY = "ESWIN ECR6600U USB WiFi firmware for the VisionFive 2"
DESCRIPTION = "Version-matched firmware for the ecrnx driver in the StarFive \
6.12 vendor kernel (fw V1.1.0B04P05T01 == driver V1.1.0B04P05). Blob taken \
from starfive-tech/buildroot @ JH7110_VisionFive2_devel \
(package/starfive/starfive-firmware/ECR6600U-usb-wifi); the \
eswincomputing/eswin_6600u repo firmware is known NOT to work with this \
driver. cfg from the kernel tree (drivers/net/wireless/eswin)."
LICENSE = "CLOSED"

SRC_URI = "\
    file://ECR6600U_transport.bin \
    file://wifi_ecr6600u.cfg \
"

S = "${UNPACKDIR}"

inherit allarch

do_install() {
    install -d ${D}${nonarch_base_libdir}/firmware
    install -m 0644 ${UNPACKDIR}/ECR6600U_transport.bin ${D}${nonarch_base_libdir}/firmware/
    install -m 0644 ${UNPACKDIR}/wifi_ecr6600u.cfg ${D}${nonarch_base_libdir}/firmware/
}

FILES:${PN} = "${nonarch_base_libdir}/firmware"
