# The bench unit's eth0 PHY never links (docs/PRODUCTIONIZE.md #7), so also bring
# up eth1. Harmless elsewhere: udhcpc backgrounds when it gets no lease.
do_install:append:visionfive2() {
    sed -i 's/^auto eth0$/auto eth0 eth1/' ${D}${sysconfdir}/network/interfaces
}
