class_name SectManager
extends RefCounted

const _Balance = preload("res://scripts/Systems/game_balance.gd")




static func train_disciples(sect: SectData, character: CharacterData) -> Dictionary:
	if sect.disciple_count >= sect.max_disciples:
		return {"success": false, "message": "제자 정원이 가득 찼습니다."}
	if not sect.spend_resources(_Balance.TRAIN_GOLD, _Balance.TRAIN_FOOD):
		return {"success": false, "message": "자원이 부족합니다. (금화 30, 식량 20 필요)"}

	sect.disciple_count += 1
	character.strength += 1
	character.agility += 1
	character.wisdom += 1
	character.gain_experience(10)
	return {"success": true, "message": "제자 훈련 완료! 문파 전력이 강해졌습니다."}


static func upgrade_library(sect: SectData) -> Dictionary:
	if sect.library_level >= 5:
		return {"success": false, "message": "서고는 이미 최고 수준입니다."}
	if not sect.spend_resources(_Balance.UPGRADE_LIBRARY_GOLD):
		return {"success": false, "message": "금화가 부족합니다. (80 필요)"}

	sect.library_level += 1
	return {"success": true, "message": "서고를 확장했습니다. 연구 효율이 상승합니다."}


static func upgrade_training_ground(sect: SectData) -> Dictionary:
	if sect.training_ground_level >= 5:
		return {"success": false, "message": "무술장은 이미 최고 수준입니다."}
	if not sect.spend_resources(_Balance.UPGRADE_TRAINING_GOLD):
		return {"success": false, "message": "금화가 부족합니다. (60 필요)"}

	sect.training_ground_level += 1
	return {"success": true, "message": "무술장을 확장했습니다. 훈련 효율이 상승합니다."}


static func upgrade_treasury(sect: SectData) -> Dictionary:
	if sect.treasury_level >= 5:
		return {"success": false, "message": "금고는 이미 최고 수준입니다."}
	if not sect.spend_resources(_Balance.UPGRADE_TREASURY_GOLD):
		return {"success": false, "message": "금화가 부족합니다. (70 필요)"}

	sect.treasury_level += 1
	return {"success": true, "message": "금고를 확장했습니다. 계절 수입이 증가합니다."}