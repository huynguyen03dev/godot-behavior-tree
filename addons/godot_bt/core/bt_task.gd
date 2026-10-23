class_name BTTask
extends BTTaskNative

func _init() -> void:
	pass

static func coerce_bool(value, fallback: bool = false) -> bool:
	return BTTaskNative.coerce_bool(value, fallback)

func get_param(name: String, default_val = null):
	return bt_get_param(name, default_val)

func set_param(name: String, value, is_blackboard_key: bool = false) -> void:
	bt_set_param(name, value, is_blackboard_key)

func get_blackboard_var(name: String, default_val = null):
	return bt_get_blackboard_var(name, default_val)

func on_awake() -> void:
	bt_on_awake()

func on_reset() -> void:
	bt_on_reset()

func on_start() -> void:
	bt_on_start()

func on_update() -> int:
	return bt_on_update()

func evaluate_condition(runner: BTRunner) -> int:
	return bt_evaluate_condition(runner)

func on_end() -> void:
	bt_on_end()

func on_abort() -> void:
	bt_on_abort()

func on_pause(paused: bool) -> void:
	bt_on_pause(paused)

func on_event(event_name: String, data = null) -> void:
	bt_on_event(event_name, data)

func can_execute() -> bool:
	return bt_can_execute()

func on_tick_start() -> void:
	bt_on_tick_start()

func can_run_parallel_children() -> bool:
	return bt_can_run_parallel_children()

func on_child_started(child_index: int) -> void:
	bt_on_child_started(child_index)

func get_current_child_index() -> int:
	return bt_current_child_index()

func get_execution_order_index(child_index: int) -> int:
	return bt_execution_order_index(child_index)

func on_child_executed(child_index: int, child_status: int) -> void:
	bt_on_child_executed(child_index, child_status)

func decorate(status: int) -> int:
	return bt_decorate(status)

func override_status(status: int) -> int:
	return bt_override_status(status)
