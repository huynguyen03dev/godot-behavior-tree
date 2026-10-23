extends SceneTree
## Comprehensive Regression Test Suite for Villager Colony Life-Sim Showcase Demo.
##
## Validates all hard requirements and upgraded verification metrics:
## 1. Subtree JSON loading and total node count (main trees + subtree files >= 400 nodes).
## 2. Blackboard scoping demonstration: is_shared=true in parent scope; is_shared=false isolated in child scope.
## 3. Needs-driven branch switches: hunger drop triggers mealtime/starvation routines.
## 4. Threat override preemption via LOWER_PRIORITY conditional abort: aborts in-progress actions.
## 5. Day/Night schedule transitions (Morning -> Afternoon -> Evening -> Night).
## 6. Tree serialization round-trip (to_dict -> validate_dict -> from_dict) for main tree and subtree JSON.
## 7. Long adversarial chaos simulation (>= 3000 ticks):
##    - >= 60% coverage across all nodes in main trees + subtree files.
##    - Strict lifecycle balance: starts == ends + aborts, 0 double-aborts, 0 update-without-start.
##    - Tick execution timing (µs per tick): reports p50/p99 and asserts honest performance limits.

const VILLAGER_SCENE := preload("res://demo/complex/villager_demo.tscn")

var failures = 0
var checks = 0

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
	else:
		print("PASS: " + description)

func _initialize() -> void:
	print("==================================================")
	print(" Running Villager Demo Regression Test Suite")
	print("==================================================")

	await _test_subtree_loading_and_node_count()
	await _test_blackboard_scoping()
	await _test_needs_driven_branch_switch()
	await _test_threat_preemption_lifecycle()
	await _test_day_night_schedule()
	await _test_tree_serialization_roundtrip()
	await _test_long_chaos_simulation()

	print("==================================================")
	print("Villager demo regression tests: %d checks, %d failures" % [checks, failures])
	print("==================================================")
	quit(1 if failures else 0)


# ---------------------------------------------------------------- Test 1: Subtree JSON Loading & Node Counts

func _test_subtree_loading_and_node_count() -> void:
	print("\n--- Testing Subtree Loading & Node Counts ---")
	var demo: Node = VILLAGER_SCENE.instantiate()
	root.add_child(demo)
	await process_frame
	demo.auto_tick = false

	var main_count: int = demo.get_main_trees_node_count()
	var subtree_count: int = demo.get_subtree_files_node_count()
	var total_count: int = demo.get_total_node_count()

	print("Main trees node count: %d" % main_count)
	print("Subtree files node count: %d" % subtree_count)
	print("Total BT nodes: %d" % total_count)

	_check(main_count > 0, "main trees contain nodes (%d)" % main_count)
	_check(subtree_count > 0, "subtree JSON files loaded and contain nodes (%d)" % subtree_count)
	_check(total_count >= 400, "HARD REQUIREMENT: Total BT nodes >= 400 (actual: %d)" % total_count)
	_check(demo.villagers.size() == 6, "demo initialized with 6 autonomous villagers")

	# Verify each subtree loaded cleanly
	var expected_subtrees = [
		"farmer_job", "guard_job", "merchant_job", "cook_job",
		"threat_response", "eat_routine", "sleep_routine", "socialize_routine"
	]
	for st_name in expected_subtrees:
		var st: BTTree = demo.tree_source.load_tree(st_name)
		_check(st != null and st.get_node_count() > 0, "subtree '%s' loaded cleanly (%d nodes)" % [st_name, st.get_node_count() if st != null else 0])

	demo.queue_free()
	await process_frame


# ---------------------------------------------------------------- Test 2: Blackboard Scoping

