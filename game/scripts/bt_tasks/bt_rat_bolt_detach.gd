class_name BTRatBoltDetach
extends BTRatTaskBase

func on_update() -> int:
	var target_var = _get_param_any(["targetGameObject"], "$Hay")
	var target = _get_bb(str(target_var))
	if target is Node:
		target.queue_free()
	_set_bb(str(target_var), null)
	return BTStatus.SUCCESS
