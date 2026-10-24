class_name BTRatStartStopAbility
extends BTRatTaskBase

func on_update() -> int:
	var start: bool = bool(_get_param_any(["Start", "start"], false))
	var ability_type: String = str(_get_param_any(["AbilityType", "ability_type"], ""))

	if "SpeedChange" in ability_type or "Speed" in ability_type:
		if start:
			# Speed up -> Flee speed
			var flee_spd = float(_get_bb("FleeSpeed", 3.2))
			_set_bb("Speed", flee_spd)
		else:
			# Slow down -> Wander speed
			var wander_spd = float(_get_bb("WanderSpeed", 1.0))
			_set_bb("Speed", wander_spd)

	return BTStatus.SUCCESS
