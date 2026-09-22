#!/usr/bin/env python3
"""Localization.swift의 번역 사전을 검사한다.

두 가지를 본다:

1. **사전 구조.** 괄호 균형 검사로는 잡히지 않는 오류가 있다 — 값이 다음
   줄에 오는 두 줄짜리 항목

       "긴 한국어 키":
           "Its English value",

   의 key와 value 사이에 새 항목을 끼워 넣으면 괄호 수는 그대로인데 사전은
   깨진다. CI는 이렇게 터진다:

       error: expected key expression in dictionary literal
       error: expected ':' in dictionary literal

   실제로 한 번 이렇게 CI를 터뜨렸다(198차). 사전 몸통을 토큰화해서
   `"키" : "값" ,` 의 반복인지 확인한다.

2. **문자열 이스케이프.** Swift 문자열에서 `\\`는 정해진 몇 가지 뒤에만 올 수
   있다. 사전을 스크립트로 고치다 보면 `\\u2014`(파이썬에서 `\\\\u2014`를 쓴
   실수)나 `\\"`를 겹쳐 쓴 것이 들어가는데, 괄호 수도 사전 구조도 멀쩡해
   두 검사를 다 지난다. CI는 이렇게 터진다:

       error: expected hexadecimal code in braces after unicode escape
       error: invalid escape sequence in literal

   실제로 두 번 이렇게 터뜨렸다(`\\"PinSpots\\"`, `\\u2014`). 값 안의 모든
   `\\`가 Swift가 아는 이스케이프인지 본다.

3. **번역 누락.** 앱 코드의 `"…".localized` 한국어 리터럴 중 사전에 없는 것.
   단, `CSVExport`처럼 `.map { $0.localized }`로 일괄 번역하는 곳이 있으므로
   리터럴만 훑는 이 검사는 *미사용 키*는 판단하지 못한다 — 누락만 본다.

사용법:  python3 Tools/localization/check.py
"""
import glob
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LOC = os.path.join(ROOT, "PlaceCards/PlaceCards/Services/Localization.swift")
SWIFT_GLOB = os.path.join(ROOT, "PlaceCards/**/*.swift")


def dictionary_body(src):
    """`englishTranslations = [ … ]`의 몸통. 문자열 안의 괄호는 건너뛴다."""
    start = src.index("= [", src.index("englishTranslations")) + 2
    depth, i = 0, start
    while True:
        ch = src[i]
        if ch == '"':
            i += 1
            while src[i] != '"':
                i += 2 if src[i] == "\\" else 1
        elif ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                return src[start + 1:i]
        i += 1


def tokenize(body):
    body = re.sub(r"//[^\n]*", "", body)
    tokens, j = [], 0
    while j < len(body):
        ch = body[j]
        if ch == '"':
            k = j + 1
            while body[k] != '"':
                k += 2 if body[k] == "\\" else 1
            tokens.append(("str", body[j + 1:k]))
            j = k + 1
        elif ch in ":,":
            tokens.append((ch, ch))
            j += 1
        elif ch.isspace():
            j += 1
        else:
            raise SystemExit("FAIL: 사전 안에 예상치 못한 문자 %r" % ch)
    return tokens


def main():
    src = io.open(LOC, encoding="utf-8").read()
    tokens = tokenize(dictionary_body(src))

    failures = 0
    order = ["str", ":", "str", ","]
    for n, (kind, _) in enumerate(tokens):
        if kind != order[n % 4]:
            near = next((t for k, t in reversed(tokens[:n + 1]) if k == "str"), "?")
            print("FAIL: 사전이 깨졌습니다 — %r 근처에서 %r가 와야 할 자리에 %r"
                  % (near[:40], order[n % 4], kind))
            failures += 1
            if failures > 5:
                break
    if failures:
        return 1
    if len(tokens) % 4 != 0:
        print("FAIL: 마지막 항목이 잘렸습니다 (토큰 %d개)" % len(tokens))
        return 1

    keys = [t for n, (_, t) in enumerate(tokens) if n % 4 == 0]
    print("사전 구조 정상 — %d개 항목." % len(keys))

    # 토큰 안의 문자열은 따옴표를 벗긴 **원문**이라, 여기 남은 `\`는 전부
    # Swift가 해석할 이스케이프다. Swift가 아는 것만 통과시킨다.
    legal = set('"\\nt0r\\\\\'u(')
    bad_escapes = []
    for _, text in tokens:
        for m in re.finditer(r"\\(.)", text):
            if m.group(1) not in legal:
                bad_escapes.append((text[:40], m.group(0)))
            elif m.group(1) == "u" and not re.match(r"\\u\{[0-9A-Fa-f]{1,8}\}", m.group(0) + text[m.end():m.end() + 10]):
                bad_escapes.append((text[:40], "\\u (중괄호 없음)"))
    if bad_escapes:
        print("FAIL: Swift가 모르는 이스케이프 %d건" % len(bad_escapes))
        for near, esc in bad_escapes[:10]:
            print("  %r 안의 %s" % (near, esc))
        return 1

    dupes = sorted({k for k in keys if keys.count(k) > 1})
    if dupes:
        print("경고: 키 중복 %d건 — 뒤엣것이 이깁니다: %s" % (len(dupes), dupes[:5]))

    known = set(keys)
    missing = []
    for path in glob.glob(SWIFT_GLOB, recursive=True):
        if path.endswith("Localization.swift"):
            continue
        text = io.open(path, encoding="utf-8").read()
        for m in re.finditer(r'"((?:[^"\\]|\\.)*)"\s*\.localized', text):
            key = m.group(1)
            if key not in known and re.search(r"[가-힣]", key):
                missing.append((os.path.basename(path), key))
    if missing:
        print("FAIL: 번역 누락 %d건" % len(missing))
        for name, key in missing:
            print("  %s | %s" % (name, key[:70]))
        return 1
    print("번역 누락 없음.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
