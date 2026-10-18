class_name RelationshipData
extends Resource

enum BondType {
	MASTER_DISCIPLE,
	ROMANCE,
	BLOOD_OATH,
	RIVALRY,
	HATRED,
	## 알게 된 인물. 유대가 깊어지면 기연으로 연애·혈맹 등으로 바뀐다
	ACQUAINTANCE,
	## 혼인한 사이. 여러 명과 맺을 수 있다
	SPOUSE,
	## 마음을 터놓는 벗
	FRIEND,
	## 같은 문파의 사형제
	FELLOW,
	## 내가 가르치는 제자
	PUPIL,
	## 나를 도와준 은인
	BENEFACTOR,
	## 혼인으로 맺어진 사돈·처가
	IN_LAW,
}

## 관계 유형 이름 (화면·새 게임 설정에 쓴다)
const TYPE_NAMES: Dictionary = {
	BondType.MASTER_DISCIPLE: "사부",
	BondType.ROMANCE: "연인",
	BondType.BLOOD_OATH: "혈맹",
	BondType.RIVALRY: "라이벌",
	BondType.HATRED: "원한",
	BondType.ACQUAINTANCE: "지인",
	BondType.SPOUSE: "배우자",
	BondType.FRIEND: "벗",
	BondType.FELLOW: "동문",
	BondType.PUPIL: "제자",
	BondType.BENEFACTOR: "은인",
	BondType.IN_LAW: "인척",
}

@export var target_id: String = ""
@export var target_name: String = ""
@export var bond_type: BondType = BondType.MASTER_DISCIPLE
@export var bond_strength: int = 0
@export var stage: int = 0


func get_bond_name() -> String:
	return TYPE_NAMES.get(bond_type, "관계")


## 관계 유형 이름 ("SPOUSE" 같은 키로)
static func type_name_of(key: String) -> String:
	return TYPE_NAMES.get(BondType.get(key, -1), key)


func get_stage_name() -> String:
	if bond_strength < 20:
		return "낯선 사이"
	if bond_strength < 40:
		return "알게 된 사이"
	if bond_strength < 60:
		return "신뢰"
	if bond_strength < 80:
		return "깊은 유대"
	return "운명적 인연"


func increase_bond(amount: int) -> void:
	bond_strength = clampi(bond_strength + amount, 0, 100)
	_update_stage()


func decrease_bond(amount: int) -> void:
	increase_bond(-amount)


func _update_stage() -> void:
	stage = bond_strength / 20


func get_combat_damage_modifier() -> float:
	match bond_type:
		BondType.MASTER_DISCIPLE, BondType.BLOOD_OATH, BondType.SPOUSE, BondType.PUPIL:
			return 1.0 + bond_strength * 0.002
		BondType.FRIEND, BondType.FELLOW:
			return 1.0 + bond_strength * 0.001
		BondType.HATRED:
			return 1.0 + bond_strength * 0.003
		BondType.RIVALRY:
			return 1.0 + bond_strength * 0.001
		_:
			return 1.0


func get_combat_defense_modifier() -> float:
	if bond_type in [BondType.MASTER_DISCIPLE, BondType.BLOOD_OATH, BondType.ROMANCE, BondType.SPOUSE, BondType.PUPIL, BondType.FRIEND]:
		return 1.0 + bond_strength * 0.001
	return 1.0