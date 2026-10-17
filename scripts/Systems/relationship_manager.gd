class_name RelationshipManager
extends RefCounted

## 새 게임 시작 관계. NPC 명부에서 initial_bond가 있는 인물로 만든다.
static func create_default_relationships() -> Array[RelationshipData]:
	var relationships: Array[RelationshipData] = []
	for npc in NpcRoster.get_all():
		var bond: Dictionary = npc.get("initial_bond", {})
		if bond.is_empty():
			continue
		var rel := RelationshipData.new()
		rel.target_id = npc["id"]
		rel.target_name = npc["display_name"]
		rel.bond_type = RelationshipData.BondType.get(bond["type"])
		rel.bond_strength = int(bond.get("strength", 0))
		rel.stage = int(bond.get("stage", 0))
		relationships.append(rel)
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