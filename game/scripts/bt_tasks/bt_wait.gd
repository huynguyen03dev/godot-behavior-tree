class_name BTWait
extends BTGhostTaskBase

var elapsed_time: float = 0.0
var current_duration: float = 1.0

func on_start() -> void:
	elapsed_time = 0.0
	var is_random: bool = bool(_get_param_any(["random_wait", "randomWait"], false))
	if is_random:
		var r_min: float = float(_get_param_any(["random_wait_min", "randomWaitMin"], 1.0))
		var r_max: float = float(_get_param_any(["random_wait_max", "randomWaitMax"], 3.0))
		current_duration = randf_range(r_min, r_max)
	else:
		current_duration = float(_get_param_any(["wait_time", "waitTime", "duration"], 1.0))

func on_update() -> int:
	var delta: float = _get_delta()
	elapsed_time += delta
	if elapsed_time >= current_duration:
		return BTStatus.SUCCESS
	return BTStatus.RUNNING

func on_end() -> void:
	elapsed_time = 0.0
