class_name BTGetIntegerParameter
extends BTGhostTaskBase

func on_update() -> int:
	var param_name: String = str(_get_param_any(["parameter_name", "paramaterName", "parameter"], "AbilityIndex"))
	var store_var: String = str(_get_param_any(["store_variable", "storeValue"], "AbilityIndex"))

	var val: int = 0
	var actor = _get_actor()
	if actor != null and actor.has_method("get_ability_index") and param_name == "AbilityIndex":
		val = actor.get_ability_index()
	else:
		var bb_val = _get_bb(param_name)
		if bb_val != null:
			val = int(bb_val)

	_set_bb(store_var, val)
	return BTStatus.SUCCESS
