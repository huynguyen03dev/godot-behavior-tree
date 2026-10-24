class_name BTCanHearPlayer
extends BTGhostTaskBase

func on_update() -> int:
	var actor = _get_actor()
	if actor == null:
		return BTStatus.FAILURE

	var hearing_radius: float = float(_get_param_any(["hearing_radius", "hearingRadius"], 1.5))
	var audibility_distance: float = float(_get_param_any(["audibility_distance", "audibilityDistance"], 15.0))
	var returned_player_key: String = str(_get_param_any(["returned_player", "playerHeard", "otherPlayerToChase"], "$PlayerToChase"))

	var heard_player: Node3D = null
	if actor.has_method("detect_player_noise"):
		heard_player = actor.detect_player_noise(hearing_radius, audibility_distance)

	if heard_player != null:
		_set_bb(returned_player_key, heard_player)
		_set_bb("PlayerToChase", heard_player)
		_set_bb("PlayerHeard", heard_player)
		return BTStatus.SUCCESS

	return BTStatus.FAILURE

func evaluate_condition(_runner) -> int:
	return on_update()
