#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ScreenshotPlaceScanner 회귀 검사.

    python3 Tools/ocr-regression/check.py

fixtures.json의 네 세트를 _scanner_port.py(Swift 포팅본)에 통과시키고
기대값과 대조한다. 자세한 배경은 같은 폴더의 README.md 참고.
"""
import json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _scanner_port import extract

HERE = os.path.dirname(os.path.abspath(__file__))
norm = lambda s: re.sub(r"\s+", "", s or "")

def as_lines(case, layout, size):
    if layout == "text":
        return [{"text": t, "x": 0.1, "x2": 0.9, "midY": 0.9 - i * 0.03, "h": 0.02}
                for i, t in enumerate(case["lines"])]
    w, h = size
    return [{"text": c["text"], "x": c["x"] / w, "x2": c["x2"] / w,
             "midY": 1 - (c["y"] + c["h"] / 2) / h, "h": c["h"] / h}
            for c in case["cells"]]

def main():
    data = json.load(open(os.path.join(HERE, "fixtures.json"), encoding="utf-8"))
    failures, limits, checked = [], [], 0

    for s in data["sets"]:
        passed = total = 0
        for case in s["cases"]:
            got = extract(as_lines(case, s["layout"], s.get("image_size")))
            names = [n for n, _ in got]

            if case.get("expect_empty"):
                total += 1; checked += 1
                if names: failures.append(f'{s["name"]} / {case["id"]}: 비어야 하는데 {names}')
                else: passed += 1
            elif "expect_any_name" in case:
                total += 1; checked += 1
                if any(w in names for w in case["expect_any_name"]):
                    passed += 1
                    if "known_limitation" in case: limits.append(f'{s["name"]} / {case["id"]}')
                else: failures.append(f'{s["name"]} / {case["id"]}: {case["expect_any_name"]} 중 하나를 기대했으나 {names}')
            elif "expect_names_among" in case:
                allowed = {norm(x) for x in case["expect_names_among"]}
                hit = sum(1 for n in names if norm(n) in allowed)
                total += 1; checked += 1
                if hit >= case["min_correct"]: passed += 1
                else: failures.append(f'{s["name"]} / {case["id"]}: 최소 {case["min_correct"]}개 기대, {hit}개 맞음 ({names})')
            else:
                for want in case["expect"]:
                    total += 1; checked += 1
                    ok = any(want["name"] == n and norm(want["address_contains"]) in norm(a)
                             for n, a in got)
                    if ok: passed += 1
                    else: failures.append(f'{s["name"]} / {case["id"]}: {want["name"]!r} 못 찾음 → {got}')
        print(f'  {s["name"]:<14} {passed}/{total}')

    print()
    if limits:
        print("알려진 한계 (기대값이 '옳은 답'이 아니라 '현재 동작'인 케이스):")
        for l in limits: print("  ·", l)
        print()
    if failures:
        print(f"실패 {len(failures)}건 / 검사 {checked}건")
        for f in failures: print("  -", f)
        return 1
    print(f"전체 통과 ({checked}건)")
    return 0

if __name__ == "__main__":
    sys.exit(main())
