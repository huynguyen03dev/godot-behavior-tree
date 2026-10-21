class_name BTRunner
extends Node
## Generic Runner for executing Behavior Trees (`BTTree`).
## Manages execution lifecycle, ticking, status propagation, signals, and placeholder handling.

signal tree_finished(status: int)
signal task_started(task)
signal task_finished(task, status: int)

enum UpdateInterval { EVERY_FRAME = 0, SPECIFIED_SECONDS = 1 }
enum ExecutionsPerTick { NO_LIMIT = 0, COUNT = 1 }

@export var update_interval: UpdateInterval = UpdateInterval.EVERY_FRAME
@export var update_interval_seconds: float = 0.0
@export var executions_per_tick: ExecutionsPerTick = ExecutionsPerTick.NO_LIMIT
@export var max_task_executions_per_tick: int = 0
@export var auto_start: bool = false
@export var max_ticks: int = 0

var tree: BTTree = null
var is_running: bool = false
var last_status: int = BTStatus.INACTIVE
var ticks: int = 0
var task_executions: int = 0
var tick_log: Array = []
var stopped_at_placeholder: String = ""

var _started: Dictionary = {} # task -> true
var _last_status: Dictionary = {} # task -> status
var _prepared_for_tick: Dictionary = {} # parent task -> true
var _elapsed: float = 0.0

func _init(p_tree: BTTree = null) -> void:
	if p_tree != null:
		tree = p_tree

func _ready() -> void:
	if auto_start and tree != null:
		start()

func _process(delta: float) -> void:
	if not is_running:
		return
	if update_interval == UpdateInterval.SPECIFIED_SECONDS:
		_elapsed += delta
		if _elapsed < update_interval_seconds:
			return
		_elapsed = 0.0
	tick()

func set_tree(p_tree: BTTree) -> void:
	if is_running:
		stop()
	tree = p_tree
	_reset_state()

func _reset_state() -> void:
	_started.clear()
	_last_status.clear()
	_prepared_for_tick.clear()
	tick_log.clear()
	ticks = 0
	task_executions = 0
	last_status = BTStatus.INACTIVE
	stopped_at_placeholder = ""
	_elapsed = 0.0

func start() -> void:
	if tree == null or tree.root_task == null:
		return
	if is_running:
		stop()
	_reset_state()
	is_running = true

	# Assign owner so lifecycle callbacks can access the runner
	for task in tree.node_list:
		if task != null and not task.is_placeholder:
			task.owner = self

	# Root task recursively resets subtree, avoiding repeated on_reset calls
	if tree.root_task != null and not tree.root_task.is_placeholder:
		tree.root_task.on_reset()

	# Call on_awake once per task
	for task in tree.node_list:
		if task != null and not task.is_placeholder:
			task.on_awake()

func stop() -> void:
	if not is_running:
		return
	is_running = false
	for task in _started.keys():
		if task != null and not task.is_placeholder:
			task.on_end()
	_started.clear()

func tick() -> int:
	if tree == null or tree.root_task == null:
		return BTStatus.INACTIVE
	if not is_running:
		return last_status
	if max_ticks > 0 and ticks >= max_ticks:
		is_running = false
		return last_status

	ticks += 1
	task_executions = 0
	_prepared_for_tick.clear()
	var status := _run_task(tree.root_task)
	last_status = status
	if status != BTStatus.RUNNING:
		is_running = false
		tree_finished.emit(status)
	return status

func _run_task(task: BTTask) -> int:
	if task == null:
		return BTStatus.INACTIVE
	if executions_per_tick == ExecutionsPerTick.COUNT and max_task_executions_per_tick > 0 \
			and task_executions >= max_task_executions_per_tick:
		return BTStatus.RUNNING

	task_executions += 1

	# Handle placeholder tasks
	if task.is_placeholder:
		if stopped_at_placeholder == "":
			stopped_at_placeholder = task.type_name
			tick_log.append("<placeholder:%s>" % stopped_at_placeholder)
		return BTStatus.INACTIVE

	# Start task
	if not _started.has(task):
		_started[task] = true
		task.on_start()
		task_started.emit(task)

	tick_log.append(task.friendly_name if task.friendly_name != "" else task.type_name)

	var result := BTStatus.INACTIVE
	if task is BTParentTask:
		var parent_task := task as BTParentTask
		if not _prepared_for_tick.has(task):
			parent_task.on_tick_start()
			_prepared_for_tick[task] = true
		var executed_child := false
		var last_child_index := -1
		while parent_task.can_execute():
			var child_idx := parent_task.get_current_child_index()
			# A parent that keeps the same child index (repeat/until/decorator
			# semantics) must yield to the next tick. Without this guard a child
			# that keeps returning Failure/Success spins inside one tick forever.
			if executions_per_tick == ExecutionsPerTick.NO_LIMIT and child_idx == last_child_index:
				break
			last_child_index = child_idx
			var child_status := BTStatus.INACTIVE
			if child_idx >= 0 and child_idx < parent_task.children.size():
				parent_task.on_child_started(child_idx)
				child_status = _run_task(parent_task.children[child_idx])
			parent_task.on_child_executed(child_idx, child_status)
			executed_child = true
			result = child_status
			if child_status == BTStatus.RUNNING and not parent_task.can_run_parallel_children():
				break
			if executions_per_tick == ExecutionsPerTick.COUNT and max_task_executions_per_tick > 0 \
					and task_executions >= max_task_executions_per_tick:
				break
		if not executed_child:
			result = int(_last_status.get(task, BTStatus.INACTIVE))
	else:
		result = task.on_update()

	if task is BTParentTask:
		result = (task as BTParentTask).decorate(result)
		result = (task as BTParentTask).override_status(result)

	_last_status[task] = result

	if result != BTStatus.RUNNING:
		task.on_end()
		_started.erase(task)
		task_finished.emit(task, result)

	return result
