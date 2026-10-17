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
}

@export var target_id: String = ""
@export var target_name: String = ""
@export var bond_type: BondType = BondType.MASTER_DISCIPLE
@export var bond_strength: int = 0
@export var stage: int = 0


func get_bond_name() -> String:
	match bond_type:
		BondType.MASTER_DISCIPLE:
			return "사제"
		BondType.ROMANCE:
			return "연애"
		BondType.BLOOD_OATH:
			return "혈맹"
		BondType.RIVALRY:
			return "라이벌"
		BondType.HATRED:
			return "원한"
		BondType.ACQUAINTANCE:
			return "지인"
		_:
			return "관계"


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
		BondType.MASTER_DISCIPLE, BondType.BLOOD_OATH:
			return 1.0 + bond_strength * 0.002
		BondType.HATRED:
			return 1.0 + bond_strength * 0.003
		BondType.RIVALRY:
			return 1.0 + bond_strength * 0.001
		_:
			return 1.0


func get_combat_defense_modifier() -> float:
	if bond_type in [BondType.MASTER_DISCIPLE, BondType.BLOOD_OATH, BondType.ROMANCE]:
		return 1.0 + bond_strength * 0.001
	return 1.0