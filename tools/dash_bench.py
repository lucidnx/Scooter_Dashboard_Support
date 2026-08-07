#!/usr/bin/env python3
"""Pretend to be the ESC so a scooter dashboard can be driven from a PC.

The dashboard talks to its controller over one half-duplex wire at 115200. Put a
Flipper Zero in USB-UART bridge mode on that wire and this answers the dash the
way scooter_support.lisp does, so a dash - and an app paired to its BLE module -
can be exercised without a VESC anywhere near the bench.

    Flipper 13 (TX) --[1k]--+
                            +---- dash signal (green on Ninebot, single wire on Xiaomi)
    Flipper 14 (RX) --------+
    Flipper 8/11/18 (GND) -- dash GND
    dash 5V from a bench supply, ground common with the Flipper

Tying TX and RX together is what makes it half duplex, and it means every byte
sent comes straight back in. Echo suppression is on by default; -E turns it off
if you wired a proper transceiver instead.

    tools/dash_bench.py --port /dev/tty.usbmodemXXXX --proto xiaomi
    tools/dash_bench.py --port COM7 --proto ninebot --log logs/bench.log

Keys while running: q quit, l headlight, k lock, b beep, m mode, +/- speed,
[/] battery, f fault, s dump the register tables the dash has asked for.
"""

import argparse
import sys
import time
from collections import Counter


def _serial():
    """Imported on use, not on import - the codec below is worth having in a
    REPL for picking apart a capture, and that needs no serial port."""
    try:
        import serial
    except ImportError:
        sys.exit("needs pyserial:  pip3 install --user pyserial")
    return serial

# ---------------------------------------------------------------- frame codecs
#
# Both protocols are [header][len][addressing][cmd][arg][payload][crc16], the
# checksum is the sum of everything from the length byte to the end of the
# payload inverted, and it goes out low byte first. They differ in the header,
# in how many address bytes there are, and in what len counts:
#
#   Ninebot  5A A5 | len | src dst cmd arg | payload | crc    len = payload
#   Xiaomi   55 AA | len | addr cmd arg    | payload | crc    len = payload + 2
#
# Verified against seal-dash-frame in scooter_support.lisp, which has driven a
# real dash of each family since v2.0.

NINEBOT, XIAOMI = "ninebot", "xiaomi"
HEADER = {NINEBOT: b"\x5a\xa5", XIAOMI: b"\x55\xaa"}
ADDR_LEN = {NINEBOT: 2, XIAOMI: 1}


def crc_of(proto, ln, body):
    """body is everything from the first address byte to the last payload byte"""
    return (ln + sum(body)) ^ 0xFFFF


def encode(proto, addr, cmd, arg, payload):
    """addr is (src, dst) on Ninebot, a single device byte on Xiaomi"""
    body = bytes(addr) + bytes([cmd, arg]) + bytes(payload)
    ln = len(payload) if proto == NINEBOT else len(payload) + 2
    crc = crc_of(proto, ln, body)
    return HEADER[proto] + bytes([ln]) + body + bytes([crc & 0xFF, crc >> 8 & 0xFF])


class Frame:
    __slots__ = ("proto", "ln", "src", "dst", "cmd", "arg", "payload", "raw", "ok")

    def __init__(self, proto, ln, addr, cmd, arg, payload, raw, ok):
        self.proto, self.ln, self.cmd, self.arg = proto, ln, cmd, arg
        self.payload, self.raw, self.ok = payload, raw, ok
        if proto == NINEBOT:
            self.src, self.dst = addr[0], addr[1]
        else:
            self.src, self.dst = None, addr[0]

    def __str__(self):
        who = f"{self.src:02X}->{self.dst:02X}" if self.src is not None else f"{self.dst:02X}"
        return (f"{who} cmd={self.cmd:02X} arg={self.arg:02X} "
                f"len={self.ln} {'ok ' if self.ok else 'BAD'} "
                f"[{' '.join(f'{b:02X}' for b in self.payload)}]")


