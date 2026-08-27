"""Custom Grammarinator serializer that interleaves trivia between tokens.

Replaces grammarinator.runtime.serializer.simple_space_serializer.

The Teal grammar marks COMMENT/LINE_COMMENT as channel(HIDDEN) and WS as
skip, so Grammarinator never emits them. This serializer compensates by
picking a random separator (space, newline, comment, fmt:off region, ...)
between each pair of generated tokens. With a high enough trivia rate,
comments land at every grammar position by chance — including the
op_leading/op_trailing/before_separator/head/after_opener slots from the
formatter's comment model.

Draws from the global `random`, which grammarinator reseeds per test case as
`random_seed + index` (grammarinator.generate.create_test). A private
Random(seed) would instead replay one identical trivia stream for every file in
a seeded run, so reproducibility comes from --random-seed alone.

Knobs (env vars, read once per call):

    FUZZ_TRIVIA_RATE   float in [0,1]. Probability that a token gap is filled
                       with something other than a single space. 0.0 = behaves
                       exactly like simple_space_serializer. Default: 0.3.
"""

import os
import random

from grammarinator.runtime import Rule


_LINE_COMMENT_BODIES = [
    "x",
    "TODO",
    "note: comment text",
    "-- nested dashes",
    "trailing ]]",
    "with ]==] embedded",
]

_BLOCK_COMMENT_BODIES = [
    "b",
    "block comment",
    "with ] inside",
    "with ]] inside",
    "multi\nline\nblock",
]

_LONG_BLOCK_BODIES = [
    "long ] block",
    "long ]= block",
    "long ]== block",
    "multi\nline\nlong\nblock",
]


def _line_comment() -> str:
    return "-- " + random.choice(_LINE_COMMENT_BODIES) + "\n"


def _closes_early(body: str, level: int) -> bool:
    eq = "=" * level
    # A body ending in the closer minus its final ']' fuses with the closer we
    # append, so `--[[x]]]` closes after `x` and leaves a stray ']' as code.
    return "]" + eq + "]" in body or body.endswith("]" + eq)


def _bracket_comment(body: str, min_level: int) -> str:
    level = min_level
    while _closes_early(body, level):
        level += 1
    eq = "=" * level
    return "--[" + eq + "[" + body + "]" + eq + "]"


def _block_comment() -> str:
    return _bracket_comment(random.choice(_BLOCK_COMMENT_BODIES), 0)


def _long_block_comment() -> str:
    return _bracket_comment(random.choice(_LONG_BLOCK_BODIES), random.randint(1, 3))


def _fmt_off_region() -> str:
    return "-- fmt:off\n"


def _fmt_on_region() -> str:
    return "-- fmt:on\n"


def _pick_separator(rate: float, fmt_off_active: list) -> str:
    if random.random() >= rate:
        return " "

    choices = [
        ("space", 4),
        ("newline", 3),
        ("blank_line", 2),
        ("line_comment", 3),
        ("block_comment", 3),
        ("long_block", 1),
        ("fmt_toggle", 1),
    ]
    total = sum(weight for _, weight in choices)
    roll = random.uniform(0, total)
    acc = 0
    pick = choices[-1][0]
    for name, weight in choices:
        acc += weight
        if roll <= acc:
            pick = name
            break

    if pick == "space":
        return " "
    if pick == "newline":
        return "\n"
    if pick == "blank_line":
        return "\n\n"
    if pick == "line_comment":
        return " " + _line_comment()
    if pick == "block_comment":
        return " " + _block_comment() + " "
    if pick == "long_block":
        return " " + _long_block_comment() + " "
    if pick == "fmt_toggle":
        if fmt_off_active[0]:
            fmt_off_active[0] = False
            return "\n" + _fmt_on_region()
        fmt_off_active[0] = True
        return "\n" + _fmt_off_region()
    return " "


def trivia_serializer(root: Rule) -> str:
    rate_str = os.environ.get("FUZZ_TRIVIA_RATE", "0.3")
    try:
        rate = float(rate_str)
    except ValueError:
        rate = 0.3
    rate = max(0.0, min(1.0, rate))

    tokens = list(root.tokens())
    if not tokens:
        return ""

    parts = [tokens[0]]
    fmt_off_active = [False]
    for tok in tokens[1:]:
        parts.append(_pick_separator(rate, fmt_off_active))
        parts.append(tok)

    if fmt_off_active[0]:
        parts.append("\n" + _fmt_on_region())

    return "".join(parts)
