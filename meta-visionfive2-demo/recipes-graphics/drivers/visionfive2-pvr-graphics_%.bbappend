# No stop links: rc.pvr's `rmmod pvrsrvkm` panics in pvr_exit on every reboot,
# & the GPU needs no teardown.
INITSCRIPT_PARAMS = "start 20 2 3 4 5 ."
