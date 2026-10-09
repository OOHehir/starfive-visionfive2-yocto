#!/usr/bin/env python3
"""Netboot the VF2 over TFTP from its QSPI U-Boot prompt, then stream the boot log.

Assumes MSEL=QSPI & bootdelay=-1, so a reset lands at the prompt. A booted Linux
on the console is rebooted back to U-Boot first. bootm_size=0x30000000 keeps the
133 MB initrd in low RAM; without it U-Boot faults.

Usage: vf2-netboot.py [--reset] [--dtb F | --overlay F,...] [--blacklist MOD]
                      [--extra-args "..."] [--log F]
"""
import argparse
import sys
import threading
import time

import serial

PROMPT = b"StarFive #"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="/dev/ttyUSB2")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--serverip", default="192.168.178.100")
    ap.add_argument("--reset", action="store_true",
                    help="issue `reset` first (board must already be at a prompt)")
    ap.add_argument("--blacklist", default="",
                    help="comma-list of modules -> modprobe.blacklist=...")
    ap.add_argument("--extra-args", default="")
    ap.add_argument("--root", default="/dev/ram0",
                    help="root= value; default initramfs ram0")
    ap.add_argument("--initramfs", default="visionfive2/core-image-weston-visionfive2.rootfs.cpio.gz",
                    help="TFTP path of the initramfs to boot")
    ap.add_argument("--dtb", default="",
                    help="TFTP path of a real kernel DTB to load+pass (with fdt resize) "
                         "instead of U-Boot's ${fdtcontroladdr}. Needed for HDMI/display nodes.")
    ap.add_argument("--overlay", default="",
                    help="Comma-separated TFTP paths of .dtbo files to fdt-apply (in order) "
                         "onto a COPY of ${fdtcontroladdr} (needs __symbols__). Preferred path.")
    ap.add_argument("--log", default="scripts/vf2-netboot.log")
    args = ap.parse_args()

    ser = serial.Serial(args.port, args.baud, timeout=0.3)
    logf = open(args.log, "wb", buffering=0)

    def emit(b):
        sys.stdout.buffer.write(b); sys.stdout.buffer.flush(); logf.write(b)

    def cmd(c, tmo=90):
        ser.write(c.encode() + b"\r"); ser.flush()
        out = bytearray(); t = time.time()
        while time.time() - t < tmo:
            b = ser.read(256)
            if b:
                out += b; emit(b)
                if out.rstrip().endswith(PROMPT):
                    return out
        print(f"\n[WARN] no prompt after {tmo}s: {c}", flush=True)
        return out

    if args.reset:
        ser.write(b"reset\r"); ser.flush(); time.sleep(2)
    for _ in range(30):
        ser.write(b" "); ser.flush(); time.sleep(0.04)
    ser.write(b"\r"); ser.flush(); time.sleep(0.4)
    ser.reset_input_buffer()
    probe = cmd("", tmo=5)
    if not probe.rstrip().endswith(PROMPT):
        # Not at U-Boot. If it's a booted Linux (login: or shell), reboot it back
        # to the QSPI U-Boot prompt instead of typing U-Boot commands into it.
        if b"login:" in probe or b"@visionfive2" in probe or b"# " in probe:
            print("[netboot] Linux detected on console; rebooting to U-Boot", flush=True)
            if b"login:" in probe:
                ser.write(b"root\r"); ser.flush(); time.sleep(4)
                # the login banner's `resize` probe reads stdin for a moment —
                # clear the line and wait for a real shell prompt before typing
                ser.write(b"\r"); ser.flush(); time.sleep(1.5)
                ser.reset_input_buffer()
            ser.write(b"reboot\r"); ser.flush()
            out = bytearray(); t = time.time()
            while time.time() - t < 90:
                b = ser.read(256)
                if b:
                    out += b; emit(b)
                    if out.rstrip().endswith(PROMPT):
                        break
            else:
                sys.exit("[netboot] board did not return to U-Boot after reboot")
            ser.reset_input_buffer()
        else:
            sys.exit(f"[netboot] no U-Boot prompt (got: {probe[-80:]!r}); aborting")

    # panic=10: auto-reboot a panicked kernel back to the U-Boot prompt so the
    # bench never needs a manual power-cycle to recover from a crash.
    bootargs = f"console=ttyS0,115200 earlycon=sbi root={args.root} rootwait panic=10"
    if args.blacklist:
        bootargs += f" modprobe.blacklist={args.blacklist}"
    if args.extra_args:
        bootargs += " " + args.extra_args

    cmd("setenv autoload no", 10)
    cmd("dhcp", 40)
    cmd(f"setenv serverip {args.serverip}", 10)
    cmd("setenv bootm_size 0x30000000", 10)
    cmd(f"setenv bootargs '{bootargs}'", 10)
    OV_SCRATCH = 0x51000000     # overlay .dtbo load base (above the loaded initrd)
    FDT_SCRATCH = "0x50000000"  # working copy of the control FDT
    overlays = [o for o in args.overlay.split(",") if o]
    def tftp(c, tmo):
        out = cmd(c, tmo)
        if b"Bytes transferred" not in out:
            sys.exit(f"[netboot] TFTP failed ({c}); aborting before booti")
        return out

    tftp("tftpboot ${kernel_addr_r} visionfive2/Image", 90)
    if args.dtb:
        tftp(f"tftpboot ${{fdt_addr_r}} {args.dtb}", 60)
    ov_addrs = []
    for i, ov in enumerate(overlays):
        addr = f"0x{OV_SCRATCH + i*0x100000:08x}"
        tftp(f"tftpboot {addr} {ov}", 30)
        ov_addrs.append(addr)
    # Last, because booti reads ${filesize} as the initrd size.
    tftp(f"tftpboot ${{ramdisk_addr_r}} {args.initramfs}", 120)

    if overlays:
        # fdt apply needs free space, so overlays go onto a resized copy of the control FDT.
        cmd(f"fdt move ${{fdtcontroladdr}} {FDT_SCRATCH}", 10)
        cmd(f"fdt addr {FDT_SCRATCH}", 10)
        cmd("fdt resize 0x20000", 10)
        for addr in ov_addrs:
            cmd(f"fdt apply {addr}", 15)
        fdt = FDT_SCRATCH
    elif args.dtb:
        # give U-Boot headroom to write chosen/initrd/memory fixups into the FDT
        cmd("fdt addr ${fdt_addr_r}", 10)
        cmd("fdt resize 0x10000", 10)
        fdt = "${fdt_addr_r}"
    else:
        fdt = "${fdtcontroladdr}"

    # A loaded DTB corrupts U-Boot's heap, so the xHCI free() in usb_stop() at handoff
    # store-faults; stopping USB now, heap still intact, avoids it.
    cmd("usb stop", 15)

    print(f"\n[netboot] booti (fdt={fdt}) bootargs: {bootargs}", flush=True)
    ser.reset_input_buffer()
    ser.write(f"booti ${{kernel_addr_r}} ${{ramdisk_addr_r}}:${{filesize}} {fdt}\r".encode())
    ser.flush()
    try:
        while True:
            b = ser.read(512)
            if b:
                emit(b)
    except KeyboardInterrupt:
        pass
    finally:
        logf.close(); ser.close()


if __name__ == "__main__":
    main()
