#!/usr/bin/env python3
"""Every symbol the script calls must exist.

LispBM binds names at call time, so a function that was deleted or misspelled
parses cleanly, builds cleanly, and only shows up as `variable_not_bound` on the
scooter - and then only on the model that happens to reach it. This walks the
source, collects what is defined and what is bound locally, and reports every
call to something that is neither.

    python3 tools/check_lisp.py scooter_support.lisp
"""
import re, sys

BUILTINS = set("""
+ - * / mod = != < > <= >= and or not eq eq? equal if cond let progn quote
setq set setvar def define defun defunret defstruct lambda closure var
loopwhile loopfor looprange loopforeach loopwhile-thd break return recv recv-to
send spawn spawn-trap self wait exit-ok exit-error atomic trap match
list cons car cdr first second ix append length reverse range assoc cossa acons
setassoc take drop rest sort filter foldl foldr map apply
array-create bufget-u8 bufget-i8 bufget-u16 bufget-i16 bufget-u24 bufget-u32
bufget-i32 bufget-f32 bufset-u8 bufset-i8 bufset-u16 bufset-i16 bufset-u24
bufset-u32 bufset-i32 bufset-f32 bufclear bufcpy buflen free
bitwise-and bitwise-or bitwise-xor bitwise-not shl shr
to-i to-i32 to-float to-double to-byte to-u to-u32 type-of is-list
str-merge str-from-n str-part str-split str-replace str-to-i str-to-f str-len
str-cmp to-str to-str-delim str-find num-eq
print puts sleep systime secs-since time-now timeout-reset
abs sin cos tan asin acos atan atan2 pow exp sqrt log log10 deg2rad rad2deg
floor ceil round min max
gpio-configure gpio-write gpio-read
uart-start uart-stop uart-write uart-read uart-read-bytes uart-read-until
can-start can-scan can-send-sid can-send-eid can-recv-sid can-recv-eid
can-cmd can-list-devs can-local-id can-update-baud
canget-current canget-current-in canget-duty canget-rpm canget-temp-fet
canget-temp-motor canget-speed canget-dist canget-ah canget-wh canget-vin
canget-current-dir canget-current-in-dir
get-vin get-rpm get-current get-current-in get-duty get-temp-fet get-temp-mot
get-speed get-dist get-dist-abs get-batt get-adc get-adc-decoded get-ppm
get-encoder get-imu-gyro get-imu-acc get-imu-rpy get-imu-mag get-fault
get-adc-temp get-current-dir get-imu-quat get-est-lambda get-est-res
set-current set-current-rel set-duty set-brake set-brake-rel set-handbrake
set-rpm set-pos set-current-rel-off stop-current
setup-current-in setup-current setup-ah setup-wh
conf-get conf-set conf-store conf-detect-foc conf-restore-mc conf-dc-cal
conf-get-limits conf-measure-res
eeprom-store-f eeprom-read-f eeprom-store-i eeprom-read-i
app-adc-detach app-adc-override app-adc-range-ok app-disable-output
app-is-output-disabled app-pas-get-rpm app-ppm-detach app-ppm-override
foc-play-tone foc-play-stop foc-beep foc-openloop foc-set-openloop-phase
event-enable event-register-handler
sysinfo import load-native-lib unload-native-lib
rcode-run rcode-run-noret start-code-server
img-buffer img-color img-rectangle img-text disp-render
pwm-start pwm-stop pwm-set-duty
raw-adc-current raw-adc-voltage raw-mod-alpha raw-mod-beta raw-hall
plot-init plot-add-graph plot-set-graph plot-send-points
gc mem-info word-size lbm-heap-state set-gc-stack-size
unsafe-call-system flatten unflatten kill number-consed
crc16 crc32 buf-resize
member not-eq send-data get-bms-val setup-wh-chg stats-reset image-save
read-eval-program read eval read-program t nil true false
""".split())

# (set 'x v) updates whichever environment holds x - local or global - so a set
# target only needs a def when nothing local binds it. Collected in walk, where
# the scope is known, not in collect_defs, where it is not.
SETS = set()

BINDERS = {"let"}
VARFORMS = {"var", "def", "define", "setq", "set", "setvar"}


def strip(src):
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == ';':
            while i < n and src[i] != '\n':
                i += 1
        elif c == '"':
            out.append(c); i += 1
            while i < n and src[i] != '"':
                if src[i] == '\\':
                    out.append(src[i]); i += 1
                out.append(src[i]); i += 1
            out.append('"'); i += 1
        else:
            out.append(c); i += 1
    return ''.join(out)


TOK = re.compile(r'\(|\)|\[|\]|"(?:[^"\\]|\\.)*"|[^\s()\[\]]+')


def parse(src):
    stack, cur = [], []
    for m in TOK.finditer(strip(src)):
        t = m.group(0)
        if t in '([':
            stack.append(cur); cur = []
        elif t in ')]':
            if not stack:
                raise SystemExit("check_lisp: unbalanced ) in source")
            top = stack.pop(); top.append(cur); cur = top
        else:
            cur.append(t)
    if stack:
        raise SystemExit("check_lisp: unbalanced ( in source")
    return cur


def sym(x):
    return isinstance(x, str)