class Decoder:
    """Byte stream in, frames out. Resyncs on the header the way the reader in
    scooter_support.lisp does, so a lost byte costs one frame and not the link."""

    def __init__(self, proto):
        self.proto = proto
        self.buf = bytearray()

    def feed(self, data):
        self.buf.extend(data)
        out = []
        hdr = HEADER[self.proto]
        alen = ADDR_LEN[self.proto]
        while True:
            i = self.buf.find(hdr)
            if i < 0:
                # keep one byte back: the header may be split across two reads
                del self.buf[: max(0, len(self.buf) - 1)]
                return out
            if i:
                del self.buf[:i]
            if len(self.buf) < 3:
                return out
            ln = self.buf[2]
            payload_n = ln if self.proto == NINEBOT else ln - 2
            if payload_n < 0 or payload_n > 60:
                del self.buf[:2]                      # nonsense length, resync
                continue
            total = 3 + alen + 2 + payload_n + 2
            if len(self.buf) < total:
                return out
            body = bytes(self.buf[3: total - 2])
            got = self.buf[total - 2] | (self.buf[total - 1] << 8)
            ok = got == crc_of(self.proto, ln, body)
            out.append(Frame(self.proto, ln, body[:alen], body[alen], body[alen + 1],
                             body[alen + 2:], bytes(self.buf[:total]), ok))
            del self.buf[:total]


# ------------------------------------------------------------- emulated scooter

