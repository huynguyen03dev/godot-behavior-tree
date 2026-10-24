class_name RatBT
extends RefCounted

static var _cached_registry: BTTaskRegistry = null

static func build_registry() -> BTTaskRegistry:
	if _cached_registry != null:
		return _cached_registry

	var registry := BTTaskRegistry.new()

	# Custom composites and decorators (reused)
	registry.register_task("ParallelComplete", func(): return BTParallelComplete.new(), "Composite")
	registry.register_task("ParallelSelector", func(): return BTParallelSelector.new(), "Composite")
	registry.register_task("Interrupt", func(): return BTInterrupt.new(), "Decorator")
	registry.register_task("PerformInterruption", func(): return BTPerformInterruption.new(), "Action")

	# General tasks (reused)
	registry.register_task("Wait", func(): return BTWait.new(), "Action")
	registry.register_task("ExecuteEvent", func(): return BTExecuteEvent.new(), "Action")
	registry.register_task("SetSharedGameObject", func(): return BTSetSharedGameObject.new(), "Action")
	registry.register_task("CompareSharedBool", func(): return BTCompareSharedBool.new(), "Condition")
	registry.register_task("SetSharedBool", func(): return BTSetSharedBool.new(), "Action")

	# Rat-specific tasks
	registry.register_task("GoatWander", func(): return BTRatWander.new(), "Action")
	registry.register_task("GoatFlee", func(): return BTRatFlee.new(), "Action")
	registry.register_task("UnknownTask", func(): return BTRatUnknownTask.new(), "Condition")
	registry.register_task("SetLocomotionState", func(): return BTRatSetLocomotionState.new(), "Action")
	registry.register_task("StartStopAbility", func(): return BTRatStartStopAbility.new(), "Action")
	registry.register_task("IsAbilityActive", func(): return BTRatIsAbilityActive.new(), "Condition")
	registry.register_task("BoolComparison", func(): return BTRatBoolComparison.new(), "Condition")
	registry.register_task("CompareSharedGameObject", func(): return BTRatCompareSharedGameObject.new(), "Condition")
	registry.register_task("GetBoolStateValue", func(): return BTRatGetBoolStateValue.new(), "Action")
	registry.register_task("BoltDetach", func(): return BTRatBoltDetach.new(), "Action")
	registry.register_task("RestartBehaviorTree", func(): return BTRatRestartBehaviorTree.new(), "Action")
	registry.register_task("StartStopEatingHayAbility", func(): return BTRatStartStopEatingHayAbility.new(), "Action")

	_cached_registry = registry
	return registry

static func attach(rat: Node3D, tree_path := "res://game/bt/rat_main.json") -> BTRunner:
	if not FileAccess.file_exists(tree_path):
		push_error("RatBT: Tree file not found at " + tree_path)
		return null

	var file = FileAccess.open(tree_path, FileAccess.READ)
	if file == null:
		push_error("RatBT: Cannot open " + tree_path)
		return null

	var json_text = file.get_as_text()
	var test_json_conv = JSON.new()
	var parse_err = test_json_conv.parse(json_text)
	if parse_err != OK:
		push_error("RatBT: JSON parse error in " + tree_path)
		return null

	var data = test_json_conv.data
	if not (data is Dictionary):
		push_error("RatBT: Tree root data must be a Dictionary")
		return null

	var registry = build_registry()
	var errors = BTTree.validate_dict(data, registry)
	if not errors.is_empty():
		push_error("RatBT: Tree validation errors: " + str(errors))
		return null

	var tree = BTTree.from_dict(data, registry)
	if tree == null:
		push_error("RatBT: Failed to load tree from dict")
		return null

	var runner := BTRunner.new(tree)
	runner.actor = rat
	return runner
