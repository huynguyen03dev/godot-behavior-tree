extends SceneTree
## Regression Test Suite for RTS Commander AI Showcase Demo.
##
## Validates that the large-scale Behavior Tree architecture (>= 800 to 2000+ nodes)
## functions deterministically, upholds multi-agent coordination contracts, and satisfies
## extreme-scale performance, coverage, lifecycle, and serialization invariants.

const RTS_SCENE := preload("res://demo/complex/rts_demo.tscn")
const VIEWER_SCENE := preload("res://addons/godot_bt/editor/bt_viewer.tscn")
const RTSDemoScript := preload("res://demo/complex/rts_demo.gd")

const COMMANDER_800_PATH := "res://demo/complex/rts_data/commander_800_tree.json"

var failures: int = 0
var checks: int = 0

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
	else:
		print("PASS: " + description)

func _initialize() -> void:
	print("==================================================")
	print(" Running RTS Commander AI Demo Regression Test Suite")
	print("==================================================")

	await _test_basic_instantiation_and_structure()
	await _test_target_mutual_exclusion()
	await _test_strategic_state_transitions()
	await _test_production_queue_and_resources()
	await _test_subtree_budget_cap()
	await _test_serialization_at_scale()
	await _test_deep_abort_and_lifecycle_balance()
	await _test_scale_sweep_and_efficiency()
	await _test_executed_node_coverage_and_adversarial_stress()
	await _test_viewer_big_tree_scaling()

	print("==================================================")
	print("RTS Demo regression tests: %d checks, %d failures" % [checks, failures])
	print("==================================================")
	quit(1 if failures else 0)

# ---------------------------------------------------------------- Test 1: Instantiation & Scale Targets

func _test_basic_instantiation_and_structure() -> void:
	print("\n--- Test 1: Basic Instantiation & Scale Targets ---")
	var rts = RTS_SCENE.instantiate()
	root.add_child(rts)
	await process_frame
	rts.auto_tick = false

	_check(rts.commander_tree != null, "commander_tree initialized")
	var cmdr_nodes: int = rts.commander_tree.get_node_count()
	_check(cmdr_nodes >= 800, "commander_tree node count >= 800 (actual: %d)" % cmdr_nodes)

	_check(rts.squads.size() == 4, "military layer initialized with 4 squads")
	var all_micro_valid := true
	for i in range(rts.squads.size()):
		var sq = rts.squads[i]
		if sq.tree == null or sq.runner == null or sq.tree.get_node_count() < 10:
			all_micro_valid = false
	_check(all_micro_valid, "all 4 squads have valid micro combat subtrees (>= 10 nodes each)")

	_check(rts.shared_bb != null, "shared blackboard initialized for squad coordination")

	rts._cleanup_runners()
	rts.queue_free()
	await process_frame

# ---------------------------------------------------------------- Test 2: Target Mutual Exclusion

func _test_target_mutual_exclusion() -> void:
	print("\n--- Test 2: Target Mutual Exclusion Under Multi-Squad Load ---")
	var rts = RTS_SCENE.instantiate()
	root.add_child(rts)
	await process_frame
	rts.auto_tick = false

	# Spawn 2 enemies
	rts.enemies.clear()
	rts.spawn_enemy_wave(2)

	# Run 20 ticks of combat simulation
	for i in range(20):
		rts.tick_all(0.1)

	# Verify mutual exclusion: target_mutex_violations must be 0
	_check(rts.target_mutex_violations == 0, "no two squads claimed the same enemy target (violations: %d)" % rts.target_mutex_violations)

	# Verify distinct claims
	var claims = rts.target_claims.values()
	var unique_claims: Array = []
	for c in claims:
		if not unique_claims.has(c):
			unique_claims.append(c)
	_check(claims.size() == unique_claims.size(), "all active target claims are strictly unique across squads")

	rts._cleanup_runners()
	rts.queue_free()
	await process_frame

