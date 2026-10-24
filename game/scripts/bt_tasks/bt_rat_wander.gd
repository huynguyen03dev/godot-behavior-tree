class_name BTRatWander
extends BTRatTaskBase

var current_destination: Vector3 = Vector3.ZERO
var has_destination: bool = false
var pause_timer: float = 0.0
var is_pausing: bool = false

func on_start() -> void:
	if _is_actor_disabled():
		has_destination = false
		return

	var actor := _get_actor()
	if actor == null:
		return

	var min_dist: float = float(_get_param_any(["minWanderDistance", "min_wander_distance"], 1.0))
	var max_dist: float = float(_get_param_any(["maxWanderDistance", "max_wander_distance"], 3.0))

	if actor.has_method("get_random_navmesh_point"):
		current_destination = actor.get_random_navmesh_point(min_dist, max_dist)
	else:
		var r_pos := get_node_pos(actor)
		var angle := randf() * TAU
		var d := randf_range(min_dist, max_dist)
		current_destination = r_pos + Vector3(cos(angle) * d, 0.0, sin(angle) * d)

	has_destination = true
	_set_bb("WanderDestination", current_destination)

func on_update() -> int:
	if _is_actor_disabled():
		return BTStatus.RUNNING

	var actor := _get_actor()
	if actor == null:
		return BTStatus.FAILURE

	if is_pausing:
		pause_timer -= _get_delta()
		if pause_timer <= 0.0:
			is_pausing = false
			on_start()
		return BTStatus.RUNNING

	if not has_destination:
		on_start()
		if not has_destination:
			return BTStatus.RUNNING

	var arrive_dist: float = float(_get_param_any(["arriveDistance", "arrive_distance"], 0.4))
	var wander_speed: float = float(_get_bb("WanderSpeed", _get_param_any(["speed"], 1.0)))

	if actor.has_method("move_towards_point"):
		actor.move_towards_point(current_destination, wander_speed)

	var cur_pos := get_node_pos(actor)
	var dist := cur_pos.distance_to(current_destination)
	if dist <= arrive_dist:
		var p_min: float = float(_get_param_any(["minPauseDuration", "idleMin"], 0.0))
		var p_max: float = float(_get_param_any(["maxPauseDuration", "idleMax"], 0.0))
		if p_max > 0.0 and p_max >= p_min:
			is_pausing = true
			pause_timer = randf_range(p_min, p_max)
		else:
			on_start()

	return BTStatus.RUNNING

func on_end() -> void:
	has_destination = false
	is_pausing = false
