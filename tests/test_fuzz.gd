extends SceneTree
## Property-based fuzz and soak testing harness for Godot Behavior Tree.
## Generates randomized trees, drives them with chaos, and checks runtime invariants.
## Run with: godot --headless --path . -s res://tests/test_fuzz.gd

const BTTreeScript = preload("res://addons/godot_bt/core/bt_tree.gd")
const BTRunnerScript = preload("res://addons/godot_bt/core/bt_runner.gd")
const BTCompositeScript = preload("res://addons/godot_bt/core/bt_composite.gd")
const BTDecoratorScript = preload("res://addons/godot_bt/core/bt_decorator.gd")
const BTTaskScript = preload("res://addons/godot_bt/core/bt_task.gd")
const BTParentTaskScript = preload("res://addons/godot_bt/core/bt_parent_task.gd")
const BTSubTreeScript = preload("res://addons/godot_bt/core/bt_subtree.gd")
const BTTaskRegistryScript = preload("res://addons/godot_bt/core/bt_task_registry.gd")
const BTStatusScript = preload("res://addons/godot_bt/core/bt_status.gd")
const BTBlackboardScript = preload("res://addons/godot_bt/core/bt_blackboard.gd")

# ==============================================================================
# Instrumented Probe Tasks
# ==============================================================================

class FuzzProbeBase extends BTTask:
	static var live_count: int = 0
	static var leaf_updates_this_tick: int = 0

	var starts: int = 0
	var ends: int = 0
	var aborts: int = 0
	var updates: int = 0
	var awakes: int = 0
	var resets: int = 0
	var pauses: int = 0
	var is_open: bool = false
	var double_open_count: int = 0
	var double_close_count: int = 0
	var update_without_start_count: int = 0
	var reentrancy_stop_armed: bool = false
	var id_tag: int = 0

	func _init() -> void:
		super._init()
		live_count += 1

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			live_count -= 1

	func _check_start() -> void:
		if is_open:
			double_open_count += 1
		is_open = true
		starts += 1
		if reentrancy_stop_armed and is_instance_valid(owner) and owner is BTRunner:
			reentrancy_stop_armed = false
			(owner as BTRunner).stop()

	func _check_update() -> void:
		if not is_open:
			update_without_start_count += 1
		updates += 1
		leaf_updates_this_tick += 1
		if reentrancy_stop_armed and is_instance_valid(owner) and owner is BTRunner:
			reentrancy_stop_armed = false
			(owner as BTRunner).stop()

	func _check_end() -> void:
		if not is_open:
			double_close_count += 1
		is_open = false
		ends += 1

	func _check_abort() -> void:
		if not is_open:
			double_close_count += 1
		is_open = false
		aborts += 1

	func on_awake() -> void:
		awakes += 1
		super.on_awake()

	func on_reset() -> void:
		resets += 1
		super.on_reset()

	func on_pause(paused: bool) -> void:
		pauses += 1
		super.on_pause(paused)

class FuzzProbeAction extends FuzzProbeBase:
	var ticks_to_run: int = 0
	var target_status: int = BTStatusScript.SUCCESS
	var remaining_ticks: int = 0

	func _init() -> void:
		super._init()
		type_name = "FuzzProbeAction"
		category = "Action"

	func on_start() -> void:
		_check_start()
		remaining_ticks = ticks_to_run

	func on_update() -> int:
		_check_update()
		if remaining_ticks > 0:
			remaining_ticks -= 1
			return BTStatusScript.RUNNING
		var bound = get_param("result_status", target_status)
		if bound is int:
			return bound
		return target_status

	func on_end() -> void:
		_check_end()

	func on_abort() -> void:
		_check_abort()

