class_name BTPlayersFocusingMeWait
extends BTGhostTaskBase

var accumulated_time: float = 0.0

func on_start() -> void:
	accumulated_time = 0.0

func on_update() -> int:
	var actor = _get_actor()
	if actor == null:
		return BTStatus.FAILURE

	var wait_time: float = float(_get_param_any(["wait_time", "waitTime"], 1.5))
	var delta: float = _get_delta()

	var shining_player = null
	if actor.has_method("is_flashlight_shining_on_me"):
		shining_player = actor.is_flashlight_shining_on_me(true, 6.0)

	if shining_player != null:
		accumulated_time += delta
		if accumulated_time >= wait_time:
			accumulated_time = 0.0
			return BTStatus.SUCCESS
		return BTStatus.RUNNING
	else:
		accumulated_time = maxf(0.0, accumulated_time - delta * 0.5)
		return BTStatus.FAILURE

func on_end() -> void:
	# Keep accumulated_time if still running or reset on full end
	pass