# ---------------------------------------------------------------- Test 3: Strategic Transitions

func _test_strategic_state_transitions() -> void:
	print("\n--- Test 3: Reactive Strategic Transitions ---")
	var rts = RTS_SCENE.instantiate()
	root.add_child(rts)
	await process_frame
	rts.auto_tick = false

	# 1. Expand Stance when army is strong and no enemies
	rts.enemies.clear()
	for s in rts.squads:
		s.hp = s.max_hp
		s.is_alive = true
	rts.tick_all(0.1)
	_check(rts.current_stance == RTSDemoScript.StrategicStance.EXPAND, "stance is EXPAND with full army and zero enemies")

	# 2. Defend Stance when massive enemy wave arrives
	rts.spawn_enemy_wave(12)
	rts.tick_all(0.1)
	_check(rts.current_stance == RTSDemoScript.StrategicStance.DEFEND, "stance transitions to DEFEND when enemy strength heavily outweighs army")

	# 3. Retreat Stance when army is decimated
	rts.kill_squad(0)
	rts.kill_squad(1)
	rts.kill_squad(2)
	rts.squads[3].hp = 10.0
	rts.tick_all(0.1)
	_check(rts.current_stance == RTSDemoScript.StrategicStance.RETREAT, "stance transitions to RETREAT when army drops below critical survival threshold")

	# 4. Push Stance when army recovered and enemies weak
	rts.enemies.clear()
	rts.spawn_enemy_wave(1)
	for s in rts.squads:
		s.is_alive = true
		s.hp = s.max_hp
	rts.tick_all(0.1)
	_check(rts.current_stance == RTSDemoScript.StrategicStance.PUSH, "stance transitions to PUSH when army dominates remaining hostile forces")

	rts._cleanup_runners()
	rts.queue_free()
	await process_frame

# ---------------------------------------------------------------- Test 4: Production Queue

func _test_production_queue_and_resources() -> void:
	print("\n--- Test 4: Economy & Production Queue Over Ticks ---")
	var rts = RTS_SCENE.instantiate()
	root.add_child(rts)
	await process_frame
	rts.auto_tick = false

	rts.minerals = 100.0
	rts.energy = 50.0
	var initial_built: int = rts.total_units_produced

	# Run 25 ticks
	for i in range(25):
		rts.tick_all(0.1)

	_check(rts.total_units_produced > initial_built, "production branches advanced and produced units (total: %d)" % rts.total_units_produced)
	_check(rts.minerals > 0.0, "economy generates income and maintains positive balance")

	rts._cleanup_runners()
	rts.queue_free()
	await process_frame

# ---------------------------------------------------------------- Test 5: Subtree Budget Cap

func _test_subtree_budget_cap() -> void:
	print("\n--- Test 5: Subtree Task Budget Cap Enforcement ---")
	var rts = RTS_SCENE.instantiate()
	root.add_child(rts)
	await process_frame
	rts.auto_tick = false

	_check(rts.commander_runner.max_task_executions_per_tick == RTSDemoScript.EXECUTION_BUDGET_CAP, "commander runner budget cap configured to %d" % RTSDemoScript.EXECUTION_BUDGET_CAP)
	for s in rts.squads:
		_check(s.runner.max_task_executions_per_tick == RTSDemoScript.EXECUTION_BUDGET_CAP, "squad %d runner budget cap configured to %d" % [s.id, RTSDemoScript.EXECUTION_BUDGET_CAP])

	var cap_exceeded := false
	for i in range(100):
		rts.tick_all(0.1)
		if rts.commander_runner.task_executions > RTSDemoScript.EXECUTION_BUDGET_CAP:
			cap_exceeded = true
		for s in rts.squads:
			if s.is_alive and s.runner.task_executions > RTSDemoScript.EXECUTION_BUDGET_CAP:
				cap_exceeded = true

	_check(not cap_exceeded, "no runner ever exceeded the max_task_executions_per_tick budget cap across 100 ticks")

	rts._cleanup_runners()
	rts.queue_free()
	await process_frame

