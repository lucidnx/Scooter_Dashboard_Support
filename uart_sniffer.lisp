; Scooter Dashboard Support - UART sniffer v1.0
; Passive logger for the dash link. Listens on the COMM port (half-duplex on the
; TX pin, same wiring as the package) and prints what the dash sends to the
; VESC Tool Lisp console. Nothing is ever written to the wire, so the dash gets
; no ESC reply while this runs.
;
; Standalone debug script, not part of the package: VESC Dev Tools -> Lisp,
; open this file, Upload & Run. Reinstall the package to get the normal script
; back. The motor is never touched here - the ADC app keeps working as configured.
;
; Frame layouts (checksum = ~(sum of everything between header and checksum), LE):
;   55 AA | len | addr cmd arg payload | crc-lo crc-hi   M365 / 1S / PRO2
;   5A A5 | len | src dst cmd arg payload | crc-lo crc-hi   G30
;
; One line per frame, same format as the package's own console log:
; uptime  src>dst  cmd  arg  payload-length  payload
;
; Guide and wiring: https://github.com/lucidnx/Scooter_Dashboard_Support

; -> Settings

(def baudrate 115200)
(def half-duplex true) ; single wire on the TX pin, like the dash link
(def log-mode 'all) ; 'all, 'changes = only when a command's payload changes, 'raw, 'quiet
(def show-bad-crc true) ; also print frames that fail the checksum
(def only-cmd -1) ; -1 = every command, or a single command byte like 0x65
(def stats-interval 5.0) ; seconds between counter lines, 0 = off
(def max-lines 0) ; print lines per second, 0 = unlimited
(def gap-time 0.003) ; silence that ends a burst on the wire
(def idle-time 0.5) ; how long to wait for the first byte of a burst

; -> Code starts here

(def rx (array-create 128))
(def line-t (systime))
(def stats-t (systime))
(def line-n 0)
(def n-frames 0)
(def n-bad 0)
(def n-stray 0)
(def counts nil)
(def seen nil)

(defun hex8 (v) (str-merge "0x" (str-from-n v "%02x")))

(defun hex-bytes (base n) {
        (var lim (if (> n 32) 32 n))
        (var s "")
        (looprange i base (+ base lim)
            (set 's (str-merge s (str-from-n (bufget-u8 rx i) "%02x") " ")))
        (if (> n lim) (str-merge s "...") s)
})

(defun key-tag (key)
    (str-merge (if (< key 256) "M365" "G30") " " (hex8 (mod key 256)))
)

(defun log-line (txt) {
        (if (> (secs-since line-t) 1.0) {
                (set 'line-t (systime))
                (set 'line-n 0)
        })
        (if (or (= max-lines 0) (< line-n max-lines)) {
                (set 'line-n (+ line-n 1))
                (print (str-merge (str-from-n (secs-since 0) "%8.3f") "  " txt))
        })
})

(defun log-raw (n)
    (if (not (eq log-mode 'quiet))
        (log-line (str-merge "raw " (str-from-n n "%d") "B   " (hex-bytes 0 n)))
    )
)

(defun log-stats () {
        (var s "")
        (loopforeach p counts
            (set 's (str-merge s "  " (key-tag (car p)) ":" (str-from-n (cdr p) "%d"))))
        (print (str-merge (str-from-n (secs-since 0) "%8.3f") "  frames "
                          (str-from-n n-frames "%d") "  bad-crc " (str-from-n n-bad "%d")
                          "  stray " (str-from-n n-stray "%d") s))
})

(defun bump-count (key) {
        (var c (assoc counts key))
        (if (eq c nil)
            (set 'counts (acons key 1 counts))
            (set 'counts (setassoc counts key (+ c 1)))
        )
})

(defun changed (key hex) {
        (var prev (assoc seen key))
        (cond
            ((eq prev nil) { (set 'seen (acons key hex seen)) true })
            ((= (str-cmp prev hex) 0) false)
            (t { (set 'seen (setassoc seen key hex)) true })
        )
})

(defun crc-ok (base total) {
        (var end (+ base total))
        (var crc 0)
        (looprange i (+ base 2) (- end 2) (set 'crc (+ crc (bufget-u8 rx i))))
        (set 'crc (bitwise-xor (bitwise-and crc 0xFFFF) 0xFFFF))
        (= crc (+ (bufget-u8 rx (- end 2)) (shl (bufget-u8 rx (- end 1)) 8)))
})

; addr is the first address byte, len the payload length byte. M365 has a
; single address byte and counts cmd+arg in len.
(defun frame-line (addr len xiaomi) {
        (var n (if xiaomi (- len 2) len))
        (var from (+ addr (if xiaomi 3 4)))
        (var pay "")
        (looprange i from (+ from (if (> n 0) n 0))
            (set 'pay (str-merge pay " " (str-from-n (bufget-u8 rx i) "%02x"))))
        (str-merge
            (if xiaomi "  " (str-from-n (bufget-u8 rx addr) "%02x"))
            ">" (str-from-n (bufget-u8 rx (+ addr (if xiaomi 0 1))) "%02x")
            "    " (str-from-n (bufget-u8 rx (+ addr (if xiaomi 1 2))) "%02x")
            "   " (str-from-n (bufget-u8 rx (+ addr (if xiaomi 2 3))) "%02x")
            "   " (str-from-n n "%-2d")
            "  " pay
        )
})

(defun log-frame (base total xiaomi) {
        (var cmd (bufget-u8 rx (+ base (if xiaomi 4 5))))
        (var ok (crc-ok base total))
        (var key (+ (if xiaomi 0 256) cmd))
        (set 'n-frames (+ n-frames 1))
        (if (not ok) (set 'n-bad (+ n-bad 1)))
        (bump-count key)
        (if (and (or ok show-bad-crc)
                 (or (< only-cmd 0) (= only-cmd cmd))
                 (not (eq log-mode 'quiet)))
            {
                (var line (frame-line (+ base 3) (bufget-u8 rx (+ base 2)) xiaomi))
                (if (or (eq log-mode 'all) (not ok) (changed key line))
                    (log-line (str-merge line (if ok "" "   CRC BAD")))
                )
            }
        )
})

(defun scan-chunk (n) {
        (var i 0)
        (var found 0)
        (loopwhile (< i n) {
                (var magic (if (< (+ i 2) n) (bufget-u16 rx i) 0))
                (var xiaomi (= magic 0x55aa))
                (var total (if (or xiaomi (= magic 0x5aa5))
                    (+ (bufget-u8 rx (+ i 2)) (if xiaomi 6 9))
                    0
                ))
                (if (and (> total 6) (<= (+ i total) n))
                    {
                        (log-frame i total xiaomi)
                        (set 'found (+ found 1))
                        (set 'i (+ i total))
                    }
                    {
                        (set 'n-stray (+ n-stray 1))
                        (set 'i (+ i 1))
                    }
                )
        })
        found
})

(defun sniff ()
    (loopwhile t {
        (trap ; a parse error must not kill the sniffer
            (loopwhile t {
                    (var n (uart-read rx 1 0 256 idle-time)) ; 256 = no stop byte
                    (if (> n 0) {
                            (set 'n (+ n (uart-read rx (- (buflen rx) 1) 1 256 gap-time)))
                            (if (or (eq log-mode 'raw) (= (scan-chunk n) 0))
                                (log-raw n)
                            )
                    })
                    (if (and (> stats-interval 0) (> (secs-since stats-t) stats-interval)) {
                            (set 'stats-t (systime))
                            (log-stats)
                    })
            })
        )
        (sleep 0.1) ; only reached after an error
    })
)

(defun main () {
        (if half-duplex
            (uart-start baudrate 'half-duplex)
            (uart-start baudrate)
        )
        (gpio-configure 'pin-rx 'pin-mode-in-pu)
        (print (str-merge "UART sniffer: " (str-from-n baudrate "%d") " baud"
                          (if half-duplex " half-duplex" " full-duplex")
                          ", mode " (to-str log-mode)))
        (sniff)
})

(main)
