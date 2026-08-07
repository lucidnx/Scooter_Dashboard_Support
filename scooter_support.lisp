(def software-adc true)  ; ADC1 / throttle from the dashboard
(def software-adc2 true) ; ADC2 / brake from the dashboard
; Decoded lever position counted as a touch. get-adc-decoded is mapped by the
; ADC app itself (Start/End voltage + hysteresis, after our light correction),
; so >0 already means "past the configured start voltage" - this is just an
; epsilon against float noise, not a user-facing deadband.
(def adc-touch 0.02)
(def temp-warning-motor 80) ; temperature warning for motor in degree celsius
(def temp-warning-fet 80) ; temperature warning for fet in degree celsius
(def show-batt-in-idle false) ; show idle-display instead of speed at idle, normal modes
(def idle-display 0) ; 0 battery %, 1 battery V, 2 controller C, 3 motor C
(def last-alarm-code 0) ; the code the app reads back after an alarm has cleared
(def show-batt-idle-secret false) ; same but in secret modes
(def min-speed 1) ; minimum speed in km/h to enable throttle and brake
(def button-safety-speed (/ 0.1 3.6)) ; disabling button above 0.1 km/h (due to safety reasons)

; Alarm parameters (foc-play-tone)
(def alarm-tone true)
(def alarm-speed-threshold 0.5) ; speed in km/h to trigger alarm
(def alarm-gyro-threshold 10) ; change in degree/s to trigger alarm
(def alarm-voltage 24) ; voltage for alarm sound, higher = louder
;(def alarm-frequency) ; todo: not supported yet, lower = louder, current: 2=4000, 3=7000, 6=2000

; Speed modes (km/h, watts, current scale)
(def eco-speed (/ 7 3.6))
(def eco-current 0.6)
(def eco-watts 400)
(def eco-fw 0)
(def drive-speed (/ 17 3.6))
(def drive-current 0.7)
(def drive-watts 500)
(def drive-fw 0)
(def sport-speed (/ 22 3.6))
(def sport-current 1.0)
(def sport-watts 700)
(def sport-fw 0)

; Secret speed modes. To enable, press the button 2 times while holding break and throttle at the same time.
(def secret-enabled true)
(def secret-eco-speed (/ 27 3.6))
(def secret-eco-current 1.0)
(def secret-eco-watts 1000)
(def secret-eco-fw 0)
(def secret-drive-speed (/ 47 3.6))
(def secret-drive-current 1.0)
(def secret-drive-watts 1500)
(def secret-drive-fw 0)
(def secret-sport-speed (/ 1000 3.6)) ; 1000 km/h easy
(def secret-sport-current 1.0)
(def secret-sport-watts 2000)
(def secret-sport-fw 10)

; Per-parameter apply toggles - a disabled parameter is never written to the motor config
(def apply-speed true)
(def apply-current true)
(def apply-watts true)
(def apply-fw true)

; Secret modes gate each parameter separately
(def secret-apply-speed true)
(def secret-apply-current true)
(def secret-apply-watts true)
(def secret-apply-fw true)

; Button gestures (combo: 0=brake+throttle, 1=brake only, 2=throttle only, 3=none)
; presses = 0 means no button press needed, the gesture fires from levers alone
(def secret-presses 1)
(def secret-off-presses 3) ; a gesture that only ever leaves secret, never enters
(def secret-off-combo 3)
(def secret-off-requires-lock false)
(def secret-combo 0)
(def secret-requires-lock false) ; secret gesture only works while locked
(def secret-exit-on-lock false) ; locking drops back to normal modes
(def lock-presses 2)
(def lock-combo 1)
(def mode-presses 2)
(def mode-combo 3)
(def mode-requires-lock false)
(def light-presses 1)
(def light-combo 3)
(def light-requires-lock false)
(def light-on-boot false)
; Light compensation: reconstructs the light-off reading from a light-on
; reading via corrected = (raw - offset) / gain. Calibrated with the Sample
; buttons in Setup; gain=1/offset=0 is a no-op (uncalibrated default).
(def light-offset-thr 0.0)
(def light-gain-thr 1.0)
(def light-offset-brk 0.0)
(def light-gain-brk 1.0)
(def boot-mode 1) ; speed mode applied at boot (1=drive, 2=eco, 4=sport)

; Display / battery
(def use-mph false) ; dash shows mph instead of km/h
(def bms-soc-enable false) ; battery % from a VESC BMS when one reports

; BLE pairing code reported to third-party apps, 6 digits
(def app-pin 0)

; Rear light on the servo/PPM pin via PWM (MOSFET driver)
(def rear-light-enable false)
(def auto-taillight false) ; taillight on from power on
(def brake-light-mode 1) ; 0=off, 1=on while braking, 2=blink while braking
(def taillight-brightness 0.4) ; tail light duty, 0-1
(def slip-erpm 1200.0) ; wheel spread that counts as slip, from VESC's own at boot
(def slip-hold 2.0) ; seconds the slip lamp stays on after the last one
(def slip-time 0)

; Overmodulation factor per mode (max recommended 1.15)
(def eco-om 1.0)
(def drive-om 1.0)
(def sport-om 1.0)
(def secret-eco-om 1.0)
(def secret-drive-om 1.0)
(def secret-sport-om 1.0)
(def apply-om false)
(def secret-apply-om false)

; Cruise control (experimental)
(def cruise-allow false) ; master switch - without it nothing can turn cruise on
(def cruise-enabled false)
(def cruise-delay 5.0) ; seconds of steady speed to activate
(def cruise-deviation 1.0) ; km/h window counted as "steady"
(def cruise-min-speed 5.0) ; km/h - cruise can only activate at or above this
(def cruise-max-speed 35.0) ; km/h - cruise can only activate at or below this

; -> Code starts here (DO NOT CHANGE ANYTHING BELOW THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING)