func _test_blackboard_scoping() -> void:
	print("\n--- Testing Blackboard Scoping Invariants ---")
	var demo: Node = VILLAGER_SCENE.instantiate()
	root.add_child(demo)
	await process_frame
	demo.auto_tick = false

	# Let the villagers tick through a few cycles to invoke subtrees and modify variables
	for t in range(15):
		demo.tick_manual(0.1)

	# Farmer Alden: shared 'food_produced', private 'field_harvest_count'
	var alden = demo.villagers[0]
	_check(alden.tree.blackboard != null, "Alden has parent blackboard")
	var has_shared = alden.tree.blackboard.has_var("food_produced")
	var has_private = alden.tree.blackboard.has_var("field_harvest_count")
	_check(has_shared, "SCOPING: is_shared=true variable 'food_produced' is accessible in parent blackboard")
	_check(not has_private, "SCOPING: is_shared=false variable 'field_harvest_count' did NOT leak into parent blackboard")

	# Guard Cedric: shared 'patrol_reports', private 'drill_reps'
	var cedric = demo.villagers[2]
	var g_shared = cedric.tree.blackboard.has_var("patrol_reports")
	var g_private = cedric.tree.blackboard.has_var("drill_reps")
	_check(g_shared, "SCOPING: Guard shared variable 'patrol_reports' is accessible in parent blackboard")
	_check(not g_private, "SCOPING: Guard private variable 'drill_reps' did NOT leak into parent blackboard")

	demo.queue_free()
	await process_frame


# ---------------------------------------------------------------- Test 3: Needs-Driven Branch Switches

func _test_needs_driven_branch_switch() -> void:
	print("\n--- Testing Needs-Driven Branch Switches ---")
	var demo: Node = VILLAGER_SCENE.instantiate()
	root.add_child(demo)
	await process_frame
	demo.auto_tick = false

	var alden = demo.villagers[0]
	alden.hunger = 80.0
	demo.colony_time = 10.0 # Morning work
	demo.tick_manual(0.1)

	# Action should be working or moving to field
	var initial_action: String = alden.current_action_name
	print("Alden initial action when well-fed: %s" % initial_action)

	# Now starve Alden (hunger <= 25 triggers critical starvation branch)
	alden.hunger = 20.0
	demo.tick_manual(0.1)
	var hungry_action: String = alden.current_action_name
	print("Alden action when starving: %s" % hungry_action)
	_check(hungry_action.contains("Eat") or hungry_action.contains("Granary") or hungry_action.contains("Dining") or hungry_action.contains("Meal") or hungry_action.contains("dining") or hungry_action.contains("granary"),
		"Alden switched to eating routine on critical hunger drop (action: %s)" % hungry_action)

	# Now exhaust Alden (energy <= 20 triggers sleep branch)
	alden.hunger = 90.0
	alden.energy = 15.0
	demo.tick_manual(0.1)
	var tired_action: String = alden.current_action_name
	print("Alden action when exhausted: %s" % tired_action)
	_check(tired_action.contains("Sleep") or tired_action.contains("Bed") or tired_action.contains("home") or tired_action.contains("Slumber") or tired_action.contains("Cottage"),
		"Alden switched to sleep routine on exhaustion (action: %s)" % tired_action)

	demo.queue_free()
	await process_frame


# ---------------------------------------------------------------- Test 4: Threat Preemption & Lifecycle Integrity

