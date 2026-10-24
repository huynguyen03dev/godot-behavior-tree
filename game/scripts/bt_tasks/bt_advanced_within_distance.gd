class_name BTAdvancedWithinDistance
extends BTGhostTaskBase

func on_update() -> int:
	var actor = _get_actor()
	if actor == null:
		return BTStatus.FAILURE

	var magnitude: float = float(_get_param_any(["magnitude"], 5.0))
	var target_tag: String = str(_get_param_any(["target_tag", "targetTag"], "RitualBook"))
	var line_of_sight: bool = bool(_get_param_any(["line_of_sight", "lineOfSight"], true))
	var returned_object_key: String = str(_get_param_any(["returned_object", "returnedObject"], "$RitualBook"))

	var found_obj = null
	if actor.has_method("query_nearby_objects"):
		found_obj = actor.query_nearby_objects(target_tag, magnitude, line_of_sight)

	if found_obj != null:
		_set_bb(returned_object_key, found_obj)
		if target_tag == "RitualBook":
			_set_bb("RitualBook", found_obj)
			_set_bb("NearRitualBook", true)
		elif target_tag == "Player":
			_set_bb("PlayerWithinDistance", found_obj)
		return BTStatus.SUCCESS

	return BTStatus.FAILURE

func evaluate_condition(_runner) -> int:
	return on_update()
