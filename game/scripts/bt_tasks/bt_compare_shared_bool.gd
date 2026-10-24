class_name BTCompareSharedBool
extends BTGhostTaskBase

func on_update() -> int:
	var var_name: String = str(_get_param_any(["variable_name", "variable"], ""))
	var compare_to = bool(_get_param_any(["compare_to", "compareTo"], false))

	var actual_val: bool = false
	if not var_name.is_empty():
		actual_val = bool(_get_bb(var_name, false))

	return BTStatus.SUCCESS if actual_val == compare_to else BTStatus.FAILURE

func evaluate_condition(_runner) -> int:
	return on_update()