; Load VESC CAN code server - const block so the library code lives in flash, not heap
@const-start
(import "pkg@://vesc_packages/lib_code_server/code_server.vescpkg" 'code-server)
(read-eval-program code-server)
@const-end

; Model (0=G30, 1=M365/1S/PRO2, 2=Slave)
(def model 2)

; Protocol offsets, set per model in main
(def tx-base 7) ; first dash field in tx-frame
(def rx-hdr 0x5aa5) ; frame header, how far past len the checksum reaches, the
(def rx-pre 4)      ; extra address byte Ninebot has, and what its len does not
(def rx-o 1)        ; count that Xiaomi's does
(def rx-sub 0)
(def tx-hdr-sum 0) ; fixed part of the dash checksum, summed once in main
(def thr-idx 5) ; throttle byte in uart-buf
(def brk-idx 6) ; brake byte in uart-buf

; Button handling
(def press-time (systime))
(def presses 0)

; Mode states
(def off false)
(def lock false)
(def speedmode 4)
(def light false)
(def unlock false)

; alarm states
(def alarm 0)
(def alarm-time (systime))

; sound feedback
(def feedback 0)
(def beep-time (systime)) ; when the last beep byte actually went out

; dash link watchdog: last time a throttle frame was received
(def last-rx (systime))
(def rx-gap-avg 0.05) ; running average gap between lever frames

; lever-only gesture state (gestures configured with 0 presses)
; both levers, sampled once a pass in button-logic
(def lev-thr 0.0)
(def lev-brk 0.0)

(def lever-state 0)
(def lever-since (systime))
(def lever-armed true)

; which ids are on the bus, not what they report - canget-* read the status
; frames the slaves broadcast by themselves, so every reading stays live while
; the list behind it is built once instead of four times a pass
(def can-ids '())
(def can-ids-time 0)

; the unit whose gyro answers: -1 for this one, otherwise a can id. Each remote
; probe is a blocking round trip holding the code server's mutex, so the answer
; is kept and only looked for again every ten seconds.
(def gyro-src -1)
(def gyro-probe 0)

; cached telemetry - refreshed at ~16 Hz by the button thread so the
; per-frame dash reply doesn't run CAN queries and allocations itself
(def cur-speed-kmh 0.0)
(def cur-batt 0.0)
(def cur-vin 0.0)
(def cur-amps 0.0)
(def cur-range 0.0)
(def cur-trip 0)
(def cur-odo 0)
(def cur-runtime 0)
(def cur-fet 0.0)
(def cur-mot 0.0)
(def cur-fet-max 0.0) ; hottest across every unit on the bus
(def cur-mot-max 0.0)
(def warn-temp false) ; either of them over its warning level
(def cur-maxkmh 0.0)
(def cur-cells 10)
(def cur-cap 0)


; BMS state
(def bms-active false)
(def bms-warn false)

; app protocol state - buffers are built in main, they must stay out of flash
(def app-boot-time (systime))
(def app-cache-time (systime))
(def app-slow-time (systime))
(def app-slow-step 0)
(def cur-wh-tot 0.0)
(def b0-wanted false)  ; the 52 byte block is 26 lookups - only rebuild it when asked
(def app-dst 0x3e)     ; address the app last asked from
(def g2-aux 0x40)      ; last G2 horn / turn signal byte, for edge detection
; Control writes must not do slow work in the reader thread: a mode change
; means conf-set plus CAN round trips with retries, and persisting a setting
; means a flash write - either stalls the lever frames for as long as it takes,
; and the app repeats every write several times. Writes only record what
; changed; the button loop carries it out.
(def app-todo 0) ; 1 cruise, 2 taillight, 4 buzzer, 8 pin, 16 apply-mode, 32 lock, 64 power off
; A reply of 20 bytes or more holds the line long enough to lose a lever frame,
; and the cell voltage read alone is over one a second. Those are diagnostics,
; not riding data, so they wait until the levers are released.
(def levers-active false)
; worst gap between lever frames as we actually process them, in ms. The wire
; says they arrive every 30 ms; if this is much larger we are being starved.
; uart-write switches the receiver off and hands the job of switching it back on
; to a shared worker thread without waiting for it, so the deaf window lasts
; until that worker runs - measured at up to 470 ms while the bus was carrying
; frames every 30 ms. Transmitting again before it recovers extends the window.
; So an app answer rides along inside the next dash answer: framing is by header
; and length, not by transmission, and this halves the number of writes.
(def app-pend false)
(def power-pin 0) ; dashboard supply switch: 0 off, 1 ADC1, 2 ADC2
(def dash-power-held false) ; the pin symbol once it is ours, false otherwise
(def pend-dev 0)
(def app-pend2 false)
(def pend2-dev 0)
(def pend2-reg 0)
(def pend2-n 0)
(def pend-reg 0)
(def pend-n 0)

; Lever detection for the deferral above works off the raw dash bytes against a
; learned resting value, not the corrected voltage against the ADC start point -
; the correction shifts with the headlight and the start point can sit below the
; resting reading, either of which leaves this stuck on or stuck off.
(def thr-rest 255)
(def brk-rest 255)
; In half duplex the firmware switches the receiver off for the whole of every
; uart-write and leaves it off a millisecond or two afterwards, so every
; transmission is a window in which the dash's lever frames are simply lost.
; Answering every single 0x64 costs about a sixth of all receive time and the
; display does not need that rate. 0 restores a reply to every poll.
(def dash-tx-iv 0.05)
(def dash-tx-time (systime))
; Answer third-party apps at all. Transmitting makes the receiver deaf for as
; long as the firmware's worker takes to switch it back on, so a connected app
; costs lever responsiveness - turn this off to ride with the sharpest throttle.
(def app-enable false)
(def cur-cell-mv 0) ; one division, not fifteen per cell read
(def cur-soh 100)   ; pack health, from the BMS when there is one

; rear light state
(def pwm-started false)
(def blink-state false)
(def blink-since (systime))

; cruise control state
(def cruising false)
(def cruise-thr-released false)
(def cruise-blocked false)
(def cruise-ref 0.0)
(def cruise-since (systime))
(def cruise-shown-time (systime)) ; activation time - drives the 3s dash "C5"
(def cruise-v1-start 0.3) ; ADC1 start voltage, read from the app config at activation
(def thr-corr-v 0.0) ; corrected lever voltage before the capture-assist mask
(def dash-thr-raw 0) ; raw dash throttle byte, tracked in adc-input
(def dash-brk-raw 0) ; raw dash brake byte, tracked in adc-input

; Light-compensation calibration wizard state.
; Two lever positions per channel (released, then full press). At EACH held
; position the light is toggled off/on/off/on and sampled every time, so the
; light-off and light-on readings are a paired measurement taken at the very
; same lever position - the lever is never re-positioned between an off and
; its matching on, which was the dominant error in the old 4-step version.
; Alternating several times also averages out slow drift (pack sag, thermal),
; and a settle window after each toggle skips the headlight inrush transient.
(def calib-stage 'idle) ; 'idle / 'prep / 'settle / 'measure / 'release
(def calib-phase 0) ; 0 = lever released, 1 = lever at full press
(def calib-slot 0) ; index into the off/on/off/on toggle sequence
(def calib-slots 4) ; toggles per position - even, so off and on get equal weight
(def calib-channel 'thr) ; 'thr or 'brk - which raw signal to sample
(def calib-since (systime))
(def calib-prep-duration 3.0) ; time to get into position before sampling
(def calib-settle-duration 0.5) ; after a light toggle, before sampling
(def calib-sample-duration 0.5) ; averaging window per light state
(def calib-release-duration 3.0) ; grace window after the last step to let go
                                  ; of the lever before real output resumes
(def calib-off-sum 0.0) (def calib-off-cnt 0)
(def calib-on-sum 0.0) (def calib-on-cnt 0)
(def calib-off-rel 0.0) (def calib-on-rel 0.0) ; released-position averages

@const-start

(def settings-version 411i32)

; Persistent settings: (label . (eeprom-offset type))
; Every setting in one place: name, eeprom slot, type, default. read-setting
; and write-setting look up the first two, restore-defaults writes the last,
; so a new setting is one line here and nowhere else.
(def setting-defs '(
    (ver-code 0 i 0)
    (software-adc 1 b true)
    (software-adc2 87 b true)
    (temp-warning-motor 4 f 80.0)
    (temp-warning-fet 5 f 80.0)
    (show-batt-in-idle 6 b false)
    (min-speed-kmh 7 f 1.0)
    (alarm-tone 8 b true)
    (alarm-speed-threshold 9 f 0.5)
    (alarm-gyro-threshold 10 f 10.0)
    (alarm-voltage 11 f 24.0)
    (eco-speed-kmh 12 f 7.0)
    (eco-current 13 f 0.6)
    (eco-watts 14 f 400.0)
    (eco-fw 15 f 0.0)
    (drive-speed-kmh 16 f 17.0)
    (drive-current 17 f 0.7)
    (drive-watts 18 f 500.0)
    (drive-fw 19 f 0.0)
    (sport-speed-kmh 20 f 22.0)
    (sport-current 21 f 1.0)
    (sport-watts 22 f 700.0)
    (sport-fw 23 f 0.0)
    (secret-enabled 24 b true)
    (secret-eco-speed-kmh 25 f 27.0)
    (secret-eco-current 26 f 1.0)
    (secret-eco-watts 27 f 1000.0)
    (secret-eco-fw 28 f 0.0)
    (secret-drive-speed-kmh 29 f 47.0)
    (secret-drive-current 30 f 1.0)
    (secret-drive-watts 31 f 1500.0)
    (secret-drive-fw 32 f 0.0)
    (secret-sport-speed-kmh 33 f 1000.0)
    (secret-sport-current 34 f 1.0)
    (secret-sport-watts 35 f 2000.0)
    (secret-sport-fw 36 f 10.0)
    (model 37 i 2)
    (apply-speed 38 b true)
    (apply-current 39 b true)
    (apply-watts 40 b true)
    (apply-fw 41 b true)
    (secret-presses 42 i 1)
    (secret-off-presses 89 i 3)
    (secret-off-combo 90 i 3)
    (secret-off-requires-lock 91 b false)
    (idle-display 92 i 0)
    (secret-combo 43 i 0)
    (secret-requires-lock 44 b false)
    (lock-presses 45 i 2)
    (lock-combo 46 i 1)
    (secret-apply-fw 47 b true)
    (secret-apply-speed 48 b true)
    (secret-apply-current 49 b true)
    (secret-apply-watts 50 b true)
    (mode-presses 51 i 2)
    (mode-combo 52 i 3)
    (light-presses 53 i 1)
    (light-combo 54 i 3)
    (light-on-boot 55 b false)
    (button-speed-kmh 56 f 0.1)
    (boot-mode 57 i 1)
    (show-batt-idle-secret 58 b false)
    (mode-requires-lock 59 b false)
    (light-requires-lock 60 b false)
    (use-mph 61 b false)
    (rear-light-enable 62 b false)
    (auto-taillight 63 b false)
    (brake-light-mode 64 i 1)
    (eco-om 65 f 1.0)
    (drive-om 66 f 1.0)
    (sport-om 67 f 1.0)
    (secret-eco-om 68 f 1.0)
    (secret-drive-om 69 f 1.0)
    (secret-sport-om 70 f 1.0)
    (apply-om 71 b false)
    (secret-apply-om 72 b false)
    (bms-soc-enable 73 b false)
    (cruise-enabled 74 b false)
    (cruise-delay 75 f 5.0)
    (cruise-deviation 76 f 1.0)
    (cruise-min-speed 82 f 5.0)
    (cruise-max-speed 83 f 35.0)
    (secret-exit-on-lock 77 b false)
    (light-offset-thr 78 f 0.0)
    (light-offset-brk 79 f 0.0)
    (light-gain-thr 80 f 1.0)
    (light-gain-brk 81 f 1.0)
    (app-pin 84 i 0)
    (taillight-brightness 94 f 0.4)
    (app-enable 85 b false)
    (power-pin 88 i 0)
    (cruise-allow 93 b false)
))

; Each group is one line to and from the UI: the name it travels under, then its
; settings in the order the UI packs and unpacks them. send-settings builds the
; line from this, save-group writes one back, and load-settings walks it - so a
; new setting is one name here and one row above, and nowhere else.
; cruise-enabled is deliberately absent: it is the Control tab switch, written
; when it is flipped rather than when settings are saved.
(def setting-groups '(
    (misc light-on-boot button-speed-kmh use-mph bms-soc-enable secret-exit-on-lock
        light-offset-thr light-gain-thr light-offset-brk light-gain-brk app-pin power-pin)
    (general software-adc software-adc2 show-batt-in-idle show-batt-idle-secret
        min-speed-kmh app-enable idle-display)
    (temps temp-warning-motor temp-warning-fet)
    (modes eco-speed-kmh eco-current eco-watts eco-fw
        drive-speed-kmh drive-current drive-watts drive-fw
        sport-speed-kmh sport-current sport-watts sport-fw
        boot-mode eco-om drive-om sport-om)
    (secret secret-enabled
        secret-eco-speed-kmh secret-eco-current secret-eco-watts secret-eco-fw
        secret-drive-speed-kmh secret-drive-current secret-drive-watts secret-drive-fw
        secret-sport-speed-kmh secret-sport-current secret-sport-watts secret-sport-fw
        secret-eco-om secret-drive-om secret-sport-om)
    (apply apply-speed apply-current apply-watts apply-fw apply-om
        secret-apply-speed secret-apply-current secret-apply-watts secret-apply-fw
        secret-apply-om)
    (gesture secret-presses secret-combo secret-requires-lock
        lock-presses lock-combo
        mode-presses mode-combo mode-requires-lock
        light-presses light-combo light-requires-lock
        secret-off-presses secret-off-combo secret-off-requires-lock)
    (rear rear-light-enable auto-taillight brake-light-mode taillight-brightness)
    (cruise cruise-allow cruise-delay cruise-deviation cruise-min-speed cruise-max-speed)
    (alarm alarm-tone alarm-speed-threshold alarm-gyro-threshold alarm-voltage)
))

; stored in km/h, kept at runtime in m/s or under another name - load-settings
; converts these by hand instead of copying them straight across
(def speed-settings '(min-speed-kmh button-speed-kmh eco-speed-kmh drive-speed-kmh
    sport-speed-kmh secret-eco-speed-kmh secret-drive-speed-kmh secret-sport-speed-kmh))

(def last-button-state false)

; assoc walks the table, so it is asked once and the slot and type read off the
; one answer - a settings load is ninety of these
(defun read-setting (name)
    {
        (var d (assoc setting-defs name))
        (var addr (first d))
        (cond
            ; a slot that was never written reads back nil, and every caller
            ; wants that nil so it can fall back to the default. The bool
            ; conversion used to swallow it and hand back a value either way.
            ((eq (second d) 'f) (eeprom-read-f addr))
            ((eq (second d) 'b) (let ((v (eeprom-read-i addr)))
                                     (if (eq v nil) nil (!= v 0))))
            (t (eeprom-read-i addr))
        )
    }
)

; A write waits for the motor to release, locks interrupts, reconfigures the
; watchdog and tells the ADC app to ignore its input for five seconds - all of
; it before the firmware compares the value and, if it has not changed, writes
; nothing after all. So the comparison happens here instead, where it can skip
; the whole thing: a save that changed two fields costs two writes, not ninety.
; What is left still yields, because a real run of them should not hold the rest
; of the system off.
(defun write-setting (name val)
    {
        (var d (assoc setting-defs name))
        (var addr (first d))
        (var ty (second d))
        (var new (if (eq ty 'b) (if val 1 0) val))
        (var cur (if (eq ty 'f) (eeprom-read-f addr) (eeprom-read-i addr)))
        (if (or (eq cur nil) (!= cur new)) ; nil is a slot never written
            {
                (if (eq ty 'f) (eeprom-store-f addr new) (eeprom-store-i addr new))
                (sleep 0.01)
            }
        )
    }
)

(defun valid-model (m) ; eeprom reads nil when never written
    (and (not (eq m nil)) (>= m 0) (<= m 3))
)

(defun restore-defaults (keep-model)
    {
        (var cur-model (read-setting 'model))
        ; the version first: a restore cut short by a reset cannot come back and
        ; repeat itself
        (write-setting 'ver-code settings-version)
        (write-setting 'model (if (and keep-model (valid-model cur-model)) cur-model 2))
        (loopforeach s setting-defs
            (let ((n (ix s 0)))
                (if (not (or (eq n 'model) (eq n 'ver-code)))
                    (write-setting n (ix s 3)))))
    }
)

(defun load-settings ()
    {
        ; A version that does not match is reconfigured from defaults. The script
        ; carries no migrations, so every release starts from a known set rather
        ; than from whatever an older one happened to leave behind.
        (if (not-eq (read-setting 'ver-code) settings-version) (restore-defaults true))

        ; Every setting whose runtime variable carries the same name, straight off
        ; the group table. The ones below are the exceptions: stored in km/h and
        ; kept in m/s, or under a different name.
        (loopforeach g setting-groups
            (loopforeach n (cdr g)
                (if (not (member n speed-settings))
                    (set n (let ((v (read-setting n))) (if (eq v nil) (eval n) v))))))
        ; the Control tab switch is persisted on its own, outside any group
        (set 'cruise-enabled (let ((v (read-setting 'cruise-enabled))) (if (eq v nil) cruise-enabled v)))
        ; these divide, so an unwritten slot has to come back as its default and
        ; not as nil - setting-def is what guarantees that
        (set 'min-speed (setting-def 'min-speed-kmh))
        (set 'eco-speed (/ (setting-def 'eco-speed-kmh) 3.6))
        (set 'drive-speed (/ (setting-def 'drive-speed-kmh) 3.6))
        (set 'sport-speed (/ (setting-def 'sport-speed-kmh) 3.6))
        (set 'secret-eco-speed (/ (setting-def 'secret-eco-speed-kmh) 3.6))
        (set 'secret-drive-speed (/ (setting-def 'secret-drive-speed-kmh) 3.6))
        (set 'secret-sport-speed (/ (setting-def 'secret-sport-speed-kmh) 3.6))
        (set 'button-safety-speed (/ (setting-def 'button-speed-kmh) 3.6))
        ; adc-input divides by these every lever frame, so a zero from a bad save
        ; or a corrupt cell must never reach it
        (if (< light-gain-thr 0.05) (set 'light-gain-thr 1.0))
        (if (< light-gain-brk 0.05) (set 'light-gain-brk 1.0))

        (var m (read-setting 'model))
        (if (not (valid-model m)) { ; never stored, or out of range - Slave drives nothing
            (setq m 2)
            (write-setting 'model m)
        })
        (set 'model m)
    }
)

; 1 detaches both channels, 2 only the throttle, 3 only the brake - so each
; lever can come from the dashboard or from a lever wired to the pin
(defun apply-software-adc ()
    (let ((d1 (or software-adc (= power-pin 1)))   ; a pin driving the supply must
          (d2 (or software-adc2 (= power-pin 2)))) ; never be read as a lever
        {
            ; mode 3 detaches the levers and the buttons, mode 2 only the buttons.
            ; Cruise presses the ADC app's own cruise button, so that has to stay
            ; ours even when both levers come straight from their pins.
            (let ((d (cond ((and d1 d2) 1) (d1 2) (d2 3) (t 0))))
                (if (= d 0)
                    (app-adc-detach 2 1)
                    (app-adc-detach 3 d)
                )
            )
            ; a channel we detached but do not feed would otherwise keep the last
            ; value the dashboard put there
            (if (and d1 (not software-adc)) (app-adc-override 0 0))
            (if (and d2 (not software-adc2)) (app-adc-override 1 0))
            ; the calibration sequencer only runs on dashboard lever frames, so a
            ; run left open when both channels are switched off would never finish
            (if (and (not software-adc) (not software-adc2) (not (eq calib-stage 'idle))) {
                (set 'calib-stage 'idle)
                (send-data "calib-aborted")
            })
        }
    )
)

; ADC2 switches the dashboard's supply: high while the scooter is on, low when
; it is off. Only ever driven with software ADC on, where the ADC app replaces
; both pin readings with ours - without it ADC2 is the brake input, and a driven
; pin would read as brake. The level is written before the pin becomes an output
; so claiming it cannot glitch the supply, and the mode is only touched when the
; setting changes, never on an ordinary save.
(defun apply-dash-power ()
    (let ((pin (if (= power-pin 1) 'pin-adc1 'pin-adc2)))
        (if (> power-pin 0)
            (if (not (eq dash-power-held pin)) {
                (if dash-power-held (gpio-configure dash-power-held 'pin-mode-analog))
                (gpio-write pin (if off 0 1))
                (gpio-configure pin 'pin-mode-out)
                (set 'dash-power-held pin)
            })
            (if dash-power-held {
                (gpio-configure dash-power-held 'pin-mode-analog)
                (set 'dash-power-held false)
            })
        )
    )
)

(defun apply-runtime-settings ()
    {
        (load-settings)
        ; the ADC app fades the motor out between 60 ERPM of wheel spread and its
        ; own limit, so light the lamp once it has taken away nearly half
        (trap (let ((v (* 0.4 (conf-get 'adc-tc-max-diff)))) (if (> v 60) (setq slip-erpm v))))
        (if (!= model 2) { ; slave must not push conf to the master
            (apply-software-adc)
            (apply-dash-power)
            (apply-mode)
            (if rear-light-enable
                (if (not pwm-started) {
                    (pwm-start 200 0)
                    (set 'pwm-started true)
                })
                (if pwm-started (pwm-set-duty 0.0))
            )
        })
    }
)

; One writer for every settings group. The UI names the group and sends its
; values in the order setting-groups lists them, so the names live in one place
; instead of once per group here and once more in send-settings.
(defun save-group (g vals)
    {
        (var i 0)
        (loopforeach n (assoc setting-groups g)
            {
                (write-setting n (ix vals i))
                (setq i (+ i 1))
            }
        )
    }
)


; UI restarts lisp after "model-ok" so the new model takes effect
(defun save-model (m)
    {
        (write-setting 'model (if (valid-model m) m 2))
        (send-data "model-ok")
    }
)

(defun finish-settings-save ()
    {
        (apply-runtime-settings)
        (send-settings)
        (send-data "ok")
    }
)

(defun restore-settings-ui ()
    {
        (restore-defaults false) ; back to Slave, like a fresh install
        (apply-runtime-settings)
        (send-data "reset-ok") ; the model only takes effect on a restart
    }
)

; Remote controls for the UI Control tab. They reuse the gesture actions so
; all side effects stay identical; lock only reacts at standstill.
(defun ctrl-lock (on)
    (if (and (not (eq on lock)) (<= (abs (get-speed)) 1.0))
        (toggle-lock)
    )
)

(defun ctrl-light (on)
    (set 'light on) ; allowed while locked too, like secret/mode from the app
)

(defun ctrl-mode (m)
    (if (or (= m 1) (= m 2) (= m 4)) {
        (set 'speedmode m)
        (apply-mode)
    })
)

(defun ctrl-secret (on)
    (if (and secret-enabled (not (eq on unlock)))
        (toggle-secret)
    )
)

; Enable/disable the cruise feature live from the Control tab. Persisted so it
; survives a reboot, and cancels any active hold when switched off.
(defun ctrl-cruise (on)
    {
        (set 'cruise-enabled (and on cruise-allow))
        (write-setting 'cruise-enabled cruise-enabled)
        (if (not cruise-enabled) (cruise-cancel))
    }
)

(defun ctrl-power (on)
    (if on
        (if off {
            (set 'off false)
            (set 'feedback 1)
            (set 'unlock false)
            (apply-mode)
            (stats-reset)
        })
        (if (and (not off) (not lock) (<= (abs (get-speed)) 1.0)) {
            (set 'feedback 1)
            (set 'unlock false)
            (apply-mode)
            (set 'off true)
        })
    )
)

; Polled several times a second while the Control tab is open, so it reads what
; the feature loop already sampled instead of asking the firmware again. Only the
; consumption figure is still live: it is three cheap reads, and it is the one
; number here that answers to the throttle.
(defun send-state ()
    (let ((whkm (send-state-whkm)))
        (send-data (str-merge
            "state "
            (if off "true " "false ")
            (if lock "true " "false ")
            (if light "true " "false ")
            (if unlock "true " "false ")
            (str-from-n speedmode "%d ")
            (str-from-n cur-batt "%.0f ")
            (str-from-n cur-vin "%.1f ")
            (str-from-n (abs cur-speed-kmh) "%.1f ")
            (str-from-n (* cur-vin cur-amps) "%.0f ")
            (str-from-n whkm "%.1f ")
            (str-from-n cur-range "%.1f ")
            (str-from-n cur-amps "%.1f ")
            (str-from-n (send-state-maxkmh) "%.0f ")
            (if cruising "true " "false ")
            (if cruise-enabled "true " "false ")
            (if cruise-allow "true " "false ")
            (if img-ok "true " "false ")
            (str-from-n cur-fet-max "%.0f ")
            (str-from-n cur-mot-max "%.0f ")
            (if secret-enabled "true " "false ")
            (str-from-n (+ 1 (length (can-devs))) "%d ")
            (str-from-n (get-fault) "%d ")
            (str-from-n (wheel-slip) "%d")
        ))
    )
)

; configured max speed of the active mode in km/h - the speed bar scales to it
(defun send-state-maxkmh ()
    (* 3.6 (if unlock
        (cond ((= speedmode 1) secret-drive-speed) ((= speedmode 2) secret-eco-speed) (t secret-sport-speed))
        (cond ((= speedmode 1) drive-speed) ((= speedmode 2) eco-speed) (t sport-speed))
    ))
)

; setup-* values are the combined figures across all CAN VESCs, computed in
; firmware - no need to sum the units by hand
(defun send-state-whkm () {
        ; matches VESC Tool: (wh - wh_chg) / abs tacho distance, combined values
        (var dist-km (/ (get-dist-abs) 1000.0))
        (if (> dist-km 0.05)
            (/ (- (setup-wh) (setup-wh-chg)) dist-km)
            0.0
        )
})

; cur-wh-tot is the usable pack the way mc_interface_get_battery_level counts it
; - Li-ion assumed, 0.85 usable at 3.7 V a cell, as VESC Tool does. get-batt
; already carries the non-linear discharge curve, so this reproduces its estimate.
(defun send-state-range () {
        (var whkm (send-state-whkm))
        (if (> whkm 0.1)
            (/ (* (get-batt) cur-wh-tot) whkm) ; VESC Tool: wh_batt_left / wh_km
            0.0
        )
})

; One setting as the UI reads it back. The type in setting-defs picks the shape,
; so no group needs to carry a format string of its own - the UI parses every
; number with parseFloat either way.
; the stored value, or the table default when the slot has never been written -
; which is what every caller wants, and what a bare read-setting cannot give the
; ones below that divide by it
(defun setting-def (n)
    (let ((v (read-setting n))) (if (eq v nil) (ix (assoc setting-defs n) 2) v))
)

(defun setting-str (n)
    (let ((d (assoc setting-defs n)) (v (setting-def n)))
        {
            (cond
                ((eq (second d) 'b) (if v "true" "false"))
                ((eq (second d) 'f) (str-from-n v "%.3f"))
                (t (str-from-n v "%d"))
            )
        }
    )
)

; misc leads, as it always has: it carries the mph switch, and every speed in the
; groups after it is rendered for whichever unit that sets.
(defun send-settings ()
    {
        (send-data (str-merge "model " (setting-str 'model)))
        (sleep 0.05)
        (loopforeach g setting-groups
            {
                (var line (to-str (first g)))
                (loopforeach n (cdr g)
                    (setq line (str-merge line " " (setting-str n))))
                (send-data line)
                (sleep 0.05)
            }
        )
    }
)


(defun event-handler ()
    (loopwhile t
        (recv
            ((event-data-rx . (? data)) (trap (eval (read data))))
            (_ nil)
)))

@const-end

@const-start

; ---- Light-compensation calibration wizard ----
; The headlight sags throttle/brake readings non-linearly across the lever
; range (not a flat volts shift), so calibration fits an affine correction
; corrected = (raw - offset) / gain, from two held lever positions per
; channel (released and full press). At each position the light is toggled
; off/on/off/on and sampled each time: the off/on pair therefore comes from
; the identical lever position, so the only variable is the light itself.

(defun calib-reset-accum()
    {
        (set 'calib-off-sum 0.0) (set 'calib-off-cnt 0)
        (set 'calib-on-sum 0.0) (set 'calib-on-cnt 0)
    }
)

(defun calib-slot-light(slot) (= (mod slot 2) 1)) ; off, on, off, on...

(defun calib-add(val)
    (if (calib-slot-light calib-slot)
        { (set 'calib-on-sum (+ calib-on-sum val)) (set 'calib-on-cnt (+ calib-on-cnt 1)) }
        { (set 'calib-off-sum (+ calib-off-sum val)) (set 'calib-off-cnt (+ calib-off-cnt 1)) }
    )
)

(defun calib-off-avg() (if (> calib-off-cnt 0) (/ calib-off-sum calib-off-cnt) 0.0))
(defun calib-on-avg() (if (> calib-on-cnt 0) (/ calib-on-sum calib-on-cnt) 0.0))

; Two-point fit from the released/full-press averages, inverted for runtime
; use: corrected = (on_measured - offset) / gain
(defun calib-finish-regression(label off-rel off-full on-rel on-full)
    {
        (var off-range (- off-full off-rel))
        (if (< off-range 0.3) ; released/full too close together - bad sample
            (send-data (str-merge "calib-error " label))
            {
                (var gain (/ (- on-full on-rel) off-range))
                (var offset (- on-rel (* gain off-rel)))
                ; hard safety bounds - gain must stay well clear of 0 (division
                ; at runtime) and within a sane range for a lighting-induced sag
                (if (< gain 0.3) (setq gain 0.3))
                (if (> gain 3.0) (setq gain 3.0))
                (if (< offset -1.5) (setq offset -1.5))
                (if (> offset 1.5) (setq offset 1.5))
                (send-data (str-merge "calib-result " label " "
                    (str-from-n offset "%.3f ") (str-from-n gain "%.3f ")
                    (str-from-n off-rel "%.3f ") (str-from-n off-full "%.3f ")
                    (str-from-n on-rel "%.3f ") (str-from-n on-full "%.3f")))
            }
        )
    }
)

(defun calib-phase-label(phase) (if (= phase 0) "rel" "full"))

; 1-based sample number across the whole run, for the UI progress readout
(defun calib-slot-index() (+ (* calib-phase calib-slots) calib-slot 1))
(defun calib-slot-total() (* calib-slots 2))

(defun calib-slot-progress()
    (str-merge (str-from-n (calib-slot-index) "%d") " " (str-from-n (calib-slot-total) "%d"))
)

(defun calib-can-start() (and (not off) (<= (abs (get-speed)) 1.0)))

; Ask for a lever position and give the user time to get there. The light is
; forced off during prep so every position starts from the same known state.
(defun calib-begin-prep(phase)
    {
        (set 'calib-phase phase)
        (set 'calib-slot 0)
        (set 'light false)
        (calib-reset-accum)
        (set 'calib-stage 'prep)
        (set 'calib-since (systime))
        (send-data (str-merge "calib-stage prep " (calib-phase-label phase)))
    }
)

; Set the light for this slot, then wait out the inrush before sampling.
(defun calib-begin-settle()
    {
        (set 'light (calib-slot-light calib-slot))
        (set 'calib-stage 'settle)
        (set 'calib-since (systime))
        (send-data (str-merge "calib-stage settle " (calib-phase-label calib-phase) " " (calib-slot-progress)))
    }
)

(defun calib-begin-sample()
    {
        (set 'calib-stage 'measure)
        (set 'calib-since (systime))
        (send-data (str-merge "calib-stage measure " (calib-phase-label calib-phase) " " (calib-slot-progress)))
    }
)

; One light state sampled. Advance through the off/on/off/on sequence; when
; the position is done, either move to the full-press position or finish.
(defun calib-finish-slot()
    {
        (set 'calib-slot (+ calib-slot 1))
        (if (< calib-slot calib-slots)
            (calib-begin-settle) ; next light state, same lever position
            {
                (var off-avg (calib-off-avg))
                (var on-avg (calib-on-avg))
                (var ch calib-channel)
                (send-data (str-merge "calib-progress " (if (eq ch 'thr) "thr " "brk ")
                    (calib-phase-label calib-phase) " "
                    (str-from-n off-avg "%.3f ") (str-from-n on-avg "%.3f")))
                (if (= calib-phase 0)
                    { ; released position done - keep it, ask for full press
                        (set 'calib-off-rel off-avg)
                        (set 'calib-on-rel on-avg)
                        (calib-begin-prep 1)
                    }
                    { ; both positions done - compute and send the result now, then
                      ; hold output disengaged a bit longer so the lever (still held
                      ; fully pressed) can be released before real throttle/brake
                      ; control resumes - avoids a surprise full-power launch
                        (set 'light false)
                        (calib-finish-regression (if (eq ch 'thr) "thr" "brk")
                            calib-off-rel off-avg calib-on-rel on-avg)
                        (set 'calib-stage 'release)
                        (set 'calib-since (systime))
                        (send-data (str-merge "calib-stage release " (if (eq ch 'thr) "thr" "brk")))
                    }
                )
            }
        )
    }
)

(defun calib-start-channel(channel)
    (if (calib-can-start)
        {
            (set 'calib-channel channel)
            (calib-begin-prep 0) ; start at the released position
        }
        (send-data "calib-refused")
    )
)

(defun calib-start-thr() (calib-start-channel 'thr))
(defun calib-start-brk() (calib-start-channel 'brk))

; lever frames - off shifts to the levers in a 0x61, and the enable test
; lives here so every caller does not have to repeat it
(defunret adc-input (off)
    {
        (if (not (or software-adc software-adc2)) (return nil))
        ; The dash serves the app out of its own transmission budget, so lever
        ; frames arrive four times slower while an app is connected. Track the
        ; real rate so the watchdog below scales with it instead of firing.
        ; widen immediately when the dash slows, narrow slowly when it speeds up,
        ; so connecting an app cannot trip the watchdog before the average catches up
        (let ((gap (secs-since last-rx)))
            (if (< gap 1.0)
                (if (> gap rx-gap-avg)
                    (set 'rx-gap-avg gap)
                    (set 'rx-gap-avg (+ (* 0.98 rx-gap-avg) (* 0.02 gap)))
                )
            )
        )
        (set 'last-rx (systime)) ; feed the dash link watchdog

        (set 'dash-thr-raw (bufget-u8 uart-buf (+ thr-idx off))) ; raw physical throttle (before override)
        (set 'dash-brk-raw (bufget-u8 uart-buf (+ brk-idx off))) ; raw physical brake (before override)
        (var thr-raw-v (/ dash-thr-raw 77.2)) ; 255/3.3 = 77.2
        (var brk-raw-v (/ dash-brk-raw 77.2))

        ; Affine light compensation: corrected = (raw - offset) / gain.
        ; gain=1/offset=0 (uncalibrated default) makes this a no-op.
        (var throttle (if light (/ (- thr-raw-v light-offset-thr) light-gain-thr) thr-raw-v))
        (var brake (if light (/ (- brk-raw-v light-offset-brk) light-gain-brk) brk-raw-v))
        ; a dash that is not powered up yet reports both levers at 0x0a, far
        ; under any real rest position - taking that as the rest would leave the
        ; levers looking active for good and starve the app of its bulk reads
        (if (and (> dash-thr-raw 16) (< dash-thr-raw thr-rest)) (set 'thr-rest dash-thr-raw))
        (if (and (> dash-brk-raw 16) (< dash-brk-raw brk-rest)) (set 'brk-rest dash-brk-raw))
        (set 'levers-active (or (> dash-thr-raw (+ thr-rest 10))
                                (> dash-brk-raw (+ brk-rest 10))))

        (if (< throttle 0.0) (setq throttle 0.0))
        (if (> throttle 3.3) (setq throttle 3.3))
        (if (< brake 0.0) (setq brake 0.0))
        (if (> brake 3.3) (setq brake 3.3))

        (set 'thr-corr-v throttle) ; pre-mask - cruise release detection needs it

        ; cruise capture-assist: hold the throttle signal at 0 from activation
        ; until the lever is physically released, so the app captures the speed
        ; we were actually riding instead of the lower post-release speed. No
        ; time limit on it - a lever still held is a lever the app must not see,
        ; or it drives from the throttle and cruise stops holding anything. The
        ; rider is never stuck with a dead lever: brake cancels, and so does
        ; letting go and pressing again.
        (if (and cruising (not cruise-thr-released)) (setq throttle 0.0))

        ; Pass through throttle and brake to VESC - except during calibration,
        ; where the real output stays disengaged so a full press samples the
        ; correct raw voltage without actually moving the scooter (no stand
        ; needed; safe to calibrate stopped on the road like people actually do)
        (if (eq calib-stage 'idle)
            {
                (if software-adc (app-adc-override 0 throttle))
                (if software-adc2 (app-adc-override 1 brake))
            }
            {
                (if software-adc (app-adc-override 0 0))
                (if software-adc2 (app-adc-override 1 0))
            }
        )

        ; Light-compensation calibration wizard: drive the prep -> measure ->
        ; release sequencer. The safety abort only applies during prep/measure
        ; (invalidates in-progress data); during release the result is already
        ; sent, so we just let the grace window run out unconditionally.
        (if (and (not (eq calib-stage 'idle)) (not (eq calib-stage 'release)) (not (calib-can-start)))
            {
                (set 'calib-stage 'idle)
                (send-data "calib-aborted")
            }
            (cond
                ((eq calib-stage 'prep)
                    (if (> (secs-since calib-since) calib-prep-duration) (calib-begin-settle))
                )
                ((eq calib-stage 'settle) ; light just toggled - let it stabilise
                    (if (> (secs-since calib-since) calib-settle-duration) (calib-begin-sample))
                )
                ((eq calib-stage 'measure)
                    (if (> (secs-since calib-since) calib-sample-duration)
                        (calib-finish-slot)
                        (calib-add (if (eq calib-channel 'thr) thr-raw-v brk-raw-v))
                    )
                )
                ((eq calib-stage 'release)
                    (if (> (secs-since calib-since) calib-release-duration)
                        {
                            (set 'calib-stage 'idle)
                            (send-data (str-merge "calib-stage idle " (if (eq calib-channel 'thr) "thr" "brk")))
                        }
                    )
                )
            )
        )
    }
)

(defun handle-taillight()
    (if rear-light-enable {
        (var base (and (not off) (or light auto-taillight)))
        (var braking (and (not off) (> lev-brk adc-touch)))
        (pwm-set-duty
            (if braking
                (cond
                    ((= brake-light-mode 1) 1.0)
                    ((= brake-light-mode 2) {
                        (if (> (secs-since blink-since) 0.15) {
                            (set 'blink-state (not blink-state))
                            (set 'blink-since (systime))
                        })
                        (if blink-state 1.0 0.0)
                    })
                    (t (if base taillight-brightness 0.0))
                )
                (if base taillight-brightness 0.0)
            )
        )
    })
)

(defun cruise-cancel()
    (if cruising {
        (set 'cruising false)
        (set 'cruise-blocked true) ; no re-arming until the throttle is released
        (app-adc-override 3 0) ; release the ADC app's cruise button
        (set 'feedback 1)
    })
)

; Experimental cruise control on top of the ADC app's native cruise button:
; while the virtual button is held and the throttle is released, the app
; PID-holds the speed and mirrors current to the slaves. Any lever input
; returns control instantly at firmware level; we just release the button.
(defun handle-cruise(speed-kmh)
    (if (and cruise-allow cruise-enabled (not off) (not lock))
        {
            (var thr lev-thr)
            (var brk lev-brk)
            (if cruising
                {
                    ; Released = the lever is back under what the firmware counts
                    ; as "no throttle". The dashboard value is masked to zero until
                    ; release, so that path needs the pre-mask voltage; a lever on
                    ; the pin is never masked and reads true straight from the app.
                    ; Only a real release counts. This used to give up after three
                    ; seconds as well, which read a lever that had never been let
                    ; go as a fresh press and cancelled - so holding the throttle
                    ; through activation killed cruise three seconds later, every
                    ; time. The mask still ends at three seconds regardless.
                    (if (if software-adc
                            (< thr-corr-v cruise-v1-start)
                            (<= thr adc-touch))
                        (set 'cruise-thr-released true)
                    )
                    ; After release, any lever touch past the ADC mapping start
                    ; voltage cancels. The live lever is already flowing to the
                    ; app, so throttle/brake take over the same instant the
                    ; virtual cruise button is let go - no re-press needed.
                    (if (or (and cruise-thr-released (> thr adc-touch))
                            (> brk adc-touch))
                        (cruise-cancel)
                    )
                }
                (if (<= thr adc-touch)
                    { ; throttle released - re-arm and hold the timer at now
                        (set 'cruise-blocked false)
                        (set 'cruise-ref speed-kmh)
                        (set 'cruise-since (systime))
                    }
                    ; also never below the kick-start speed - output is disabled
                    ; down there, so cruise would arm against a dead motor
                    (if (and (not cruise-blocked) (>= speed-kmh min-speed)
                             (>= speed-kmh cruise-min-speed) (<= speed-kmh cruise-max-speed))
                        {
                            (if (> (abs (- speed-kmh cruise-ref)) cruise-deviation) {
                                (set 'cruise-ref speed-kmh)
                                (set 'cruise-since (systime))
                            })
                            (if (> (secs-since cruise-since) cruise-delay) {
                                (set 'cruising true)
                                (set 'cruise-thr-released false)
                                (set 'cruise-v1-start (conf-get 'adc-v1-start)) ; fresh from the app config
                                (set 'cruise-shown-time (systime))
                                (app-adc-override 3 1) ; hold the cruise button
                                (set 'feedback 2)
                                (set 'cruise-since (systime))
                            })
                        }
                        { ; blocked or too slow - keep the timer from counting
                            (set 'cruise-ref speed-kmh)
                            (set 'cruise-since (systime))
                        }
                    )
                )
            )
        }
        (cruise-cancel)
    )
)

(defun handle-features()
    {
        (set 'cur-speed-kmh (* (get-lowest-speed) 3.6))
        (check-slip)

        ; battery %: BMS reads can throw if no BMS is present - keep them from
        ; skipping the safety-critical output/lock handling below
        (trap
            (if (and bms-soc-enable (> (get-bms-val 'bms-soc) 0))
                {
                    (set 'bms-active true)
                    (set 'cur-batt (* (get-bms-val 'bms-soc) 100))
                    (var bt (get-bms-val 'bms-temp-cell-max))
                    (set 'bms-warn (or (> bt 50) (< bt 0)))
                }
                (set 'cur-batt (* (get-batt) 100))
            )
        )
        (var current-speed cur-speed-kmh)

        ; Dash link watchdog. The levers are not zeroed here - writing an override
        ; resets the firmware's command timeout, so doing it every pass would hold
        ; off the failsafe the timeout exists to provide. Going quiet is the
        ; release: the ADC app stops driving once the timeout expires. Only cruise
        ; is dropped, because the virtual button is ours to let go of.
        ; Scaled to the measured frame rate - a fixed half second fires by itself
        ; once an app is connected and the dash drops to ten frames a second.
        (var wd (* 8 rx-gap-avg))
        (if (< wd 0.5) (setq wd 0.5))
        (if (> wd 1.5) (setq wd 1.5))
        (if (and (or software-adc software-adc2) (> (secs-since last-rx) wd))
            (cruise-cancel)
        )


        (trap (handle-cruise current-speed)) ; experimental - never let it break the loop

        (if (or off lock (< current-speed min-speed))
            (if (not (app-is-output-disabled)) ; Disable output when scooter is turned off
                {
                    (app-adc-override 0 0)
                    (app-adc-override 1 0)
                    (app-disable-output -1)
                    (stop-current)
                }
            )
            (if (app-is-output-disabled) ; Enable output when scooter is turned on
                (app-disable-output 0)
            )
        )

        (trap (app-run-todo))
        (trap (app-cache-update))
        (trap (handle-taillight))
        ; the dash cannot beep once its supply is gone, so hold the pin up until
        ; the beep byte has gone out and the buzzer has had time to sound. A dash
        ; that stopped answering never spends it, so a silent bus cuts anyway.
        (if dash-power-held
            (gpio-write dash-power-held
                (if (and off (or (and (= feedback 0) (> (secs-since beep-time) 0.15))
                                 (> (secs-since last-rx) 0.5)))
                    0 1)))
        ; A detached ADC app stops resetting the timeout itself - the script has to,
        ; or a pin taken for the supply kills the other channel too even when a real
        ; lever is wired to it. Only when neither lever comes from the dashboard:
        ; when one does, adc-input keeps the timeout alive and its silence is the
        ; failsafe, which this would otherwise hold off.
        (if (and (not software-adc) (not software-adc2)) {
            (if (= power-pin 1) (app-adc-override 0 0))
            (if (= power-pin 2) (app-adc-override 1 0))
        })
        (handle-lock (abs current-speed))
            }
)

; What the dashboard shows instead of the speed while standing still.
(defun highest-temp (local canget)
    (let ((hi local))
        {
            (trap (loopforeach i (can-devs)
                (let ((c (canget i))) (if (> c hi) (setq hi c)))))
            hi
        }
    )
)

(defun idle-value ()
    (cond
        ((= idle-display 1) (rnd cur-vin))
        ((= idle-display 2) (rnd cur-fet-max))
        ((= idle-display 3) (rnd cur-mot-max))
        (t (rnd cur-batt))
    )
)

(defun build-dash-frame () ; contents of the 0x64 reply
    {
        (var current-speed (abs cur-speed-kmh))
        (var disp-speed (rnd (if use-mph (* current-speed 0.621371) current-speed)))
        (var battery (rnd cur-batt))

        ; mode field (2=eco, 4=sport, 8=charge, 16=off, 32=lock, 64=mph,
        ; 128=overheat). Drive sets no bit at all: a stock G2 cycles 2 -> 0 -> 4
        ; and a stock M365 4 -> 2 -> 0, neither of them ever sending 1. Bit 6 is
        ; the unit - Koxx3's M365 firmware reads it back to pick its own km/h or
        ; mph conversion, so the dash takes the label from there, not the number.
        (var mode-base (+ (if (= speedmode 1) 0 speedmode) (if use-mph 64 0)))
        ; On the G2 these are bits in one byte, not states that replace it - the
        ; stock controller was captured sending 0x12, off and eco together, and
        ; TriWrite's ESP32 sums them the same way. The older path sent a bare 16
        ; or 32 and threw the speed mode away with them.
        (if (= model 3)
            (bufset-u8 tx-frame tx-base (+ mode-base
                                           (if off 16 0)
                                           (if lock 32 0)
                                           (if (or warn-temp bms-warn) 128 0)))
            (if off
                (bufset-u8 tx-frame tx-base 16)
                (if lock
                    (bufset-u8 tx-frame tx-base 32) ; lock display
                    (if (or warn-temp bms-warn) ; temp icon will show up above warning degree
                        (bufset-u8 tx-frame tx-base (+ 128 mode-base))
                        (bufset-u8 tx-frame tx-base mode-base)
                    )
                )
            )
        )

        ; batt field
        (if lock
            (bufset-u8 tx-frame (+ tx-base 1) 0) ; lock display
            (bufset-u8 tx-frame (+ tx-base 1) battery)
        )

        ; light field - bit 0 on a Ninebot, and the G2 packs cruise in beside it.
        ; The M365 wants bit 6: a stock controller sends 0x64 and Koxx3's M365
        ; firmware 0x40, and bit 6 is what those two have in common. Bit 0 is
        ; clear in both, so the 1 this used to send was never the lamp.
        (var lamp (if (= model 1) 100 1))
        (if (not off)
            (if (> alarm 4)
                (bufset-u8 tx-frame (+ tx-base 2) lamp) ; alarm on
                (bufset-u8 tx-frame (+ tx-base 2) (+ (if light lamp 0)
                                                     (if (and (= model 3) cruising) 4 0)))
            )
            (bufset-u8 tx-frame (+ tx-base 2) 0)
        )

        ; speed field
        (if lock
            (bufset-u8 tx-frame (+ tx-base 4) 0) ; lock display
            (if (and cruising (< (secs-since cruise-shown-time) 3))
                (bufset-u8 tx-frame (+ tx-base 4) 125) ; "C5" for 3s after cruise engages
                (if (if unlock show-batt-idle-secret show-batt-in-idle)
                    (if (> current-speed 1)
                        (bufset-u8 tx-frame (+ tx-base 4) disp-speed)
                        (bufset-u8 tx-frame (+ tx-base 4) (idle-value)))
                    (bufset-u8 tx-frame (+ tx-base 4) disp-speed)
                )
            )
        )

        ; error field
        (if (> alarm 0)
            (bufset-u8 tx-frame (+ tx-base 5) 99) ; alarm active
            (bufset-u8 tx-frame (+ tx-base 5) (get-fault))
        )

    }
)

; The beep must be spent by a frame that actually goes out. The feature loop
; builds faster than the dash is answered, so counting it down there dropped and
; doubled beeps at random. Sealing the frame here also covers the beep byte.
(defun seal-dash-frame ()
    {
        ; Filling the frame here rather than in the feature loop is what keeps it
        ; whole: the evaluator switches contexts every fifty steps, so a frame
        ; built in one thread and sealed in another can go out with a checksum
        ; taken over bytes that changed underneath it. One thread owns it now,
        ; and every field it needs is a value the feature loop already sampled.
        (trap (build-dash-frame))
        (if (> feedback 0)
            {
                (bufset-u8 tx-frame (+ tx-base 3) 1)
                (set 'feedback (- feedback 1))
                (set 'beep-time (systime))
            }
            (bufset-u8 tx-frame (+ tx-base 3) 0)
        )
        (var crc-end (- (buflen tx-frame) 2)) ; crc bytes at end of frame
        (var crcout tx-hdr-sum) ; header bytes never change, only the fields do
        (looprange i tx-base crc-end
            (setq crcout (+ crcout (bufget-u8 tx-frame i))))
        (setq crcout (bitwise-xor crcout 0xFFFF))
        (bufset-u8 tx-frame crc-end crcout)
        (bufset-u8 tx-frame (+ crc-end 1) (shr crcout 8))
    }
)

(defun update-dash () { (seal-dash-frame) (uart-write tx-frame) })

; -> App protocol (NineDash, m365 Dashboard)
; The dash BLE module bridges app frames onto this same half-duplex bus, so
; their reads arrive here addressed to the ESC (0x20) or, on Xiaomi, to the
; BMS (0x22) - a VESC has no Xiaomi BMS on the bus, so that device is emulated.
; Replies are request-driven: never answer a frame the app did not send.

(def app-ver 0x0700) ; 7.0.0 - above every stock version, marks this as a VESC

; "VESC" plus ten digits derived from the controller UUID, so a VESC is
; identifiable at a glance and every unit reads differently. Together with
; firmware version 7.0.0 this is what an app keys off to detect the package.
(defun app-build-serial ()
    (let ((n 0))
        {
            (trap (loopforeach b (sysinfo 'uuid) (setq n (+ (* n 31) b))))
            (var lo (mod (bitwise-and n 0x7FFFFFFF) 100000))
            (var hi (mod (bitwise-and (shr n 7) 0x7FFFFFFF) 100000))
            (var s (str-merge "VESC" (str-from-n hi "%05d") (str-from-n lo "%05d")))
            (looprange i 0 14 (bufset-u8 app-serial i (bufget-u8 s i)))
            ; 0xDA-0xDF is the ESC CPU id, and apps print it as plain hex. Pack
            ; the serial digits two per byte so it reads back as the serial
            ; instead of as an unrecognisable number.
            (looprange i 0 5 (bufset-u8 app-cpuid i
                (+ (shl (- (bufget-u8 s (+ 4 (* i 2))) 48) 4)
                   (- (bufget-u8 s (+ 5 (* i 2))) 48))))
        }
    )
)

(defun app-build-pin ()
    (let ((s (str-from-n app-pin "%06d")))
        (looprange i 0 6 (bufset-u8 app-pin-buf i (bufget-u8 s i)))
    )
)

(defun app-word (buf idx) ; register pair out of a byte string, little endian
    (+ (bufget-u8 buf (* idx 2)) (shl (bufget-u8 buf (+ (* idx 2) 1)) 8))
)

; Anything shown as a whole number came from a float, and to-i drops the
; fraction rather than rounding it - so 78.9% reads 78 and 27.6 C reads 27, a
; whole unit low half the time. Away from zero, so a charging current reads the
; same way a discharging one does.
(defun rnd (v) (to-i (if (< v 0) (- v 0.5) (+ v 0.5))))

(defun app-clamp16 (v)
    (cond ((> v 32767) 32767) ((< v -32768) -32768) (t (rnd v)))
)

(defun app-sysinfo (key) (let ((v 0)) { (trap (setq v (sysinfo key))) (to-i v) }))

; One bulk read asks for 26 registers at once, so nothing below may query CAN
; or read the config - the reply path has to stay cheap, same as the dash
; frame. Everything expensive is sampled once per cycle in app-cache-update.
(defun app-cache-update ()
    {
        ; Five times a second: only what genuinely moves that fast.
        (if (> (secs-since app-cache-time) 0.2) {
            (set 'app-cache-time (systime))
            (set 'cur-vin (get-vin))
            (set 'cur-amps (setup-current-in))
            (set 'cur-fet (get-temp-fet))
            (set 'cur-mot (get-temp-mot))
            ; the hottest of every unit, sampled here so the dash frame and the
            ; state line can read a number instead of walking the bus themselves
            (set 'cur-fet-max (highest-temp cur-fet canget-temp-fet))
            (set 'cur-mot-max (highest-temp cur-mot canget-temp-motor))
            (set 'warn-temp (or (> cur-fet-max temp-warning-fet)
                                (> cur-mot-max temp-warning-motor)))
            (set 'cur-cell-mv (app-clamp16 (/ (* cur-vin 1000) cur-cells)))
            ; Real per-cell voltages and health when a VESC BMS is reporting, so
            ; an app's cell view shows the actual balance instead of fifteen
            ; copies of the pack average. Sampled here, never in the reply path.
            (if bms-active
                (trap {
                    (set 'cur-soh (app-clamp16 (* (get-bms-val 'bms-soh) 100)))
                    (looprange i 0 (if (> cur-cells 15) 15 cur-cells) {
                        (var mv (app-clamp16 (* (get-bms-val 'bms-v-cell i) 1000)))
                        (bufset-u8 app-cells (* i 2) (bitwise-and mv 0xFF))
                        (bufset-u8 app-cells (+ (* i 2) 1) (bitwise-and (shr mv 8) 0xFF))
                    })
                })
            )
            ; only the protocol this dash actually speaks - the other one's
            ; frames are never sent, so preparing them is work for nothing
            (if (!= model 1)
                {
                    (build-app-frame app-f-b4 0xb4 6)
                    (build-app-frame app-f-7b 0x7b 6)
                    ; the app polls the mode back three times a second, so this
                    ; one cannot sit in the half second group with the odometer
                    (build-app-frame app-f-75 0x75 2)
                    (build-app-frame-from app-f-33 0 0x22 0x33 4 true)
                    (build-app-frame-from app-f-35 0 0x22 0x35 2 true)
                }
            )
        })
        ; The slow figures - range, odometer, runtime, pack capacity - crawl, and
        ; conf-get and sysinfo are expensive. They run one group per tick rather
        ; than all together, so no single pass can hold the evaluator for long.
        (if (> (secs-since app-slow-time) 0.5) {
            (set 'app-slow-time (systime))
            (cond
                ((= app-slow-step 0) {
                    (set 'cur-wh-tot (* 0.85 (conf-get 'si-battery-ah) (* 3.7 (conf-get 'si-battery-cells))))
                    (set 'cur-range (send-state-range))
                    (set 'cur-trip (to-i (get-dist-abs)))
                })
                ((= app-slow-step 1) {
                    (set 'cur-odo (app-sysinfo 'odometer))
                    (set 'cur-runtime (app-sysinfo 'runtime))
                    (set 'cur-maxkmh (send-state-maxkmh))
                })
                ((= app-slow-step 2)
                    (if (!= model 1) {
                        (build-app-frame-from app-f-31 0 0x22 0x31 2 true)
                        (build-app-frame-from app-f-40 0 0x22 0x40 30 true)
                        (build-app-frame app-f-25 0x25 2)
                    })
                )
                (t (if (and b0-wanted (!= model 1)) {
                    (set 'b0-wanted false)
                    (build-app-frame app-f-b0 0xb0 52)
                }))
            )
            (set 'app-slow-step (mod (+ app-slow-step 1) 4))
        })
    }
)

; The dash's throttle and brake frames share this bus and this thread, and a
; reply holds the line while it transmits - 5.3 ms for the 52 byte bulk read at
; 115200 baud. Nothing may delay the lever path while riding, so above walking
; pace only short replies are answered and the big blocks wait for a standstill.
; The app re-requests what it misses, which the traces show it already does.
(defun app-speed-01 () (app-clamp16 (* (abs cur-speed-kmh) 10))) ; 0.1 km/h
(defun app-trip-m () cur-trip)
(defun app-volt-cv () (app-clamp16 (* cur-vin 100))) ; 0.01 V
(defun app-amp-ca () (app-clamp16 (* cur-amps 100))) ; 0.01 A, negative = charging
(defun app-range-10m () (app-clamp16 (* cur-range 100)))
(defun app-fet-01 () (app-clamp16 (* cur-fet 10)))
; a BMS-backed pack reports each cell; anything else divides the pack voltage
(defun app-cell-mv (i) (if bms-active (app-word app-cells i) cur-cell-mv))

; The app fetches 0xB0..0xC9 as a single 52 byte read. Assembling that is 26
; register lookups and 104 buffer operations, so it is done once per cache
; cycle and only when something actually asks for it.
(defunret app-pend-buf ()
    {
        (if (= pend-dev 0x22)
            (return (cond
                ((and (= pend-reg 0x33) (= pend-n 4)) app-f-33)
                ((and (= pend-reg 0x35) (= pend-n 2)) app-f-35)
                ((and (= pend-reg 0x31) (= pend-n 2)) app-f-31)
                ((and (= pend-reg 0x40) (= pend-n 30)) app-f-40)
                (t nil)
            ))
        )
        (cond
            ((and (= pend-reg 0xb4) (= pend-n 6)) app-f-b4)
            ((and (= pend-reg 0xb0) (= pend-n 52)) app-f-b0)
            ((and (= pend-reg 0x7b) (= pend-n 6)) app-f-7b)
            ((and (= pend-reg 0x1a) (= pend-n 2)) app-f-1a)
            ((and (= pend-reg 0x25) (= pend-n 2)) app-f-25)
            ((and (= pend-reg 0x3b) (= pend-n 2)) app-f-3b)
            ((and (= pend-reg 0x75) (= pend-n 2)) app-f-75)
            ((and (= pend-reg 0xda) (= pend-n 12)) app-f-da)
            (t nil)
        )
    }
)

; one buffer per app answer size that can occur - never resized, never allocated
(defun combo-buf (al)
    (cond ((= al 11) combo11) ((= al 13) combo13) ((= al 15) combo15)
          ((= al 21) combo21) ((= al 39) combo39) ((= al 61) combo61) (t nil))
)

(defun send-dash-and-app ()
    ; Xiaomi prepares nothing - its app asks three times a second where a Ninebot
    ; app asks ten, so a live build costs less than keeping buffers current
    (let ((ab (if (or (= model 1) app-pend2) nil (app-pend-buf))))
        {
            (set 'app-pend false)
            (seal-dash-frame)
            (if app-pend2
                ; both slots full - build the pair onto the end of the dash frame
                ; and send the lot as one transmission
                {
                    (set 'app-pend2 false)
                    (var dl (buflen tx-frame))
                    (var l1 (app-fr-len pend-n))
                    (var cb (array-create (+ dl l1 (app-fr-len pend2-n))))
                    (trap {
                        (bufcpy cb 0 tx-frame 0 dl)
                        (build-app-frame-from cb dl pend-dev pend-reg pend-n (= pend-dev 0x22))
                        (build-app-frame-from cb (+ dl l1) pend2-dev pend2-reg pend2-n
                                              (= pend2-dev 0x22))
                        (uart-write cb)
                    })
                    (free cb)
                }
            (if (eq ab nil)
                ; no prepared buffer for this one, so build it straight onto the
                ; end of the dash frame rather than sending it after: two writes
                ; are two transmissions, and it is transmissions that cost lever
                ; data on a half-duplex bus, not bytes
                {
                    (var dl (buflen tx-frame))
                    (var cb (array-create (+ dl (app-fr-len pend-n))))
                    (trap {
                        (bufcpy cb 0 tx-frame 0 dl)
                        (build-app-frame-from cb dl pend-dev pend-reg pend-n (= pend-dev 0x22))
                        (uart-write cb)
                    })
                    (free cb)
                }
                (let ((cb (combo-buf (buflen ab))) (dl (buflen tx-frame)))
                    (if (eq cb nil)
                        { (uart-write tx-frame) (uart-write ab) }
                        {
                            (bufcpy cb 0 tx-frame 0 dl)
                            (bufcpy cb dl ab 0 (buflen ab))
                            (uart-write cb)
                        }
                    )
                )
            ))
        }
    )
)

; One app answer, in whichever framing this dash speaks. Ninebot names both ends
; and counts only the payload in len; Xiaomi names one end and counts two more.
; Past that - payload, checksum, and where they sit - the two are the same shape.
; at is zero for a prepared reply and the dash frame's length when it rides on one.
(defun build-app-frame-from (buf at dev reg n bms)
    {
        (var xm (= model 1))
        (var p (+ at (if xm 6 7))) ; first payload byte
        (var crc (+ n reg))
        (if xm
            (let ((a (if bms 0x25 0x23)))
                {
                    (bufset-u16 buf at 0x55aa)
                    (bufset-u8 buf (+ at 2) (+ n 2))
                    (bufset-u8 buf (+ at 3) a)
                    (bufset-u8 buf (+ at 4) 0x01)
                    (setq crc (+ crc 2 a 0x01))
                }
            )
            {
                (bufset-u16 buf at 0x5aa5)
                (bufset-u8 buf (+ at 2) n)
                (bufset-u8 buf (+ at 3) dev)
                (bufset-u8 buf (+ at 4) app-dst)
                (bufset-u8 buf (+ at 5) 0x04)
                (setq crc (+ crc dev app-dst 0x04))
            }
        )
        (bufset-u8 buf (- p 1) reg)
        (looprange i 0 (/ n 2) {
            (var w (if bms (xm-bms-word (+ reg i))
                       (if xm (xm-word (+ reg i)) (nb-word (+ reg i)))))
            (var lo (bitwise-and w 0xFF))
            (var hi (bitwise-and (shr w 8) 0xFF))
            (bufset-u8 buf (+ p (* i 2)) lo)
            (bufset-u8 buf (+ p (* i 2) 1) hi)
            (setq crc (+ crc lo hi))
        })
        (setq crc (bitwise-xor crc 0xFFFF))
        (bufset-u8 buf (+ p n) (bitwise-and crc 0xFF))
        (bufset-u8 buf (+ p n 1) (bitwise-and (shr crc 8) 0xFF))
    }
)

(defun build-app-frame (buf reg n) (build-app-frame-from buf 0 0x20 reg n false))

(defun app-cap-mah () cur-cap)

; NB_INF_BOOL: bit0 speed limited, bit1 locked, bit2 buzzer, bit11 activated
(defun app-bool-word ()
    (+ (if (= speedmode 2) 1 0) (if lock 2 0) (if (> alarm 0) 4 0) 2048)
)

(defun app-workmode () (cond ((= speedmode 2) 1) ((= speedmode 4) 2) (t 0)))

; Writes shared by both protocols. Speed limits are acknowledged but never
; applied - the app must not silently overwrite the configured profiles.
; The prepared 0x7B answer is a Ninebot buffer and app-write is shared by both
; protocols, so the refresh has to know which one it is running under. Letting
; it throw here would abandon the rest of the write - including the flag that
; tells the feature loop to persist the setting.
(defun app-refresh-7b () (if (!= model 1) (build-app-frame app-f-7b 0x7b 6)))

(defun app-write (reg val)
    (cond
        ; lock and unlock are only valid in non-riding mode
        ((= reg 0x70) (if (and (!= val 0) (not lock) (<= (abs cur-speed-kmh) 0.5))
            (set 'app-todo (bitwise-or app-todo 32))))
        ((= reg 0x71) (if (and (!= val 0) lock (<= (abs cur-speed-kmh) 0.5))
            (set 'app-todo (bitwise-or app-todo 32))))
        ((= reg 0x75) (let ((m (cond ((= val 1) 2) ((= val 2) 4) (t 1))))
            (if (!= m speedmode) {
                (set 'speedmode m)
                (set 'app-todo (bitwise-or app-todo 16))
            })))
        ; 0x7A is Reserved in the Ninebot protocol, so it is free for a proper
        ; headlight switch. Note that changing the headlight ends the BLE
        ; session on this hardware whatever triggers it - see docs/ninedash.md
        ((= reg 0x7a) (let ((v (!= val 0)))
            (if (not (eq v light)) {
                (set 'light v)
                (app-refresh-7b)
            })))
        ((= reg 0x7c) (let ((v (and (!= val 0) cruise-allow)))
            (if (not (eq v cruise-enabled)) {
                (set 'cruise-enabled v)
                (app-refresh-7b)
                (set 'app-todo (bitwise-or app-todo 1))
            })))
        ((= reg 0x7d) (let ((v (!= val 0)))
            (if (not (eq v auto-taillight)) {
                (set 'auto-taillight v)
                (app-refresh-7b)
                (set 'app-todo (bitwise-or app-todo 2))
            })))
        ; The app's KERS selector, walk-mode and direct-power-control toggles
        ; have no VESC equivalent, so they drive speed mode, secret and the
        ; headlight instead.
        ((= reg 0x7b) (let ((m (cond ((= val 1) 1) ((= val 2) 4) (t 2)))) ; weak eco, medium drive, strong sport
            (if (!= m speedmode) {
                (set 'speedmode m)
                (set 'app-todo (bitwise-or app-todo 16))
            })))
        ((= reg 0x77) (let ((u (!= val 0)))
            (if (not (eq u unlock)) {
                (set 'unlock u)
                (set 'app-todo (bitwise-or app-todo 16))
            })))
        ((= reg 0x76) (let ((v (!= val 0)))
            (if (not (eq v light)) {
                (set 'light v)
                (app-refresh-7b)
            })))
        ((= reg 0x90) (set 'light (!= val 0)))
        ; 0x79 powerdown: the dashboard is powered separately from a VESC, so
        ; this turns it off the same way the appUI button and a long press do,
        ; rather than cutting the whole vehicle
        ((= reg 0x79) (if (!= val 0) (set 'app-todo (bitwise-or app-todo 64))))
        ((= reg 0x7e) (if (!= val 0) (set 'feedback 3))) ; find my scooter
        ((or (= reg 0x91) (= reg 0x92)) (let ((v (!= val 0)))
            (if (not (eq v alarm-tone)) {
                (set 'alarm-tone v)
                (set 'app-todo (bitwise-or app-todo 4))
            })))
        ((= reg 0x17) (if (and (>= val 0) (<= val 999999) (!= val app-pin)) {
            (set 'app-pin val)
            (app-build-pin)
            (set 'app-todo (bitwise-or app-todo 8))
        }))
    )
)

(defun app-run-todo ()
    (if (!= app-todo 0)
        (let ((td app-todo))
            {
                (set 'app-todo 0)
                (if (= (bitwise-and td 64) 64) (ctrl-power false)) ; speed guarded there
                (if (= (bitwise-and td 32) 32) (toggle-lock))
                (if (= (bitwise-and td 16) 16) (apply-mode))
                (if (= (bitwise-and td 1) 1) (write-setting 'cruise-enabled cruise-enabled))
                (if (= (bitwise-and td 2) 2) (write-setting 'auto-taillight auto-taillight))
                (if (= (bitwise-and td 4) 4) (write-setting 'alarm-tone alarm-tone))
                (if (= (bitwise-and td 8) 8) (write-setting 'app-pin app-pin))
            }
        )
    )
)

; 0xb0~0xbd mirrors the commonly polled values so the app can fetch them in a
; single read, and it does - one bulk read asks for 26 registers at once. That
; block is split out and tested first, so a bulk read does not walk the whole
; table 26 times over.
(defun nb-quick (reg)
    (cond
        ((= reg 0xb0) (get-fault))
        ((= reg 0xb1) (if (> alarm 0) 9 0))
        ((= reg 0xb2) (app-bool-word))
        ((= reg 0xb3) (+ (bitwise-and (rnd cur-batt) 0xFF) (shl (bitwise-and (rnd cur-batt) 0xFF) 8)))
        ((= reg 0xb4) (rnd cur-batt))
        ((or (= reg 0xb5) (= reg 0xb6)) (app-speed-01))
        ((= reg 0xb7) (bitwise-and cur-odo 0xFFFF))
        ((= reg 0xb8) (shr cur-odo 16))
        ((= reg 0xb9) (app-clamp16 (/ (app-trip-m) 10)))
        ((= reg 0xba) (to-i (secs-since app-boot-time)))
        ((= reg 0xbb) (app-fet-01))
        ((= reg 0xbe) last-alarm-code) ; the alarm that just cleared
        ((= reg 0xbc) (+ (bitwise-and (rnd cur-maxkmh) 0xFF) ; low: current limit, high: full speed
                         (shl (bitwise-and (rnd cur-maxkmh) 0xFF) 8)))
        ((= reg 0xbd) (app-clamp16 (* cur-vin cur-amps))) ; W
        ((= reg 0xbf) (app-range-10m))
        ((and (>= reg 0xda) (<= reg 0xdf)) (app-word app-cpuid (- reg 0xda))) ; NB_CPUID_A-F
        (t 0)
    )
)

; ordered by how often the app asks, the interpreter walks this top to bottom
(defun nb-word (reg)
    (if (>= reg 0xb0)
        (nb-quick reg)
        (cond
            ((= reg 0x1a) app-ver)
            ((= reg 0x75) (app-workmode))
            ((= reg 0x7b) (cond ((= speedmode 1) 1) ((= speedmode 4) 2) (t 0))) ; shows the speed mode
            ((= reg 0x77) (if unlock 1 0))
            ((= reg 0x76) (if light 1 0))
            ((= reg 0x7c) (if (and cruise-allow cruise-enabled) 1 0))
            ((= reg 0x7d) (if auto-taillight 2 0)) ; the app writes 2 for on
            ((or (= reg 0x24) (= reg 0x25)) (app-range-10m))
            ((= reg 0x3a) (to-i (secs-since app-boot-time)))
            ((and (>= reg 0x10) (< reg 0x17)) (app-word app-serial (- reg 0x10)))
            ((and (>= reg 0x17) (< reg 0x1a)) (app-word app-pin-buf (- reg 0x17)))
            ((= reg 0x1b) (get-fault))
            ((= reg 0x1c) (if (> alarm 0) 9 0)) ; ALARM_CODE_LOCKED
            ((= reg 0x1d) (app-bool-word))
            ((= reg 0x1f) (app-workmode))
            ((= reg 0x22) (rnd cur-batt))
            ((= reg 0x26) (app-speed-01))
            ((= reg 0x29) (bitwise-and cur-odo 0xFFFF))
            ((= reg 0x2a) (shr cur-odo 16))
            ((= reg 0x2f) (app-clamp16 (/ (app-trip-m) 10)))
            ((= reg 0x32) (bitwise-and cur-runtime 0xFFFF))
            ((= reg 0x33) (shr cur-runtime 16))
            ((= reg 0x3e) (app-fet-01))
            ((= reg 0x41) (app-clamp16 (* cur-mot 10)))
            ((= reg 0x46) 0x32) ; apps read this back to recognise a VESC
            ((or (= reg 0x47) (= reg 0x48)) (app-volt-cv))
            ((or (= reg 0x49) (= reg 0x53)) (app-amp-ca))
            ((= reg 0x65) (app-speed-01))
            ((or (= reg 0x66) (= reg 0x67) (= reg 0x68)) app-ver)
            ((= reg 0x72) (if (= speedmode 2) 1 0)) ; limiter flag, not a limit
            ((or (= reg 0x73) (= reg 0x74)) (app-clamp16 (* cur-maxkmh 10)))
            ((= reg 0x7a) (if light 1 0))
            ((= reg 0x90) (if light 1 0))
            ((or (= reg 0x91) (= reg 0x92)) (if alarm-tone 1 0))
            (t 0)
        )
    )
)

; a read answers with 0x04 and rides on the dash frame, a write acks with 0x05
; on its own - frame: 5A A5 01 src dst 05 reg 01 crc
(defun nb-ack (from dst reg)
    (let ((buf (array-create 10)) (crc (+ 1 from dst 0x05 reg 1)))
        {
            (trap {
            (bufset-u16 buf 0 0x5aa5)
            (bufset-u8 buf 2 1)
            (bufset-u8 buf 3 from)
            (bufset-u8 buf 4 dst)
            (bufset-u8 buf 5 0x05)
            (bufset-u8 buf 6 reg)
            (bufset-u8 buf 7 1)
            (setq crc (bitwise-xor crc 0xFFFF))
            (bufset-u8 buf 8 (bitwise-and crc 0xFF))
            (bufset-u8 buf 9 (bitwise-and (shr crc 8) 0xFF))
            (uart-write buf)
            })
            (free buf)
        }
    )
)

; Hold an app read for the next dash answer, where it goes out inside the frame
; the controller was sending anyway. Both protocols land here - the M365 dash
; asks with 0x61 and the G30 with 0x01 - and what has to happen next is the same.
; Two slots, because apps ask in bursts three or four deep while the dash only
; offers a slot every ninety milliseconds: both replies ride in the same frame,
; so the second one is free. A third is dropped and the app re-asks, which is
; still cheaper than a transmission of its own.
(defun app-hold (dev reg n)
    {
        (if (or (< n 2) (> n 64)) (setq n 2))
        (setq n (bitwise-and n 0xFE))
        (if (not (and (>= n 20) levers-active))
            (if (not app-pend) {
                (set 'pend-dev dev) (set 'pend-reg reg) (set 'pend-n n)
                (set 'app-pend true)
            }
            (if (not app-pend2) {
                (set 'pend2-dev dev) (set 'pend2-reg reg) (set 'pend2-n n)
                (set 'app-pend2 true)
            }))
        )
    }
)

; framing bytes an app answer adds on top of its payload
(defun app-fr-len (n) (+ n (if (= model 1) 8 9)))

; Xiaomi: single device byte, 0x20/0x23 for the ESC and 0x22/0x25 for the BMS.
; The register map is the Ninebot one - every value the two answer is the same
; except the speed, which is metres/hour here and 0.1 km/h there, so it saturates
; the u16 at 65 km/h.
(defun xm-word (reg)
    (if (or (= reg 0x26) (= reg 0x65) (= reg 0xb5) (= reg 0xb6))
        (app-clamp16 (* (abs cur-speed-kmh) 1000))
        (nb-word reg)
    )
)

(defun xm-bms-word (reg)
    (cond
        ((and (>= reg 0x10) (< reg 0x17)) (app-word app-serial (- reg 0x10)))
        ((= reg 0x17) app-ver)
        ((or (= reg 0x18) (= reg 0x19)) (app-cap-mah)) ; design, then measured
        ((= reg 0x1a) 3600) ; nominal cell voltage, mV
        ((= reg 0x20) 0x3021) ; 7 bit year from 2000, 4 bit month, 5 bit day
        ; bit0 config valid, bit6 charging. A pack answering zero here reads as
        ; an unconfigured BMS, which is what this used to send.
        ((= reg 0x30) (if (< cur-amps 0) 65 1))
        ((= reg 0x31) (app-clamp16 (/ (* cur-batt cur-cap) 100)))
        ((= reg 0x32) (rnd cur-batt))
        ((= reg 0x33) (app-amp-ca))
        ((= reg 0x34) (app-volt-cv))
        ((= reg 0x35) (let ((tc (bitwise-and (+ (rnd cur-fet) 20) 0xFF))) ; both sensors +20
                          (+ tc (shl tc 8))))
        ((= reg 0x3b) cur-soh) ; health
        ; the block holds fifteen cells and a pack that has fewer leaves the rest
        ; at zero - so report as many as the VESC is configured for, not ten
        ((and (>= reg 0x40) (< reg 0x4f) (< (- reg 0x40) cur-cells))
            (app-cell-mv (- reg 0x40)))
        (t 0)
    )
)


; One app frame, either protocol. Xiaomi puts the payload a byte earlier and its
; length byte counts two more of the frame, so both come out the same once those
; two are applied. What is left is genuinely per-protocol: only Ninebot names the
; requester, and only Ninebot acks a write - a stock M365 controller acked none
; in 79 s of capture, the app simply repeats each one and reads it back.
(defun app-frame (dev src cmd reg len)
    (let ((xm (= model 1)))
        (let ((p (if xm 3 4)) (n (if xm (- len 2) len)))
            (if (= cmd 0x01)
                ; a read carries the wanted byte count as its only payload byte;
                ; some requests omit it entirely, and then one register is meant
                (let ((want (if (> n 0) (bufget-u8 uart-buf p) 2)))
                    {
                        (if (not xm) {
                            (if (!= src app-dst) (set 'app-dst src))
                            (if (and (= reg 0xb0) (= want 52)) (set 'b0-wanted true))
                        })
                        (app-hold dev reg want)
                    }
                )
                {
                    (if (and (> n 0) (!= dev 0x22))
                        (app-write reg (if (> n 1) ; one byte for a control, two for a value
                            (+ (bufget-u8 uart-buf p) (shl (bufget-u8 uart-buf (+ p 1)) 8))
                            (bufget-u8 uart-buf p)
                        ))
                    )
                    (if (not xm) (nb-ack dev src reg))
                }
            )
        )
    )
)




; The G2 handlebar has a horn and a turn signal button, and reports them one
; byte past the brake: 0x40 nothing pressed, 0x50 turn signal held for three
; seconds, 0x60 horn. The turn signal is sent in a single frame, so every lever
; frame has to be looked at - 0x64 alone is only a fifth of them. The dash drives its own turn signal lamps, so the hold is
; free to toggle cruise; the horn has no VESC output and sounds the dash buzzer.
(defun g2-extras (len)
    (if (>= len 4)
        (let ((a (bufget-u8 uart-buf 7)))
            {
                (if (= a 0x60) (set 'feedback 1)) ; refreshed while held
                (if (and (= a 0x50) (!= g2-aux 0x50) cruise-allow (not off) (not lock)) {
                    (set 'cruise-enabled (not cruise-enabled))
                    (set 'feedback 2)
                    (set 'app-todo (bitwise-or app-todo 1)) ; the flash write waits for the feature loop
                })
                (set 'g2-aux a)
            }
        )
    )
)

; Header sync, length and checksum, for either framing. Both sum from the length
; byte to the end of the payload and carry the result in two bytes, low first -
; they differ only in the header word and in how far past len that sum reaches.
; Ninebot has four bytes there (src, dst, cmd, arg) and Xiaomi one, because its
; length byte already counts its own cmd and arg. Returns the length byte on a
; good frame, nil on anything else.
(defunret read-frame ()
    {
        (uart-read-bytes uart-buf 3 0)
        ; slide a byte at a time until the header lines up - a three byte window
        ; can stay misaligned and drop every lever frame
        (loopwhile (!= (bufget-u16 uart-buf 0) rx-hdr) {
            (bufset-u8 uart-buf 0 (bufget-u8 uart-buf 1))
            (bufset-u8 uart-buf 1 (bufget-u8 uart-buf 2))
            (uart-read-bytes uart-buf 1 2)
        })
        (var len (bufget-u8 uart-buf 2))
        (if (> len 58) (return nil)) ; the rest of the frame must fit 64 bytes
        (uart-read-bytes uart-buf (+ len rx-pre 2) 0) ; overwrites the header
        (var crc len)
        (looprange i 0 (+ len rx-pre) (setq crc (+ crc (bufget-u8 uart-buf i))))
        (if (= (+ (bufget-u8 uart-buf (+ len rx-pre))
                  (shl (bufget-u8 uart-buf (+ len rx-pre 1)) 8))
               (bitwise-xor crc 0xFFFF))
            len
            nil
        )
    }
)

; One reader, both protocols. The frames differ in the header and in how many
; bytes precede the payload - Ninebot names both ends, Xiaomi only one - and
; rx-o is that difference, so the command, the register and the device all sit
; one byte apart and nothing else changes. What genuinely differs is 0x61: on a
; Ninebot it is a lever frame, on a Xiaomi it is the app's own read.
(defun read-frames ()
    (loopwhile t {
        (trap ; a parse error must not kill the reader thread
            (loopwhile t
                (let ((len (read-frame)))
                    (if (not (eq len nil))
                        (let ((cmd (bufget-u8 uart-buf (+ 1 rx-o)))
                              (dev (bufget-u8 uart-buf rx-o)))
                            (cond
                                ; the app's read, relayed with the levers riding
                                ; along: wanted byte count first, then a constant
                                ; 0x02, then throttle and brake - one byte further
                                ; along than the dash puts them in its own frames
                                ((and (= cmd 0x61) (= rx-o 0)) {
                                    (if (>= len 6) (adc-input 1))
                                    (if app-enable (app-hold dev (bufget-u8 uart-buf 2)
                                                             (bufget-u8 uart-buf 3)))
                                })
                                ; the lever frames. All three carry throttle and
                                ; brake at the same offsets, and the dash halves
                                ; its 0x65 rate while serving an app but keeps the
                                ; others coming - so taking only one of them threw
                                ; levers away exactly when they were scarcest.
                                ; Only 0x64 is answered: a stock controller of
                                ; either family replies to those and to no 0x65.
                                ((or (= cmd 0x61) (= cmd 0x65) (= cmd 0x64)) {
                                    (if (>= (- len rx-sub) (if (and (= cmd 0x64) (= rx-o 1)) 7 3))
                                        (adc-input 0))
                                    (if (= model 3) (g2-extras len))
                                    (if (and (= cmd 0x64)
                                             (> (secs-since dash-tx-time) dash-tx-iv)) {
                                        (set 'dash-tx-time (systime))
                                        (if app-pend (send-dash-and-app) (update-dash))
                                    })
                                })
                                ((and app-enable (>= cmd 0x01) (<= cmd 0x03)
                                      (or (= rx-o 0) (= dev 0x20) (= dev 0x22)))
                                    (trap (app-frame dev (bufget-u8 uart-buf 0) cmd
                                                     (bufget-u8 uart-buf (+ 2 rx-o)) len)))
                            )
                        )
                    )
                )
            )
        )
        (sleep 0.005) ; only reached after an error
    })
)

(defun combo-held(combo thr brk) ; exclusive lever matching
    (cond
        ((= combo 0) (and (> brk adc-touch) (> thr adc-touch)))
        ((= combo 1) (and (> brk adc-touch) (<= thr adc-touch)))
        ((= combo 2) (and (> thr adc-touch) (<= brk adc-touch)))
        ((= combo 3) (and (<= brk adc-touch) (<= thr adc-touch))) ; no levers
    )
)

(defun combo-state-match(combo state) ; state: bit0=brake, bit1=throttle
    (cond
        ((= combo 0) (= state 3))
        ((= combo 1) (= state 1))
        ((= combo 2) (= state 2))
    )
)

(defun toggle-secret()
    {
        (set 'unlock (not unlock))
        (set 'feedback 2) ; beep 2x
        (apply-mode)
    }
)

(defun toggle-lock()
    {
        (set 'lock (not lock)) ; lock on or off
        (if (and lock secret-exit-on-lock) (set 'unlock false)) ; optionally leave secret mode when locking
        (apply-mode)
        (set 'feedback 1) ; beep feedback
        (if (not lock)
            (stop-alarm)
        )
    }
)

(defun cycle-mode()
    {
        (cond
            ((= speedmode 1) (set 'speedmode 4))
            ((= speedmode 2) (set 'speedmode 1))
            ((= speedmode 4) (set 'speedmode 2))
        )
        (apply-mode)
    }
)

(defun toggle-light()
    (set 'light (not light))
)

; Gestures stop above the speed set in Setup - 0.1 km/h by default, so standstill
; only, but raise it and modes, headlight and secret can be reached while riding.
; Locking and switching off are never allowed with the wheel turning, whatever
; that is set to.
(def lock-safety-speed (/ 0.1 3.6))
(defun gestures-allowed() (or off (<= (abs (get-speed)) button-safety-speed)))
(defun at-standstill() (or off (<= (abs (get-speed)) lock-safety-speed)))

; Button gestures. Matching order: power-on, secret, lock, modes, light.
(defun handle-button()
    {
        (var thr lev-thr)
        (var brk lev-brk)
        (cond
            ((and off (= presses 1)) ; power on always wins when off
                {
                    (set 'off false) ; turn on
                    (set 'feedback 1) ; beep feedback
                    (set 'unlock false) ; Disable unlock on turn off
                    (apply-mode) ; Apply mode on start-up
                    (stats-reset) ; reset stats when turning on
                }
            )
            ((and unlock
                    (if secret-off-requires-lock lock (not lock))
                    (> secret-off-presses 0)
                    (= presses secret-off-presses)
                    (combo-held secret-off-combo thr brk))
                (toggle-secret) ; unlock is set, so this can only turn it off
            )
            ((and secret-enabled
                    (> secret-presses 0)
                    (= presses secret-presses)
                    (combo-held secret-combo thr brk)
                    (or (not secret-requires-lock) lock))
                (toggle-secret)
            )
            ((and (> lock-presses 0)
                    (= presses lock-presses)
                    (combo-held lock-combo thr brk))
                (if (at-standstill) (toggle-lock)) ; never while moving
            )
            ((and (if mode-requires-lock lock (not lock))
                    (> mode-presses 0)
                    (= presses mode-presses)
                    (combo-held mode-combo thr brk))
                (cycle-mode)
            )
            ((and (if light-requires-lock lock (not lock))
                    (> light-presses 0)
                    (= presses light-presses)
                    (combo-held light-combo thr brk))
                (toggle-light)
            )
            (lock (set 'feedback 1)) ; locked: beep on any unmatched press
        )
    }
)

; Gestures configured with 0 presses fire from levers alone: the lever
; combination must be held steady for 0.5 s and releases re-arm it.
(defun handle-lever-gestures()
    {
        (var thr lev-thr)
        (var brk lev-brk)
        (var state (+ (if (> brk adc-touch) 1 0) (if (> thr adc-touch) 2 0)))

        (if (!= state lever-state) {
            (set 'lever-state state)
            (set 'lever-since (systime))
        })
        (if (= state 0) (set 'lever-armed true))

        (if (and lever-armed (> state 0) (> (secs-since lever-since) 0.5))
            (cond
                ((and unlock (= secret-off-presses 0)
                        (if secret-off-requires-lock lock (not lock))
                        (combo-state-match secret-off-combo state))
                    {
                        (set 'lever-armed false)
                        (toggle-secret)
                    }
                )
                ((and secret-enabled
                        (= secret-presses 0)
                        (combo-state-match secret-combo state)
                        (or (not secret-requires-lock) lock))
                    {
                        (set 'lever-armed false)
                        (toggle-secret)
                    }
                )
                ((and (if mode-requires-lock lock (not lock)) (= mode-presses 0) (combo-state-match mode-combo state))
                    {
                        (set 'lever-armed false)
                        (cycle-mode)
                    }
                )
                ((and (if light-requires-lock lock (not lock)) (= light-presses 0) (combo-state-match light-combo state))
                    {
                        (set 'lever-armed false)
                        (toggle-light)
                    }
                )
            )
        )
    }
)

(defun handle-holding-button()
    {
        (if (and (not lock) (not off)) ; it is locked and off?
            {
                (set 'light false) ; turn off light
                (set 'feedback 1) ; beep feedback
                (set 'unlock false) ; Disable unlock on turn off
                (apply-mode)
                (set 'off true) ; turn off
            }
        )
    }
)

(defun reset-button()
    {
        (set 'press-time (systime)) ; reset press time again
        (set 'presses 0)
    }
)

; Speed mode implementation
(defun apply-mode()
    (if (not unlock)
        (cond
            ((= speedmode 1) (configure-speed drive-speed drive-watts drive-current drive-fw drive-om false))
            ((= speedmode 2) (configure-speed eco-speed eco-watts eco-current eco-fw eco-om false))
            ((= speedmode 4) (configure-speed sport-speed sport-watts sport-current sport-fw sport-om false))
        )
        (cond
            ((= speedmode 1) (configure-speed secret-drive-speed secret-drive-watts secret-drive-current secret-drive-fw secret-drive-om true))
            ((= speedmode 2) (configure-speed secret-eco-speed secret-eco-watts secret-eco-current secret-eco-fw secret-eco-om true))
            ((= speedmode 4) (configure-speed secret-sport-speed secret-sport-watts secret-sport-current secret-sport-fw secret-sport-om true))
        )
    )
)

(defun configure-speed(speed watts current fw om secret) ; normal and secret modes gate each parameter separately
    {
        (if (if secret secret-apply-speed apply-speed) (set-param 'max-speed speed))
        (if (if secret secret-apply-watts apply-watts) (set-param 'l-watt-max watts))
        (if (if secret secret-apply-current apply-current) (set-param 'l-current-max-scale current))
        (if (if secret secret-apply-fw apply-fw) (set-param 'foc-fw-current-max fw))
        (if (if secret secret-apply-om apply-om) (set-param 'foc-overmod-factor om))
    }
)

(defun set-param(param value)
    {
        (conf-set param value)
        ; live enumeration here (infrequent, and must catch the slave at boot)
        (loopforeach id (can-list-devs)
            (looprange i 0 5 {
                (if (eq (rcode-run id 0.1 `(conf-set (quote ,param) ,value)) t) (break t))
                false
            })
        )
    }
)

(defun start-alarm()
    (if (= alarm 0)
        {
            (set 'alarm 1)
            (set 'last-alarm-code 9) ; ALARM_CODE_LOCKED, kept for 0xBE
            (set 'alarm-time (systime))
            (print "Alarm started")
        }
    )
)

(defun stop-alarm()
    (if (> alarm 0)
        {
            (set 'alarm 0)
            (set-brake-rel 0)
            (stop-tone)
            (print "Alarm stopped")
        }
    )
)

; Disabling the output stops the master driving, but a slave holds its last
; command until the master's own timeout runs out - tell them directly.
(defun stop-current()
    {
        (set-current-rel 0)
        (loopforeach id (can-devs)
            (rcode-run-noret id '(set-current-rel 0))
        )
    }
)

(defun handle-lock(speed)
    {
        ; alarm detection - gyro is only polled while locked, on controllers without
        ; a local IMU get-gyro falls back to blocking CAN queries on every call
        (if lock
            {
                (var gyro (get-gyro))
                (cond
                    ; gyro detects movement while locked
                    ((or (> (abs (ix gyro 0)) alarm-gyro-threshold) (> (abs (ix gyro 1)) alarm-gyro-threshold) (> (abs (ix gyro 2)) alarm-gyro-threshold))
                        (start-alarm)
                    )
                    ; wheel is moving while locked
                    ((> speed alarm-speed-threshold)
                        (start-alarm)
                    )
                    ; not moving (> 3 seconds)
                    ((> (secs-since alarm-time) 3)
                        (stop-alarm)
                    )
                )
            }
            (stop-alarm)
        )

        ; lock power control
        (if lock
            {
                (set-current-rel 0) ; No current input when locked
                (if (and (> alarm 0) (> speed 0.0))
                    (set-brake-rel 1) ; Full power brake
                    (set-brake-rel 0) ; No brake
                )
            }
        )

        ; alarm sound handling
        (cond
            ((= alarm 2) ; first tone
                {
                    (if alarm-tone
                        (play-tone 0 4000 alarm-voltage)
                    )
                    (set 'feedback 1)
                }
            )
            ((= alarm 3) ; second tone
                {
                    (if alarm-tone
                        (play-tone 2 7000 alarm-voltage)
                    )
                    (set 'feedback 1)
                }
            )
            ((= alarm 6) ; third tone
                {
                    (if alarm-tone
                        (play-tone 1 2000 alarm-voltage)
                    )
                    (set 'feedback 1)
                }

            )
            ((= alarm 8) ; repeat alarm sound
                {
                    (if alarm-tone
                        (stop-tone)
                    )
                    (set 'feedback 1)
                    (set 'alarm 1) ; reset alarm to 1
                }
            )
        )

        ; count up alarm state
        (if (> alarm 0)
            (set 'alarm (+ alarm 1))
        )
    }
)

(defun play-tone(channel freq voltage)
    {
        (foc-play-tone channel freq voltage)
        (loopforeach id (can-devs)
            (rcode-run-noret id `(foc-play-tone ,channel ,freq ,voltage))
        )
    }
)

(defun stop-tone()
    {
        (foc-play-stop)
        (loopforeach id (can-devs)
            (rcode-run-noret id '(foc-play-stop))
        )
    }
)

(defun can-devs ()
    {
        (if (> (secs-since can-ids-time) 0.5) {
            (set 'can-ids-time (systime))
            (set 'can-ids (can-list-devs))
        })
        can-ids
    }
)

; Sampled in the feature loop, not when the UI asks: a slip is over long before
; the next poll, so asking on demand almost always looks at a wheel that has
; already gripped again.
;
; The two guards are the ones the ADC app's own traction control uses. It runs
; the spread only on the driving branch, never the braking one, so a wheel that
; locks under the brake is not slip. And a wheel reading zero while the other
; turns is a motor that is not driving, not one that has broken traction - the
; firmware drops those by status age, which nothing here can see, so the spread
; is only trusted while the slower wheel is turning too.
(defun check-slip ()
    (if (<= lev-brk adc-touch)
        (let ((r (abs (get-rpm))))
            (let ((lo r) (hi r))
                {
                    (trap (loopforeach i (can-devs)
                        (let ((v (abs (canget-rpm i))))
                            { (if (< v lo) (setq lo v)) (if (> v hi) (setq hi v)) })))
                    (if (and (> lo 0) (> (- hi lo) slip-erpm)) (set 'slip-time (systime)))
                }
            )
        )
    )
)

(defun wheel-slip ()
    (if (and (> slip-time 0) (< (secs-since slip-time) slip-hold)) 1 0))

(defun get-lowest-speed()
    {
        (var speed (get-speed))
        (trap ; a CAN device dropping off the bus must not break speed reads
            (loopforeach i (can-devs)
                (let ((can-speed (canget-speed i)))
                    (if (< can-speed speed) (set 'speed can-speed))
                )
            )
        )
        speed
    }
)

(defun gyro-live (g)
    (and (eq (type-of g) 'type-list) (= (length g) 3)
        (or (> (abs (ix g 0)) 0) (> (abs (ix g 1)) 0) (> (abs (ix g 2)) 0)))
)

; The unit that answered last time is asked first. Only when it has gone quiet
; is the bus searched again, and not more than once every ten seconds - a scooter
; with no IMU anywhere would otherwise spend a blocking round trip per device on
; every pass of the loop, for as long as it stays locked.
(defunret get-gyro()
    {
        (var g (if (< gyro-src 0) (get-imu-gyro) (rcode-run gyro-src 0.5 '(get-imu-gyro))))
        (if (gyro-live g) (return g))
        (if (< (secs-since gyro-probe) 10.0) (return '(0.0 0.0 0.0)))
        (set 'gyro-probe (systime))
        (set 'gyro-src -1)
        (setq g (get-imu-gyro))
        (if (gyro-live g) (return g))
        (loopforeach i (can-devs)
            (let ((c (rcode-run i 0.5 '(get-imu-gyro))))
                (if (gyro-live c) {
                    (set 'gyro-src i)
                    (return c)
                })
            )
        )
        '(0.0 0.0 0.0)
    }
)

(defun read-button-pin()
    {
        (var sample-num 3)
        (var sample-sum 0)

        (looprange i 0 sample-num {
            (sleep 0.02)
            (setq sample-sum (+ sample-sum (gpio-read 'pin-rx)))
        })

        (= (if (> sample-sum (/ sample-num 2)) 1 0) 0)
    }
)

(defun button-logic()
    {
        (loopwhile t
            {
                (var button-state (read-button-pin)) ; paces the loop with its own sleeps

                (if (and button-state (not last-button-state))
                    {
                        (set 'presses (+ presses 1))
                        (set 'press-time (systime))
                    }
                )
                (set 'last-button-state button-state)

                ; A transient error here (BMS/CAN/gyro) must not permanently kill
                ; button, lock, alarm and output handling - trap and keep looping.
                (trap {
                    ; read once for the whole pass - gestures, cruise, the slip
                    ; check and the brake light all used to ask separately, and a
                    ; lever released halfway through was seen both ways at once
                    (set 'lev-thr (get-adc-decoded 0))
                    (set 'lev-brk (get-adc-decoded 1))
                    (button-apply button-state)
                    (if (and (not off) (gestures-allowed)) (handle-lever-gestures))
                    (handle-features)
                })
            }
        )
    }
)

(defun button-apply(button)
    {
        (var time-passed (- (systime) press-time))

        ; systime ticks are 0.1 ms, so these are 300 ms and 600 ms
        (if (> time-passed 3000)
            (if button ; check button is still pressed
                (if (> time-passed 6000) ; long press
                    {
                        (if (at-standstill)
                            (handle-holding-button) ; switching off, so standstill only
                        )
                        (reset-button) ; reset button
                    }
                )
                (if (> presses 0) ; if presses > 0
                    {
                        (if (gestures-allowed)
                            (handle-button) ; handle button presses
                        )
                        (reset-button) ; reset button
                    }
                )
            )
        )
    }
)

(defun main () {
        (load-settings)

        (event-register-handler (spawn event-handler))
        (event-enable 'event-data-rx)

        (if (= model 2) { ; Slave: code server only, model stays switchable over CAN
            (start-code-server)
        } {
            (set 'speedmode (if (or (= boot-mode 1) (= boot-mode 2) (= boot-mode 4)) boot-mode 4))
            (if light-on-boot (set 'light true))
            (if rear-light-enable {
                (pwm-start 200 0)
                (set 'pwm-started true)
            })

            ; Packet handling
            (uart-start 115200 'half-duplex)
            (gpio-configure 'pin-rx 'pin-mode-in-pu)
            (def uart-buf (array-create 64))

            ; app protocol identity - mutable, so it is built here and not in flash
            (def app-serial (array-create 14))
            (def app-cpuid (array-create 12))
            (def app-pin-buf (array-create 6))
            (def app-cells (array-create 30)) ; fifteen cells, little endian
            ; prepared replies, sent as-is. Only Ninebot has them: its apps poll
            ; ten times a second where a Xiaomi one asks three.
            (if (!= model 1)
                {
                    (def app-f-b0 (array-create 61))
                    (def app-f-b4 (array-create 15))
                    (def app-f-7b (array-create 15))
                    (def app-f-1a (array-create 11))
                    (def app-f-25 (array-create 11))
                    (def app-f-3b (array-create 11))
                    (def app-f-75 (array-create 11))
                    (def app-f-da (array-create 21))
                    (def app-f-33 (array-create 13)) ; the BMS reads, also prepared
                    (def app-f-35 (array-create 11))
                    (def app-f-31 (array-create 11))
                    (def app-f-40 (array-create 39))
                }
            )
            (set 'cur-cells (let ((n (conf-get 'si-battery-cells))) (if (> n 0) n 10)))
            (set 'cur-wh-tot (* 0.85 (conf-get 'si-battery-ah) (* 3.7 (conf-get 'si-battery-cells))))
            (set 'cur-cap (app-clamp16 (* (conf-get 'si-battery-ah) 1000)))
            ; timestamps captured at load are frozen into the image - reset them
            ; here or the first measurement after a boot compares against a
            ; reference from whenever the image was written
            (set 'last-rx (systime))
            (set 'app-cache-time (systime))
            (set 'app-slow-time (systime))
            ; not now: stamping this one here throttles away the first poll to
            ; arrive, and the next is a hundred milliseconds behind it. Zero
            ; makes secs-since large, so the very first 0x64 gets an answer.
            (set 'dash-tx-time 0)
            (set 'press-time (systime))
            (set 'alarm-time (systime))
            (set 'lever-since (systime))
            (set 'blink-since (systime))
            (set 'cruise-since (systime))
            (set 'cruise-shown-time (systime))
            (set 'calib-since (systime))
            (app-build-serial)
            (app-build-pin)
            (if (!= model 1) {
                (build-app-frame app-f-1a 0x1a 2) ; constant, built once
                (build-app-frame app-f-da 0xda 12)
                (build-app-frame app-f-3b 0x3b 2) ; constant zero, so also once
                ; empty until the app first asks for it, and an empty buffer is
                ; also an empty checksum - so seal it once here
                (build-app-frame app-f-b0 0xb0 52)
            })
            (set 'app-boot-time (systime))

            (if (= model 1) {
                (define tx-frame (array-create 14))
                (bufset-u16 tx-frame 0 0x55AA) ;Xiaomi protocol
                (bufset-u16 tx-frame 2 0x0821)
                (bufset-u16 tx-frame 4 0x6400) ; Packet is from ESC to BLE
                (set 'rx-hdr 0x55aa)
                (set 'rx-pre 1)
                (set 'rx-o 0)
                (set 'rx-sub 2)
                (set 'tx-base 6)
                (set 'thr-idx 4)
                (set 'brk-idx 5)
            } {
                (define tx-frame (array-create (if (= model 3) 17 15)))
                (bufset-u16 tx-frame 0 0x5AA5) ;Ninebot protocol
                (bufset-u8 tx-frame 2 (if (= model 3) 0x08 0x06)) ;Payload length
                (bufset-u16 tx-frame 3 0x2021) ; Packet is from ESC to BLE
                (bufset-u16 tx-frame 5 0x6400) ; Packet is from ESC to BLE
                ; the G2 reply carries two more payload bytes - what they mean is
                ; not known, these are what a stock G2 sends once it has booted
                (if (= model 3) {
                    (bufset-u8 tx-frame 13 0x04)
                    (bufset-u8 tx-frame 14 0x91)
                })
                (set 'rx-hdr 0x5aa5)
                (set 'rx-pre 4)
                (set 'tx-base 7)
                (set 'thr-idx 5)
                (set 'brk-idx 6)
            })

            (looprange i 2 tx-base (set 'tx-hdr-sum (+ tx-hdr-sum (bufget-u8 tx-frame i))))

            ; dash answer plus each app answer size - the dash frame is two bytes
            ; longer on the G2, so they can only be sized once it exists. Only the
            ; Ninebot reader folds an app answer into the dash one.
            (if (!= model 1)
                (let ((dl (buflen tx-frame)))
                    {
                        (def combo11 (array-create (+ dl 11)))
                        (def combo13 (array-create (+ dl 13)))
                        (def combo15 (array-create (+ dl 15)))
                        (def combo21 (array-create (+ dl 21)))
                        (def combo39 (array-create (+ dl 39)))
                        (def combo61 (array-create (+ dl 61)))
                    }
                )
            )

            (apply-software-adc)
            (apply-dash-power)

            ; The dash starts polling as soon as it has power and switches itself
            ; off if nothing answers - a stock G2 controller replies within a
            ; millisecond and is never quiet for longer than about 200 ms. So the
            ; reader goes first: applying the mode below asks every CAN device to
            ; take five parameters, five attempts each at a tenth of a second, and
            ; nothing on the bus would be answered for as long as that took.
            ; Seed the battery too - the reply carries it from the very first
            ; frame, and a dash told it has none may act on that.
            (set 'cur-batt (* (get-batt) 100))
            (spawn 500 read-frames) ; 500 words: app replies allocate and nest deeper

            (apply-mode) ; Apply mode on start-up
            (button-logic) ; Start button logic in main thread - this will block the main thread
        })
})

@const-end

; Without an image the firmware reparses the whole script on every boot, and it
; rewrites the const heap from the same base pointer each time - the second boot
; then collides with the first. With one, main is found in the restored
; environment and only (main) runs.
;
; image-save returns nil when the script has outgrown the const heap. Nothing
; breaks until the next boot, so catch it here: true is what goes into the image,
; so a boot that came from one always reports success.
(def img-ok true)
(set 'img-ok (image-save))
(if (not img-ok) (print "image-save failed - script too big, will not boot"))
(main)
