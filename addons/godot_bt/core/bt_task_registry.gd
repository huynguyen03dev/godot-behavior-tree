class_name BTTaskRegistry
extends RefCounted
## Task Registry & Factory for generic Behavior Trees.
## Manages task type registrations, dynamic instantiation, and fallback placeholders.

class BTUnknownTask extends BTTask:
	func _init(p_type: String = "UnknownTask") -> void:
		super._init()
		type_name = p_type
		friendly_name = p_type
		category = "Unknown"
		is_placeholder = true

	func on_update() -> int:
		# Unknown tasks remain Inactive without executing fake actions
		return BTStatus.INACTIVE

var _registry: Dictionary = {} # type_name -> Callable or Script
var _categories: Dictionary = {} # type_name -> category string

func _init() -> void:
	_register_builtins()

func register_task(p_type: String, p_factory_or_script: Variant, p_category: String = "Action") -> void:
	_registry[p_type] = p_factory_or_script
	_categories[p_type] = p_category

func unregister_task(p_type: String) -> void:
	_registry.erase(p_type)
	_categories.erase(p_type)

func has_task(p_type: String) -> bool:
	return _registry.has(p_type)

func get_category(p_type: String) -> String:
	return _categories.get(p_type, "Unknown")

func create_task(p_type: String) -> BTTask:
	if _registry.has(p_type):
		var entry = _registry[p_type]
		var task: BTTask = null
		if entry is Callable:
			task = entry.call()
		elif entry is Script:
			task = entry.new()
		elif entry is GDScript:
			task = entry.new()
		if task != null:
			task.type_name = p_type
			if _categories.has(p_type):
				task.category = _categories[p_type]
			return task
	# Not found -> create BTUnknownTask placeholder
	var ph := BTUnknownTask.new(p_type)
	return ph

func get_registered_types() -> Array:
	return _registry.keys()

func _register_builtins() -> void:
	# Composites
	register_task("Sequence", func(): return BTComposite.BTSequence.new(), "Composite")
	register_task("Selector", func(): return BTComposite.BTSelector.new(), "Composite")
	register_task("Parallel", func(): return BTComposite.BTParallel.new(), "Composite")
	register_task("RandomSequence", func(): return BTComposite.BTRandomSequence.new(), "Composite")
	register_task("RandomSelector", func(): return BTComposite.BTRandomSelector.new(), "Composite")

	# Decorators
	register_task("Inverter", func(): return BTDecorator.BTInverter.new(), "Decorator")
	register_task("ReturnSuccess", func(): return BTDecorator.BTReturnSuccess.new(), "Decorator")
	register_task("ReturnFailure", func(): return BTDecorator.BTReturnFailure.new(), "Decorator")
	register_task("Repeater", func(): return BTDecorator.BTRepeater.new(), "Decorator")
	register_task("UntilSuccess", func(): return BTDecorator.BTUntilSuccess.new(), "Decorator")
	register_task("UntilFailure", func(): return BTDecorator.BTUntilFailure.new(), "Decorator")
