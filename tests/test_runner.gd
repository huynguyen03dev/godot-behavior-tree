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
		_test_editor_ui()
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

	var t1 = BTTask.new() # returns INACTIVE by default
	tree.connect_parent_child(seq, t1)

	var runner = BTRunner.new(tree)
	rows.append(["BTRunner instantiates with tree", runner != null, "runner inst"])
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
