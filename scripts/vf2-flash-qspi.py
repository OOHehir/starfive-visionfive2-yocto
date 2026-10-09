#!/usr/bin/env python3
"""Flash SPL + u-boot.itb into the VF2 QSPI NOR from a live U-Boot prompt.

Run after vf2-uart-boot.py has U-Boot at its prompt. Layout (mainline
CONFIG_SYS_SPI_U_BOOT_OFFS=0x100000):
  QSPI 0x000000 : u-boot-spl.bin.normal.out   (boot ROM loads this in QSPI mode)
  QSPI 0x100000 : u-boot.itb                   (SPL loads this)
Each image is read back & compared. Then set MSEL=QSPI (0,0); UART recovery
(MSEL=1,1) still rescues a bad flash.
"""
import argparse
import sys
import time

import serial

PROMPT = b"StarFive #"
RAM_A = "0xa0000000"   # load buffer (DRAM, well above SPL/U-Boot)
RAM_B = "0xb0000000"   # read-back compare buffer


def send(ser, cmd, tmo=90, quiet=False):
    ser.write(cmd.encode() + b"\r"); ser.flush()
    out = bytearray(); t = time.time()
    while time.time() - t < tmo:
        b = ser.read(256)
        if b:
            out += b
            if not quiet:
                sys.stdout.buffer.write(b); sys.stdout.buffer.flush()
            if out.rstrip().endswith(PROMPT):
                return out
    print(f"\n[WARN] no prompt after {tmo}s for: {cmd}", flush=True)
    return out


def expect_ok(out, cmd, needles):
    """Fail loudly if none of the expected success markers appear."""
    txt = out.decode(errors="replace")
    if not any(n in txt for n in needles):
        print(f"\n[FAIL] '{cmd}' did not report success ({needles}).", flush=True)
        return False
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="/dev/ttyUSB2")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--serverip", default="192.168.178.100")
    args = ap.parse_args()

    ser = serial.Serial(args.port, args.baud, timeout=0.3)

    # break autoboot, get a clean prompt
    for _ in range(60):
        ser.write(b" "); ser.flush(); time.sleep(0.03)
    ser.write(b"\r"); ser.flush(); time.sleep(0.6)
    ser.reset_input_buffer()
    send(ser, "")  # sync to prompt

    ok = True
    out = send(ser, "sf probe", tmo=15)
    ok &= expect_ok(out, "sf probe", ["SF: Detected", "sf probe"])

    send(ser, "setenv autoload no", tmo=10)
    send(ser, "dhcp", tmo=40)
    send(ser, f"setenv serverip {args.serverip}", tmo=10)

    images = [
        ("visionfive2/u-boot-spl.bin.normal.out", "0x0", "spl"),
        ("visionfive2/u-boot.itb", "0x100000", "uboot"),
    ]
    for fname, off, tag in images:
        print(f"\n===== flashing {tag} -> QSPI {off} =====", flush=True)
        out = send(ser, f"tftpboot {RAM_A} {fname}", tmo=90)
        if not expect_ok(out, "tftpboot", ["Bytes transferred"]):
            ok = False; break
        send(ser, "setenv fsz ${filesize}", tmo=10)
        out = send(ser, f"sf update {RAM_A} {off} ${{fsz}}", tmo=120)
        if not expect_ok(out, "sf update", ["bytes written", "bytes: 0",
                                            "0 bytes written, ", "written"]):
            ok = False; break
        send(ser, f"sf read {RAM_B} {off} ${{fsz}}", tmo=60)
        out = send(ser, f"cmp.b {RAM_A} {RAM_B} ${{fsz}}", tmo=30)
        if "differ" in out.decode(errors="replace").lower() or \
           "Total of" not in out.decode(errors="replace"):
            print(f"\n[FAIL] verify mismatch for {tag}", flush=True)
            ok = False; break
        print(f"[OK] {tag} written + verified", flush=True)

    print("\n" + ("=== QSPI FLASH OK — set MSEL=QSPI (0,0) and reset ==="
                  if ok else "=== QSPI FLASH FAILED — do NOT switch MSEL, retry ==="),
          flush=True)
    ser.close()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
