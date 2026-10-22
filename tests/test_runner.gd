extends SceneTree
## Automated test suite for Godot Behavior Tree.
## Run with: godot --headless --path . -s res://tests/test_runner.gd

func _init() -> void:
	print("==================================================")
	print(" Running Godot Behavior Tree Test Suite")
	print("==================================================")

	var total_tests := 0
	var total_passed := 0
	var total_failed := 0

	var test_groups = [
		_test_core_and_status(),
		_test_composite_and_decorator(),
		_test_blackboard(),
		_test_tree_builder_and_serialization(),
		_test_runner_execution(),
		_test_file_adapter(),
		_test_editor_ui(),
		_test_task_parameters_and_blackboard_binding(),
		_test_decorators_cooldown_and_timelimit(),
		_test_conditional_aborts(),
		_test_lifecycle_and_events()
	]

	for group in test_groups:
		for row in group:
			total_tests += 1
			if row[1]:
				total_passed += 1
			else:
				total_failed += 1
				print("  ❌ FAIL: %s [%s]" % [row[0], str(row[2])])

	print("--------------------------------------------------")
	print("Results: %d total, %d passed, %d failed" % [total_tests, total_passed, total_failed])
	print("==================================================")
	quit(0 if total_failed == 0 else 1)

func _test_core_and_status() -> Array:
	var rows := []
	rows.append(["BTStatus enum values exist", BTStatus.SUCCESS == 2 and BTStatus.FAILURE == 1 and BTStatus.RUNNING == 3 and BTStatus.INACTIVE == 0, "status values"])
	var task = BTTask.new()
	rows.append(["BTTask instantiates with default INACTIVE status", task.last_status == BTStatus.INACTIVE, "status=%d" % task.last_status])
	rows.append(["BTTask default category is Action", task.category == "Action", "cat=%s" % task.category])
	return rows

func _test_composite_and_decorator() -> Array:
	var rows := []
	var seq = BTComposite.BTSequence.new()
	rows.append(["BTSequence instantiates", seq != null, "seq inst"])
	var sel = BTComposite.BTSelector.new()
	rows.append(["BTSelector instantiates", sel != null, "sel inst"])
	var inv = BTDecorator.BTInverter.new()
	rows.append(["BTInverter instantiates", inv != null, "inv inst"])
	return rows

func _test_blackboard() -> Array:
	var rows := []
	var bb = BTBlackboard.new()
	bb.set_var("speed", 5.5, "float")
	bb.set_var("target_name", "Player", "String")
	rows.append(["BTBlackboard set and get float", abs(float(bb.get_var("speed", 0.0)) - 5.5) < 0.001, "speed=%s" % str(bb.get_var("speed"))])
	rows.append(["BTBlackboard set and get string", str(bb.get_var("target_name", "")) == "Player", "target=%s" % str(bb.get_var("target_name"))])
	rows.append(["BTBlackboard has_var check", bb.has_var("speed") and not bb.has_var("non_existent"), "has_var ok"])
	return rows

func _test_tree_builder_and_serialization() -> Array:
	var rows := []
	var tree = BTTree.new()
	var root = BTComposite.BTSequence.new()
	root.friendly_name = "RootSequence"
	tree.set_root(root)

	var child1 = BTTask.new()
	child1.friendly_name = "TaskA"
	var child2 = BTTask.new()
	child2.friendly_name = "TaskB"

	tree.connect_parent_child(root, child1)
	tree.connect_parent_child(root, child2)

	rows.append(["Tree has 3 nodes", tree.get_node_count() == 3, "count=%d" % tree.get_node_count()])
	rows.append(["Root has 2 children", root.children.size() == 2, "children=%d" % root.children.size()])

	# Serialization test
	var dict = tree.to_dict()
	rows.append(["Tree serializes to Dictionary", dict.has("nodes") and dict.has("root_id"), "has keys"])
	var restored = BTTree.from_dict(dict)
	rows.append(["Tree deserializes from Dictionary", restored != null and restored.get_node_count() == 3, "restored count=%s" % str(restored.get_node_count() if restored else 0)])
	rows.append(["Restored root has matching name", restored.root_task.friendly_name == "RootSequence", "name=%s" % str(restored.root_task.friendly_name if restored.root_task else "")])
	return rows

