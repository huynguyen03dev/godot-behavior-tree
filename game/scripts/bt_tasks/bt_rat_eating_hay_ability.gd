class_name BTRatStartStopEatingHayAbility
extends BTRatTaskBase

func on_update() -> int:
	var start: bool = bool(_get_param_any(["Start", "start"], true))
	var actor := _get_actor()
	if actor != null and actor.has_method("set_locomotion_state"):
		actor.set_locomotion_state("Eating" if start else "Default")
	return BTStatus.SUCCESS
