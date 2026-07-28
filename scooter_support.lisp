(def software-adc true)  ; ADC1 / throttle from the dashboard
(def software-adc2 true) ; ADC2 / brake from the dashboard
; Decoded lever position counted as a touch. get-adc-decoded is mapped by the
; ADC app itself (Start/End voltage + hysteresis, after our light correction),
; so >0 already means "past the configured start voltage" - this is just an
; epsilon against float noise, not a user-facing deadband.
(def adc-touch 0.02)
(def temp-warning-motor 80) ; temperature warning for motor in degree celsius
(def temp-warning-fet 80) ; temperature warning for fet in degree celsius
(def show-batt-in-idle false) ; battery instead of speed at idle, normal modes
(def show-batt-idle-secret true) ; same but in secret modes
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
(def secret-eco-watts 1200)
(def secret-eco-fw 0)
(def secret-drive-speed (/ 47 3.6))
(def secret-drive-current 1.0)
(def secret-drive-watts 1500000)
(def secret-drive-fw 0)
(def secret-sport-speed (/ 1000 3.6)) ; 1000 km/h easy
(def secret-sport-current 1.0)
(def secret-sport-watts 1500000)
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
(def secret-exit-on-lock true) ; locking drops back to normal modes
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
(def taillight-brightness 0.4)

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
(def cruise-enabled false)
(def cruise-delay 5.0) ; seconds of steady speed to activate
(def cruise-deviation 1.0) ; km/h window counted as "steady"
(def cruise-min-speed 5.0) ; km/h - cruise can only activate at or above this
(def cruise-max-speed 100.0) ; km/h - cruise can only activate at or below this

; -> Code starts here (DO NOT CHANGE ANYTHING BELOW THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING)

; Load VESC CAN code server - const block so the library code lives in flash, not heap
@const-start
(import "pkg@://vesc_packages/lib_code_server/code_server.vescpkg" 'code-server)
(read-eval-program code-server)
@const-end

; Model (0=G30, 1=M365/1S/PRO2, 2=Slave)
(def model 0)

; Protocol offsets, set per model in main
(def tx-base 7) ; first dash field in tx-frame
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

; dash link watchdog: last time a throttle frame was received
(def last-rx (systime))
(def rx-gap-avg 0.05) ; running average gap between lever frames

; lever-only gesture state (gestures configured with 0 presses)
(def lever-state 0)
(def lever-since (systime))
(def lever-armed true)

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
(def app-reply-time (systime))
(def quick-sum 0)   ; checksum contribution of the prebuilt 0xB0 block
(def quick-used false) ; only worth maintaining while an app is actually asking
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
(def pend-src 0)
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
(def app-enable true)
(def cur-cell-mv 0) ; one division, not fifteen per cell read

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

(def settings-version 406i32)

; Persistent settings: (label . (eeprom-offset type))
(def eeprom-addrs '(
    (ver-code              . (0 i))
    (software-adc          . (1 b))
    (software-adc2         . (87 b))
    (min-adc-throttle      . (2 f)) ; legacy, unused - kept so old migrations keep working
    (min-adc-brake         . (3 f)) ; legacy, unused - the ADC app start voltages rule now
    (temp-warning-motor    . (4 f))
    (temp-warning-fet      . (5 f))
    (show-batt-in-idle     . (6 b))
    (min-speed-kmh         . (7 f))
    (alarm-tone            . (8 b))
    (alarm-speed-threshold . (9 f))
    (alarm-gyro-threshold  . (10 f))
    (alarm-voltage         . (11 f))
    (eco-speed-kmh         . (12 f))
    (eco-current           . (13 f))
    (eco-watts             . (14 f))
    (eco-fw                . (15 f))
    (drive-speed-kmh       . (16 f))
    (drive-current         . (17 f))
    (drive-watts           . (18 f))
    (drive-fw              . (19 f))
    (sport-speed-kmh       . (20 f))
    (sport-current         . (21 f))
    (sport-watts           . (22 f))
    (sport-fw              . (23 f))
    (secret-enabled        . (24 b))
    (secret-eco-speed-kmh  . (25 f))
    (secret-eco-current    . (26 f))
    (secret-eco-watts      . (27 f))
    (secret-eco-fw         . (28 f))
    (secret-drive-speed-kmh . (29 f))
    (secret-drive-current  . (30 f))
    (secret-drive-watts    . (31 f))
    (secret-drive-fw       . (32 f))
    (secret-sport-speed-kmh . (33 f))
    (secret-sport-current  . (34 f))
    (secret-sport-watts    . (35 f))
    (secret-sport-fw       . (36 f))
    (model                 . (37 i))
    (apply-speed           . (38 b))
    (apply-current         . (39 b))
    (apply-watts           . (40 b))
    (apply-fw              . (41 b))
    (secret-presses        . (42 i))
    (secret-off-presses    . (89 i))
    (secret-off-combo      . (90 i))
    (secret-off-requires-lock . (91 b))
    (secret-combo          . (43 i))
    (secret-requires-lock  . (44 b))
    (lock-presses          . (45 i))
    (lock-combo            . (46 i))
    (secret-apply-fw       . (47 b))
    (secret-apply-speed    . (48 b))
    (secret-apply-current  . (49 b))
    (secret-apply-watts    . (50 b))
    (mode-presses          . (51 i))
    (mode-combo            . (52 i))
    (light-presses         . (53 i))
    (light-combo           . (54 i))
    (light-on-boot         . (55 b))
    (button-speed-kmh      . (56 f))
    (boot-mode             . (57 i))
    (show-batt-idle-secret . (58 b))
    (mode-requires-lock    . (59 b))
    (light-requires-lock   . (60 b))
    (use-mph               . (61 b))
    (rear-light-enable     . (62 b))
    (auto-taillight        . (63 b))
    (brake-light-mode      . (64 i))
    (eco-om                . (65 f))
    (drive-om              . (66 f))
    (sport-om              . (67 f))
    (secret-eco-om         . (68 f))
    (secret-drive-om       . (69 f))
    (secret-sport-om       . (70 f))
    (apply-om              . (71 b))
    (secret-apply-om       . (72 b))
    (bms-soc-enable        . (73 b))
    (cruise-enabled        . (74 b))
    (cruise-delay          . (75 f))
    (cruise-deviation      . (76 f))
    (cruise-min-speed      . (82 f))
    (cruise-max-speed      . (83 f))
    (secret-exit-on-lock   . (77 b))
    (light-offset-thr      . (78 f))
    (light-offset-brk      . (79 f))
    (light-gain-thr        . (80 f))
    (light-gain-brk        . (81 f))
    (app-pin               . (84 i))
    (app-enable            . (85 b))
    (dash-power-out        . (86 b)) ; kept so the v404 migration can read it
    (power-pin             . (88 i))
))

(def last-button-state false)

