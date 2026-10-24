class_name BTPlayerFlashlightOnMe
extends BTGhostTaskBase

func on_update() -> int:
	var actor = _get_actor()
	if actor == null:
		return BTStatus.FAILURE

	var view_distance: float = float(_get_param_any(["view_distance", "viewDistance"], 15.0))
	var fry_only: bool = bool(_get_param_any(["fry_only", "fryOnly"], false))
	var target_player_mode: bool = bool(_get_param_any(["target_player_mode", "targetPlayerMode"], false))
	var target_player_key: String = str(_get_param_any(["target_player", "chasedPlayer"], "$PlayerToChase"))
	var returned_player_key: String = str(_get_param_any(["returned_player", "returnedPlayer", "otherPlayerToChase"], "$PlayerToChase"))

	var shining_player = null
	if actor.has_method("is_flashlight_shining_on_me"):
		shining_player = actor.is_flashlight_shining_on_me(fry_only, view_distance)

	if shining_player != null:
		if target_player_mode:
			var target = _get_bb(target_player_key)
			if target != null and target != shining_player:
				return BTStatus.FAILURE

		_set_bb(returned_player_key, shining_player)
		_set_bb("PlayerToChase", shining_player)
		if fry_only:
			_set_bb("StartedFocus", true)
			_set_bb("PlayerFryingMe", shining_player)
		return BTStatus.SUCCESS

	return BTStatus.FAILURE

func evaluate_condition(_runner) -> int:
	return on_update()
