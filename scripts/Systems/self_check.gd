class_name SelfCheck
extends RefCounted

## 내보낸 빌드 자체 점검: 데이터 JSON·무공·그림·소리·글꼴이 패키지 안에서 제대로 읽히는지 본다.
## 실행: <게임 실행 파일> --headless -- --self-check   (모두 통과하면 종료 코드 0, 아니면 1)
## 내보낼 때 *.json이 빠지거나 .remap 처리가 어긋나면 여기서 잡힌다.

const ARG := "--self-check"

## 항목 이름 → 최소 개수. 데이터가 늘면 그대로 두어도 되고, 줄면 실패한다.
const MINIMUMS: Dictionary = {
	"기연": 50,
	"인물": 15,
	"문파": 4,
	"데이터 전투": 10,
	"엔딩": 10,
	"시나리오": 3,
	"무공": 3,
}


## 명령줄에 --self-check가 있는지
static func requested() -> bool:
	return ARG in OS.get_cmdline_user_args() or ARG in OS.get_cmdline_args()


## 점검을 돌려 {ok, lines}를 돌려준다.
static func run() -> Dictionary:
	var lines: PackedStringArray = []
	var ok: bool = true
	var counts: Dictionary = {
		"기연": EventManager.get_definitions().size(),
		"인물": NpcRoster.get_all().size(),
		"문파": ["qingyun", "namgung", "heukpung", "cheonma"].filter(func(id: String) -> bool: return SectRegistry.has_sect(id)).size(),
		"데이터 전투": CombatLibrary.get_ids().size(),
		"엔딩": EndingManager.get_all_endings().size(),
		"시나리오": ScenarioManager.list_scenarios().size(),
		"무공": MartialArtLibrary.get_all().size(),
	}
	for key in MINIMUMS:
		var passed: bool = counts[key] >= MINIMUMS[key]
		ok = ok and passed
		lines.append("%s %s: %d개 (최소 %d)" % ["통과" if passed else "실패", key, counts[key], MINIMUMS[key]])
	var assets: Dictionary = {
		"배경 그림": ArtAssets.background("hub"),
		"지형 타일": ArtAssets.tile("plain"),
		"초상화": ArtAssets.portrait("npc_rival"),
		"문장": ArtAssets.emblem("qingyun"),
		"본문 글꼴": ArtAssets.body_font(),
		"배경음악": load("res://assets/audio/music/hub.ogg") if ResourceLoader.exists("res://assets/audio/music/hub.ogg") else null,
	}
	for key in assets:
		var passed: bool = assets[key] != null
		ok = ok and passed
		lines.append("%s %s" % ["통과" if passed else "실패", key])
	return {"ok": ok, "lines": lines}
