#!/usr/bin/env python3
"""VisionFive 2 UART-recovery boot loader + netboot driver.

JH7110 boot ROM (MSEL=1,1 UART mode) streams 'C' (XMODEM-CRC handshake).
Recovery sequence:
  1. XMODEM-CRC send u-boot-spl.bin.normal.out          (boot ROM, 128B packets)
  2. SPL runs in SRAM, re-issues 'C'                     (SPL_YMODEM_SUPPORT)
  3. YMODEM send u-boot.itb                              (1024B blocks)
  4. U-Boot prompt -> optionally interrupt autoboot and run the tftpboot chain

No lrzsz/sx needed; both protocols are hand-rolled over pyserial.

Usage:
  vf2-uart-boot.py --spl SPL --itb ITB [--port /dev/ttyUSB2]
                   [--boot | --flash-qspi] [--serverip IP] [--log FILE]
  vf2-uart-boot.py --console-only            # just attach + log

Env fallbacks: VF2_PORT for --port, SERVERIP for --serverip.
"""
import argparse
import os
import sys
import threading
import time

try:
    import serial
except ImportError:
    sys.exit("pyserial not found: pip install --user pyserial")

SOH = 0x01  # 128-byte packet
STX = 0x02  # 1024-byte packet
EOT = 0x04
ACK = 0x06
NAK = 0x15
CAN = 0x18
CRC = ord('C')

DEFAULT_PORT = "/dev/ttyUSB2"
DEFAULT_BAUD = 115200


def crc16_xmodem(data: bytes) -> int:
    crc = 0
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if (crc & 0x8000) else (crc << 1) & 0xFFFF
    return crc & 0xFFFF


def log(msg):
    sys.stderr.write(msg + "\n")
    sys.stderr.flush()


def wait_for_c(ser, timeout=30, label="handshake"):
    """Block until the receiver sends 'C' (or NAK). Returns the byte seen."""
    log(f"[{label}] waiting for handshake ('C') ... reset the board now if idle")
    deadline = time.time() + timeout
    seen = bytearray()
    while time.time() < deadline:
        b = ser.read(1)
        if not b:
            continue
        seen.append(b[0])
        if b[0] in (CRC, NAK):
            log(f"[{label}] got {'C' if b[0]==CRC else 'NAK'} -> start sending")
            return b[0]
    raise TimeoutError(f"[{label}] no handshake within {timeout}s (last bytes: {bytes(seen[-16:])!r})")


def _send_packet(ser, blk, payload, block_size):
    frame = bytearray()
    frame.append(SOH if block_size == 128 else STX)
    frame.append(blk & 0xFF)
    frame.append((~blk) & 0xFF)
    chunk = payload.ljust(block_size, b'\x1a')  # pad with CPMEOF
    frame += chunk
    crc = crc16_xmodem(chunk)
    frame.append((crc >> 8) & 0xFF)
    frame.append(crc & 0xFF)
    last = None
    for attempt in range(12):
        ser.write(frame)
        ser.flush()
        # Skip stray 'C' & NULs rather than retransmit: treating a late ACK as a
        # failure desyncs the transfer.
        deadline = time.time() + 2.0
        r = None
        while time.time() < deadline:
            b = ser.read(1)
            if not b:
                continue
            c = b[0]
            if c in (ACK, NAK, CAN):
                r = c
                break
            # else: 'C', 0x00, or noise -> keep waiting
        last = r
        if r == ACK:
            return
        if r == CAN:
            raise IOError("receiver cancelled (CAN)")
        # NAK or timeout -> retransmit same block
    raise IOError(f"block {blk}: no ACK after 12 retries (last resp {last!r})")


def xmodem_send(ser, path, block_size=128):
    data = open(path, "rb").read()
    total = len(data)
    log(f"[xmodem] sending {os.path.basename(path)} ({total} bytes, {block_size}B blocks)")
    wait_for_c(ser, label="xmodem")
    blk = 1
    off = 0
    t0 = time.time()
    while off < total:
        _send_packet(ser, blk, data[off:off + block_size], block_size)
        off += block_size
        blk += 1
        if blk % 64 == 0:
            log(f"[xmodem]  {off}/{total} bytes ({100*off//total}%)")
    for _ in range(10):
        ser.write(bytes([EOT]))
        ser.flush()
        r = ser.read(1)
        if r and r[0] == ACK:
            break
    log(f"[xmodem] done in {time.time()-t0:.1f}s")