func _test_runner_execution() -> Array:
	var rows := []
	var tree = BTTree.new()
	var seq = BTComposite.BTSequence.new()
	tree.set_root(seq)

	var t1 = BTTask.new() # on_update() returns SUCCESS by default
	tree.connect_parent_child(seq, t1)

	var runner = BTRunner.new(tree)
	if runner != null:
		runner.start()
		var result := runner.tick()
		rows.append(["Runner executes the tree to SUCCESS", result == BTStatus.SUCCESS and runner.last_status == BTStatus.SUCCESS, "result=%d last=%d" % [result, runner.last_status]])
		runner.stop()
		runner.free()
	else:
		rows.append(["Runner executes the tree to SUCCESS", false, "runner construction failed"])
	return rows

func _test_file_adapter() -> Array:
	var rows := []
	var provider = BTFileTreeSource.new("res://demo/data")
	var trees = provider.list_trees()
	rows.append(["FileTreeSource lists demo tree", trees.has("patrol_ai") or trees.has("patrol_ai.json"), "trees=%s" % str(trees)])

	var tree = provider.load_tree("patrol_ai.json")
	if tree == null:
		tree = provider.load_tree("patrol_ai")
	rows.append(["Loaded demo tree successfully", tree != null, "tree loaded"])
	if tree != null:
		rows.append(["Demo tree has 9 nodes", tree.get_node_count() == 9, "count=%d" % tree.get_node_count()])
		rows.append(["Demo tree root is Sequence", tree.root_task.type_name == "Sequence", "root=%s" % tree.root_task.type_name])
	return rows

func _test_editor_ui() -> Array:
	var rows := []
	var ViewerScript = load("res://addons/godot_bt/editor/bt_viewer.gd")
	rows.append(["bt_viewer.gd loads successfully", ViewerScript != null, "loaded"])
	if ViewerScript != null:
		var viewer = ViewerScript.new()
		var provider = BTFileTreeSource.new("res://demo/data")
		viewer.set_tree_source(provider)
		viewer.load_tree_file("res://demo/data/patrol_ai.json")
		rows.append(["Viewer loads demo tree", viewer.current_tree != null, "viewer loaded"])
		rows.append(["Viewer creates 9 GraphNodes", viewer._graph_nodes_by_id.size() == 9, "nodes=%d" % viewer._graph_nodes_by_id.size()])
		viewer.free()
	return rows

# ---------------------------------------------------------------- Test Mock Classes
class TestMockCondition extends BTTask:
	var condition_met: bool = false
	func _init(p_met: bool = false) -> void:
		super._init()
		type_name = "MockCondition"
		category = "Condition"
		condition_met = p_met

	func on_update() -> int:
		return BTStatus.SUCCESS if condition_met else BTStatus.FAILURE

class TestMockRunningAction extends BTTask:
	var abort_called: bool = false
	var update_count: int = 0
	var event_received: String = ""

	func _init() -> void:
		super._init()
		type_name = "MockRunningAction"
		category = "Action"

	func on_update() -> int:
		update_count += 1
		return BTStatus.RUNNING

	func on_abort() -> void:
		abort_called = true
		super.on_abort()

	func on_event(event_name: String, data: Variant = null) -> void:
		event_received = event_name

