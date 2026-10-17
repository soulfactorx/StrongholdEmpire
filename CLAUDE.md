# 강호제패 (StrongholdEmpire)

무협 전략 시뮬레이션 RPG. Godot 4 (GDScript), 렌더러는 GL Compatibility.
기획 문서는 `docs/`에 있다.

## 언어 규칙

- 소스 코멘트, 커밋 메시지, PR 제목과 본문, 사용자에게 하는 답변은 **모두 한국어**로 작성한다.
- 식별자(변수·함수·클래스 이름)는 기존 코드처럼 영어를 쓴다.
- 게임 내 텍스트는 한국어다.

## 구조

- `scripts/Systems/` — 오토로드(GameManager, EventBus, AudioManager)와 정적 매니저 클래스
- `scripts/Resources/` — 데이터 Resource (CharacterData, SectData, MartialArtData 등)
- `scripts/Combat/`, `scenes/Combat/` — 그리드 전투
- `scripts/UI/`, `scenes/UI/` — 화면. 문파 경영 화면(`management_screen`)이 게임 허브다.
- 씬 전환은 `SceneRouter`를 통해서만 한다. 씬 경로 상수도 거기에 있다.
- 밸런스 수치는 `GameBalance`에 모은다.
- 기연은 `data/events/*.json` 데이터로 정의한다. 형식은 `docs/기연_데이터_형식.md` 참고.
  새 기연은 코드가 아니라 JSON으로 추가한다.
- 인물은 `data/npcs/*.json`, 문파는 `data/sects/*.json`으로 정의한다.
  형식은 `docs/NPC_문파_데이터_형식.md` 참고.

## 테스트

헤드리스 스모크 테스트 (커밋 전에 실행):

```
godot --headless --path . -s res://scripts/Tests/smoke_test.gd
```

새 스크립트를 추가했다면 먼저 `godot --headless --editor --quit`로 클래스 캐시를 갱신한다.
`.godot/`는 커밋하지 않는다.