def ymodem_send(ser, path, block_size=1024):
    data = open(path, "rb").read()
    total = len(data)
    name = os.path.basename(path)
    log(f"[ymodem] sending {name} ({total} bytes, {block_size}B blocks)")
    # header block (block 0): "name\0size\0..."
    wait_for_c(ser, label="ymodem-hdr")
    hdr = name.encode() + b'\x00' + str(total).encode()
    _send_packet(ser, 0, hdr, 128)          # header is always 128B
    # after header ACK, receiver sends 'C' again to start data
    wait_for_c(ser, label="ymodem-data")
    blk = 1
    off = 0
    t0 = time.time()
    while off < total:
        _send_packet(ser, blk, data[off:off + block_size], block_size)
        off += block_size
        blk += 1
        if blk % 32 == 0:
            log(f"[ymodem]  {off}/{total} bytes ({100*off//total}%)")
    # EOT (YMODEM: first EOT gets NAK, second gets ACK)
    ser.write(bytes([EOT])); ser.flush(); ser.read(1)
    ser.write(bytes([EOT])); ser.flush(); ser.read(1)
    # closing null header to end the batch
    try:
        wait_for_c(ser, timeout=5, label="ymodem-end")
        _send_packet(ser, 0, b'', 128)
    except TimeoutError:
        pass
    log(f"[ymodem] done in {time.time()-t0:.1f}s")


def stream_console(ser, logfile, stop_evt):
    with open(logfile, "ab", buffering=0) as lf:
        while not stop_evt.is_set():
            b = ser.read(256)
            if b:
                sys.stdout.buffer.write(b)
                sys.stdout.buffer.flush()
                lf.write(b)


PROMPT = b"StarFive #"

TFTP_CHAIN = (
    "setenv autoload no",
    "dhcp",
    "setenv serverip {serverip}",       # after dhcp, which overwrites it with the router
    "setenv bootm_size 0x30000000",     # keeps initrd & FDT clear of relocated U-Boot
    "setenv bootargs 'console=ttyS0,115200 earlycon=sbi root=/dev/ram0 rootwait'",
    "tftpboot ${{kernel_addr_r}} visionfive2/Image",
    "tftpboot ${{ramdisk_addr_r}} visionfive2/core-image-weston-visionfive2.rootfs.cpio.gz",
)
# U-Boot's own FDT: mainline 2026.01 store-faults fixing up a loaded DTB at handoff.
BOOTI = "booti ${kernel_addr_r} ${ramdisk_addr_r}:${filesize} ${fdtcontroladdr}"


def _echo(ser, dur):
    out = bytearray(); t = time.time()
    while time.time() - t < dur:
        b = ser.read(256)
        if b:
            out += b
            sys.stdout.buffer.write(b); sys.stdout.buffer.flush()
    return out


def _send_wait_prompt(ser, cmd, tmo):
    """Send one command, block until the U-Boot prompt returns (or timeout)."""
    ser.write(cmd.encode() + b"\r"); ser.flush()
    out = bytearray(); t = time.time()
    while time.time() - t < tmo:
        b = ser.read(256)
        if b:
            out += b
            sys.stdout.buffer.write(b); sys.stdout.buffer.flush()
            if out.rstrip().endswith(PROMPT):
                return out
    log(f"[uboot] WARN: no prompt after {tmo}s for: {cmd}")
    return out


def drive_uboot(ser, serverip, logfile):
    """Interrupt autoboot, run the tftpboot chain prompt-paced, then booti."""
    log(f"[uboot] interrupting autoboot; netboot via serverip={serverip}")
    for _ in range(60):
        ser.write(b' '); ser.flush(); time.sleep(0.03)
    ser.write(b"\r"); ser.flush()
    _echo(ser, 1.0)
    ser.reset_input_buffer()
    for line in TFTP_CHAIN:
        cmd = line.format(serverip=serverip)
        log(f"[uboot] >>> {cmd}")
        _send_wait_prompt(ser, cmd, tmo=90)   # 133 MB TFTP fetch can take ~60s
    log(f"[uboot] >>> {BOOTI}")
    ser.reset_input_buffer()
    ser.write(BOOTI.encode() + b"\r"); ser.flush()
    log("[uboot] booti sent; streaming boot log (Ctrl-C to detach)")
    stop = threading.Event()
    t = threading.Thread(target=stream_console, args=(ser, logfile, stop), daemon=True)
    t.start()
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        stop.set()
        t.join(timeout=2)