func _test_threat_preemption_lifecycle() -> void:
	print("\n--- Testing Threat Preemption & Lifecycle Under Chaos ---")
	var demo: Node = VILLAGER_SCENE.instantiate()
	root.add_child(demo)
	await process_frame
	demo.auto_tick = false

	# Put colony in normal working state
	demo.colony_time = 10.0
	for t in range(5):
		demo.tick_manual(0.1)

	var alden = demo.villagers[0]
	var pre_aborts = alden.total_aborts
	var pre_starts = alden.total_starts
	var pre_ends = alden.total_ends

	# Trigger wolf attack threat (LOWER_PRIORITY conditional abort)
	demo.spawn_threat()
	_check(demo.threat_active, "Wolf threat spawned")

	# Next tick MUST preempt the working branch immediately
	demo.tick_manual(0.1)

	_check(alden.total_aborts > pre_aborts, "LOWER_PRIORITY conditional abort preempted Alden's action (aborts: %d -> %d)" % [pre_aborts, alden.total_aborts])
	_check(alden.current_action_name.contains("Threat") or alden.current_action_name.contains("Bunker") or alden.current_action_name.contains("Safe") or alden.current_action_name.contains("Cower") or alden.current_action_name.contains("Aborted"),
		"Alden responded to threat immediately (current action: %s)" % alden.current_action_name)

	# Guard Cedric should engage or secure gates
	var cedric = demo.villagers[2]
	_check(cedric.current_action_name.contains("Gate") or cedric.current_action_name.contains("Threat") or cedric.current_action_name.contains("Guard") or cedric.current_action_name.contains("Attack") or cedric.current_action_name.contains("Aborted") or cedric.current_action_name.contains("Watchtower"),
		"Cedric guard mobilized for defense (action: %s)" % cedric.current_action_name)

	# Run a few ticks under threat
	for t in range(4):
		demo.tick_manual(0.1)

	# Clear threat and verify return to normal
	demo.clear_threat()
	demo.tick_manual(0.1)
	_check(not demo.threat_active, "Threat cleared successfully")

	# Check lifecycle invariant on Alden
	var lifecycle = demo.assert_lifecycle_balance()
	_check(alden.double_abort_errors == 0, "zero double-abort errors on Alden")
	_check(alden.update_without_start_errors == 0, "zero update-without-start errors on Alden")

	demo.queue_free()
	await process_frame


# ---------------------------------------------------------------- Test 5: Day/Night Schedule Transition

func _test_day_night_schedule() -> void:
	print("\n--- Testing Day/Night Schedule Transitions ---")
	var demo: Node = VILLAGER_SCENE.instantiate()
	root.add_child(demo)
	await process_frame
	demo.auto_tick = false

	# Test morning phase (8:00)
	demo.colony_time = 8.0
	demo.tick_manual(0.1)
	_check(demo.current_phase == "morning", "Phase is morning at 08:00")

	# Test afternoon phase (14:00)
	demo.colony_time = 14.0
	demo.tick_manual(0.1)
	_check(demo.current_phase == "afternoon", "Phase is afternoon at 14:00")

	# Test evening phase (19:00)
	demo.colony_time = 19.0
	demo.tick_manual(0.1)
	_check(demo.current_phase == "evening", "Phase is evening at 19:00")

	# Test night phase (23:00)
	demo.colony_time = 23.0
	demo.tick_manual(0.1)
	_check(demo.current_phase == "night", "Phase is night at 23:00")

	# Verify villagers go to sleep at night
	for v in demo.villagers:
		_check(v.current_action_name.contains("Sleep") or v.current_action_name.contains("Bed") or v.current_action_name.contains("home") or v.current_action_name.contains("Slumber") or v.current_action_name.contains("Cottage"),
			"%s went to sleep at night (action: %s)" % [v.name, v.current_action_name])

	demo.queue_free()
	await process_frame


# ---------------------------------------------------------------- Test 6: Tree Serialization Round-Trip

