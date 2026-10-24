class_name BTGhostMoveTowards
extends BTGhostTaskBase

var destination_pos: Vector3 = Vector3.ZERO
var target_resolved: bool = false

func on_start() -> void:
	target_resolved = false
	var actor = _get_actor()
	if actor == null:
		return

	var target_var = _get_param_any(["target_variable", "targetPosition", "target"], "$WanderDestination")
	var dest_val = null
	if str(target_var).begins_with("$") or str(target_var).begins_with("@"):
		dest_val = _get_bb(str(target_var))
	else:
		dest_val = target_var

	if dest_val is Vector3:
		destination_pos = dest_val
		target_resolved = true
	elif dest_val is Node3D:
		destination_pos = get_node_pos(dest_val)
		target_resolved = true
	elif dest_val is String and dest_val.begins_with("(") and dest_val.ends_with(")"):
		# e.g. "(0,0,0)"
		var parts = dest_val.strip_edges().trim_prefix("(").trim_suffix(")").split(",")
		if parts.size() == 3:
			destination_pos = Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())
			target_resolved = true

	if target_resolved and actor.has_method("set_nav_target"):
		actor.set_nav_target(destination_pos)

func on_update() -> int:
	var actor = _get_actor()
	if actor == null:
		return BTStatus.FAILURE

	if not target_resolved:
		on_start()
		if not target_resolved:
			return BTStatus.FAILURE

	var speed: float = float(_get_param_any(["speed"], 1.0))
	var bb_speed = _get_bb("Speed")
	if bb_speed != null and float(bb_speed) > 0.0:
		speed = float(bb_speed)

	var arrive_dist: float = float(_get_param_any(["arrive_distance", "arriveDistance"], 0.2))
	var look_at_target: bool = bool(_get_param_any(["look_at_target", "lookAtTarget"], true))
	var delta: float = _get_delta()

	var remaining_dist: float = 999.0
	if actor.has_method("step_navigation"):
		remaining_dist = actor.step_navigation(delta, speed, look_at_target)
	elif actor is Node3D:
		remaining_dist = get_node_pos(actor).distance_to(destination_pos)

	if remaining_dist <= arrive_dist:
		if actor.has_method("stop_navigation"):
			actor.stop_navigation()
		return BTStatus.SUCCESS

	return BTStatus.RUNNING

func on_abort() -> void:
	var actor = _get_actor()
	if actor != null and actor.has_method("stop_navigation"):
		actor.stop_navigation()
