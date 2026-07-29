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

# VESC Tool's renderer applies emphasis to the source text before it works out
# what is a link, and it honours no backslash escape. So an underscore is lost
# wherever it appears - in the text as a missing character, and in a destination
# as a literal <em> inside the href. Nothing may carry one: labels avoid them,
# and encode_link_targets swaps them for %5F, which is the same character to the
# server and has nothing to pair with.
REPO_MD = "[VESC Scooter Support on GitHub](" + REPO + ")"


def is_image(line):
    return "<img " in line or re.match(r"\s*!\[", line)


def strip_images(src):
    out = []
    lines = src.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]

        # an html table of images goes whole - dropping the img lines alone would
        # leave the tr and td tags behind as markup in the description
        if "<table" in line:
            j = i
            block = []
            while j < len(lines):
                block.append(lines[j])
                if "</table>" in lines[j]:
                    break
                j += 1
            if any(is_image(b) for b in block):
                i = j + 1
                while i < len(lines) and not lines[i].strip():
                    i += 1
                out.append("")
                continue

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

        # comments are notes to whoever edits the README, never to the reader -
        # and a multi line one would otherwise spill its middle into the description
        if line.lstrip().startswith("<!--"):
            while i < len(lines) and "-->" not in lines[i]:
                i += 1
            i += 1
            while i < len(lines) and not lines[i].strip():
                i += 1
            continue

        out.append(line)
        i += 1

    text = "\n".join(out)
    return re.sub(r"\n{3,}", "\n\n", text)


def code_bare_urls(src):
    """Same trap as REPO_MD, for URLs the README writes out in full rather than
    hiding behind a label. A code span is literal in every markdown flavour, so
    the underscores survive - at the cost of not being clickable."""
    return re.sub(r"(?<![(\[<`])\bhttps?://\S*_\S*",
                  lambda m: "`" + m.group(0) + "`", src)


def encode_link_targets(src):
    """Underscores in a link destination, percent encoded so emphasis cannot reach
    them. Verified against GitHub: the %5F form serves the same repository."""
    return re.sub(r"\]\(([^)\s]*)\)",
                  lambda m: "](" + m.group(1).replace("_", "%5F") + ")", src)


def add_link(src):
    lines = src.split("\n")
    for i, line in enumerate(lines):
        if line.startswith("# "):
            lines.insert(i + 1, f"\n{REPO_MD}")
            break
    return "\n".join(lines)


def main():
    src = open(sys.argv[1]).read()
    dst = encode_link_targets(add_link(code_bare_urls(strip_images(src))))
    open(sys.argv[2], "w").write(dst)
    print(f"pkg_readme: {len(src)} -> {len(dst)} bytes, "
          f"{sum(1 for l in src.split(chr(10)) if is_image(l))} images dropped")


if __name__ == "__main__":
    main()