def _cmd(ser, cmd, tmo=90):
    """Send a U-Boot command, echo output, return once the prompt comes back."""
    ser.write(cmd.encode() + b"\r"); ser.flush()
    out = bytearray(); t = time.time()
    while time.time() - t < tmo:
        b = ser.read(256)
        if b:
            out += b
            sys.stdout.buffer.write(b); sys.stdout.buffer.flush()
            if out.rstrip().endswith(PROMPT):
                return out
    log(f"[uboot] WARN no prompt after {tmo}s for: {cmd}")
    return out


def catch_prompt(ser, secs=12):
    """Spam keys to break the autoboot countdown and land at the U-Boot prompt.
    Called with ZERO gap after upload so the SD card can't autoboot first."""
    log("[uboot] grabbing prompt (interrupting autoboot)...")
    t = time.time()
    while time.time() - t < secs:
        ser.write(b" "); ser.flush(); time.sleep(0.05)
    ser.write(b"\r"); ser.flush(); time.sleep(0.5)
    ser.reset_input_buffer()
    _cmd(ser, "", tmo=5)


def flash_qspi(ser, serverip):
    """Flash SPL@0x0 + u-boot.itb@0x100000 into QSPI, verify, persist env."""
    RAM_A, RAM_B = "0xa0000000", "0xb0000000"
    catch_prompt(ser)
    _cmd(ser, "sf probe", tmo=15)
    _cmd(ser, "setenv autoload no", tmo=10)
    _cmd(ser, "dhcp", tmo=40)
    _cmd(ser, f"setenv serverip {serverip}", tmo=10)
    ok = True
    for fname, off, tag in [
        ("visionfive2/u-boot-spl.bin.normal.out", "0x0", "spl"),
        ("visionfive2/u-boot.itb", "0x100000", "uboot"),
    ]:
        log(f"[qspi] === {tag} -> {off} ===")
        out = _cmd(ser, f"tftpboot {RAM_A} {fname}", tmo=90)
        if b"Bytes transferred" not in out:
            log(f"[qspi] FAIL tftp {tag}"); ok = False; break
        _cmd(ser, "setenv fsz ${filesize}", tmo=10)
        _cmd(ser, f"sf update {RAM_A} {off} ${{fsz}}", tmo=120)
        _cmd(ser, f"sf read {RAM_B} {off} ${{fsz}}", tmo=60)
        out = _cmd(ser, f"cmp.b {RAM_A} {RAM_B} ${{fsz}}", tmo=30)
        if b"same" not in out or b"differ" in out.lower():
            log(f"[qspi] FAIL verify {tag}"); ok = False; break
        log(f"[qspi] OK {tag} written+verified")
    if ok:
        # halt at prompt on every future reset (no autoboot race / SD soft-lock)
        _cmd(ser, "setenv bootdelay -1", tmo=10)
        _cmd(ser, "saveenv", tmo=20)
        log("[qspi] DONE — set MSEL=QSPI (0,0) and reset; U-Boot halts at prompt")
    else:
        log("[qspi] FAILED — do NOT switch MSEL; retry")
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default=os.environ.get("VF2_PORT", DEFAULT_PORT))
    ap.add_argument("--baud", type=int, default=DEFAULT_BAUD)
    ap.add_argument("--spl")
    ap.add_argument("--itb")
    ap.add_argument("--boot", action="store_true", help="drive the tftpboot chain after upload")
    ap.add_argument("--flash-qspi", action="store_true", help="flash SPL+itb into QSPI after upload")
    ap.add_argument("--serverip", default=os.environ.get("SERVERIP", "192.168.178.100"))
    ap.add_argument("--log", default="scripts/vf2-boot.log")
    ap.add_argument("--console-only", action="store_true")
    args = ap.parse_args()

    ser = serial.Serial(args.port, args.baud, timeout=1)
    log(f"[port] {args.port} @ {args.baud}")

    if args.console_only:
        stop = threading.Event()
        try:
            stream_console(ser, args.log, stop)
        except KeyboardInterrupt:
            pass
        return

    if args.spl:
        xmodem_send(ser, args.spl)
        time.sleep(1.5)  # let SPL come up and print its banner
    if args.itb:
        ymodem_send(ser, args.itb)

    if args.flash_qspi:
        flash_qspi(ser, args.serverip)      # zero-gap: grabs prompt before SD autoboots
    elif args.boot:
        time.sleep(1.0)
        drive_uboot(ser, args.serverip, args.log)
    else:
        log("[done] upload complete; attach a console to interact")


if __name__ == "__main__":
    main()
