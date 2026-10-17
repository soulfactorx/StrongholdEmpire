class_name DialogueLines
extends RefCounted

## 인물과 주고받는 대사. 인연(대화·선물·비무), 외교, 역할 행동에서 오간 말을 만들어 기록에 남긴다.
## 인물 JSON의 "dialogue"에 그 인물만의 대사가 있으면 먼저 쓰고, 없으면 관계 유형·깊이에 맞는 기본 대사를 쓴다.
## 대사 한 줄은 "말한 사람: 대사" 형식의 문자열이다.

## 인물 JSON "dialogue"에 쓸 수 있는 키
const NPC_KEYS: PackedStringArray = ["talk", "gift", "spar", "hatred"]

const PLAYER_LINES: Dictionary = {
	"talk": {
		"MASTER_DISCIPLE": ["사부님, 오늘도 가르침을 청합니다.", "요즘 검이 무겁게 느껴집니다. 무엇이 부족한 걸까요?", "차 한 잔 올리겠습니다. 잠시 말씀 나누시지요."],
		"ROMANCE": ["달이 밝아 그대 생각이 났소.", "잠시 함께 걸어도 되겠소?"],
		"BLOOD_OATH": ["형제, 요즘 강호 사정은 어떻소?", "한잔하세. 오늘은 내가 사지."],
		"RIVALRY": ["요즘 수련은 잘되시오? 다음엔 지지 않을 것이오.", "그대의 검을 보면 나도 게을러질 수가 없소."],
		"HATRED": ["지난 일은... 이제 그만 묻어 두면 안 되겠소?", "칼 대신 말로 풀어 봅시다."],
		"ACQUAINTANCE": ["안녕하시오. 지나는 길에 들렀소.", "강호에 무슨 소식이 있소?"],
	},
	"gift": {
		"_": ["약소하지만 받아 주시오.", "그대를 생각하며 고른 것이오.", "먼 길에서 구해 온 물건이오. 쓸모가 있을 것이오."],
		"HATRED": ["사죄의 뜻이오. 받아 주시오."],
	},
	"spar": {
		"_": ["한 수 겨뤄 보시겠소?", "검을 맞대 보면 서로를 더 잘 알게 될 것이오."],
	},
}

## 관계 유형별 기본 답 (유대가 낮을 때 / 높을 때)
const REPLY_LINES: Dictionary = {
	"talk": {
		"MASTER_DISCIPLE": [["검은 손이 아니라 마음으로 쥐는 것이다. 서두르지 마라.", "기본을 소홀히 하지 마라."], ["네가 이만큼 자랐구나. 이제는 내가 배울 것도 있겠다.", "네 검에 흔들림이 없어졌구나. 기특하다."]],
		"ROMANCE": [["...바쁜 분이 웬일이세요?", "갑자기 찾아오시면 곤란해요."], ["기다리고 있었어요.", "당신과 걷는 길이라면 어디든 좋아요."]],
		"BLOOD_OATH": [["강호가 뒤숭숭하네. 몸조심하게.", "술은 좋지. 이야기는 천천히 하세."], ["자네가 있어 든든하네. 무슨 일이든 말만 하게.", "우리 사이에 무슨 사양인가."]],
		"RIVALRY": [["흥, 말보다 검으로 보여 주시오.", "다음에도 내가 이길 것이오."], ["그대만 한 맞수는 강호에 드물지.", "그대 덕에 나도 한 걸음 더 나아갔소."]],
		"HATRED": [["할 말이 있으면 검으로 하시오.", "그 얼굴을 보니 옛 원한이 되살아나는군."], ["...그 말, 한 번은 믿어 보겠소.", "원한이 쉽게 사라지진 않겠지만, 듣고는 있겠소."]],
		"ACQUAINTANCE": [["아, 또 뵙는군요.", "별일 없소. 그쪽은 어떻소?"], ["반갑소! 마침 이야기 상대가 필요했소.", "그대와 이야기하면 마음이 편해지는구려."]],
	},
	"gift": {
		"_": [["이런 걸 다... 고맙소.", "받아 두겠소."], ["그대의 마음이 느껴지는구려. 소중히 쓰겠소.", "이렇게까지 챙겨 주다니, 이 은혜 잊지 않겠소."]],
		"HATRED": [["...물건으로 원한이 풀릴 것 같소?", "받기는 하겠소. 그뿐이오."], ["...그대 마음은 알겠소.", "이것으로 조금은 누그러지는군."]],
	},
	"spar": {
		"_": [["좋소. 사정 봐주지 않겠소.", "검으로 이야기합시다."], ["기다리던 바요! 전력을 다하겠소.", "그대와의 비무라면 언제든 환영이오."]],
	},
}

## 외교: 우리 쪽 사절의 말, 상대 문주의 답 (성공 / 실패)
const DIPLOMACY_LINES: Dictionary = {
	"envoy": ["%s께 문안 올립니다. 예물을 받아 주십시오.", ["먼 길 오셨소. 귀파의 뜻은 잘 알겠소.", "예를 갖추어 주니 고맙소."], ["예물은 받겠으나 마음까지 열리진 않소."]],
	"alliance": ["두 문파가 손을 잡으면 강호의 풍파도 두렵지 않을 것입니다.", ["좋소. 오늘부터 귀파와 우리는 한 배를 탄 것이오."], ["아직은 때가 아니오."]],
	"break_alliance": ["이제 각자의 길을 가야 할 때입니다.", ["...그렇다면 할 수 없지. 다음에 만날 땐 적일지도 모르오."], ["말이 지나치시오."]],
	"marriage": ["두 집안이 사돈을 맺어 영원히 함께하기를 청합니다.", ["경사로다! 좋은 인연이 되길 바라오."], ["혼사는 가벼이 정할 일이 아니오."]],
	"challenge": ["우리 문주께서 정식으로 도전장을 보내셨습니다.", ["감히! 좋소, 받아 주지."], ["하찮은 도전에 응할 생각 없소."]],
	"tribute": ["우리 문파에 굴복한 이상, 예를 다해 공물을 바치시오.", ["...알겠소. 해마다 바치겠소."], ["누구 앞에서 공물을 논하는가!"]],
	"release_tribute": ["이제 공물은 바치지 않아도 됩니다.", ["관대한 처분에 감사하오. 이 은혜 잊지 않겠소."], ["...무슨 꿍꿍이요?"]],
}

