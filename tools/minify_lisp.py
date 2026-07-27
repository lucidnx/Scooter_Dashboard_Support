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


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: minify_lisp.py <in.lisp> <out.lisp>")
    src = open(sys.argv[1]).read()
    dst = strip(src)
    if tokenize(src) != tokenize(dst):
        raise SystemExit("minify: token stream changed, refusing to write")
    open(sys.argv[2], "w").write(dst)
    saved = len(src) - len(dst)
    print(f"minify: {len(src)} -> {len(dst)} bytes ({100 * saved / len(src):.0f}% smaller)")


if __name__ == "__main__":
    main()
