class_name BTPlayerTouchingMe
extends BTGhostTaskBase

func on_update() -> int:
	var actor = _get_actor()
	if actor == null:
		return BTStatus.FAILURE

	var touching_distance: float = float(_get_param_any(["touching_distance", "touchingDistance"], 0.2))
	var target_player_key: String = str(_get_param_any(["target_player", "returnedPlayer", "chasedPlayer"], "$PlayerToChase"))

	var target = _get_bb(target_player_key)
	if target == null and actor.has_method("_get_player"):
		target = actor._get_player()

	if target == null:
		return BTStatus.FAILURE

	var dist: float = 999.0
	if actor.has_method("get_target_distance"):
		dist = actor.get_target_distance(target)
	elif actor is Node3D and target is Node3D:
		dist = get_node_pos(actor).distance_to(get_node_pos(target))

	if dist <= touching_distance:
		return BTStatus.SUCCESS

	return BTStatus.FAILURE

func evaluate_condition(_runner) -> int:
	return on_update()
