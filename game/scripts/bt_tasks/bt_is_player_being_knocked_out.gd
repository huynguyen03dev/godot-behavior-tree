class_name BTIsPlayerBeingKnockedOut
extends BTGhostTaskBase

func on_update() -> int:
	var target_var = _get_param_any(["player", "Player"], "$PlayerToChase")
	var target = _get_bb(str(target_var))
	var actor = _get_actor()
	if target == null and actor != null and actor.has_method("_get_player"):
		target = actor._get_player()

	if target == null:
		return BTStatus.FAILURE

	if "is_knocked_out" in target and bool(target.is_knocked_out):
		return BTStatus.SUCCESS
	if "is_downed" in target and bool(target.is_downed):
		return BTStatus.SUCCESS

	return BTStatus.FAILURE

func evaluate_condition(_runner) -> int:
	return on_update()
