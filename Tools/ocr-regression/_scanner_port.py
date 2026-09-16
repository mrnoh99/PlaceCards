# -*- coding: utf-8 -*-
"""ScreenshotPlaceScanner.swift를 파이썬으로 옮긴 것.

이 파일은 Swift 원본의 **거울**이다. 스스로 진실이 아니다.
`PlaceCards/PlaceCards/Services/ScreenshotPlaceScanner.swift`의 규칙이나
상수를 고치면 여기도 같이 고쳐야 한다. 안 그러면 회귀 검사가 존재하지
않는 코드를 검사하게 된다.

옮겨 온 부분: AddressPattern.match / PlaceName.from / rows(of:) / places(in:)
옮기지 않은 부분: Vision 호출(VNRecognizeTextRequest) — 여기서 실행할 수 없다.
"""
import re

SIDO = ("(?:서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주)"
        "(?:특별시|광역시|특별자치시|특별자치도|자치도|도)?")
DISTRICT = r"(?:[가-힣]+(?:시|군|구)\s+){1,2}(?:[가-힣]+(?:읍|면)\s+)?"
PATTERNS = [
    rf"(?:{SIDO}\s+)?{DISTRICT}\S*[가-힣0-9]+(?:대로|로|길)\s?\d+(?:-\d+)?(?:번길\s?\d+)?",
    rf"(?:{SIDO}\s+)?{DISTRICT}[가-힣]+(?:동|읍|면|리)\s?\d+(?:-\d+)?",
    r"[가-힣0-9]+(?:대로|로|길)\s?\d+(?:-\d+)?",
    r"[가-힣]{2,}(?:동|읍|면|리)\s?\d+(?:-\d+)?",
]
def address_match(text):
    for pat in PATTERNS:
        ms = list(re.finditer(pat, text))
        if ms:
            best = max(ms, key=lambda m: len(m.group()))
            return best.group().strip(), best.start()
    return None

QUOTES = "'\"‘’“”"
QUOTED = re.compile(f"[{QUOTES}][^{QUOTES}]{{2,20}}[{QUOTES}]")
BARE_SIDO = SIDO
DISTRICT_TOKEN = rf"^(?:{BARE_SIDO}|[가-힣]+(?:시|군|구|동|읍|면|리))$"
MIN_LEN, MAX_LEN, MAX_SPACES = 2, 40, 2

CHROME = set("""저장 저장됨 공유 길찾기 출발 도착 리뷰 리뷰쓰기 사진 예약 전화 홈 검색 지도 주변 즐겨찾기
더보기 정보 메뉴 영업시간 편의시설 위치 상세정보 완료 취소 닫기 목록 내비게이션 거리뷰 블로그
쿠폰 주차 문의 길안내 오늘 식당이름 음식종류 지역""".split()) | {
 "영업 중","영업중","영업 종료","영업종료","지금 영업 중",
 "save","saved","share","directions","start","review","reviews","photo","photos","call",
 "website","menu","home","search","nearby","overview","about","book","order","more","done",
 "cancel","close","list","open","closed","open now","hours","parking","updates","add","edit",
 "팔로우","팔로잉","좋아요","답글","답글 달기","번역 보기","원본 오디오","게시물","스토리","릴스",
 "더 보기","공유하기","보관","instagram","follow","following","likes","like","reply",
 "translation","see translation","original audio","posts","reels","story"}

def strip_decoration(t):
    s = t
    while s and not (s[0].isalpha() or s[0].isdigit()): s = s[1:]
    while s and not (s[-1].isalpha() or s[-1].isdigit()): s = s[:-1]
    s = s.strip()
    for o, c in (("(", ")"), ("（","）")):
        if s.count(o) > s.count(c): s += c
    return s

def is_sentence(s): return sum(1 for ch in s if ch.isspace()) >= MAX_SPACES + 1
def is_admin_fragment(s):
    if re.fullmatch(BARE_SIDO, s): return True
    toks = s.split(" ")
    return len(toks) >= 2 and all(re.match(DISTRICT_TOKEN, t) for t in toks)

def place_name(raw):
    t = raw.strip()
    if not t or t.startswith("#"): return None
    q = QUOTED.search(t)
    if q:
        inner = q.group()[1:-1].strip()
        return inner or None
    c = strip_decoration(t)
    if not (MIN_LEN <= len(c) <= MAX_LEN): return None
    if not any(ch.isalpha() for ch in c): return None
    if is_sentence(c) or c.lower() in CHROME or is_admin_fragment(c): return None
    return c

LOCATION_MARKERS = set("◎◉📍🏠⌂")
ROW_TOL, COL_GAP, STATUS_BAR_MIN_Y = 0.8, 0.05, 0.96

def extract(lines):
    """lines: dict(text, x, x2, midY, h) — Vision 좌표계(원점 좌하단) 기준."""
    lines = [l for l in lines if l["midY"] - l["h"]/2 <= STATUS_BAR_MIN_Y]
    if not lines: return []
    ordered = sorted(lines, key=lambda l: -l["midY"])
    rows, cur = [], [ordered[0]]
    for l in ordered[1:]:
        ref = cur[0]
        if abs(l["midY"] - ref["midY"]) <= max(ref["h"], l["h"]) * ROW_TOL: cur.append(l)
        else: rows.append(sorted(cur, key=lambda z: z["x"])); cur = [l]
    rows.append(sorted(cur, key=lambda z: z["x"]))

    out, claimed = [], set()
    for i, row in enumerate(rows):
        anchor = next((c for c in row if address_match(c["text"])), None)
        if not anchor: continue
        addr, start = address_match(anchor["text"])
        name = None
        left = next((c for c in row if c["x2"] < anchor["x"] - COL_GAP), None)   # 규칙1
        if left: name = place_name(left["text"])
        if name is None:                                                          # 규칙2
            head = anchor["text"][:start]
            if not any(m in head for m in LOCATION_MARKERS): name = place_name(head)
        if name is None:                                                          # 규칙3
            for j in range(i-1, -1, -1):
                if j in claimed: continue
                cand = next((place_name(c["text"]) for c in rows[j]
                             if not address_match(c["text"]) and place_name(c["text"])), None)
                if cand: name = cand; claimed.add(j); break
        if name: out.append((name, addr))
    return out

def flat(texts, y0=0.9, step=0.03, h=0.02):
    """좌표가 없는 전사용: 한 줄씩 위→아래로 배치."""
    return [{"text": t, "x": 0.1, "x2": 0.9, "midY": y0 - i*step, "h": h}
            for i, t in enumerate(texts)]
