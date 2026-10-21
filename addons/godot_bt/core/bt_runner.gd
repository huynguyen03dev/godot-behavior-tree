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

		# Check conditional aborts for composites with active running children
		if task is BTComposite:
			var composite := task as BTComposite
			if composite.abort_type != BTComposite.AbortType.NONE and composite.current_child_index > 0:
				_check_conditional_abort(composite)

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

func _check_conditional_abort(composite: BTComposite) -> bool:
	if composite.children.is_empty():
		return false
	var cur_idx := composite.current_child_index
	if cur_idx <= 0 or cur_idx >= composite.children.size():
		return false

	var abort_type := composite.abort_type

	# LowerPriority or Both: check if higher-priority branch (< cur_idx) can now run
	if composite is BTComposite.BTSelector and (abort_type == BTComposite.AbortType.LOWER_PRIORITY or abort_type == BTComposite.AbortType.BOTH):
		for i in range(0, cur_idx):
			var child: BTTask = composite.children[i]
			var status := _reevaluate_branch(child)
			if status == BTStatus.SUCCESS:
				# Higher priority condition met! Abort current running branch
				_abort_task_branch(composite.children[cur_idx])
				composite.current_child_index = i
				composite._execution_status = BTStatus.RUNNING
				return true

	# Self or Both: check if active sequence's guard conditions (< cur_idx) failed
	if composite is BTComposite.BTSequence and (abort_type == BTComposite.AbortType.SELF or abort_type == BTComposite.AbortType.BOTH):
		for i in range(0, cur_idx):
			var child: BTTask = composite.children[i]
			var status := _reevaluate_branch(child)
			if status == BTStatus.FAILURE:
				# Guard condition failed! Abort current running child and fail sequence
				_abort_task_branch(composite.children[cur_idx])
				composite._execution_status = BTStatus.FAILURE
				composite.current_child_index = composite.children.size()
				return true

	return false

func _reevaluate_branch(task: BTTask) -> int:
	if task == null or task.is_placeholder:
		return BTStatus.INACTIVE

	if task is BTComposite.BTSequence:
		var seq := task as BTComposite.BTSequence
		for child in seq.children:
			var s := _reevaluate_branch(child)
			if s == BTStatus.FAILURE:
				return BTStatus.FAILURE
			elif s == BTStatus.RUNNING:
				return BTStatus.SUCCESS
		return BTStatus.SUCCESS
	elif task is BTComposite.BTSelector:
		var sel := task as BTComposite.BTSelector
		for child in sel.children:
			var s := _reevaluate_branch(child)
			if s == BTStatus.SUCCESS:
				return BTStatus.SUCCESS
		return BTStatus.FAILURE
	elif task is BTDecorator.BTInverter:
		var inv := task as BTDecorator.BTInverter
		if not inv.children.is_empty():
			var s := _reevaluate_branch(inv.children[0])
			if s == BTStatus.SUCCESS:
				return BTStatus.FAILURE
			elif s == BTStatus.FAILURE:
				return BTStatus.SUCCESS
			return s
		return BTStatus.SUCCESS
	else:
		if task.category == "Condition" or task.get("is_condition") == true:
			if task.owner == null:
				task.owner = self
			if task.blackboard == null and tree != null:
				task.blackboard = tree.blackboard
			return task.on_update()
		else:
			# Action reached: preconditions prior to this action succeeded
			return BTStatus.SUCCESS

func _abort_task_branch(task: BTTask) -> void:
	if task == null:
		return
	if task is BTParentTask:
		for child in (task as BTParentTask).children:
			_abort_task_branch(child)
	if _started.has(task):
		task.on_abort()
		_started.erase(task)
		_last_status[task] = BTStatus.FAILURE
		task_finished.emit(task, BTStatus.FAILURE)

## Broadcasts a named event to all tasks in the tree.
func send_event(event_name: String, data: Variant = null) -> void:
	if tree == null:
		return
	for task in tree.node_list:
		if task != null and not task.is_placeholder:
			task.on_event(event_name, data)

## Pauses or resumes execution of the tree and notifies active tasks.
func pause(paused: bool = true) -> void:
	is_running = not paused
	for task in _started.keys():
		if task != null and not task.is_placeholder:
			task.on_pause(paused)

## Explicitly interrupts and aborts an active task branch.
func interrupt(task: BTTask, status: int = BTStatus.FAILURE) -> void:
	_abort_task_branch(task)
	_last_status[task] = status

