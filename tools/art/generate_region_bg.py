#!/usr/bin/env python3
"""지역 배경 생성기: 강호 지도의 지역마다 다른 산수화 배경을 만든다.

render_shanshui.js로 찍은 shan-shui-inf(MIT) 산수화 밑그림에 지역의 성격(설산·사막·강남 물가·도성·남방 숲 등)에 맞는
색을 입히고, 지역 이름을 붓글씨와 낙관으로 넣는다. 경영 화면은 지금 있는 지역의 배경을 보인다.
나중에 그린 그림으로 바꾸려면 같은 이름·크기(1280×720)로 assets/art/bg/regions/<지역 id>.jpg를 덮어쓰면 된다.
지도 데이터에서 지역의 background를 정하면(청운산 → bg/hub.jpg) 그 그림을 쓴다. 그래서 청운산은 만들지 않는다.

실행:
  curl -sSfL -o <작업폴더>/index.html https://raw.githubusercontent.com/LingDong-/shan-shui-inf/master/index.html
  node tools/art/render_shanshui.js <작업폴더>/index.html <밑그림 폴더> 301 302 ... 320
  python3 tools/art/generate_region_bg.py <밑그림 폴더>     (PIL, numpy 필요)
"""

from __future__ import annotations

import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_art import (  # noqa: E402
	GOLD, INDIGO, INK, JADE, OCHRE, PAPER, VERMILION, brush_text, fractal_noise, multiply, paste_seal, radial,
	to_image, vertical,
)

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "art", "bg", "regions")
REGIONS = os.path.join(ROOT, "data", "map", "regions.json")
SIZE = (1280, 720)

# 지역 id → (산수화 시드, 성격)
# 성격: snow 설산 · desert 서역 사막 · capital 도성 · water 강남 물가 · mountain 산악 · south 남방 숲 · plain 중원 들판
REGION_STYLE = {
	"tianshan": (316, "snow"),
	"lanzhou": (306, "desert"),
	"xian": (311, "capital"),
	"taiyuan": (313, "mountain"),
	"taihang": (304, "mountain"),
	"luoyang": (309, "capital"),
	"kaifeng": (317, "plain"),
	"jinan": (315, "water"),
	"beijing": (318, "capital"),
	"hefei": (307, "plain"),
	"yangzhou": (305, "water"),
	"hangzhou": (303, "water"),
	"wudang": (301, "mountain"),
	"hanzhong": (302, "mountain"),
	"chengdu": (308, "south"),
	"wuchang": (310, "water"),
	"changsha": (319, "south"),
	"nanchang": (312, "water"),
	"kunming": (314, "south"),
}


def tint(img: np.ndarray, style: str, rng: np.random.Generator) -> np.ndarray:
	h, w, _ = img.shape
	if style == "snow":
		# 눈 덮인 설산: 하늘을 차갑게, 먹을 옅게
		img[:] = img * 0.75 + 0.25
		multiply(img, INDIGO * 1.7, (1 - vertical(h, w, 0.0, 0.7)) * 0.25)
		multiply(img, INDIGO * 1.9, 0.08)
	elif style == "desert":
		# 서역의 모래 바람: 황토색으로 덮고 바람결 얼룩
		multiply(img, OCHRE * 1.25, 0.35)
		wind = fractal_noise(rng, w, h, 3, 4)
		multiply(img, OCHRE, np.clip((wind - 0.5) * 1.5, 0, 1) * 0.25)
	elif style == "capital":
		# 도성: 금빛 노을과 붉은 기운
		multiply(img, GOLD * 1.2, vertical(h, w, 0.0, 0.6) * 0.28)
		multiply(img, VERMILION * 1.4, radial(w, h, w * 0.8, h * 0.18, h * 0.12, h * 0.05) * 0.35)
	elif style == "water":
		# 강남 물가: 아래쪽에 쪽빛 물안개
		multiply(img, INDIGO * 1.5, (1 - vertical(h, w, 0.45, 1.0)) * 0.3)
		multiply(img, JADE * 1.6, 0.06)
	elif style == "mountain":
		# 깊은 산: 산허리에 청록, 먹을 조금 짙게
		img[:] = np.clip(img * 1.0 - (1 - img) * 0.12, 0, 1)
		multiply(img, JADE * 1.5, (1 - vertical(h, w, 0.25, 0.9)) * 0.18)
	elif style == "south":
		# 남방의 무성한 숲: 짙은 청록
		multiply(img, JADE * 1.3, 0.22)
		multiply(img, JADE, (1 - vertical(h, w, 0.4, 1.0)) * 0.15)
	else:
		# 중원 들판: 옅은 황토와 연두
		multiply(img, OCHRE * 1.5, (1 - vertical(h, w, 0.5, 1.0)) * 0.2)
		multiply(img, JADE * 1.8, 0.05)
	return img


def main() -> None:
	base_dir = sys.argv[1] if len(sys.argv) > 1 else ""
	regions = {r["id"]: r for r in json.load(open(REGIONS, encoding="utf-8"))["regions"]}
	os.makedirs(OUT, exist_ok=True)
	for i, (region_id, (seed, style)) in enumerate(REGION_STYLE.items()):
		path = os.path.join(base_dir, f"shanshui_{seed}_0.png")
		if not os.path.exists(path):
			print("밑그림 없음:", path)
			continue
		rng = np.random.default_rng(20261018 + i)
		img = np.asarray(Image.open(path).convert("RGB").resize(SIZE, Image.LANCZOS), np.float32) / 255.0
		out = to_image(tint(img.copy(), style, rng)).convert("RGBA")
		name = regions.get(region_id, {}).get("name", region_id)
		# 오른쪽 위에 지역 이름을 세로 붓글씨로, 그 아래 낙관
		size = 64
		brush_text(out, name, size, (SIZE[0] - 70, 28), INK, 215, vertical=True)
		paste_seal(out, name[0], 44, (SIZE[0] - 92, 28 + int(size * 0.92) * len(name) + 8), rng)
		out.convert("RGB").save(os.path.join(OUT, f"{region_id}.jpg"), quality=80, optimize=True)
		print("  bg/regions/%s.jpg (%s)" % (region_id, style))


if __name__ == "__main__":
	main()
