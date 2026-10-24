class_name BTRatSetLocomotionState
extends BTRatTaskBase

func on_update() -> int:
	var state_name: String = str(_get_param_any(["StateName", "state_name"], ""))
	var activate: bool = bool(_get_param_any(["Activate", "activate"], false))

	var actor := _get_actor()
	if actor != null and actor.has_method("set_locomotion_state"):
		if activate:
			actor.set_locomotion_state(state_name)
		else:
			actor.set_locomotion_state("Default")

	return BTStatus.SUCCESS