class Scooter:
    """Everything the dash and an app can read, and the handful of things they
    can write. Mirrors nb-word / xm-word / xm-bms-word so a discrepancy here is
    a discrepancy in the script."""

    def __init__(self, serial_no="TEST0000000001", pin="123456"):
        self.serial_no = serial_no.ljust(14, "0")[:14]
        self.pin = pin.ljust(6, "0")[:6]
        self.version = 0x0700           # reads as 7.0.0, above every stock build
        self.speed_kmh = 0.0
        self.battery = 78
        self.mode = 1                   # 1 drive, 2 eco, 4 sport
        self.light = False
        self.lock = False
        self.off = False
        self.cruise = False
        self.taillight = False
        self.buzzer = True
        self.fault = 0
        self.alarm = 0
        self.beeps = 0
        self.temp_c = 27.0
        self.vin = 41.5
        self.current_a = 0.0
        self.odo_m = 25_990
        self.trip_m = 1_240
        self.cells = 10
        self.cap_mah = 7800
        self.boot = time.time()
        self.writes = []                # (register, value) an app has sent us

    # ---- helpers matching the lisp names so the two are easy to compare
    def uptime(self):
        return int(time.time() - self.boot)

    def workmode(self):
        return {2: 1, 4: 2}.get(self.mode, 0)

    def bool_word(self):
        return (1 if self.mode == 2 else 0) | (2 if self.lock else 0) \
             | (4 if self.alarm else 0) | 2048

    def _str_word(self, s, i):
        b = s.encode() + b"\0\0"
        return b[i * 2] | (b[i * 2 + 1] << 8)

    def esc_word(self, proto, reg):
        """One register of the ESC table. proto matters for the few that differ."""
        xm = proto == XIAOMI
        spd10 = int(abs(self.speed_kmh) * 10)
        spd_mh = min(65535, int(abs(self.speed_kmh) * 1000))
        if 0x10 <= reg < 0x17:
            return self._str_word(self.serial_no, reg - 0x10)
        if 0x17 <= reg < 0x1A:
            return self._str_word(self.pin, reg - 0x17)
        table = {
            0x1A: self.version, 0x66: self.version, 0x67: self.version,
            0x68: self.version,
            0x1B: self.fault, 0x1C: 9 if self.alarm else 0, 0x1D: self.bool_word(),
            0x1F: self.workmode(), 0x22: self.battery,
            0x24: int(self.range_km() * 100), 0x25: int(self.range_km() * 100),
            0x26: spd10, 0x65: spd10,
            0x29: self.odo_m & 0xFFFF, 0x2A: self.odo_m >> 16,
            0x2F: self.trip_m // 10,
            0x32: self.uptime() & 0xFFFF, 0x33: self.uptime() >> 16,
            0x3A: self.uptime(),
            0x3B: (min(65535, self.trip_m) if xm else self.uptime()),
            0x3E: int(self.temp_c * 10),
            0x41: int(self.temp_c * 10), 0x47: int(self.vin * 100),
            0x72: 250, 0x73: 250, 0x74: 250,
            0x75: (1 if self.mode == 2 else 0) if xm else self.workmode(),
            0x76: int(self.light), 0x77: 0, 0x7A: int(self.light),
            0x7B: {1: 1, 4: 2}.get(self.mode, 0),
            0x7C: int(self.cruise), 0x7D: 2 if self.taillight else 0,
            0x90: int(self.light), 0x91: int(self.buzzer), 0x92: int(self.buzzer),
            0xB0: self.fault, 0xB1: 9 if self.alarm else 0, 0xB2: self.bool_word(),
            0xB3: self.workmode(), 0xB4: self.battery,
            0xB5: spd_mh if xm else spd10, 0xB6: spd_mh if xm else spd10,
            0xB7: self.odo_m & 0xFFFF, 0xB8: self.odo_m >> 16,
            0xB9: self.trip_m // 10, 0xBA: self.uptime(),
            0xBB: int(self.temp_c * 10), 0xBE: 9 if self.alarm else 0,
        }
        if 0xDA <= reg <= 0xDF:
            return self._cpuid_word(reg - 0xDA)
        return table.get(reg, 0)

    def _cpuid_word(self, i):
        """NB_CPUID_A-F. Apps print these as plain hex, so app-build-serial packs
        the serial's ten digits two to a byte - five bytes of a twelve byte
        field, the rest left zero - and it reads back as the serial itself."""
        d = self.serial_no[4:14].ljust(10, "0")
        cpuid = bytes([(ord(d[k * 2]) - 48) << 4 | (ord(d[k * 2 + 1]) - 48)
                       for k in range(5)]) + bytes(7)
        return cpuid[i * 2] | (cpuid[i * 2 + 1] << 8)

    def bms_word(self, reg):
        if 0x10 <= reg < 0x17:
            return self._str_word(self.serial_no, reg - 0x10)
        return {
            0x17: self.version, 0x18: self.cap_mah, 0x20: 0x3021,
            0x31: int(self.battery * self.cap_mah / 100), 0x32: self.battery,
            0x33: int(self.current_a * 100) & 0xFFFF, 0x34: int(self.vin * 100),
            0x35: (int(self.temp_c) + 20) | ((int(self.temp_c) + 20) << 8),
            0x3B: 100,
        }.get(reg, int(self.vin * 1000 / self.cells) if 0x40 <= reg < 0x4A else 0)

    def range_km(self):
        return max(0.0, self.battery * 0.4)

    def apply_write(self, reg, val):
        self.writes.append((reg, val))
        if reg == 0x70 and val:
            self.lock = True
        elif reg == 0x71 and val:
            self.lock = False
        elif reg == 0x75:
            self.mode = {1: 2, 2: 4}.get(val, 1)
        elif reg == 0x7B:
            self.mode = {1: 1, 2: 4}.get(val, 2)
        elif reg in (0x76, 0x7A, 0x90):
            self.light = bool(val)
        elif reg == 0x7C:
            self.cruise = bool(val)
        elif reg == 0x7D:
            self.taillight = bool(val)
        elif reg in (0x91, 0x92):
            self.buzzer = bool(val)
        elif reg == 0x7E and val:
            self.beeps = 3
        elif reg == 0x79 and val:
            self.off = True

    def dash_payload(self, proto, g2=False):
        """The six field reply: mode, battery, light, beep, speed, error."""
        if self.off:
            mode = 16
        elif self.lock:
            mode = 32
        else:
            mode = self.mode
            if g2 and self.mode == 1:
                mode = 0
            if self.temp_c > 80:
                mode += 128
        beep = 1 if self.beeps > 0 else 0
        if self.beeps:
            self.beeps -= 1
        light = 0 if self.off else (16 if (g2 and self.light) else int(self.light))
        speed = 0 if self.lock else int(abs(self.speed_kmh) + 0.5)
        p = [mode, 0 if self.lock else self.battery, light, beep, speed,
             99 if self.alarm else self.fault]
        return p + ([0x04, 0x91] if g2 else [])


# -------------------------------------------------------------- plain English
#
# What each register means and how to read its value, so a session on the bench
# is a conversation you can follow rather than a wall of hex. Names match the
# lisp so a surprise here points straight at nb-word / xm-word / xm-bms-word.

def _secs(v):
    return f"{v // 60}m {v % 60}s" if v >= 60 else f"{v}s"


