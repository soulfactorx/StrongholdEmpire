#!/usr/bin/env python3
"""수묵 인물 초상화·세력 문장 생성기.

주의: 지금 assets/art/에는 프로젝트 소유자가 넣은 그림 세트가 있다. 이 스크립트는 그 그림을 덮어쓴다.

- 초상화: 한지 바탕에 담채 후광, 먹선 상반신(머리 모양·관·두건·수염·옷깃·무기), 세로 붓글씨 이름과 낙관.
  NPC는 assets/art/portraits/<npc_id>.jpg, 주인공 역할은 assets/art/portraits/role_<역할>.jpg (256×320)
- 문장: assets/art/emblems/<sect_id>.png (256×256, 투명 바탕)

같은 이름·크기 파일로 덮어쓰면 코드 수정 없이 바뀐다 (AI로 그린 초상화 등).
실행: python3 tools/art/generate_portraits.py   (PIL, numpy 필요)
"""

from __future__ import annotations

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_art as ga  # noqa: E402  (한지·낙관·붓글꼴 도구를 함께 쓴다)

OUT = os.path.join(ga.ROOT, "assets", "art")
W, H = 512, 640  # 크게 그린 뒤 반으로 줄인다

SKIN = (236, 214, 184)
INK = (30, 28, 26)

# 세력 색 (담채): 옷과 후광
TINTS = {
	"qingyun": (70, 128, 112),
	"namgung": (64, 84, 128),
	"heukpung": (96, 78, 60),
	"cheonma": (140, 40, 36),
	"none": (150, 120, 80),
	"light": (200, 196, 178),
	"white": (226, 222, 208),
	"black": (52, 50, 52),
	"rose": (178, 92, 86),
	"green": (70, 96, 60),
}

# 인물 모습: hair(머리) · headwear(관·띠·두건) · robe(옷 색) · weapon · face(표정) · beard · 기타
NPCS = {
	"npc_bandit": dict(hair="messy", headwear="headband", robe="heukpung", weapon="saber", face="stern", scar=True),
	"npc_cheonma": dict(hair="long", headwear="tall_crown", robe="cheonma", face="stern", beard="short", age=50, eyes_red=True),
	"npc_cheonma_cultist": dict(hair="none", headwear="hood_mask", robe="cheonma", hood_color="cheonma", face="stern"),
	"npc_cheonma_envoy": dict(hair="long", headwear="headband", robe="black", weapon="sword", face="stern", scar=True),
	"npc_disciple": dict(hair="topknot", robe="qingyun", weapon="sword", face="gentle", young=True),
	"npc_healer": dict(hair="bun", female=True, robe="white", face="gentle", accent="qingyun"),
	"npc_heukpung_chief": dict(hair="messy", headwear="headband", robe="heukpung", weapon="saber", face="stern", beard="full", scar=True, age=45),
	"npc_heukpung_second": dict(hair="long", robe="green", weapon="dagger", face="sly"),
	"npc_iron_blade": dict(hair="topknot", robe="light", weapon="greatsword", face="stern", beard="stubble", age=40),
	"npc_master": dict(hair="topknot", headwear="crown", robe="white", accent="qingyun", weapon="sword", face="gentle", beard="long", age=70),
	"npc_namgung_enforcer": dict(hair="topknot", headwear="crown", robe="namgung", weapon="sword", face="stern", beard="short", age=40),
	"npc_namgung_guard": dict(hair="topknot", headwear="headband_blue", robe="namgung", weapon="spear", face="neutral"),
	"npc_namgung_lady": dict(hair="half_up", female=True, robe="namgung", accent="white", face="gentle", young=True),
	"npc_namgung_lord": dict(hair="topknot", headwear="crown", robe="namgung", face="stern", beard="long", age=55),
	"npc_rival": dict(hair="topknot", headwear="crown", robe="namgung", accent="white", weapon="sword", face="proud", young=True),
	"npc_scholar": dict(hair="topknot", headwear="scholar_cap", robe="white", weapon="fan", face="gentle", young=True),
	"npc_senior_brother": dict(hair="topknot", robe="qingyun", weapon="sword", face="neutral"),
	"npc_shadow_blade": dict(hair="none", headwear="hood_mask", robe="black", hood_color="black", weapon="dagger", face="stern"),
	"npc_swallow": dict(hair="ponytail", female=True, robe="rose", accent="white", weapon="sword", face="proud"),
}

