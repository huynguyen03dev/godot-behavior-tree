class_name BTGhostGetWanderDestination
extends BTGhostTaskBase

func on_update() -> int:
	var actor = _get_actor()
	if actor == null:
		return BTStatus.FAILURE

	var min_distance: float = float(_get_param_any(["min_distance", "minWanderDistance"], 5.0))
	var max_distance: float = float(_get_param_any(["max_distance", "maxWanderDistance"], 10.0))
	var returned_dest_key: String = str(_get_param_any(["returned_destination", "returnedDestination"], "WanderDestination"))

	var dest: Vector3 = Vector3.ZERO
	if actor.has_method("get_random_navmesh_point"):
		dest = actor.get_random_navmesh_point(min_distance, max_distance)

	_set_bb(returned_dest_key, dest)
	_set_bb("WanderDestination", dest)
	return BTStatus.SUCCESS
