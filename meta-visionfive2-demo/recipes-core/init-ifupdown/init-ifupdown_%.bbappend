# Bring up BOTH GMAC ports at boot. The stock interfaces file only autos
# eth0 — on this bench eth0's PHY never links (PRODUCTIONIZE.md #7) and the
# usable port is eth1, so the status webserver was unreachable on first
# boot. eth0's udhcpc backgrounds on no-lease, so autoing both is harmless.
do_install:append:visionfive2() {
    sed -i 's/^auto eth0$/auto eth0 eth1/' ${D}${sysconfdir}/network/interfaces
}