# 주인공 역할별 초상화 (CharacterData.Role 이름)
ROLES = {
	"YOUNG_DISCIPLE": ("이청풍", dict(hair="topknot", robe="qingyun", face="gentle", young=True)),
	"WANDERER": ("독고휘", dict(hair="long", robe="light", weapon="sword", face="neutral", beard="stubble")),
	"MERCENARY": ("모용진", dict(hair="topknot", headwear="headband", robe="none", weapon="saber", face="proud")),
	"LEADER": ("청운도", dict(hair="topknot", headwear="crown", robe="qingyun", accent="white", weapon="sword", face="stern", beard="short", age=32)),
	"MANAGER": ("총관", dict(hair="topknot", headwear="scholar_cap", robe="qingyun", weapon="fan", face="gentle")),
	"SPY": ("밀정", dict(hair="topknot", headwear="hood", hood_color="namgung", robe="black", weapon="dagger", face="sly")),
	"ASSASSIN": ("자객", dict(hair="none", headwear="hood_mask", hood_color="black", robe="black", weapon="dagger", face="stern")),
}

SECT_EMBLEMS = {
	"qingyun": ("청운", "circle", "qingyun"),
	"namgung": ("남궁", "square", "namgung"),
	"heukpung": ("흑풍", "octagon", "black"),
	"cheonma": ("천마", "circle_double", "cheonma"),
}


def mix(a, b, t):
	return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(3))


def rgba(c, a=255):
	return (c[0], c[1], c[2], a)


def brush_poly(draw: ImageDraw.ImageDraw, pts, width, color, rng, closed=True):
	"""굵기가 조금씩 흔들리는 먹선"""
	seq = list(pts) + ([pts[0]] if closed else [])
	for i in range(len(seq) - 1):
		w = max(2, int(width * rng.uniform(0.75, 1.2)))
		draw.line([seq[i], seq[i + 1]], fill=color, width=w)
		draw.ellipse((seq[i + 1][0] - w / 2, seq[i + 1][1] - w / 2, seq[i + 1][0] + w / 2, seq[i + 1][1] + w / 2), fill=color)


def bezier(p0, p1, p2, n=24):
	return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
		(1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]) for t in np.linspace(0, 1, n)]


def wash_layer(size, mask: Image.Image, color, alpha, rng) -> Image.Image:
	"""마스크 모양으로 번지는 담채: 가장자리를 흐리고 얼룩을 섞는다"""
	w, h = size
	noise = ga.fractal_noise(rng, w, h, 4, 4)
	m = np.asarray(mask.filter(ImageFilter.GaussianBlur(3)), np.float32) / 255.0
	a = m * alpha * (0.7 + 0.5 * noise)
	arr = np.zeros((h, w, 4), np.uint8)
	arr[..., 0], arr[..., 1], arr[..., 2] = color
	arr[..., 3] = np.clip(a * 255, 0, 255).astype(np.uint8)
	return Image.fromarray(arr)


def body_shape():
	"""어깨와 몸통 윤곽 (위쪽 목에서 아래 가장자리까지)"""
	left = bezier((222, 352), (120, 380), (40, 520)) + [(10, 640)]
	right = [(502, 640)] + bezier((472, 520), (392, 380), (290, 352))
	return left + right