def _mode_name(v):
    return {0: "DRIVE(G2)", 1: "DRIVE", 2: "ECO", 4: "SPORT"}.get(v, f"?{v}")


ESC_REGS = {
    0x10: ("serial", "ascii"), 0x17: ("pin", "ascii"), 0x1A: ("firmware", "ver"),
    0x1B: ("fault", "raw"), 0x1C: ("alarm", "raw"), 0x1D: ("flags", "hex"),
    0x1F: ("workmode", "raw"), 0x22: ("battery", "pct"), 0x24: ("range", "range"),
    0x25: ("range", "range"), 0x26: ("speed", "spd10"), 0x29: ("odometer lo", "raw"),
    0x2A: ("odometer hi", "raw"), 0x2F: ("trip", "dam"), 0x32: ("runtime lo", "raw"),
    0x33: ("runtime hi", "raw"), 0x3A: ("trip seconds", "secs"),
    0x3B: ("trip metres / uptime", "raw"), 0x3E: ("temperature", "t10"),
    0x41: ("motor temp", "t10"), 0x47: ("pack voltage", "cv"),
    0x65: ("speed", "spd10"), 0x66: ("version", "ver"), 0x67: ("bms version", "ver"),
    0x68: ("version", "ver"), 0x70: ("LOCK", "bool"), 0x71: ("UNLOCK", "bool"),
    0x72: ("max speed", "spd10"), 0x73: ("max speed", "spd10"),
    0x74: ("max speed", "spd10"), 0x75: ("workmode", "raw"),
    0x76: ("headlight", "bool"), 0x77: ("walk mode -> secret", "bool"),
    0x79: ("power down", "bool"), 0x7A: ("headlight", "bool"),
    0x7B: ("KERS -> speed mode", "kers"), 0x7C: ("cruise control", "bool"),
    0x7D: ("tail light", "bool"), 0x7E: ("find my scooter", "bool"),
    0x90: ("direct power -> headlight", "bool"), 0x91: ("buzzer", "bool"),
    0x92: ("buzzer", "bool"),
    0xB0: ("fault", "raw"), 0xB1: ("warning", "raw"), 0xB2: ("flags", "hex"),
    0xB3: ("workmode", "raw"), 0xB4: ("battery", "pct"), 0xB5: ("speed", "spd"),
    0xB6: ("average speed", "spd"), 0xB7: ("odometer lo", "raw"),
    0xB8: ("odometer hi", "raw"), 0xB9: ("trip", "dam"), 0xBA: ("seconds on", "secs"),
    0xBB: ("temperature", "t10"), 0xBC: ("max speed", "raw"),
    0xBE: ("last alarm", "raw"),
}
BMS_REGS = {
    0x10: ("bms serial", "ascii"), 0x17: ("bms version", "ver"),
    0x18: ("capacity", "mah"), 0x20: ("date", "hex"), 0x1B: ("cycles", "raw"),
    0x31: ("charge left", "mah"), 0x32: ("battery", "pct"),
    0x33: ("current", "ca"), 0x34: ("voltage", "cv"), 0x35: ("cell temps", "hex"),
    0x3B: ("health", "pct"),
}


def reg_info(reg, bms):
    if bms:
        if 0x40 <= reg < 0x4A:
            return (f"cell {reg - 0x3F} voltage", "mv")
        if 0x10 <= reg < 0x17:
            return ("bms serial", "ascii")
        return BMS_REGS.get(reg, (f"reg 0x{reg:02X}", "raw"))
    if 0x10 <= reg < 0x17:
        return ("serial", "ascii")
    if 0x17 <= reg < 0x1A:
        return ("pin", "ascii")
    if 0xDA <= reg <= 0xDF:
        return ("cpu id", "hex")
    return ESC_REGS.get(reg, (f"reg 0x{reg:02X}", "raw"))


