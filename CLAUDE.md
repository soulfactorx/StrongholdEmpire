# 강호제패 (StrongholdEmpire)

무협 전략 시뮬레이션 RPG. Godot 4 (GDScript), 렌더러는 GL Compatibility.
기획 문서는 `docs/`에 있다. 남은 작업과 진행 순서는 `docs/구현_계획.md`를 따른다.

## 언어 규칙

- 소스 코멘트, 커밋 메시지, PR 제목과 본문, 사용자에게 하는 답변은 **모두 한국어**로 작성한다.
- 식별자(변수·함수·클래스 이름)는 기존 코드처럼 영어를 쓴다.
- 게임 내 텍스트는 한국어다. 무협 용어를 쓰고 `docs/용어집.md`를 따른다 (은자·깨달음·경지·전각·신분 등).

## 구조

- `scripts/Systems/` — 오토로드(GameManager, EventBus, AudioManager)와 정적 매니저 클래스
- `scripts/Resources/` — 데이터 Resource (CharacterData, SectData, MartialArtData 등)
- `scripts/Combat/`, `scenes/Combat/` — 초식 배치 대결 (판정 `DuelRules`·`DuelEngine`, 화면 `duel_controller.gd`)
- `scripts/UI/`, `scenes/UI/` — 화면. 문파 경영 화면(`management_screen`)이 게임 허브다.
- 씬 전환은 `SceneRouter`를 통해서만 한다. 씬 경로 상수도 거기에 있다.
- 밸런스 수치는 `GameBalance`에 모은다.
- 기연은 `data/events/*.json` 데이터로 정의한다. 형식은 `docs/기연_데이터_형식.md` 참고.
  새 기연은 코드가 아니라 JSON으로 추가한다. 스토리 아크는 `data/events/arcs/<아크>/`에 묶고,
  스모크 테스트 `_test_story_arcs`에 선택지를 고정한 진행 경로를 함께 추가한다.
- 기연에서 이어지는 전투는 `data/combats/*.json`으로 정의한다. 형식은 `docs/전투_데이터_형식.md` 참고.
  전투의 형식(연전·포위·진형·추격·잠입·대치·비무대회)·전장·조건·특성·사건은 `docs/전투_다양화_설계.md`.
- 경영 화면 행동 뒤의 대화 장면은 `data/scenes/actions/<행동>.json`으로 정의한다. 형식은 `docs/행동_장면_데이터_형식.md` 참고.
  새 행동 버튼을 만들면 그 행동의 장면(서술 장면 하나 이상 포함)도 함께 추가한다.
- 인물은 `data/npcs/*.json`, 문파는 `data/sects/*.json`으로 정의한다.
  형식은 `docs/NPC_문파_데이터_형식.md` 참고.
- 강호 지도는 `data/map/regions.json`으로 정의한다. 형식은 `docs/지도_데이터_형식.md` 참고.
- 결말은 `data/endings/*.json`으로 정의한다. 형식은 `docs/결말_데이터_형식.md` 참고.
  새 자동 결말을 추가하면 스모크 테스트의 도달 시험 상태도 함께 추가한다.
- 시나리오는 `data/scenarios/<id>/`로 정의한다. 형식은 `docs/시나리오_데이터_형식.md` 참고.
  게임 길이·난이도에 관한 값은 `GameBalance`를 직접 읽지 말고 `ScenarioRules`를 통해 읽는다.
- 메인 시나리오 「강호삼란」(정·사·마 세 번의 대전)은 `docs/메인_시나리오.md`와 `data/scenarios/saga_*/`에 있다.
  장마다 등장인물(`playables`)을 골라 플레이하고, 기연은 선택지 조건·장면 대사(`scene`)로 인물마다 달라진다.
  장의 기연·결말을 바꾸면 스모크 테스트 `_test_main_saga_paths`의 진행 경로도 함께 고친다.

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
밸런스 시뮬레이터(전투 자동 플레이·세력 AI·경제): `godot --headless --path . -s res://scripts/Tools/balance_sim.gd [-- combat|world|economy] [runs=N] [only=전투,…]`
전투 수치(적 배율·`GameBalance`의 `DUEL_*`)를 바꾸면 전투 시뮬레이션 결과를 `docs/구현_계획.md` M9-10에 갱신한다.

새 스크립트를 추가했다면 먼저 `godot --headless --editor --quit`로 클래스 캐시를 갱신한다.
경제 수치(수입·씀씀이·전각·재고 손실)를 바꾸면 경제 시뮬레이터로 전략별 10년 추이를 확인한다:
`godot --headless --path . -s res://scripts/Tools/economy_sim.gd`
`.godot/`는 커밋하지 않는다.

내보내기 프리셋은 `export_presets.cfg`(Android·웹·윈도우·리눅스). 내보낸 빌드 자체 점검: `<실행 파일> --headless -- --self-check`.
`.github/workflows/export.yml`이 푸시마다 네 플랫폼을 내보내고 APK·웹·윈도우 빌드를 아티팩트로 올린다. `main`이면 웹 빌드를 GitHub Pages에 배포한다. 기기 시험은 `docs/기기_테스트_안내.md`.
`main`에 머지되면 같은 워크플로가 GitHub 릴리스를 자동으로 만들고 네 플랫폼 파일을 붙인다 (`v*` 태그 푸시도 같다, `docs/릴리스_안내.md`).
게임 버전은 `project.godot`의 `config/version`이고, 그 버전이 이미 나갔으면 끝자리를 올려 낸다. 큰 변화는 `config/version`을 올려 머지한다.

GitHub Actions(`.github/workflows/smoke_test.yml`)가 푸시마다 같은 스모크 테스트를 돌리고,
데이터 정의 오류·스크립트 오류가 로그에 있으면 실패로 처리한다. Godot 버전을 올리면 워크플로의 `GODOT_VERSION`도 함께 바꾼다.