def portrait(name: str, spec: dict, seed: int) -> Image.Image:
	rng = np.random.default_rng(seed)
	female = spec.get("female", False)
	age = spec.get("age", 22 if spec.get("young") else 30)
	robe = TINTS[spec.get("robe", "none")]
	accent = TINTS[spec.get("accent", "white")]
	hair_col = INK if age < 50 else (150, 148, 144)
	if age >= 65:
		hair_col = (205, 203, 198)

	base = ga.to_image(ga.paper(rng, W, H, ga.PAPER * 1.01, 0.7)).convert("RGBA")
	# 후광: 세력 색 담채 원
	halo = Image.new("L", (W, H), 0)
	ImageDraw.Draw(halo).ellipse((96, 90, 416, 410), fill=255)
	base.alpha_composite(wash_layer((W, H), halo.filter(ImageFilter.GaussianBlur(30)), robe, 0.35, rng))

	layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
	d = ImageDraw.Draw(layer)
	cx, cy = 256, 250  # 머리 중심
	rx, ry = (62, 80) if female else (68, 86)

	# ── 뒤쪽: 무기, 늘어뜨린 머리 ──
	weapon = spec.get("weapon")
	if weapon in ("sword", "greatsword", "saber", "spear"):
		x0, y0, x1, y1 = (300, 640, 452, 190) if weapon != "spear" else (330, 640, 470, 40)
		blade_w = {"sword": 10, "greatsword": 18, "saber": 14, "spear": 8}[weapon]
		d.line([(x0, y0), (x1, y1)], fill=rgba((90, 88, 84)), width=blade_w)
		# 손잡이와 코등이 (어깨 위로 보인다)
		gx, gy = x1 - (x1 - x0) * 0.18, y1 + (y0 - y1) * 0.18
		if weapon == "spear":
			d.polygon([(x1, y1 - 30), (x1 - 10, y1 + 10), (x1 + 10, y1 + 6)], fill=rgba((120, 118, 112)))
			d.line([(x1 - 4, y1 + 16), (x1 - 14, y1 + 50)], fill=rgba(ga_vermilion()), width=6)
		else:
			d.line([(gx - 24, gy - 10), (gx + 24, gy + 10)], fill=rgba(INK), width=8)
			d.line([(gx, gy), (x1 + (x1 - x0) * 0.02, y1 - 6)], fill=rgba((60, 40, 30)), width=blade_w + 4)
			d.line([(x1, y1), (x1 + 6, y1 + 40)], fill=rgba(ga_vermilion()), width=4)  # 수술
	hair = spec.get("hair", "topknot")
	if hair in ("long",) or (female and hair in ("half_up",)):
		pts = [(cx - rx - 6, cy - 20), (cx - rx - 30, cy + 140), (cx - rx - 10, cy + 260), (cx + rx + 10, cy + 260),
			(cx + rx + 30, cy + 140), (cx + rx + 6, cy - 20)]
		d.polygon(pts, fill=rgba(hair_col))
		for k in range(10):
			x = cx - rx - 20 + k * (2 * rx + 40) / 9
			d.line([(x, cy + 40), (x + rng.uniform(-10, 10), cy + 250)], fill=rgba(mix(hair_col, (90, 90, 90), 0.3)), width=2)
	if hair == "ponytail":
		d.polygon([(cx + 20, cy - 80), (cx + 120, cy - 40), (cx + 150, cy + 120), (cx + 110, cy + 200), (cx + 70, cy - 40)], fill=rgba(hair_col))

	# ── 몸: 담채 옷 + 먹선 윤곽 + 교차 옷깃 ──
	body_mask = Image.new("L", (W, H), 0)
	ImageDraw.Draw(body_mask).polygon(body_shape(), fill=255)
	# 뒤의 칼·머리가 비치지 않게 먼저 불투명하게 칠하고 담채 얼룩을 얹는다
	layer.paste(Image.new("RGBA", (W, H), rgba(mix(robe, (236, 230, 212), 0.35))), (0, 0), body_mask)
	layer.alpha_composite(wash_layer((W, H), body_mask, robe, 0.75, rng))
	# 옷 주름
	for k in range(6):
		x = rng.uniform(60, 450)
		d.line([(x, rng.uniform(470, 540)), (x + rng.uniform(-30, 30), 640)], fill=rgba(mix(robe, INK, 0.5), 140), width=3)
	brush_poly(d, body_shape(), 6, rgba(INK, 235), rng, closed=False)
	# 목
	d.rectangle((cx - 28, cy + 50, cx + 28, cy + 115), fill=rgba(mix(SKIN, (200, 170, 140), 0.25)))
	# 안깃(흰 띠)과 겉깃: 왼깃이 오른쪽 아래로 덮는다
	# 오른깃(아래): 오른쪽 목에서 가운데로 내려와 왼깃 밑으로 들어간다
	right_band = [(cx + 46, 350), (cx + 20, 350), (cx - 10, 440), (cx + 14, 446)]
	d.polygon(right_band, fill=rgba(accent))
	brush_poly(d, [(cx + 46, 350), (cx + 14, 446)], 4, rgba(INK, 220), rng, closed=False)
	# 왼깃(위): 왼쪽 목에서 오른쪽 아래로 길게 덮는다
	left_band = [(cx - 46, 350), (cx - 20, 350), (cx + 80, 540), (cx + 54, 552)]
	d.polygon(left_band, fill=rgba(accent))
	brush_poly(d, [(cx - 46, 350), (cx + 54, 552)], 4, rgba(INK, 220), rng, closed=False)
	brush_poly(d, [(cx - 20, 350), (cx + 80, 540)], 4, rgba(INK, 220), rng, closed=False)
	# 띠
	d.line([(60, 590), (452, 590)], fill=rgba(mix(robe, INK, 0.45)), width=22)

	# ── 머리: 얼굴 ──
	headwear = spec.get("headwear", "")
	hooded = headwear.startswith("hood")
	if hooded:
		hood = TINTS[spec.get("hood_color", "black")]
		hood_pts = [(cx - rx - 40, cy + 120), (cx - rx - 30, cy - 40), (cx - 40, cy - ry - 40), (cx + 40, cy - ry - 40),
			(cx + rx + 30, cy - 40), (cx + rx + 40, cy + 120), (cx + rx + 70, 380), (cx - rx - 70, 380)]
		hmask = Image.new("L", (W, H), 0)
		ImageDraw.Draw(hmask).polygon(hood_pts, fill=255)
		layer.alpha_composite(wash_layer((W, H), hmask, hood, 0.95, rng))
		brush_poly(d, hood_pts, 5, rgba(INK, 220), rng)
		rx2, ry2 = rx - 10, ry - 12
	else:
		rx2, ry2 = rx, ry
	d.ellipse((cx - rx2, cy - ry2, cx + rx2, cy + ry2), fill=rgba(SKIN))
	# 귀
	if not hooded and hair not in ("long",) and not female:
		for side in (-1, 1):
			ex = cx + side * (rx2 - 2)
			d.ellipse((ex - 12, cy - 12, ex + 12, cy + 22), fill=rgba(mix(SKIN, (200, 160, 130), 0.2)))
	brush_poly(d, [(cx + rx2 * math.cos(t), cy + ry2 * math.sin(t)) for t in np.linspace(math.pi * 0.05, math.pi * 0.95, 16)],
		3, rgba(INK, 200), rng, closed=False)

	# ── 머리카락과 관 ──
	if not hooded and hair != "none":
		hm = Image.new("L", (W, H), 0)
		hd = ImageDraw.Draw(hm)
		hd.ellipse((cx - rx - 6, cy - ry - 10, cx + rx + 6, cy + ry - 30), fill=255)
		# 이마 선 아래는 지운다
		line_y = cy - 22 if female else cy - 30
		hd.rectangle((0, line_y, W, H), fill=0)
		if female or hair in ("long", "messy"):
			# 옆머리
			hd.polygon([(cx - rx - 6, cy - 40), (cx - rx + 12, cy - 40), (cx - rx + 8, cy + 60), (cx - rx - 8, cy + 70)], fill=255)
			hd.polygon([(cx + rx + 6, cy - 40), (cx + rx - 12, cy - 40), (cx + rx - 8, cy + 60), (cx + rx + 8, cy + 70)], fill=255)
		# 앞머리 가르마 곡선
		hd.ellipse((cx - 60, line_y - 20, cx + 60, line_y + 14), fill=0)
		hd.rectangle((cx - 60, line_y - 6, cx + 60, line_y + 14), fill=0)
		hair_img = Image.new("RGBA", (W, H), rgba(hair_col))
		layer.paste(hair_img, (0, 0), hm)
		if hair == "messy":
			for k in range(14):
				a = rng.uniform(math.pi * 1.05, math.pi * 1.95)
				r0 = rx + 2
				x0, y0 = cx + r0 * math.cos(a), cy - 20 + (ry - 10) * math.sin(a)
				d.line([(x0, y0), (x0 + 22 * math.cos(a), y0 + 22 * math.sin(a))], fill=rgba(hair_col), width=6)
		if hair in ("topknot",) or (hair == "messy"):
			d.ellipse((cx - 30, cy - ry - 52, cx + 30, cy - ry + 6), fill=rgba(hair_col))
		if hair == "bun":
			d.ellipse((cx - 46, cy - ry - 60, cx + 46, cy - ry + 14), fill=rgba(hair_col))
			d.line([(cx - 70, cy - ry - 10), (cx + 70, cy - ry - 40)], fill=rgba((190, 160, 80)), width=6)  # 비녀
			d.ellipse((cx + 60, cy - ry - 52, cx + 80, cy - ry - 32), fill=rgba(ga_vermilion()))
		if hair == "half_up":
			d.ellipse((cx - 40, cy - ry - 40, cx + 40, cy - ry + 10), fill=rgba(hair_col))
			for k in range(3):
				d.ellipse((cx - 58 + k * 40, cy - ry - 36, cx - 42 + k * 40, cy - ry - 20), fill=rgba((200, 170, 90)))
		if hair == "ponytail":
			d.ellipse((cx - 26, cy - ry - 34, cx + 26, cy - ry + 10), fill=rgba(hair_col))
			d.line([(cx + 10, cy - ry - 20), (cx + 40, cy - ry - 30)], fill=rgba(ga_vermilion()), width=10)  # 끈

	if headwear == "crown":
		d.rectangle((cx - 26, cy - ry - 58, cx + 26, cy - ry - 18), fill=rgba((176, 146, 70)))
		d.line([(cx - 60, cy - ry - 40), (cx + 60, cy - ry - 40)], fill=rgba((120, 100, 60)), width=5)  # 동곳
	elif headwear == "tall_crown":
		d.polygon([(cx - 34, cy - ry - 8), (cx - 24, cy - ry - 110), (cx + 24, cy - ry - 110), (cx + 34, cy - ry - 8)], fill=rgba((40, 30, 30)))
		d.line([(cx - 24, cy - ry - 80), (cx + 24, cy - ry - 80)], fill=rgba(ga_vermilion()), width=6)
	elif headwear == "scholar_cap":
		d.polygon([(cx - rx - 4, cy - 34), (cx - rx + 6, cy - ry - 40), (cx + rx - 6, cy - ry - 40), (cx + rx + 4, cy - 34)], fill=rgba((40, 40, 46)))
		d.line([(cx + rx - 10, cy - ry - 20), (cx + rx + 40, cy + 30)], fill=rgba((40, 40, 46)), width=8)
	elif headwear in ("headband", "headband_blue"):
		band = ga_vermilion() if headwear == "headband" else (60, 80, 130)
		d.line([(cx - rx - 2, cy - 40), (cx + rx + 2, cy - 40)], fill=rgba(band), width=14)
		d.line([(cx + rx, cy - 40), (cx + rx + 50, cy - 10)], fill=rgba(band), width=8)
		d.line([(cx + rx, cy - 36), (cx + rx + 40, cy + 20)], fill=rgba(band), width=8)

	# ── 얼굴 ──
	face = spec.get("face", "neutral")
	eye_y = cy - 2
	brow_y = cy - 24
	for side in (-1, 1):
		ex = cx + side * 28
		# 눈썹
		if face in ("stern", "proud"):
			b0, b1 = (ex - side * 2 - 18 * side * -1, brow_y - 4), (ex + side * 20, brow_y - 10)
			b0 = (ex - side * 16, brow_y + 2)
		elif face == "sly":
			b0, b1 = (ex - side * 16, brow_y - 2), (ex + side * 20, brow_y - 12)
		else:
			b0, b1 = (ex - side * 16, brow_y - 4), (ex + side * 18, brow_y - 6)
		bw = 7 if not female else 4
		d.line([b0, b1], fill=rgba(INK if age < 60 else (160, 158, 150)), width=bw)
		# 눈
		if spec.get("eyes_red"):
			d.line([(ex - 13, eye_y), (ex + 13, eye_y - side * 0)], fill=rgba(ga_vermilion()), width=5)
		elif face in ("stern", "sly"):
			d.line([(ex - 13, eye_y + (side * 2)), (ex + 13, eye_y - (side * 2))], fill=rgba(INK), width=4)
		else:
			d.arc((ex - 13, eye_y - 8, ex + 13, eye_y + 8), 200, 340, fill=rgba(INK), width=4)
		d.ellipse((ex - 4, eye_y - 3, ex + 4, eye_y + 5), fill=rgba(INK))
		if female:
			d.line([(ex + side * 12, eye_y - 2), (ex + side * 18, eye_y - 7)], fill=rgba(INK), width=3)
			d.ellipse((ex - 18 + side * 4, eye_y + 24, ex + 6 + side * 4, eye_y + 38), fill=rgba(ga_vermilion(), 50))
	# 코와 입
	d.line([(cx + 2, cy + 6), (cx - 4, cy + 30), (cx + 6, cy + 32)], fill=rgba(mix(INK, SKIN, 0.4)), width=3)
	mouth_y = cy + 50
	if face in ("gentle",):
		d.arc((cx - 16, mouth_y - 10, cx + 16, mouth_y + 6), 20, 160, fill=rgba((150, 70, 60)), width=3)
	elif face == "sly":
		d.line([(cx - 14, mouth_y), (cx + 14, mouth_y - 5)], fill=rgba((120, 60, 50)), width=3)
	else:
		d.line([(cx - 14, mouth_y), (cx + 14, mouth_y)], fill=rgba((120, 60, 50)), width=3)
	if female:
		d.ellipse((cx - 8, mouth_y - 4, cx + 8, mouth_y + 4), fill=rgba((176, 70, 64), 160))
	# 주름
	if age >= 45:
		for side in (-1, 1):
			d.line([(cx + side * 22, cy + 34), (cx + side * 32, cy + 56)], fill=rgba(mix(INK, SKIN, 0.55)), width=2)
		d.line([(cx - 20, brow_y - 22), (cx + 20, brow_y - 22)], fill=rgba(mix(INK, SKIN, 0.6)), width=2)
	if spec.get("scar"):
		d.line([(cx + 22, cy - 30), (cx + 48, cy + 20)], fill=rgba((150, 60, 50)), width=4)

	# 수염
	beard = spec.get("beard")
	beard_col = hair_col if age < 60 else (215, 213, 208)
	if beard == "stubble":
		for _ in range(160):
			a = rng.uniform(0.15, math.pi - 0.15)
			r = rng.uniform(0.7, 0.98)
			x, y = cx + rx2 * r * math.cos(a), cy + 20 + (ry2 - 20) * r * math.sin(a)
			d.point((x, y), fill=rgba(mix(INK, SKIN, 0.5)))
	elif beard in ("short", "full", "long"):
		length = {"short": 40, "full": 70, "long": 150}[beard]
		width = {"short": 34, "full": 60, "long": 40}[beard]
		pts = [(cx - width, mouth_y + 8), (cx - width * 0.6, mouth_y + length * 0.7), (cx, mouth_y + length),
			(cx + width * 0.6, mouth_y + length * 0.7), (cx + width, mouth_y + 8)]
		if beard == "full":
			pts = [(cx - rx2 + 4, cy + 10)] + pts + [(cx + rx2 - 4, cy + 10)]
		d.polygon(pts, fill=rgba(beard_col))
		for k in range(8):
			x = cx - width * 0.6 + k * width * 1.2 / 7
			d.line([(x, mouth_y + 12), (x + rng.uniform(-6, 6), mouth_y + length * 0.85)], fill=rgba(mix(beard_col, INK, 0.25)), width=2)
		# 콧수염
		d.line([(cx - 4, mouth_y - 8), (cx - 34, mouth_y + 6)], fill=rgba(beard_col), width=7)
		d.line([(cx + 4, mouth_y - 8), (cx + 34, mouth_y + 6)], fill=rgba(beard_col), width=7)
	if headwear == "hood_mask":
		d.rectangle((cx - rx2 - 2, cy + 18, cx + rx2 + 2, cy + ry2 + 14), fill=rgba(TINTS[spec.get("hood_color", "black")]))
		brush_poly(d, [(cx - rx2, cy + 18), (cx + rx2, cy + 18)], 4, rgba(INK, 220), rng, closed=False)

	# 앞쪽 소품: 부채, 단검
	if weapon == "fan":
		fx, fy = 150, 560
		for k in range(9):
			a = math.pi * (1.1 + k * 0.09)
			d.line([(fx, fy), (fx + 110 * math.cos(a) + 60, fy + 110 * math.sin(a))], fill=rgba((90, 70, 50)), width=3)
		d.pieslice((fx - 50, fy - 110, fx + 170, fy + 110), 195, 290, fill=rgba((236, 230, 210), 230), outline=rgba(INK), width=3)
	elif weapon == "dagger":
		d.line([(120, 640), (180, 520)], fill=rgba((110, 108, 104)), width=10)
		d.line([(160, 548), (196, 566)], fill=rgba(INK), width=8)

	base.alpha_composite(layer)
	# 이름: 세로 붓글씨 + 낙관
	ga.brush_text(base, name, 58, (52, 40), color=ga.INK, alpha=210, vertical=True)
	stamp = ga.seal(name[:1], 54, rng)
	base.paste(stamp, (25, 44 + len(name) * 54), stamp)
	return base.convert("RGB").resize((256, 320), Image.LANCZOS)


