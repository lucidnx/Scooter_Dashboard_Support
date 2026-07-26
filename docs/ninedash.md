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

NineDash has no headlight, secret-mode or speed-mode controls, so the package currently
borrows two controls that have no VESC meaning. This works, but the labels lie:

| your control | register | what it actually does |
|---|---|---|
| Recovery mode (KERS) | `0x7B` | **speed mode** — Weak = Eco, Medium = Drive, Strong = Sport |
| Direct power control | `0x76` | **secret modes** on/off |
| Cruise mode | `0x7C` | cruise control on/off |
| Back light | `0x7D` | tail light |
| Lock | `0x70` / `0x71` | lock / unlock |

All read back, so the switches show real state.

## Requests, most useful first

### 1. A slower polling mode

This is the big one, and it affects **stock scooters too** — it is not a VESC problem.

Measured on a G30 dash, riding, with and without NineDash connected:

```
app disconnected   lever frames 40/s   dash polls 10/s
app connected      lever frames 10/s   dash polls 10/s   app requests 15.6/s
```

The dash works to a fixed transmission budget. When it relays app traffic it takes the
slots from the `0x65`/`0x61` frames that carry throttle and brake, and the ESC's throttle
update interval goes from 51 ms to 104 ms — with a 90th percentile of 308 ms. On a stock
G30 that is masked by gentler throttle response; on a high-power VESC it is felt directly
as lag.

Four registers account for 12.8 of the 15.6 requests per second:

| register | rate | contents |
|---|---|---|
| BMS `0x33` | 3.4 Hz | current + voltage |
| ESC `0xB4` | 3.3 Hz | speed + battery |
| ESC `0xDA` | 3.2 Hz | unknown |
| BMS `0x35` | 2.9 Hz | temperatures |

Dropping to roughly 4 requests/s would return most of the lever bandwidth. A "reduce
polling while riding" option would help every user on every controller.

### 2. A headlight toggle on `0x7A`

`0x7A` is marked **Reserved** in the Ninebot ES protocol document, so it cannot collide
with stock semantics. Same shape as your Back light switch — `cmd 0x03`, one payload byte,
`0` off and non-zero on — and readable at the same address for the state.

The package already implements it, so it works the moment a control writes there.

**Please read the next section before adding it.**

### 3. Something in the app reacts to the headlight

On this setup, **changing the headlight state ends the BLE session**, within one dash cycle,
regardless of how it is triggered. Confirmed four ways:

- app writes `0x7B` mapped to the headlight → disconnect
- app writes `0x7D` mapped to the headlight → disconnect
- headlight toggled by the scooter's own button gesture, app untouched → disconnect
- headlight state never changes → 15 writes over 120 s, no disconnect

The dash itself is unaffected — no flicker, no reset — and the supply is a 3 A buck
converter with a capacitor, so it is not a brownout. The ESC stays healthy throughout: it
keeps answering the dash at 10/s and lever frames return to 40/s the moment the app drops.
The bus capture shows a completely clean exchange right up to the silence.

The only thing that changes on the wire is bit 2 of the dash frame payload (`20>21 cmd 0x64`),
which carries the headlight state. Does the app react to that bit? A stock G30 does not
behave this way, which is why we suspect something app-side rather than protocol-side.

Until this is understood, a headlight control would disconnect on first use.

### 4. Two smaller things

**`0xDA`** is polled at 3.2 Hz — your third most frequent register — and is undocumented in
every protocol reference we can find. The package returns zeros. What is it?

**BMS version** displays as `0067` no matter what we return. We answer `0x0700` at both ESC
`0x67` and BMS `0x17`; feeding `0x1234` and `0x5678` respectively changed nothing, so the
field appears not to come from either. `0x67` is the register number, which suggests the
value is being read one byte early.

**Switch state** is polled rarely — `0x7B` about every 30 s — so a change made on the
scooter takes up to half a minute to appear in the app. Not a bug, just worth knowing.
