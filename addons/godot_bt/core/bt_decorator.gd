class_name BTDecorator
extends BTParentTask
## Base class for Decorators (wraps exactly one child task and modifies its return status or loop policy).

var _execution_status: int = BTStatus.INACTIVE

func _init() -> void:
	super._init()
	category = "Decorator"

func on_start() -> void:
	current_child_index = 0
	_execution_status = BTStatus.RUNNING if not children.is_empty() else BTStatus.INACTIVE

func can_execute() -> bool:
	return current_child_index < children.size() and _execution_status == BTStatus.RUNNING

func on_child_executed(child_index: int, child_status: int) -> void:
	if child_status != BTStatus.RUNNING:
		current_child_index += 1

func on_end() -> void:
	_execution_status = BTStatus.INACTIVE

# ---------------------------------------------------------------- BTInverter
class BTInverter extends BTDecorator:
	func _init() -> void:
		super._init()
		type_name = "Inverter"
		friendly_name = "Inverter"

	func decorate(status: int) -> int:
		if status == BTStatus.SUCCESS:
			return BTStatus.FAILURE
		elif status == BTStatus.FAILURE:
			return BTStatus.SUCCESS
		return status

# ---------------------------------------------------------------- BTReturnSuccess
class BTReturnSuccess extends BTDecorator:
	func _init() -> void:
		super._init()
		type_name = "ReturnSuccess"
		friendly_name = "Return Success"

	func decorate(status: int) -> int:
		if status == BTStatus.FAILURE:
			return BTStatus.SUCCESS
		return status

# ---------------------------------------------------------------- BTReturnFailure
class BTReturnFailure extends BTDecorator:
	func _init() -> void:
		super._init()
		type_name = "ReturnFailure"
		friendly_name = "Return Failure"

	func decorate(status: int) -> int:
		if status == BTStatus.SUCCESS:
			return BTStatus.FAILURE
		return status

# ---------------------------------------------------------------- BTRepeater
class BTRepeater extends BTDecorator:
	var count: int = 1
	var repeat_forever: bool = false
	var end_on_failure: bool = false
	var _iteration: int = 0

	func _init() -> void:
		super._init()
		type_name = "Repeater"
		friendly_name = "Repeater"

	func on_start() -> void:
		super.on_start()
		_iteration = 0

	func can_execute() -> bool:
		if repeat_forever:
			return _execution_status == BTStatus.RUNNING
		return _iteration < count and _execution_status == BTStatus.RUNNING

	func on_child_executed(child_index: int, child_status: int) -> void:
		if child_status == BTStatus.RUNNING:
			_execution_status = BTStatus.RUNNING
			return
		if child_status == BTStatus.INACTIVE:
			_execution_status = BTStatus.INACTIVE
			return
		_iteration += 1
		if end_on_failure and child_status == BTStatus.FAILURE:
			_execution_status = BTStatus.FAILURE
			return
		if repeat_forever or _iteration < count:
			current_child_index = 0 # reset to re-execute child
			_execution_status = BTStatus.RUNNING
		else:
			_execution_status = child_status

	func override_status(status: int) -> int:
		return _execution_status

# ---------------------------------------------------------------- BTUntilSuccess
class BTUntilSuccess extends BTDecorator:
	func _init() -> void:
		super._init()
		type_name = "UntilSuccess"
		friendly_name = "Until Success"

	func can_execute() -> bool:
		return _execution_status == BTStatus.RUNNING

	func on_child_executed(child_index: int, child_status: int) -> void:
		if child_status == BTStatus.RUNNING:
			_execution_status = BTStatus.RUNNING
		elif child_status == BTStatus.INACTIVE:
			_execution_status = BTStatus.INACTIVE
		elif child_status == BTStatus.SUCCESS:
			_execution_status = BTStatus.SUCCESS
		else:
			current_child_index = 0
			_execution_status = BTStatus.RUNNING

	func override_status(status: int) -> int:
		return _execution_status

# ---------------------------------------------------------------- BTUntilFailure
class BTUntilFailure extends BTDecorator:
	func _init() -> void:
		super._init()
		type_name = "UntilFailure"
		friendly_name = "Until Failure"

	func can_execute() -> bool:
		return _execution_status == BTStatus.RUNNING

	func on_child_executed(child_index: int, child_status: int) -> void:
		if child_status == BTStatus.RUNNING:
			_execution_status = BTStatus.RUNNING
		elif child_status == BTStatus.INACTIVE:
			_execution_status = BTStatus.INACTIVE
		elif child_status == BTStatus.FAILURE:
			_execution_status = BTStatus.FAILURE
		else:
			current_child_index = 0
			_execution_status = BTStatus.RUNNING

	func override_status(status: int) -> int:
		return _execution_status

# ---------------------------------------------------------------- BTCooldown
class BTCooldown extends BTDecorator:
	var cooldown_time: float = 1.0
	var _last_execution_time: float = -999999.0

	func _init() -> void:
		super._init()
		type_name = "Cooldown"
		friendly_name = "Cooldown"

	func on_start() -> void:
		cooldown_time = float(get_param("cooldown_time", cooldown_time))
		var current_time: float = Time.get_ticks_msec() / 1000.0
		if current_time - _last_execution_time < cooldown_time:
			# Still on cooldown -> fail immediately
			_execution_status = BTStatus.FAILURE
			current_child_index = children.size()
		else:
			super.on_start()

	func on_child_executed(child_index: int, child_status: int) -> void:
		super.on_child_executed(child_index, child_status)
		if child_status != BTStatus.RUNNING:
			_last_execution_time = Time.get_ticks_msec() / 1000.0
			_execution_status = child_status

	func override_status(status: int) -> int:
		return _execution_status

# ---------------------------------------------------------------- BTTimeLimit
class BTTimeLimit extends BTDecorator:
	var time_limit: float = 5.0
	var _start_time: float = 0.0

	func _init() -> void:
		super._init()
		type_name = "TimeLimit"
		friendly_name = "Time Limit"

	func on_start() -> void:
		time_limit = float(get_param("time_limit", time_limit))
		_start_time = Time.get_ticks_msec() / 1000.0
		super.on_start()

	func on_child_executed(child_index: int, child_status: int) -> void:
		super.on_child_executed(child_index, child_status)
		var elapsed = (Time.get_ticks_msec() / 1000.0) - _start_time
		if child_status == BTStatus.RUNNING and elapsed >= time_limit:
			# Exceeded time limit -> abort child and fail
			if child_index >= 0 and child_index < children.size():
				var child_task: BTTask = children[child_index]
				if child_task != null:
					child_task.on_abort()
			_execution_status = BTStatus.FAILURE
		else:
			_execution_status = child_status

	func override_status(status: int) -> int:
		return _execution_status
