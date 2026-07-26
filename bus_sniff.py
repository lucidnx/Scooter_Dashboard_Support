#!/usr/bin/env python3
"""Passively log the scooter's half-duplex bus via a Flipper Zero USB-UART bridge.

    pip install pyserial
    python3 bus_sniff.py /dev/tty.usbmodemflip_XXXX      (macOS)
    python3 bus_sniff.py COM5                            (Windows)

Prints one line per frame: time since start, gap since previous frame,
src>dst, command, register, length, and whether the checksum is valid.
Bad checksums or unparseable bytes mean two devices transmitted at once.
"""
import sys, time, serial

port = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyACM0"
ser = serial.Serial(port, 115200, timeout=0.05)
buf = bytearray()
t0 = time.time()
prev = {}
stats = {"ok": 0, "bad": 0, "junk": 0}

def ck(b):
    return (0xFFFF ^ (sum(b) & 0xFFFF)) & 0xFFFF

print(f"{'time':>8} {'gap':>7}  {'src>dst':<9} {'cmd':<5} {'reg':<5} {'len':<4} ok")
try:
    while True:
        data = ser.read(256)
        if data:
            buf += data
        while len(buf) >= 9:
            i = buf.find(b"\x5a\xa5")
            if i < 0:
                stats["junk"] += len(buf) - 1
                del buf[:-1]
                break
            if i:
                stats["junk"] += i
                del buf[:i]
            if len(buf) < 9:
                break
            ln = buf[2]
            total = ln + 9
            if ln > 60:
                stats["junk"] += 2
                del buf[:2]
                continue
            if len(buf) < total:
                break
            f = bytes(buf[:total])
            del buf[:total]
            src, dst, cmd, reg = f[3], f[4], f[5], f[6]
            good = ck(f[2:2 + 5 + ln]) == int.from_bytes(f[-2:], "little")
            stats["ok" if good else "bad"] += 1
            now = time.time() - t0
            key = (src, dst, cmd)
            gap = now - prev.get(key, now)
            prev[key] = now
            print(f"{now:8.3f} {gap*1000:6.1f}ms  {src:02x}>{dst:02x}     "
                  f"{cmd:02x}    {reg:02x}    {ln:<4} {'ok' if good else 'BAD'}")
except KeyboardInterrupt:
    tot = stats["ok"] + stats["bad"]
    print(f"\nframes {tot}   good {stats['ok']}   bad checksum {stats['bad']}"
          f"   junk bytes {stats['junk']}")