func _test_task_parameters_and_blackboard_binding() -> Array:
	var rows := []
	var bb = BTBlackboard.new()
	bb.set_var("target_speed", 12.5, "float")
	bb.set_var("enemy_name", "Goblin", "String")

	var task = BTTask.new()
	task.blackboard = bb

	# Literal param
	task.set_param("fov", 90.0)
	rows.append(["Literal param get", float(task.get_param("fov", 0.0)) == 90.0, "fov=%s" % str(task.get_param("fov"))])
	rows.append(["Literal param is not blackboard", not task.is_param_blackboard("fov"), "is_bb"])

	# Blackboard binding with @ syntax
	task.parameters["speed"] = "@target_speed"
	rows.append(["@key param binds to blackboard", abs(float(task.get_param("speed", 0.0)) - 12.5) < 0.001, "speed=%s" % str(task.get_param("speed"))])
	rows.append(["@key is detected as blackboard", task.is_param_blackboard("speed"), "is_bb"])

	# Blackboard binding with set_param(..., true)
	task.set_param("enemy", "enemy_name", true)
	rows.append(["set_param(..., true) binds to blackboard", str(task.get_param("enemy", "")) == "Goblin", "enemy=%s" % str(task.get_param("enemy"))])
	rows.append(["get_param_blackboard_key returns key", task.get_param_blackboard_key("enemy") == "enemy_name", "key=%s" % task.get_param_blackboard_key("enemy")])

	# Dynamic update in blackboard
	bb.set_var("enemy_name", "Dragon", "String")
	rows.append(["Dynamic blackboard update resolves in get_param", str(task.get_param("enemy", "")) == "Dragon", "enemy=%s" % str(task.get_param("enemy"))])

	return rows

func _test_decorators_cooldown_and_timelimit() -> Array:
	var rows := []

	# Cooldown test (simulated time: advance time by ticking with deltas)
	var cd = BTDecorator.BTCooldown.new()
	cd.cooldown_time = 0.5
	var child_act = TestMockCondition.new(true) # Returns SUCCESS
	cd.children.append(child_act)

	var tree = BTTree.new()
	tree.set_root(cd)
	var runner = BTRunner.new(tree)
	runner.start()

	# Tick 1: runs child and succeeds
	var s1 = runner.tick(0.0)
	rows.append(["Cooldown tick 1 runs child and succeeds", s1 == BTStatus.SUCCESS, "s1=%d" % s1])

	# Next tick with no simulated time elapsed: should fail because of cooldown
	runner.start() # A completed run is inactive; start a fresh run for the cooldown check.
	var s2 = runner.tick(0.0)
	rows.append(["Cooldown tick 2 blocked by cooldown timer", s2 == BTStatus.FAILURE, "s2=%d" % s2])

	# Advance simulated time past the cooldown: it opens again
	runner.start()
	var s3 = runner.tick(0.5)
	rows.append(["Cooldown reopens once simulated time passes", s3 == BTStatus.SUCCESS, "s3=%d" % s3])
	runner.stop()
	runner.free()

	# TimeLimit test
	var tl = BTDecorator.BTTimeLimit.new()
	tl.time_limit = 0.05
	var tl_act = TestMockRunningAction.new()
	tl.children.append(tl_act)

	var tl_tree = BTTree.new()
	tl_tree.set_root(tl)
	var tl_runner = BTRunner.new(tl_tree)
	tl_runner.start()

	var t_s1 = tl_runner.tick(0.0)
	rows.append(["TimeLimit tick 1 running", t_s1 == BTStatus.RUNNING, "ts1=%d" % t_s1])

	# Zero delta never advances simulated time, so the limit is never reached
	var zero_delta_running := true
	for i in 3:
		if tl_runner.tick(0.0) != BTStatus.RUNNING:
			zero_delta_running = false
	rows.append(["TimeLimit with zero delta never expires", zero_delta_running, "zero-delta running=%s" % str(zero_delta_running)])

	# Advance simulated time beyond time_limit
	var t_s2 = tl_runner.tick(0.06)
	rows.append(["TimeLimit aborts after simulated delta exceeds limit", t_s2 == BTStatus.FAILURE and tl_act.abort_called, "ts2=%d, abort=%s" % [t_s2, str(tl_act.abort_called)]])
	tl_runner.stop()
	tl_runner.free()

	return rows

