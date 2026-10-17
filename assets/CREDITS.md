# 그림·글꼴·소리 출처

## 글꼴 (`assets/fonts/`)
- **나눔명조** (본문), **나눔손글씨 붓** (제목·장기말 글자) — NAVER, SIL Open Font License 1.1.
  Google Fonts 저장소에서 받았다. 라이선스 전문: `assets/fonts/OFL.txt`

## 그림 (`assets/art/`)
- 배경 8장·초상화 26장·세력 문장 4개·지형 타일·장기말·UI 텍스처는 프로젝트 소유자가 제작해 넣은 수묵담채 세트다 (2026년 10월).
  - 초상화에는 이름을 넣지 않았다. 이름은 게임 UI가 옆이나 아래에 쓴다.
  - 문장은 글자 대신 문양이다. 청운은 학과 검, 남궁은 검과 매화, 흑풍은 매, 천마는 마두.
  - 크게 쓸 원본(hires)은 저장소에 넣지 않고 따로 보관한다.
- 규격: 배경 1920×1080 JPG, 초상화 256×320 JPG, 문장 256×256 PNG(바깥 투명), 타일 96px, 장기말 128px(가운데 비움),
  버튼 96×48·패널 96px(9분할 여백 10·16px). 같은 이름·크기로 덮어쓰면 코드 수정 없이 바뀐다.

## 예전 절차적 그림 도구 (`tools/art/`)
- 그림 세트가 들어오기 전에 쓰던 생성기다. **실행하면 `assets/art/`의 지금 그림을 덮어쓴다.** 새 그림을 시험 삼아 만들 때만
  다른 폴더로 옮겨 쓰거나, 덮어쓴 뒤 git으로 되돌린다.
  - `generate_art.py`: 배경(shan-shui-inf 밑그림, MIT, `assets/art/LICENSE_shan-shui-inf.txt`)·타일·장기말·UI
  - `generate_portraits.py`: 초상화·문장

## 소리 (`assets/audio/`)
- 배경음악 4곡·효과음 10종 모두 `tools/audio/generate_audio.py`로 합성했다. (이 저장소 소유)
  다시 만들기: `python3 tools/audio/generate_audio.py` (numpy, libvorbis가 든 ffmpeg 필요)
- 같은 이름의 OGG로 덮어쓰면 코드 수정 없이 바뀐다. 배경음악은 반복 재생된다.
