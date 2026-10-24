class_name BTCompareIntegerParameter
extends BTGhostTaskBase

func on_update() -> int:
	var param_name: String = str(_get_param_any(["parameter_name", "paramaterName", "parameter"], "AbilityIndex"))
	var compare_to: int = int(_get_param_any(["compare_to", "compareTo"], 0))
	var anim_obj_key = _get_param_any(["animator_game_object", "animatorGameObject"], null)

	var actual_val: int = 0
	if anim_obj_key != null:
		var target = _get_bb(str(anim_obj_key))
		if target != null and target.has_method("get_ability_index"):
			actual_val = target.get_ability_index()
		elif target != null and "ability_index" in target:
			actual_val = int(target.ability_index)
		else:
			var actor = _get_actor()
			if actor != null and actor.has_method("get_ability_index"):
				actual_val = actor.get_ability_index()
	else:
		var bb_val = _get_bb(param_name)
		if bb_val != null:
			actual_val = int(bb_val)
		else:
			var actor = _get_actor()
			if actor != null and actor.has_method("get_ability_index") and param_name == "AbilityIndex":
				actual_val = actor.get_ability_index()

	if actual_val == compare_to:
		return BTStatus.SUCCESS

	return BTStatus.FAILURE

func evaluate_condition(_runner) -> int:
	return on_update()
