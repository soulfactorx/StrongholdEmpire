#!/usr/bin/env python3
"""수묵담채 그림 생성기.

주의: 지금 assets/art/에는 프로젝트 소유자가 넣은 그림 세트가 있다. 이 스크립트는 그 그림을 덮어쓴다.

AI 이미지 생성기를 쓸 수 없는 환경에서 쓰는 절차적 그림이다. 같은 시드로 늘 같은 그림을 만든다.
나중에 AI로 만든 그림으로 바꾸려면 같은 파일 이름·크기로 assets/art/ 아래 파일을 덮어쓰면 된다.

배경은 render_shanshui.js로 찍은 shan-shui-inf(MIT) 산수화 밑그림에 색과 낙관을 더해 만든다.

실행: python3 tools/art/generate_art.py [산수화 밑그림 폴더]   (PIL, numpy 필요)
"""

from __future__ import annotations

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "art")
BRUSH_FONT = os.path.join(ROOT, "assets", "fonts", "NanumBrushScript-Regular.ttf")

# 아트 방향 문서의 색 (0~1)
PAPER = np.array([0xEF, 0xE6, 0xD2]) / 255.0
INK = np.array([0x1E, 0x1E, 0x1E]) / 255.0
LIGHT_INK = np.array([0x7A, 0x74, 0x6A]) / 255.0
VERMILION = np.array([0xB2, 0x3A, 0x2B]) / 255.0
JADE = np.array([0x2F, 0x6B, 0x5E]) / 255.0
GOLD = np.array([0xC9, 0xA5, 0x4B]) / 255.0
INDIGO = np.array([0x3E, 0x55, 0x6E]) / 255.0
OCHRE = np.array([0xA8, 0x7E, 0x4A]) / 255.0


# ─── 기본 도구 ─────────────────────────────────────

def smooth_noise(rng: np.random.Generator, w: int, h: int, cells: int) -> np.ndarray:
	"""낮은 해상도 난수를 부드럽게 키운 값 노이즈 (0~1)"""
	cw = max(2, cells)
	ch = max(2, int(cells * h / w))
	small = rng.random((ch, cw)).astype(np.float32)
	img = Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
	return np.asarray(img, dtype=np.float32) / 255.0


def fractal_noise(rng: np.random.Generator, w: int, h: int, base: int = 4, octaves: int = 5) -> np.ndarray:
	total = np.zeros((h, w), np.float32)
	amp, norm = 1.0, 0.0
	for i in range(octaves):
		total += smooth_noise(rng, w, h, base * 2 ** i) * amp
		norm += amp
		amp *= 0.5
	return total / norm


