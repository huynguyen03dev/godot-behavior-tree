class_name GhostBT
extends RefCounted

static var _cached_registry: BTTaskRegistry = null

static func build_registry() -> BTTaskRegistry:
	if _cached_registry != null:
		return _cached_registry

	var registry := BTTaskRegistry.new()

	# Custom composites and decorators
	registry.register_task("ParallelComplete", func(): return BTParallelComplete.new(), "Composite")
	registry.register_task("ParallelSelector", func(): return BTParallelSelector.new(), "Composite")
	registry.register_task("Interrupt", func(): return BTInterrupt.new(), "Decorator")
	registry.register_task("PerformInterruption", func(): return BTPerformInterruption.new(), "Action")

	# Perception tasks
	registry.register_task("PlayerFlashlightOnMe", func(): return BTPlayerFlashlightOnMe.new(), "Condition")
	registry.register_task("OtherPlayerFlashlightOnMe", func(): return BTPlayerFlashlightOnMe.new(), "Condition")
	registry.register_task("CanSeePlayer", func(): return BTCanSeePlayer.new(), "Condition")
	registry.register_task("CanSeeOtherSurvivalPlayer", func(): return BTCanSeePlayer.new(), "Condition")
	registry.register_task("CanHearPlayer", func(): return BTCanHearPlayer.new(), "Condition")
	registry.register_task("CanHearOtherPlayer", func(): return BTCanHearPlayer.new(), "Condition")
	registry.register_task("PlayerTouchingMe", func(): return BTPlayerTouchingMe.new(), "Condition")
	registry.register_task("OtherPlayerTouchingMe", func(): return BTPlayerTouchingMe.new(), "Condition")
	registry.register_task("AdvancedWithinDistance", func(): return BTAdvancedWithinDistance.new(), "Condition")

	# Navigation & Movement tasks
	registry.register_task("GhostGetWanderDestination", func(): return BTGhostGetWanderDestination.new(), "Action")
	registry.register_task("GhostGetFleeDestination", func(): return BTGhostGetFleeDestination.new(), "Action")
	registry.register_task("GhostMoveTowards", func(): return BTGhostMoveTowards.new(), "Action")
	registry.register_task("GhostPursue", func(): return BTGhostPursue.new(), "Action")
	registry.register_task("RotateTowards", func(): return BTRotateTowards.new(), "Action")

	# State & Parameter tasks
	registry.register_task("SetSpeed", func(): return BTSetSpeed.new(), "Action")
	registry.register_task("SetIntegerParameter", func(): return BTSetIntegerParameter.new(), "Action")
	registry.register_task("GetIntegerParameter", func(): return BTGetIntegerParameter.new(), "Action")
	registry.register_task("CompareIntegerParameter", func(): return BTCompareIntegerParameter.new(), "Condition")
	registry.register_task("SetSharedBool", func(): return BTSetSharedBool.new(), "Action")
	registry.register_task("CompareSharedBool", func(): return BTCompareSharedBool.new(), "Condition")
	registry.register_task("CompareSharedInt", func(): return BTCompareSharedInt.new(), "Condition")
	registry.register_task("SetSharedGameObject", func(): return BTSetSharedGameObject.new(), "Action")
	registry.register_task("DistanceToGameObject", func(): return BTDistanceToGameObject.new(), "Action")
	registry.register_task("FloatComparison", func(): return BTFloatComparison.new(), "Condition")

	# Timers
	registry.register_task("Wait", func(): return BTWait.new(), "Action")
	registry.register_task("PlayersFocusingMeWait", func(): return BTPlayersFocusingMeWait.new(), "Action")

	# Ritual & Events
	registry.register_task("CanCarryInteractable", func():
		var t = BTRitualBookAction.new()
		t.set_param("action_type", "can_carry")
		return t
	, "Action")
	registry.register_task("BoltDetach", func():
		var t = BTRitualBookAction.new()
		t.set_param("action_type", "detach")
		return t
	, "Action")
	registry.register_task("GetStringStateValue", func():
		var t = BTRitualBookAction.new()
		t.set_param("action_type", "get_metadata")
		return t
	, "Action")
	registry.register_task("SetStringStateValue", func():
		var t = BTRitualBookAction.new()
		t.set_param("action_type", "set_carry_name")
		return t
	, "Action")
	registry.register_task("RitualBookAction", func(): return BTRitualBookAction.new(), "Action")
	registry.register_task("ExecuteLocalEventGameObject", func(): return BTExecuteEvent.new(), "Action")
	registry.register_task("ExecuteEvent", func(): return BTExecuteEvent.new(), "Action")
	registry.register_task("StopBehaviorTree", func(): return BTStopBehaviorTree.new(), "Action")
	registry.register_task("IsPlayerBeingKnockedOut", func(): return BTIsPlayerBeingKnockedOut.new(), "Condition")
	registry.register_task("IsAbilityActive", func(): return BTIsAbilityActive.new(), "Condition")

	_cached_registry = registry
	return registry

static func attach(actor: Node, tree_path := "res://game/bt/ghost_main.json") -> BTRunner:
	if not FileAccess.file_exists(tree_path):
		push_error("GhostBT: Tree file not found at " + tree_path)
		return null

	var file = FileAccess.open(tree_path, FileAccess.READ)
	if file == null:
		push_error("GhostBT: Cannot open " + tree_path)
		return null

	var json_text = file.get_as_text()
	var test_json_conv = JSON.new()
	var parse_err = test_json_conv.parse(json_text)
	if parse_err != OK:
		push_error("GhostBT: JSON parse error in " + tree_path)
		return null

	var data = test_json_conv.data
	if not (data is Dictionary):
		push_error("GhostBT: Tree root data must be a Dictionary")
		return null

	var registry = build_registry()
	var errors = BTTree.validate_dict(data, registry)
	if not errors.is_empty():
		push_error("GhostBT: Tree validation errors: " + str(errors))
		return null

	var tree = BTTree.from_dict(data, registry)
	if tree == null:
		push_error("GhostBT: Failed to load tree from dict")
		return null

	var runner := BTRunner.new(tree)
	runner.actor = actor
	return runner