def show_value(kind, v, proto):
    if kind == "bool":
        return "ON" if v else "off"
    if kind == "pct":
        return f"{v}%"
    if kind == "t10":
        return f"{v / 10:.1f} C"
    if kind == "cv":
        return f"{v / 100:.2f} V"
    if kind == "ca":
        return f"{(v - 65536 if v > 32767 else v) / 100:.2f} A"
    if kind == "mv":
        return f"{v / 1000:.3f} V"
    if kind == "mah":
        return f"{v} mAh"
    if kind == "spd10":
        return f"{v / 10:.1f} km/h"
    if kind == "spd":                       # the one real protocol split
        return f"{v / 1000:.1f} km/h" if proto == XIAOMI else f"{v / 10:.1f} km/h"
    if kind == "range":
        return f"{v / 100:.1f} km"
    if kind == "dam":
        return f"{v / 100:.2f} km"
    if kind == "secs":
        return _secs(v)
    if kind == "ver":
        return f"{v >> 8}.{(v >> 4) & 0xF}.{v & 0xF}"
    if kind == "hex":
        return f"0x{v:04X}"
    if kind == "ascii":
        a, b = v & 0xFF, v >> 8
        return "".join(chr(c) if 32 <= c < 127 else "." for c in (a, b))
    return str(v)


def explain_dash_reply(payload, proto, g2):
    mode, batt, light, beep, speed, err = payload[:6]
    bits = []
    if mode == 16:
        bits.append("OFF")
    elif mode == 32:
        bits.append("LOCKED")
    else:
        bits.append(_mode_name(mode & 0x3F))
        if mode & 128:
            bits.append("OVERHEAT")
        if g2 and mode & 64:
            bits.append("mph")
    if g2:
        lamp = ("headlight ON" if light & 16 else "headlight off")
        if light & 2:
            lamp += " +lock"
        if light & 4:
            lamp += " +cruise"
    else:
        lamp = "headlight ON" if light else "headlight off"
    return (f"{' '.join(bits):<18s} battery {batt:3d}%  {lamp:<22s} "
            f"{'BEEP' if beep else '    '}  speed {speed:3d}  "
            f"{'error ' + str(err) if err else 'no error'}")


# ----------------------------------------------------------------- the bench

