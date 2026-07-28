#!/usr/bin/env python3
"""Make the copy of the README that ships inside the package.

VESC Tool shows the description as markdown but does not fetch images, so the
screenshots and wiring diagrams render as nothing useful. They are dropped here,
along with the tables that held them, and a link to the project is added under
the title so the pictures are still one tap away. The repository README keeps
everything.
"""

import re
import sys

REPO = "https://github.com/lucidnx/vesc_scooter_support"


def is_image(line):
    return "<img " in line or re.match(r"\s*!\[", line)


def strip_images(src):
    out = []
    lines = src.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]

        # a table row of images takes its header and separator with it
        if is_image(line) and line.lstrip().startswith("|"):
            while out and out[-1].lstrip().startswith("|"):
                out.pop()
            while out and not out[-1].strip():
                out.pop()
            i += 1
            while i < len(lines) and not lines[i].strip():
                i += 1
            out.append("")
            continue

        if is_image(line):
            i += 1
            while i < len(lines) and not lines[i].strip():
                i += 1
            continue

        # the comment only explains the screenshot widths
        if "fixed width so screenshots" in line:
            i += 1
            continue

        out.append(line)
        i += 1

    text = "\n".join(out)
    return re.sub(r"\n{3,}", "\n\n", text)


def add_link(src):
    lines = src.split("\n")
    for i, line in enumerate(lines):
        if line.startswith("# "):
            lines.insert(i + 1, f"\n{REPO}")
            break
    return "\n".join(lines)


def main():
    src = open(sys.argv[1]).read()
    dst = add_link(strip_images(src))
    open(sys.argv[2], "w").write(dst)
    print(f"pkg_readme: {len(src)} -> {len(dst)} bytes, "
          f"{sum(1 for l in src.split(chr(10)) if is_image(l))} images dropped")


if __name__ == "__main__":
    main()