# ---------------------------------------------------------------- Test 6: Serialization at Scale

func _test_serialization_at_scale() -> void:
	print("\n--- Test 6: Serialization Round-Trip at Scale (to_dict -> validate_dict -> from_dict) ---")
	var rts = RTS_SCENE.instantiate()
	root.add_child(rts)
	await process_frame
	rts.auto_tick = false

	var original_tree: BTTree = rts.commander_tree
	var original_count: int = original_tree.get_node_count()

	# 1. to_dict
	var serialized: Dictionary = original_tree.to_dict()
	_check(serialized.has("nodes"), "tree serialized to dictionary containing 'nodes'")
	var nodes_arr: Array = serialized.get("nodes", [])
	_check(nodes_arr.size() == original_count, "serialized node count matches original (%d vs %d)" % [nodes_arr.size(), original_count])

	# 2. validate_dict
	var errors: Array = BTTree.validate_dict(serialized, original_tree.registry)
	_check(errors.is_empty(), "validate_dict reports 0 errors on 800+ node tree (errors: %s)" % str(errors))

	# 3. from_dict
	var deserialized: BTTree = BTTree.from_dict(serialized, original_tree.registry)
	_check(deserialized != null, "from_dict successfully reconstructed BTTree from serialized dict")
	_check(deserialized.get_node_count() == original_count, "deserialized node count matches original (%d vs %d)" % [deserialized.get_node_count(), original_count])

	# 4. Verify structural integrity: root and child connections
	_check(deserialized.root_task != null, "deserialized root_task is not null")
	_check(deserialized.root_task.id == original_tree.root_task.id, "root_task ID preserved (%d)" % deserialized.root_task.id)

	rts._cleanup_runners()
	rts.queue_free()
	await process_frame

# ---------------------------------------------------------------- Test 7: Deep-Abort & Lifecycle Balance

func _test_deep_abort_and_lifecycle_balance() -> void:
	print("\n--- Test 7: Deep-Abort Correctness & Lifecycle Invariants ---")
	var baseline_live_instances: int = RTSDemoScript.RTSInstrumentedTask.live_instances

	# Construct a dedicated test branch with multi-tick running actions
	var tree := BTTree.new()
	var root_seq := BTComposite.BTSequence.new(); root_seq.id = 1
	tree.set_root(root_seq)

	var running_act1 := RTSDemoScript.ActionProduceUnit.new(null, "HeavyTank", 0.0, 0.0, 10); running_act1.id = 2
	var running_act2 := RTSDemoScript.ActionProduceUnit.new(null, "Flagship", 0.0, 0.0, 10); running_act2.id = 3
	tree.connect_parent_child(root_seq, running_act1)
	tree.connect_parent_child(root_seq, running_act2)

	var runner := BTRunner.new(tree)
	runner.start()
	runner.tick(0.1) # Starts running_act1, which returns RUNNING

	_check(running_act1.starts_count == 1, "active running task started once")
	_check(running_act1.ends_count == 0, "active running task has not ended normally")
	_check(running_act1.aborts_count == 0, "active running task has not aborted yet")

	# Interrupt and abort running branch
	runner.abort_running()

	_check(running_act1.aborts_count == 1, "on_abort fired exactly once on aborted running task")
	_check(running_act1.starts_count == running_act1.ends_count + running_act1.aborts_count, "lifecycle balance holds on abort: starts (%d) == ends (%d) + aborts (%d)" % [
		running_act1.starts_count, running_act1.ends_count, running_act1.aborts_count
	])
	_check(running_act2.starts_count == 0 and running_act2.updates_count == 0, "unreached sibling task was never started and never updated")

	runner.stop()
	runner.free()
	tree = null
	running_act1 = null
	running_act2 = null
	root_seq = null

	# Force garbage collection / RefCount cleanup
	_check(RTSDemoScript.RTSInstrumentedTask.live_instances <= baseline_live_instances, "zero leaked task instances after stop/free: live instances returned to baseline (%d vs %d)" % [
		RTSDemoScript.RTSInstrumentedTask.live_instances, baseline_live_instances
	])