func _test_conditional_aborts() -> Array:
	var rows := []

	# 1. Lower Priority Abort on Selector
	var tree = BTTree.new()
	var selector = BTComposite.BTSelector.new()
	selector.set_abort_type(BTComposite.AbortType.LOWER_PRIORITY)
	tree.set_root(selector)

	var cond = TestMockCondition.new(false)
	var high_action = TestMockRunningAction.new()
	var high_seq = BTComposite.BTSequence.new()
	tree.connect_parent_child(selector, high_seq)
	tree.connect_parent_child(high_seq, cond)
	tree.connect_parent_child(high_seq, high_action)

	var low_action = TestMockRunningAction.new()
	tree.connect_parent_child(selector, low_action)

	var runner = BTRunner.new(tree)
	runner.start()

	# Tick 1: Condition is false, so low_action runs
	var st1 = runner.tick()
	rows.append(["Tick 1: Low priority action is RUNNING", st1 == BTStatus.RUNNING and low_action.update_count == 1, "st1=%d, low=%d" % [st1, low_action.update_count]])
	rows.append(["Tick 1: High action has not run", high_action.update_count == 0, "high=%d" % high_action.update_count])
	rows.append(["Tick 1: Low action not aborted", not low_action.abort_called, "aborted=%s" % str(low_action.abort_called)])

	# Now change condition to true!
	cond.condition_met = true

	# Tick 2: Selector re-evaluates high_seq, condition succeeds, aborts low_action, runs high_seq!
	var st2 = runner.tick()
	rows.append(["Tick 2: Low priority action was aborted", low_action.abort_called, "aborted=%s" % str(low_action.abort_called)])
	rows.append(["Tick 2: High priority action now running", high_action.update_count == 1, "high=%d" % high_action.update_count])
	rows.append(["Tick 2: Runner status is RUNNING", st2 == BTStatus.RUNNING, "st2=%d" % st2])
	runner.stop()
	runner.free()

	# 2. Self Abort on Sequence
	var tree_seq = BTTree.new()
	var seq = BTComposite.BTSequence.new()
	seq.set_abort_type(BTComposite.AbortType.SELF)
	tree_seq.set_root(seq)

	var seq_cond = TestMockCondition.new(true)
	var seq_action = TestMockRunningAction.new()
	tree_seq.connect_parent_child(seq, seq_cond)
	tree_seq.connect_parent_child(seq, seq_action)

	var seq_runner = BTRunner.new(tree_seq)
	seq_runner.start()

	# Tick 1: Condition true, action is RUNNING
	var s_st1 = seq_runner.tick()
	rows.append(["Seq Tick 1: Action is RUNNING", s_st1 == BTStatus.RUNNING and seq_action.update_count == 1, "st1=%d" % s_st1])

	# Now condition becomes false!
	seq_cond.condition_met = false

	# Tick 2: Sequence re-evaluates condition, it fails -> abort action and sequence fails!
	var s_st2 = seq_runner.tick()
	rows.append(["Seq Tick 2: Action was aborted on condition failure", seq_action.abort_called, "aborted=%s" % str(seq_action.abort_called)])
	rows.append(["Seq Tick 2: Sequence failed", s_st2 == BTStatus.FAILURE, "st2=%d" % s_st2])
	seq_runner.stop()
	seq_runner.free()

	return rows

func _test_lifecycle_and_events() -> Array:
	var rows := []
	var tree = BTTree.new()
	var act = TestMockRunningAction.new()
	tree.set_root(act)

	var runner = BTRunner.new(tree)
	runner.start()
	runner.tick()

	runner.send_event("on_damage", 50)
	rows.append(["send_event reaches active tasks", act.event_received == "on_damage", "evt=%s" % act.event_received])

	runner.interrupt(act)
	rows.append(["interrupt aborts running task", act.abort_called, "aborted=%s" % str(act.abort_called)])
	runner.stop()
	runner.free()

	return rows
