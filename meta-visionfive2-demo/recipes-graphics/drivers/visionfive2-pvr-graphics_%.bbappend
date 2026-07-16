# Start-only init links: rc.pvr's shutdown `rmmod pvrsrvkm` panics in
# pvr_exit (broken DDK module — "Fatal exception in interrupt" on every
# clean reboot, JOURNAL 2026-07-16). The GPU needs no teardown at
# shutdown/reboot; do not create K links.
INITSCRIPT_PARAMS = "start 20 2 3 4 5 ."
