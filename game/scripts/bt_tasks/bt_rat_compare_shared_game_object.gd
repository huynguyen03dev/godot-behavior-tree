class_name BTRatCompareSharedGameObject
extends BTRatTaskBase

func on_update() -> int:
	var var_name: String = str(_get_param_any(["variable"], "$Hay"))
	var obj = _get_bb(var_name, null)
	# BD task "CompareSharedGameObject": if object == null, return SUCCESS
	return BTStatus.SUCCESS if obj == null else BTStatus.FAILURE

func evaluate_condition(_runner) -> int:
	return on_update()
