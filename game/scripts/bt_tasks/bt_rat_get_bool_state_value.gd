class_name BTRatGetBoolStateValue
extends BTRatTaskBase

func on_update() -> int:
	var state_name: String = str(_get_param_any(["stateName", "state_name"], "DroppedByPlayer"))
	var entity_var = _get_param_any(["entityObject"], "$Hay")
	var entity = _get_bb(str(entity_var))

	var val: bool = false
	if entity is Object and entity.has_method("get_shared_bool"):
		val = bool(entity.get_shared_bool(state_name))
	elif entity is Object and state_name in entity:
		val = bool(entity.get(state_name))
	else:
		val = bool(_get_bb(state_name, false))

	_set_bb(state_name, val)
	return BTStatus.SUCCESS
