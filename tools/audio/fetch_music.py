#!/usr/bin/env python3
"""배경음악 4곡을 OpenGameArt에서 받아 게임에 맞게 다듬는다 (CC-BY, 출처는 assets/CREDITS.md·「만든 이들」 화면).

다듬기: 앞뒤 빈 소리를 자르고, 크기를 -16 LUFS 안팎으로 맞추고, 처음 0.4초·끝 2.5초를 서서히 키우고 줄인다
(AudioManager가 반복 재생하므로 끝과 처음이 부드럽게 이어지게). OGG Vorbis q3, 44.1kHz 스테레오.

실행: python3 tools/audio/fetch_music.py   (ffmpeg(libvorbis)·인터넷 필요)
generate_audio.py를 전부 다시 돌리면 배경음악이 합성곡으로 덮이므로, 그 뒤에 이 스크립트를 다시 돌린다.
"""

from __future__ import annotations

import os
import subprocess
import tempfile
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "audio", "music")
BASE = "https://opengameart.org/sites/default/files/"

# 곡 이름(AudioManager) → (원본 파일, 곡 제목, 만든 이, 라이선스, 페이지)
TRACKS = {
	"main": ("RPG_-_Misty_Mountains.ogg", "RPG - Misty Mountains", "HitCtrl", "CC-BY 3.0",
		"https://opengameart.org/content/rpg-misty-mountains"),
	"hub": ("Views%20From%20Atop%20the%20Jade%20Kings%20Throne.ogg", "Views From Atop the Jade Kings Throne", "HitCtrl", "CC-BY 3.0",
		"https://opengameart.org/content/views-from-atop-the-jade-kings-throne"),
	"combat": ("Most%20Critical.mp3_0.mp3", "Most Critical", "Dan Knoflicek (Macro)", "CC-BY 4.0",
		"https://opengameart.org/content/most-critical"),
	"ending": ("Viktor%20Kraus%20-%20The%20Pilgrimage_1.wav", "The Pilgrimage", "Viktor Kraus", "CC-BY 3.0",
		"https://opengameart.org/content/the-pilgrimage-0"),
}

TRIM = "silenceremove=start_periods=1:start_threshold=-55dB,areverse,silenceremove=start_periods=1:start_threshold=-55dB,areverse"


def duration(path: str) -> float:
	out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
		capture_output=True, text=True, check=True).stdout
	return float(out.strip())


def main() -> None:
	os.makedirs(OUT, exist_ok=True)
	with tempfile.TemporaryDirectory() as tmp:
		for name, (source, title, author, license_name, page) in TRACKS.items():
			raw = os.path.join(tmp, name + os.path.splitext(source)[1])
			print("받는 중:", title)
			urllib.request.urlretrieve(BASE + source, raw)
			norm = os.path.join(tmp, name + "_norm.wav")
			subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", raw, "-af",
				TRIM + ",loudnorm=I=-16:TP=-1.5:LRA=11,aresample=44100", "-ar", "44100", norm], check=True)
			length = duration(norm)
			out = os.path.join(OUT, name + ".ogg")
			subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", norm, "-af",
				f"afade=t=in:st=0:d=0.4,afade=t=out:st={length - 2.5:.3f}:d=2.5",
				"-c:a", "libvorbis", "-q:a", "3", out], check=True)
			print(f"{name}.ogg ← {title} — {author} ({license_name}) {page}")


if __name__ == "__main__":
	main()
