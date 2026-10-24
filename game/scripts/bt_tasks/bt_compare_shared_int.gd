class_name BTCompareSharedInt
extends BTGhostTaskBase

func on_update() -> int:
	var var_name: String = str(_get_param_any(["variable_name", "variable"], "AbilityIndex"))
	var compare_to: int = int(_get_param_any(["compare_to", "compareTo"], 0))

	var actual_val: int = int(_get_bb(var_name, 0))
	return BTStatus.SUCCESS if actual_val == compare_to else BTStatus.FAILURE

func evaluate_condition(_runner) -> int:
	return on_update()
