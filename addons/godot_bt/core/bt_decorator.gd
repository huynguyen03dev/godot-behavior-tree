class_name BTDecorator
extends BTParentTask

func _init() -> void:
	_setup_kind("BTDecorator", "BTDecorator", "Decorator")

class BTInverter extends BTDecorator:
	func _init() -> void:
		_setup_kind("Inverter", "Inverter", "Decorator")

class BTReturnSuccess extends BTDecorator:
	func _init() -> void:
		_setup_kind("ReturnSuccess", "Return Success", "Decorator")

class BTReturnFailure extends BTDecorator:
	func _init() -> void:
		_setup_kind("ReturnFailure", "Return Failure", "Decorator")

class BTRepeater extends BTDecorator:
	func _init() -> void:
		_setup_kind("Repeater", "Repeater", "Decorator")

class BTUntilSuccess extends BTDecorator:
	func _init() -> void:
		_setup_kind("UntilSuccess", "Until Success", "Decorator")

class BTUntilFailure extends BTDecorator:
	func _init() -> void:
		_setup_kind("UntilFailure", "Until Failure", "Decorator")

class BTCooldown extends BTDecorator:
	func _init() -> void:
		_setup_kind("Cooldown", "Cooldown", "Decorator")

class BTTimeLimit extends BTDecorator:
	func _init() -> void:
		_setup_kind("TimeLimit", "Time Limit", "Decorator")
