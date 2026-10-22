class_name BTParentTask
extends BTTask
## Base class for tasks that can contain child nodes (Composites, Decorators).

var children: Array = [] # Array[BTTask]
var current_child_index: int = 0

func _init() -> void:
	super._init()
	category = "Composite"

func add_child_task(child_task: BTTask) -> void:
	if child_task == null or child_task == self or children.has(child_task):
		return
	if self is BTDecorator and not children.is_empty():
		return
	var ancestor: BTTask = self
	while ancestor != null:
		if ancestor == child_task:
			return
		ancestor = ancestor.parent
	if child_task.parent != null and child_task.parent != self:
		child_task.parent.remove_child_task(child_task)
	children.append(child_task)
	child_task.parent = self

func remove_child_task(child_task: BTTask) -> void:
	if child_task != null and children.has(child_task):
		children.erase(child_task)
		if child_task.parent == self:
			child_task.parent = null

func get_children_count() -> int:
	return children.size()

func can_execute() -> bool:
	if has_method("CanExecute"):
		return bool(call("CanExecute"))
	return current_child_index < children.size()

func on_tick_start() -> void:
	# Hook for parents that need to prepare a new runner tick (for example Parallel).
	pass

func can_run_parallel_children() -> bool:
	# Sequential parents yield after a running child. Parallel parents override
	# this hook so every active branch can be dispatched in the same tick.
	return false

func on_child_started(child_index: int) -> void:
	# Hook for runtimes whose parent tracks children as they are dispatched.
	# Behavior Designer-compatible consumers use this to mark a parallel child
	# active and advance the dispatch cursor.
	pass

func get_current_child_index() -> int:
	if has_method("CurrentChildIndex"):
		return int(call("CurrentChildIndex"))
	return current_child_index

## Converts a child index to its position in this parent's execution order.
func get_execution_order_index(child_index: int) -> int:
	return child_index

func on_child_executed(child_index: int, child_status: int) -> void:
	if has_method("OnChildExecuted"):
		call("OnChildExecuted", child_index, child_status)
	elif child_status != BTStatus.RUNNING:
		current_child_index += 1

func decorate(status: int) -> int:
	if has_method("Decorate"):
		return int(call("Decorate", status))
	return status

func override_status(status: int) -> int:
	if has_method("OverrideStatus"):
		return int(call("OverrideStatus", status))
	return status

func on_reset() -> void:
	current_child_index = 0
	super.on_reset()
	for child in children:
		if child != null:
			child.on_reset()