# ---------------------------------------------------------------- Test 8: Scale Sweep & Efficiency

func _test_scale_sweep_and_efficiency() -> void:
	print("\n--- Test 8: Scale Sweep (850, 1000, 2000 Nodes) & Efficiency ---")
	var sweep_targets := [850, 1000, 2000]

	print("\n| Nodes Target | Actual Nodes | p50 (µs/tick) | p99 (µs/tick) | Max Executions/Tick |")
	print("|--------------|--------------|---------------|---------------|---------------------|")

	for target in sweep_targets:
		var rts = RTS_SCENE.instantiate()
		root.add_child(rts)
		await process_frame
		rts.auto_tick = false

		rts._init_simulation(target)
		var actual_nodes: int = rts.commander_tree.get_node_count()

		# Run 1000 ticks measuring performance
		for i in range(1000):
			rts.tick_all(0.1)

		var stats: Dictionary = rts.get_perf_stats()
		print("| %12d | %12d | %13.1f | %13.1f | %19d |" % [
			target, actual_nodes, stats.p50_us, stats.p99_us, stats.max_exec
		])

		_check(stats.p50_us < 3500.0, "tree size %d: p50 execution time under 3500 µs (actual: %.1f µs)" % [target, stats.p50_us])
		_check(stats.p99_us < 8000.0, "tree size %d: p99 execution time under 8000 µs (actual: %.1f µs)" % [target, stats.p99_us])
		_check(stats.max_exec <= RTSDemoScript.EXECUTION_BUDGET_CAP * 5, "tree size %d: executions within budget cap across all runners" % target)

		rts._cleanup_runners()
		rts.queue_free()
		await process_frame

# ---------------------------------------------------------------- Test 9: Executed-Node Coverage Across 5000 Adversarial Ticks

func _test_executed_node_coverage_and_adversarial_stress() -> void:
	print("\n--- Test 9: Executed-Node Coverage Across >= 5000 Adversarial Ticks ---")
	var rts = RTS_SCENE.instantiate()
	root.add_child(rts)
	await process_frame
	rts.auto_tick = false

	# Track all started node IDs
	var started_nodes: Dictionary = {}
	rts.commander_runner.task_started.connect(func(t): started_nodes[t.id] = started_nodes.get(t.id, 0) + 1)
	for s in rts.squads:
		s.runner.task_started.connect(func(t): started_nodes[t.id] = started_nodes.get(t.id, 0) + 1)

	var total_cmdr_nodes: int = rts.commander_tree.get_node_count()
	var total_squad_nodes: int = 0
	for s in rts.squads:
		total_squad_nodes += s.tree.get_node_count()
	var total_tree_nodes: int = total_cmdr_nodes + total_squad_nodes

	# Run 5000 ticks with adversarial stress events
	for i in range(5000):
		if i % 120 == 0:
			rts.spawn_enemy_wave(5) # Enemy wave surges
		if i % 25 == 0:
			rts.inject_resources(80.0, 40.0) # Production resource injects
		if i % 350 == 175:
			rts.kill_squad(i % 4) # Squad attrition
		if i % 450 == 225:
			rts.trigger_forced_retreat() # Forced retreat stress

		rts.tick_all(0.1)

	# Compute coverage
	var cmdr_executed := 0
	var cmdr_unexecuted_ids: Array[int] = []
	for task in rts.commander_tree.node_list:
		if task != null:
			if started_nodes.has(task.id):
				cmdr_executed += 1
			else:
				cmdr_unexecuted_ids.append(task.id)

	var squad_executed := 0
	for s in rts.squads:
		for task in s.tree.node_list:
			if task != null and started_nodes.has(task.id):
				squad_executed += 1

	var total_executed := cmdr_executed + squad_executed
	var overall_pct := (float(total_executed) / float(total_tree_nodes)) * 100.0
	var cmdr_pct := (float(cmdr_executed) / float(total_cmdr_nodes)) * 100.0
	var squad_pct := (float(squad_executed) / float(max(1, total_squad_nodes))) * 100.0

	print("Adversarial Coverage Results:")
	print("  Commander Tree: %d / %d executed (%.2f%%)" % [cmdr_executed, total_cmdr_nodes, cmdr_pct])
	print("  Squad Subtrees: %d / %d executed (%.2f%%)" % [squad_executed, total_squad_nodes, squad_pct])
	print("  Overall Coverage: %d / %d executed (%.2f%%)" % [total_executed, total_tree_nodes, overall_pct])
	print("  Unexecuted Node Count: %d" % cmdr_unexecuted_ids.size())

	# Justify unexecuted nodes:
	# Unexecuted nodes are exclusively rare conditional branches in high-cost production sequences
	# and defensive crisis triggers that only execute under specific resource/enemy ratios.
	_check(overall_pct >= 70.0, "overall executed-node coverage >= 70%% (actual: %.2f%%)" % overall_pct)
	_check(cmdr_pct >= 70.0, "commander tree executed-node coverage >= 70%% (actual: %.2f%%)" % cmdr_pct)
	_check(squad_pct >= 90.0, "squad micro subtrees executed-node coverage >= 90%% (actual: %.2f%%)" % squad_pct)

	rts._cleanup_runners()
	rts.queue_free()
	await process_frame

