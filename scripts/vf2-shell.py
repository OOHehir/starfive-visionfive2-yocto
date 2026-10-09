#!/usr/bin/env python3
"""Run shell commands on the VF2 over the serial console, logging in as root.

Relies on the image's passwordless root. Commands come from --cmd (repeatable)
or stdin, one per line.

Usage:
  vf2-shell.py --cmd 'uname -a' --cmd 'lsusb'
  echo -e 'ip -br link\\ndmesg | tail' | vf2-shell.py
"""
import argparse
import re
import sys
import time

import serial

LOGIN_RE = b"login:"
# The root prompt, e.g. "root@visionfive2:~# ".
PROMPT = b"# "


def read_until(ser, needles, tmo, echo=True):
    out = bytearray(); t = time.time()
    if isinstance(needles, (bytes, bytearray)):
        needles = [needles]
    while time.time() - t < tmo:
        b = ser.read(256)
        if b:
            out += b
            if echo:
                sys.stdout.buffer.write(b); sys.stdout.buffer.flush()
            for n in needles:
                if n in out:
                    return out, n
    return out, None


def ensure_shell(ser):
    ser.write(b"\r"); ser.flush()
    out, hit = read_until(ser, [LOGIN_RE, PROMPT], 4, echo=False)
    if hit == LOGIN_RE or LOGIN_RE in out:
        ser.write(b"root\r"); ser.flush()
        read_until(ser, PROMPT, 8, echo=False)
    else:
        ser.write(b"\r"); ser.flush()
        read_until(ser, PROMPT, 3, echo=False)


MARKER = "___END___"
# The echoed command line holds "$?", not digits, so only the real output matches.
# The tty turns "\n" into "\r\n" (ONLCR); a plain "\n" also matches.
END_RE = re.compile(MARKER.encode() + rb"(\d+)\r?\n")


def run(ser, cmd, tmo=25):
    print(f"\n\033[1m$ {cmd}\033[0m", flush=True)
    ser.reset_input_buffer()
    ser.write((cmd + f"\recho {MARKER}$?\r").encode()); ser.flush()
    out = bytearray(); t = time.time(); m = None
    while m is None and time.time() - t < tmo:
        b = ser.read(256)
        if b:
            out += b
            sys.stdout.buffer.write(b); sys.stdout.buffer.flush()
            m = END_RE.search(out)
    # Drain to the prompt so the next command does not interleave.
    read_until(ser, PROMPT, 3)
    if m is None:
        print(f"\n[WARN] no end-marker after {tmo}s", flush=True)
    elif m.group(1) != b"0":
        print(f"\n[WARN] exit status {m.group(1).decode()}", flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="/dev/ttyUSB2")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--cmd", action="append", default=[])
    ap.add_argument("--tmo", type=int, default=25)
    args = ap.parse_args()

    cmds = list(args.cmd)
    if not sys.stdin.isatty():
        cmds += [l.strip() for l in sys.stdin if l.strip()]
    if not cmds:
        print("no commands given", file=sys.stderr); sys.exit(2)

    ser = serial.Serial(args.port, args.baud, timeout=0.3)
    ensure_shell(ser)
    for c in cmds:
        run(ser, c, args.tmo)
    ser.close()
    print("\n[done]", flush=True)


if __name__ == "__main__":
    main()
