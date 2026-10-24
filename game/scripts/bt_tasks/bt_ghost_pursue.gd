class_name BTGhostPursue
extends BTGhostTaskBase

var default_speeds: Array = [1.25, 1.4, 1.55, 1.7, 1.85, 2.0, 2.15, 2.3, 2.5, 2.5]

func on_update() -> int:
	var actor = _get_actor()
	if actor == null:
		return BTStatus.FAILURE

	var target_var = _get_param_any(["target_variable", "target"], "$PlayerToChase")
	var target = _get_bb(str(target_var))
	if target == null and actor.has_method("_get_player"):
		target = actor._get_player()

	if target == null or not is_instance_valid(target):
		return BTStatus.FAILURE

	var arrive_dist: float = float(_get_param_any(["arrive_distance", "arriveDistance"], 1.0))
	var delta: float = _get_delta()

	# Determine speed: scaled by Altar.burnt_count if speeds list provided
	var speeds = _get_param_any(["FloatListdodgeSpeeds", "dodge_speeds"], default_speeds)
	var speed: float = 1.0
	var burnt_count: int = 0
	var scene_tree = actor.get_tree() if actor.is_inside_tree() else null
	if scene_tree != null:
		var altar = scene_tree.get_first_node_in_group("Altar")
		if altar != null and "burnt_count" in altar:
			burnt_count = int(altar.burnt_count)

	if speeds is Array and not speeds.is_empty():
		var idx = clampi(burnt_count, 0, speeds.size() - 1)
		speed = float(speeds[idx])
	else:
		var bb_speed = _get_bb("Speed")
		if bb_speed != null and float(bb_speed) > 0.0:
			speed = float(bb_speed)

	var target_pos: Vector3 = get_node_pos(target)
	if actor.has_method("step_pursue"):
		actor.step_pursue(target_pos, speed, delta)

	var current_dist: float = 999.0
	if actor.has_method("get_target_distance"):
		current_dist = actor.get_target_distance(target)
	elif actor is Node3D:
		current_dist = get_node_pos(actor).distance_to(target_pos)

	if current_dist <= arrive_dist:
		return BTStatus.SUCCESS

	return BTStatus.RUNNING

func on_abort() -> void:
	var actor = _get_actor()
	if actor != null and actor.has_method("stop_navigation"):
		actor.stop_navigation()