def collect_defs(node, out):
    if isinstance(node, list):
        if node and sym(node[0]):
            h = node[0]
            if h in ("defun", "defunret") and len(node) > 1 and sym(node[1]):
                out.add(node[1])
            elif h in ("def", "define") and len(node) > 1 and sym(node[1]):
                out.add(node[1])
            elif h == "import" and len(node) > 2 and sym(node[2]) and node[2].startswith("'"):
                out.add(node[2][1:])

        for x in node:
            collect_defs(x, out)


def walk(node, local, defs, calls, free=None):
    """calls: names used in head position. free: names used as a value.
    Both end up as variable_not_bound at run time if nothing defines them."""
    if not isinstance(node, list) or not node:
        return
    # a backquoted template is data apart from its ,unquoted holes
    if any(sym(x) and x == "`" for x in node):
        def unq(n):
            if sym(n):
                if n.startswith(",") and free is not None and n[1:] not in local:
                    free.add(n[1:])
            elif isinstance(n, list):
                for q in n: unq(q)
        unq(node)
        return
    # a quoted form is data, not code - this is what setting-defs and the
    # setting-groups tables are, and every symbol inside them is a name
    if any(sym(x) and x == "'" for x in node):
        out = []
        skip = False
        for x in node:
            if skip: skip = False; continue
            if sym(x) and x == "'": skip = True; continue
            out.append(x)
        node = out
        if not node: return
    h = node[0]
    if sym(h):
        # match and recv clauses lead with a pattern, not a call. match and
        # recv-to carry one expression first, plain recv carries none.
        if h in ("match", "recv", "recv-to"):
            k = 1 if h == "recv" else 2
            for x in node[1:k]: walk(x, local, defs, calls, free)
            for cl in node[k:]:
                if isinstance(cl, list):
                    bound = set(local)
                    def names(pat):
                        if sym(pat): bound.add(pat)
                        elif isinstance(pat, list):
                            for q in pat: names(q)
                    names(cl[0])
                    for x in cl[1:]: walk(x, bound, defs, calls, free)
            return
        if h == "let" and len(node) > 1 and isinstance(node[1], list):
            inner = set(local)
            for b in node[1]:
                if isinstance(b, list) and b and sym(b[0]):
                    inner.add(b[0])
                    for x in b[1:]:
                        walk(x, inner, defs, calls, free)
            for x in node[2:]:
                walk(x, inner, defs, calls, free)
            return
        if h in ("defun", "defunret") and len(node) > 2 and isinstance(node[2], list):
            inner = set(local) | {a for a in node[2] if sym(a)}
            for x in node[3:]:
                walk(x, inner, defs, calls, free)
            return
        if h == "lambda" and len(node) > 1 and isinstance(node[1], list):
            inner = set(local) | {a for a in node[1] if sym(a)}
            for x in node[2:]:
                walk(x, inner, defs, calls, free)
            return
        if h in ("looprange", "loopfor") and len(node) > 1 and sym(node[1]):
            inner = set(local) | {node[1]}
            for x in node[2:]:
                walk(x, inner, defs, calls, free)
            return
        if h == "loopforeach" and len(node) > 1 and sym(node[1]):
            inner = set(local) | {node[1]}
            for x in node[2:]:
                walk(x, inner, defs, calls, free)
            return
        if h in ("set", "setvar", "setq") and len(node) > 1:
            t = node[1]
            name = t[1:] if sym(t) and t.startswith("'") else (t if h == "setq" and sym(t) else None)
            if name and name not in local:
                SETS.add(name)
            for x in node[2:]:
                walk(x, local, defs, calls, free)
            return
        if h == "var" and len(node) > 1 and sym(node[1]):
            local.add(node[1])
            for x in node[2:]:
                walk(x, local, defs, calls, free)
            return
        if h not in local:
            calls.add(h)
    for k, x in enumerate(node):
        if sym(x):
            if k and free is not None and x not in local:
                free.add(x)
        else:
            walk(x, local, defs, calls, free)


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "scooter_support.lisp"
    src = open(path).read()
    tree = parse(src)
    defs = set()
    for n in tree:
        collect_defs(n, defs)
    calls, free = set(), set()
    for n in tree:
        walk(n, set(), defs, calls, free)
    orphan = sorted(n for n in SETS if n not in defs)
    if orphan:
        print(f"check_lisp: {len(orphan)} global(s) assigned but never defined:",
              file=sys.stderr)
        for o in orphan:
            print(f"  {o}", file=sys.stderr)
        sys.exit(1)

    def unresolved(names):
        return sorted(c for c in names
                      if c not in defs and c not in BUILTINS
                      and not c.startswith(("'", '"', "@", "{", "}", "."))
                      and not re.match(r"^[-+]?[\d.]", c))
    bad = unresolved(calls) + [x for x in unresolved(free) if x not in unresolved(calls)]
    if bad:
        print(f"check_lisp: {len(bad)} name(s) used but never defined:",
              file=sys.stderr)
        for b in bad:
            where = [i + 1 for i, l in enumerate(src.splitlines())
                     if re.search(r'\(' + re.escape(b) + r'[\s)]', l)]
            print(f"  {b}   line(s) {where[:6]}", file=sys.stderr)
        sys.exit(1)
    print(f"check_lisp: ok - {len(defs)} definitions, {len(calls)} calls, "
          f"{len(free)} value references, all resolved")


main()