## 역할 행동에서 오가는 말: [플레이어 대사, 상대 이름(빈칸이면 없음), 상대 답(성공), 상대 답(실패)]
const ROLE_ACTION_LINES: Dictionary = {
	"council": ["모두 기탄없이 말해 보시오. 문파를 위해 무엇이 필요하오?", "원로", "문주께서 귀를 열어 주시니 다들 한결 마음이 놓였습니다.", ""],
	"proposal": ["문주님, 문파 운영에 대해 한 말씀 올리겠습니다.", "문주", "좋은 생각이다. 그대로 시행하라.", "쓸데없는 소리. 물러가라."],
	"teaching": ["사부님, 가르침을 청합니다.", "사부", "잘 보아라. 이 한 수에 검의 이치가 담겼다.", "오늘은 마음이 흐트러져 있구나. 다음에 오너라."],
	"contract": ["그 일, 제가 맡겠습니다. 선금부터 주시지요.", "의뢰주", "좋소. 실수 없이 처리해 주시오.", ""],
	"fulfill": ["맡은 일은 끝냈습니다. 잔금을 주시지요.", "의뢰주", "깔끔하군. 다음에도 부탁하겠소.", "이걸 일이라고 해 왔소?"],
	"breach": ["미안하게 됐소. 더 좋은 값을 부른 쪽이 있어서.", "의뢰주", "", "이 배신, 강호에 다 알리겠다!"],
}


## 인연 상호작용(대화·선물·비무 신청)에서 오간 대사
static func for_interaction(rel: RelationshipData, kind: String, player_name: String, success: bool) -> PackedStringArray:
	var lines: PackedStringArray = []
	if not success:
		return lines
	var type_name: String = RelationshipData.BondType.keys()[rel.bond_type]
	var hatred: bool = rel.bond_type == RelationshipData.BondType.HATRED
	lines.append("%s: %s" % [player_name, _pick(_player_pool(kind, type_name))])
	var npc_lines: Dictionary = NpcRoster.get_npc(rel.target_id).get("dialogue", {})
	var own_key: String = "hatred" if hatred else kind
	var reply: String
	if npc_lines.get(own_key, []) is Array and not npc_lines.get(own_key, []).is_empty():
		reply = _pick(npc_lines[own_key])
	else:
		reply = _pick(_reply_pool(kind, type_name, rel.bond_strength >= 50 if not hatred else rel.bond_strength < 40))
	lines.append("%s: %s" % [rel.target_name, reply])
	return lines


static func _player_pool(kind: String, type_name: String) -> Array:
	var table: Dictionary = PLAYER_LINES.get(kind, {})
	return table.get(type_name, table.get("_", table.get("ACQUAINTANCE", ["..."])))


static func _reply_pool(kind: String, type_name: String, warm: bool) -> Array:
	var table: Dictionary = REPLY_LINES.get(kind, {})
	var pair: Array = table.get(type_name, table.get("_", table.get("ACQUAINTANCE", [["..."], ["..."]])))
	return pair[1 if warm else 0]


## 외교 사절과 상대 문주의 대사
static func for_diplomacy(sect: SectData, action_id: String, success: bool) -> PackedStringArray:
	var lines: PackedStringArray = []
	if sect == null or not DIPLOMACY_LINES.has(action_id):
		return lines
	var entry: Array = DIPLOMACY_LINES[action_id]
	var opening: String = entry[0]
	if opening.contains("%s"):
		opening = opening % sect.leader_name
	lines.append("우리 사절: %s" % opening)
	lines.append("%s: %s" % [sect.leader_name, _pick(entry[1] if success else entry[2])])
	return lines


## 역할 행동에서 오간 대사 (해당 없으면 빈 목록)
static func for_role_action(action_id: String, player_name: String, success: bool, counterpart: String = "") -> PackedStringArray:
	var lines: PackedStringArray = []
	if not ROLE_ACTION_LINES.has(action_id):
		return lines
	var entry: Array = ROLE_ACTION_LINES[action_id]
	lines.append("%s: %s" % [player_name, entry[0]])
	var reply: String = entry[2] if success else entry[3]
	if not reply.is_empty():
		lines.append("%s: %s" % [counterpart if not counterpart.is_empty() else entry[1], reply])
	return lines


## 인물 JSON의 dialogue 검사 (오류 문구 목록)
static func validate(dialogue: Variant) -> PackedStringArray:
	var errors: PackedStringArray = []
	if not dialogue is Dictionary:
		errors.append("dialogue는 객체여야 함")
		return errors
	for key in dialogue:
		if not key in NPC_KEYS:
			errors.append("알 수 없는 대사 종류: %s" % key)
		elif not dialogue[key] is Array or dialogue[key].any(func(line: Variant) -> bool: return not line is String):
			errors.append("대사 %s는 문자열 배열이어야 함" % key)
	return errors


static func _pick(pool: Array) -> String:
	if pool.is_empty():
		return "..."
	return str(pool[randi() % pool.size()])
