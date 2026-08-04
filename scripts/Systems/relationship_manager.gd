class_name RelationshipManager
extends RefCounted

static func create_default_relationships() -> Array[RelationshipData]:
	var relationships: Array[RelationshipData] = []

	var master := RelationshipData.new()
	master.target_id = "npc_master"
	master.target_name = "청운검선"
	master.bond_type = RelationshipData.BondType.MASTER_DISCIPLE
	master.bond_strength = 35
	master.stage = 1
	relationships.append(master)

	var rival := RelationshipData.new()
	rival.target_id = "npc_rival"
	rival.target_name = "남궁휘"
	rival.bond_type = RelationshipData.BondType.RIVALRY
	rival.bond_strength = 15
	rival.stage = 0
	relationships.append(rival)

	return relationships


static func get_bond_with(
	relationships: Array[RelationshipData],
	target_id: String
) -> RelationshipData:
	for rel in relationships:
		if rel.target_id == target_id:
			return rel
	return null


static func get_combat_damage_bonus(
	relationships: Array[RelationshipData],
	target_id: String
) -> float:
	var rel := get_bond_with(relationships, target_id)
	if rel == null:
		return 1.0
	return rel.get_combat_damage_modifier()


static func get_ally_buff_multiplier(relationships: Array[RelationshipData]) -> float:
	var multiplier := 1.0
	for rel in relationships:
		if rel.bond_type in [
			RelationshipData.BondType.MASTER_DISCIPLE,
			RelationshipData.BondType.BLOOD_OATH,
		]:
			multiplier += rel.bond_strength * 0.001
	return multiplier


static func format_relationships(relationships: Array[RelationshipData]) -> String:
	if relationships.is_empty():
		return "관계 없음"
	var lines: PackedStringArray = []
	for rel in relationships:
		lines.append(
			"%s (%s Lv.%d, %d)" % [
				rel.target_name,
				rel.get_bond_name(),
				rel.stage,
				rel.bond_strength,
			]
		)
	return "\n".join(lines)