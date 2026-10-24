class_name BTSetSharedBool
extends BTGhostTaskBase

func on_update() -> int:
	var var_name: String = str(_get_param_any(["variable_name", "targetVariable", "variable"], ""))
	var val = _get_param_any(["value", "targetValue"], false)
	var bool_val: bool = bool(val)

	if var_name.is_empty():
		# In some BD nodes, targetVariable is false/true boolean literal or variable name string
		# If targetVariable was serialized as a boolean or name:
		if val is String:
			var_name = val
			bool_val = false

	if not var_name.is_empty():
		_set_bb(var_name, bool_val)

	return BTStatus.SUCCESS

class CompareSharedBool extends BTGhostTaskBase:
	func on_update() -> int:
		var var_name: String = str(_get_param_any(["variable_name", "variable"], ""))
		var compare_to = bool(_get_param_any(["compare_to", "compareTo"], false))

		var actual_val: bool = false
		if not var_name.is_empty():
			actual_val = bool(_get_bb(var_name, false))

		return BTStatus.SUCCESS if actual_val == compare_to else BTStatus.FAILURE

	func evaluate_condition(_runner) -> int:
		return on_update()
