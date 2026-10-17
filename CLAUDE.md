# 강호제패 (StrongholdEmpire)

무협 전략 시뮬레이션 RPG. Godot 4 (GDScript), 렌더러는 GL Compatibility.
기획 문서는 `docs/`에 있다. 남은 작업과 진행 순서는 `docs/구현_계획.md`를 따른다.

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
  새 기연은 코드가 아니라 JSON으로 추가한다. 스토리 아크는 `data/events/arcs/<아크>/`에 묶고,
  스모크 테스트 `_test_story_arcs`에 선택지를 고정한 진행 경로를 함께 추가한다.
- 기연에서 이어지는 전투는 `data/combats/*.json`으로 정의한다. 형식은 `docs/전투_데이터_형식.md` 참고.
- 인물은 `data/npcs/*.json`, 문파는 `data/sects/*.json`으로 정의한다.
  형식은 `docs/NPC_문파_데이터_형식.md` 참고.
- 엔딩은 `data/endings/*.json`으로 정의한다. 형식은 `docs/엔딩_데이터_형식.md` 참고.
  새 자동 엔딩을 추가하면 스모크 테스트의 도달 시험 상태도 함께 추가한다.
- 시나리오는 `data/scenarios/<id>/`로 정의한다. 형식은 `docs/시나리오_데이터_형식.md` 참고.
  게임 길이·난이도에 관한 값은 `GameBalance`를 직접 읽지 말고 `ScenarioRules`를 통해 읽는다.

## 플랫폼

- 모든 플랫폼 대상이며 우선순위는 모바일 → 웹 → PC → Mac → 콘솔이다.
- 새 화면은 터치만으로 모든 기능을 쓸 수 있어야 한다. 호버 전용 정보나 작은 버튼(48px 미만)을 만들지 않는다.

## 테스트

헤드리스 스모크 테스트 (커밋 전에 실행):

```
godot --headless --path . -s res://scripts/Tests/smoke_test.gd
```

검사는 영역별 파일 `scripts/Tests/test_*.gd`(core·events·combat·world·scenario·roles·ui)에 있고,
`smoke_test.gd`는 실행 순서(`INIT_SEQUENCE`·`RUNTIME_SEQUENCE`)와 결과 집계만 맡는다.
새 검사 함수는 해당 영역 파일에 넣고 순서 목록에 추가한다. 공통 도우미는 `test_base.gd`에 둔다.
밸런스 시뮬레이터(전투 자동 플레이·세력 AI·경제): `godot --headless --path . -s res://scripts/Tools/balance_sim.gd [-- combat|world|economy]`

새 스크립트를 추가했다면 먼저 `godot --headless --editor --quit`로 클래스 캐시를 갱신한다.
경제 수치(수입·유지비·시설·재고 손실)를 바꾸면 경제 시뮬레이터로 전략별 10년 추이를 확인한다:
`godot --headless --path . -s res://scripts/Tools/economy_sim.gd`
`.godot/`는 커밋하지 않는다.

GitHub Actions(`.github/workflows/smoke_test.yml`)가 푸시마다 같은 스모크 테스트를 돌리고,
데이터 정의 오류·스크립트 오류가 로그에 있으면 실패로 처리한다. Godot 버전을 올리면 워크플로의 `GODOT_VERSION`도 함께 바꾼다.
