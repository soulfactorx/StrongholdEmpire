# NPC·문파 데이터 형식

인물과 문파는 JSON 데이터로 정의합니다. 파일 하나가 인물 한 명 또는 문파 하나입니다.
형식이 잘못된 파일은 경고를 남기고 건너뜁니다.

- NPC 명부: `data/npcs/*.json` → `scripts/Systems/npc_roster.gd`
- 문파: `data/sects/*.json` → `scripts/Systems/sect_registry.gd`

## NPC

```json
{
  "id": "npc_rival",
  "display_name": "남궁휘",
  "title": "남궁세가 소가주",
  "sect_id": "namgung",
  "role": "YOUNG_DISCIPLE",
  "description": "남궁세가의 젊은 후계자.",
  "level": 2,
  "stats": { "strength": 14, "agility": 13, "wisdom": 10, "charisma": 9, "internal_energy_max": 100 },
  "scaling": { "base_level": 2, "level_offset": 0, "per_level": { "strength": 1, "agility": 1 } },
  "initial_bond": { "type": "RIVALRY", "strength": 15, "stage": 0 }
}
```

| 필드 | 설명 |
|---|---|
| `id` | 고유 id. 전투·관계·기연에서 이 id로 가리킵니다. |
| `display_name`, `title`, `description` | 이름, 호칭, 소개 (강호 정세 화면에 표시) |
| `sect_id` | 소속 문파 id. `data/sects/`에 있어야 합니다. |
| `role` | `LEADER`, `MANAGER`, `YOUNG_DISCIPLE`, `WANDERER`, `SPY`, `ASSASSIN`, `MERCENARY` |
| `level`, `stats` | 레벨과 능력치 (`strength`, `agility`, `wisdom`, `charisma`, `internal_energy_max`, `age`, `morality`) |
| `scaling` | (선택) 플레이어와 함께 성장. 레벨 = max(`base_level`, 플레이어 레벨 + `level_offset`), `per_level` 능력치가 레벨당 증가 |
| `initial_bond` | (선택) 새 게임 시작 관계. `type`은 `MASTER_DISCIPLE`, `ROMANCE`, `BLOOD_OATH`, `RIVALRY`, `HATRED` |

`scaling`이 있고 `initial_bond`가 없는 인물(예: 도적)은 이름 없는 졸개로 보고 인물 목록에서 뺍니다.

| (선택) `war_specialty` | 문파전 장수로 참전할 때 보너스를 주는 명령: `CHARGE`(돌격) · `DEFEND`(방어) · `FLANK`(측면) |
| (선택) `martial_arts` | `[{ "id": 무공 id, "min_level": 레벨 }]` — 그 레벨 이상이면 전투에서 해당 무공을 씁니다. 무공 id는 `resources/MartialArts/`의 프리셋 또는 `data/martial_arts/`의 모드 무공 |

특수 용도 인물:
- `npc_bandit`: 도적 전투의 적 템플릿
- `npc_disciple`: 문파 방어전에 합류하는 아군 제자 템플릿. 무술장 레벨 1을 넘는 단계마다 무력·신법이 오릅니다.

## 문파

```json
{
  "id": "heukpung",
  "sect_name": "흑풍채",
  "alignment": "UNORTHODOX",
  "leader_id": "npc_heukpung_chief",
  "description": "관도를 장악한 사파 산채.",
  "reputation": 35,
  "disciple_count": 16,
  "max_disciples": 30,
  "training_ground_level": 1,
  "attitude": -30
}
```

| 필드 | 설명 |
|---|---|
| `id`, `sect_name`, `description` | 고유 id, 이름, 소개 |
| `alignment` | `RIGHTEOUS`(정파), `UNORTHODOX`(사파), `DEMONIC`(마교) |
| `leader_id` | 문주 NPC id. 명부에 있어야 하며, 이 인물의 능력치가 문파전 전력에 들어갑니다. |
| `is_player_sect` | (선택) `true`인 문파 하나가 플레이어 문파가 됩니다. |
| `attitude` | 플레이어 문파에 대한 태도 (-100 적대 ~ 100 우호) |
| 수치 필드 | `gold`, `food`, `reputation`, `research_points`, `disciple_count`, `max_disciples`, `library_level`, `training_ground_level`, `treasury_level` |
| `war_tactics` | (선택) 문파전 명령 선택 가중치. 예: `{ "CHARGE": 0.4, "DEFEND": 0.15, "FLANK": 0.4, "RETREAT": 0.05 }`. 없으면 성향별 기본값 |
| `war_formation` | (선택) 문파전 진형: `CRANE`(학익진) · `FISH`(어린진) · `CIRCLE`(방원진) · `NONE`. 없으면 성향별 기본값 |

## 문파전과의 관계

- 적 전력 = (제자 수 × 3 + 무술장 레벨 × 8 + 문주 전투력 × 역할 보정 + 명성 / 5) × 시나리오 적 강도
- 라운드 판정: 명령 상성(돌격 > 측면 > 방어 > 돌격), 진형, 장수 특기, 같은 명령 연속 사용 감점, 전장의 변수(±10%)
- 진형은 한 명령을 강화하고, 그 명령을 이기는 명령을 약화합니다 (학익진: 측면↑ 돌격↓, 어린진: 돌격↑ 방어↓, 방원진: 방어↑ 측면↓)
- 적은 지난 문파전에서 본 아군 명령을 기억해 다음 전투에서 일정 확률로 맞받아칩니다
- 장수: 유대 50 이상인 사제·혈맹 인물이 참전할 수 있습니다 (상대 세력 소속 제외)
- `war_tactics`·`war_formation`을 바꾸면 스모크 테스트의 문파전 밸런스 검사(고정 조합 승률 60% 이하)로 확인합니다
- 문파전에서 이기면 적 문파의 제자·명성·태도가 줄고, 제자가 5명 이하가 되면 **굴복**합니다.
  굴복하면 스토리 플래그 `subjugated_<문파 id>`가 켜지고 더 이상 공격할 수 없습니다.
- 굴복하지 않은 세력은 해마다 제자가 2명씩 늘어납니다.
- 기연에서는 `world_sect` 조건·효과로 강호 세력의 태도·명성·제자 수를 다룰 수 있습니다.
  (`docs/기연_데이터_형식.md` 참고)
