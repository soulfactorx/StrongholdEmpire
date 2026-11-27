#!/usr/bin/env python3
"""전투 효과음을 CC0 녹음 소리로 만든다 (칼 휘두름·칼 부딪힘·타격·쓰러짐·징).

OpenGameArt의 CC0 묶음을 받아 앞의 빈 소리를 잘라 내고, 겹치고, 크기를 맞춰 assets/audio/sfx/에 OGG로 쓴다.
음악적인 효과음(성공·실패·기연·운기·돌파·승리·패배·누름)은 generate_audio.py의 국악풍 합성음을 그대로 쓴다.
같은 소리를 여러 벌(hit.ogg, hit_2.ogg, …) 만들면 AudioManager가 번갈아 골라 낸다.

출처(모두 CC0, assets/CREDITS.md에 적음):
- StarNinjas, "20 Sword Sound Effects (Attacks and Clashes)", "10 Impact/Shield Blocks"
- artisticdude, "Swishes Sound Pack", "RPG Sound Pack"
- rubberduck, "100 CC0 SFX"
- Kenney, "50 RPG sound effects"

실행: python3 tools/audio/build_cc0_sfx.py   (ffmpeg(libvorbis)·인터넷 필요)
"""

from __future__ import annotations

import os
import subprocess
import tempfile
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "audio", "sfx")
BASE = "https://opengameart.org/sites/default/files/"
PACKS = {
	"sword": "sword_-_starninjas_1.zip",
	"clash": "sword_clash_-_starninjas_0.zip",
	"impact": "impact_-_starninjas.zip",
	"swish": "swishes.zip",
	"rpg": "rpg_sound_pack.zip",
	"cc0": "100-CC0-SFX_0.zip",
	"kenney": "RPGsounds_Kenney.zip",
}

# 소리 이름 → [(묶음, 파일 이름, 시작 지연(초), 음량(dB))]. 여럿이면 겹친다.
RECIPES: dict[str, list[tuple[str, str, float, float]]] = {
	# 칼이 살을 스친다: 휘두름 + 둔탁한 타격
	"hit": [("swish", "swish-5.wav", 0.0, -2), ("impact", "impact.8.ogg", 0.05, 0)],
	"hit_2": [("swish", "swish-3.wav", 0.0, -2), ("impact", "impact.2.ogg", 0.05, 0)],
	"hit_3": [("swish", "swish-6.wav", 0.0, -2), ("impact", "impact.10.ogg", 0.06, 0)],
	# 칼끼리 부딪혀 막는다
	"block": [("clash", "sword_clash.7.ogg", 0.0, 0)],
	"block_2": [("clash", "sword_clash.8.ogg", 0.0, 0)],
	"block_3": [("clash", "sword_clash.5.ogg", 0.0, 0)],
	# 몸을 틀어 흘린다: 바람 소리
	"evade": [("swish", "swish-9.wav", 0.0, -3)],
	"evade_2": [("swish", "swish-7.wav", 0.0, -3)],
	"evade_3": [("swish", "swish-4.wav", 0.0, -3)],
	# 절초: 크게 휘두르고 칼이 울리며 낮은 징이 깔린다
	"art": [("rpg", "swing.wav", 0.0, -1), ("clash", "sword_clash.1.ogg", 0.12, 0), ("cc0", "gong_01.ogg", 0.12, -9)],
	# 쓰러짐: 무거운 타격 + 옷자락
	"fall": [("impact", "impact.4.ogg", 0.0, 0), ("kenney", "cloth1.ogg", 0.08, -6)],
	"fall_2": [("impact", "impact.5.ogg", 0.0, 0), ("kenney", "cloth3.ogg", 0.08, -6)],
	# 겨루기 시작: 칼을 뽑고 징이 울린다
	"battle_start": [("rpg", "sword-unsheathe.wav", 0.0, -2), ("cc0", "gong_02.ogg", 0.35, -4)],
}

# 소리마다 최종 최고 크기(dBFS). 자주 나는 소리는 조금 낮게.
PEAK = {"evade": -6.0, "block": -3.0, "hit": -2.5, "fall": -3.0, "art": -1.5, "battle_start": -2.0}


def fetch(tmp: str) -> dict[str, str]:
	dirs = {}
	for key, name in PACKS.items():
		path = os.path.join(tmp, name)
		if not os.path.exists(path):
			print("받는 중:", name)
			urllib.request.urlretrieve(BASE + name, path)
		target = os.path.join(tmp, key)
		with zipfile.ZipFile(path) as z:
			z.extractall(target)
		dirs[key] = target
	return dirs


def find(root: str, filename: str) -> str:
	for dirpath, _, files in os.walk(root):
		if "__MACOSX" in dirpath:
			continue
		if filename in files:
			return os.path.join(dirpath, filename)
	raise FileNotFoundError(filename)


def build(name: str, layers, dirs: dict[str, str], tmp: str) -> None:
	inputs = []
	parts = []
	for i, (pack, filename, delay, gain) in enumerate(layers):
		inputs += ["-i", find(dirs[pack], filename)]
		# 앞의 빈 소리를 잘라 내고(-50dB 아래), 지연·음량을 준다
		parts.append(
			f"[{i}:a]aformat=sample_rates=44100:channel_layouts=mono,"
			f"silenceremove=start_periods=1:start_threshold=-50dB,"
			f"adelay={int(delay * 1000)},volume={gain}dB[a{i}]"
		)
	mix = "".join(f"[a{i}]" for i in range(len(layers)))
	graph = ";".join(parts) + f";{mix}amix=inputs={len(layers)}:normalize=0:duration=longest,"
	# 끝의 긴 꼬리는 잘라 내고 살짝 줄인다
	# 뒤집어서 앞의 빈 소리를 자르는 식으로 끝의 빈 소리를 잘라 낸다 (가운데의 짧은 틈은 그대로)
	graph += "areverse,silenceremove=start_periods=1:start_threshold=-60dB,areverse[out]"
	raw = os.path.join(tmp, name + ".wav")
	subprocess.run(["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", graph, "-map", "[out]", raw], check=True)
	# 최고 크기를 맞춘다
	probe = subprocess.run(["ffmpeg", "-v", "info", "-i", raw, "-af", "volumedetect", "-f", "null", "-"],
		capture_output=True, text=True).stderr
	peak = float(probe.split("max_volume:")[1].split("dB")[0])
	target = PEAK.get(name.split("_")[0] if name != "battle_start" else name, -3.0)
	out = os.path.join(OUT, name + ".ogg")
	subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", raw, "-af", f"volume={target - peak}dB",
		"-c:a", "libvorbis", "-q:a", "5", out], check=True)
	print(f"{name}.ogg  (최고 {target:.1f} dBFS)")


def main() -> None:
	os.makedirs(OUT, exist_ok=True)
	with tempfile.TemporaryDirectory() as tmp:
		dirs = fetch(tmp)
		for name, layers in RECIPES.items():
			build(name, layers, dirs, tmp)


if __name__ == "__main__":
	main()
