#!/usr/bin/env python3
"""Strip comments and indentation from a LispBM script.

The packager stores the script as source text, so comments and leading
whitespace are charged against the 128 KB Lisp data budget. This keeps the
repository copy readable and ships a stripped one.

Newlines are kept: a ';' comment ends at the newline, so joining lines would
change what the next line means. Only whole-line and trailing comments and the
indentation in front of a line are removed.

The result is verified by tokenising both files and comparing the token
streams, so a bug here fails the build instead of reaching the scooter.
"""

import sys


# Measured with :info in the VESC Tool Lisp console, on two units running the
# v4.0 release. The const heap and the image share 128 KB:
#
#   unit  release  tokens   const heap   image   free   extensions
#   A       v4.0     16386      109684   21372     16   307 of 322
#   B       v4.0     16386      109672   21320     80   304 of 319
#   B       v4.1     14090       89400   22120  19552   304 of 319
#   B       v4.2     14086       88992   22404  19676   304 of 319
#   B       v4.3     14090       89080   21940  20052   304 of 319
#
# Sixteen bytes. The image holds the symbol table, so a firmware build with a
# few more extensions than unit A has none - image-save fails, and a script that
# cannot save an image bootloops the controller with no way in but an ST-Link.
# The two v4.0 units' images differ by 52 bytes over 3 extensions, so unit to
# unit the variation is tens of bytes; the ceiling is that 128 KB less the
# largest image seen and 6 KB of margin.
#
# The image is the number to re-measure every release. It grew 800 bytes from
# v4.0 to v4.1 on the same unit while the script itself got 2296 tokens shorter,
# so it does not track the token count and nothing in this build catches it.
#
# IMAGE_BYTES stays at the largest image ever measured, not the newest one. v4.3
# came back 464 bytes under v4.2 on the same unit with four more tokens, so the
# figure moves in both directions for reasons the token count does not explain -
# and the ceiling has to hold for the worst image seen, not the last one.
#
# BYTES_PER_TOKEN stays calibrated on v4.0: cost per token is not uniform (6.69
# there, 6.35 at v4.1, 8.83 marginal between the two), and v4.0 is the build
# measured a hair from failing. Fitting the ceiling to v4.1 instead would put it
# back at roughly the token count that bootlooped.
BYTES_PER_TOKEN = 6.694
IMAGE_BYTES = 22404
MARGIN_BYTES = 6144
TOKEN_MAX = int((131072 - IMAGE_BYTES - MARGIN_BYTES) / BYTES_PER_TOKEN)
TOKEN_WARN = TOKEN_MAX - 600


def tokenize(src):
    """Token stream with comments dropped and strings kept intact."""
    toks, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c in " \t\r\n":
            i += 1
        elif c == ";":
            while i < n and src[i] != "\n":
                i += 1
        elif c == '"':
            j, buf = i + 1, ['"']
            while j < n:
                if src[j] == "\\" and j + 1 < n:
                    buf.append(src[j:j + 2])
                    j += 2
                    continue
                buf.append(src[j])
                if src[j] == '"':
                    j += 1
                    break
                j += 1
            toks.append("".join(buf))
            i = j
        elif c in "()[]{}'":
            toks.append(c)
            i += 1
        else:
            j = i
            while j < n and src[j] not in " \t\r\n;\"()[]{}'":
                j += 1
            toks.append(src[i:j])
            i = j
    return toks


def strip(src):
    out = []
    for line in src.split("\n"):
        kept, i, in_str = [], 0, False
        while i < len(line):
            c = line[i]
            if in_str:
                kept.append(c)
                if c == "\\" and i + 1 < len(line):
                    kept.append(line[i + 1])
                    i += 2
                    continue
                if c == '"':
                    in_str = False
            elif c == '"':
                in_str = True
                kept.append(c)
            elif c == ";":
                break
            else:
                kept.append(c)
            i += 1
        if in_str:
            raise SystemExit(f"minify: string is not closed on one line: {line[:60]}")
        text = "".join(kept).strip()
        if text:
            out.append(text)
    return "\n".join(out) + "\n"


def stray_backslash(src):
    """A backslash outside a string is never valid here, and a bad edit can
    leave one behind without unbalancing anything."""
    i = line = 1
    line = 1
    i = 0
    in_str = False
    while i < len(src):
        c = src[i]
        if c == "\n":
            line += 1
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == ";":
            while i < len(src) and src[i] != "\n":
                i += 1
            continue
        elif c == "\\":
            return f"stray backslash at line {line}: {src[i:i + 20]!r}"
        i += 1
    return None


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: minify_lisp.py <in.lisp> <out.lisp>")
    src = open(sys.argv[1]).read()
    err = stray_backslash(src)
    if err:
        raise SystemExit(f"minify: {err}")
    dst = strip(src)
    if tokenize(src) != tokenize(dst):
        raise SystemExit("minify: token stream changed, refusing to write")
    open(sys.argv[2], "w").write(dst)
    saved = len(src) - len(dst)
    print(f"minify: {len(src)} -> {len(dst)} bytes ({100 * saved / len(src):.0f}% smaller)")

    # The binding limit is not the code area, it is the 128 KB flash the const
    # heap and the image share. That fills with parsed forms, so stripping bytes
    # does nothing for it - only having fewer of them does. Measured on a G30:
    # 16312 tokens boots reliably, 16888 leaves image-save no room, so the script
    # is reparsed on every boot and collides with the previous one.
    n = len(tokenize(dst))
    print(f"const-heap tokens: {n} of {TOKEN_MAX} "
          f"({n * BYTES_PER_TOKEN / 1024:.0f} KB of the 128 KB const heap, "
          f"image takes {IMAGE_BYTES / 1024:.0f})")
    if n > TOKEN_MAX:
        raise SystemExit(
            f"minify: {n} tokens is over the {TOKEN_MAX} ceiling. image-save will "
            f"fail on units with less room than the one this was measured on, and "
            f"a script that cannot save an image bootloops the controller on the "
            f"next reboot. Take tokens out before building.")
    if n > TOKEN_WARN:
        print(f"WARNING: {n} tokens leaves little room - check :info in the VESC "
              f"Tool Lisp console for the free bytes on the target unit",
              file=sys.stderr)


if __name__ == "__main__":
    main()