class FuzzProbeCondition extends FuzzProbeBase:
	var check_key: String = ""
	var expect_truthy: bool = true

	func _init() -> void:
		super._init()
		type_name = "FuzzProbeCondition"
		category = "Condition"

	func evaluate_condition(_runner: BTRunner) -> int:
		var val: Variant = null
		if check_key != "":
			val = get_blackboard_var(check_key, null)
		if val == null:
			val = get_param("cond_val", expect_truthy)
		var is_true: bool = BTTask.coerce_bool(val, false)
		var matches: bool = (is_true == expect_truthy)
		return BTStatusScript.SUCCESS if matches else BTStatusScript.FAILURE

	func on_start() -> void:
		_check_start()

	func on_update() -> int:
		_check_update()
		return evaluate_condition(owner as BTRunner)

	func on_end() -> void:
		_check_end()

	func on_abort() -> void:
		_check_abort()

# ==============================================================================
# Harness State & Engine
# ==============================================================================

var registry: BTTaskRegistry
var tracked_probes: Array[WeakRef] = []
var rng: RandomNumberGenerator
var subtree_counter: int = 0
var active_seed: int = 0

# Runner signal tracking
var signal_task_started: Dictionary = {} # task -> int
var signal_task_finished: Dictionary = {} # task -> int
var signal_task_aborted: Dictionary = {} # task -> int
var signal_tree_finished: Array = [] # Array[int]

func _init() -> void:
	print("================================================================================")
	print(" Godot Behavior Tree - Fuzz / Soak Test Suite")
	print("================================================================================")

	# Seed configuration: FUZZ_SEED env override or deterministic default
	active_seed = 20261023
	if OS.has_environment("FUZZ_SEED") and OS.get_environment("FUZZ_SEED").strip_edges() != "":
		active_seed = int(OS.get_environment("FUZZ_SEED"))
	print("Random Seed: %d" % active_seed)

	rng = RandomNumberGenerator.new()
	rng.seed = active_seed

	# Scale configuration: default 30 trees x 2,000 ticks
	var num_trees := 30
	if OS.has_environment("FUZZ_TREES") and OS.get_environment("FUZZ_TREES").strip_edges() != "":
		num_trees = int(OS.get_environment("FUZZ_TREES"))

	var ticks_per_tree := 2000
	if OS.has_environment("FUZZ_TICKS") and OS.get_environment("FUZZ_TICKS").strip_edges() != "":
		ticks_per_tree = int(OS.get_environment("FUZZ_TICKS"))

	print("Configuration: %d trees × %d ticks (scale total: %d ticks)" % [num_trees, ticks_per_tree, num_trees * ticks_per_tree])

	# Setup registry and tracking
	registry = BTTaskRegistryScript.new()
	registry.register_task("FuzzProbeAction", func():
		var p = FuzzProbeAction.new()
		tracked_probes.append(weakref(p))
		return p
	, "Action")
	registry.register_task("FuzzProbeCondition", func():
		var p = FuzzProbeCondition.new()
		tracked_probes.append(weakref(p))
		return p
	, "Condition")

	DirAccess.make_dir_recursive_absolute("user://fuzz_subtrees")
	_cleanup_fuzz_files()

	var start_time_msec := Time.get_ticks_msec()
	var total_passed := 0
	var total_failed := 0
	var total_executed_ticks := 0

	for tree_idx in num_trees:
		var ok := _run_fuzz_tree(tree_idx, ticks_per_tree)
		if ok:
			total_passed += 1
			total_executed_ticks += ticks_per_tree
		else:
			total_failed += 1
			break

	_cleanup_fuzz_files()
	var elapsed_sec := float(Time.get_ticks_msec() - start_time_msec) / 1000.0

	print("--------------------------------------------------------------------------------")
	print("Fuzz Suite Execution: %.3f seconds (%d ticks executed)" % [elapsed_sec, total_executed_ticks])
	print("Results: %d total, %d passed, %d failed" % [num_trees, total_passed, total_failed])
	print("================================================================================")

	quit(0 if total_failed == 0 else 1)

