SUMMARY = "ESWIN ECR6600U USB WiFi firmware for the VisionFive 2"
DESCRIPTION = "Version-matched firmware for the ecrnx driver in the StarFive \
6.12 vendor kernel (fw V1.1.0B04P05T01 == driver V1.1.0B04P05). Blob taken \
from starfive-tech/buildroot @ JH7110_VisionFive2_devel \
(package/starfive/starfive-firmware/ECR6600U-usb-wifi); the \
eswincomputing/eswin_6600u repo firmware is known NOT to work with this \
driver. cfg from the kernel tree (drivers/net/wireless/eswin)."
# No published licence, & oe-core no longer accepts bare "CLOSED": the LicenseRef
# points at a provenance notice instead.
LICENSE = "LicenseRef-ecr6600u-firmware-CLOSED"
NO_GENERIC_LICENSE[ecr6600u-firmware-CLOSED] = "LICENSE.ecr6600u"
LIC_FILES_CHKSUM = "file://LICENSE.ecr6600u;md5=e1d96006ada7ff87964a6958d4698f56"

SRC_URI = "\
    file://ECR6600U_transport.bin \
    file://wifi_ecr6600u.cfg \
    file://LICENSE.ecr6600u \
"

S = "${UNPACKDIR}"

inherit allarch

do_install() {
    install -d ${D}${nonarch_base_libdir}/firmware
    install -m 0644 ${UNPACKDIR}/ECR6600U_transport.bin ${D}${nonarch_base_libdir}/firmware/
    install -m 0644 ${UNPACKDIR}/wifi_ecr6600u.cfg ${D}${nonarch_base_libdir}/firmware/
}

FILES:${PN} = "${nonarch_base_libdir}/firmware"