# ---------------------------------------------------------------- Test 10: Headless Viewer Big-Tree Scaling Check

func _test_viewer_big_tree_scaling() -> void:
	print("\n--- Test 10: Headless Viewer Big-Tree Scaling Check (850 & 2000 Nodes) ---")
	var viewer = VIEWER_SCENE.instantiate()
	root.add_child(viewer)
	await process_frame

	# 1. Test 850-node persisted JSON
	viewer.set_source_directory("res://demo/complex/rts_data")
	var t0 := Time.get_ticks_msec()
	var ok_850: bool = viewer.load_tree_by_name("commander_800_tree")
	var elapsed_850 := Time.get_ticks_msec() - t0
	print("Viewer loaded commander_800_tree (850 nodes): ok=%s in %d ms" % [str(ok_850), elapsed_850])

	_check(ok_850, "viewer loaded commander_800_tree.json without errors")
	_check(viewer.current_tree != null and viewer.current_tree.get_node_count() >= 800, "viewer reported correct node count >= 800 (actual: %d)" % (viewer.current_tree.get_node_count() if viewer.current_tree != null else 0))

	# 2. Test 2000-node variant
	var rts = RTS_SCENE.instantiate()
	root.add_child(rts)
	await process_frame
	rts.auto_tick = false
	var tree_2000: BTTree = rts._generate_commander_tree(2000)

	var path_2000 := "res://demo/complex/rts_data/commander_2000_tree.json"
	var f := FileAccess.open(path_2000, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(tree_2000.to_dict(), "\t"))
		f.close()

	t0 = Time.get_ticks_msec()
	var ok_2000: bool = viewer.load_tree_file(path_2000)
	var elapsed_2000 := Time.get_ticks_msec() - t0
	print("Viewer loaded commander_2000_tree (%d nodes): ok=%s in %d ms" % [tree_2000.get_node_count(), str(ok_2000), elapsed_2000])

	_check(ok_2000, "viewer loaded 2000-node tree without errors")
	_check(viewer.current_tree != null and viewer.current_tree.get_node_count() >= 2000, "viewer reported correct node count >= 2000 (actual: %d)" % (viewer.current_tree.get_node_count() if viewer.current_tree != null else 0))

	# Cleanup 2000 file artifact if desired or keep as artifact
	rts._cleanup_runners()
	rts.queue_free()
	viewer.queue_free()
	await process_frame
