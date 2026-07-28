# Notes for the NineDash developer

[VESC Scooter Support](https://github.com/lucidnx/vesc_scooter_support) lets a VESC
controller drive a stock Ninebot G30 or Xiaomi M365 dashboard. Since v4.0 it also answers
the app protocol, so NineDash works against it exactly as against a stock ESC.

Everything below comes from logic-level captures of the internal UART bus on a real G30
dash, not from guesswork. Frame counts and timings are measured.

## Detecting a VESC

Two independent markers, either is enough:

| register | value | notes |
|---|---|---|
| `0x10` serial | `VESC` + 10 digits, e.g. `VESC8437945242` | the digits come from the controller UUID, so each unit differs |
| `0x1A` firmware | `0x0700` → **7.0.0** | above every stock version, deliberately |

The serial is the more reliable one: a plain `startsWith("VESC")`. The version is easy to
read but ordering comparisons against it will misfire, since `7.0.0` is higher than any
stock release and every `version >= x` check passes.

## What a VESC cannot do

**Shutdown (`0x79`)** works, with one difference worth knowing. On a stock scooter the ESC
powers down the whole vehicle; on a VESC the dashboard is powered separately, so the
command switches the dashboard off exactly as the package's own power button and a long
press of the scooter button do. The controller stays live. Refused above walking pace.

**KERS (`0x7B`)** has no VESC equivalent — regenerative braking is configured in VESC Tool
and is not a three-level setting.

## Current control mapping

NineDash has no headlight, secret-mode or speed-mode controls, so the package borrows
three controls that have no VESC meaning. This works, but the labels lie:

| your control | register | what it actually does |
|---|---|---|
| Recovery mode (KERS) | `0x7B` | **speed mode** — Weak = Eco, Medium = Drive, Strong = Sport |
| Walk / pedestrian mode | `0x77` | **secret modes** on/off |
| Direct power control | `0x76` | **headlight** on/off |
| Cruise mode | `0x7C` | cruise control on/off |
| Back light | `0x7D` | tail light |
| Lock | `0x70` / `0x71` | lock / unlock |

All read back, so the switches show real state.

## The polling budget

**This is the important section.** It affects stock scooters too — it is not a VESC
problem, it is a property of the bus.

The dash and the ESC share a **single half-duplex wire**. Whenever the ESC transmits, its
receiver is switched off, and on VESC firmware it stays off slightly past the end of the
frame. Any lever frame that arrives in that window is lost. The dash also runs a fixed
transmission budget of about 10 ESC slots per second, and relaying app traffic takes those
slots from the `0x65`/`0x61` frames that carry throttle and brake.

So the cost of a poll is **one transmission**, not one byte. Big reads are cheap. Frequent
reads are expensive.

The package answers the app by packing the reply inside the dash reply it was going to send
anyway. That is free. But it can only do that if the request arrives before the dash's own
poll in that cycle — otherwise the reply needs a transmission of its own, and that is what
costs throttle response.

### Measured, three apps, same scooter, same firmware

| app | requests/s | shortest gap | ESC transmissions/s | worst lever gap |
|---|---|---|---|---|
| *no app connected* | — | — | **9.9** | — |
| Segway Ninebot (official) | 3.4 | 102 ms | **9.7** | **55 ms** |
| m365 Tools | 5.2 | 102 ms | **10.2** | 105 ms |
| NineDash | 10.5 – 11.7 | 50 ms | **14.7 – 15.4** | 104 ms |

The first two are free — the ESC transmits no more often than with no app at all, and the
rider feels nothing. NineDash adds about **5 extra transmissions per second**, roughly 50%
over baseline, and that is felt directly as throttle and brake lag on a high-power VESC.

It is not about data volume. m365 Tools moves **more** bytes than NineDash — 83 B/s against
71 B/s — in half the transactions, and is smooth. The official Segway app reads only small
2-byte registers, one at a time, and is smoother still. The single variable that separates
them is how often they transmit.

### Suggested limits

These come straight from what the two well-behaved apps already do:

- **≥ 100 ms between consecutive requests.** That is two dash cycles (a cycle is 51 ms).
  Both good apps sit at 102 ms minimum and never go below it. NineDash currently sits at
  50 ms — one request every single cycle.
- **One request in flight.** Send the next only after the previous reply arrives. The
  official Segway app is strictly request → reply → wait a cycle → next.
- **Never two requests inside one 51 ms cycle.** In the captures NineDash sent 55 of 673
  requests within 20 ms of the previous one. Each back-to-back pair forces a second reply
  in a cycle that only had room for one.
- **≤ 5 requests/s sustained.** This is the number that keeps total ESC transmissions at
  or under ~10/s, which is the baseline with no app at all.
- **Tolerate unanswered requests.** The package already drops bulk reads while the levers
  are active — 29–42% of m365 Tools' requests go unanswered and the user sees nothing
  wrong, because the app simply re-asks. Please do not treat a missing reply as an error
  or retry it immediately.

### Where NineDash's requests currently go

Four registers account for 12.8 of the 15.6 requests per second:

| register | rate | contents |
|---|---|---|
| BMS `0x33` | 3.4 Hz | current + voltage |
| ESC `0xB4` | 3.3 Hz | speed + battery |
| ESC `0xDA` | 3.2 Hz | unknown — see below |
| BMS `0x35` | 2.9 Hz | temperatures |

Two ways to get under the limits, both proven on this hardware:

**Batch them.** m365 Tools reads `0xB0` (28 B), `0x25` (48 B), `0x1A` (24 B), `0x72` (32 B)
and BMS `0x30` (24 B) as bulk blocks at about 1 Hz each and gets everything in 5.2
requests/s. The package answers all of these.

**Or just slow down.** The official Segway app keeps the same small single-register reads
NineDash uses and simply paces them at 104 ms, and it is the cleanest of the three. Pacing
alone is enough — batching is an optimisation on top.

A "reduce polling while riding" option would help every user on every controller.

## Other notes


### The headlight change is the pairing signal, and it disconnects you

This one is now measured rather than suspected.

**The Segway app's pairing confirmation is a headlight state change, not a button press.**
Its instruction says "press the button" because on a stock scooter that is what toggles the
headlight — but the light change is what it watches for. Confirmed two ways: pairing
completes when the light is toggled from the package's own UI with the button never
touched, and in the pairing capture the pairing reads follow the light change rather than
the button:

```
light byte  00 -> 01 at  8.85    serial reads at  9.16, 9.27, 9.83
light byte  01 -> 00 at 10.70    serial reads at 11.83, 11.98
button                4.79, 24.08, 25.05   (no light change, no pairing reads)
```

The dashboard does report the button separately — byte 4 of the `0x64`/`0x65` lever frames,
high for about 100 ms per press — but it is not what drives pairing.

**NineDash disconnects on that same signal.** In two captures the last app frame arrives one
dash cycle after the light byte changes:

```
11.955  3e>20 cmd 03 reg 7b 01     app writes the register mapped to the headlight
12.006  20>21 cmd 64  light 00 -> 01
12.110  last app frame, ever
```

The other capture is identical with the light going the other way. Five writes to `0x76` in
the same session did **not** disconnect it, because they did not change the light byte — so
it is the byte, not the write.

**And the link is fine.** m365 Tools, same scooter, same firmware, rode through five light
changes at 90.05, 96.21, 103.43, 111.45 and 117.07 s with no gap in its traffic at all. The
dashboard does not reset, the BLE module does not drop the link, and there is no reconnect
to miss. NineDash closes the connection itself.

Which is reasonable behaviour on a stock scooter: a pairing event invalidates the previous
session. The problem is that the signal cannot distinguish a pairing from someone switching
their headlight on, so on a VESC — where the headlight is used normally — it fires all the
time. A stock G30 does the same thing; there has just never been a reason to notice.

There is nothing the package can send to prevent it. The signal *is* the headlight state,
and it cannot stop reporting that without breaking the dashboard's light indicator. The
serial-read burst that follows a real pairing looks like a better discriminator.


### `0xDA` is the controller CPU id

Worth flagging because it is easy to mistake for telemetry. It sits past the end
of the register table most people work from, which stops at `0xCE` — but the
official *Ninebot ES Communication Protocol* document has it: `0xD0`–`0xD9` is a
reserved gap, and `0xDA`–`0xDF` are `NB_CPUID_A` … `NB_CPUID_F`, six read-only
U16s, default 0. Twelve bytes, which is exactly the width of an STM32 unique
device id.

All three apps read it as one 12 byte block, never a sub-range. What differs is
how hard they poll it:

| app | rate |
|---|---|
| Segway Ninebot (official) | 0.04 – 0.08 /s — two or three reads in a whole session |
| m365 Tools | 1.2 /s |
| NineDash | 2.2 /s |

It is a factory serial number. It cannot change while the scooter is running, and
the official app treats it accordingly — two or three reads in a whole session.
Polling it at 2.2 Hz is the easiest saving available to you: 3 of your 15.6
requests per second, most of the way to the budget above on its own. Read it once
at connect and cache it.

The package now answers with the VESC serial, packed two digits per byte so it
reads back as the serial rather than as an unrecognisable number — a controller
reporting `VESC6848843236` returns `684884323600000000000000`. It used to answer
twelve zeros, which is the documented default and which all three apps accepted
without complaint.

For reference, these are read and answered with zeros without complaint: ESC
`0xE4`, `0xE7`, `0x23`, `0x7F`, `0x69`, and BMS `0x1B`, `0x8B`. `0xBE` is
answered with the last alarm code.


### Two smaller things

**BMS version** displays as `0067` no matter what we return. We answer `0x0700` at both ESC
`0x67` and BMS `0x17`; feeding `0x1234` and `0x5678` respectively changed nothing, so the
field appears not to come from either. `0x67` is the register number, which suggests the
value is being read one byte early.

**Switch state** is polled rarely — `0x7B` about every 30 s — so a change made on the
scooter takes up to half a minute to appear in the app. Not a bug, just worth knowing.