func _cleanup_fuzz_files() -> void:
	var dir := DirAccess.open("user://fuzz_subtrees")
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				dir.remove(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()

func _run_fuzz_tree(tree_idx: int, ticks_per_tree: int) -> bool:
	tracked_probes.clear()
	signal_task_started.clear()
	signal_task_finished.clear()
	signal_task_aborted.clear()
	signal_tree_finished.clear()

	# Tree generation: bounded depth <= 8, bounded width <= 6
	var max_depth := rng.randi_range(3, 7)
	var max_width := rng.randi_range(2, 5)
	var tree: BTTree = _generate_tree(tree_idx, max_depth, max_width)

	# Invariant 4d: Initial serialization round-trip check
	if not _check_serialization_roundtrip(tree, tree_idx, 0):
		return false

	var runner := BTRunnerScript.new(tree)
	runner.task_started.connect(func(t):
		signal_task_started[t] = signal_task_started.get(t, 0) + 1
	)
	runner.task_finished.connect(func(t, st):
		signal_task_finished[t] = signal_task_finished.get(t, 0) + 1
		if not (st in [BTStatusScript.INACTIVE, BTStatusScript.FAILURE, BTStatusScript.SUCCESS, BTStatusScript.RUNNING]):
			_fail("task_finished emitted with invalid status %d" % st, tree_idx, runner.ticks, tree)
	)
	runner.task_aborted.connect(func(t):
		signal_task_aborted[t] = signal_task_aborted.get(t, 0) + 1
	)
	runner.tree_finished.connect(func(st):
		signal_tree_finished.append(st)
	)

	# Budget configuration: mix 0 (unlimited) and bounded budgets (1 to 10)
	var budget_mode := tree_idx % 4
	match budget_mode:
		0: runner.max_task_executions_per_tick = 0
		1: runner.max_task_executions_per_tick = 1
		2: runner.max_task_executions_per_tick = 3
		3: runner.max_task_executions_per_tick = rng.randi_range(4, 8)

	runner.start()

	# Mid-run serialization checkpoint ticks
	var mid_checkpoint_a := ticks_per_tree / 3
	var mid_checkpoint_b := (ticks_per_tree * 2) / 3

	for tick in ticks_per_tree:
		FuzzProbeBase.leaf_updates_this_tick = 0
		var delta := rng.randf_range(0.0, 0.05)

		# Chaos driver actions:
		# 1. Blackboard mutations
		if rng.randf() < 0.15:
			var mut_key: String = ["flag_a", "flag_b", "shared_flag", "speed", "counter", "sub_shared_int"][rng.randi_range(0, 5)]
			if mut_key.begins_with("flag") or mut_key.ends_with("bool"):
				tree.blackboard.set_var(mut_key, rng.randf() < 0.5)
			elif mut_key.ends_with("int") or mut_key == "counter":
				tree.blackboard.set_var(mut_key, rng.randi_range(0, 100))
			else:
				tree.blackboard.set_var(mut_key, rng.randf_range(0.0, 200.0))

		# 2. Occasionally remove a blackboard key (testing default fallback)
		if rng.randf() < 0.02:
			tree.blackboard.remove_var("flag_b")

		# 3. Random pause / resume
		if rng.randf() < 0.03:
			if runner.is_running:
				runner.pause(true)
			elif runner._paused:
				runner.pause(false)

		# 4. Random task interrupt
		if rng.randf() < 0.03 and not runner._started.is_empty():
			var started_list := runner._started.keys()
			var target: BTTask = started_list[rng.randi_range(0, started_list.size() - 1)]
			runner.interrupt(target)

		# 5. Re-entrancy torture: arm a probe hook to call stop() from within
		if rng.randf() < 0.005 and not tracked_probes.is_empty():
			var wr: WeakRef = tracked_probes[rng.randi_range(0, tracked_probes.size() - 1)]
			var p: FuzzProbeBase = wr.get_ref() as FuzzProbeBase
			if p != null:
				p.reentrancy_stop_armed = true

		var will_tick := runner.is_running
		var prev_ticks := runner.ticks

		# Execute tick
		var status := runner.tick(delta)

		# Invariant 4e: Ticks counter strictly increases when running
		if will_tick:
			if runner.ticks != prev_ticks + 1:
				_fail("Ticks counter did not strictly increase: prev=%d, now=%d" % [prev_ticks, runner.ticks], tree_idx, tick, tree)
				return false
		else:
			if runner.ticks != prev_ticks:
				_fail("Ticks counter changed while runner was not running: prev=%d, now=%d" % [prev_ticks, runner.ticks], tree_idx, tick, tree)
				return false

		# Invariant 4e: Return status sanity
		if not (status in [BTStatusScript.INACTIVE, BTStatusScript.FAILURE, BTStatusScript.SUCCESS, BTStatusScript.RUNNING]):
			_fail("Tick returned invalid status enum: %d" % status, tree_idx, tick, tree)
			return false

		if not (runner.last_status in [BTStatusScript.INACTIVE, BTStatusScript.FAILURE, BTStatusScript.SUCCESS, BTStatusScript.RUNNING]):
			_fail("runner.last_status has invalid status enum: %d" % runner.last_status, tree_idx, tick, tree)
			return false

		# Invariant 4b: Budget
		if runner.max_task_executions_per_tick > 0:
			if FuzzProbeBase.leaf_updates_this_tick > runner.max_task_executions_per_tick:
				_fail("Budget exceeded on tick %d: updates=%d, budget=%d" % [tick, FuzzProbeBase.leaf_updates_this_tick, runner.max_task_executions_per_tick], tree_idx, tick, tree)
				return false

		# Invariant 4d: Checkpoint serialization round-trip
		if tick == mid_checkpoint_a or tick == mid_checkpoint_b:
			if not _check_serialization_roundtrip(tree, tree_idx, tick):
				return false

		# Restart runner if stopped / finished (with high probability to sustain fuzzing)
		if not runner.is_running and rng.randf() < 0.90:
			runner.start()

	# End of tick loop: cleanly stop runner
	runner.stop()

	# Invariant 4a: Lifecycle balance across all probe instances
	for i in tracked_probes.size():
		var wr: WeakRef = tracked_probes[i]
		var p: FuzzProbeBase = wr.get_ref() as FuzzProbeBase
		if p != null:
			if p.starts != (p.ends + p.aborts):
				_fail("Lifecycle balance violation: starts=%d, ends=%d, aborts=%d (open=%d)" % [p.starts, p.ends, p.aborts, p.starts - (p.ends + p.aborts)], tree_idx, ticks_per_tree, tree)
				return false
			if p.is_open:
				_fail("Probe remains open after stop()", tree_idx, ticks_per_tree, tree)
				return false
			if p.double_open_count > 0:
				_fail("Double on_start() detected on probe: count=%d" % p.double_open_count, tree_idx, ticks_per_tree, tree)
				return false
			if p.double_close_count > 0:
				_fail("Double on_end() or on_abort() detected on probe: count=%d" % p.double_close_count, tree_idx, ticks_per_tree, tree)
				return false
			if p.update_without_start_count > 0:
				_fail("on_update() invoked on unopened probe: count=%d" % p.update_without_start_count, tree_idx, ticks_per_tree, tree)
				return false

	# Invariant 4d: Final serialization round-trip check
	if not _check_serialization_roundtrip(tree, tree_idx, ticks_per_tree):
		return false

	# Clean up runner, tree, and signal tracking dictionaries
	signal_task_started.clear()
	signal_task_finished.clear()
	signal_task_aborted.clear()
	signal_tree_finished.clear()

	runner.free()
	runner = null
	tree = null

	# Invariant 4c: No leaks (static probe instance count returns to 0)
	if FuzzProbeBase.live_count != 0:
		print("❌ LEAK DETECTED: Tree %d finished but FuzzProbeBase.live_count = %d (expected 0)" % [tree_idx, FuzzProbeBase.live_count])
		quit(1)
		return false

	tracked_probes.clear()
	return true

func _check_serialization_roundtrip(tree: BTTree, tree_idx: int, tick: int) -> bool:
	var dict1 := tree.to_dict()
	var errs := BTTreeScript.validate_dict(dict1, registry)
	if not errs.is_empty():
		_fail("validate_dict reported errors: " + "; ".join(errs), tree_idx, tick, tree)
		return false

	var tree_rt: BTTree = BTTreeScript.from_dict(dict1, registry)
	if tree_rt == null:
		_fail("from_dict returned null", tree_idx, tick, tree)
		return false

	if tree_rt.get_node_count() != tree.get_node_count():
		_fail("Node count mismatch on roundtrip: orig=%d, rt=%d" % [tree.get_node_count(), tree_rt.get_node_count()], tree_idx, tick, tree)
		return false

	for i in tree.node_list.size():
		var n_orig: BTTask = tree.node_list[i]
		if n_orig != null:
			var n_rt: BTTask = tree_rt.get_node_by_id(n_orig.id)
			if n_rt == null:
				_fail("Node id %d missing in roundtrip tree" % n_orig.id, tree_idx, tick, tree)
				return false
			if n_orig.type_name != n_rt.type_name:
				_fail("Node id %d type_name mismatch: orig='%s', rt='%s'" % [n_orig.id, n_orig.type_name, n_rt.type_name], tree_idx, tick, tree)
				return false
			if n_orig.category != n_rt.category:
				_fail("Node id %d category mismatch: orig='%s', rt='%s'" % [n_orig.id, n_orig.category, n_rt.category], tree_idx, tick, tree)
				return false

	var dict2 := tree_rt.to_dict()
	if dict1 != dict2:
		_fail("Roundtrip dict mismatch between to_dict() results", tree_idx, tick, tree)
		return false

	return true

func _fail(reason: String, tree_idx: int, tick: int, tree: BTTree) -> void:
	print("❌ FAIL: Invariant violation [seed %d, tree %d, tick %d]: %s" % [active_seed, tree_idx, tick, reason])
	if tree != null:
		print("--- Tree JSON Dump ---")
		print(JSON.stringify(tree.to_dict(), "\t"))
		print("----------------------")

# ==============================================================================
# Random Tree Generation
# ==============================================================================

func _generate_tree(tree_idx: int, max_depth: int, max_width: int) -> BTTree:
	var tree := BTTreeScript.new()
	tree.registry = registry
	tree.tree_name = "FuzzTree_%d" % tree_idx
	tree.blackboard.set_var("flag_a", true, "bool")
	tree.blackboard.set_var("flag_b", false, "bool")
	tree.blackboard.set_var("shared_flag", true, "bool")
	tree.blackboard.set_var("speed", 15.0, "float")
	tree.blackboard.set_var("counter", 10, "int")

	var root := _generate_node(tree, 0, max_depth, max_width, true)
	tree.set_root(root)
	return tree

func _generate_node(tree: BTTree, depth: int, max_depth: int, max_width: int, is_root: bool) -> BTTask:
	if depth >= max_depth:
		return _generate_leaf(tree)

	var roll := rng.randf()
	if is_root or roll < 0.45:
		return _generate_composite(tree, depth, max_depth, max_width)
	elif roll < 0.72:
		return _generate_decorator(tree, depth, max_depth, max_width)
	elif roll < 0.85 and depth <= 3:
		return _generate_subtree(tree)
	else:
		return _generate_leaf(tree)

func _generate_composite(tree: BTTree, depth: int, max_depth: int, max_width: int) -> BTTask:
	var comp_types := ["Sequence", "Selector", "Parallel", "RandomSequence", "RandomSelector"]
	var t_name: String = comp_types[rng.randi_range(0, comp_types.size() - 1)]
	var comp: BTComposite = registry.create_task(t_name) as BTComposite
	comp.set_abort_type(rng.randi_range(0, 3))
	tree.add_node(comp)

	var num_children := rng.randi_range(1, max_width)
	for i in num_children:
		var child := _generate_node(tree, depth + 1, max_depth, max_width, false)
		tree.connect_parent_child(comp, child)
	return comp

func _generate_decorator(tree: BTTree, depth: int, max_depth: int, max_width: int) -> BTTask:
	var dec_types := ["Inverter", "ReturnSuccess", "ReturnFailure", "Repeater", "UntilSuccess", "UntilFailure", "TimeLimit", "Cooldown"]
	var t_name: String = dec_types[rng.randi_range(0, dec_types.size() - 1)]
	var dec: BTDecorator = registry.create_task(t_name) as BTDecorator

	if t_name == "Repeater":
		var count := rng.randi_range(1, 5)
		dec.set_param("count", count)
		(dec as BTDecorator.BTRepeater).count = count
		var rep_forever := rng.randf() < 0.08
		dec.set_param("repeat_forever", rep_forever)
		(dec as BTDecorator.BTRepeater).repeat_forever = rep_forever
		var end_fail := rng.randf() < 0.5
		dec.set_param("end_on_failure", end_fail)
		(dec as BTDecorator.BTRepeater).end_on_failure = end_fail
	elif t_name == "TimeLimit":
		var tl := rng.randf_range(0.05, 0.5)
		dec.set_param("time_limit", tl)
		(dec as BTDecorator.BTTimeLimit).time_limit = tl
	elif t_name == "Cooldown":
		var cd := rng.randf_range(0.0, 0.3)
		dec.set_param("cooldown_time", cd)
		(dec as BTDecorator.BTCooldown).cooldown_time = cd

	tree.add_node(dec)
	var child := _generate_node(tree, depth + 1, max_depth, max_width, false)
	tree.connect_parent_child(dec, child)
	return dec

func _generate_leaf(tree: BTTree) -> BTTask:
	var is_cond := rng.randf() < 0.45
	var task: BTTask

	if is_cond:
		var cond: FuzzProbeCondition = registry.create_task("FuzzProbeCondition") as FuzzProbeCondition
		cond.check_key = ["flag_a", "flag_b", "shared_flag", "sub_local_bool"][rng.randi_range(0, 3)]
		cond.expect_truthy = rng.randf() < 0.5
		if rng.randf() < 0.4:
			cond.set_param("cond_val", "@" + cond.check_key)
		task = cond
	else:
		var act: FuzzProbeAction = registry.create_task("FuzzProbeAction") as FuzzProbeAction
		act.ticks_to_run = rng.randi_range(0, 3)
		act.target_status = BTStatusScript.SUCCESS if rng.randf() < 0.6 else BTStatusScript.FAILURE

		var binding_roll := rng.randf()
		if binding_roll < 0.25:
			act.set_param("speed_val", "@speed")
		elif binding_roll < 0.50:
			act.set_param("counter_val", "$counter")
		elif binding_roll < 0.65:
			act.set_param("escaped_literal", "@@escaped")
		elif binding_roll < 0.80:
			act.set_param("result_status", BTStatusScript.SUCCESS if rng.randf() < 0.5 else BTStatusScript.FAILURE)
		task = act

	tree.add_node(task)
	return task

func _generate_subtree(parent_tree: BTTree) -> BTTask:
	subtree_counter += 1
	var sub_path := "user://fuzz_subtrees/sub_%d_%d.json" % [active_seed, subtree_counter]
	var sub_tree := BTTreeScript.new()
	sub_tree.registry = registry
	sub_tree.tree_name = "SubTree_%d" % subtree_counter

	# Subtree blackboard with declared shared and local variables
	sub_tree.blackboard.set_var("sub_shared_int", rng.randi_range(10, 99), "int")
	var v_shared: BTBlackboard.Variable = sub_tree.blackboard.get_variable_obj("sub_shared_int")
	if v_shared != null:
		v_shared.is_shared = true
		v_shared.description = "Shared integer between parent and subtree"

	sub_tree.blackboard.set_var_local("sub_local_bool", rng.randf() < 0.5, "bool", false, "Private subtree flag")

	var sub_root: BTComposite = BTCompositeScript.BTSequence.new()
	sub_root.set_abort_type(rng.randi_range(0, 3))
	sub_tree.set_root(sub_root)

	for i in rng.randi_range(1, 3):
		var leaf := _generate_leaf(sub_tree)
		sub_tree.connect_parent_child(sub_root, leaf)

	var f := FileAccess.open(sub_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(sub_tree.to_dict()))
		f.close()
	sub_tree = null

	var sub_task := BTSubTreeScript.new(sub_path)
	parent_tree.add_node(sub_task)
	return sub_task
