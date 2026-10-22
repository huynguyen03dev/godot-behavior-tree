extends SceneTree
## Standalone model/persistence regression suite.
var _failures := 0
var _checks := 0

class SubTreeProbeTask extends BTTask:
	func on_update() -> int:
		var expected: Node = blackboard.get_var("expected_actor")
		blackboard.set_var("actor_seen", owner.actor == expected)
		blackboard.set_var("delta_seen", owner.delta)
		blackboard.set_var("calls", int(blackboard.get_var("calls", 0)) + 1)
		blackboard.set_var("runtime_task_ref", weakref(self))
		return BTStatus.SUCCESS

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_failures = 0
	_checks = 0
	var tree := BTTree.new()
	var root := BTComposite.BTSequence.new()
	tree.set_root(root)
	var first := BTTask.new()
	tree.connect_parent_child(root, first)
	var second := BTTask.new()
	tree.add_node(second)
	_check(first.id != second.id, "new nodes get distinct IDs")
	tree.remove_node(first)
	var third := BTTask.new()
	tree.add_node(third)
	_check(third.id != second.id, "IDs remain distinct after removal")
	var composite := BTComposite.BTSelector.new()
	composite.set_abort_type(BTComposite.AbortType.BOTH)
	var persisted := BTTree.new()
	persisted.set_root(composite)
	persisted.blackboard.set_var("position", Vector3(1, 2, 3))
	persisted.blackboard.set_var("nested", {"color": Color.RED, "items": [Vector2(4, 5)]})
	var json_text := JSON.stringify(persisted.to_dict())
	var parsed: Variant = JSON.parse_string(json_text)
	var restored := BTTree.from_dict(parsed)
	_check(restored != null and restored.root_task.abort_type == BTComposite.AbortType.BOTH, "abort type survives persistence")
	_check(restored != null and restored.blackboard.get_var("position") == Vector3(1, 2, 3), "Vector3 survives persistence")
	_check(restored != null and restored.blackboard.get_var("nested").color == Color.RED, "nested Color survives JSON persistence")
	_check(restored != null and restored.blackboard.get_var("nested").items[0] == Vector2(4, 5), "nested Vector2 survives JSON persistence")
	var parameter_tree := BTTree.new()
	var parameter_root := BTComposite.BTSequence.new()
	parameter_root.parameters = {"__bt_type": "Vector2", "value": [1, 2], "position": Vector2(1, 2)}
	parameter_tree.set_root(parameter_root)
	var parameter_roundtrip := BTTree.from_dict(JSON.parse_string(JSON.stringify(parameter_tree.to_dict())))
	_check(parameter_roundtrip != null and parameter_roundtrip.root_task.parameters is Dictionary, "parameters remain a dictionary across JSON roundtrip")
	var ordinary_parameters: Dictionary = parameter_roundtrip.root_task.parameters if parameter_roundtrip != null else {}
	var ordinary_value: Array = ordinary_parameters.get("value", [])
	_check(ordinary_parameters.get("__bt_type") == "Vector2" and ordinary_value.size() == 2 and float(ordinary_value[0]) == 1.0 and float(ordinary_value[1]) == 2.0, "ordinary parameter tag-like dictionary is not hijacked")
	_check(parameter_roundtrip != null and parameter_roundtrip.root_task.parameters.position == Vector2(1, 2), "typed parameter values roundtrip inside parameter map")
	var none_tree := BTTree.new()
	var none_root := BTComposite.BTSelector.new()
	none_root.set_abort_type(BTComposite.AbortType.NONE)
	none_tree.set_root(none_root)
	var none_roundtrip := BTTree.from_dict(JSON.parse_string(JSON.stringify(none_tree.to_dict())))
	_check(none_roundtrip != null and none_roundtrip.root_task.abort_type == BTComposite.AbortType.NONE, "None abort type survives JSON roundtrip")
	var invalid := {"root_id": 1, "nodes": [{"id": 1, "type_name": "Sequence", "children_ids": [1], "parameters": {}}]}
	_check(not BTTree.validate_dict(invalid).is_empty(), "cyclic hierarchy rejected")
	_check(not BTTree.validate_dict({}).is_empty(), "missing schema rejected")
	_check(not BTTree.validate_dict({"root_id": 1.9, "nodes": [{"id": 1, "children_ids": []}]}).is_empty(), "fractional root ID rejected")
	_check(not BTTree.validate_dict({"root_id": 1, "nodes": [{"id": 1, "children_ids": [], "parameters": {"x": {"__bt_type": "Vector2", "value": [1]}}}]}).is_empty(), "malformed tagged value rejected")
	_check(BTTree.validate_dict({"root_id": 1, "nodes": [{"id": 1, "type_name": "Sequence", "children_ids": [], "parameters": {"__bt_type": "Vector2", "value": [1, 2]}}]}).is_empty(), "tag-shaped parameters container remains an ordinary dictionary")
	for bad_abort in [{}, [], "1", 4, -1, 1.5]:
		var bad_abort_data := {"root_id": 1, "nodes": [{"id": 1, "type_name": "Sequence", "children_ids": [], "parameters": {"abort_type": bad_abort}}]}
		_check(not BTTree.validate_dict(bad_abort_data).is_empty(), "malformed abort_type rejected: " + str(bad_abort))
	_check(not BTTree.validate_dict({"root_id": 1, "nodes": [{"id": 1, "children_ids": "bad", "parameters": {}}]}).is_empty(), "malformed children_ids rejected without aborting validation")
	_check(not BTTree.validate_dict({"root_id": 1, "nodes": [{"id": 1, "children_ids": [], "parameters": {}}], "blackboard": {"x": {"value": {"nested": {"__bt_type": "Vector2", "value": [1]}}}}}).is_empty(), "nested malformed blackboard encoding rejected")
	_check(BTTree.validate_dict({"root_id": 1, "nodes": [{"id": 1, "children_ids": [], "parameters": {}}, {"id": 2, "children_ids": [], "parent_id": 1, "parameters": {}}]}).is_empty(), "disconnected draft node with parent metadata allowed")
	_check(not BTTree.validate_dict({"root_id": 2, "nodes": [{"id": 1, "children_ids": [2], "parameters": {}}, {"id": 2, "children_ids": [], "parameters": {}}]}).is_empty(), "root with parent rejected")
	var draft := BTTree.new()
	draft.set_root(BTTask.new())
	draft.add_node(BTTask.new())
	var draft_copy := BTTree.from_dict(JSON.parse_string(JSON.stringify(draft.to_dict())))
	_check(draft_copy != null and draft_copy.node_list.size() == 2, "disconnected draft node survives JSON roundtrip")
	var custom := BTTaskRegistry.new()
	custom.register_task("CustomTask", func(): return BTTask.new(), "Action")
	var custom_tree := BTTree.from_dict({"root_id": 1, "nodes": [{"id": 1, "type_name": "CustomTask", "children_ids": [], "parameters": {}}]}, custom)
	_check(custom_tree != null and custom_tree.registry == custom, "custom registry retained")
	var unknown_data := {"root_id": 1, "nodes": [{"id": 1, "type_name": "NoSuchTask", "is_placeholder": false, "children_ids": [], "parameters": {}}]}
	var unknown := BTTree.from_dict(unknown_data)
	_check(unknown != null and unknown.root_task.is_placeholder, "serialized flag cannot disable unknown placeholder")
	await _test_subtree_end_to_end()
	print("Model regression suite: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

func _test_subtree_end_to_end() -> void:
	var child_path := "user://bt_review_subtree_child.json"
	var self_path := "user://bt_review_subtree_self.json"
	var cycle_a_path := "user://bt_review_subtree_a.json"
	var cycle_b_path := "user://bt_review_subtree_b.json"
	var fixture_paths := [child_path, self_path, cycle_a_path, cycle_b_path]
	var actor := Node.new()
	var runner: BTRunner = null
	var task_ref: WeakRef = null
	var registry := BTTaskRegistry.new()
	registry.register_task("ReviewSubTreeProbe", func(): return SubTreeProbeTask.new(), "Action")
	var child_tree := BTTree.new()
	var child_root := SubTreeProbeTask.new()
	child_root.type_name = "ReviewSubTreeProbe"
	child_tree.set_root(child_root)
	_write_tree_fixture(child_path, child_tree.to_dict())
	var parent_tree := BTTree.new()
	parent_tree.registry = registry
	var subtree := BTSubTree.new(child_path)
	parent_tree.set_root(subtree)
	parent_tree.blackboard.set_var("expected_actor", actor)
	runner = BTRunner.new(parent_tree)
	runner.actor = actor
	runner.start()
	_check(runner.tick(0.125) == BTStatus.SUCCESS, "SubTree custom task executes successfully")
	task_ref = parent_tree.blackboard.get_var("runtime_task_ref")
	_check(parent_tree.blackboard.get_var("actor_seen") == true, "SubTree custom task receives parent actor")
	_check(parent_tree.blackboard.get_var("delta_seen") == 0.125, "SubTree custom task receives tick delta")
	runner.start()
	_check(runner.tick(0.25) == BTStatus.SUCCESS, "SubTree can execute after a repeated start")
	_check(parent_tree.blackboard.get_var("calls") == 2, "SubTree shares blackboard across repeated starts")
	parent_tree.blackboard.remove_var("expected_actor")
	runner.stop()
	runner.free()
	runner = null
	parent_tree = null
	subtree = null
	child_tree = null
	child_root = null
	parent_tree = null
	await process_frame
	_check(task_ref != null and task_ref.get_ref() == null, "SubTree cleanup releases its loaded task")
	# Avoid retaining a freed Node through the blackboard fixture.
	actor.free()
	actor = null

	var self_dict := _subtree_fixture_dict(self_path)
	_write_tree_fixture(self_path, self_dict)
	_check(_run_subtree_fixture(self_path, BTStatus.FAILURE), "self-referencing SubTree fails without recursion hang")
	var a_dict := _subtree_fixture_dict(cycle_b_path)
	var b_dict := _subtree_fixture_dict(cycle_a_path)
	_write_tree_fixture(cycle_a_path, a_dict)
	_write_tree_fixture(cycle_b_path, b_dict)
	_check(_run_subtree_fixture(cycle_a_path, BTStatus.FAILURE), "two-file A-to-B-to-A SubTree cycle fails without recursion hang")
	for path in fixture_paths:
		var absolute_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(absolute_path)
	_check(fixture_paths.all(func(path): return not FileAccess.file_exists(path)), "all SubTree fixture files removed")

func _subtree_fixture_dict(path: String) -> Dictionary:
	return {"root_id": 1, "nodes": [{"id": 1, "type_name": "SubTree", "friendly_name": "SubTree", "children_ids": [], "parameters": {"tree_path": path}}]}

func _write_tree_fixture(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "fixture file opens for writing: " + path)
	if file != null:
		file.store_string(JSON.stringify(data))
		file.close()

func _run_subtree_fixture(path: String, expected_status: int) -> bool:
	var tree := BTTree.new()
	var subtree := BTSubTree.new(path)
	tree.set_root(subtree)
	var runner := BTRunner.new(tree)
	runner.start()
	var status := runner.tick(0.01)
	runner.free()
	return status == expected_status

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: ", label)
