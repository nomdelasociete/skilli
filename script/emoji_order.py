#!/usr/bin/env python3
"""Writes Sources/SkilliCore/EmojiOrder.swift from Unicode's emoji-test.txt.

The emoji picker's order before anything is typed: Unicode's groups
(Smileys & Emotion, People & Body…) in Unicode's order, as Raycast and
Apple's own picker show them. macOS keeps its order only in undocumented
binary files, so skil.li ships this one. Once a year, when Unicode adds
emoji:

    curl -sSfLo /tmp/emoji-test.txt https://unicode.org/Public/emoji/latest/emoji-test.txt
    python3 script/emoji_order.py /tmp/emoji-test.txt

Kept: fully-qualified emoji, without a skin tone (Settings → Emoji puts
the one chosen on those that take it); the Component group (skin tones and
hair pieces alone) is left out.
"""

import pathlib
import re
import sys

TONES = range(0x1F3FB, 0x1F400)


def main(source: str) -> None:
    text = pathlib.Path(source).read_text(encoding="utf-8")
    version = re.search(r"^# Version: (\S+)", text, re.M).group(1)
    groups: list[tuple[str, list[str]]] = []
    for line in text.splitlines():
        if line.startswith("# group: "):
            groups.append((line[len("# group: "):].strip(), []))
            continue
        if line.startswith("#") or "; fully-qualified" not in line:
            continue
        emoji = line.split("#", 1)[1].split()[0]
        if any(ord(c) in TONES for c in emoji):
            continue
        groups[-1][1].append(emoji)
    groups = [(name, emoji) for name, emoji in groups if name != "Component" and emoji]

    rows = "\n".join(f'        ("{name}", "{" ".join(emoji)}"),' for name, emoji in groups)
    out = f'''// Written by script/emoji_order.py from Unicode's emoji-test.txt
// (Emoji {version}); run it again rather than editing this file.

/// The emoji picker's order before anything is typed: Unicode's groups, in
/// Unicode's order. Fully qualified, without skin tones (Settings → Emoji
/// puts the one chosen on those that take it).
public enum EmojiOrder {{
    public static let version = "{version}"

    /// Each group's name and its emoji, separated by spaces.
    static let groups: [(name: String, emoji: String)] = [
{rows.rstrip(",")}
    ]
}}
'''
    target = pathlib.Path(__file__).resolve().parent.parent / "Sources/SkilliCore/EmojiOrder.swift"
    target.write_text(out, encoding="utf-8")
    print(f"{target.name}: Emoji {version}, {sum(len(e) for _, e in groups)} emoji in {len(groups)} groups")


if __name__ == "__main__":
    main(sys.argv[1])
