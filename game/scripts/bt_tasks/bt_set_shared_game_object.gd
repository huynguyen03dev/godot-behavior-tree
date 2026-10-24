class_name BTSetSharedGameObject
extends BTGhostTaskBase

func on_update() -> int:
	var target_var: String = str(_get_param_any(["target_variable", "targetVariable"], "PlayerToChase"))
	var source_var = _get_param_any(["source_variable", "targetValue"], null)
	var value_can_be_null: bool = bool(_get_param_any(["value_can_be_null", "valueCanBeNull"], false))

	var val = null
	if source_var != null:
		var s_str = str(source_var)
		if s_str.begins_with("$") or s_str.begins_with("@"):
			val = _get_bb(s_str)
		elif source_var is Object:
			val = source_var

	if val != null or value_can_be_null:
		_set_bb(target_var, val)

	return BTStatus.SUCCESS
