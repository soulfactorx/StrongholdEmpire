#!/usr/bin/env python3
"""국악풍 배경음악·효과음 합성기.

무료 음원을 받을 수 없는 환경에서 쓰는 절차적 소리다. 같은 시드로 늘 같은 소리를 만든다.
- 악기: 뜯는 현(가야금·쟁 느낌, 배음 덧셈 합성), 대금(사인파 + 숨소리 + 떨림), 북, 징, 목탁, 풍경
- 음계: 5음 음계. 잔향은 합성 임펄스 응답과의 FFT 합성곱
- 배경음악은 끝의 잔향을 앞으로 접어 넣어 이음매 없이 반복된다

실행: python3 tools/audio/generate_audio.py [이름 ...]   (numpy와 libvorbis가 든 ffmpeg 필요. 이름을 주면 그 소리만)
같은 이름의 파일로 덮어쓰면 코드 수정 없이 바뀐다.
"""

from __future__ import annotations

import os
import subprocess
import tempfile
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "audio")
SR = 44100


def midi_hz(note: float) -> float:
	return 440.0 * 2 ** ((note - 69) / 12)


# ─── 악기 ─────────────────────────────────────────

def env_ad(n: int, attack: float, decay: float) -> np.ndarray:
	t = np.arange(n) / SR
	a = np.clip(t / max(attack, 1e-4), 0, 1)
	return a * np.exp(-t / decay)


def pluck(freq: float, dur: float, rng, bright: float = 1.0, decay: float = 1.6) -> np.ndarray:
	"""뜯는 현: 배음마다 감쇠가 빠르고, 살짝 어긋난 배음과 손톱 잡음을 더한다."""
	n = int(SR * dur)
	t = np.arange(n) / SR
	out = np.zeros(n)
	for k in range(1, 12):
		f = freq * k * (1 + 0.0007 * k * k)
		if f > SR / 2.2:
			break
		amp = (1.0 / k ** (1.3 - 0.3 * bright)) * (1.0 if k % 2 else 0.7)
		out += amp * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t * (1 / decay) * (1 + 0.55 * k))
	# 줄을 뜯은 뒤 살짝 눌러 올리는 농현 느낌
	bend = 1 + 0.004 * np.sin(2 * np.pi * 5.0 * t) * np.clip((t - 0.25) / 0.4, 0, 1)
	out = np.interp(np.cumsum(bend) - 1, np.arange(n), out)
	noise = rng.standard_normal(n) * np.exp(-t / 0.008) * 0.3
	out = out + noise
	out *= np.clip(t / 0.003, 0, 1)
	return out / 3.0


def flute(freq: float, dur: float, rng, vibrato: float = 1.0) -> np.ndarray:
	"""대금: 부드러운 시작, 늦게 오는 떨림, 숨소리"""
	n = int(SR * (dur + 0.35))
	t = np.arange(n) / SR
	vib = 1 + 0.006 * vibrato * np.sin(2 * np.pi * 5.2 * t) * np.clip((t - 0.3) / 0.5, 0, 1)
	phase = 2 * np.pi * np.cumsum(freq * vib) / SR
	tone = np.sin(phase) + 0.18 * np.sin(2 * phase) + 0.06 * np.sin(3 * phase)
	breath = rng.standard_normal(n)
	breath = np.convolve(breath, np.ones(12) / 12, mode="same")
	env = np.clip(t / 0.12, 0, 1) * np.clip((dur + 0.35 - t) / 0.35, 0, 1)
	swell = 0.85 + 0.15 * np.sin(np.pi * np.clip(t / max(dur, 0.1), 0, 1))
	return (tone * 0.5 + breath * 0.08) * env * swell


def drum(rng, size: float = 1.0, dur: float = 0.9) -> np.ndarray:
	"""북: 음높이가 떨어지는 사인파 + 가죽 잡음"""
	n = int(SR * dur)
	t = np.arange(n) / SR
	f = (55 + 70 * np.exp(-t / 0.05)) / size
	body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / (0.32 * size))
	skin = rng.standard_normal(n)
	skin = np.convolve(skin, np.ones(30) / 30, mode="same") * np.exp(-t / 0.03) * 1.5
	return (body + skin) * 0.9


