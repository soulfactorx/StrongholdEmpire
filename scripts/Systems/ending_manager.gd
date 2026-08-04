class_name EndingManager
extends RefCounted

const _Balance = preload("res://scripts/Systems/game_balance.gd")

const ENDINGS: Dictionary = {
	"unify_righteous": {
		"title": "정파 통일",
		"description": "문주로서 청운검파를 이끌고 강호에 새 질서를 세웠습니다.\n정파가 연합하여 천하대란을 막을 수 있었습니다.",
	},
	"shadow_empire": {
		"title": "그림자 제패",
		"description": "암살과 음모로 강호를 장악했습니다.\n아무도 당신의 이름을 모르지만, 모두가 당신을 두려워합니다.",
	},
	"wanderer_legend": {
		"title": "낭인 전설",
		"description": "문파와 굴레를 벗어나 자유롭게 강호를 누볐습니다.\n당신의 이름은 전설이 되어 후대에 전해집니다.",
	},
	"tragic_execution": {
		"title": "비극적 처형",
		"description": "스파이 신분이 드러나 적문파에 체포되었습니다.\n이청풍의 이야기는 비극으로 끝났습니다.",
	},
	"new_sect_founder": {
		"title": "신파 창설",
		"description": "이중 스파이로 살아남아 새로운 문파를 세웠습니다.\n강호에 또 하나의 세력이 탄생했습니다.",
	},
}


static func check_endings(
	character: CharacterData,
	sect: SectData,
	story_flags: Dictionary
) -> String:
	if story_flags.get("spy_exposed", false):
		return "tragic_execution"

	if (
		character.role == CharacterData.Role.LEADER
		and sect.reputation >= _Balance.ENDING_REPUTATION_UNIFY
		and character.morality >= _Balance.ENDING_MORALITY_UNIFY
	):
		return "unify_righteous"

	if (
		character.role in [CharacterData.Role.ASSASSIN, CharacterData.Role.SPY]
		and character.morality <= _Balance.ENDING_MORALITY_SHADOW
		and sect.reputation >= _Balance.ENDING_REPUTATION_SHADOW
		and story_flags.get("assassin_path", false)
	):
		return "shadow_empire"

	if (
		character.role == CharacterData.Role.WANDERER
		and character.martial_arts.size() >= _Balance.ENDING_WANDERER_ARTS
		and character.level >= _Balance.ENDING_WANDERER_LEVEL
	):
		return "wanderer_legend"

	if (
		story_flags.get("spy_mission_complete", false)
		and character.role == CharacterData.Role.MANAGER
		and sect.reputation >= 85
	):
		return "new_sect_founder"

	return ""


static func get_ending(ending_id: String) -> Dictionary:
	if ENDINGS.has(ending_id):
		return ENDINGS[ending_id]
	return {"title": "미완의 서사", "description": "이야기가 아직 끝나지 않았습니다."}