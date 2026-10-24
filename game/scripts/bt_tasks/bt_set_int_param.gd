class_name BTSetIntegerParameter
extends BTGhostTaskBase

func on_update() -> int:
	var param_name: String = str(_get_param_any(["parameter_name", "paramaterName", "parameter"], "AbilityIndex"))
	var int_val: int = int(_get_param_any(["int_value", "intValue", "value"], 0))

	_set_bb(param_name, int_val)

	var actor = _get_actor()
	if actor != null:
		if actor.has_method("set_parameter"):
			actor.set_parameter(param_name, int_val)
		elif param_name == "AbilityIndex" and actor.has_method("set_ability_index"):
			actor.set_ability_index(int_val)
		elif param_name == "AbilityIntData" and actor.has_method("set_ability_int_data"):
			actor.set_ability_int_data(int_val)

	return BTStatus.SUCCESS
