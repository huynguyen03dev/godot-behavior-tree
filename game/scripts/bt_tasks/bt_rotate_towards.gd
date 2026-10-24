class_name BTRotateTowards
extends BTGhostTaskBase

func on_update() -> int:
	var actor = _get_actor()
	if actor == null:
		return BTStatus.FAILURE

	var target_var = _get_param_any(["target_variable", "target"], "$PlayerToChase")
	var target = _get_bb(str(target_var))
	if target == null and actor.has_method("_get_player"):
		target = actor._get_player()

	if target == null:
		return BTStatus.FAILURE

	var max_delta: float = float(_get_param_any(["max_rotation_delta", "maxLookAtRotationDelta"], 5.0))
	var target_pos: Vector3 = get_node_pos(target)

	var done: bool = true
	if actor.has_method("rotate_towards_point"):
		done = actor.rotate_towards_point(target_pos, max_delta)

	return BTStatus.SUCCESS if done else BTStatus.RUNNING