func _test_tree_serialization_roundtrip() -> void:
	print("\n--- Testing Tree Serialization Round-Trip (to_dict -> validate -> from_dict) ---")
	var demo: Node = VILLAGER_SCENE.instantiate()
	root.add_child(demo)
	await process_frame
	demo.auto_tick = false

	# 1. Round-trip a SubTree JSON
	var st_tree: BTTree = demo.tree_source.load_tree("farmer_job")
	_check(st_tree != null, "farmer_job subtree loaded for serialization test")
	var st_dict = st_tree.to_dict()
	_check(st_dict is Dictionary and st_dict.has("nodes"), "subtree to_dict produced valid dictionary")

	var st_errors = BTTree.validate_dict(st_dict, demo.task_registry)
	_check(st_errors.is_empty(), "subtree dictionary validation has zero errors (errors: %s)" % str(st_errors))

	var st_reconstructed = BTTree.from_dict(st_dict, demo.task_registry)
	_check(st_reconstructed != null, "subtree successfully reconstructed from dict")
	_check(st_reconstructed.get_node_count() == st_tree.get_node_count(),
		"subtree node count matches exactly: original=%d, reconstructed=%d" % [st_tree.get_node_count(), st_reconstructed.get_node_count()])

	# 2. Round-trip a Main Tree
	var main_tree = demo.villagers[0].tree
	_check(main_tree != null, "main tree available for serialization test")
	var main_dict = main_tree.to_dict()
	_check(main_dict is Dictionary and main_dict.has("nodes"), "main tree to_dict produced valid dictionary")

	var main_errors = BTTree.validate_dict(main_dict, demo.task_registry)
	_check(main_errors.is_empty(), "main tree dictionary validation has zero errors (errors: %s)" % str(main_errors))

	var main_reconstructed = BTTree.from_dict(main_dict, demo.task_registry)
	_check(main_reconstructed != null, "main tree successfully reconstructed from dict")
	_check(main_reconstructed.get_node_count() == main_tree.get_node_count(),
		"main tree node count matches exactly: original=%d, reconstructed=%d" % [main_tree.get_node_count(), main_reconstructed.get_node_count()])

	demo.queue_free()
	await process_frame


# ---------------------------------------------------------------- Test 7: Long Chaos Simulation (>= 3000 Ticks)

func _test_long_chaos_simulation() -> void:
	print("\n--- Testing Long Chaos Simulation (>= 3000 Ticks) ---")
	var demo: Node = VILLAGER_SCENE.instantiate()
	root.add_child(demo)
	await process_frame
	demo.auto_tick = false

	var total_ticks = 3200
	var threat_interval = 200
	var feed_interval = 450

	print("Running %d ticks across multiple day/night cycles with periodic threats and feeding..." % total_ticks)

	for t in range(total_ticks):
		# Periodic threat injection
		if t % threat_interval == 50:
			demo.spawn_threat()
		elif t % threat_interval == 70:
			demo.clear_threat()

		# Periodic feeding
		if t % feed_interval == 0:
			demo.feed_all()

		demo.tick_manual(0.1)

	# 1. Assert Lifecycle Balance Under Chaos
	var balance_report = demo.assert_lifecycle_balance()
	_check(balance_report["all_balanced"] == true, "LIFECYCLE: All 6 villagers maintained perfect lifecycle balance (starts == ends + aborts)")
	for v_info in balance_report["villagers"]:
		print("Villager %s: Starts=%d, Ends=%d, Aborts=%d, DoubleAborts=%d, UpdateNoStart=%d" % [
			v_info["name"], v_info["starts"], v_info["ends"], v_info["aborts"], v_info["double_aborts"], v_info["update_without_starts"]
		])
		_check(v_info["double_aborts"] == 0, "%s had 0 double aborts" % v_info["name"])
		_check(v_info["update_without_starts"] == 0, "%s had 0 update-without-start errors" % v_info["name"])

	# 2. Assert Executed Node Coverage >= 60%
	var coverage = demo.get_coverage_ratio()
	var executed_count = demo.get_executed_node_count()
	var total_count = demo.get_total_node_count()
	print("Executed Nodes: %d / %d (%.2f%%)" % [executed_count, total_count, coverage * 100.0])
	_check(coverage >= 0.60, "HARD REQUIREMENT: Executed-node coverage >= 60%% (actual: %.2f%%)" % [coverage * 100.0])

	# 3. Assert Runner Tick Performance (µs per tick)
	var percs = demo.get_tick_percentiles()
	print("Timing stats over %d runner ticks: p50=%d µs, p90=%d µs, p99=%d µs" % [
		percs["count"], percs["p50"], percs["p90"], percs["p99"]
	])
	_check(percs["p50"] < 1500, "EFFICIENCY: p50 tick time < 1500 µs (actual: %d µs)" % percs["p50"])
	_check(percs["p99"] < 10000, "EFFICIENCY: p99 tick time < 10000 µs (actual: %d µs)" % percs["p99"])

	demo.queue_free()
	await process_frame