def ga_vermilion():
	return tuple(int(c * 255) for c in ga.VERMILION)


def emblem(text: str, shape: str, tint: str, seed: int) -> Image.Image:
	"""세력 문장: 색 테두리 안에 붓글씨 두 글자"""
	rng = np.random.default_rng(seed)
	s = 512
	im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
	d = ImageDraw.Draw(im)
	col = TINTS[tint]
	paper = (238, 230, 210, 255)

	def outline(r, fill, width=0, outline_col=None):
		box = (s / 2 - r, s / 2 - r, s / 2 + r, s / 2 + r)
		if shape.startswith("circle"):
			d.ellipse(box, fill=fill, outline=outline_col, width=width)
		elif shape == "square":
			d.rounded_rectangle(box, radius=r * 0.12, fill=fill, outline=outline_col, width=width)
		else:
			pts = [(s / 2 + r * math.cos(math.pi / 8 + k * math.pi / 4), s / 2 + r * math.sin(math.pi / 8 + k * math.pi / 4)) for k in range(8)]
			d.polygon(pts, fill=fill, outline=outline_col, width=width)

	outline(240, rgba(col))
	outline(200, paper)
	if shape == "circle_double":
		outline(180, None, 10, rgba(col))
	font = ga.brush_font(150)
	text_col = rgba(mix(col, INK, 0.35))
	for i, ch in enumerate(text[:2]):
		d.text((s / 2, s / 2 + (i - 0.5) * 130), ch, font=font, fill=text_col, anchor="mm")
	arr = np.asarray(im).astype(np.float32)
	noise = ga.fractal_noise(rng, s, s, 16, 3)
	arr[..., :3] *= (0.9 + 0.15 * noise)[..., None]
	out = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
	return out.resize((256, 256), Image.LANCZOS)


