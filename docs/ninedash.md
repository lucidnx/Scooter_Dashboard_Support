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

**Shutdown (`0x79`)** is acknowledged and ignored. On a stock scooter the ESC powers down
the whole vehicle including the dash; on a VESC the dash is powered separately, so a
shutdown would cut the display and the BLE link while the controller stayed live. Please
hide or disable the power control when a VESC is detected.

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
| ESC `0xDA` | 3.2 Hz | unknown |
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

### A headlight toggle on `0x7A`

Beyond the borrowed `0x76` mapping above, `0x7A` is marked **Reserved** in the Ninebot ES
protocol document, so it is free for a properly labelled headlight switch. Same shape as
your Back light switch — `cmd 0x03`, one payload byte, `0` off and non-zero on — and
readable at the same address for the state. The package implements it already.

### Something in NineDash reacts to the headlight

On this setup, **changing the headlight state has been observed to end NineDash's BLE
session**, within one dash cycle, regardless of how it is triggered. Confirmed four ways:

- app writes `0x7B` mapped to the headlight → disconnect
- app writes `0x7D` mapped to the headlight → disconnect
- headlight toggled by the scooter's own button gesture, app untouched → disconnect
- headlight state never changes → 15 writes over 120 s, no disconnect

The dash itself is unaffected — no flicker, no reset — and the supply is a 3 A buck
converter with a capacitor, so it is not a brownout. The ESC stays healthy throughout: it
keeps answering the dash at 10/s and lever frames return to 40/s the moment the app drops.
The bus capture shows a completely clean exchange right up to the silence.

The only thing that changes on the wire is bit 2 of the dash frame payload (`20>21 cmd 0x64`),
which carries the headlight state. Does the app react to that bit?

**The official Segway app and m365 Tools do not disconnect** when the headlight is toggled
on the same scooter and the same firmware, which is what points at something app-side.

One caveat: all four observations above predate the timing work described earlier, when
replies were sometimes hundreds of milliseconds late — and NineDash was the app driving
the bus into that state, so a plain timeout has not been fully ruled out either. The
headlight now sits on `0x76` (Direct power control) and can be re-tested directly.

### Two smaller things

**`0xDA`** is polled at 3.2 Hz — your third most frequent register — and is undocumented in
every protocol reference we can find. The package returns zeros. What is it?

**BMS version** displays as `0067` no matter what we return. We answer `0x0700` at both ESC
`0x67` and BMS `0x17`; feeding `0x1234` and `0x5678` respectively changed nothing, so the
field appears not to come from either. `0x67` is the register number, which suggests the
value is being read one byte early.

**Switch state** is polled rarely — `0x7B` about every 30 s — so a change made on the
scooter takes up to half a minute to appear in the app. Not a bug, just worth knowing.