def paper(rng: np.random.Generator, w: int, h: int, tone: np.ndarray = PAPER, grain: float = 1.0) -> np.ndarray:
	"""한지 바탕: 얼룩·섬유·가장자리 그늘"""
	img = np.ones((h, w, 3), np.float32) * tone
	blot = fractal_noise(rng, w, h, 3, 5) - 0.5
	img += blot[..., None] * 0.07 * grain
	fiber = rng.random((h, w)).astype(np.float32) - 0.5
	img += fiber[..., None] * 0.035 * grain
	# 가로로 긴 섬유 결
	streak = np.asarray(
		Image.fromarray(((rng.random((h // 2, w // 16)) * 255).astype(np.uint8))).resize((w, h), Image.BILINEAR),
		np.float32,
	) / 255.0 - 0.5
	img += streak[..., None] * 0.02 * grain
	yy, xx = np.mgrid[0:h, 0:w]
	d = np.sqrt(((xx - w / 2) / (w / 2)) ** 2 + ((yy - h / 2) / (h / 2)) ** 2)
	img *= (1.0 - np.clip(d - 0.7, 0, 1) * 0.18 * grain)[..., None]
	return img


def blend(img: np.ndarray, color: np.ndarray, alpha: np.ndarray) -> None:
	a = np.clip(alpha, 0, 1)[..., None]
	img[:] = img * (1 - a) + color * a


def ridge(rng: np.random.Generator, w: int, base: float, height: float, rough: float, peaks: int) -> np.ndarray:
	"""산 능선 높이(위쪽 y 좌표). 뾰족한 봉우리 몇 개에 중점 변위 잡음을 얹는다."""
	x = np.arange(w, dtype=np.float32)
	y = np.zeros(w, np.float32)
	for _ in range(peaks):
		cx = rng.uniform(-0.1, 1.1) * w
		width = rng.uniform(0.08, 0.25) * w
		hgt = rng.uniform(0.4, 1.0) * height
		y += hgt * np.exp(-np.abs(x - cx) / width) ** 1.3
	# 중점 변위 잡음
	n = 2 ** int(math.ceil(math.log2(w)))
	pts = np.zeros(n + 1, np.float32)
	step, scale = n, rough
	while step > 1:
		half = step // 2
		for i in range(half, n, step):
			pts[i] = (pts[i - half] + pts[i + half]) / 2 + rng.uniform(-1, 1) * scale
		step, scale = half, scale * 0.55
	y += pts[:w]
	return base - y


def mountain_layer(img: np.ndarray, rng: np.random.Generator, top: np.ndarray, color: np.ndarray,
		strength: float, fade: float) -> None:
	"""능선 아래를 먹으로 칠한다. 능선 가까이는 진하고 아래로 갈수록 안개에 묻힌다."""
	h, w, _ = img.shape
	yy = np.arange(h, dtype=np.float32)[:, None]
	depth = yy - top[None, :]
	inside = depth >= 0
	alpha = np.where(inside, np.exp(-np.maximum(depth, 0) / fade), 0.0)
	# 붓 결: 세로로 늘어진 준법(皴法) 잡음
	tex = fractal_noise(rng, w, h, 8, 4)
	vstreak = np.asarray(
		Image.fromarray((rng.random((h // 24 + 1, w // 3)) * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC),
		np.float32,
	) / 255.0
	alpha = alpha * (0.55 + 0.6 * tex) * (0.75 + 0.4 * vstreak)
	# 능선 윤곽선을 진하게
	edge = np.where(inside, np.exp(-np.maximum(depth, 0) / 3.0), 0.0)
	alpha = np.maximum(alpha, edge * 0.9)
	blend(img, color, alpha * strength)


def mist(img: np.ndarray, rng: np.random.Generator, y_center: float, thickness: float, strength: float) -> None:
	h, w, _ = img.shape
	yy = np.arange(h, dtype=np.float32)[:, None]
	band = np.exp(-((yy - y_center) / thickness) ** 2)
	n = fractal_noise(rng, w, h, 3, 4)
	blend(img, PAPER * 1.02, band * (0.5 + 0.7 * n) * strength)


def disc(img: np.ndarray, cx: float, cy: float, r: float, color: np.ndarray, strength: float, soft: float = 2.0) -> None:
	h, w, _ = img.shape
	yy, xx = np.mgrid[0:h, 0:w]
	d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
	blend(img, color, np.clip((r - d) / soft, 0, 1) * strength)


def to_image(img: np.ndarray) -> Image.Image:
	return Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))


def brush_font(size: int) -> ImageFont.FreeTypeFont:
	return ImageFont.truetype(BRUSH_FONT, size)


def seal(text: str, size: int, rng: np.random.Generator) -> Image.Image:
	"""붉은 낙관: 주홍 바탕에 글자를 비워 찍는다. 가장자리는 닳은 듯 거칠게."""
	im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
	d = ImageDraw.Draw(im)
	col = tuple(int(c * 255) for c in VERMILION)
	d.rounded_rectangle((2, 2, size - 3, size - 3), radius=size // 10, fill=col + (235,))
	font = brush_font(int(size * 0.62 / max(1, len(text) // 2 + (len(text) % 2))))
	if len(text) <= 2:
		font = brush_font(int(size * (0.7 if len(text) == 1 else 0.48)))
		tw = d.textlength(text, font=font)
		d.text(((size - tw) / 2, size * (0.1 if len(text) == 1 else 0.24)), text, font=font, fill=(0, 0, 0, 0))
	else:
		# 네 글자는 2×2로
		half = size / 2
		font = brush_font(int(size * 0.42))
		for i, ch in enumerate(text[:4]):
			col_i, row_i = 1 - i // 2, i % 2
			tw = d.textlength(ch, font=font)
			d.text((col_i * half + (half - tw) / 2, row_i * half + size * 0.02), ch, font=font, fill=(0, 0, 0, 0))
	# 글자 자리를 투명하게 (text가 0 알파를 덮어쓰도록)
	arr = np.asarray(im).copy()
	worn = rng.random(arr.shape[:2]) < 0.06
	arr[..., 3] = np.where(worn, (arr[..., 3] * 0.4).astype(np.uint8), arr[..., 3])
	return Image.fromarray(arr)


def paste_seal(base: Image.Image, text: str, size: int, pos: tuple[int, int], rng: np.random.Generator) -> None:
	stamp = seal(text, size, rng)
	base.paste(stamp, pos, stamp)


def brush_text(base: Image.Image, text: str, size: int, pos: tuple[int, int], color=INK, alpha: int = 230,
		vertical: bool = False) -> None:
	layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
	d = ImageDraw.Draw(layer)
	font = brush_font(size)
	col = tuple(int(c * 255) for c in color) + (alpha,)
	if vertical:
		x, y = pos
		for ch in text:
			tw = d.textlength(ch, font=font)
			d.text((x - tw / 2, y), ch, font=font, fill=col)
			y += int(size * 0.92)
	else:
		d.text(pos, text, font=font, fill=col)
	base.paste(layer, (0, 0), layer)


# ─── 붓질 소품 ─────────────────────────────────────

def ink_stroke(draw: ImageDraw.ImageDraw, pts: list[tuple[float, float]], width: float, color, rng) -> None:
	"""굵기가 바뀌는 붓 선"""
	for i in range(len(pts) - 1):
		t = i / max(1, len(pts) - 2)
		wdt = max(1, width * (0.4 + 0.8 * math.sin(math.pi * t)) * rng.uniform(0.85, 1.1))
		draw.line([pts[i], pts[i + 1]], fill=color, width=int(wdt))


def pine(draw: ImageDraw.ImageDraw, x: float, y: float, height: float, rng, alpha: int = 220) -> None:
	"""소나무: 굽은 줄기와 층층이 뻗은 솔잎 덩이"""
	ink = (30, 30, 30, alpha)
	pts = []
	cx = x
	for i in range(12):
		t = i / 11
		cx += rng.uniform(-1, 1) * height * 0.03
		pts.append((cx, y - t * height))
	ink_stroke(draw, pts, height * 0.05, ink, rng)
	for i in range(5):
		t = 0.45 + i * 0.12
		px, py = pts[int(t * 11)]
		side = -1 if i % 2 else 1
		length = height * rng.uniform(0.25, 0.45) * (1.1 - t * 0.6)
		ex, ey = px + side * length, py - rng.uniform(0, height * 0.06)
		draw.line([(px, py), (ex, ey)], fill=ink, width=max(1, int(height * 0.015)))
		for _ in range(int(length / 3)):
			bx = rng.uniform(min(px, ex), max(px, ex))
			by = py + (ey - py) * (bx - px) / (ex - px + 1e-6) - rng.uniform(0, height * 0.06)
			rx, ry = height * 0.06, height * 0.022
			draw.ellipse((bx - rx, by - ry, bx + rx, by + ry), fill=(25, 35, 30, int(alpha * 0.55)))


def pavilion(draw: ImageDraw.ImageDraw, x: float, y: float, w: float, alpha: int = 230, levels: int = 2) -> None:
	"""정자·전각: 끝이 들린 지붕과 기둥"""
	ink = (28, 28, 28, alpha)
	h = w * 0.35
	base_y = y
	for lvl in range(levels):
		scale = 1.0 - lvl * 0.28
		ww = w * scale
		hh = h * scale
		# 기둥과 벽
		body_top = base_y - hh
		draw.rectangle((x - ww * 0.36, body_top, x + ww * 0.36, base_y), fill=(70, 55, 45, int(alpha * 0.6)))
		for k in range(5):
			px = x - ww * 0.32 + k * ww * 0.16
			draw.line([(px, body_top), (px, base_y)], fill=ink, width=max(1, int(w * 0.012)))
		# 지붕: 처마 끝이 들린 사다리꼴
		roof_h = hh * 0.55
		eave = ww * 0.62
		roof = [
			(x - eave, body_top - roof_h * 0.05),
			(x - eave * 0.9, body_top + roof_h * 0.05),
			(x + eave * 0.9, body_top + roof_h * 0.05),
			(x + eave, body_top - roof_h * 0.05),
			(x + ww * 0.3, body_top - roof_h * 0.9),
			(x - ww * 0.3, body_top - roof_h * 0.9),
		]
		draw.polygon(roof, fill=ink)
		base_y = body_top - roof_h * 0.85
	# 지붕 꼭대기 장식
	draw.line([(x, base_y), (x, base_y - h * 0.4)], fill=ink, width=max(1, int(w * 0.015)))


def bamboo(draw: ImageDraw.ImageDraw, x: float, y0: float, y1: float, width: float, rng, alpha: int = 220) -> None:
	ink = (30, 45, 35, alpha)
	y = y0
	while y > y1:
		seg = rng.uniform(70, 130)
		ny = max(y1, y - seg)
		draw.rectangle((x - width / 2, ny + 3, x + width / 2, y - 3), fill=ink)
		y = ny
	for _ in range(int((y0 - y1) / 90)):
		ly = rng.uniform(y1, y0 * 0.8)
		for _k in range(rng.integers(2, 5)):
			ang = rng.uniform(-0.6, 0.6) + (0 if rng.random() < 0.5 else math.pi)
			length = rng.uniform(40, 90)
			ex = x + math.cos(ang) * length
			ey = ly + abs(math.sin(ang)) * length * 0.6 + 10
			mx, my = (x + ex) / 2, (ly + ey) / 2 - 8
			draw.polygon([(x, ly), (mx, my - width * 0.5), (ex, ey), (mx, my + width * 0.4)], fill=ink)


def birds(draw: ImageDraw.ImageDraw, cx: float, cy: float, n: int, rng, alpha: int = 200) -> None:
	for _ in range(n):
		x = cx + rng.uniform(-120, 120)
		y = cy + rng.uniform(-50, 50)
		s = rng.uniform(6, 12)
		draw.line([(x - s, y - s * 0.4), (x, y), (x + s, y - s * 0.5)], fill=(30, 30, 30, alpha), width=2)


def overlay(img: np.ndarray, layer: Image.Image) -> np.ndarray:
	base = to_image(img).convert("RGBA")
	base.alpha_composite(layer)
	return np.asarray(base.convert("RGB"), np.float32) / 255.0


# ─── 배경 ──────────────────────────────────────────

def mountains_scene(rng, w, h, layers, ink_color=INK, mist_strength=0.9):
	img = paper(rng, w, h)
	for i, (base, height, rough, peaks, strength, fade) in enumerate(layers):
		top = ridge(rng, w, base * h, height * h, rough * h, peaks)
		mountain_layer(img, rng, top, ink_color, strength, fade * h)
		if i < len(layers) - 1:
			mist(img, rng, base * h + 0.05 * h, 0.06 * h, mist_strength)
	return img


def bg_main_menu(rng, w, h):
	img = paper(rng, w, h)
	disc(img, w * 0.72, h * 0.26, h * 0.11, VERMILION, 0.55, 4)
	for base, height, rough, peaks, strength, fade in [
		(0.62, 0.32, 0.05, 5, 0.22, 0.25), (0.74, 0.30, 0.05, 4, 0.38, 0.18),
		(0.86, 0.28, 0.06, 4, 0.6, 0.14), (1.02, 0.30, 0.05, 3, 0.85, 0.2),
	]:
		top = ridge(rng, w, base * h, height * h, rough * h, peaks)
		mountain_layer(img, rng, top, INK, strength, fade * h)
		mist(img, rng, base * h + 0.04 * h, 0.05 * h, 0.8)
	layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	d = ImageDraw.Draw(layer)
	pine(d, w * 0.1, h * 1.0, h * 0.55, rng, 235)
	birds(d, w * 0.6, h * 0.2, 5, rng)
	img = overlay(img, layer)
	out = to_image(img)
	paste_seal(out, "강호제패", int(h * 0.11), (int(w * 0.9), int(h * 0.84)), rng)
	return out


def bg_hub(rng, w, h):
	img = mountains_scene(rng, w, h, [
		(0.5, 0.28, 0.04, 5, 0.2, 0.3), (0.66, 0.25, 0.05, 4, 0.35, 0.2),
	])
	# 앞쪽 언덕과 전각
	top = ridge(rng, w, 0.9 * h, 0.18 * h, 0.03 * h, 2)
	mountain_layer(img, rng, top, INK, 0.55, 0.2 * h)
	layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	d = ImageDraw.Draw(layer)
	pavilion(d, w * 0.78, top[int(w * 0.78)] + 6, w * 0.16, 225, 2)
	pavilion(d, w * 0.62, top[int(w * 0.62)] + 10, w * 0.09, 200, 1)
	pine(d, w * 0.9, h * 1.0, h * 0.45, rng, 230)
	pine(d, w * 0.05, h * 1.02, h * 0.38, rng, 210)
	birds(d, w * 0.3, h * 0.18, 4, rng)
	img = overlay(img, layer)
	return to_image(img)


def bg_world(rng, w, h):
	"""강호 지도 느낌: 위에서 내려다본 산줄기와 강"""
	img = paper(rng, w, h, PAPER * np.array([1.0, 0.98, 0.94]))
	yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
	# 구불구불한 강
	river_y = h * 0.55 + np.sin(xx / w * 5.0) * h * 0.12 + np.sin(xx / w * 13.0 + 1) * h * 0.03
	dist = np.abs(yy - river_y)
	blend(img, INDIGO, np.clip(1 - dist / (h * 0.025), 0, 1) * 0.35)
	blend(img, INDIGO, np.clip(1 - dist / (h * 0.06), 0, 1) * 0.12)
	# 산 무리: 작은 봉우리를 흩뿌린다
	layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	d = ImageDraw.Draw(layer)
	for _ in range(70):
		cx, cy = rng.uniform(0, w), rng.uniform(0, h)
		if abs(cy - (h * 0.55 + math.sin(cx / w * 5.0) * h * 0.12)) < h * 0.09:
			continue
		s = rng.uniform(30, 80)
		for k in range(3):
			ox = (k - 1) * s * 0.6
			ph = s * (1.1 if k == 1 else 0.7)
			a = int(rng.uniform(90, 170))
			d.polygon([(cx + ox - s * 0.55, cy), (cx + ox, cy - ph), (cx + ox + s * 0.55, cy)], fill=(40, 45, 42, a // 3))
			d.line([(cx + ox - s * 0.55, cy), (cx + ox, cy - ph), (cx + ox + s * 0.55, cy)], fill=(30, 30, 30, a), width=3)
	img = overlay(img, layer)
	img = to_image(img)
	paste_seal(img, "강호", int(h * 0.08), (int(w * 0.05), int(h * 0.06)), rng)
	return img


def bg_war(rng, w, h):
	img = paper(rng, w, h, PAPER * 0.93)
	disc(img, w * 0.3, h * 0.3, h * 0.13, VERMILION, 0.7, 3)
	# 먹구름
	cloud = fractal_noise(rng, w, h, 3, 5)
	yy = np.arange(h, dtype=np.float32)[:, None] / h
	blend(img, INK, np.clip((cloud - 0.45) * 2.2, 0, 1) * np.clip(0.55 - yy, 0, 1) * 1.4)
	for base, height, rough, peaks, strength, fade in [
		(0.7, 0.3, 0.06, 5, 0.45, 0.2), (0.9, 0.3, 0.07, 4, 0.85, 0.3),
	]:
		top = ridge(rng, w, base * h, height * h, rough * h, peaks)
		mountain_layer(img, rng, top, INK, strength, fade * h)
	layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	d = ImageDraw.Draw(layer)
	# 깃발들
	for i in range(9):
		x = w * (0.45 + i * 0.06) + rng.uniform(-20, 20)
		y = h * (0.72 + rng.uniform(-0.03, 0.03))
		d.line([(x, y), (x, y - h * 0.18)], fill=(25, 25, 25, 230), width=4)
		col = (178, 58, 43, 220) if i % 2 == 0 else (30, 30, 30, 210)
		d.polygon([(x, y - h * 0.18), (x + h * 0.07, y - h * 0.16), (x, y - h * 0.13)], fill=col)
	img = overlay(img, layer)
	return to_image(img)


def bg_ending(rng, w, h):
	img = paper(rng, w, h)
	yy = np.arange(h, dtype=np.float32)[:, None] / h
	blend(img, GOLD, np.clip(0.6 - yy, 0, 1) * 0.35 * np.ones((1, w)))
	disc(img, w * 0.5, h * 0.52, h * 0.16, VERMILION, 0.5, 6)
	for base, height, rough, peaks, strength, fade in [
		(0.62, 0.22, 0.04, 6, 0.25, 0.3), (0.78, 0.22, 0.05, 5, 0.45, 0.2), (0.98, 0.25, 0.05, 4, 0.8, 0.25),
	]:
		top = ridge(rng, w, base * h, height * h, rough * h, peaks)
		mountain_layer(img, rng, top, INK, strength, fade * h)
		mist(img, rng, base * h + 0.04 * h, 0.05 * h, 0.85)
	layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	d = ImageDraw.Draw(layer)
	birds(d, w * 0.5, h * 0.3, 7, rng)
	img = overlay(img, layer)
	return to_image(img)


def bg_study(rng, w, h):
	"""무공 수련·연구: 대숲"""
	img = paper(rng, w, h)
	top = ridge(rng, w, 0.75 * h, 0.25 * h, 0.04 * h, 4)
	mountain_layer(img, rng, top, INK, 0.18, 0.3 * h)
	mist(img, rng, 0.8 * h, 0.1 * h, 0.8)
	far = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	d = ImageDraw.Draw(far)
	for _ in range(10):
		bamboo(d, rng.uniform(0, w), h * 1.05, rng.uniform(-50, h * 0.3), rng.uniform(10, 16), rng, 70)
	img = overlay(img, far.filter(ImageFilter.GaussianBlur(3)))
	near = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	d = ImageDraw.Draw(near)
	for x in (w * 0.04, w * 0.11, w * 0.9, w * 0.96):
		bamboo(d, x + rng.uniform(-20, 20), h * 1.05, -20, rng.uniform(20, 28), rng, 225)
	img = overlay(img, near)
	return to_image(img)


def bg_scroll(rng, w, h):
	"""도움말·새 게임: 펼친 두루마리 같은 밝은 한지와 옅은 산"""
	img = paper(rng, w, h, PAPER * 1.01)
	top = ridge(rng, w, 1.0 * h, 0.35 * h, 0.05 * h, 4)
	mountain_layer(img, rng, top, INK, 0.25, 0.25 * h)
	disc(img, w * 0.85, h * 0.2, h * 0.07, VERMILION, 0.35, 3)
	layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	d = ImageDraw.Draw(layer)
	pine(d, w * 0.95, h * 1.0, h * 0.4, rng, 200)
	img = overlay(img, layer)
	return to_image(img)


def bg_combat(rng, w, h):
	"""전투 바탕: 그리드 둘레를 옅은 산과 안개로"""
	img = paper(rng, w, h, PAPER * 0.97)
	for base, height, rough, peaks, strength, fade in [
		(0.35, 0.25, 0.04, 5, 0.18, 0.2), (0.9, 0.2, 0.05, 4, 0.3, 0.2),
	]:
		top = ridge(rng, w, base * h, height * h, rough * h, peaks)
		mountain_layer(img, rng, top, INK, strength, fade * h)
		mist(img, rng, base * h + 0.05 * h, 0.08 * h, 0.9)
	return to_image(img)


# ─── 산수화 밑그림 마무리 ──────────────────────────
# render_shanshui.js로 찍은 shan-shui-inf(MIT) 산수화에 담채 색과 낙관을 더한다.

def multiply(img: np.ndarray, color: np.ndarray, alpha) -> None:
	"""먹·물감을 겹쳐 칠하듯 곱하기로 섞는다"""
	a = np.clip(alpha, 0, 1)
	if np.ndim(a) == 2:
		a = a[..., None]
	img[:] = img * (1 - a * (1 - color))


def radial(w: int, h: int, cx: float, cy: float, r: float, soft: float) -> np.ndarray:
	yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
	d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
	return np.clip((r - d) / soft, 0, 1)


def vertical(h: int, w: int, start: float, end: float) -> np.ndarray:
	"""위(start)에서 아래(end)로 1→0이 되는 띠"""
	yy = np.arange(h, dtype=np.float32)[:, None] / h
	return np.clip((end - yy) / max(1e-6, end - start), 0, 1) * np.ones((1, w), np.float32)


def fin_main_menu(img, rng):
	h, w, _ = img.shape
	multiply(img, VERMILION, radial(w, h, w * 0.3, h * 0.2, h * 0.1, 3) * 0.75)
	multiply(img, GOLD, vertical(h, w, 0.0, 0.5) * 0.12)
	out = to_image(img)
	paste_seal(out, "강호제패", int(h * 0.11), (int(w * 0.9), int(h * 0.84)), rng)
	return out


def fin_hub(img, rng):
	h, w, _ = img.shape
	multiply(img, JADE * 1.6, (1 - vertical(h, w, 0.3, 0.9)) * 0.07)
	return to_image(img)


def fin_world(img, rng):
	h, w, _ = img.shape
	multiply(img, INDIGO * 1.5, (1 - vertical(h, w, 0.2, 0.8)) * 0.15)
	return to_image(img)


def fin_war(img, rng):
	h, w, _ = img.shape
	cloud = fractal_noise(rng, w, h, 3, 5)
	multiply(img, INK * 1.6, np.clip((cloud - 0.4) * 2.0, 0, 1) * vertical(h, w, 0.0, 0.45) * 0.75)
	multiply(img, VERMILION, radial(w, h, w * 0.78, h * 0.16, h * 0.09, 3) * 0.85)
	multiply(img, VERMILION * 1.5, 0.06)
	return to_image(img)


def fin_ending(img, rng):
	h, w, _ = img.shape
	multiply(img, GOLD, vertical(h, w, 0.0, 0.7) * 0.3)
	multiply(img, VERMILION, radial(w, h, w * 0.62, h * 0.28, h * 0.08, 6) * 0.6)
	layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	birds(ImageDraw.Draw(layer), w * 0.4, h * 0.2, 6, rng)
	return to_image(overlay(img, layer))


def fin_study(img, rng):
	h, w, _ = img.shape
	multiply(img, JADE * 1.7, 0.04 + (1 - vertical(h, w, 0.4, 1.0)) * 0.08)
	return to_image(img)


def fin_scroll(img, rng):
	return to_image(img)


def fin_combat(img, rng):
	"""그리드 밑에 깔리므로 옅게"""
	img[:] = img * 0.45 + PAPER * 0.55
	return to_image(img)


# 배경 이름 → (shan-shui-inf 시드, 가로 위치, 마무리)
SHANSHUI = {
	"main_menu": ("123", 0, fin_main_menu),
	"hub": ("1003", 0, fin_hub),
	"world": ("2024", 0, fin_world),
	"war": ("42", 0, fin_war),
	"ending": ("888", 0, fin_ending),
	"study": ("520", 0, fin_study),
	"scroll": ("1001", 0, fin_scroll),
	"combat": ("1592", 0, fin_combat),
}


BACKGROUNDS = {
	"main_menu": bg_main_menu,
	"hub": bg_hub,
	"world": bg_world,
	"war": bg_war,
	"ending": bg_ending,
	"study": bg_study,
	"scroll": bg_scroll,
	"combat": bg_combat,
}


# ─── 지형 타일 (96px) ─────────────────────────────

TILE = 96


def tile_base(rng, tone=PAPER):
	return paper(rng, TILE, TILE, tone, 0.8)


def tile_plain(rng):
	img = tile_base(rng, PAPER * np.array([0.97, 0.97, 0.92]))
	layer = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
	d = ImageDraw.Draw(layer)
	for _ in range(7):
		x, y = rng.uniform(8, 88), rng.uniform(10, 90)
		for k in range(3):
			d.line([(x + k * 3, y), (x + k * 3 + rng.uniform(-3, 3), y - rng.uniform(5, 10))], fill=(60, 70, 50, 120), width=1)
	return to_image(overlay(img, layer))


def tile_forest(rng):
	img = tile_base(rng, PAPER * np.array([0.9, 0.95, 0.88]))
	blend(img, JADE, fractal_noise(rng, TILE, TILE, 3, 3) * 0.22)
	layer = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
	d = ImageDraw.Draw(layer)
	for cx, cy, s in [(28, 44, 26), (66, 38, 30), (46, 74, 24), (80, 76, 18)]:
		cx += rng.uniform(-4, 4)
		d.line([(cx, cy), (cx, cy + s * 0.8)], fill=(35, 30, 25, 230), width=3)
		for k in range(3):
			yy = cy - k * s * 0.32
			ww = s * (0.7 - k * 0.17)
			d.polygon([(cx - ww, yy + s * 0.25), (cx, yy - s * 0.3), (cx + ww, yy + s * 0.25)], fill=(30, 60, 48, 200))
	return to_image(overlay(img, layer))


def tile_water(rng):
	img = tile_base(rng, PAPER * np.array([0.86, 0.9, 0.95]))
	blend(img, INDIGO, 0.25 + fractal_noise(rng, TILE, TILE, 3, 3) * 0.15)
	layer = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
	d = ImageDraw.Draw(layer)
	for row in range(5):
		y0 = 12 + row * 18 + rng.uniform(-2, 2)
		pts = [(x, y0 + math.sin(x / 9.0 + row) * 3) for x in range(0, TILE + 1, 4)]
		d.line(pts, fill=(40, 60, 80, 170), width=2)
	return to_image(overlay(img, layer))


def tile_high(rng):
	img = tile_base(rng, PAPER * np.array([0.98, 0.92, 0.82]))
	blend(img, OCHRE, 0.18 + fractal_noise(rng, TILE, TILE, 3, 3) * 0.15)
	layer = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
	d = ImageDraw.Draw(layer)
	# 바위 봉우리 두 개와 준법 선
	for cx, s in [(34, 40), (66, 30)]:
		pts = [(cx - s, 84), (cx - s * 0.3, 84 - s * 1.3), (cx + s * 0.2, 84 - s * 1.1), (cx + s, 84)]
		d.polygon(pts, fill=(120, 95, 60, 110))
		d.line(pts, fill=(40, 32, 25, 230), width=3)
		for k in range(4):
			x = cx - s * 0.5 + k * s * 0.3
			d.line([(x, 84 - s * 0.9 + k * 3), (x - 6, 80)], fill=(50, 40, 30, 140), width=2)
	return to_image(overlay(img, layer))


def tile_wall(rng):
	img = tile_base(rng, PAPER * 0.75)
	blend(img, INK, 0.55 + fractal_noise(rng, TILE, TILE, 4, 4) * 0.35)
	layer = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
	d = ImageDraw.Draw(layer)
	for k in range(4):
		y = 10 + k * 22
		d.line([(4, y), (92, y + rng.uniform(-3, 3))], fill=(200, 190, 170, 70), width=2)
		off = 0 if k % 2 else 24
		for x in range(off, TILE, 48):
			d.line([(x, y), (x, y + 22)], fill=(200, 190, 170, 60), width=2)
	return to_image(overlay(img, layer))


TILES = {
	"plain": tile_plain,
	"forest": tile_forest,
	"water": tile_water,
	"high": tile_high,
	"wall": tile_wall,
}


# ─── 장기말 토큰 (128px) ──────────────────────────

TOKEN = 128


def token(shape: str, ring: np.ndarray, rng) -> Image.Image:
	"""나무 장기말: 그림자, 나뭇결 몸통, 색 테두리. 가운데는 비워 두고 글자는 게임에서 쓴다."""
	s = TOKEN * 4  # 크게 그린 뒤 줄여 가장자리를 부드럽게
	im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
	d = ImageDraw.Draw(im)

	def poly(r, cx=s / 2, cy=s / 2):
		if shape == "circle":
			return None
		return [(cx + r * math.cos(math.pi / 8 + k * math.pi / 4), cy + r * math.sin(math.pi / 8 + k * math.pi / 4)) for k in range(8)]

	def fill(r, color, cx=s / 2, cy=s / 2):
		p = poly(r, cx, cy)
		if p is None:
			d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color)
		else:
			d.polygon(p, fill=color)

	r = s * 0.44
	fill(r, (0, 0, 0, 90), s / 2 + s * 0.02, s / 2 + s * 0.035)  # 그림자
	fill(r, (40, 32, 24, 255))  # 옆면
	ring_col = tuple(int(c * 255) for c in ring) + (255,)
	fill(r * 0.96, ring_col)
	fill(r * 0.8, (226, 205, 165, 255))
	im = im.resize((TOKEN, TOKEN), Image.LANCZOS)

	# 나뭇결과 볕
	arr = np.asarray(im).astype(np.float32) / 255.0
	grain = np.asarray(
		Image.fromarray((rng.random((TOKEN // 2, 8)) * 255).astype(np.uint8)).resize((TOKEN, TOKEN), Image.BICUBIC),
		np.float32,
	) / 255.0
	yy, xx = np.mgrid[0:TOKEN, 0:TOKEN]
	light = 1.0 + 0.12 * (1 - (xx + yy) / TOKEN)
	arr[..., :3] *= ((0.92 + 0.12 * grain) * light)[..., None]
	# 안쪽 테두리 먹선
	arr = np.clip(arr, 0, 1)
	out = Image.fromarray((arr * 255).astype(np.uint8))
	line = Image.new("RGBA", (s, s), (0, 0, 0, 0))
	ld = ImageDraw.Draw(line)
	p = poly(r * 0.8)
	if p is None:
		ld.ellipse((s / 2 - r * 0.8, s / 2 - r * 0.8, s / 2 + r * 0.8, s / 2 + r * 0.8), outline=(40, 30, 20, 160), width=10)
	else:
		ld.polygon(p, outline=(40, 30, 20, 160), width=10)
	out.alpha_composite(line.resize((TOKEN, TOKEN), Image.LANCZOS))
	return out


TOKENS = {
	"player": ("circle", GOLD),
	"ally": ("circle", JADE),
	"enemy": ("octagon", VERMILION),
}


def token_highlight() -> Image.Image:
	"""조종 중인 말 둘레의 금빛 붓 고리"""
	s = TOKEN * 4
	im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
	d = ImageDraw.Draw(im)
	col = tuple(int(c * 255) for c in GOLD)
	for k in range(6):
		w = 28 - k * 3
		inset = s * 0.03 + k * 6
		d.arc((inset, inset, s - inset, s - inset), start=-80 + k * 9, end=250 - k * 7, fill=col + (220,), width=w)
	return im.resize((TOKEN, TOKEN), Image.LANCZOS)


# ─── UI 텍스처 ────────────────────────────────────

def ui_panel(rng) -> Image.Image:
	"""9분할 패널: 한지 바탕에 먹 테두리 두 줄 (모서리 16px)"""
	size = 96
	img = paper(rng, size, size, PAPER * 1.01, 0.6)
	im = to_image(img).convert("RGBA")
	d = ImageDraw.Draw(im)
	d.rectangle((3, 3, size - 4, size - 4), outline=(30, 30, 30, 170), width=2)
	d.rectangle((8, 8, size - 9, size - 9), outline=(122, 116, 106, 90), width=1)
	arr = np.asarray(im).copy()
	arr[..., 3] = 245
	return Image.fromarray(arr)


def ui_button(rng, kind: str) -> Image.Image:
	w, h = 96, 48
	tone = {
		"normal": PAPER * 0.97,
		"hover": PAPER * np.array([1.0, 0.95, 0.82]),
		"pressed": VERMILION * 1.05,
		"disabled": PAPER * 0.82,
	}[kind]
	img = paper(rng, w, h, tone, 0.5)
	im = to_image(img).convert("RGBA")
	d = ImageDraw.Draw(im)
	edge = (30, 30, 30, 230) if kind != "disabled" else (122, 116, 106, 200)
	d.rounded_rectangle((1, 1, w - 2, h - 2), radius=6, outline=edge, width=2)
	if kind == "hover":
		d.rounded_rectangle((4, 4, w - 5, h - 5), radius=4, outline=tuple(int(c * 255) for c in GOLD) + (220,), width=2)
	# 모서리 밖은 투명
	mask = Image.new("L", (w, h), 0)
	ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), radius=7, fill=255)
	im.putalpha(mask)
	return im


def ui_header_brush(rng) -> Image.Image:
	"""제목 밑에 깔 붓 자국 띠"""
	w, h = 512, 64
	im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	arr = np.zeros((h, w, 4), np.float32)
	yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
	center = h / 2 + np.sin(xx / w * 3.0) * 4
	thick = h * 0.32 * (0.6 + 0.4 * np.sin(np.pi * xx / w) ** 0.5)
	core = np.clip(1 - np.abs(yy - center) / thick, 0, 1)
	dry = fractal_noise(rng, w, h, 32, 3)
	streak = np.asarray(
		Image.fromarray((rng.random((h, w // 40)) * 255).astype(np.uint8)).resize((w, h), Image.BILINEAR), np.float32
	) / 255.0
	alpha = core * np.clip(dry * 1.6 + streak * 0.6 - 0.35, 0, 1)
	alpha *= np.clip(xx / (w * 0.08), 0, 1) * np.clip((w - xx) / (w * 0.25), 0, 1)
	arr[..., :3] = INK
	arr[..., 3] = alpha * 0.8
	return Image.fromarray((arr * 255).astype(np.uint8))


# ─── 실행 ─────────────────────────────────────────

def save(img: Image.Image, rel: str, quality: int = 85) -> None:
	path = os.path.join(OUT, rel)
	os.makedirs(os.path.dirname(path), exist_ok=True)
	if rel.endswith(".jpg"):
		img.convert("RGB").save(path, quality=quality, optimize=True)
	else:
		img.save(path, optimize=True)
	print("  ", rel, img.size)


def main() -> None:
	# 인자: [산수화 밑그림 폴더]. 밑그림이 없는 배경은 절차적 그림으로 대신한다.
	shanshui_dir = sys.argv[1] if len(sys.argv) > 1 else ""
	seed = 20261017
	for i, (name, fn) in enumerate(BACKGROUNDS.items()):
		rng = np.random.default_rng(seed + i)
		ss_seed, cursx, finish = SHANSHUI[name]
		base = os.path.join(shanshui_dir, f"shanshui_{ss_seed}_{cursx}.png")
		if shanshui_dir and os.path.exists(base):
			img = np.asarray(Image.open(base).convert("RGB").resize((1920, 1080), Image.LANCZOS), np.float32) / 255.0
			save(finish(img.copy(), rng), f"bg/{name}.jpg")
		else:
			save(fn(rng, 1920, 1080), f"bg/{name}.jpg")
	for i, (name, fn) in enumerate(TILES.items()):
		rng = np.random.default_rng(seed + 100 + i)
		save(fn(rng), f"tiles/{name}.png")
	for i, (name, (shape, ring)) in enumerate(TOKENS.items()):
		rng = np.random.default_rng(seed + 200 + i)
		save(token(shape, ring, rng), f"tokens/{name}.png")
	save(token_highlight(), "tokens/highlight.png")
	rng = np.random.default_rng(seed + 300)
	save(ui_panel(rng), "ui/panel.png")
	for kind in ("normal", "hover", "pressed", "disabled"):
		save(ui_button(rng, kind), f"ui/button_{kind}.png")
	save(ui_header_brush(rng), "ui/brush_stroke.png")
	save(seal("강호", 128, rng), "ui/seal.png")


if __name__ == "__main__":
	main()
