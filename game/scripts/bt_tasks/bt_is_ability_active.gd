class_name BTIsAbilityActive
extends BTGhostTaskBase

func on_update() -> int:
	var target_var = _get_param_any(["target_game_object", "TargetGameObject"], "$PlayerToChase")
	var ability_type: String = str(_get_param_any(["ability_type", "AbilityType"], "Crawl"))

	var target = _get_bb(str(target_var))
	var actor = _get_actor()
	if target == null and actor != null and actor.has_method("_get_player"):
		target = actor._get_player()

	if target == null:
		return BTStatus.FAILURE

	if ability_type == "Crawl":
		if "is_crawling" in target and bool(target.is_crawling):
			return BTStatus.SUCCESS
		if "is_crouching" in target and bool(target.is_crouching):
			return BTStatus.SUCCESS

	return BTStatus.FAILURE

func evaluate_condition(_runner) -> int:
	return on_update()
