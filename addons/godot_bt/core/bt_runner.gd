class_name BTRunner
extends Node
## Generic Runner for executing Behavior Trees (`BTTree`).
## Manages execution lifecycle, ticking, status propagation, signals, and placeholder handling.

signal tree_finished(status: int)
signal task_started(task)
signal task_finished(task, status: int)
## Emitted for each started task that ends because its branch was aborted
## (conditional abort, interrupt, or sibling failure). Emitted before the
## compatibility task_finished(task, FAILURE) signal.
signal task_aborted(task)

enum UpdateInterval { EVERY_FRAME = 0, SPECIFIED_SECONDS = 1 }
## Deprecated: the execution budget now applies whenever
## max_task_executions_per_tick > 0, regardless of this enum. The enum is kept
## only for backward compatibility with existing scenes and scripts.
enum ExecutionsPerTick { NO_LIMIT = 0, COUNT = 1 }

@export var update_interval: UpdateInterval = UpdateInterval.EVERY_FRAME
@export var update_interval_seconds: float = 0.0
@export var executions_per_tick: ExecutionsPerTick = ExecutionsPerTick.NO_LIMIT
@export var max_task_executions_per_tick: int = 0
@export var auto_start: bool = false
@export var max_ticks: int = 0
## When false (default) the runner records no per-task tick entries. When true,
## tick_log collects the last 512 executed task names for debugging.
@export var debug_log := false

var tree: BTTree = null
var actor: Node = null
var delta: float = 0.0
## Simulated time advanced by each running tick's delta. Monotonic for the
## runner's lifetime: start()/set_tree() never reset it. Time-based decorators
## (TimeLimit, Cooldown) read it instead of wall-clock time so pauses, manual
## ticking, and Engine.time_scale behave predictably.
var time: float = 0.0
var is_running: bool = false
var last_status: int = BTStatus.INACTIVE
var ticks: int = 0
var task_executions: int = 0
var tick_log: Array = []
var stopped_at_placeholder: String = ""
var subtree_path_stack: Array[String] = []

var _started: Dictionary = {} # task -> true
var _last_status: Dictionary = {} # task -> status
var _prepared_for_tick: Dictionary = {} # parent task -> true
var _pending_terminal: Dictionary = {}
var _elapsed: float = 0.0
var _paused: bool = false
var _execution_generation: int = 0
var _activation_interrupts: Dictionary = {}
var _ticking: bool = false

func _init(p_tree: BTTree = null) -> void:
	if p_tree != null:
		tree = p_tree

func _ready() -> void:
	if auto_start and tree != null:
		start()

func _process(delta: float) -> void:
	if not is_running:
		return
	if update_interval != UpdateInterval.SPECIFIED_SECONDS:
		tick(delta)
		return
	if update_interval_seconds <= 0.0:
		tick(delta)
		return
	_elapsed += delta
	if _elapsed < update_interval_seconds:
		return
	# Hand the tree the full accumulated interval, and subtract the interval
	# instead of resetting so leftover time carries toward the next tick.
	var step := _elapsed
	_elapsed -= update_interval_seconds
	tick(step)

func _exit_tree() -> void:
	stop()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		stop()

func set_tree(p_tree: BTTree) -> void:
	_execution_generation += 1
	if is_running or not _started.is_empty() or _paused:
		stop()
	tree = p_tree
	_reset_state()

func _reset_state() -> void:
	_started.clear()
	_last_status.clear()
	_prepared_for_tick.clear()
	_pending_terminal.clear()
	tick_log.clear()
	ticks = 0
	task_executions = 0
	last_status = BTStatus.INACTIVE
	stopped_at_placeholder = ""
	_elapsed = 0.0

