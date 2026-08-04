class_name LegacyManager
extends RefCounted

const _Balance = preload("res://scripts/Systems/game_balance.gd")

const SUCCESSOR_NAMES: PackedStringArray = [
	"이청운", "소련심", "백무진", "남궁설", "고운하",
]


static func can_retire(character: CharacterData) -> bool:
	return character.age >= _Balance.RETIRE_AGE or character.level >= _Balance.RETIRE_LEVEL


static func create_legacy_record(
	character: CharacterData,
	sect: SectData,
	generation: int,
	ending_id: String = ""
) -> LegacyData:
	var legacy := LegacyData.new()
	legacy.predecessor_name = character.display_name
	legacy.predecessor_role = character.role
	legacy.generation = generation
	legacy.final_reputation = sect.reputation
	legacy.legacy_points = _calculate_legacy_points(character, sect)
	legacy.ending_reached = ending_id

	for art in character.martial_arts:
		legacy.martial_art_names.append(art.display_name)

	legacy.summary = "%s세대 %s — %s로 강호를 떠났습니다." % [
		generation,
		character.display_name,
		character.get_role_name(),
	]
	return legacy


static func create_successor(
	legacy: LegacyData,
	sect: SectData
) -> CharacterData:
	var character := CharacterData.new()
	var gen: int = legacy.generation + 1
	character.id = "player_gen_%d" % gen
	character.display_name = SUCCESSOR_NAMES[gen % SUCCESSOR_NAMES.size()]
	character.role = CharacterData.Role.YOUNG_DISCIPLE
	character.age = 16
	character.level = 1
	character.strength = 10 + legacy.legacy_points / 10
	character.agility = 10 + legacy.legacy_points / 12
	character.wisdom = 12 + legacy.legacy_points / 8
	character.charisma = 10 + legacy.legacy_points / 15
	character.internal_energy_max = 100 + legacy.legacy_points
	character.internal_energy_current = character.internal_energy_max
	character.morality = 55
	character.experience = legacy.legacy_points / 2
	return character


static func apply_legacy_bonuses(sect: SectData, legacy: LegacyData) -> void:
	sect.reputation += legacy.legacy_points / 5
	sect.research_points += legacy.legacy_points / 3


static func _calculate_legacy_points(character: CharacterData, sect: SectData) -> int:
	var points: int = character.level * 5
	points += sect.reputation / 2
	points += character.martial_arts.size() * 8
	points += character.experience / 5
	return points