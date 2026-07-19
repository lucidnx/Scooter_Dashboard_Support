; VESC Scooter Support lisp script v2.0 by Izuna, AKA13 and Netzpfuscher
; Supports G30 (Ninebot), M365/1S/PRO2 (Xiaomi) dashboards and Slave ESCs - model is set in the package UI
; Tested with VESC 7.00 on Spintend Ubox Single 85 200

; -> Installation
; UART Wiring: red=5V black=GND yellow=COM-TX (UART-HDX) green=COM-RX (button)+3.3V with 1K Resistor
; Guide (German): https://rollerplausch.com/threads/vesc-controller-einbau-1s-pro2-g30.6032/

(def software-adc true)
(def min-adc-throttle 0.1)
(def min-adc-brake 0.1)
(def temp-warning-motor 100) ; temperature warning for motor in degree celsius
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
(def light-offset-thr 0.0) ; volts added to throttle while the headlight is on
(def light-offset-brk 0.0) ; volts added to brake while the headlight is on
(def boot-mode 1) ; speed mode applied at boot (1=drive, 2=eco, 4=sport)

; Display / battery
(def use-mph false) ; dash shows mph instead of km/h
(def bms-soc-enable false) ; battery % from a VESC BMS when one reports

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

; lever-only gesture state (gestures configured with 0 presses)
(def lever-state 0)
(def lever-since (systime))
(def lever-armed true)

; cached telemetry - refreshed at ~16 Hz by the button thread so the
; per-frame dash reply doesn't run CAN queries and allocations itself
(def cur-speed-kmh 0.0)
(def cur-batt 0.0)


; BMS state
(def bms-active false)
(def bms-warn false)

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

@const-start

(def settings-version 308i32)

; Persistent settings: (label . (eeprom-offset type))
(def eeprom-addrs '(
    (ver-code              . (0 i))
    (software-adc          . (1 b))
    (min-adc-throttle      . (2 f))
    (min-adc-brake         . (3 f))
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
    (secret-exit-on-lock   . (77 b))
    (light-offset-thr      . (78 f))
    (light-offset-brk      . (79 f))
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
    (and (not (eq m nil)) (>= m 0) (<= m 2))
)