func start() -> void:
	_execution_generation += 1
	if tree == null or tree.root_task == null:
		return
	if is_running or not _started.is_empty() or _paused:
		stop()
	_reset_state()
	is_running = true
	if actor == null and get_parent() is Node:
		actor = get_parent()

	# Assign owner so lifecycle callbacks can access the runner, and keep every
	# task pointing at the tree's current blackboard so replacing
	# tree.blackboard before start() reaches all tasks.
	for task in tree.node_list:
		if task != null and not task.is_placeholder:
			task.owner = self
			task.blackboard = tree.blackboard

	# Root task recursively resets subtree, avoiding repeated on_reset calls
	if tree.root_task != null and not tree.root_task.is_placeholder:
		tree.root_task.on_reset()

	# Call on_awake once per start (not once per task lifetime; tasks that need
	# one-time-per-lifetime init must guard themselves)
	var awake_generation := _execution_generation
	var awake_tree := tree
	for task in tree.node_list:
		if task != null and not task.is_placeholder:
			task.on_awake()
			if awake_generation != _execution_generation or awake_tree != tree:
				return

func stop() -> void:
	_execution_generation += 1
	is_running = false
	_paused = false
	var started := _started.keys()
	_started.clear()
	_prepared_for_tick.clear()
	_pending_terminal.clear()
	for task in started:
		if task != null and not task.is_placeholder:
			task.on_end()
			# Mirror natural finish/abort so lifecycle listeners see every
			# started task closed; stop() is no longer signal-silent.
			task_finished.emit(task, task.last_status)
	_ticking = false

func tick(p_delta: float = 0.0) -> int:
	if _ticking:
		push_warning("BTRunner.tick() was called re-entrantly from inside a running tick; the nested tick is ignored.")
		return last_status
	_ticking = true
	var status := _tick_internal(p_delta)
	_ticking = false
	return status

func _tick_internal(p_delta: float = 0.0) -> int:
	if tree == null or tree.root_task == null:
		return BTStatus.INACTIVE
	if not is_running:
		return last_status
	if max_ticks > 0 and ticks >= max_ticks:
		stop()
		return last_status

	delta = p_delta
	time += p_delta
	ticks += 1
	task_executions = 0
	_prepared_for_tick.clear()
	var generation := _execution_generation
	_activation_interrupts.clear()
	var status := _run_task(tree.root_task)
	if generation != _execution_generation:
		return last_status
	# A root interrupt completes synchronously; do not emit a second completion
	# when the interrupted root unwinds through this tick.
	if _activation_interrupts.has(tree.root_task) and not is_running:
		return last_status
	if _activation_interrupts.has(tree.root_task):
		status = int(_activation_interrupts[tree.root_task])
	last_status = status
	if status != BTStatus.RUNNING:
		stop()
		tree_finished.emit(status)
	return status