(defun read-setting (name)
    (let (
            (addr (first (assoc eeprom-addrs name)))
            (type (second (assoc eeprom-addrs name)))
        )
        (cond
            ((eq type 'i) (eeprom-read-i addr))
            ((eq type 'f) (eeprom-read-f addr))
            ((eq type 'b) (!= (eeprom-read-i addr) 0))
)))

(defun write-setting (name val)
    (let (
            (addr (first (assoc eeprom-addrs name)))
            (type (second (assoc eeprom-addrs name)))
        )
        (cond
            ((eq type 'i) (eeprom-store-i addr val))
            ((eq type 'f) (eeprom-store-f addr val))
            ((eq type 'b) (eeprom-store-i addr (if val 1 0)))
)))

(defun valid-model (m) ; eeprom reads nil when never written
    (and (not (eq m nil)) (>= m 0) (<= m 3))
)

(defun write-secret-mode-toggles () ; settings added in v303
    {
        (write-setting 'secret-apply-speed true)
        (write-setting 'secret-apply-current true)
        (write-setting 'secret-apply-watts true)
    }
)

; v309 replaces the flat light offset with a gain+offset affine correction
; (raw wasn't shifted by a constant volts - it scaled non-linearly with lever
; position). A flat offset from v308 would be WRONG under the new formula
; (sign-inverted at points), so it's reset here - recalibrate with Sample.
; the secret-off gesture only shipped as a default nobody had reason to keep
(defun write-v406-defaults () ; settings added in v406
    {
        (write-setting 'secret-off-presses 3)
        (write-setting 'secret-off-combo 3)
        (write-setting 'secret-off-requires-lock false)
    }
)

(defun write-v405-defaults () ; settings added in v405
    {
        (write-setting 'secret-off-presses 3)
        (write-setting 'secret-off-combo 3)
    }
)

; the ADC2-only bool becomes a pin selector
(defun write-v404-defaults () ; settings added in v404
    (write-setting 'power-pin (if (read-setting 'dash-power-out) 2 0))
)

; the brake channel keeps whatever the single old switch was set to
(defun write-v403-defaults () ; settings added in v403
    (write-setting 'software-adc2 (read-setting 'software-adc))
)

(defun write-v402-defaults () ; settings added in v402
    (write-setting 'dash-power-out false)
)

(defun write-v401-defaults () ; settings added in v401
    (write-setting 'app-enable true)
)

(defun write-v400-defaults () ; settings added in v400
    (write-setting 'app-pin 0)
)

(defun write-v310-defaults () ; settings added in v310
    {
        (write-setting 'cruise-min-speed 5.0)
        (write-setting 'cruise-max-speed 100.0)
    }
)

(defun write-v309-defaults ()
    {
        (write-setting 'light-offset-thr 0.0)
        (write-setting 'light-gain-thr 1.0)
        (write-setting 'light-offset-brk 0.0)
        (write-setting 'light-gain-brk 1.0)
    }
)

(defun write-v308-defaults () ; settings added in v308
    {
        (write-setting 'light-offset-thr 0.0)
        (write-setting 'light-offset-brk 0.0)
    }
)

(defun write-v307-defaults () ; settings added in v307
    (write-setting 'secret-exit-on-lock true)
)

(defun write-v306-defaults () ; settings added in v306
    {
        (write-setting 'use-mph false)
        (write-setting 'rear-light-enable false)
        (write-setting 'auto-taillight false)
        (write-setting 'brake-light-mode 1)
        (write-setting 'eco-om 1.0)
        (write-setting 'drive-om 1.0)
        (write-setting 'sport-om 1.0)
        (write-setting 'secret-eco-om 1.0)
        (write-setting 'secret-drive-om 1.0)
        (write-setting 'secret-sport-om 1.0)
        (write-setting 'apply-om false)
        (write-setting 'secret-apply-om false)
        (write-setting 'bms-soc-enable false)
        (write-setting 'cruise-enabled false)
        (write-setting 'cruise-delay 5.0)
        (write-setting 'cruise-deviation 1.0)
    }
)

(defun write-v305-defaults () ; settings added in v305
    {
        ; battery-on-idle used to act in secret modes only - keep that behavior
        (write-setting 'show-batt-idle-secret (read-setting 'show-batt-in-idle))
        (write-setting 'show-batt-in-idle false)
        (write-setting 'mode-requires-lock false)
        (write-setting 'light-requires-lock false)
    }
)

(defun write-remap-defaults () ; settings added in v304
    {
        (write-setting 'mode-presses 2)
        (write-setting 'mode-combo 3)
        (write-setting 'light-presses 1)
        (write-setting 'light-combo 3)
        (write-setting 'light-on-boot false)
        (write-setting 'button-speed-kmh 0.1)
        (write-setting 'boot-mode 1)
    }
)

(defun restore-gesture-apply-defaults () ; settings added in v301+
    {
        (write-setting 'apply-speed true)
        (write-setting 'apply-current true)
        (write-setting 'apply-watts true)
        (write-setting 'apply-fw true)
        (write-setting 'secret-apply-fw true)
        (write-secret-mode-toggles)
        (write-remap-defaults)
        (write-v305-defaults)
        (write-v306-defaults)
        (write-v307-defaults)
        (write-v308-defaults)
        (write-v309-defaults)
        (write-v310-defaults)
        (write-v400-defaults)
        (write-v401-defaults)
        (write-v402-defaults)
        (write-v403-defaults)
        (write-v404-defaults)
        (write-v405-defaults)
        (write-v406-defaults)
                    (write-v402-defaults)
                    (write-v403-defaults)
                    (write-v404-defaults)
        (write-setting 'secret-presses 1)
        (write-setting 'secret-combo 0)
        (write-setting 'secret-requires-lock false)
        (write-setting 'lock-presses 2)
        (write-setting 'lock-combo 1)
    }
)

(defun restore-defaults ()
    {
        (var cur-model (read-setting 'model)) ; keep model across restores
        (write-setting 'software-adc true)
        (write-setting 'software-adc2 true)
        (write-setting 'min-adc-throttle 0.1)
        (write-setting 'min-adc-brake 0.1)
        (write-setting 'temp-warning-motor 80.0)
        (write-setting 'temp-warning-fet 80.0)
        (write-setting 'show-batt-in-idle true)
        (write-setting 'min-speed-kmh 1.0)
        (write-setting 'alarm-tone true)
        (write-setting 'alarm-speed-threshold 0.5)
        (write-setting 'alarm-gyro-threshold 10.0)
        (write-setting 'alarm-voltage 24.0)
        (write-setting 'eco-speed-kmh 7.0)
        (write-setting 'eco-current 0.6)
        (write-setting 'eco-watts 400.0)
        (write-setting 'eco-fw 0.0)
        (write-setting 'drive-speed-kmh 17.0)
        (write-setting 'drive-current 0.7)
        (write-setting 'drive-watts 500.0)
        (write-setting 'drive-fw 0.0)
        (write-setting 'sport-speed-kmh 22.0)
        (write-setting 'sport-current 1.0)
        (write-setting 'sport-watts 700.0)
        (write-setting 'sport-fw 0.0)
        (write-setting 'secret-enabled true)
        (write-setting 'secret-eco-speed-kmh 27.0)
        (write-setting 'secret-eco-current 1.0)
        (write-setting 'secret-eco-watts 1200.0)
        (write-setting 'secret-eco-fw 0.0)
        (write-setting 'secret-drive-speed-kmh 47.0)
        (write-setting 'secret-drive-current 1.0)
        (write-setting 'secret-drive-watts 1500000.0)
        (write-setting 'secret-drive-fw 0.0)
        (write-setting 'secret-sport-speed-kmh 1000.0)
        (write-setting 'secret-sport-current 1.0)
        (write-setting 'secret-sport-watts 1500000.0)
        (write-setting 'secret-sport-fw 10.0)
        (restore-gesture-apply-defaults)
        (write-setting 'model (if (valid-model cur-model) cur-model 0))
        (write-setting 'ver-code settings-version)
    }
)

(defun load-settings ()
    {
        (var ver (read-setting 'ver-code))
        ; Each release only writes the settings it added, so an upgrade runs every
        ; writer newer than the stored version and keeps everything else. Anything
        ; older than v4.0 is reconfigured from defaults rather than migrated.
        (if (not-eq ver settings-version)
            (if (or (eq ver nil) (< ver 400i32) (> ver settings-version))
                (restore-defaults)
                {
                    (if (< ver 401i32) (write-v401-defaults))
                    (if (< ver 402i32) (write-v402-defaults))
                    (if (< ver 403i32) (write-v403-defaults))
                    (if (< ver 404i32) (write-v404-defaults))
                    (if (< ver 405i32) (write-v405-defaults))
                    (if (< ver 406i32) (write-v406-defaults))
                    (write-setting 'ver-code settings-version)
                }
            )
        )

        ; Every setting whose runtime variable carries the same name. Spelling these
        ; out one by one cost about six hundred cells of the const heap.
        (loopforeach n '(
            software-adc software-adc2 temp-warning-motor temp-warning-fet
            show-batt-in-idle show-batt-idle-secret alarm-tone alarm-speed-threshold
            alarm-gyro-threshold alarm-voltage eco-current eco-watts eco-fw
            drive-current drive-watts drive-fw sport-current sport-watts sport-fw
            secret-enabled secret-eco-current secret-eco-watts secret-eco-fw
            secret-drive-current secret-drive-watts secret-drive-fw
            secret-sport-current secret-sport-watts secret-sport-fw apply-speed
            apply-current apply-watts apply-fw secret-apply-fw secret-apply-speed
            secret-apply-current secret-apply-watts secret-presses secret-combo
            secret-requires-lock secret-exit-on-lock light-offset-thr light-gain-thr
            light-offset-brk light-gain-brk lock-presses lock-combo mode-presses
            mode-combo mode-requires-lock light-presses light-combo
            light-requires-lock light-on-boot boot-mode use-mph rear-light-enable
            power-pin auto-taillight brake-light-mode eco-om drive-om sport-om
            secret-eco-om secret-drive-om secret-sport-om apply-om secret-apply-om
            bms-soc-enable cruise-enabled cruise-delay cruise-deviation
            cruise-min-speed cruise-max-speed app-pin app-enable secret-off-presses
            secret-off-combo secret-off-requires-lock
        ) (set n (read-setting n)))
        (set 'min-speed (read-setting 'min-speed-kmh))
        (set 'eco-speed (/ (read-setting 'eco-speed-kmh) 3.6))
        (set 'drive-speed (/ (read-setting 'drive-speed-kmh) 3.6))
        (set 'sport-speed (/ (read-setting 'sport-speed-kmh) 3.6))
        (set 'secret-eco-speed (/ (read-setting 'secret-eco-speed-kmh) 3.6))
        (set 'secret-drive-speed (/ (read-setting 'secret-drive-speed-kmh) 3.6))
        (set 'secret-sport-speed (/ (read-setting 'secret-sport-speed-kmh) 3.6))
        (set 'button-safety-speed (/ (read-setting 'button-speed-kmh) 3.6))

        (var m (read-setting 'model))
        (if (not (valid-model m)) {
            (setq m 0)
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

(defun save-general-settings (adc adc2 show-batt show-batt-secret min-speed-kmh app)
    {
        (write-setting 'app-enable app)
        (write-setting 'software-adc adc)
        (write-setting 'software-adc2 adc2)
        (write-setting 'show-batt-in-idle show-batt)
        (write-setting 'show-batt-idle-secret show-batt-secret)
        (write-setting 'min-speed-kmh min-speed-kmh)
    }
)

(defun save-temp-settings (motor-warning fet-warning)
    {
        (write-setting 'temp-warning-motor motor-warning)
        (write-setting 'temp-warning-fet fet-warning)
    }
)

(defun save-mode-settings (
        eco-speed-kmh eco-current eco-watts eco-fw
        drive-speed-kmh drive-current drive-watts drive-fw
        sport-speed-kmh sport-current sport-watts sport-fw
        boot eco-om drive-om sport-om)
    {
        (write-setting 'boot-mode boot)
        (write-setting 'eco-om eco-om)
        (write-setting 'drive-om drive-om)
        (write-setting 'sport-om sport-om)
        (write-setting 'eco-speed-kmh eco-speed-kmh)
        (write-setting 'eco-current eco-current)
        (write-setting 'eco-watts eco-watts)
        (write-setting 'eco-fw eco-fw)
        (write-setting 'drive-speed-kmh drive-speed-kmh)
        (write-setting 'drive-current drive-current)
        (write-setting 'drive-watts drive-watts)
        (write-setting 'drive-fw drive-fw)
        (write-setting 'sport-speed-kmh sport-speed-kmh)
        (write-setting 'sport-current sport-current)
        (write-setting 'sport-watts sport-watts)
        (write-setting 'sport-fw sport-fw)
    }
)

(defun save-secret-settings (
        enabled
        eco-speed-kmh eco-current eco-watts eco-fw
        drive-speed-kmh drive-current drive-watts drive-fw
        sport-speed-kmh sport-current sport-watts sport-fw
        eco-om drive-om sport-om)
    {
        (write-setting 'secret-eco-om eco-om)
        (write-setting 'secret-drive-om drive-om)
        (write-setting 'secret-sport-om sport-om)
        (write-setting 'secret-enabled enabled)
        (write-setting 'secret-eco-speed-kmh eco-speed-kmh)
        (write-setting 'secret-eco-current eco-current)
        (write-setting 'secret-eco-watts eco-watts)
        (write-setting 'secret-eco-fw eco-fw)
        (write-setting 'secret-drive-speed-kmh drive-speed-kmh)
        (write-setting 'secret-drive-current drive-current)
        (write-setting 'secret-drive-watts drive-watts)
        (write-setting 'secret-drive-fw drive-fw)
        (write-setting 'secret-sport-speed-kmh sport-speed-kmh)
        (write-setting 'secret-sport-current sport-current)
        (write-setting 'secret-sport-watts sport-watts)
        (write-setting 'secret-sport-fw sport-fw)
    }
)

(defun save-apply-settings (speed current watts fw om s-speed s-current s-watts s-fw s-om)
    {
        (write-setting 'apply-speed speed)
        (write-setting 'apply-current current)
        (write-setting 'apply-watts watts)
        (write-setting 'apply-fw fw)
        (write-setting 'apply-om om)
        (write-setting 'secret-apply-speed s-speed)
        (write-setting 'secret-apply-current s-current)
        (write-setting 'secret-apply-watts s-watts)
        (write-setting 'secret-apply-fw s-fw)
        (write-setting 'secret-apply-om s-om)
    }
)

(defun save-gesture-settings (s-presses s-combo s-locked l-presses l-combo m-presses m-combo m-locked li-presses li-combo li-locked so-presses so-combo so-locked)
    {
        (write-setting 'secret-presses s-presses)
        (write-setting 'secret-combo s-combo)
        (write-setting 'secret-requires-lock s-locked)
        (write-setting 'lock-presses l-presses)
        (write-setting 'lock-combo l-combo)
        (write-setting 'mode-presses m-presses)
        (write-setting 'mode-combo m-combo)
        (write-setting 'mode-requires-lock m-locked)
        (write-setting 'light-presses li-presses)
        (write-setting 'light-combo li-combo)
        (write-setting 'light-requires-lock li-locked)
        (write-setting 'secret-off-presses so-presses)
        (write-setting 'secret-off-combo so-combo)
        (write-setting 'secret-off-requires-lock so-locked)
    }
)

(defun save-misc-settings (auto-light btn-speed-kmh mph bms secret-exit pin dash-power)
    {
        (write-setting 'power-pin dash-power)
        (write-setting 'light-on-boot auto-light)
        (write-setting 'button-speed-kmh btn-speed-kmh)
        (write-setting 'use-mph mph)
        (write-setting 'bms-soc-enable bms)
        (write-setting 'secret-exit-on-lock secret-exit)
        (write-setting 'app-pin pin)
    }
)

(defun save-light-offsets (thr thr-gain brk brk-gain)
    {
        (write-setting 'light-offset-thr thr)
        (write-setting 'light-gain-thr (if (> thr-gain 0.05) thr-gain 1.0)) ; never persist a near-zero/invalid gain
        (write-setting 'light-offset-brk brk)
        (write-setting 'light-gain-brk (if (> brk-gain 0.05) brk-gain 1.0))
    }
)

(defun save-rear-settings (enable auto-tail brake-mode)
    {
        (write-setting 'rear-light-enable enable)
        (write-setting 'auto-taillight auto-tail)
        (write-setting 'brake-light-mode brake-mode)
    }
)

(defun save-cruise-settings (enable delay deviation min-speed max-speed)
    { ; also toggled live from the Control tab (ctrl-cruise)
        (set 'cruise-enabled enable)
        (write-setting 'cruise-enabled enable)
        (write-setting 'cruise-delay delay)
        (write-setting 'cruise-deviation deviation)
        (write-setting 'cruise-min-speed min-speed)
        (write-setting 'cruise-max-speed max-speed)
    }
)

(defun save-alarm-settings (tone speed-threshold gyro-threshold voltage)
    {
        (write-setting 'alarm-tone tone)
        (write-setting 'alarm-speed-threshold speed-threshold)
        (write-setting 'alarm-gyro-threshold gyro-threshold)
        (write-setting 'alarm-voltage voltage)
    }
)

; UI restarts lisp after "model-ok" so the new model takes effect
(defun save-model (m)
    {
        (write-setting 'model (if (valid-model m) m 0))
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
        (restore-defaults)
        (finish-settings-save)
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
        (set 'cruise-enabled on)
        (write-setting 'cruise-enabled on)
        (if (not on) (cruise-cancel))
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

(defun send-state ()
    (send-data (str-merge
        "state "
        (if off "true " "false ")
        (if lock "true " "false ")
        (if light "true " "false ")
        (if unlock "true " "false ")
        (str-from-n speedmode "%d ")
        (str-from-n cur-batt "%.0f ")
        (str-from-n (get-vin) "%.1f ")
        (str-from-n (abs cur-speed-kmh) "%.1f ")
        (str-from-n (send-state-watts) "%.0f ")
        (str-from-n (send-state-whkm) "%.1f ")
        (str-from-n (send-state-range) "%.1f ")
        (str-from-n (send-state-amps) "%.1f ")
        (str-from-n (send-state-maxkmh) "%.0f ")
        (if cruising "true " "false ")
        (if cruise-enabled "true" "false")
    ))
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
(defun send-state-amps () (setup-current-in))

(defun send-state-watts () (* (get-vin) (setup-current-in)))

(defun send-state-whkm () {
        ; matches VESC Tool: (wh - wh_chg) / abs tacho distance, combined values
        (var dist-km (/ (get-dist-abs) 1000.0))
        (if (> dist-km 0.05)
            (/ (- (setup-wh) (setup-wh-chg)) dist-km)
            0.0
        )
})

; total usable battery Wh the same way mc_interface_get_battery_level does, so
; range = get-batt * this / wh-km reproduces VESC Tool's estimate. get-batt
; already carries the non-linear discharge curve.
(defun batt-wh-tot ()
        ; Li-ion assumed (scooter default, si-battery-type isn't a valid
        ; conf-get param in fw 7.0). Matches VESC Tool: 0.85 usable * 3.7 V/cell
        cur-wh-tot
)

(defun send-state-range () {
        (var whkm (send-state-whkm))
        (if (> whkm 0.1)
            (/ (* (get-batt) (batt-wh-tot)) whkm) ; VESC Tool: wh_batt_left / wh_km
            0.0
        )
})

; Reading a setting straight into a state line is the same two shapes ninety
; times over, and each spelled-out copy costs const heap.
(defun setting-bool (n) (if (read-setting n) "true " "false "))
(defun setting-num (n f) (str-from-n (read-setting n) f))

(defun send-settings ()
    {
        (send-data (str-merge
            "model "
            (setting-num 'model "%d")
        ))
        (sleep 0.05)
        ; misc goes early so the UI knows the km/h vs mph unit before it
        ; renders the speed fields that follow
        (send-data (str-merge
            "misc "
            (setting-bool 'light-on-boot)
            (setting-num 'button-speed-kmh "%.1f ")
            (setting-bool 'use-mph)
            (setting-bool 'bms-soc-enable)
            (setting-bool 'secret-exit-on-lock)
            (setting-num 'light-offset-thr "%.3f ")
            (setting-num 'light-gain-thr "%.3f ")
            (setting-num 'light-offset-brk "%.3f ")
            (setting-num 'light-gain-brk "%.3f ")
            (setting-num 'app-pin "%d ")
            (setting-num 'power-pin "%d")
        ))
        (sleep 0.05)
        (send-data (str-merge
            "general "
            (setting-bool 'software-adc)
            (setting-bool 'software-adc2)
            (setting-bool 'show-batt-in-idle)
            (setting-bool 'show-batt-idle-secret)
            (setting-num 'min-speed-kmh "%.1f ")
            (if (read-setting 'app-enable) "true" "false")
        ))
        (sleep 0.05)
        (send-data (str-merge
            "temps "
            (setting-num 'temp-warning-motor "%.1f ")
            (setting-num 'temp-warning-fet "%.1f")
        ))
        (sleep 0.05)
        (send-data (str-merge
            "modes "
            (setting-num 'eco-speed-kmh "%.1f ")
            (setting-num 'eco-current "%.2f ")
            (setting-num 'eco-watts "%.0f ")
            (setting-num 'eco-fw "%.1f ")
            (setting-num 'drive-speed-kmh "%.1f ")
            (setting-num 'drive-current "%.2f ")
            (setting-num 'drive-watts "%.0f ")
            (setting-num 'drive-fw "%.1f ")
            (setting-num 'sport-speed-kmh "%.1f ")
            (setting-num 'sport-current "%.2f ")
            (setting-num 'sport-watts "%.0f ")
            (setting-num 'sport-fw "%.1f ")
            (setting-num 'boot-mode "%d ")
            (setting-num 'eco-om "%.3f ")
            (setting-num 'drive-om "%.3f ")
            (setting-num 'sport-om "%.3f")
        ))
        (sleep 0.05)
        (send-data (str-merge
            "secret "
            (setting-bool 'secret-enabled)
            (setting-num 'secret-eco-speed-kmh "%.1f ")
            (setting-num 'secret-eco-current "%.2f ")
            (setting-num 'secret-eco-watts "%.0f ")
            (setting-num 'secret-eco-fw "%.1f ")
            (setting-num 'secret-drive-speed-kmh "%.1f ")
            (setting-num 'secret-drive-current "%.2f ")
            (setting-num 'secret-drive-watts "%.0f ")
            (setting-num 'secret-drive-fw "%.1f ")
            (setting-num 'secret-sport-speed-kmh "%.1f ")
            (setting-num 'secret-sport-current "%.2f ")
            (setting-num 'secret-sport-watts "%.0f ")
            (setting-num 'secret-sport-fw "%.1f ")
            (setting-num 'secret-eco-om "%.3f ")
            (setting-num 'secret-drive-om "%.3f ")
            (setting-num 'secret-sport-om "%.3f")
        ))
        (sleep 0.05)
        (send-data (str-merge
            "apply "
            (setting-bool 'apply-speed)
            (setting-bool 'apply-current)
            (setting-bool 'apply-watts)
            (setting-bool 'apply-fw)
            (setting-bool 'apply-om)
            (setting-bool 'secret-apply-speed)
            (setting-bool 'secret-apply-current)
            (setting-bool 'secret-apply-watts)
            (setting-bool 'secret-apply-fw)
            (if (read-setting 'secret-apply-om) "true" "false")
        ))
        (sleep 0.05)
        (send-data (str-merge
            "gesture "
            (setting-num 'secret-presses "%d ")
            (setting-num 'secret-combo "%d ")
            (setting-bool 'secret-requires-lock)
            (setting-num 'lock-presses "%d ")
            (setting-num 'lock-combo "%d ")
            (setting-num 'mode-presses "%d ")
            (setting-num 'mode-combo "%d ")
            (setting-bool 'mode-requires-lock)
            (setting-num 'light-presses "%d ")
            (setting-num 'light-combo "%d ")
            (setting-bool 'light-requires-lock)
            (setting-num 'secret-off-presses "%d ")
            (setting-num 'secret-off-combo "%d ")
            (setting-bool 'secret-off-requires-lock)
        ))
        (sleep 0.05)
        (send-data (str-merge
            "rear "
            (setting-bool 'rear-light-enable)
            (setting-bool 'auto-taillight)
            (setting-num 'brake-light-mode "%d")
        ))
        (sleep 0.05)
        (send-data (str-merge
            "cruise "
            (setting-bool 'cruise-enabled)
            (setting-num 'cruise-delay "%.1f ")
            (setting-num 'cruise-deviation "%.1f ")
            (setting-num 'cruise-min-speed "%.1f ")
            (setting-num 'cruise-max-speed "%.1f")
        ))
        (sleep 0.05)
        (send-data (str-merge
            "alarm "
            (setting-bool 'alarm-tone)
            (setting-num 'alarm-speed-threshold "%.1f ")
            (setting-num 'alarm-gyro-threshold "%.1f ")
            (setting-num 'alarm-voltage "%.1f")
        ))
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

(defun adc-input(buffer) ; Frame 0x65
    {
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

        (set 'dash-thr-raw (bufget-u8 uart-buf thr-idx)) ; raw physical throttle (before override)
        (set 'dash-brk-raw (bufget-u8 uart-buf brk-idx)) ; raw physical brake (before override)
        (var thr-raw-v (/ dash-thr-raw 77.2)) ; 255/3.3 = 77.2
        (var brk-raw-v (/ dash-brk-raw 77.2))

        ; Affine light compensation: corrected = (raw - offset) / gain.
        ; gain=1/offset=0 (uncalibrated default) makes this a no-op.
        (var throttle (if light (/ (- thr-raw-v light-offset-thr) light-gain-thr) thr-raw-v))
        (var brake (if light (/ (- brk-raw-v light-offset-brk) light-gain-brk) brk-raw-v))
        (if (< dash-thr-raw thr-rest) (set 'thr-rest dash-thr-raw))
        (if (< dash-brk-raw brk-rest) (set 'brk-rest dash-brk-raw))
        (set 'levers-active (or (> dash-thr-raw (+ thr-rest 10))
                                (> dash-brk-raw (+ brk-rest 10))))

        (if (< throttle 0.0) (setq throttle 0.0))
        (if (> throttle 3.3) (setq throttle 3.3))
        (if (< brake 0.0) (setq brake 0.0))
        (if (> brake 3.3) (setq brake 3.3))

        (set 'thr-corr-v throttle) ; pre-mask - cruise release detection needs it

        ; cruise capture-assist: hold the throttle signal at 0 from activation
        ; until the lever is physically released, so the app captures the speed
        ; we were actually riding instead of the lower post-release speed
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
        (var braking (and (not off) (> (get-adc-decoded 1) adc-touch)))
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
    (if (and cruise-enabled (not off) (not lock))
        {
            (var thr (get-adc-decoded 0))
            (var brk (get-adc-decoded 1))
            (if cruising
                {
                    ; Released = the lever is back under what the firmware counts
                    ; as "no throttle". The dashboard value is masked to zero until
                    ; release, so that path needs the pre-mask voltage; a lever on
                    ; the pin is never masked and reads true straight from the app.
                    ; Safety timeout after 3 s so the throttle can never stay masked
                    ; if the lever simply isn't released.
                    (if (or (if software-adc
                                (< thr-corr-v cruise-v1-start)
                                (<= thr adc-touch))
                            (> (secs-since cruise-shown-time) 3))
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
                    (set-current 0)
                    ; rcode canset
                    ;(loopforeach i (can-list-devs)
                    ;    (canset-current i 0)
                    ;)
                }
            )
            (if (app-is-output-disabled) ; Enable output when scooter is turned on
                (app-disable-output 0)
            )
        )

        (trap (build-dash-frame))
        (trap (app-run-todo))
        (trap (app-cache-update))
        (trap (handle-taillight))
        (if dash-power-held (gpio-write dash-power-held (if off 0 1)))
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

(defun build-dash-frame () ; contents of the 0x64 reply
    {
        (var current-speed (abs cur-speed-kmh))
        (var disp-speed (+ (if use-mph (* current-speed 0.621371) current-speed) 0.5)) ; rounded for the dash
        (var battery cur-batt)

        ; mode field (1=drive, 2=eco, 4=sport, 8=charge, 16=off, 32=lock)
        (if off
            (bufset-u8 tx-frame tx-base 16)
            (if lock
                (bufset-u8 tx-frame tx-base 32) ; lock display
                (if (or (> (get-temp-fet) temp-warning-fet) (> (get-temp-mot) temp-warning-motor) bms-warn) ; temp icon will show up above warning degree
                    (bufset-u8 tx-frame tx-base (+ 128 speedmode))
                    (bufset-u8 tx-frame tx-base speedmode)
                )
            )
        )

        ; batt field
        (if lock
            (bufset-u8 tx-frame (+ tx-base 1) 0) ; lock display
            (bufset-u8 tx-frame (+ tx-base 1) battery)
        )

        ; light field - the G2 packs headlight, park and cruise into one byte
        (if (not off)
            (if (> alarm 4)
                (bufset-u8 tx-frame (+ tx-base 2) 1) ; alarm on
                (bufset-u8 tx-frame (+ tx-base 2) (if (= model 3)
                    (+ (if light 1 0) (if lock 2 0) (if cruising 4 0))
                    (if light 1 0)
                ))
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
                        (bufset-u8 tx-frame (+ tx-base 4) battery))
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
        (if (> feedback 0)
            {
                (bufset-u8 tx-frame (+ tx-base 3) 1)
                (set 'feedback (- feedback 1))
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

(defun update-dash(buffer) { (seal-dash-frame) (uart-write tx-frame) })

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

(defun app-clamp16 (v)
    (cond ((> v 32767) 32767) ((< v -32768) -32768) (t (to-i v)))
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
            (set 'cur-cell-mv (app-clamp16 (/ (* cur-vin 1000) cur-cells)))
            (build-app-frame app-f-b4 0xb4 6)
            (build-app-frame app-f-7b 0x7b 6)
            (build-app-frame-from app-f-33 0x22 0x33 4 true)
            (build-app-frame-from app-f-35 0x22 0x35 2 true)
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
                ((= app-slow-step 2) {
                    (build-app-frame-from app-f-31 0x22 0x31 2 true)
                    (build-app-frame-from app-f-40 0x22 0x40 30 true)
                    (build-app-frame app-f-25 0x25 2)
                    (build-app-frame app-f-3b 0x3b 2)
                    (build-app-frame app-f-75 0x75 2)
                })
                (t (if b0-wanted {
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
(defun app-cell-mv () cur-cell-mv)

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
    (let ((ab (app-pend-buf)))
        {
            (set 'app-pend false)
            (seal-dash-frame)
            (if (eq ab nil)
                { (uart-write tx-frame) (nb-send pend-dev pend-src 0x04 pend-reg pend-n (= pend-dev 0x22)) }
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
            )
        }
    )
)

(defun build-app-frame-from (buf from reg n bms)
    (let ((crc (+ n from app-dst 0x04 reg)))
        {
            (bufset-u16 buf 0 0x5aa5)
            (bufset-u8 buf 2 n)
            (bufset-u8 buf 3 from)
            (bufset-u8 buf 4 app-dst)
            (bufset-u8 buf 5 0x04)
            (bufset-u8 buf 6 reg)
            (looprange i 0 (/ n 2) {
                (var w (if bms (xm-bms-word (+ reg i)) (nb-word (+ reg i))))
                (var lo (bitwise-and w 0xFF))
                (var hi (bitwise-and (shr w 8) 0xFF))
                (bufset-u8 buf (+ 7 (* i 2)) lo)
                (bufset-u8 buf (+ 8 (* i 2)) hi)
                (setq crc (+ crc lo hi))
            })
            (setq crc (bitwise-xor crc 0xFFFF))
            (bufset-u8 buf (+ n 7) (bitwise-and crc 0xFF))
            (bufset-u8 buf (+ n 8) (bitwise-and (shr crc 8) 0xFF))
        }
    )
)

(defun build-app-frame (buf reg n) (build-app-frame-from buf 0x20 reg n false))

(defun build-quick ()
    (let ((sum 0))
        {
            (looprange i 0 26 {
                (var w (nb-word (+ 0xb0 i)))
                (var lo (bitwise-and w 0xFF))
                (var hi (bitwise-and (shr w 8) 0xFF))
                (bufset-u8 quick-buf (* i 2) lo)
                (bufset-u8 quick-buf (+ (* i 2) 1) hi)
                (setq sum (+ sum lo hi))
            })
            (set 'quick-sum sum)
        }
    )
)
(defun app-cap-mah () cur-cap)

; NB_INF_BOOL: bit0 speed limited, bit1 locked, bit2 buzzer, bit11 activated
(defun app-bool-word ()
    (+ (if (= speedmode 2) 1 0) (if lock 2 0) (if (> alarm 0) 4 0) 2048)
)

(defun app-workmode () (cond ((= speedmode 2) 1) ((= speedmode 4) 2) (t 0)))

; Writes shared by both protocols. Speed limits are acknowledged but never
; applied - the app must not silently overwrite the configured profiles.
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
                (build-app-frame app-f-7b 0x7b 6)
            })))
        ((= reg 0x7c) (let ((v (!= val 0)))
            (if (not (eq v cruise-enabled)) {
                (set 'cruise-enabled v)
                (build-app-frame app-f-7b 0x7b 6)
                (set 'app-todo (bitwise-or app-todo 1))
            })))
        ((= reg 0x7d) (let ((v (!= val 0)))
            (if (not (eq v auto-taillight)) {
                (set 'auto-taillight v)
                (build-app-frame app-f-7b 0x7b 6)
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
                (build-app-frame app-f-7b 0x7b 6)
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
        ((= reg 0xb3) (+ (bitwise-and (to-i cur-batt) 0xFF) (shl (bitwise-and (to-i cur-batt) 0xFF) 8)))
        ((= reg 0xb4) (to-i cur-batt))
        ((or (= reg 0xb5) (= reg 0xb6)) (app-speed-01))
        ((= reg 0xb7) (bitwise-and cur-odo 0xFFFF))
        ((= reg 0xb8) (shr cur-odo 16))
        ((= reg 0xb9) (app-clamp16 (/ (app-trip-m) 10)))
        ((= reg 0xba) (to-i (secs-since app-boot-time)))
        ((= reg 0xbb) (app-fet-01))
        ((= reg 0xbc) (+ (bitwise-and (to-i cur-maxkmh) 0xFF) ; low: current limit, high: full speed
                         (shl (bitwise-and (to-i cur-maxkmh) 0xFF) 8)))
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
            ((= reg 0x7c) (if cruise-enabled 1 0))
            ((= reg 0x7d) (if auto-taillight 2 0)) ; the app writes 2 for on
            ((or (= reg 0x24) (= reg 0x25)) (app-range-10m))
            ((= reg 0x3a) (to-i (secs-since app-boot-time)))
            ((= reg 0x3b) (to-i (secs-since app-boot-time)))
            ((and (>= reg 0x10) (< reg 0x17)) (app-word app-serial (- reg 0x10)))
            ((and (>= reg 0x17) (< reg 0x1a)) (app-word app-pin-buf (- reg 0x17)))
            ((= reg 0x1b) (get-fault))
            ((= reg 0x1c) (if (> alarm 0) 9 0)) ; ALARM_CODE_LOCKED
            ((= reg 0x1d) (app-bool-word))
            ((= reg 0x1f) (app-workmode))
            ((= reg 0x22) (to-i cur-batt))
            ((= reg 0x26) (app-speed-01))
            ((= reg 0x29) (bitwise-and cur-odo 0xFFFF))
            ((= reg 0x2a) (shr cur-odo 16))
            ((= reg 0x2f) (app-clamp16 (/ (app-trip-m) 10)))
            ((= reg 0x32) (bitwise-and cur-runtime 0xFFFF))
            ((= reg 0x33) (shr cur-runtime 16))
            ((= reg 0x3e) (app-fet-01))
            ((= reg 0x41) (app-clamp16 (* cur-mot 10)))
            ((= reg 0x47) (app-volt-cv))
            ((= reg 0x65) (app-speed-01))
            ((or (= reg 0x66) (= reg 0x67) (= reg 0x68)) app-ver)
            ((or (= reg 0x72) (= reg 0x73) (= reg 0x74)) (app-clamp16 (* cur-maxkmh 10)))
            ((= reg 0x7a) (if light 1 0))
            ((= reg 0x90) (if light 1 0))
            ((or (= reg 0x91) (= reg 0x92)) (if alarm-tone 1 0))
            (t 0)
        )
    )
)

(defun nb-send (from dst cmd reg n bms) ; frame: 5A A5 len src dst cmd arg payload crc
    (let ((buf (array-create (+ n 9))) (crc 0))
        {
            (trap {
            (bufset-u16 buf 0 0x5aa5)
            (bufset-u8 buf 2 n)
            (bufset-u8 buf 3 from)
            (bufset-u8 buf 4 dst)
            (bufset-u8 buf 5 cmd)
            (bufset-u8 buf 6 reg)
            (setq crc (+ n from dst cmd reg)) ; summed as the frame is built
            (if (= cmd 0x05) ; a read answers with 0x04, a write acks with 0x05
                {
                    (bufset-u8 buf 7 1) ; write ack payload
                    (setq crc (+ crc 1))
                }
                (if (and (not bms) (= reg 0xb0) (= n 52)) ; the app's bulk read, prebuilt
                    {
                        (build-quick)
                        (bufcpy buf 7 quick-buf 0 52)
                        (setq crc (+ crc quick-sum))
                    }
                    (looprange i 0 (/ n 2) {
                        (var w (if bms (xm-bms-word (+ reg i)) (nb-word (+ reg i))))
                        (var lo (bitwise-and w 0xFF))
                        (var hi (bitwise-and (shr w 8) 0xFF))
                        (bufset-u8 buf (+ 7 (* i 2)) lo)
                        (bufset-u8 buf (+ 8 (* i 2)) hi)
                        (setq crc (+ crc lo hi))
                    })
                )
            )
            (setq crc (bitwise-xor crc 0xFFFF))
            (bufset-u8 buf (+ n 7) (bitwise-and crc 0xFF))
            (bufset-u8 buf (+ n 8) (bitwise-and (shr crc 8) 0xFF))
            (uart-write buf)
            })
            (free buf)
        }
    )
)

(defun nb-app-frame (dev src cmd reg len)
    (cond
        ; a read carries the wanted byte count as its only payload byte; some
        ; requests omit it entirely, in which case one register is meant
        ((= cmd 0x01) (let ((n (if (> len 0) (bufget-u8 uart-buf 4) 2))) {
            (if (or (< n 2) (> n 64)) (setq n 2))
            (setq n (bitwise-and n 0xFE))
            (if (!= src app-dst) (set 'app-dst src))
            (set 'quick-used true)
            (if (and (= reg 0xb0) (= n 52)) (set 'b0-wanted true))
            ; held for the next dash answer; one arriving while another waits is
            ; dropped and the app re-asks, which is cheaper than a transmission
            (if (and (not app-pend) (not (and (>= n 20) levers-active))) {
                (set 'pend-dev dev) (set 'pend-src src)
                (set 'pend-reg reg) (set 'pend-n n)
                (set 'app-pend true)
            })
        }))
        ((or (= cmd 0x02) (= cmd 0x03)) {
            (if (and (> len 0) (!= dev 0x22))
                (app-write reg (if (> len 1) ; controls send one byte, the checksum follows it
                    (+ (bufget-u8 uart-buf 4) (shl (bufget-u8 uart-buf 5) 8))
                    (bufget-u8 uart-buf 4)
                ))
            )
            (nb-send dev src 0x05 reg 1 false)
        })
    )
)

; Xiaomi: single device byte, 0x20/0x23 for the ESC and 0x22/0x25 for the BMS.
; Speed is metres/hour here, so it saturates the u16 at 65 km/h.
(defun xm-word (reg)
    (cond
        ((and (>= reg 0x10) (< reg 0x17)) (app-word app-serial (- reg 0x10)))
        ((and (>= reg 0x17) (< reg 0x1a)) (app-word app-pin-buf (- reg 0x17)))
        ((= reg 0x1a) app-ver)
        ((= reg 0x25) (app-range-10m))
        ((= reg 0x3b) (to-i (secs-since app-boot-time)))
        ((= reg 0x3e) (app-fet-01))
        ((= reg 0x67) app-ver)
        ((= reg 0x75) (if (= speedmode 2) 1 0))
        ((= reg 0x7a) (if light 1 0))
        ((= reg 0x7b) (cond ((= speedmode 1) 1) ((= speedmode 4) 2) (t 0)))
        ((= reg 0x77) (if unlock 1 0))
        ((= reg 0x76) (if light 1 0))
        ((= reg 0x7c) (if cruise-enabled 1 0))
        ((= reg 0x7d) (if auto-taillight 2 0))
        ((= reg 0xb0) (get-fault))
        ((= reg 0xb4) (to-i cur-batt))
        ((or (= reg 0xb5) (= reg 0xb6)) (app-clamp16 (* (abs cur-speed-kmh) 1000)))
        ((= reg 0xb7) (bitwise-and cur-odo 0xFFFF))
        ((= reg 0xb8) (shr cur-odo 16))
        ((= reg 0xb9) (app-clamp16 (/ (app-trip-m) 10)))
        ((= reg 0xbb) (app-fet-01))
        (t 0)
    )
)

(defun xm-bms-word (reg)
    (cond
        ((and (>= reg 0x10) (< reg 0x17)) (app-word app-serial (- reg 0x10)))
        ((= reg 0x17) app-ver)
        ((= reg 0x18) (app-cap-mah))
        ((= reg 0x20) 0x3021) ; 7 bit year from 2000, 4 bit month, 5 bit day
        ((= reg 0x31) (app-clamp16 (/ (* cur-batt cur-cap) 100)))
        ((= reg 0x32) (to-i cur-batt))
        ((= reg 0x33) (app-amp-ca))
        ((= reg 0x34) (app-volt-cv))
        ((= reg 0x35) (let ((tc (bitwise-and (+ (to-i cur-fet) 20) 0xFF))) ; both sensors +20
                          (+ tc (shl tc 8))))
        ((= reg 0x3b) 100) ; health
        ((and (>= reg 0x40) (< reg 0x4a)) (app-cell-mv))
        (t 0)
    )
)

(defun xm-send (dev reg n bms) ; frame: 55 AA len addr cmd arg payload crc
    (let ((buf (array-create (+ n 8))) (crc 0))
        {
            (trap {
            (bufset-u16 buf 0 0x55aa)
            (bufset-u8 buf 2 (+ n 2))
            (bufset-u8 buf 3 dev)
            (bufset-u8 buf 4 0x01)
            (bufset-u8 buf 5 reg)
            (setq crc (+ n 2 dev 0x01 reg)) ; summed as the frame is built
            (looprange i 0 (/ n 2) {
                (var w (if bms (xm-bms-word (+ reg i)) (xm-word (+ reg i))))
                (var lo (bitwise-and w 0xFF))
                (var hi (bitwise-and (shr w 8) 0xFF))
                (bufset-u8 buf (+ 6 (* i 2)) lo)
                (bufset-u8 buf (+ 7 (* i 2)) hi)
                (setq crc (+ crc lo hi))
            })
            (setq crc (bitwise-xor crc 0xFFFF))
            (bufset-u8 buf (+ n 6) (bitwise-and crc 0xFF))
            (bufset-u8 buf (+ n 7) (bitwise-and (shr crc 8) 0xFF))
            (uart-write buf)
            })
            (free buf)
        }
    )
)

(defun xm-app-frame (dev cmd reg len)
    (cond
        ((= cmd 0x01) (let ((n (bitwise-and (bufget-u8 uart-buf 3) 0xFE)))
            (if (and (> n 1) (<= n 64)) (xm-send (if (= dev 0x22) 0x25 0x23) reg n (= dev 0x22)))
        ))
        ((= cmd 0x03) (if (!= dev 0x22)
            (app-write reg (if (> len 3)
                (+ (bufget-u8 uart-buf 3) (shl (bufget-u8 uart-buf 4) 8))
                (bufget-u8 uart-buf 3)
            ))
        ))
    )
)


; The G2 handlebar has a horn and a turn signal button, and reports them one
; byte past the brake: 0x40 nothing pressed, 0x50 turn signal held for three
; seconds, 0x60 horn. The dash drives its own turn signal lamps, so the hold is
; free to toggle cruise; the horn has no VESC output and sounds the dash buzzer.
(defun g2-extras (len)
    (if (>= len 4)
        (let ((a (bufget-u8 uart-buf 7)))
            {
                (if (= a 0x60) (set 'feedback 1)) ; refreshed while held
                (if (and (= a 0x50) (!= g2-aux 0x50) (not off) (not lock)) {
                    (set 'cruise-enabled (not cruise-enabled))
                    (set 'feedback 2)
                    (set 'app-todo (bitwise-or app-todo 1)) ; the flash write waits for the feature loop
                })
                (set 'g2-aux a)
            }
        )
    )
)

(defun read-frames-g30()
    (loopwhile t {
        (trap ; a parse error must not kill the reader thread
            (loopwhile t
                {
                    (uart-read-bytes uart-buf 3 0)
                    ; slide a byte at a time until the header lines up - a three
                    ; byte window can stay misaligned and drop every lever frame
                    (loopwhile (!= (bufget-u16 uart-buf 0) 0x5aa5) {
                        (bufset-u8 uart-buf 0 (bufget-u8 uart-buf 1))
                        (bufset-u8 uart-buf 1 (bufget-u8 uart-buf 2))
                        (uart-read-bytes uart-buf 1 2)
                    })
                    (var len (bufget-u8 uart-buf 2))
                    (if (< len 59) ; len+6 must fit the 64 byte buffer, len 0 is a valid read
                        {
                            (uart-read-bytes uart-buf (+ len 6) 0) ; rest of the frame, overwrites the header
                            (var dst (bufget-u8 uart-buf 1))
                            (var code (bufget-u8 uart-buf 2))
                            ; Verify only what we act on. The dash sends a steady
                            ; stream of 0x61 we have no use for, and every byte
                            ; checked costs interpreter time the lever path needs.
                            (if (or (= code 0x64) (= code 0x65)
                                    (and (or (= dst 0x20) (= dst 0x22))
                                         (or (= code 0x01) (= code 0x02) (= code 0x03))))
                                {
                                    (var crc len)
                                    (looprange i 0 (+ len 4) (setq crc (+ crc (bufget-u8 uart-buf i))))
                                    (setq crc (bitwise-xor crc 0xFFFF))
                                    (if (= (bufget-u16 uart-buf (+ len 4))
                                           (bitwise-and (+ (shr crc 8) (shl crc 8)) 65535))
                                        (cond
                                                ; 0x61 is a lever frame the dash switches to while
                                                ; it serves an app - same payload layout as 0x65, and
                                                ; the most frequent of the three in that state
                                                ((= code 0x61)
                                                    (if (and (or software-adc software-adc2) (>= len 3))
                                                        (adc-input uart-buf)
                                                    )
                                                )
                                                ((= code 0x65)
                                                    (if (and (or software-adc software-adc2) (>= len 3)) ; frame must carry the lever bytes
                                                        (adc-input uart-buf)
                                                    )
                                                )
                                                ((= code 0x64) {
                                                    ; 0x64 carries throttle and brake at the same
                                                    ; offsets as 0x65. The dash halves its 0x65 rate
                                                    ; while serving an app but keeps sending 0x64, so
                                                    ; ignoring these threw away half the lever data
                                                    ; exactly when it was scarce.
                                                    (if (and (or software-adc software-adc2) (>= len 7))
                                                        (adc-input uart-buf)
                                                    )
                                                    ; only off 0x64 - the horn and turn signal do not
                                                    ; need the 40/s the lever frames arrive at
                                                    (if (= model 3) (g2-extras len))
                                                    (if (> (secs-since dash-tx-time) dash-tx-iv) {
                                                        (set 'dash-tx-time (systime))
                                                        (if app-pend
                                                            (send-dash-and-app)
                                                            (update-dash uart-buf)
                                                        )
                                                    })
                                                })
                                                (t (if app-enable
                                                    (trap (nb-app-frame dst (bufget-u8 uart-buf 0) code (bufget-u8 uart-buf 3) len))
                                                ))
                                        )
                                    )
                                }
                            )
                        }
                    )
                }
            )
        )
        (sleep 0.005) ; only reached after an error
    })
)

(defun read-frames-m365()
    (loopwhile t {
        (trap ; a parse error must not kill the reader thread
            (loopwhile t
                {
                    (uart-read-bytes uart-buf 3 0)
                    ; slide a byte at a time until the header lines up - a three
                    ; byte window can stay misaligned and drop every lever frame
                    (loopwhile (!= (bufget-u16 uart-buf 0) 0x55aa) {
                        (bufset-u8 uart-buf 0 (bufget-u8 uart-buf 1))
                        (bufset-u8 uart-buf 1 (bufget-u8 uart-buf 2))
                        (uart-read-bytes uart-buf 1 2)
                    })
                    (if (= (bufget-u16 uart-buf 0) 0x55aa)
                        {
                            (var len (bufget-u8 uart-buf 2))
                            (var crc len)
                            (if (and (> len 0) (< len 60)) ; max 64 bytes
                                {
                                    (uart-read-bytes uart-buf (+ len 4) 0)
                                    (looprange i 0 len
                                        (setq crc (+ crc (bufget-u8 uart-buf i))))
                                    (if (=(+(shl(bufget-u8 uart-buf (+ len 2))8) (bufget-u8 uart-buf (+ len 1))) (bitwise-xor crc 0xFFFF))
                                        {
                                            (if (and (= (bufget-u8 uart-buf 1) 0x65) (or software-adc software-adc2) (>= len 2)) ; frame must actually carry the throttle/brake bytes
                                                (adc-input uart-buf)
                                            )
                                            ; the dash also addresses 0x20 - only the command
                                            ; separates its frames from app register access
                                            (let ((cmd (bufget-u8 uart-buf 1)))
                                                (if (or (= cmd 0x01) (= cmd 0x03))
                                                    (trap (xm-app-frame (bufget-u8 uart-buf 0) cmd (bufget-u8 uart-buf 2) len))
                                                    (update-dash uart-buf) ; dash expects a reply on every frame
                                                )
                                            )
                                        }
                                    )
                                }
                            )
                        }
                    )
                }
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

; Button gestures. Matching order: power-on, secret, lock, modes, light.
(defun handle-button()
    {
        (var thr (get-adc-decoded 0))
        (var brk (get-adc-decoded 1))
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
                (toggle-lock)
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
        (var thr (get-adc-decoded 0))
        (var brk (get-adc-decoded 1))
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
        (loopforeach id (can-list-devs)
            (rcode-run-noret id `(foc-play-tone ,channel ,freq ,voltage))
        )
    }
)

(defun stop-tone()
    {
        (foc-play-stop)
        (loopforeach id (can-list-devs)
            (rcode-run-noret id '(foc-play-stop))
        )
    }
)

(defun get-lowest-speed()
    {
        (var speed (get-speed))
        (loopforeach i (can-list-devs)
            (trap { ; a CAN device dropping off the bus must not break speed reads
                (var can-speed (canget-speed i))
                (if (< can-speed speed)
                    (set 'speed can-speed)
                )
            })
        )

        speed
    }
)

; finds gyro that does not respond with (0,0,0)
(defunret get-gyro()
    {
        (var gyro (get-imu-gyro))
        (if (and (= (length gyro) 3)
                (or (> (abs (ix gyro 0)) 0)
                (> (abs (ix gyro 1)) 0)
                (> (abs (ix gyro 2)) 0)))
            (return gyro)
        )

        (loopforeach i (can-list-devs)
            {
                (var can-gyro (rcode-run i 0.5 '(get-imu-gyro)))

                (if (and (eq (type-of can-gyro) 'type-list)
                        (= (length can-gyro) 3)
                        (or (> (abs (ix can-gyro 0)) 0)
                        (> (abs (ix can-gyro 1)) 0)
                        (> (abs (ix can-gyro 2)) 0)))
                    (return can-gyro)
                )
            }
        )

        gyro
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
                    (button-apply button-state)
                    (if (and (not off) (<= (abs (get-speed)) button-safety-speed))
                        (handle-lever-gestures)
                    )
                    (handle-features)
                })
            }
        )
    }
)

(defun button-apply(button)
    {
        (var time-passed (- (systime) press-time))
        (var is-active (or off (<= (get-speed) button-safety-speed)))

        (if (> time-passed 2500) ; after 2500 ms
            (if button ; check button is still pressed
                (if (> time-passed 6000) ; long press after 6000 ms
                    {
                        (if is-active
                            (handle-holding-button)
                        )
                        (reset-button) ; reset button
                    }
                )
                (if (> presses 0) ; if presses > 0
                    {
                        (if is-active
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
            (def app-pin-buf (array-create 6))
            (def quick-buf (array-create 52))
            (def app-f-b0 (array-create 61)) ; prepared replies, sent as-is
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
            (set 'cur-cells (let ((n (conf-get 'si-battery-cells))) (if (> n 0) n 10)))
            (set 'cur-wh-tot (* 0.85 (conf-get 'si-battery-ah) (* 3.7 (conf-get 'si-battery-cells))))
            (set 'cur-cap (app-clamp16 (* (conf-get 'si-battery-ah) 1000)))
            ; timestamps captured at load are frozen into the image - reset them
            ; here or the first measurement after a boot compares against a
            ; reference from whenever the image was written
            (set 'last-rx (systime))
            (set 'app-cache-time (systime))
            (set 'app-slow-time (systime))
            (set 'app-reply-time (systime))
            (set 'dash-tx-time (systime))
            (set 'press-time (systime))
            (set 'alarm-time (systime))
            (set 'lever-since (systime))
            (set 'blink-since (systime))
            (set 'cruise-since (systime))
            (set 'cruise-shown-time (systime))
            (set 'calib-since (systime))
            (app-build-serial)
            (app-build-pin)
            (build-app-frame app-f-1a 0x1a 2) ; constant, built once
            (build-app-frame app-f-da 0xda 12)
            (set 'app-boot-time (systime))

            (if (= model 1) {
                (define tx-frame (array-create 14))
                (bufset-u16 tx-frame 0 0x55AA) ;Xiaomi protocol
                (bufset-u16 tx-frame 2 0x0821)
                (bufset-u16 tx-frame 4 0x6400) ; Packet is from ESC to BLE
                (set 'tx-base 6)
                (set 'thr-idx 4)
                (set 'brk-idx 5)
            } {
                (define tx-frame (array-create (if (= model 3) 17 15)))
                (bufset-u16 tx-frame 0 0x5AA5) ;Ninebot protocol
                (bufset-u8 tx-frame 2 (if (= model 3) 0x08 0x06)) ;Payload length
                (bufset-u16 tx-frame 3 0x2021) ; Packet is from ESC to BLE
                (bufset-u16 tx-frame 5 0x6400) ; Packet is from ESC to BLE
                ; the G2 reply carries two more payload bytes, both constant -
                ; what they mean is not known, the reference sends them fixed too
                (if (= model 3) {
                    (bufset-u8 tx-frame 13 0x06)
                    (bufset-u8 tx-frame 14 0x2e)
                })
                (set 'tx-base 7)
                (set 'thr-idx 5)
                (set 'brk-idx 6)
            })

            (looprange i 2 tx-base (set 'tx-hdr-sum (+ tx-hdr-sum (bufget-u8 tx-frame i))))

            ; dash answer plus each app answer size - the dash frame is two bytes
            ; longer on the G2, so they can only be sized once it exists
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

            (apply-software-adc)

            ; Apply mode on start-up
            (apply-mode)

            ; Spawn UART reading frames thread
            (if (= model 1) ; 500 words: app register replies allocate and nest deeper
                (spawn 500 read-frames-m365)
                (spawn 500 read-frames-g30)
            )
            (button-logic) ; Start button logic in main thread - this will block the main thread
        })
})

@const-end

; Without an image the firmware reparses the whole script on every boot, and it
; rewrites the const heap from the same base pointer each time - the second boot
; then collides with the first. With one, main is found in the restored
; environment and only (main) runs.
(image-save)
(main)
