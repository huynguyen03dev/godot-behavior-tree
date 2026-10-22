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

class RealDecoratorTask extends BTDecorator:
	func on_update() -> int:
		return children[0].last_status if not children.is_empty() else BTStatus.FAILURE

class CacheProbeA extends BTTask:
	func on_update() -> int:
		blackboard.set_var("cache_calls", int(blackboard.get_var("cache_calls", 0)) + 1)
		return BTStatus.SUCCESS

class CacheProbeB extends BTTask:
	func on_update() -> int:
		blackboard.set_var("cache_version_b", true)
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
	_test_validate_from_dict_agreement()
	_test_registry_category_override()
	_test_nonfinite_and_rejected_encodings()
	_test_save_tree_validation()
	_test_file_source_paths()
	_test_reparent()
	await _test_subtree_end_to_end()
	await _test_subtree_caching()
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

# ------------------------------------------------------------- Fix: S7/P30
func _test_validate_from_dict_agreement() -> void:
	var registry := BTTaskRegistry.new()
	registry.register_task("FakeDecorator", func(): return BTTask.new(), "Decorator")
	registry.register_task("RealDecorator", func(): return RealDecoratorTask.new(), "Decorator")
	registry.register_task("RealComposite", func(): return BTComposite.BTSequence.new(), "Composite")

	# Custom task registered as "Decorator" but returning a plain BTTask, given two children.
	var fake := {"root_id": 1, "nodes": [
		{"id": 1, "type_name": "FakeDecorator", "children_ids": [2, 3], "parameters": {}},
		{"id": 2, "children_ids": [], "parameters": {}},
		{"id": 3, "children_ids": [], "parameters": {}}
	]}
	_check(not BTTree.validate_dict(fake, registry).is_empty(), "custom leaf 'Decorator' with children fails registry validation")
	_check(BTTree.from_dict(fake, registry) == null, "custom leaf 'Decorator' with children rejected by from_dict")
	_check(BTTree.validate_dict(fake).is_empty(), "validate_dict without registry stays permissive for unknown types")

	# Builtin Inverter with two children: both functions reject.
	var two_kids := {"root_id": 1, "nodes": [
		{"id": 1, "type_name": "Inverter", "children_ids": [2, 3], "parameters": {}},
		{"id": 2, "children_ids": [], "parameters": {}},
		{"id": 3, "children_ids": [], "parameters": {}}
	]}
	_check(not BTTree.validate_dict(two_kids).is_empty(), "builtin Inverter with two children rejected without registry")
	_check(not BTTree.validate_dict(two_kids, registry).is_empty(), "builtin Inverter with two children rejected with registry")
	_check(BTTree.from_dict(two_kids, registry) == null, "builtin Inverter with two children rejected by from_dict")

	# A valid custom BTParentTask decorator is accepted by both.
	var good := {"root_id": 1, "nodes": [
		{"id": 1, "type_name": "RealDecorator", "children_ids": [2], "parameters": {}},
		{"id": 2, "type_name": "RealComposite", "children_ids": [3], "parameters": {}},
		{"id": 3, "children_ids": [], "parameters": {}}
	]}
	_check(BTTree.validate_dict(good, registry).is_empty(), "custom parent-task decorator accepted by validation")
	var good_tree := BTTree.from_dict(good, registry)
	_check(good_tree != null and good_tree.root_task is RealDecoratorTask, "custom parent-task decorator loads via from_dict")

	# from_dict validates with its registry even for a single child.
	var leaf_with_kid := {"root_id": 1, "nodes": [
		{"id": 1, "type_name": "FakeDecorator", "children_ids": [2], "parameters": {}},
		{"id": 2, "children_ids": [], "parameters": {}}
	]}
	_check(BTTree.from_dict(leaf_with_kid, registry) == null, "registry leaf task with one child rejected by from_dict")

# ------------------------------------------------------------- Fix: S6
func _test_registry_category_override() -> void:
	var registry := BTTaskRegistry.new()
	registry.register_task("CustomActionTask", func(): return BTTask.new(), "Action")
	# The registered task sits under a builtin root; set_root would relabel the
	# root itself, so the child carries the observable category.
	var data := {"root_id": 1, "nodes": [
		{"id": 1, "type_name": "Sequence", "children_ids": [2, 3], "parameters": {}},
		{"id": 2, "type_name": "CustomActionTask", "category": "Condition", "children_ids": [], "parameters": {}},
		{"id": 3, "type_name": "NoSuchTask", "category": "Condition", "children_ids": [], "parameters": {}}
	]}
	var tree := BTTree.from_dict(data, registry)
	_check(tree != null and tree.get_node_by_id(2).category == "Action", "registry category overrides JSON category for known types")
	_check(tree != null and tree.get_node_by_id(3).category == "Condition", "JSON category remains the fallback for unknown types")

