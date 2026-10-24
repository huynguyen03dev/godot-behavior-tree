class_name BTSetSpeed
extends BTGhostTaskBase

func on_update() -> int:
	var speed: float = float(_get_param_any(["speed", "ReturnedSpeed"], 1.0))
	_set_bb("Speed", speed)

	var actor = _get_actor()
	if actor != null and actor.has_method("set_motor_speed"):
		actor.set_motor_speed(speed)
	elif actor != null and actor.has_method("set_speed"):
		actor.set_speed(speed)

	return BTStatus.SUCCESS