func _run_task(task: BTTask) -> int:
	if task == null:
		return BTStatus.INACTIVE
	var _tick_generation := _execution_generation
	if _pending_terminal.has(task):
		var pending_status := int(_pending_terminal[task])
		_pending_terminal.erase(task)
		_last_status[task] = pending_status
		task.last_status = pending_status
		return pending_status
	if max_task_executions_per_tick > 0 \
			and task_executions >= max_task_executions_per_tick and not task is BTParentTask:
		return BTStatus.RUNNING

	if not task is BTParentTask:
		task_executions += 1

	# Handle placeholder tasks
	if task.is_placeholder:
		if stopped_at_placeholder == "":
			stopped_at_placeholder = task.type_name
			_log_tick("<placeholder:%s>" % stopped_at_placeholder)
		return BTStatus.INACTIVE

	# Start task
	if not _started.has(task):
		_started[task] = true
		var activation_generation := _execution_generation
		task.on_start()
		if activation_generation != _execution_generation or not _started.has(task):
			return int(_activation_interrupts.get(task, BTStatus.INACTIVE))
		task_started.emit(task)
		if activation_generation != _execution_generation or not _started.has(task):
			return int(_activation_interrupts.get(task, BTStatus.INACTIVE))

	_log_tick(task.friendly_name if task.friendly_name != "" else task.type_name)

	var result := BTStatus.INACTIVE
	if task is BTParentTask:
		var parent_task := task as BTParentTask
		if not _prepared_for_tick.has(task):
			var hook_generation := _execution_generation
			parent_task.on_tick_start()
			if hook_generation != _execution_generation or _activation_interrupts.has(task):
				return int(_activation_interrupts.get(task, BTStatus.INACTIVE))
			_prepared_for_tick[task] = true

		# Check conditional aborts for composites with active running children
		if task is BTComposite:
			var composite := task as BTComposite
			if composite.abort_type != BTComposite.AbortType.NONE and composite.current_child_index > 0:
				var abort_generation := _execution_generation
				_check_conditional_abort(composite)
				# Condition probes run user code; stop()/set_tree()/interrupt()
				# from inside one must unwind this tick like every other hook.
				if abort_generation != _execution_generation or _activation_interrupts.has(task):
					return int(_activation_interrupts.get(task, BTStatus.INACTIVE))

		var executed_child := false
		var last_child_index := -1
		while parent_task.can_execute():
			var child_idx := parent_task.get_current_child_index()
			# A parent that keeps the same child index (repeat/until/decorator
			# semantics) must yield to the next tick. Without this guard a child
			# that keeps returning Failure/Success spins inside one tick forever.
			if child_idx == last_child_index:
				break
			last_child_index = child_idx
			var child_status := BTStatus.INACTIVE
			if child_idx >= 0 and child_idx < parent_task.children.size():
				var child_hook_generation := _execution_generation
				parent_task.on_child_started(child_idx)
				if child_hook_generation != _execution_generation or _activation_interrupts.has(task):
					return int(_activation_interrupts.get(task, BTStatus.INACTIVE))
				child_status = _run_task(parent_task.children[child_idx])
				if _execution_generation != _tick_generation or _activation_interrupts.has(task):
					return int(_activation_interrupts.get(task, _last_status.get(task, BTStatus.INACTIVE)))
				child_hook_generation = _execution_generation
				parent_task.on_child_executed(child_idx, child_status)
				if child_hook_generation != _execution_generation or _activation_interrupts.has(task):
					return int(_activation_interrupts.get(task, _last_status.get(task, BTStatus.INACTIVE)))
			executed_child = true
			result = child_status
			if child_status == BTStatus.RUNNING and not parent_task.can_run_parallel_children():
				break
			if max_task_executions_per_tick > 0 \
					and task_executions >= max_task_executions_per_tick:
				break
		if not executed_child:
			result = int(_last_status.get(task, BTStatus.INACTIVE))
	else:
		var activation_generation := _execution_generation
		result = task.on_update()
		if activation_generation != _execution_generation or _activation_interrupts.has(task):
			return int(_activation_interrupts.get(task, BTStatus.INACTIVE))

	if task is BTParentTask:
		var decorate_generation := _execution_generation
		result = (task as BTParentTask).decorate(result)
		if decorate_generation != _execution_generation or _activation_interrupts.has(task):
			return int(_activation_interrupts.get(task, BTStatus.INACTIVE))
		result = (task as BTParentTask).override_status(result)
		if decorate_generation != _execution_generation or _activation_interrupts.has(task):
			return int(_activation_interrupts.get(task, BTStatus.INACTIVE))

	_last_status[task] = result
	task.last_status = result

	if result != BTStatus.RUNNING:
		_started.erase(task)
		if task is BTParentTask:
			for child in (task as BTParentTask).children:
				_abort_task_branch(child)
		task.on_end()
		if _execution_generation != _tick_generation:
			return result
		task_finished.emit(task, result)
		if _execution_generation != _tick_generation:
			return result

	return result

