class_name BTRatFlee
extends BTRatTaskBase

var current_flee_dest: Vector3 = Vector3.ZERO
var has_flee_dest: bool = false
var repath_timer: float = 0.0

func on_start() -> void:
	repath_timer = 0.0
	has_flee_dest = false
	_compute_flee_point()

func _compute_flee_point() -> void:
	if _is_actor_disabled():
		return

	var actor := _get_actor()
	if actor == null:
		return

	var target_var = _get_param_any(["target"], "$PlayerWithinDistance")
	var threat = null
	if str(target_var).begins_with("$"):
		threat = _get_bb(str(target_var))
	elif target_var is Object:
		threat = target_var

	if threat == null and actor.has_method("get_player"):
		threat = actor.get_player()

	var flee_dist: float = float(_get_bb("FleeDistance", _get_param_any(["fleedDistance", "fleeDistance"], 5.0)))

	if actor.has_method("flee_from") and threat is Node3D:
		current_flee_dest = actor.flee_from(threat)
		has_flee_dest = true
	elif threat is Node3D:
		var threat_pos = get_node_pos(threat)
		var rat_pos = get_node_pos(actor)
		var dir = (rat_pos - threat_pos).normalized()
		if dir.length_squared() < 0.001:
			dir = Vector3.FORWARD
		dir.y = 0.0
		current_flee_dest = rat_pos + dir * flee_dist
		has_flee_dest = true
	else:
		if actor.has_method("get_random_navmesh_point"):
			current_flee_dest = actor.get_random_navmesh_point(flee_dist * 0.5, flee_dist)
			has_flee_dest = true

	if has_flee_dest and actor.has_method("play_squeak"):
		actor.play_squeak()

func on_update() -> int:
	if _is_actor_disabled():
		return BTStatus.RUNNING

	var actor := _get_actor()
	if actor == null:
		return BTStatus.FAILURE

	repath_timer += _get_delta()
	if repath_timer >= 0.5 or not has_flee_dest:
		repath_timer = 0.0
		_compute_flee_point()

	var arrive_dist: float = float(_get_param_any(["arriveDistance", "arrive_distance"], 0.2))
	var flee_speed: float = float(_get_bb("FleeSpeed", _get_param_any(["speed"], 3.2)))

	if actor.has_method("move_towards_point"):
		actor.move_towards_point(current_flee_dest, flee_speed)

	var cur_pos := get_node_pos(actor)
	if cur_pos.distance_to(current_flee_dest) <= arrive_dist:
		return BTStatus.SUCCESS

	return BTStatus.RUNNING

func on_end() -> void:
	has_flee_dest = false
