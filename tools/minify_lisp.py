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
#   unit  const heap   image   free   extensions
#   A         109684   21372     16   307 of 322
#   B         109672   21320     80   304 of 319
#
# Sixteen bytes. The image holds the symbol table, so a firmware build with a
# few more extensions than unit A has none - image-save fails, and a script that
# cannot save an image bootloops the controller with no way in but an ST-Link.
# The two units' images differ by 52 bytes over 3 extensions, so the ceiling is
# that 128 KB less the largest image seen and 6 KB - about a hundred times the
# variation measured, and room for the image itself to grow by a third.
BYTES_PER_TOKEN = 6.694
IMAGE_BYTES = 21372
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
          f"({n * 6.694 / 1024:.0f} KB of the 128 KB const heap, image takes 20)")
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
