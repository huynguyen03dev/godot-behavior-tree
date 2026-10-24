class_name BTParallelComplete
extends BTComposite.BTParallel

var execution_status_list: Array = []

func _init() -> void:
	_setup_kind("Parallel", "ParallelComplete", "Composite")

func on_awake() -> void:
	execution_status_list.clear()
	for c in children:
		execution_status_list.append(BTStatus.INACTIVE)

func on_child_started(child_index: int) -> void:
	super.on_child_started(child_index)
	if execution_status_list.is_empty():
		on_awake()
	if child_index >= 0 and child_index < execution_status_list.size():
		execution_status_list[child_index] = BTStatus.RUNNING

func on_child_executed(child_index: int, child_status: int) -> void:
	super.on_child_executed(child_index, child_status)
	if execution_status_list.is_empty():
		on_awake()
	if child_index >= 0 and child_index < execution_status_list.size():
		execution_status_list[child_index] = child_status

func override_status(_status: int) -> int:
	if execution_status_list.is_empty():
		on_awake()
	for s in execution_status_list:
		if s == BTStatus.SUCCESS or s == BTStatus.FAILURE:
			return s
	return BTStatus.RUNNING

func on_end() -> void:
	for i in range(execution_status_list.size()):
		execution_status_list[i] = BTStatus.INACTIVE
	super.on_end()
