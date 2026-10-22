class_name BTComposite
extends BTParentTask
## Base class and implementations for Composite control-flow tasks (Sequence, Selector, Parallel, etc.).

enum AbortType { NONE = 0, SELF = 1, LOWER_PRIORITY = 2, BOTH = 3 }

var abort_type: int = AbortType.NONE
var _execution_status: int = BTStatus.INACTIVE

func _init() -> void:
	super._init()
	category = "Composite"

func get_abort_type() -> int:
	return abort_type

func set_abort_type(val: int) -> void:
	abort_type = val
	parameters["abort_type"] = val

func on_start() -> void:
	current_child_index = 0
	_execution_status = BTStatus.RUNNING

func can_execute() -> bool:
	return current_child_index < children.size() and _execution_status == BTStatus.RUNNING

func on_child_executed(child_index: int, child_status: int) -> void:
	if child_status == BTStatus.INACTIVE:
		_execution_status = BTStatus.INACTIVE
	elif child_status != BTStatus.RUNNING:
		current_child_index += 1

func on_end() -> void:
	_execution_status = BTStatus.INACTIVE

# ---------------------------------------------------------------- BTSequence
class BTSequence extends BTComposite:
	func _init() -> void:
		super._init()
		type_name = "Sequence"
		friendly_name = "Sequence"

	func on_start() -> void:
		super.on_start()
		if children.is_empty():
			_execution_status = BTStatus.SUCCESS

	func on_child_executed(child_index: int, child_status: int) -> void:
		super.on_child_executed(child_index, child_status)
		if child_status == BTStatus.FAILURE:
			_execution_status = BTStatus.FAILURE
		elif child_status == BTStatus.RUNNING:
			_execution_status = BTStatus.RUNNING
		elif current_child_index >= children.size():
			_execution_status = BTStatus.SUCCESS

	func override_status(status: int) -> int:
		return _execution_status

# ---------------------------------------------------------------- BTSelector
class BTSelector extends BTComposite:
	func _init() -> void:
		super._init()
		type_name = "Selector"
		friendly_name = "Selector"

	func on_start() -> void:
		super.on_start()
		if children.is_empty():
			_execution_status = BTStatus.FAILURE

	func on_child_executed(child_index: int, child_status: int) -> void:
		super.on_child_executed(child_index, child_status)
		if child_status == BTStatus.SUCCESS:
			_execution_status = BTStatus.SUCCESS
		elif child_status == BTStatus.RUNNING:
			_execution_status = BTStatus.RUNNING
		elif current_child_index >= children.size():
			_execution_status = BTStatus.FAILURE

	func override_status(status: int) -> int:
		return _execution_status

# ---------------------------------------------------------------- BTParallel
class BTParallel extends BTComposite:
	var _children_status: Array = []
	var _dispatched_this_tick: Array[bool] = []
	var _warned_placeholders: Dictionary = {} # placeholder task -> true

	func _init() -> void:
		super._init()
		type_name = "Parallel"
		friendly_name = "Parallel"

	func on_start() -> void:
		super.on_start()
		_children_status.clear()
		for i in children.size():
			_children_status.append(BTStatus.RUNNING)
		if children.is_empty():
			_execution_status = BTStatus.SUCCESS

	func on_tick_start() -> void:
		_dispatched_this_tick.resize(children.size())
		_dispatched_this_tick.fill(false)

	func can_run_parallel_children() -> bool:
		return true

	func can_execute() -> bool:
		if _execution_status != BTStatus.RUNNING or children.is_empty():
			return false
		for offset in children.size():
			var index := (current_child_index + offset) % children.size()
			if not _dispatched_this_tick[index] and _children_status[index] == BTStatus.RUNNING:
				current_child_index = index
				return true
		return false

	func on_child_started(child_index: int) -> void:
		if child_index >= 0 and child_index < _dispatched_this_tick.size():
			_dispatched_this_tick[child_index] = true
		if child_index >= 0 and child_index < children.size():
			var child: BTTask = children[child_index]
			if child.is_placeholder and not _warned_placeholders.has(child):
				_warned_placeholders[child] = true
				push_warning("BTParallel '%s': child '%s' is an unregistered placeholder and is ignored while other branches run." % [friendly_name, child.type_name])

	## Aggregates branch statuses. Inactive branches (for example unregistered
	## placeholder tasks) do not contribute while at least one sibling is
	## active; only when every branch is inactive does the Parallel go inactive.
	func _aggregate_status() -> int:
		var any_running := false
		var saw_active := false
		for status in _children_status:
			if status == BTStatus.INACTIVE:
				continue
			saw_active = true
			if status == BTStatus.FAILURE:
				return BTStatus.FAILURE
			if status == BTStatus.RUNNING:
				any_running = true
		if not saw_active:
			return BTStatus.INACTIVE
		return BTStatus.RUNNING if any_running else BTStatus.SUCCESS

	func on_child_executed(child_index: int, child_status: int) -> void:
		if child_index < _children_status.size():
			_children_status[child_index] = child_status
		if not children.is_empty():
			current_child_index = (child_index + 1) % children.size()
		_execution_status = _aggregate_status()

	func override_status(status: int) -> int:
		_execution_status = _aggregate_status()
		return _execution_status

# ---------------------------------------------------------------- BTRandomSequence
class BTRandomSequence extends BTSequence:
	var _shuffled_order: Array = []

	func _init() -> void:
		super._init()
		type_name = "RandomSequence"
		friendly_name = "Random Sequence"

	func on_start() -> void:
		super.on_start()
		_shuffled_order.clear()
		for i in children.size():
			_shuffled_order.append(i)
		_shuffled_order.shuffle()

	func get_current_child_index() -> int:
		if current_child_index < _shuffled_order.size():
			return _shuffled_order[current_child_index]
		return current_child_index

	func get_execution_order_index(child_index: int) -> int:
		return _shuffled_order.find(child_index)

# ---------------------------------------------------------------- BTRandomSelector
class BTRandomSelector extends BTSelector:
	var _shuffled_order: Array = []

	func _init() -> void:
		super._init()
		type_name = "RandomSelector"
		friendly_name = "Random Selector"

	func on_start() -> void:
		super.on_start()
		_shuffled_order.clear()
		for i in children.size():
			_shuffled_order.append(i)
		_shuffled_order.shuffle()

	func get_current_child_index() -> int:
		if current_child_index < _shuffled_order.size():
			return _shuffled_order[current_child_index]
		return current_child_index

	func get_execution_order_index(child_index: int) -> int:
		return _shuffled_order.find(child_index)
