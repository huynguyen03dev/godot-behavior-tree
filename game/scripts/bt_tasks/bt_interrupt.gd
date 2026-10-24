class_name BTInterrupt
extends BTDecorator

var interrupt_status: int = BTStatus.FAILURE
var is_interrupted: bool = false
var child_status: int = BTStatus.INACTIVE

func _init() -> void:
	_setup_kind("BTDecorator", "Interrupt", "Decorator")

func do_interrupt(p_status: int) -> void:
	is_interrupted = true
	interrupt_status = p_status
	if not children.is_empty():
		var child = children[0]
		if child != null:
			if child.has_method("on_abort"):
				child.on_abort()
			child.last_status = p_status

func on_child_executed(_child_index: int, p_child_status: int) -> void:
	child_status = p_child_status

func decorate(status: int) -> int:
	if is_interrupted:
		var ret = interrupt_status
		is_interrupted = false
		return ret
	return status

func override_status(status: int) -> int:
	if is_interrupted:
		var ret = interrupt_status
		is_interrupted = false
		return ret
	return status

func on_end() -> void:
	is_interrupted = false
	interrupt_status = BTStatus.FAILURE
	child_status = BTStatus.INACTIVE
	super.on_end()
