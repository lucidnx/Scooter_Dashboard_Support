# Release notes

Text to paste into the GitHub release for each version. Not shipped in the package.

---

## v4.0

### Stock scooter apps work

**NineDash**, **m365 Tools** and the **official Segway Ninebot app** all connect over the
dashboard's own BLE module, show live data and control the scooter. No extra hardware and
no rewiring - the dash BLE module already puts their frames on the UART the package
listens to.

- **Live data**: speed, battery %, voltage, current, power, temperature, odometer, trip
  distance and time, average speed, estimated range, error and alarm codes.
- **Controls from the app**: lock/unlock, headlight, rear light, cruise control, speed mode,
  secret mode, buzzer and "find my scooter". Apps have no headlight, secret or speed-mode
  control of their own, so three of theirs are borrowed - **Recovery mode (KERS)** selects
  the speed mode, **Walk mode** toggles secret, **Direct power control** toggles the
  headlight.
- **Battery screen**: on Xiaomi the BMS is emulated, so the app's battery page is populated.
- **Shutdown from the app** switches the dashboard off, refused above walking pace.
- **App pairing PIN** - set your own 6-digit code in Setup. The package answers it, though
  none of the three apps ever asks: they treat a headlight state change as the pairing
  confirmation.
- **App support is off by default** and switchable in Setup - turn it on to use an app,
  leave it off for the sharpest throttle.
- Reports firmware 7.0.0 and a `VESC` + ten digit serial so app authors can detect a VESC
  and adapt. Protocol notes: [docs/ninedash.md](ninedash.md).

### Throttle response improved for everyone, app or no app

The dashboard sends lever data in three different frame types and the package only read
one of them. It now reads all three, which roughly halves the worst-case delay before a
throttle change is applied. App replies are also composed in advance and carried inside
the dash reply the controller was going to send anyway, so answering an app usually costs
no extra transmission at all.

How much an app costs depends on how often it polls, not how much data it asks for. Apps
that pace requests at least 100 ms apart cost nothing measurable. The full analysis, with
measurements from three apps on the same scooter, is in [docs/ninedash.md](ninedash.md).

### Ninebot Max G2 dashboard

Selectable as its own model. The handlebar **horn** sounds the dash buzzer, and **holding
the turn signal button** for three seconds toggles cruise control - the dash drives its own
turn signal lamps, so that button is free.

**Untested.** The frame layout was corrected against a capture of a stock G2 dashboard
talking to its own stock controller, but nobody has run this code on a G2 yet. Please
report back if you have one.

### Gestures work while riding

The speed above which gestures stop responding is yours to set - **Disable Gestures above**
in Setup. It defaults to 0.1 km/h, which means standstill only; raise it and modes, the
headlight and secret mode are all reachable at speed. **Lock** and **power off** are the
exceptions: they are never accepted with the wheel turning, whatever that is set to.

**Secret OFF** is a new gesture that can only ever *leave* secret mode, so it is a way out
that cannot turn it on by mistake, and it gained a *Locked* option of its own.

### Dashboard power control

**ADC1** or **ADC2** can switch the dashboard's supply through a MOSFET - 3.3 V while the
scooter is on, 0 V when you switch it off with the button or from the app. Because the pin
stays low until the script runs, the dashboard no longer shows error 10 while the VESC
boots. Off by default. The chosen pin is detached from the ADC app, so it stops working as
a lever input - the UI warns in red which lever that costs you.

### Rebuilt UI

- A large **speed dial** with a power sub-dial that scales to the active mode's watt limit
  times the number of controllers on the bus, so a dual reads correctly. Regen shown in its
  own colour.
- **Battery bar** that walks green to red as the pack drains and alternates between charge
  and estimated range, with **consumption** (Wh/km or Wh/mi) inside the dial.
- **Voltage, current, controller and motor temperature** as four cards; the temperatures
  flash red above the warning thresholds set in Setup.
- A function switched off in Setup **reads as off** on the Control tab - cruise and secret
  grey out and stop responding rather than sitting there coloured.
- Everything sits on **cards**, on every screen, with one grey for anything you can touch.
  Settings are grouped across **General**, **Modes** and **Setup**, reached through the
  settings badge instead of a tab bar.
- The Control page **scales to the window** and only scrolls once it genuinely cannot fit.

### Backup

**Export** puts every saved setting on the clipboard as a short block of text; **Import**
takes it back and fills in the fields for you to Save. VESC Tool gives a package no way to
write a file, so a backup travels as text rather than as a download. The model is not part
of it, since it belongs to the unit.

### Other changes

- **Software ADC is switchable per channel** - take throttle from the dashboard and leave
  brake on a lever wired to the ADC pin, or the other way round. **Light compensation** is
  only offered for the channels that actually come from the dashboard.
- **Cruise control's Setup switch is a master switch** - with it off, cruise cannot be
  turned on from the Control tab, an app or a gesture.
- **Idle display**: pick what the dashboard shows at rest - battery %, pack voltage,
  controller or motor temperature. Off by default now, for both normal and secret modes.
- **CAN slaves are told to stop** with the master, instead of holding their last command
  until it times out.
- **Secret watts** default to 1000 / 1500 / 2000. They were previously unlimited.
- **The model defaults to Slave**, so a fresh install drives nothing until you tell it which
  dashboard it has. **Reset** returns it to Slave as well.

### Upgrading

Install over the old package. Anything older than v4.0 is reconfigured from defaults, so
**check every tab and re-run the light compensation calibration** after updating. An
upgrade keeps the model it had; only an explicit Reset returns it to Slave.

---

## v3.0

- **Light compensation is now a real calibration.** The headlight sags the throttle/brake
  signal *non-linearly*, so a single offset was never enough - 3.0 fits an affine
  correction (offset + gain) with a guided wizard that measures it for you, light off vs
  on, at the same held lever position. Old flat-offset values cannot be converted and are
  reset on upgrade: **re-run the calibration after updating**.
- **Cruise control reworked.** It now only presses and releases the VESC's own cruise
  button - no speed logic of its own. Throttle or brake cancels it instantly and your live
  lever takes over in the same moment, and a new **min/max activation speed** window
  controls when it may engage. It no longer cancels on speed dips, which fixes random
  disengaging on rough roads and with traction control enabled.
- **Cruise moved to the Control tab** as a live toggle button.
- **Lever thresholds now come from VESC Tool.** The old *Min Throttle ADC* / *Min Brake ADC*
  fields are gone; gestures, brake light and cruise cancel all use your configured
  **ADC start voltage** instead, so there is one less thing to tune and it matches what the
  motor actually does.
- **Current %** is entered as a percentage and hard capped at 100%, and **Overmodulation**
  is floored at 1.0 - neither can be set to a value that overdrives the motor.
- **mph** now converts every speed-related settings field, not just the dashboard readout.
