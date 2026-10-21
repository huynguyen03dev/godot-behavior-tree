class_name BTComposite
extends BTParentTask
## Base class and implementations for Composite control-flow tasks (Sequence, Selector, Parallel, etc.).

var _execution_status: int = BTStatus.INACTIVE

func _init() -> void:
	super._init()
	category = "Composite"

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
		if _execution_status == BTStatus.RUNNING:
			current_child_index = 0

	func can_run_parallel_children() -> bool:
		return true

	func can_execute() -> bool:
		while current_child_index < children.size() and _children_status[current_child_index] != BTStatus.RUNNING:
			current_child_index += 1
		return current_child_index < children.size() and _execution_status == BTStatus.RUNNING

	func on_child_executed(child_index: int, child_status: int) -> void:
		if child_index < _children_status.size():
			_children_status[child_index] = child_status
		current_child_index += 1
		if current_child_index >= children.size():
			var any_inactive := false
			var any_failure := false
			var any_running := false
			for s in _children_status:
				if s == BTStatus.INACTIVE:
					any_inactive = true
				elif s == BTStatus.FAILURE:
					any_failure = true
				elif s == BTStatus.RUNNING:
					any_running = true
			if any_inactive:
				_execution_status = BTStatus.INACTIVE
			elif any_failure:
				_execution_status = BTStatus.FAILURE
			elif any_running:
				_execution_status = BTStatus.RUNNING
			else:
				_execution_status = BTStatus.SUCCESS

	func override_status(status: int) -> int:
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