func _check_conditional_abort(composite: BTComposite) -> bool:
	if composite.children.is_empty():
		return false
	var cursor := composite.current_child_index
	if cursor <= 0 or cursor >= composite.children.size():
		return false
	var cur_idx := _child_at_execution_order(composite, cursor)

	var abort_type := composite.abort_type

	# LowerPriority or Both: check if higher-priority branch (< cur_idx) can now run
	if composite is BTComposite.BTSelector and (abort_type == BTComposite.AbortType.LOWER_PRIORITY or abort_type == BTComposite.AbortType.BOTH):
		for order_idx in range(cursor):
			var i := _child_at_execution_order(composite, order_idx)
			var child: BTTask = composite.children[i]
			var status := _reevaluate_branch(child)
			if status == BTStatus.SUCCESS:
				# Higher priority condition met! Abort current running branch
				_abort_task_branch(composite.children[cur_idx])
				composite.current_child_index = composite.get_execution_order_index(i)
				composite._execution_status = BTStatus.RUNNING
				return true

	# Self or Both: check if active sequence's guard conditions (< cur_idx) failed
	if composite is BTComposite.BTSequence and (abort_type == BTComposite.AbortType.SELF or abort_type == BTComposite.AbortType.BOTH):
		for order_idx in range(cursor):
			var i := _child_at_execution_order(composite, order_idx)
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
		var previous := BTStatus.SUCCESS
		var saw_guard := false
		for order_idx in seq.children.size():
			var child: BTTask = seq.children[_child_at_execution_order(seq, order_idx)]
			if child.category != "Condition" and not _is_condition_wrapper(child):
				return previous if saw_guard else BTStatus.INACTIVE
			var s := _reevaluate_branch(child)
			if s != BTStatus.SUCCESS:
				return s
			previous = s
			saw_guard = true
		return BTStatus.SUCCESS if saw_guard else BTStatus.INACTIVE
	elif task is BTComposite.BTSelector:
		var sel := task as BTComposite.BTSelector
		for order_idx in sel.children.size():
			var child: BTTask = sel.children[_child_at_execution_order(sel, order_idx)]
			var s := _reevaluate_branch(child)
			if s == BTStatus.SUCCESS:
				return BTStatus.SUCCESS
			if s != BTStatus.FAILURE:
				return s
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
		return BTStatus.INACTIVE
	elif task is BTDecorator.BTReturnSuccess or task is BTDecorator.BTReturnFailure:
		if not task.children.is_empty():
			var child_status := _reevaluate_branch(task.children[0])
			return (task as BTParentTask).decorate(child_status)
		return BTStatus.INACTIVE
	else:
		return task.evaluate_condition(self) if task.category == "Condition" else BTStatus.INACTIVE

func _child_at_execution_order(parent_task: BTParentTask, order_index: int) -> int:
	for child_index in parent_task.children.size():
		if parent_task.get_execution_order_index(child_index) == order_index:
			return child_index
	return order_index

func _is_condition_wrapper(task: BTTask) -> bool:
	return task is BTDecorator.BTInverter or task is BTDecorator.BTReturnSuccess or task is BTDecorator.BTReturnFailure

func _abort_task_branch(task: BTTask) -> void:
	if task == null:
		return
	_pending_terminal.erase(task)
	if task is BTParentTask:
		for child in (task as BTParentTask).children:
			_abort_task_branch(child)
	if _started.has(task):
		_started.erase(task)
		_last_status[task] = BTStatus.FAILURE
		task.last_status = BTStatus.FAILURE
		task.on_abort()
		task_aborted.emit(task)
		task_finished.emit(task, BTStatus.FAILURE)

## Appends a tick entry when debug logging is enabled, keeping tick_log at
## most 512 entries (oldest entries are dropped first).
func _log_tick(entry: String) -> void:
	if not debug_log:
		return
	tick_log.append(entry)
	while tick_log.size() > 512:
		tick_log.pop_front()

## Broadcasts a named event to all tasks in the tree.
func send_event(event_name: String, data: Variant = null) -> void:
	if tree == null:
		return
	for task in tree.node_list:
		if task != null and not task.is_placeholder:
			task.on_event(event_name, data)

## Pauses or resumes execution of the tree and notifies active tasks.
func pause(paused: bool = true) -> void:
	if paused:
		if not is_running:
			return
		_paused = true
	else:
		if not _paused or tree == null or tree.root_task == null:
			return
		_paused = false
	is_running = not paused
	for task in _started.keys():
		if task != null and not task.is_placeholder:
			task.on_pause(paused)

## Explicitly interrupts and aborts an active task branch.
## Interrupting a task that was never started (and is not the root) is a no-op:
## there is no active branch to end, and leaving a pending terminal status
## would poison the task's first execution later.
func interrupt(task: BTTask, status: int = BTStatus.FAILURE) -> void:
	if task == null or tree == null:
		return
	if task != tree.root_task and not _started.has(task):
		return
	_activation_interrupts[task] = status
	_last_status[task] = status
	task.last_status = status
	_abort_task_branch(task)
	if _activation_interrupts.get(task) != status:
		return
	if task == tree.root_task:
		last_status = status
		is_running = false
		_paused = false
		_pending_terminal.erase(task)
		tree_finished.emit(status)
	elif task.parent != null:
		_pending_terminal[task] = status
