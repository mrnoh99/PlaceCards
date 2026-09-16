#!/usr/bin/env python3
"""The two checks this environment can actually run against Swift source.

Neither catches a missing `import` — only CI's `xcodebuild` does.
"""
import re
import sys
from pathlib import Path

ROOT = Path("PlaceCards")
LOCALIZATION = ROOT / "PlaceCards/Services/Localization.swift"

STRING_LITERAL = r'"((?:[^"\\]|\\.)*)"'
LOCALIZED_USE = re.compile(STRING_LITERAL + r'\s*\.localized')
DICT_ENTRY = re.compile(r'^\s*' + STRING_LITERAL + r'\s*:\s*' + STRING_LITERAL + r'\s*,\s*$')


def swift_files():
    return sorted(p for p in ROOT.rglob("*.swift"))


def strip_strings_and_comments(source: str) -> str:
    """Remove anything a brace inside which shouldn't count."""
    out = []
    i = 0
    n = len(source)
    while i < n:
        ch = source[i]
        if source.startswith('"""', i):
            end = source.find('"""', i + 3)
            i = n if end == -1 else end + 3
            continue
        if ch == '"':
            i += 1
            while i < n:
                if source[i] == '\\':
                    i += 2
                    continue
                if source[i] == '"':
                    i += 1
                    break
                i += 1
            continue
        if source.startswith("//", i):
            end = source.find("\n", i)
            i = n if end == -1 else end
            continue
        if source.startswith("/*", i):
            end = source.find("*/", i + 2)
            i = n if end == -1 else end + 2
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def check_balance():
    pairs = {"(": ")", "[": "]", "{": "}"}
    closers = {v: k for k, v in pairs.items()}
    problems = []
    for path in swift_files():
        stack = []
        for ch in strip_strings_and_comments(path.read_text(encoding="utf-8")):
            if ch in pairs:
                stack.append(ch)
            elif ch in closers:
                if not stack or stack[-1] != closers[ch]:
                    problems.append((path, f"unexpected {ch!r}"))
                    break
                stack.pop()
        else:
            if stack:
                problems.append((path, f"unclosed {''.join(stack)!r}"))
    return problems


def localization_report():
    used = set()
    for path in swift_files():
        if path == LOCALIZATION:
            continue
        for match in LOCALIZED_USE.finditer(path.read_text(encoding="utf-8")):
            used.add(match.group(1))

    defined = []
    inside = False
    for line in LOCALIZATION.read_text(encoding="utf-8").splitlines():
        if "englishTranslations" in line:
            inside = True
            continue
        if inside:
            if line.strip() == "]":
                break
            entry = DICT_ENTRY.match(line)
            if entry:
                defined.append(entry.group(1))

    duplicates = sorted({k for k in defined if defined.count(k) > 1})
    defined_set = set(defined)
    return sorted(used - defined_set), sorted(defined_set - used), duplicates


def main():
    failed = False

    problems = check_balance()
    print("괄호 균형")
    if problems:
        for path, reason in problems:
            print(f"  ✗ {path}: {reason}")
    else:
        print("  ✓ 이상 없음")

    missing, unused, duplicates = localization_report()
    print(f"\n번역  MISSING {len(missing)} · UNUSED {len(unused)} · 중복 {len(duplicates)}")
    for key in missing:
        print(f"  MISSING  {key}")
    for key in unused:
        print(f"  UNUSED   {key}")
    for key in duplicates:
        print(f"  DUPLICATE {key}")
        failed = True

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
