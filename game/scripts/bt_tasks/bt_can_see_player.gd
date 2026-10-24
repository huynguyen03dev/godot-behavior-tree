class_name BTCanSeePlayer
extends BTGhostTaskBase

func on_update() -> int:
	var actor = _get_actor()
	if actor == null:
		return BTStatus.FAILURE

	var fov_angle: float = float(_get_param_any(["fov_angle", "fieldOfViewAngle"], 75.0))
	var view_distance: float = float(_get_param_any(["view_distance", "viewDistance"], 20.0))
	var target_player_mode: bool = bool(_get_param_any(["target_player_mode", "targetPlayerMode"], false))
	var target_player_key: String = str(_get_param_any(["target_player", "chasedPlayer"], "$PlayerToChase"))
	var returned_player_key: String = str(_get_param_any(["returned_player", "returnedObject", "otherPlayerToChase"], "$PlayerToChase"))

	var target: Node3D = null
	if target_player_mode:
		target = _get_bb(target_player_key)
	elif actor.has_method("_get_player"):
		target = actor._get_player()

	if target == null:
		return BTStatus.FAILURE

	var can_see: bool = false
	if actor.has_method("can_see_target"):
		can_see = actor.can_see_target(target, fov_angle, view_distance)
	elif actor.has_method("is_player_visible"):
		can_see = actor.is_player_visible(target)

	if can_see:
		_set_bb(returned_player_key, target)
		_set_bb("PlayerToChase", target)
		return BTStatus.SUCCESS

	return BTStatus.FAILURE

func evaluate_condition(_runner) -> int:
	return on_update()