def main() -> None:
	import json
	os.makedirs(os.path.join(OUT, "portraits"), exist_ok=True)
	os.makedirs(os.path.join(OUT, "emblems"), exist_ok=True)
	for i, (npc_id, spec) in enumerate(NPCS.items()):
		with open(os.path.join(ga.ROOT, "data", "npcs", npc_id + ".json"), encoding="utf-8") as f:
			name = json.load(f)["display_name"]
		# 이름이 긴 졸개는 짧게 쓴다
		short = name.split(" ")[-1] if len(name) > 4 else name
		img = portrait(short, spec, 4000 + i)
		img.save(os.path.join(OUT, "portraits", npc_id + ".jpg"), quality=88, optimize=True)
		print("  ", npc_id, name)
	for i, (role, (name, spec)) in enumerate(ROLES.items()):
		img = portrait(name, spec, 5000 + i)
		img.save(os.path.join(OUT, "portraits", "role_%s.jpg" % role.lower()), quality=88, optimize=True)
		print("  ", role)
	for i, (sect_id, (text, shape, tint)) in enumerate(SECT_EMBLEMS.items()):
		emblem(text, shape, tint, 6000 + i).save(os.path.join(OUT, "emblems", sect_id + ".png"), optimize=True)
		print("  ", sect_id)


if __name__ == "__main__":
	main()