def gong(rng, freq: float = 110.0, dur: float = 6.0) -> np.ndarray:
	"""징: 어긋난 배음, 느린 울림, 치고 나서 살짝 올라가는 음"""
	n = int(SR * dur)
	t = np.arange(n) / SR
	out = np.zeros(n)
	for ratio, amp, dec in [(1.0, 1.0, 3.0), (1.47, 0.6, 2.2), (2.09, 0.45, 1.6), (2.76, 0.3, 1.1), (3.4, 0.2, 0.8)]:
		f = freq * ratio * (1 + 0.012 * (1 - np.exp(-t / 0.6)))
		out += amp * np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / dec)
	out *= np.clip(t / 0.02, 0, 1) * (0.7 + 0.3 * np.sin(2 * np.pi * 2.3 * t) ** 2)
	return out * 0.45


def woodblock(rng, freq: float = 820.0) -> np.ndarray:
	"""목탁"""
	n = int(SR * 0.18)
	t = np.arange(n) / SR
	out = np.sin(2 * np.pi * freq * t) * np.exp(-t / 0.025) + 0.5 * np.sin(2 * np.pi * freq * 1.58 * t) * np.exp(-t / 0.012)
	return out * np.clip(t / 0.001, 0, 1) * 0.8


def chime(freq: float, rng, dur: float = 2.5) -> np.ndarray:
	"""풍경"""
	n = int(SR * dur)
	t = np.arange(n) / SR
	out = np.zeros(n)
	for ratio, amp, dec in [(1.0, 1.0, 1.2), (2.76, 0.5, 0.5), (5.4, 0.25, 0.25), (8.9, 0.1, 0.12)]:
		out += amp * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-t / dec)
	return out * np.clip(t / 0.002, 0, 1) * 0.35


def swish(rng, dur: float = 0.35, rising: bool = True) -> np.ndarray:
	"""바람 가르는 소리: 대역이 움직이는 잡음"""
	n = int(SR * dur)
	t = np.arange(n) / SR
	noise = rng.standard_normal(n)
	out = np.zeros(n)
	# 짧은 창으로 저역을 걸러 대역을 옮긴다
	for w, weight in [(2, 1.0), (4, 0.6), (8, 0.3)]:
		out += np.convolve(noise, np.ones(w) / w, mode="same") * weight
	shape = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 2
	if rising:
		shape *= np.clip(t / dur, 0.2, 1)
	return out * shape * 0.35


# ─── 믹스 도구 ────────────────────────────────────

class Mix:
	def __init__(self, seconds: float, tail: float = 4.0):
		self.length = int(SR * seconds)
		self.buf = np.zeros((self.length + int(SR * tail), 2))

	def add(self, sound: np.ndarray, at: float, gain: float = 1.0, pan: float = 0.0) -> None:
		start = int(SR * at)
		end = min(start + len(sound), len(self.buf))
		if start >= len(self.buf):
			return
		left = np.cos((pan + 1) * np.pi / 4)
		right = np.sin((pan + 1) * np.pi / 4)
		seg = sound[: end - start] * gain
		self.buf[start:end, 0] += seg * left
		self.buf[start:end, 1] += seg * right


def reverb(buf: np.ndarray, rng, seconds: float = 2.4, wet: float = 0.28) -> np.ndarray:
	"""합성 임펄스 응답(감쇠하는 잡음)과의 FFT 합성곱"""
	n = int(SR * seconds)
	t = np.arange(n) / SR
	out = np.zeros_like(buf)
	for ch in range(2):
		ir = rng.standard_normal(n) * np.exp(-t / (seconds / 5.5))
		ir = np.convolve(ir, np.ones(6) / 6, mode="same")  # 높은 소리가 먼저 사라지게
		ir[: int(SR * 0.012)] = 0  # 첫 반사까지의 틈
		ir /= np.sqrt(np.sum(ir ** 2))
		size = 1 << int(np.ceil(np.log2(len(buf) + n)))
		conv = np.fft.irfft(np.fft.rfft(buf[:, ch], size) * np.fft.rfft(ir, size), size)[: len(buf)]
		out[:, ch] = buf[:, ch] + conv * wet
	return out


