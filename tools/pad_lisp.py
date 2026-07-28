#!/usr/bin/env python3
"""Grow the script to a target token count, to find where image-save gives up.

    python3 tools/pad_lisp.py 16400 > /tmp/padded.lisp

The padding is real code, not filler: copies of an existing function with every
symbol they introduce renamed, so each copy costs the const heap what a new
function of that size would. Load the result in VESC Tool's Lisp editor, watch
the console, and never reboot on "image-save failed" - re-upload a smaller one.
"""
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from minify_lisp import tokenize  # noqa: E402

SRC = "scooter_support.lisp"

# one copy is about 100 tokens - shaped like the rest of the script, a defun
# with a let, some arithmetic and a couple of branches
TEMPLATE = """
(defun pad-fun-%(n)d (pad-a-%(n)d pad-b-%(n)d)
    (let ((pad-c-%(n)d (+ pad-a-%(n)d pad-b-%(n)d))
          (pad-d-%(n)d (* pad-a-%(n)d 0.5)))
        {
            (if (> pad-c-%(n)d pad-d-%(n)d)
                (setq pad-c-%(n)d (- pad-c-%(n)d pad-d-%(n)d))
                (setq pad-c-%(n)d (+ pad-c-%(n)d pad-d-%(n)d))
            )
            (if (< pad-c-%(n)d 0) (setq pad-c-%(n)d 0))
            (cond
                ((= pad-b-%(n)d 1) (* pad-c-%(n)d 2))
                ((= pad-b-%(n)d 2) (/ pad-c-%(n)d 2))
                (t pad-c-%(n)d)
            )
        }
    )
)
"""


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    target = int(sys.argv[1])
    src = open(SRC).read()
    base = len(tokenize(src))
    per = len(tokenize(TEMPLATE % {"n": 0}))
    if target < base:
        sys.exit(f"{SRC} is already {base} tokens, cannot pad down to {target}")
    copies = round((target - base) / per)
    pad = "".join(TEMPLATE % {"n": i} for i in range(copies))

    # end of the last const block, so the copies land on the const heap and in
    # the image exactly like the script's own functions
    cut = src.rfind("\n@const-end")
    assert cut > 0
    out = src[:cut] + "\n" + pad + src[cut:]
    print(f"{base} + {copies} copies x {per} = {len(tokenize(out))} tokens",
          file=sys.stderr)
    sys.stdout.write(out)


if __name__ == "__main__":
    main()
