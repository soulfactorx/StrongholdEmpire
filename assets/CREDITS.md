# 그림·글꼴·소리 출처

## 글꼴 (`assets/fonts/`)
- **나눔명조** (본문), **나눔손글씨 붓** (제목·장기말 글자) — NAVER, SIL Open Font License 1.1.
  Google Fonts 저장소에서 받았다. 라이선스 전문: `assets/fonts/OFL.txt`

## 배경 (`assets/art/bg/`)
- 산수화 밑그림: Lingdong Huang의 **shan-shui-inf** (MIT License,
  https://github.com/LingDong-/shan-shui-inf) 로 시드별로 그렸다. 라이선스 전문: `assets/art/LICENSE_shan-shui-inf.txt`
- 그 위의 담채 색·해·낙관은 `tools/art/generate_art.py`가 더했다.

## 지형 타일·장기말·UI 텍스처 (`assets/art/tiles`, `tokens`, `ui`)
- `tools/art/generate_art.py`로 만든 절차적 그림이다. (이 저장소 소유)

## 다시 만들기
```
curl -sSfL -o <작업폴더>/index.html https://raw.githubusercontent.com/LingDong-/shan-shui-inf/master/index.html
node tools/art/render_shanshui.js <작업폴더>/index.html <밑그림폴더> 123 1003 2024 42 888 520 1001 1592
python3 tools/art/generate_art.py <밑그림폴더>
```
같은 이름·크기의 파일로 덮어쓰면(예: AI로 그린 그림) 코드 수정 없이 바뀐다.
배경 1920×1080 JPG, 타일 96px, 장기말 128px(가운데 비움), 버튼 96×48·패널 96px(9분할 여백 10·16px).

## 초상화·문장 (`assets/art/portraits`, `emblems`)
- `tools/art/generate_portraits.py`로 그린 절차적 수묵 초상화(NPC 19명·주인공 역할 7종)와 세력 문장 4개다. (이 저장소 소유)
- 인물별 모습(머리·관·옷 색·무기·표정·수염)은 생성기의 `NPCS`·`ROLES` 표에서 바꾼다.
  같은 이름·크기(초상화 256×320 JPG, 문장 256×256 PNG)로 덮어쓰면 코드 수정 없이 바뀐다

## 소리 (`assets/audio/`)
- 배경음악 4곡·효과음 10종 모두 `tools/audio/generate_audio.py`로 합성했다. (이 저장소 소유)
  다시 만들기: `python3 tools/audio/generate_audio.py` (numpy, libvorbis가 든 ffmpeg 필요)
- 같은 이름의 OGG로 덮어쓰면 코드 수정 없이 바뀐다. 배경음악은 반복 재생된다.
