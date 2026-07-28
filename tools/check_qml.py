#!/usr/bin/env python3
"""Brace balance and undeclared-id check for the package UI.

The packager stores ui.qml without parsing it, so a broken brace only shows up
as a runtime error in VESC Tool. This runs at build time instead.
"""

import re
import sys


def balance(src):
    depth = line = 1
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
        elif c == "/" and i + 1 < len(src) and src[i + 1] == "/":
            while i < len(src) and src[i] != "\n":
                i += 1
            continue
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth < 1:
                return f"unbalanced '}}' at line {line}"
        i += 1
    if depth != 1:
        return f"{depth - 1} unclosed '{{'"
    return None


def undeclared(src):
    ids = set(re.findall(r"\bid:\s*([A-Za-z_][A-Za-z0-9_]*)", src))
    params = set()
    for args in re.findall(r"function\s+\w+\s*\(([^)]*)\)", src):
        params |= {a.strip() for a in args.split(",") if a.strip()}
    refs = set(re.findall(r"\b([a-z][A-Za-z0-9]*)\.checked\b", src))
    refs |= set(re.findall(r"\b([a-z][A-Za-z0-9]*)\.currentIndex\b", src))
    return sorted(refs - ids - params)


def main():
    src = open(sys.argv[1] if len(sys.argv) > 1 else "ui.qml").read()
    err = balance(src)
    if err:
        raise SystemExit(f"check_qml: {err}")
    missing = undeclared(src)
    if missing:
        raise SystemExit(f"check_qml: referenced but never declared: {', '.join(missing)}")
    print("check_qml: ok")


if __name__ == "__main__":
    main()
