class_name BTTaskRegistry
extends BTTaskRegistryNative

class BTUnknownTask extends BTTask:
	func _init(p_type := "UnknownTask") -> void:
		_make_placeholder(p_type)

func _init() -> void:
	_register_builtins()

func register_task(p_type: String, factory, category: String = "Action") -> void:
	bt_register_task(p_type, factory, category)

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
	register_task("Cooldown", func(): return BTDecorator.BTCooldown.new(), "Decorator")
	register_task("TimeLimit", func(): return BTDecorator.BTTimeLimit.new(), "Decorator")

	# SubTree
	register_task("SubTree", func(): return BTSubTree.new(), "Action")


func _make_unknown(p_type: String) -> BTTask:
	return BTUnknownTask.new(p_type)