(defun write-secret-mode-toggles () ; settings added in v303
    {
        (write-setting 'secret-apply-speed true)
        (write-setting 'secret-apply-current true)
        (write-setting 'secret-apply-watts true)
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
        (write-setting 'min-adc-throttle 0.1)
        (write-setting 'min-adc-brake 0.1)
        (write-setting 'temp-warning-motor 100.0)
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
        (if (not-eq ver settings-version)
            (cond
                ((eq ver 300i32) { ; upgrades only write the added settings, everything else is kept
                    (restore-gesture-apply-defaults)
                    (write-setting 'ver-code settings-version)
                })
                ((eq ver 301i32) {
                    (write-setting 'secret-apply-fw true)
                    (write-secret-mode-toggles)
                    (write-remap-defaults)
                    (write-v305-defaults)
                    (write-v306-defaults)
                    (write-v307-defaults)
                    (write-v308-defaults)
                    (write-setting 'ver-code settings-version)
                })
                ((eq ver 302i32) {
                    (write-secret-mode-toggles)
                    (write-remap-defaults)
                    (write-v305-defaults)
                    (write-v306-defaults)
                    (write-v307-defaults)
                    (write-v308-defaults)
                    (write-setting 'ver-code settings-version)
                })
                ((eq ver 303i32) {
                    (write-remap-defaults)
                    (write-v305-defaults)
                    (write-v306-defaults)
                    (write-v307-defaults)
                    (write-v308-defaults)
                    (write-setting 'ver-code settings-version)
                })
                ((eq ver 304i32) {
                    (write-v305-defaults)
                    (write-v306-defaults)
                    (write-v307-defaults)
                    (write-v308-defaults)
                    (write-setting 'ver-code settings-version)
                })
                ((eq ver 305i32) {
                    (write-v306-defaults)
                    (write-v307-defaults)
                    (write-v308-defaults)
                    (write-setting 'ver-code settings-version)
                })
                ((eq ver 306i32) {
                    (write-v307-defaults)
                    (write-v308-defaults)
                    (write-setting 'ver-code settings-version)
                })
                ((eq ver 307i32) {
                    (write-v308-defaults)
                    (write-setting 'ver-code settings-version)
                })
                (t (restore-defaults))
            )
        )

        (set 'software-adc (read-setting 'software-adc))
        (set 'min-adc-throttle (read-setting 'min-adc-throttle))
        (set 'min-adc-brake (read-setting 'min-adc-brake))
        (set 'temp-warning-motor (read-setting 'temp-warning-motor))
        (set 'temp-warning-fet (read-setting 'temp-warning-fet))
        (set 'show-batt-in-idle (read-setting 'show-batt-in-idle))
        (set 'show-batt-idle-secret (read-setting 'show-batt-idle-secret))
        (set 'min-speed (read-setting 'min-speed-kmh))
        (set 'alarm-tone (read-setting 'alarm-tone))
        (set 'alarm-speed-threshold (read-setting 'alarm-speed-threshold))
        (set 'alarm-gyro-threshold (read-setting 'alarm-gyro-threshold))
        (set 'alarm-voltage (read-setting 'alarm-voltage))
        (set 'eco-speed (/ (read-setting 'eco-speed-kmh) 3.6))
        (set 'eco-current (read-setting 'eco-current))
        (set 'eco-watts (read-setting 'eco-watts))
        (set 'eco-fw (read-setting 'eco-fw))
        (set 'drive-speed (/ (read-setting 'drive-speed-kmh) 3.6))
        (set 'drive-current (read-setting 'drive-current))
        (set 'drive-watts (read-setting 'drive-watts))
        (set 'drive-fw (read-setting 'drive-fw))
        (set 'sport-speed (/ (read-setting 'sport-speed-kmh) 3.6))
        (set 'sport-current (read-setting 'sport-current))
        (set 'sport-watts (read-setting 'sport-watts))
        (set 'sport-fw (read-setting 'sport-fw))
        (set 'secret-enabled (read-setting 'secret-enabled))
        (set 'secret-eco-speed (/ (read-setting 'secret-eco-speed-kmh) 3.6))
        (set 'secret-eco-current (read-setting 'secret-eco-current))
        (set 'secret-eco-watts (read-setting 'secret-eco-watts))
        (set 'secret-eco-fw (read-setting 'secret-eco-fw))
        (set 'secret-drive-speed (/ (read-setting 'secret-drive-speed-kmh) 3.6))
        (set 'secret-drive-current (read-setting 'secret-drive-current))
        (set 'secret-drive-watts (read-setting 'secret-drive-watts))
        (set 'secret-drive-fw (read-setting 'secret-drive-fw))
        (set 'secret-sport-speed (/ (read-setting 'secret-sport-speed-kmh) 3.6))
        (set 'secret-sport-current (read-setting 'secret-sport-current))
        (set 'secret-sport-watts (read-setting 'secret-sport-watts))
        (set 'secret-sport-fw (read-setting 'secret-sport-fw))
        (set 'apply-speed (read-setting 'apply-speed))
        (set 'apply-current (read-setting 'apply-current))
        (set 'apply-watts (read-setting 'apply-watts))
        (set 'apply-fw (read-setting 'apply-fw))
        (set 'secret-apply-fw (read-setting 'secret-apply-fw))
        (set 'secret-apply-speed (read-setting 'secret-apply-speed))
        (set 'secret-apply-current (read-setting 'secret-apply-current))
        (set 'secret-apply-watts (read-setting 'secret-apply-watts))
        (set 'secret-presses (read-setting 'secret-presses))
        (set 'secret-combo (read-setting 'secret-combo))
        (set 'secret-requires-lock (read-setting 'secret-requires-lock))
        (set 'secret-exit-on-lock (read-setting 'secret-exit-on-lock))
        (set 'light-offset-thr (read-setting 'light-offset-thr))
        (set 'light-offset-brk (read-setting 'light-offset-brk))
        (set 'lock-presses (read-setting 'lock-presses))
        (set 'lock-combo (read-setting 'lock-combo))
        (set 'mode-presses (read-setting 'mode-presses))
        (set 'mode-combo (read-setting 'mode-combo))
        (set 'mode-requires-lock (read-setting 'mode-requires-lock))
        (set 'light-presses (read-setting 'light-presses))
        (set 'light-combo (read-setting 'light-combo))
        (set 'light-requires-lock (read-setting 'light-requires-lock))
        (set 'light-on-boot (read-setting 'light-on-boot))
        (set 'button-safety-speed (/ (read-setting 'button-speed-kmh) 3.6))
        (set 'boot-mode (read-setting 'boot-mode))
        (set 'use-mph (read-setting 'use-mph))
        (set 'rear-light-enable (read-setting 'rear-light-enable))
        (set 'auto-taillight (read-setting 'auto-taillight))
        (set 'brake-light-mode (read-setting 'brake-light-mode))
        (set 'eco-om (read-setting 'eco-om))
        (set 'drive-om (read-setting 'drive-om))
        (set 'sport-om (read-setting 'sport-om))
        (set 'secret-eco-om (read-setting 'secret-eco-om))
        (set 'secret-drive-om (read-setting 'secret-drive-om))
        (set 'secret-sport-om (read-setting 'secret-sport-om))
        (set 'apply-om (read-setting 'apply-om))
        (set 'secret-apply-om (read-setting 'secret-apply-om))
        (set 'bms-soc-enable (read-setting 'bms-soc-enable))
        (set 'cruise-enabled (read-setting 'cruise-enabled))
        (set 'cruise-delay (read-setting 'cruise-delay))
        (set 'cruise-deviation (read-setting 'cruise-deviation))

        (var m (read-setting 'model))
        (if (not (valid-model m)) {
            (setq m 0)
            (write-setting 'model m)
        })
        (set 'model m)
    }
)

(defun apply-software-adc ()
    (if software-adc
        (app-adc-detach 3 1)
        (app-adc-detach 3 0)
    )
)

(defun apply-runtime-settings ()
    {
        (load-settings)
        (if (!= model 2) { ; slave must not push conf to the master
            (apply-software-adc)
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

(defun save-general-settings (adc throttle brake show-batt show-batt-secret min-speed-kmh)
    {
        (write-setting 'software-adc adc)
        (write-setting 'min-adc-throttle throttle)
        (write-setting 'min-adc-brake brake)
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

(defun save-gesture-settings (s-presses s-combo s-locked l-presses l-combo m-presses m-combo m-locked li-presses li-combo li-locked)
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
    }
)

(defun save-misc-settings (auto-light btn-speed-kmh mph bms secret-exit)
    {
        (write-setting 'light-on-boot auto-light)
        (write-setting 'button-speed-kmh btn-speed-kmh)
        (write-setting 'use-mph mph)
        (write-setting 'bms-soc-enable bms)
        (write-setting 'secret-exit-on-lock secret-exit)
    }
)

(defun save-light-offsets (thr brk)
    {
        (write-setting 'light-offset-thr thr)
        (write-setting 'light-offset-brk brk)
    }
)

(defun save-rear-settings (enable auto-tail brake-mode)
    {
        (write-setting 'rear-light-enable enable)
        (write-setting 'auto-taillight auto-tail)
        (write-setting 'brake-light-mode brake-mode)
    }
)

(defun save-cruise-settings (enable delay deviation)
    {
        (write-setting 'cruise-enabled enable)
        (write-setting 'cruise-delay delay)
        (write-setting 'cruise-deviation deviation)
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
        (str-from-n (send-state-maxkmh) "%.0f")
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
        (* 0.85 (conf-get 'si-battery-ah) (* 3.7 (conf-get 'si-battery-cells)))
)

(defun send-state-range () {
        (var whkm (send-state-whkm))
        (if (> whkm 0.1)
            (/ (* (get-batt) (batt-wh-tot)) whkm) ; VESC Tool: wh_batt_left / wh_km
            0.0
        )
})

(defun send-settings ()
    {
        (send-data (str-merge
            "model "
            (str-from-n (read-setting 'model) "%d")
        ))
        (sleep 0.05)
        (send-data (str-merge
            "general "
            (if (read-setting 'software-adc) "true " "false ")
            (str-from-n (read-setting 'min-adc-throttle) "%.2f ")
            (str-from-n (read-setting 'min-adc-brake) "%.2f ")
            (if (read-setting 'show-batt-in-idle) "true " "false ")
            (if (read-setting 'show-batt-idle-secret) "true " "false ")
            (str-from-n (read-setting 'min-speed-kmh) "%.1f")
        ))
        (sleep 0.05)
        (send-data (str-merge
            "temps "
            (str-from-n (read-setting 'temp-warning-motor) "%.1f ")
            (str-from-n (read-setting 'temp-warning-fet) "%.1f")
        ))
        (sleep 0.05)
        (send-data (str-merge
            "modes "
            (str-from-n (read-setting 'eco-speed-kmh) "%.1f ")
            (str-from-n (read-setting 'eco-current) "%.2f ")
            (str-from-n (read-setting 'eco-watts) "%.0f ")
            (str-from-n (read-setting 'eco-fw) "%.1f ")
            (str-from-n (read-setting 'drive-speed-kmh) "%.1f ")
            (str-from-n (read-setting 'drive-current) "%.2f ")
            (str-from-n (read-setting 'drive-watts) "%.0f ")
            (str-from-n (read-setting 'drive-fw) "%.1f ")
            (str-from-n (read-setting 'sport-speed-kmh) "%.1f ")
            (str-from-n (read-setting 'sport-current) "%.2f ")
            (str-from-n (read-setting 'sport-watts) "%.0f ")
            (str-from-n (read-setting 'sport-fw) "%.1f ")
            (str-from-n (read-setting 'boot-mode) "%d ")
            (str-from-n (read-setting 'eco-om) "%.2f ")
            (str-from-n (read-setting 'drive-om) "%.2f ")
            (str-from-n (read-setting 'sport-om) "%.2f")
        ))
        (sleep 0.05)
        (send-data (str-merge
            "secret "
            (if (read-setting 'secret-enabled) "true " "false ")
            (str-from-n (read-setting 'secret-eco-speed-kmh) "%.1f ")
            (str-from-n (read-setting 'secret-eco-current) "%.2f ")
            (str-from-n (read-setting 'secret-eco-watts) "%.0f ")
            (str-from-n (read-setting 'secret-eco-fw) "%.1f ")
            (str-from-n (read-setting 'secret-drive-speed-kmh) "%.1f ")
            (str-from-n (read-setting 'secret-drive-current) "%.2f ")
            (str-from-n (read-setting 'secret-drive-watts) "%.0f ")
            (str-from-n (read-setting 'secret-drive-fw) "%.1f ")
            (str-from-n (read-setting 'secret-sport-speed-kmh) "%.1f ")
            (str-from-n (read-setting 'secret-sport-current) "%.2f ")
            (str-from-n (read-setting 'secret-sport-watts) "%.0f ")
            (str-from-n (read-setting 'secret-sport-fw) "%.1f ")
            (str-from-n (read-setting 'secret-eco-om) "%.2f ")
            (str-from-n (read-setting 'secret-drive-om) "%.2f ")
            (str-from-n (read-setting 'secret-sport-om) "%.2f")
        ))
        (sleep 0.05)
        (send-data (str-merge
            "apply "
            (if (read-setting 'apply-speed) "true " "false ")
            (if (read-setting 'apply-current) "true " "false ")
            (if (read-setting 'apply-watts) "true " "false ")
            (if (read-setting 'apply-fw) "true " "false ")
            (if (read-setting 'apply-om) "true " "false ")
            (if (read-setting 'secret-apply-speed) "true " "false ")
            (if (read-setting 'secret-apply-current) "true " "false ")
            (if (read-setting 'secret-apply-watts) "true " "false ")
            (if (read-setting 'secret-apply-fw) "true " "false ")
            (if (read-setting 'secret-apply-om) "true" "false")
        ))
        (sleep 0.05)
        (send-data (str-merge
            "gesture "
            (str-from-n (read-setting 'secret-presses) "%d ")
            (str-from-n (read-setting 'secret-combo) "%d ")
            (if (read-setting 'secret-requires-lock) "true " "false ")
            (str-from-n (read-setting 'lock-presses) "%d ")
            (str-from-n (read-setting 'lock-combo) "%d ")
            (str-from-n (read-setting 'mode-presses) "%d ")
            (str-from-n (read-setting 'mode-combo) "%d ")
            (if (read-setting 'mode-requires-lock) "true " "false ")
            (str-from-n (read-setting 'light-presses) "%d ")
            (str-from-n (read-setting 'light-combo) "%d ")
            (if (read-setting 'light-requires-lock) "true" "false")
        ))
        (sleep 0.05)
        (send-data (str-merge
            "misc "
            (if (read-setting 'light-on-boot) "true " "false ")
            (str-from-n (read-setting 'button-speed-kmh) "%.1f ")
            (if (read-setting 'use-mph) "true " "false ")
            (if (read-setting 'bms-soc-enable) "true " "false ")
            (if (read-setting 'secret-exit-on-lock) "true " "false ")
            (str-from-n (read-setting 'light-offset-thr) "%.2f ")
            (str-from-n (read-setting 'light-offset-brk) "%.2f")
        ))
        (sleep 0.05)
        (send-data (str-merge
            "rear "
            (if (read-setting 'rear-light-enable) "true " "false ")
            (if (read-setting 'auto-taillight) "true " "false ")
            (str-from-n (read-setting 'brake-light-mode) "%d")
        ))
        (sleep 0.05)
        (send-data (str-merge
            "cruise "
            (if (read-setting 'cruise-enabled) "true " "false ")
            (str-from-n (read-setting 'cruise-delay) "%.1f ")
            (str-from-n (read-setting 'cruise-deviation) "%.1f")
        ))
        (sleep 0.05)
        (send-data (str-merge
            "alarm "
            (if (read-setting 'alarm-tone) "true " "false ")
            (str-from-n (read-setting 'alarm-speed-threshold) "%.1f ")
            (str-from-n (read-setting 'alarm-gyro-threshold) "%.1f ")
            (str-from-n (read-setting 'alarm-voltage) "%.1f")
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

(defun adc-input(buffer) ; Frame 0x65
    {
        (set 'last-rx (systime)) ; feed the dash link watchdog

        (var throttle (+ (/ (bufget-u8 uart-buf thr-idx) 77.2) (if light light-offset-thr 0.0))) ; 255/3.3 = 77.2
        (var brake (+ (/ (bufget-u8 uart-buf brk-idx) 77.2) (if light light-offset-brk 0.0)))

        (if (< throttle 0.0) (setq throttle 0.0))
        (if (> throttle 3.3) (setq throttle 3.3))
        (if (< brake 0.0) (setq brake 0.0))
        (if (> brake 3.3) (setq brake 3.3))

        ; Pass through throttle and brake to VESC
        (app-adc-override 0 throttle)
        (app-adc-override 1 brake)
    }
)

(defun handle-taillight()
    (if rear-light-enable {
        (var base (and (not off) (or light auto-taillight)))
        (var braking (and (not off) (> (get-adc-decoded 1) min-adc-brake)))
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
                    ; the throttle is still held at activation - only arm the
                    ; throttle-cancel after it has been released once
                    (if (<= thr min-adc-throttle) (set 'cruise-thr-released true))
                    (if (or (and cruise-thr-released (> thr min-adc-throttle))
                            (> brk min-adc-brake)
                            (< speed-kmh 3))
                        (cruise-cancel)
                    )
                }
                (if (<= thr min-adc-throttle)
                    { ; throttle released - re-arm and hold the timer at now
                        (set 'cruise-blocked false)
                        (set 'cruise-ref speed-kmh)
                        (set 'cruise-since (systime))
                    }
                    (if (and (not cruise-blocked) (> speed-kmh 5))
                        {
                            (if (> (abs (- speed-kmh cruise-ref)) cruise-deviation) {
                                (set 'cruise-ref speed-kmh)
                                (set 'cruise-since (systime))
                            })
                            (if (> (secs-since cruise-since) cruise-delay) {
                                (set 'cruising true)
                                (set 'cruise-thr-released false)
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

        ; Dash link watchdog: release the ADC overrides when throttle frames stop
        ; coming, otherwise the last (possibly full) throttle value stays applied
        (if (and software-adc (> (secs-since last-rx) 0.5))
            {
                (app-adc-override 0 0)
                (app-adc-override 1 0)
                (cruise-cancel)
            }
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

        (trap (handle-taillight))
        (handle-lock (abs current-speed))
    }
)

(defun update-dash(buffer) ; Frame 0x64
    {
        (var current-speed (abs cur-speed-kmh))
        (var disp-speed (+ (if use-mph (* current-speed 0.621371) current-speed) 0.5)) ; rounded for the dash
        (var battery cur-batt)
        (var crc-end (- (buflen tx-frame) 2)) ; crc bytes at end of frame

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

        ; light field
        (if (not off)
            (if (> alarm 4)
                (bufset-u8 tx-frame (+ tx-base 2) 1) ; alarm on
                (bufset-u8 tx-frame (+ tx-base 2) (if light 1 0))
            )
            (bufset-u8 tx-frame (+ tx-base 2) 0)
        )

        ; beep field
        (if (> feedback 0)
            {
                (bufset-u8 tx-frame (+ tx-base 3) 1)
                (set 'feedback (- feedback 1))
            }
            (bufset-u8 tx-frame (+ tx-base 3) 0)
        )

        ; speed field
        (if lock
            (bufset-u8 tx-frame (+ tx-base 4) 0) ; lock display
            (if (if unlock show-batt-idle-secret show-batt-in-idle)
                (if (> current-speed 1)
                    (bufset-u8 tx-frame (+ tx-base 4) disp-speed)
                    (bufset-u8 tx-frame (+ tx-base 4) battery))
                (bufset-u8 tx-frame (+ tx-base 4) disp-speed)
            )
        )

        ; error field
        (if (> alarm 0)
            (bufset-u8 tx-frame (+ tx-base 5) 99) ; alarm active
            (bufset-u8 tx-frame (+ tx-base 5) (get-fault))
        )

        ; calc crc

        (var crcout 0)
        (looprange i 2 crc-end
        (set 'crcout (+ crcout (bufget-u8 tx-frame i))))
        (set 'crcout (bitwise-xor crcout 0xFFFF))
        (bufset-u8 tx-frame crc-end crcout)
        (bufset-u8 tx-frame (+ crc-end 1) (shr crcout 8))

        ; write
        (uart-write tx-frame)
    }
)

(defun read-frames-g30()
    (loopwhile t {
        (trap ; a parse error must not kill the reader thread
            (loopwhile t
                {
                    (uart-read-bytes uart-buf 3 0)
                    (if (= (bufget-u16 uart-buf 0) 0x5aa5)
                        {
                            (var len (bufget-u8 uart-buf 2))
                            (var crc len)
                            (if (and (> len 0) (< len 59)) ; len+6 must fit the 64 byte buffer
                                {
                                    (uart-read-bytes uart-buf (+ len 6) 0) ;read remaining 6 bytes + payload, overwrite buffer

                                    (let ((code (bufget-u8 uart-buf 2)) (checksum (bufget-u16 uart-buf (+ len 4))))
                                        {
                                            (looprange i 0 (+ len 4) (set 'crc (+ crc (bufget-u8 uart-buf i))))

                                            (if (= checksum (bitwise-and (+ (shr (bitwise-xor crc 0xFFFF) 8) (shl (bitwise-xor crc 0xFFFF) 8)) 65535)) ;If the calculated checksum matches with sent checksum, forward comman
                                                {
                                                    (if (and (= code 0x65) software-adc (>= len 3)) ; frame must actually carry the throttle/brake bytes
                                                        (adc-input uart-buf)
                                                    )
                                                    (if (= code 0x64) ; dash reply only on 0x64
                                                        (update-dash uart-buf)
                                                    )
                                                }
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
        (sleep 0.1) ; only reached after an error
    })
)

(defun read-frames-m365()
    (loopwhile t {
        (trap ; a parse error must not kill the reader thread
            (loopwhile t
                {
                    (uart-read-bytes uart-buf 3 0)
                    (if (= (bufget-u16 uart-buf 0) 0x55aa)
                        {
                            (var len (bufget-u8 uart-buf 2))
                            (var crc len)
                            (if (and (> len 0) (< len 60)) ; max 64 bytes
                                {
                                    (uart-read-bytes uart-buf (+ len 4) 0)
                                    (looprange i 0 len
                                        (set 'crc (+ crc (bufget-u8 uart-buf i))))
                                    (if (=(+(shl(bufget-u8 uart-buf (+ len 2))8) (bufget-u8 uart-buf (+ len 1))) (bitwise-xor crc 0xFFFF))
                                        {
                                            (if (and (= (bufget-u8 uart-buf 1) 0x65) software-adc (>= len 2)) ; frame must actually carry the throttle/brake bytes
                                                (adc-input uart-buf)
                                            )
                                            (update-dash uart-buf) ; dash expects a reply on every frame
                                        }
                                    )
                                }
                            )
                        }
                    )
                }
            )
        )
        (sleep 0.1) ; only reached after an error
    })
)

(defun combo-held(combo thr brk) ; exclusive lever matching
    (cond
        ((= combo 0) (and (> brk min-adc-brake) (> thr min-adc-throttle)))
        ((= combo 1) (and (> brk min-adc-brake) (<= thr min-adc-throttle)))
        ((= combo 2) (and (> thr min-adc-throttle) (<= brk min-adc-brake)))
        ((= combo 3) (and (<= brk min-adc-brake) (<= thr min-adc-throttle))) ; no levers
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
        (var state (+ (if (> brk min-adc-brake) 1 0) (if (> thr min-adc-throttle) 2 0)))

        (if (!= state lever-state) {
            (set 'lever-state state)
            (set 'lever-since (systime))
        })
        (if (= state 0) (set 'lever-armed true))

        (if (and lever-armed (> state 0) (> (secs-since lever-since) 0.5))
            (cond
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

            (if (= model 1) {
                (define tx-frame (array-create 14))
                (bufset-u16 tx-frame 0 0x55AA) ;Xiaomi protocol
                (bufset-u16 tx-frame 2 0x0821)
                (bufset-u16 tx-frame 4 0x6400) ; Packet is from ESC to BLE
                (set 'tx-base 6)
                (set 'thr-idx 4)
                (set 'brk-idx 5)
            } {
                (define tx-frame (array-create 15))
                (bufset-u16 tx-frame 0 0x5AA5) ;Ninebot protocol
                (bufset-u8 tx-frame 2 0x06) ;Payload length is 5 bytes
                (bufset-u16 tx-frame 3 0x2021) ; Packet is from ESC to BLE
                (bufset-u16 tx-frame 5 0x6400) ; Packet is from ESC to BLE
                (set 'tx-base 7)
                (set 'thr-idx 5)
                (set 'brk-idx 6)
            })

            (apply-software-adc)

            ; Apply mode on start-up
            (apply-mode)

            ; Spawn UART reading frames thread
            (if (= model 1) ; 200 words: the unlock display branch + trap wrapper need headroom
                (spawn 200 read-frames-m365)
                (spawn 200 read-frames-g30)
            )
            (button-logic) ; Start button logic in main thread - this will block the main thread
        })
})

@const-end

(image-save)
(main)
