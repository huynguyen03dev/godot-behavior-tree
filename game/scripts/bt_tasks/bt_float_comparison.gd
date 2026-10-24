class_name BTFloatComparison
extends BTGhostTaskBase

func on_update() -> int:
	var op: String = str(_get_param_any(["operation", "Operationoperation"], "LessThanOrEqualTo"))
	var raw_val1 = _get_param_any(["val1", "float1"], 0.0)
	var raw_val2 = _get_param_any(["val2", "float2"], 0.0)

	var v1: float = _resolve_float(raw_val1)
	var v2: float = _resolve_float(raw_val2)

	var result: bool = false
	match op:
		"LessThan":
			result = v1 < v2
		"LessThanOrEqualTo":
			result = v1 <= v2
		"EqualTo":
			result = is_equal_approx(v1, v2)
		"NotEqualTo":
			result = not is_equal_approx(v1, v2)
		"GreaterThan":
			result = v1 > v2
		"GreaterThanOrEqualTo":
			result = v1 >= v2
		_:
			result = v1 <= v2

	return BTStatus.SUCCESS if result else BTStatus.FAILURE

func _resolve_float(raw) -> float:
	if raw is float or raw is int:
		return float(raw)
	var s = str(raw)
	if s.begins_with("$") or s.begins_with("@"):
		var bb_val = _get_bb(s, 0.0)
		return float(bb_val)
	return float(s)

func evaluate_condition(_runner) -> int:
	return on_update()