class Bench:
    def __init__(self, args):
        self.proto = args.proto
        self.g2 = args.g2
        self.quiet65 = args.quiet_65
        self.sc = Scooter(args.serial, args.pin)
        self.dec = Decoder(self.proto)
        self.log = open(args.log, "a", buffering=1) if args.log else None
        self.echo = not args.no_echo_filter
        self.pending_echo = bytearray()
        self.seen = Counter()
        self.reads = Counter()
        self.last_report = time.time()
        self.verbose = args.verbose
        self.folded = {}
        self.ser = _serial().Serial(args.port, args.baud, timeout=0)
        self.ser.reset_input_buffer()

    def say(self, tag, text, collapse=None):
        """One narrated line. The log always gets every one; the screen folds
        runs of identical lever frames and replies, because at fifty a second
        they would bury everything worth reading."""
        line = f"{time.strftime('%H:%M:%S')} {tag} {text}"
        if self.log:
            self.log.write(line + "\n")
        if self.verbose or collapse is None:
            print(line)
            return
        # Each stream folds against its own last line - the dash frame and the
        # reply alternate, so "same as the one before" would never be true.
        prev, n = self.folded.get(collapse, (None, 0))
        if text == prev:
            self.folded[collapse] = (prev, n + 1)
            return
        if n:
            print(f"{' ' * 9}{tag} ... x{n} more, unchanged")
        self.folded[collapse] = (text, 0)
        print(line)

    def send(self, data):
        if self.echo:
            self.pending_echo.extend(data)
        self.ser.write(data)
        if self.log:
            self.log.write(f"{time.strftime('%H:%M:%S')} tx "
                           f"{' '.join(f'{b:02X}' for b in data)}\n")

    def strip_echo(self, data):
        """Half duplex puts everything we sent back in our own ear."""
        if not self.echo or not self.pending_echo:
            return data
        out = bytearray()
        for b in data:
            if self.pending_echo and self.pending_echo[0] == b:
                self.pending_echo.pop(0)
            else:
                self.pending_echo.clear()
                out.append(b)
        return bytes(out)

    def handle(self, f):
        self.seen[f.cmd] += 1
        if not f.ok:
            self.say("BAD ", f"checksum failed  {' '.join(f'{b:02X}' for b in f.raw)}")
            return

        # Lever frames. Both families put throttle at payload[1] and brake at
        # payload[2] - Ninebot buf 5 and 6 past a four byte head, Xiaomi buf 4
        # and 5 past a three byte one, which lands on the same pair.
        if f.cmd in (0x61, 0x64, 0x65):
            thr = f.payload[1] if len(f.payload) > 1 else 0
            brk = f.payload[2] if len(f.payload) > 2 else 0
            self.levers = (thr, brk)
            kind = {0x61: "levers (app connected)", 0x64: "levers + poll",
                    0x65: "levers"}[f.cmd]
            self.say("DASH", f"{kind:<22s} throttle {thr:3d} ({thr / 77.2:.2f} V)"
                             f"   brake {brk:3d} ({brk / 77.2:.2f} V)",
                     collapse=f"lever{f.cmd}")
            # CamiAlfa's notes say 0x65 wants no reply and only 0x64 does. The
            # script answers everything, so --quiet-65 is how you find out which
            # the dash in front of you actually needs.
            if f.cmd == 0x64 or (self.proto == XIAOMI and not self.quiet65):
                self.reply_dash()
            return

        # app register access
        if f.cmd == 0x01:                                  # read
            n = f.payload[0] & 0xFE if f.payload else 2
            n = max(2, min(64, n))
            bms = f.dst == 0x22
            self.reads[(f.arg, n)] += 1
            words = [(self.sc.bms_word(f.arg + k) if bms
                      else self.sc.esc_word(self.proto, f.arg + k)) for k in range(n // 2)]
            who = "BMS" if bms else "ESC"
            first = reg_info(f.arg, bms)[0]
            self.say("APP ", f"reads {who} 0x{f.arg:02X} x{n}B"
                             f"{'  (' + first + ')' if n <= 2 else '  (block from ' + first + ')'}")
            kinds = [reg_info(f.arg + k, bms)[1] for k in range(len(words))]
            if kinds and all(x == "ascii" for x in kinds):
                txt = "".join(show_value("ascii", w, self.proto) for w in words)
                self.say("  ->", f'0x{f.arg:02X} {first:<26s} "{txt.rstrip(chr(0))}"')
            else:
                for k, w in enumerate(words):
                    name, kind = reg_info(f.arg + k, bms)
                    if name.startswith("reg 0x") and w == 0:
                        continue                 # nothing there and nobody named it
                    self.say("  ->", f"0x{f.arg + k:02X} {name:<26s} "
                                     f"{show_value(kind, w, self.proto)}")
            pay = b"".join(bytes([w & 0xFF, w >> 8 & 0xFF]) for w in words)
            if self.proto == XIAOMI:
                self.send(encode(XIAOMI, [0x25 if bms else 0x23], 0x01, f.arg, pay))
            else:
                self.send(encode(NINEBOT, [0x22 if bms else 0x20, f.src], 0x04, f.arg, pay))
        elif f.cmd in (0x02, 0x03):                        # write
            if f.payload:
                val = f.payload[0] | (f.payload[1] << 8 if len(f.payload) > 1 else 0)
                name, kind = reg_info(f.arg, f.dst == 0x22)
                before = self.snapshot()
                self.sc.apply_write(f.arg, val)
                after = self.snapshot()
                changed = [f"{k} is now {after[k]}" for k in after if before[k] != after[k]]
                self.say("APP ", f"WRITES 0x{f.arg:02X} {name} = "
                                 f"{show_value(kind, val, self.proto)}"
                                 + (f"    -> {', '.join(changed)}" if changed
                                    else "    (no change)"))
            if self.proto == NINEBOT:
                self.send(encode(NINEBOT, [0x20, f.src], 0x05, f.arg, b"\x01"))

    def snapshot(self):
        """Stable keys, so a value that flips does not also move the key."""
        s = self.sc
        return {"mode": _mode_name(s.mode), "headlight": "ON" if s.light else "off",
                "lock": "ON" if s.lock else "off",
                "cruise": "ON" if s.cruise else "off",
                "tail light": "ON" if s.taillight else "off",
                "buzzer": "ON" if s.buzzer else "off",
                "power": "off" if s.off else "ON"}

    def reply_dash(self):
        pay = self.sc.dash_payload(self.proto, self.g2)
        if self.proto == XIAOMI:
            self.send(encode(XIAOMI, [0x21], 0x64, 0x00, pay))
        else:
            self.send(encode(NINEBOT, [0x20, 0x21], 0x64, 0x00, pay))
        self.say("ESC ", explain_dash_reply(pay, self.proto, self.g2), collapse="reply")

    def status(self):
        s = self.sc
        lv = getattr(self, "levers", (0, 0))
        return (f"{s.speed_kmh:5.1f} km/h  batt {s.battery:3d}%  mode {s.mode}  "
                f"light {'on ' if s.light else 'off'}  lock {'yes' if s.lock else 'no '}  "
                f"thr {lv[0]:3d} brk {lv[1]:3d}  frames "
                + " ".join(f"{c:02X}:{n}" for c, n in sorted(self.seen.items())))

    def dump_reads(self):
        if not self.reads:
            print("  no register reads seen yet")
            return
        print("  registers the app has asked for:")
        for (reg, n), cnt in sorted(self.reads.items(), key=lambda kv: -kv[1]):
            print(f"    0x{reg:02X}  {n:2d} bytes  x{cnt}")

    def run(self):
        print(f"listening on {self.ser.port} at {self.ser.baudrate}, "
              f"{self.proto}{' (G2)' if self.g2 else ''}. keys: q l k b m + - [ ] f s v")
        keys = KeyReader()
        try:
            while True:
                data = self.ser.read(256)
                if data:
                    for f in self.dec.feed(self.strip_echo(data)):
                        self.handle(f)
                else:
                    time.sleep(0.001)
                k = keys.get()
                if k:
                    if k == "q":
                        break
                    self.key(k)
                if time.time() - self.last_report > 1.0:
                    self.last_report = time.time()
                    print("\r" + self.status(), end="", flush=True)
        except KeyboardInterrupt:
            pass
        finally:
            keys.restore()
            self.ser.close()
            if self.log:
                self.log.close()
            print("\n" + self.status())
            self.dump_reads()

    def key(self, k):
        s = self.sc
        if k == "l":
            s.light = not s.light
        elif k == "k":
            s.lock = not s.lock
        elif k == "b":
            s.beeps = 2
        elif k == "m":
            s.mode = {1: 2, 2: 4, 4: 1}[s.mode]
        elif k == "+":
            s.speed_kmh = min(80, s.speed_kmh + 1)
        elif k == "-":
            s.speed_kmh = max(0, s.speed_kmh - 1)
        elif k == "]":
            s.battery = min(100, s.battery + 5)
        elif k == "[":
            s.battery = max(0, s.battery - 5)
        elif k == "f":
            s.fault = 0 if s.fault else 10
        elif k == "s":
            print()
            self.dump_reads()
        elif k == "v":
            self.verbose = not self.verbose
            print(f"\nverbose {'on' if self.verbose else 'off'}")


class KeyReader:
    """Non-blocking single keys, so the poll loop never stalls waiting on input."""

    def __init__(self):
        self.fd = None
        try:
            import termios, tty
            self.termios, self.fd = termios, sys.stdin.fileno()
            self.saved = termios.tcgetattr(self.fd)
            tty.setcbreak(self.fd)
        except Exception:
            self.fd = None

    def get(self):
        if self.fd is None:
            return None
        import select
        if select.select([sys.stdin], [], [], 0)[0]:
            return sys.stdin.read(1)
        return None

    def restore(self):
        if self.fd is not None:
            self.termios.tcsetattr(self.fd, self.termios.TCSADRAIN, self.saved)


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--port", required=True, help="the Flipper's USB-UART bridge port")
    p.add_argument("--baud", type=int, default=115200)
    p.add_argument("--proto", choices=[NINEBOT, XIAOMI], default=XIAOMI)
    p.add_argument("--g2", action="store_true", help="G2 reply, two extra payload bytes")
    p.add_argument("--serial", default="TEST0000000001")
    p.add_argument("--pin", default="123456")
    p.add_argument("--log", help="append every frame here")
    p.add_argument("--quiet-65", action="store_true",
                   help="Xiaomi: do not answer 0x65, only 0x64 - tests whether\nthe dash really needs a reply to every frame")
    p.add_argument("-v", "--verbose", action="store_true",
                   help="every frame on its own line, no folding of repeats")
    p.add_argument("-E", "--no-echo-filter", action="store_true",
                   help="wired with a transceiver, so we do not hear ourselves")
    Bench(p.parse_args()).run()


if __name__ == "__main__":
    main()