def finish(buf: np.ndarray, peak: float = 0.85) -> np.ndarray:
	m = np.max(np.abs(buf))
	if m > 0:
		buf = buf / m * peak
	return np.tanh(buf * 1.1) / np.tanh(1.1)


def loop_fold(mix: Mix, rng, wet: float = 0.28) -> np.ndarray:
	"""잔향을 건 뒤 끝을 앞으로 접어 반복할 때 이음매가 없게 한다."""
	full = reverb(mix.buf, rng, wet=wet)
	body = full[: mix.length].copy()
	tail = full[mix.length:]
	k = min(len(tail), len(body))
	body[:k] += tail[:k]
	return body


def save(audio: np.ndarray, rel: str, quality: int = 4) -> None:
	"""16비트 WAV로 쓴 뒤 ffmpeg(libvorbis)로 OGG Vorbis를 만든다."""
	path = os.path.join(OUT, rel)
	os.makedirs(os.path.dirname(path), exist_ok=True)
	pcm = (np.clip(audio, -1, 1) * 32767).astype("<i2")
	with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
		wav_path = tmp.name
	try:
		with wave.open(wav_path, "wb") as w:
			w.setnchannels(pcm.shape[1] if pcm.ndim == 2 else 1)
			w.setsampwidth(2)
			w.setframerate(SR)
			w.writeframes(pcm.tobytes())
		subprocess.run(
			["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path, "-c:a", "libvorbis", "-q:a", str(quality), path],
			check=True,
		)
	finally:
		os.unlink(wav_path)
	print("  ", rel, "%.1f초" % (len(audio) / SR), "%dKB" % (os.path.getsize(path) // 1024))


# ─── 배경음악 ─────────────────────────────────────

# 평조(솔 라 도 레 미) 5음 음계 계단: 음 번호 → 반음
PENTA = [0, 2, 4, 7, 9]


def scale_note(root: int, degree: int, mode: list[int] = PENTA) -> int:
	octave, idx = divmod(degree, len(mode))
	return root + 12 * octave + mode[idx]


def phrase(rng, length: int, start: int, low: int, high: int, end: int | None = None) -> list[int]:
	"""음계 위를 주로 이웃 음으로 걷는 선율. 마지막 음을 정할 수 있다."""
	notes = [start]
	for _ in range(length - 1):
		step = rng.choice([-2, -1, -1, 1, 1, 2, 0], p=[0.1, 0.25, 0.1, 0.25, 0.1, 0.1, 0.1])
		notes.append(int(np.clip(notes[-1] + step, low, high)))
	if end is not None:
		notes[-1] = end
	return notes


def music_main(rng) -> np.ndarray:
	"""메인: 느린 대금 선율 위에 가야금이 드문드문, 낮은 지속음"""
	bpm = 62
	beat = 60 / bpm
	bars = 16
	mix = Mix(bars * 4 * beat)
	root = 50  # D3
	# 지속음
	for bar in range(0, bars, 4):
		for deg, g in [(0, 0.3), (3, 0.18)]:
			f = midi_hz(scale_note(root - 12, deg))
			mix.add(flute(f, 4 * 4 * beat - 0.3, rng, vibrato=0.2) * 0.6, bar * 4 * beat, g, -0.3)
	# 대금 선율: 4마디 동기 두 개를 변주
	motif_a = phrase(rng, 6, 7, 5, 11, end=5)
	motif_b = phrase(rng, 6, 9, 5, 12, end=7)
	rhythm = [1.5, 0.5, 2, 1, 1, 2]  # 박 (합계 8박 = 2마디)
	pos = 2 * 4 * beat
	for rep, motif in enumerate([motif_a, motif_b, motif_a, motif_b, motif_a]):
		if rep == 4:
			motif = motif[:-1] + [5]
		for deg, r in zip(motif, rhythm):
			mix.add(flute(midi_hz(scale_note(root, deg)), r * beat * 0.95, rng), pos, 0.55, 0.2)
			pos += r * beat
		pos += 4 * beat  # 숨 쉬는 쉼
	# 가야금: 마디 첫 박에 저음, 사이사이 고음 꾸밈
	for bar in range(bars):
		t0 = bar * 4 * beat
		mix.add(pluck(midi_hz(scale_note(root - 12, [0, 3, 2, 0][bar % 4])), 3.5, rng, 0.6, 2.2), t0, 0.7, -0.4)
		if rng.random() < 0.6:
			for k in range(rng.integers(1, 4)):
				deg = int(rng.integers(5, 11))
				mix.add(pluck(midi_hz(scale_note(root, deg)), 2.0, rng, 1.0, 1.2), t0 + (2 + k * 0.5) * beat, 0.35, 0.5)
	# 첫머리 징
	mix.add(gong(rng, 98.0), 0.0, 0.5)
	return finish(loop_fold(mix, rng, 0.32))


def music_hub(rng) -> np.ndarray:
	"""경영: 가야금 분산화음이 고르게 흐르는 잔잔한 곡"""
	bpm = 84
	beat = 60 / bpm
	bars = 24
	mix = Mix(bars * 4 * beat)
	root = 55  # G3
	progression = [0, 0, 3, 3, 4, 4, 2, 0]  # 마디마다 바탕 음 (계단)
	pattern = [0, 2, 4, 5, 4, 2, 3, 2]  # 8분음표 분산
	for bar in range(bars):
		base = progression[bar % len(progression)]
		t0 = bar * 4 * beat
		mix.add(pluck(midi_hz(scale_note(root - 12, base)), 3.0, rng, 0.5, 2.4), t0, 0.6, -0.3)
		for i, step in enumerate(pattern):
			if rng.random() < 0.12:
				continue
			deg = base + step
			mix.add(pluck(midi_hz(scale_note(root, deg)), 1.6, rng, 0.8, 1.0), t0 + i * beat / 2, 0.28 + 0.08 * (i == 0), 0.25)
	# 8마디마다 대금이 짧은 노래를 얹는다
	for section in (8, 16):
		pos = section * 4 * beat
		for deg, r in zip(phrase(rng, 7, 7, 5, 11, end=5), [1, 1, 2, 1, 1, 1, 1]):
			mix.add(flute(midi_hz(scale_note(root, deg)), r * beat * 0.9, rng), pos, 0.35, 0.1)
			pos += r * beat
	# 목탁이 두 마디에 한 번
	for bar in range(0, bars, 2):
		mix.add(woodblock(rng, 760), bar * 4 * beat, 0.25, -0.6)
	return finish(loop_fold(mix, rng, 0.26), 0.8)


def music_combat(rng) -> np.ndarray:
	"""전투: 빠른 북 장단과 날카로운 뜯는 현, 단조풍 5음"""
	bpm = 132
	beat = 60 / bpm
	bars = 16
	mix = Mix(bars * 4 * beat, tail=3.0)
	root = 57  # A3
	minor = [0, 3, 5, 7, 10]
	# 북 장단 (16분 칸): 큰북·작은북
	big = [0, 6, 8, 11]
	small = [4, 12, 14, 15]
	for bar in range(bars):
		t0 = bar * 4 * beat
		for s in big:
			mix.add(drum(rng, 1.0), t0 + s * beat / 4, 0.9, -0.1)
		for s in small:
			if bar % 4 == 3 or s != 15:
				mix.add(drum(rng, 0.55, 0.4), t0 + s * beat / 4, 0.45, 0.3)
		if bar % 4 == 0:
			mix.add(gong(rng, 82.0, 4.0), t0, 0.35)
	# 저음 현: 8분음표로 몰아친다
	bass = [0, 0, 3, 0, 4, 3, 2, 1]
	for bar in range(bars):
		t0 = bar * 4 * beat
		shift = [0, 0, 2, 1][(bar // 2) % 4]
		for i in range(8):
			deg = bass[i] + shift if i % 2 == 0 else shift
			mix.add(pluck(midi_hz(scale_note(root - 24, deg, minor)), 0.6, rng, 1.0, 0.5), t0 + i * beat / 2, 0.45, -0.3)
	# 고음 현 선율: 16분 떨기(트레몰로)로 긴 음을 낸다
	pos = 4 * 4 * beat
	for rep in range(2):
		for deg, r in zip(phrase(rng, 8, 5, 3, 10, end=5 if rep else 7), [1, 1, 2, 1, 1, 2, 2, 2]):
			f = midi_hz(scale_note(root, deg, minor))
			for k in range(int(r * 4)):
				mix.add(pluck(f, 0.4, rng, 1.2, 0.35), pos + k * beat / 4, 0.22 + 0.06 * (k == 0), 0.35)
			pos += r * beat
	return finish(loop_fold(mix, rng, 0.18), 0.9)


def music_ending(rng) -> np.ndarray:
	"""엔딩: 징으로 열고, 대금이 길게 노래하는 느린 곡"""
	bpm = 56
	beat = 60 / bpm
	bars = 12
	mix = Mix(bars * 4 * beat)
	root = 53  # F3
	mix.add(gong(rng, 87.0, 7.0), 0.0, 0.6)
	for bar in range(0, bars, 2):
		deg = [0, 3, 2, 0, 4, 0][(bar // 2) % 6]
		mix.add(flute(midi_hz(scale_note(root - 12, deg)), 2 * 4 * beat - 0.2, rng, 0.2), bar * 4 * beat, 0.25, -0.3)
		mix.add(pluck(midi_hz(scale_note(root - 12, deg)), 4.0, rng, 0.5, 2.6), bar * 4 * beat, 0.5, -0.4)
	pos = 1 * 4 * beat
	for motif_end in (7, 5):
		for deg, r in zip(phrase(rng, 7, 9, 5, 12, end=motif_end), [2, 1, 1, 3, 1, 2, 4]):
			mix.add(flute(midi_hz(scale_note(root, deg)), r * beat * 0.95, rng), pos, 0.5, 0.15)
			pos += r * beat
		pos += 2 * beat
	for k in range(6):
		mix.add(chime(midi_hz(scale_note(root + 24, int(rng.integers(0, 5)))), rng), (k * 2 + 1.5) * 4 * beat / 1.5, 0.18, 0.6)
	return finish(loop_fold(mix, rng, 0.36), 0.8)


MUSIC = {
	"main": music_main,
	"hub": music_hub,
	"combat": music_combat,
	"ending": music_ending,
}


# ─── 효과음 ───────────────────────────────────────

def sfx(seconds: float, fn, rng, wet: float = 0.12) -> np.ndarray:
	mix = Mix(seconds, tail=0.6)
	fn(mix)
	out = finish(reverb(mix.buf, rng, seconds=0.8, wet=wet), 0.8)
	# 끝의 무음을 잘라 낸다
	loud = np.nonzero(np.max(np.abs(out), axis=1) > 0.002)[0]
	end = min(len(out), (loud[-1] if len(loud) else 0) + int(SR * 0.05))
	out = out[:end]
	fade = min(len(out), int(SR * 0.04))
	out[-fade:] *= np.linspace(1, 0, fade)[:, None]
	return out


def build_sfx(rng) -> dict[str, np.ndarray]:
	d = midi_hz
	return {
		"click": sfx(0.12, lambda m: m.add(woodblock(rng, 900), 0, 0.8), rng, 0.05),
		"success": sfx(0.6, lambda m: [m.add(pluck(d(67), 0.8, rng, 1.0, 0.6), 0, 0.7, -0.2),
			m.add(pluck(d(74), 0.8, rng, 1.0, 0.6), 0.09, 0.7, 0.2)], rng),
		"failure": sfx(0.7, lambda m: [m.add(pluck(d(57), 0.9, rng, 0.4, 0.5), 0, 0.8, -0.1),
			m.add(pluck(d(52), 0.9, rng, 0.4, 0.5), 0.14, 0.8, 0.1)], rng),
		"event": sfx(1.6, lambda m: [m.add(chime(d(81), rng), 0, 0.8, -0.2),
			m.add(chime(d(88), rng), 0.12, 0.6, 0.3)], rng, 0.2),
		"hit": sfx(0.5, lambda m: [m.add(drum(rng, 0.7, 0.4), 0, 1.0),
			m.add(swish(rng, 0.08, False), 0, 0.8)], rng, 0.08),
		"art": sfx(0.9, lambda m: [m.add(swish(rng, 0.35), 0, 1.0),
			m.add(pluck(d(79), 0.8, rng, 1.2, 0.5), 0.3, 0.6, 0.3),
			m.add(drum(rng, 0.8, 0.5), 0.32, 0.8)], rng, 0.15),
		"level_up": sfx(2.2, lambda m: [m.add(pluck(d(n), 1.2, rng, 1.0, 0.8), i * 0.09, 0.6, -0.4 + i * 0.2)
			for i, n in enumerate([62, 64, 67, 69, 74])] + [m.add(gong(rng, 196.0, 2.0), 0.45, 0.5)], rng, 0.2),
		"battle_start": sfx(3.0, lambda m: [m.add(gong(rng, 92.0, 3.5), 0, 1.0), m.add(drum(rng, 1.1), 0, 0.8)], rng, 0.25),
		"victory": sfx(2.6, lambda m: [m.add(pluck(d(n), 1.6, rng, 0.9, 1.0), i * 0.14, 0.6)
			for i, n in enumerate([55, 62, 67, 71, 74])] + [m.add(chime(d(86), rng), 0.7, 0.5, 0.3)], rng, 0.25),
		"defeat": sfx(2.6, lambda m: [m.add(gong(rng, 73.0, 3.0), 0, 0.9),
			m.add(pluck(d(45), 2.0, rng, 0.4, 1.4), 0.1, 0.6)], rng, 0.25),
		# 합 무대 연출 (뒤에 덧붙여 앞의 소리는 그대로 나온다)
		"block": sfx(0.35, lambda m: [m.add(woodblock(rng, 620), 0, 0.9),
			m.add(pluck(d(88), 0.3, rng, 1.6, 0.12), 0, 0.45)], rng, 0.06),
		"evade": sfx(0.3, lambda m: m.add(swish(rng, 0.22, False), 0, 1.0), rng, 0.05),
		"fall": sfx(1.0, lambda m: [m.add(drum(rng, 1.2, 0.7), 0, 1.0),
			m.add(pluck(d(43), 0.9, rng, 0.3, 0.6), 0.05, 0.5)], rng, 0.15),
		"focus": sfx(1.0, lambda m: [m.add(chime(d(84), rng, 1.0), 0, 0.5),
			m.add(chime(d(91), rng, 1.0), 0.08, 0.35, 0.2)], rng, 0.2),
	}


def main(only: list[str] | None = None) -> None:
	"""only: 이 이름의 소리만 다시 쓴다 (예: block evade). 없으면 모두"""
	seed = 20261017
	for i, (name, fn) in enumerate(MUSIC.items()):
		if not only or name in only:
			save(fn(np.random.default_rng(seed + i)), f"music/{name}.ogg")
	for name, audio in build_sfx(np.random.default_rng(seed + 100)).items():
		if not only or name in only:
			save(audio, f"sfx/{name}.ogg")


if __name__ == "__main__":
	import sys
	main(sys.argv[1:] or None)
