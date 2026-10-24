class_name BTGhostGetFleeDestination
extends BTGhostTaskBase

func on_update() -> int:
	var actor = _get_actor()
	if actor == null:
		return BTStatus.FAILURE

	var look_ahead: float = float(_get_param_any(["look_ahead_distance", "lookAheadDistance"], 2.5))
	var player_key: String = str(_get_param_any(["player_variable", "player"], "$PlayerWithinDistance"))
	var returned_dest_key: String = str(_get_param_any(["returned_destination", "returnedDestination"], "FleeDestination"))

	var threat = _get_bb(player_key)
	if threat == null:
		threat = _get_bb("PlayerToChase")
	if threat == null and actor.has_method("_get_player"):
		threat = actor._get_player()

	var threat_pos: Vector3 = Vector3.ZERO
	if threat is Node3D:
		threat_pos = get_node_pos(threat)
	elif threat is Vector3:
		threat_pos = threat

	var flee_dest: Vector3 = Vector3.ZERO
	if actor.has_method("compute_flee_point"):
		flee_dest = actor.compute_flee_point(threat_pos, look_ahead * 4.0)

	_set_bb(returned_dest_key, flee_dest)
	_set_bb("FleeDestination", flee_dest)
	return BTStatus.SUCCESS