# ------------------------------------------------------------- Fix: P12/P18
func _test_nonfinite_and_rejected_encodings() -> void:
	var tree := BTTree.new()
	tree.set_root(BTTask.new())
	tree.blackboard.set_var("pos_inf", INF)
	tree.blackboard.set_var("neg_inf", -INF)
	tree.blackboard.set_var("not_a_number", NAN)
	var encoded := tree.to_dict()
	_check(BTTree.validate_dict(encoded).is_empty(), "non-finite floats encode to valid tagged values")
	var restored := BTTree.from_dict(JSON.parse_string(JSON.stringify(encoded)))
	_check(restored != null and restored.blackboard.get_var("pos_inf") == INF, "INF survives JSON roundtrip")
	_check(restored != null and restored.blackboard.get_var("neg_inf") == -INF, "-INF survives JSON roundtrip")
	_check(restored != null and is_nan(float(restored.blackboard.get_var("not_a_number"))), "NaN survives JSON roundtrip")

	_check(not BTTree.validate_dict({"root_id": 1, "nodes": [{"id": 1, "children_ids": [], "parameters": {"x": INF}}]}).is_empty(), "raw non-finite float remains invalid")
	_check(not BTTree.validate_dict({"root_id": 1, "nodes": [{"id": 1, "children_ids": [], "parameters": {"x": {"__bt_type": "float", "value": "bogus"}}}]}).is_empty(), "malformed float tag rejected")
	_check(not BTTree.validate_dict({"root_id": 1, "nodes": [{"id": 1, "children_ids": [], "parameters": {"x": {"__bt_type": "float", "value": "inf", "extra": 1}}}]}).is_empty(), "float tag with extra keys rejected")
	_check(not BTTree.validate_dict({"root_id": 1, "nodes": [{"id": 1, "children_ids": [], "parameters": {"cb": Callable()}}]}).is_empty(), "Callable parameter values rejected")
	_check(not BTTree.validate_dict({"root_id": 1, "nodes": [{"id": 1, "children_ids": [], "parameters": {"rid": RID()}}]}).is_empty(), "RID parameter values rejected")
	var probe_node := Node.new()
	_check(not BTTree.validate_dict({"root_id": 1, "nodes": [{"id": 1, "children_ids": [], "parameters": {}}], "blackboard": {"n": {"value": probe_node}}}).is_empty(), "Object blackboard values rejected")
	probe_node.free()

# ------------------------------------------------------------- Fix: P12/P18 save validation
func _test_save_tree_validation() -> void:
	var dir_a := "user://bt_model_save_a"
	DirAccess.make_dir_recursive_absolute(dir_a)
	var source := BTFileTreeSource.new(dir_a)

	var keep := BTTree.new()
	keep.set_root(BTTask.new())
	keep.tree_name = "keep"
	_check(source.save_tree("keep", keep), "valid tree saves to file source")

	var broken := BTTree.new()
	broken.set_root(BTTask.new())
	var node_value := Node.new()
	broken.blackboard.set_var("target", node_value)
	_check(not source.save_tree("keep", broken), "tree with Object in blackboard rejected by file save")
	var reloaded := source.load_tree("keep")
	_check(reloaded != null and reloaded.tree_name == "keep", "rejected save leaves the original file untouched")
	_check(not source.save_tree("fresh_bad", broken), "invalid tree does not save under a new identifier")
	_check(not FileAccess.file_exists(dir_a + "/fresh_bad.json"), "invalid tree creates no new file")

	var memory := BTMemoryTreeSource.new()
	memory.register_tree("alive", keep)
	_check(not memory.save_tree("alive", broken), "memory source rejects an invalid tree")
	_check(memory.load_tree("alive") == keep, "memory source keeps the previous tree after a rejected save")
	var live := BTTree.new()
	live.set_root(BTTask.new())
	_check(memory.save_tree("mem", live), "memory source stores a valid tree")
	_check(memory.load_tree("mem") == live, "memory source stores the live tree without cloning")
	node_value.free()

	for path in [dir_a + "/keep.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir_a))

# ------------------------------------------------------------- Fix: P11/B5
func _test_file_source_paths() -> void:
	var dir_a := "user://bt_model_paths_a"
	var dir_other := "user://bt_model_paths_other"
	DirAccess.make_dir_recursive_absolute(dir_a)
	DirAccess.make_dir_recursive_absolute(dir_other)
	var foo_path := dir_other + "/foo.json"

	var foo_tree := BTTree.new()
	foo_tree.set_root(BTComposite.BTSequence.new())
	foo_tree.tree_name = "original-foo"
	_write_tree_fixture(foo_path, foo_tree.to_dict())

	var source := BTFileTreeSource.new(dir_a)
	_check(not source.list_trees().has("foo"), "source directory starts without the external tree")

	var loaded := source.load_tree(foo_path)
	_check(loaded != null, "loading by full path outside the source directory works")

	var edited := BTTree.new()
	edited.set_root(BTComposite.BTSequence.new())
	edited.tree_name = "updated-foo"
	_check(source.save_tree("foo", edited), "saving by basename after a path load succeeds")
	_check(_read_file_text(foo_path).contains("updated-foo"), "save by basename updates the originally loaded file")
	_check(not FileAccess.file_exists(dir_a + "/foo.json"), "save by basename creates no copy in the source directory")

	var fresh := BTTree.new()
	fresh.set_root(BTComposite.BTSequence.new())
	fresh.tree_name = "new-tree"
	_check(source.save_tree("new.json", fresh), "saving a relative .json identifier succeeds")
	_check(FileAccess.file_exists(dir_a + "/new.json"), "relative .json identifier lands in the source directory")

	var extra_path := dir_a + "/fresh.json"
	var extra := BTTree.new()
	extra.set_root(BTTask.new())
	_write_tree_fixture(extra_path, extra.to_dict())
	_check(not source.list_trees().has("fresh"), "newly written file is not listed before refresh")
	source.refresh()
	_check(source.list_trees().has("fresh"), "refresh lists a newly written file")
	_check(source.load_tree("fresh") != null, "refreshed file loads by basename")
	_check(str(source.get_tree_path("fresh")).begins_with("user://"), "scanned paths stay in res:// or user:// form")
	_check(source.save_tree("foo", edited), "basename mapping to the external file survives refresh")

	for path in [foo_path, dir_a + "/new.json", extra_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir_a))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir_other))

