class_name BTRatBoolComparison
extends BTRatTaskBase

func on_update() -> int:
	var friendly_name = ""
	if owner != null and "friendly_name" in owner:
		friendly_name = owner.friendly_name

	if friendly_name == "Wander is running":
		# In SurvivalRat BT, node 51 checks if wander is running. If not disabled, return SUCCESS.
		return BTStatus.SUCCESS if not _is_actor_disabled() else BTStatus.FAILURE

	if friendly_name == "Wander has been interrupted":
		var interrupted: bool = bool(_get_bb("InterruptedWander", false))
		return BTStatus.SUCCESS if interrupted else BTStatus.FAILURE

	if friendly_name == "Hay dropped by player":
		var dropped: bool = bool(_get_bb("DroppedByPlayer", false))
		return BTStatus.SUCCESS if dropped else BTStatus.FAILURE

	if friendly_name == "Should destroy hay?":
		var destroy: bool = bool(_get_bb("DestroyHay", false))
		return BTStatus.SUCCESS if destroy else BTStatus.FAILURE

	# Generic fallback
	var b1 = _get_param_any(["bool1"], false)
	var b2 = _get_param_any(["bool2"], true)
	if str(b1).begins_with("$"): b1 = _get_bb(str(b1), false)
	if str(b2).begins_with("$"): b2 = _get_bb(str(b2), false)

	return BTStatus.SUCCESS if bool(b1) == bool(b2) else BTStatus.FAILURE

func evaluate_condition(_runner) -> int:
	return on_update()
