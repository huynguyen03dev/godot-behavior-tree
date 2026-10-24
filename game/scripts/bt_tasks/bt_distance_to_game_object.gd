class_name BTDistanceToGameObject
extends BTGhostTaskBase

func on_update() -> int:
	var actor = _get_actor()
	var target_var = _get_param_any(["target"], "$PlayerToChase")
	var store_var: String = str(_get_param_any(["store_variable", "storeResult"], "DistanceToPursuedPlayer"))

	var target = _get_bb(str(target_var))
	if target == null and actor != null and actor.has_method("_get_player"):
		target = actor._get_player()

	var dist: float = 0.0
	if actor != null and target != null:
		if actor.has_method("get_target_distance"):
			dist = actor.get_target_distance(target)
		elif actor is Node3D and target is Node3D:
			dist = get_node_pos(actor).distance_to(get_node_pos(target))

	_set_bb(store_var, dist)
	return BTStatus.SUCCESS
