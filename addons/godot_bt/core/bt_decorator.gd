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

## Simulated time on the owning runner (advanced by each tick's delta).
## Time-based decorators use this instead of wall-clock time so pauses, manual
## ticking, and Engine.time_scale behave predictably. Falls back to 0.0 when
## the decorator is not driven by a BTRunner.
func _runner_time() -> float:
	return (owner as BTRunner).time if owner is BTRunner else 0.0

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
		count = int(get_param("count", count))
		repeat_forever = coerce_bool(get_param("repeat_forever", repeat_forever), repeat_forever)
		end_on_failure = coerce_bool(get_param("end_on_failure", end_on_failure), end_on_failure)
		if count <= 0 and not repeat_forever:
			_execution_status = BTStatus.SUCCESS
			current_child_index = children.size()

	## Typed parameter schema for the editor. Reports the public config
	## fields without injecting defaults into `parameters`, so direct
	## property assignment keeps working.
	func get_parameter_schema() -> Dictionary:
		return {
			"count": {"type": "int", "default": count},
			"repeat_forever": {"type": "bool", "default": repeat_forever},
			"end_on_failure": {"type": "bool", "default": end_on_failure},
		}

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
		if _runner_time() - _last_execution_time < cooldown_time:
			# Still on cooldown -> fail immediately
			_execution_status = BTStatus.FAILURE
			current_child_index = children.size()
		else:
			super.on_start()

	func on_child_executed(child_index: int, child_status: int) -> void:
		super.on_child_executed(child_index, child_status)
		if child_status != BTStatus.RUNNING:
			_last_execution_time = _runner_time()
			_execution_status = child_status

	func override_status(status: int) -> int:
		return _execution_status

	## Typed parameter schema for the editor. Reports the public config
	## fields without injecting defaults into `parameters`, so direct
	## property assignment keeps working.
	func get_parameter_schema() -> Dictionary:
		return {
			"cooldown_time": {"type": "float", "default": cooldown_time},
		}

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
		_start_time = _runner_time()
		super.on_start()

	func on_child_executed(child_index: int, child_status: int) -> void:
		super.on_child_executed(child_index, child_status)
		var elapsed := _runner_time() - _start_time
		if child_status == BTStatus.RUNNING and elapsed >= time_limit:
			# Exceeded time limit -> abort child and fail
			if child_index >= 0 and child_index < children.size():
				var child_task: BTTask = children[child_index]
				if owner is BTRunner:
					(owner as BTRunner).interrupt(child_task)
			_execution_status = BTStatus.FAILURE
		else:
			_execution_status = child_status

	func override_status(status: int) -> int:
		return _execution_status

	## Typed parameter schema for the editor. Reports the public config
	## fields without injecting defaults into `parameters`, so direct
	## property assignment keeps working.
	func get_parameter_schema() -> Dictionary:
		return {
			"time_limit": {"type": "float", "default": time_limit},
		}
