class_name BTRatIsAbilityActive
extends BTRatTaskBase

func on_update() -> int:
	var ability_type: String = str(_get_param_any(["AbilityType", "ability_type"], ""))
	var actor := _get_actor()
	if actor != null and actor.has_method("get_shared_bool"):
		if actor.get_shared_bool(ability_type):
			return BTStatus.SUCCESS
	return BTStatus.FAILURE

func evaluate_condition(_runner) -> int:
	return on_update()