# ------------------------------------------------------------- Fix: E3
func _test_reparent() -> void:
	var tree := BTTree.new()
	var root := BTComposite.BTSequence.new()
	tree.set_root(root)
	var a := BTComposite.BTSelector.new()
	var b := BTComposite.BTSequence.new()
	tree.connect_parent_child(root, a)
	tree.connect_parent_child(root, b)
	var leaf := BTTask.new()
	tree.connect_parent_child(a, leaf)
	_check(leaf.parent == a, "leaf starts under parent A")

	tree.connect_parent_child(b, leaf)
	_check(leaf.parent == b, "reparenting moves the child to parent B")
	_check(b.children.has(leaf), "new parent holds the reparented child")
	_check(not a.children.has(leaf), "old parent releases the reparented child")
	_check(root.children.size() == 2, "reparent does not duplicate the node")

	tree.connect_parent_child(b, root)
	_check(root.parent == null, "connecting an ancestor as a child is refused")
	tree.connect_parent_child(leaf, root)
	_check(root.parent == null, "connecting to a leaf parent is refused")

	var deco := BTDecorator.BTInverter.new()
	tree.connect_parent_child(root, deco)
	var first := BTTask.new()
	tree.connect_parent_child(deco, first)
	var holder := BTComposite.BTSequence.new()
	tree.connect_parent_child(root, holder)
	var second := BTTask.new()
	tree.connect_parent_child(holder, second)
	tree.connect_parent_child(deco, second)
	_check(deco.children.size() == 1 and deco.children[0] == first, "decorator still refuses a second child")
	_check(second.parent == holder and holder.children.has(second), "refused child stays with its existing parent")

# ------------------------------------------------------------- Fix: M10
func _test_subtree_caching() -> void:
	var path_a := "user://bt_model_cache_a.json"
	var path_b := "user://bt_model_cache_b.json"
	var registry := BTTaskRegistry.new()
	registry.register_task("CacheProbeA", func(): return CacheProbeA.new(), "Action")
	registry.register_task("CacheProbeB", func(): return CacheProbeB.new(), "Action")
	var dict_a := {"root_id": 1, "nodes": [{"id": 1, "type_name": "CacheProbeA", "children_ids": [], "parameters": {}}]}
	var dict_b := {"root_id": 1, "nodes": [{"id": 1, "type_name": "CacheProbeB", "children_ids": [], "parameters": {}}]}
	_write_tree_fixture(path_a, dict_a)
	_write_tree_fixture(path_b, dict_b)

	var parent_tree := BTTree.new()
	parent_tree.registry = registry
	var subtree := BTSubTree.new(path_a)
	parent_tree.set_root(subtree)
	var runner := BTRunner.new(parent_tree)
	runner.start()
	_check(runner.tick(0.1) == BTStatus.SUCCESS, "cached subtree first run succeeds")
	_check(int(parent_tree.blackboard.get_var("cache_calls", 0)) == 1, "subtree task executed once")
	_check(not bool(parent_tree.blackboard.get_var("cache_version_b", false)), "version B task not yet seen")

	# Rewrite the file on disk: the cached parse must be reused across a restart.
	_write_tree_fixture(path_a, dict_b)
	runner.start()
	_check(runner.tick(0.1) == BTStatus.SUCCESS, "cached subtree second run succeeds")
	_check(int(parent_tree.blackboard.get_var("cache_calls", 0)) == 2, "cached subtree reruns the old parsed tree")
	_check(not bool(parent_tree.blackboard.get_var("cache_version_b", false)), "rewritten file is not reloaded while tree_path is unchanged")

	# Changing tree_path forces a reload from the new file.
	subtree.tree_path = path_b
	subtree.parameters["tree_path"] = path_b
	runner.start()
	_check(runner.tick(0.1) == BTStatus.SUCCESS, "subtree runs after tree_path change")
	_check(bool(parent_tree.blackboard.get_var("cache_version_b", false)), "changing tree_path reloads the new file")

	runner.stop()
	runner.free()
	await process_frame
	for path in [path_a, path_b]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _read_file_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: ", label)
