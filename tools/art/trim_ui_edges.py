#!/usr/bin/env python3
"""UI 텍스처(버튼·패널)의 먹 테두리 바깥 밝은 여백을 투명하게 만든다.

그림 세트의 버튼·패널은 테두리 바깥 몇 픽셀이 불투명한 한지색이라 배경 위에서 흰 경계로 보인다.
가장자리에서부터 밝은 픽셀을 따라 채워 나가 먹선에서 멈추고, 채운 곳의 알파를 0으로 한다.
그다음 지운 곳과 맞닿은 테두리 픽셀은 어두운 정도만큼만 남겨(알파) 경계를 부드럽게 한다.
새 그림 세트로 버튼·패널을 바꾸면 꼭 다시 돌린다 (스모크 테스트가 모서리 투명도를 확인한다).
실행: python3 tools/art/trim_ui_edges.py   (PIL 필요, 여러 번 돌려도 결과가 같다)
"""

import os
from collections import deque

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
UI_DIR = os.path.join(ROOT, "assets", "art", "ui")
FILES = ["button_normal.png", "button_hover.png", "button_pressed.png", "button_disabled.png", "panel.png"]
# 이보다 밝으면 바깥 여백으로 본다 (먹선은 어둡다)
LIGHT = 150
# 경계 픽셀: 이 밝기 이하면 완전히 남기고, LIGHT에 가까울수록 투명하게
SOLID = 90


def trim(path: str) -> int:
	im = Image.open(path).convert("RGBA")
	w, h = im.size
	px = im.load()
	seen = [[False] * w for _ in range(h)]
	queue = deque()
	for x in range(w):
		queue.append((x, 0))
		queue.append((x, h - 1))
	for y in range(h):
		queue.append((0, y))
		queue.append((w - 1, y))
	cleared = 0
	while queue:
		x, y = queue.popleft()
		if x < 0 or y < 0 or x >= w or y >= h or seen[y][x]:
			continue
		seen[y][x] = True
		r, g, b, a = px[x, y]
		if a > 0 and (r + g + b) / 3 < LIGHT:
			continue
		if a > 0:
			px[x, y] = (r, g, b, 0)
			cleared += 1
		queue.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
	# 지운 곳과 맞닿은 테두리 픽셀은 어두운 만큼만 남긴다 (계단·흰 점 없이 부드럽게)
	for y in range(h):
		for x in range(w):
			r, g, b, a = px[x, y]
			if a == 0:
				continue
			touches = any(
				0 <= nx < w and 0 <= ny < h and px[nx, ny][3] == 0
				for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1))
			)
			if not touches:
				continue
			lum = (r + g + b) / 3
			keep = min(1.0, max(0.0, (LIGHT - lum) / (LIGHT - SOLID)))
			new_a = min(a, round(255 * keep))
			if new_a != a:
				px[x, y] = (r, g, b, new_a)
	im.save(path, optimize=True)
	return cleared


if __name__ == "__main__":
	for name in FILES:
		print(name, trim(os.path.join(UI_DIR, name)))
