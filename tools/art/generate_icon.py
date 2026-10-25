#!/usr/bin/env python3
"""앱 아이콘 생성기: 한지 바탕에 붉은 해, 먹으로 그린 산, 그 앞에 선 검, 붉은 낙관.

실행: python3 tools/art/generate_icon.py   (Pillow·numpy 필요)
만드는 파일 (assets/icon/):
  icon_1024.png            가게·웹용 큰 아이콘 (둥근 모서리 없음)
  icon.png                 프로젝트 아이콘 256px (project.godot config/icon)
  android_192.png          안드로이드 기본 아이콘
  android_fg_432.png       안드로이드 적응형 아이콘 앞면 (검·낙관, 투명 바탕, 가운데 안전 구역 안)
  android_bg_432.png       안드로이드 적응형 아이콘 뒷면 (한지·해·산)
  android_mono_432.png     안드로이드 단색 아이콘 (검 실루엣)
  web_144·180·512.png      웹(설치형 웹 앱) 아이콘
  icon.ico                 윈도우 실행 파일 아이콘 (16~256px)
같은 시드로 늘 같은 그림을 만든다.
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "icon")
FONT = os.path.join(ROOT, "assets", "fonts", "NanumBrushScript-Regular.ttf")
S = 1024
RNG = np.random.default_rng(20261025)

PAPER = (239, 230, 210)
INK = (24, 22, 20)
RED = (178, 48, 36)
GOLD = (176, 128, 44)


def paper(size: int) -> Image.Image:
	"""한지: 고른 바탕에 섬유 결 잡음과 가장자리 그늘"""
	base = np.ones((size, size, 3)) * np.array(PAPER, dtype=float)
	noise = RNG.normal(0, 1, (size // 4, size // 4))
	noise = np.array(Image.fromarray(((noise - noise.min()) / np.ptp(noise) * 255).astype(np.uint8)).resize((size, size), Image.BICUBIC)) / 255.0
	fibers = RNG.normal(0, 1, (size, size))
	fibers = np.array(Image.fromarray(((fibers - fibers.min()) / np.ptp(fibers) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))) / 255.0
	shade = (noise - 0.5) * 18 + (fibers - 0.5) * 10
	y, x = np.mgrid[0:size, 0:size] / size - 0.5
	vignette = (x * x + y * y) * 70
	base = base + shade[..., None] - vignette[..., None]
	return Image.fromarray(np.clip(base, 0, 255).astype(np.uint8))


def sun(img: Image.Image, cx: float, cy: float, r: float) -> None:
	"""붉은 해: 가장자리가 살짝 번진 원"""
	size = img.size[0]
	layer = Image.new("L", img.size, 0)
	d = ImageDraw.Draw(layer)
	d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
	layer = layer.filter(ImageFilter.GaussianBlur(size * 0.004))
	grain = Image.fromarray((RNG.uniform(0.82, 1.0, (size, size)) * 255).astype(np.uint8))
	alpha = ImageChops.multiply(layer, grain)
	img.paste(Image.new("RGB", img.size, RED), (0, 0), alpha)


def ridge(width: int, base: float, height: float, rough: float, peaks: list) -> np.ndarray:
	"""산등성이 높이: 몇 개의 봉우리 + 잔 굴곡"""
	x = np.linspace(0, 1, width)
	y = np.full(width, base)
	for px, ph, pw in peaks:
		y -= ph * np.exp(-((x - px) / pw) ** 2)
	walk = np.cumsum(RNG.normal(0, 1, width))
	walk = (walk - np.linspace(walk[0], walk[-1], width))
	y += walk / max(1e-6, np.abs(walk).max()) * rough
	return y * height


def mountains(img: Image.Image, layers: list) -> None:
	"""겹산: 뒤는 옅게, 앞은 진하게. 아래로 갈수록 안개에 잠긴다"""
	size = img.size[0]
	for base, peaks, tone, mist in layers:
		line = ridge(size, base, size, 0.018, peaks)
		mask = np.zeros((size, size))
		rows = np.arange(size)[:, None]
		inside = rows >= line[None, :]
		# 산 몸통은 위가 진하고 아래로 갈수록 안개에 옅어진다
		depth = np.clip((rows - line[None, :]) / (size * mist), 0, 1)
		mask[inside] = (1.0 - depth[inside] * 0.85)
		# 능선의 붓 자국: 위쪽 가장자리를 짙게
		edge = np.exp(-np.clip(rows - line[None, :], 0, None) / (size * 0.012)) * inside
		alpha = np.clip(mask * tone + edge * 0.25, 0, 1)
		alpha_img = Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(size * 0.0015))
		img.paste(Image.new("RGB", img.size, INK), (0, 0), alpha_img)


def sword(size: int, scale: float = 1.0, mono: bool = False) -> Image.Image:
	"""비스듬히 선 곧은 검(劍): 강철 날의 밝고 어두운 두 면, 먹 테두리, 금빛 코등이, 붉은 수술 (투명 바탕)"""
	big = size * 2  # 두 배로 그려 줄여서 가장자리를 부드럽게
	layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
	d = ImageDraw.Draw(layer)
	c = big / 2
	angle = np.radians(-30)
	ax, ay = np.sin(angle), -np.cos(angle)   # 칼끝 방향 (위)
	nx, ny = -ay, ax                          # 날의 폭 방향
	length = big * 0.9 * scale
	center = (c + ax * length * 0.02 + big * 0.04, c + ay * length * 0.02 - big * 0.01)
	tip = (center[0] + ax * length * 0.5, center[1] + ay * length * 0.5)
	guard_at = (center[0] - ax * length * 0.2, center[1] - ay * length * 0.2)
	pommel = (center[0] - ax * length * 0.46, center[1] - ay * length * 0.46)
	w = big * 0.021 * scale

	def pt(p, along, across):
		return (p[0] + ax * along + nx * across, p[1] + ay * along + ny * across)

	ink = (22, 20, 18, 255)
	outline = int(w * 0.22)
	# 날: 먹 테두리 → 두 면 (한쪽은 빛, 한쪽은 그늘)
	edge = [pt(guard_at, 0, -w - outline), pt(tip, -w * 2.6, -w * 0.75 - outline), pt(tip, w * 0.4, 0), pt(tip, -w * 2.6, w * 0.75 + outline), pt(guard_at, 0, w + outline)]
	d.polygon(edge, fill=ink)
	if not mono:
		d.polygon([pt(guard_at, 0, -w), pt(tip, -w * 2.6, -w * 0.75), tip, pt(guard_at, 0, 0)], fill=(214, 212, 204, 255))
		d.polygon([pt(guard_at, 0, 0), tip, pt(tip, -w * 2.6, w * 0.75), pt(guard_at, 0, w)], fill=(118, 120, 122, 255))
		# 등줄
		d.line([pt(guard_at, 0, 0), tip], fill=(60, 60, 62, 255), width=max(1, int(w * 0.16)))
		# 날의 피 홈 근처 빛 한 줄
		d.line([pt(guard_at, w * 4, -w * 0.45), pt(tip, -w * 8, -w * 0.4)], fill=(250, 248, 240, 255), width=max(1, int(w * 0.14)))
	# 코등이: 양쪽이 살짝 휜 구름 모양
	gw = w * 3.1
	guard = [pt(guard_at, w * 0.9, -gw), pt(guard_at, w * 0.2, -gw * 1.12), pt(guard_at, -w * 0.9, -gw * 0.7),
		pt(guard_at, -w * 0.9, gw * 0.7), pt(guard_at, w * 0.2, gw * 1.12), pt(guard_at, w * 0.9, gw)]
	d.polygon(guard, fill=ink)
	if not mono:
		inner = [pt(guard_at, w * 0.6, -gw * 0.9), pt(guard_at, w * 0.05, -gw * 0.98), pt(guard_at, -w * 0.6, -gw * 0.62),
			pt(guard_at, -w * 0.6, gw * 0.62), pt(guard_at, w * 0.05, gw * 0.98), pt(guard_at, w * 0.6, gw * 0.9)]
		d.polygon(inner, fill=GOLD + (255,))
	# 손잡이: 먹색 바탕에 붉은 끈을 엇갈려 감음
	grip_from = pt(guard_at, -w * 0.9, 0)
	grip_to = pt(pommel, w * 1.0, 0)
	d.line([grip_from, grip_to], fill=ink, width=int(w * 1.7))
	if not mono:
		steps = 9
		for i in range(steps):
			t = (i + 0.5) / steps
			p = (grip_from[0] + (grip_to[0] - grip_from[0]) * t, grip_from[1] + (grip_to[1] - grip_from[1]) * t)
			d.line([pt(p, w * 0.3, -w * 0.8), pt(p, -w * 0.3, w * 0.8)], fill=(150, 36, 28, 255), width=max(1, int(w * 0.32)))
	# 칼자루 끝
	r = w * 1.15
	d.ellipse([pommel[0] - r, pommel[1] - r, pommel[0] + r, pommel[1] + r], fill=ink)
	if not mono:
		r2 = r * 0.7
		d.ellipse([pommel[0] - r2, pommel[1] - r2, pommel[0] + r2, pommel[1] + r2], fill=GOLD + (255,))
		# 붉은 수술: 고리에서 흘러내려 바람에 날리는 실
		knot = (pommel[0], pommel[1] + r * 1.1)
		d.ellipse([knot[0] - r * 0.55, knot[1] - r * 0.55, knot[0] + r * 0.55, knot[1] + r * 0.55], fill=(160, 34, 26, 255))
		for i in range(26):
			spread = (i - 13) / 13
			points = []
			for k in range(12):
				t = k / 11
				x = knot[0] + spread * w * 1.2 * t + np.sin(t * 2.4 + i * 0.3) * w * 1.1 * t + t * w * 2.2
				y = knot[1] + t * length * 0.11 * (0.85 + 0.15 * abs(spread))
				points.append((x, y))
			shade = 150 + int(30 * RNG.uniform())
			d.line(points, fill=(shade, 32, 24, 240), width=max(1, int(w * 0.22)))
	return layer.resize((size, size), Image.LANCZOS)


def seal(size: int, text: str = "강호\n제패") -> Image.Image:
	"""붉은 낙관: 거친 테두리의 네모 안에 흰 붓글씨"""
	layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
	d = ImageDraw.Draw(layer)
	d.rounded_rectangle([0, 0, size - 1, size - 1], radius=size * 0.08, fill=RED + (255,))
	font = ImageFont.truetype(FONT, int(size * 0.42))
	lines = text.split("\n")
	for i, line in enumerate(lines):
		box = d.textbbox((0, 0), line, font=font)
		tw, th = box[2] - box[0], box[3] - box[1]
		y = size * (0.27 + i * 0.44) - th / 2 - box[1]
		d.text(((size - tw) / 2 - box[0], y), line, font=font, fill=(250, 240, 225, 255))
	# 찍힌 자국처럼 군데군데 비게
	grain = (RNG.uniform(0, 1, (size, size)) > 0.07).astype(np.uint8) * 255
	alpha = ImageChops.multiply(layer.getchannel("A"), Image.fromarray(grain).filter(ImageFilter.GaussianBlur(0.6)))
	layer.putalpha(alpha)
	return layer


def background(size: int) -> Image.Image:
	img = paper(size)
	sun(img, size * 0.62, size * 0.38, size * 0.25)
	mountains(img, [
		(0.70, [(0.18, 0.20, 0.10), (0.42, 0.12, 0.08), (0.80, 0.24, 0.11)], 0.32, 0.25),
		(0.84, [(0.05, 0.18, 0.12), (0.30, 0.10, 0.09), (0.62, 0.20, 0.10), (0.98, 0.14, 0.08)], 0.62, 0.18),
		(0.97, [(0.20, 0.10, 0.12), (0.55, 0.06, 0.10), (0.85, 0.10, 0.09)], 0.92, 0.12),
	])
	return img


def compose(size: int) -> Image.Image:
	img = background(size).convert("RGBA")
	blade = sword(size)
	shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
	shadow.putalpha(blade.getchannel("A").filter(ImageFilter.GaussianBlur(size * 0.01)).point(lambda v: v * 0.35))
	img.alpha_composite(shadow, (int(size * 0.012), int(size * 0.012)))
	img.alpha_composite(blade)
	mark = seal(int(size * 0.2))
	img.alpha_composite(mark, (int(size * 0.07), int(size * 0.73)))
	return img


def foreground(size: int) -> Image.Image:
	"""적응형 아이콘 앞면: 가운데 66% 안전 구역 안에 검과 낙관"""
	layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
	inner = int(size * 0.68)
	blade = sword(inner)
	layer.alpha_composite(blade, ((size - inner) // 2, (size - inner) // 2))
	mark = seal(int(size * 0.14))
	layer.alpha_composite(mark, (int(size * 0.24), int(size * 0.6)))
	return layer


def monochrome(size: int) -> Image.Image:
	layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
	inner = int(size * 0.68)
	blade = sword(inner, scale=1.15, mono=True)
	white = Image.new("RGBA", blade.size, (255, 255, 255, 255))
	white.putalpha(blade.getchannel("A"))
	layer.alpha_composite(white, ((size - inner) // 2, (size - inner) // 2))
	return layer


def main() -> None:
	os.makedirs(OUT, exist_ok=True)
	big = compose(S)
	big.convert("RGB").save(os.path.join(OUT, "icon_1024.png"))
	big.resize((256, 256), Image.LANCZOS).save(os.path.join(OUT, "icon.png"))
	big.resize((192, 192), Image.LANCZOS).save(os.path.join(OUT, "android_192.png"))
	for px in [144, 180, 512]:
		big.resize((px, px), Image.LANCZOS).convert("RGB").save(os.path.join(OUT, "web_%d.png" % px))
	foreground(S).resize((432, 432), Image.LANCZOS).save(os.path.join(OUT, "android_fg_432.png"))
	background(S).resize((432, 432), Image.LANCZOS).save(os.path.join(OUT, "android_bg_432.png"))
	monochrome(S).resize((432, 432), Image.LANCZOS).save(os.path.join(OUT, "android_mono_432.png"))
	big.convert("RGBA").save(os.path.join(OUT, "icon.ico"), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
	print("아이콘:", sorted(os.listdir(OUT)))


if __name__ == "__main__":
	main()
