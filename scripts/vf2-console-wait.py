#!/usr/bin/env python3
"""Reboot the VF2 from its serial console & log the console until a line matches.

Works from a Linux shell, a login prompt or the U-Boot prompt. Exit 0 when
--until matched, 1 on timeout. --poweroff shuts Linux down instead of
rebooting (the U-Boot prompt has no poweroff, so it is left as it is).

Usage: vf2-console-wait.py --until REGEX [--tmo SECS] [--log FILE]
                           [--no-reboot | --poweroff]
"""
import argparse
import re
import sys
import time

import serial


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="/dev/ttyUSB0")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--until", required=True)
    ap.add_argument("--tmo", type=int, default=900)
    ap.add_argument("--log", default="/dev/null")
    ap.add_argument("--no-reboot", action="store_true")
    ap.add_argument("--poweroff", action="store_true")
    args = ap.parse_args()

    until = re.compile(args.until.encode())
    ser = serial.Serial(args.port, args.baud, timeout=0.3)
    log = open(args.log, "ab", buffering=0)
    out = bytearray()

    def read(secs):
        t = time.time()
        while time.time() - t < secs:
            b = ser.read(256)
            if b:
                out.extend(b); log.write(b)
                sys.stdout.buffer.write(b); sys.stdout.buffer.flush()
                if until.search(out):
                    return True
        return False

    if not args.no_reboot:
        ser.write(b"\r"); ser.flush()
        read(3)
        tail = bytes(out[-200:])
        if tail.rstrip().endswith(b"StarFive #"):
            if args.poweroff:
                print("\n[console-wait] at the U-Boot prompt: nothing to shut down", file=sys.stderr)
                return 1
            ser.write(b"reset\r")
        else:
            if b"login:" in tail:
                ser.write(b"root\r"); ser.flush(); read(4)
            ser.write(b"\rpoweroff\r" if args.poweroff else b"\rreboot\r")
        ser.flush()
        del out[:]

    ok = read(args.tmo)
    if not ok:
        print(f"\n[console-wait] no match for {args.until!r} after {args.tmo}s", file=sys.stderr)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
