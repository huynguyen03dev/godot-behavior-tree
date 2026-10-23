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

class DuckParent extends BTParentTask:
	# Custom parents extend BTParentTask: the native runner only ticks children
	# of parent-capable kinds, so a leaf task holding children is rejected.
	func on_update() -> int:
		return BTStatus.SUCCESS

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_failures = 0
	_checks = 0
	_purge_user_scratch()
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
	_test_round2_fixes()
	_test_extended_encodings_and_whitelist()
	_test_id_alloc_perf()
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
	child_tree.blackboard.set_var("actor_seen", false)
	child_tree.blackboard.set_var("delta_seen", 0.0)
	child_tree.blackboard.set_var("calls", 0)
	child_tree.blackboard.set_var("runtime_task_ref", null)
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
	_check(not BTTree.validate_dict(fake).is_empty(), "validate_dict without registry rejects a leaf task holding children (no permissive fallback)")
	_check((not BTTree.validate_dict(fake).is_empty()) and (BTTree.from_dict(fake) == null), "validate_dict and from_dict share identical rejection verdict without registry")

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
	var dict_a := {
		"root_id": 1,
		"nodes": [{"id": 1, "type_name": "CacheProbeA", "children_ids": [], "parameters": {}}],
		"blackboard": {
			"cache_calls": {"type_name": "int", "value": 0, "is_shared": true}
		}
	}
	var dict_b := {
		"root_id": 1,
		"nodes": [{"id": 1, "type_name": "CacheProbeB", "children_ids": [], "parameters": {}}],
		"blackboard": {
			"cache_calls": {"type_name": "int", "value": 0, "is_shared": true},
			"cache_version_b": {"type_name": "bool", "value": false, "is_shared": true}
		}
	}
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

func _purge_user_scratch() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	var to_delete: Array[String] = []
	while name != "":
		if name.begins_with("bt_"):
			to_delete.append("user://" + name)
		name = dir.get_next()
	dir.list_dir_end()
	for path in to_delete:
		_delete_recursive(path)

func _delete_recursive(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		var sub := DirAccess.open(path)
		if sub != null:
			sub.list_dir_begin()
			var n := sub.get_next()
			while n != "":
				if n != "." and n != "..":
					_delete_recursive(path + "/" + n)
				n = sub.get_next()
			sub.list_dir_end()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _test_round2_fixes() -> void:
	# ------------------------------------------------------------- Fix: L4
	# connect_parent_child refuses when child_task == tree.root_task
	var l4_tree := BTTree.new()
	var l4_root := BTComposite.BTSequence.new()
	l4_tree.set_root(l4_root)
	var l4_child := BTTask.new()
	l4_tree.connect_parent_child(l4_root, l4_child)
	var l4_orphan := BTComposite.BTSequence.new()
	l4_tree.add_node(l4_orphan)
	l4_tree.connect_parent_child(l4_orphan, l4_root)
	_check(l4_root.parent == null, "L4 connect_parent_child refuses reparenting root_task under orphan")
	_check(not l4_orphan.children.has(l4_root), "L4 orphan does not receive root_task as child")

	# ------------------------------------------------------------- Fix: M1
	# Memoize the parent-shape decision inside validate_dict per type_name
	var m1_registry := BTTaskRegistry.new()
	var m1_counter := [0]
	m1_registry.register_task("M1ShapeTask", func():
		m1_counter[0] += 1
		return BTComposite.BTSequence.new()
	, "Composite")
	var m1_data := {
		"root_id": 1,
		"nodes": [
			{"id": 1, "type_name": "M1ShapeTask", "children_ids": [2, 3], "parameters": {}},
			{"id": 2, "type_name": "M1ShapeTask", "children_ids": [4], "parameters": {}},
			{"id": 3, "type_name": "M1ShapeTask", "children_ids": [5], "parameters": {}},
			{"id": 4, "type_name": "BTTask", "children_ids": [], "parameters": {}},
			{"id": 5, "type_name": "BTTask", "children_ids": [], "parameters": {}}
		]
	}
	var m1_errors := BTTree.validate_dict(m1_data, m1_registry)
	_check(m1_errors.is_empty(), "M1 validation succeeds for custom parent tasks")
	_check(m1_counter[0] == 1, "M1 shape decision memoized: created task once for 3 nodes of same type_name (creates=%d)" % m1_counter[0])

	# ------------------------------------------------------------- Fix: M4
	# Custom parents (BTParentTask subclasses registered under a custom type)
	var m4_registry := BTTaskRegistry.new()
	m4_registry.register_task("DuckParent", func(): return DuckParent.new(), "Action")
	var m4_data := {
		"root_id": 1,
		"nodes": [
			{"id": 1, "type_name": "DuckParent", "children_ids": [2], "parameters": {}},
			{"id": 2, "type_name": "BTTask", "children_ids": [], "parameters": {}}
		]
	}
	var m4_errors := BTTree.validate_dict(m4_data, m4_registry)
	_check(m4_errors.is_empty(), "M4 DuckParent validates with child: %s" % str(m4_errors))
	var m4_tree := BTTree.from_dict(m4_data, m4_registry)
	_check(m4_tree != null and m4_tree.root_task != null, "M4 DuckParent loads via from_dict")
	_check(m4_tree != null and m4_tree.root_task.get("children") is Array and m4_tree.root_task.children.size() == 1, "M4 DuckParent retains child in children array")

	# ------------------------------------------------------------- Fix: M3
	# Persist direct config assignment via schema & composite abort_type
	var m3_tree := BTTree.new()
	var m3_repeater := BTDecorator.BTRepeater.new()
	m3_repeater.count = 5
	m3_repeater.repeat_forever = true
	m3_repeater.end_on_failure = true
	var m3_composite := BTComposite.BTSelector.new()
	m3_composite.abort_type = BTComposite.AbortType.BOTH
	var m3_leaf := BTTask.new()
	m3_tree.set_root(m3_repeater)
	m3_tree.connect_parent_child(m3_repeater, m3_composite)
	m3_tree.connect_parent_child(m3_composite, m3_leaf)
	var m3_dict := m3_tree.to_dict()
	var m3_reloaded := BTTree.from_dict(m3_dict)
	_check(m3_reloaded != null, "M3 tree reloads from dict")
	if m3_reloaded != null:
		var rep: BTDecorator.BTRepeater = m3_reloaded.root_task as BTDecorator.BTRepeater
		_check(rep != null and rep.count == 5, "M3 rep.count = 5 persisted directly")
		_check(rep != null and rep.repeat_forever == true, "M3 rep.repeat_forever = true persisted directly")
		_check(rep != null and rep.end_on_failure == true, "M3 rep.end_on_failure = true persisted directly")
		var comp: BTComposite = rep.children[0] as BTComposite if rep != null and rep.children.size() > 0 else null
		_check(comp != null and comp.abort_type == BTComposite.AbortType.BOTH, "M3 composite abort_type = BOTH persisted directly")

	# ------------------------------------------------------------- Fix: M2, L5, N9
	var dir_a := "user://bt_m2_dir_a"
	var dir_b := "user://bt_m2_dir_b"
	DirAccess.make_dir_recursive_absolute(dir_a)
	DirAccess.make_dir_recursive_absolute(dir_b)
	var path_a_shared := dir_a + "/shared.json"
	var path_b_shared := dir_b + "/shared.json"

	var tree_a := BTTree.new(); tree_a.set_root(BTTask.new()); tree_a.tree_name = "tree-A"
	var tree_b := BTTree.new(); tree_b.set_root(BTTask.new()); tree_b.tree_name = "tree-B"
	_write_tree_fixture(path_a_shared, tree_a.to_dict())
	_write_tree_fixture(path_b_shared, tree_b.to_dict())

	var fsource := BTFileTreeSource.new(dir_a)
	# Precondition: dir_a contains shared.json, so _tree_files["shared"] -> path_a_shared
	_check(fsource.list_trees().has("shared"), "M2 dir_a lists shared tree")
	# Load external b/shared.json
	var loaded_b := fsource.load_tree(path_b_shared)
	_check(loaded_b != null and loaded_b.tree_name == "tree-B", "M2 loaded external b/shared.json")
	# load_tree("shared") must still load dir_a's shared.json
	var loaded_shared := fsource.load_tree("shared")
	_check(loaded_shared != null and loaded_shared.tree_name == "tree-A", "M2 load_tree('shared') still returns in-directory a/shared.json")
	# Saving the external file by full path must not hijack the a/ mapping
	var tree_b_edited := BTTree.new(); tree_b_edited.set_root(BTTask.new()); tree_b_edited.tree_name = "tree-B-edited"
	var saved_ext := fsource.save_tree(path_b_shared, tree_b_edited)
	_check(saved_ext, "M2 saving external tree by full path succeeds")
	_check(fsource.get_tree_path("shared") == path_a_shared, "M2 basename mapping 'shared' still points to dir_a path")

	# L5: save_tree pushes error and sets last_error when file cannot be opened
	var obstacle_file := "user://bt_obstacle_file.tmp"
	_write_tree_fixture(obstacle_file, {})
	var uncreatable_path := obstacle_file + "/cannot_create.json"
	var l5_saved := fsource.save_tree(uncreatable_path, tree_a)
	_check(not l5_saved, "L5 save_tree into uncreatable path returns false")
	_check(fsource.last_error.contains("failed to open file for writing"), "L5 last_error contains open error: %s" % fsource.last_error)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(obstacle_file))

	# N9: refresh drops deleted in-directory files, preserves external mappings
	var temp_in_dir := dir_a + "/deleteme.json"
	_write_tree_fixture(temp_in_dir, tree_a.to_dict())
	fsource.refresh()
	_check(fsource.list_trees().has("deleteme"), "N9 deleteme listed before removal")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_in_dir))
	fsource.refresh()
	_check(not fsource.list_trees().has("deleteme"), "N9 deleted in-directory file dropped after refresh")
	_check(fsource.get_tree_path(path_b_shared.get_file().get_basename()) == path_a_shared, "N9 shared mapping retained")

	# Clean up scratch dirs
	_delete_recursive(dir_a)
	_delete_recursive(dir_b)

# ------------------------------------------------------------- Fix 5: Extended math types & strict whitelist
func _test_extended_encodings_and_whitelist() -> void:
	var tree := BTTree.new()
	var root := BTTask.new()
	tree.set_root(root)

	var v2i := Vector2i(10, 20)
	var v3i := Vector3i(1, 2, 3)
	var v4 := Vector4(1.0, 2.0, 3.0, 4.0)
	var v4i := Vector4i(10, 20, 30, 40)
	var r2 := Rect2(1.0, 2.0, 3.0, 4.0)
	var r2i := Rect2i(10, 20, 30, 40)
	var quat := Quaternion(0.0, 0.7071, 0.0, 0.7071)
	var plane := Plane(0.0, 1.0, 0.0, 5.0)
	var aabb := AABB(Vector3(1, 2, 3), Vector3(4, 5, 6))
	var t2d := Transform2D(0.5, Vector2(10, 20))
	var basis := Basis.IDENTITY
	var t3d := Transform3D.IDENTITY

	root.set_param("p_v2i", v2i)
	root.set_param("p_v3i", v3i)
	root.set_param("p_v4", v4)
	root.set_param("p_v4i", v4i)
	root.set_param("p_r2", r2)
	root.set_param("p_r2i", r2i)
	root.set_param("p_quat", quat)
	root.set_param("p_plane", plane)
	root.set_param("p_aabb", aabb)
	root.set_param("p_t2d", t2d)
	root.set_param("p_basis", basis)
	root.set_param("p_t3d", t3d)

	tree.blackboard.set_var("bb_v2i", v2i)
	tree.blackboard.set_var("bb_v4i", v4i)

	var d := tree.to_dict()
	var errs := BTTree.validate_dict(d)
	_check(errs.is_empty(), "extended math types pass validate_dict: %s" % str(errs))

	var json_str := JSON.stringify(d)
	var parsed = JSON.parse_string(json_str)
	var loaded_tree := BTTree.from_dict(parsed)
	_check(loaded_tree != null, "tree with extended math types loads from JSON")

	var loaded_root: BTTask = loaded_tree.root_task
	_check(loaded_root.get_param("p_v2i") == v2i and typeof(loaded_root.get_param("p_v2i")) == TYPE_VECTOR2I, "Vector2i roundtrips with exact type")
	_check(loaded_root.get_param("p_v3i") == v3i and typeof(loaded_root.get_param("p_v3i")) == TYPE_VECTOR3I, "Vector3i roundtrips with exact type")
	_check(loaded_root.get_param("p_v4") == v4 and typeof(loaded_root.get_param("p_v4")) == TYPE_VECTOR4, "Vector4 roundtrips with exact type")
	_check(loaded_root.get_param("p_v4i") == v4i and typeof(loaded_root.get_param("p_v4i")) == TYPE_VECTOR4I, "Vector4i roundtrips with exact type")
	_check(loaded_root.get_param("p_r2") == r2 and typeof(loaded_root.get_param("p_r2")) == TYPE_RECT2, "Rect2 roundtrips with exact type")
	_check(loaded_root.get_param("p_r2i") == r2i and typeof(loaded_root.get_param("p_r2i")) == TYPE_RECT2I, "Rect2i roundtrips with exact type")
	_check(loaded_root.get_param("p_quat").is_equal_approx(quat) and typeof(loaded_root.get_param("p_quat")) == TYPE_QUATERNION, "Quaternion roundtrips with exact type")
	_check(loaded_root.get_param("p_plane").is_equal_approx(plane) and typeof(loaded_root.get_param("p_plane")) == TYPE_PLANE, "Plane roundtrips with exact type")
	_check(loaded_root.get_param("p_aabb").is_equal_approx(aabb) and typeof(loaded_root.get_param("p_aabb")) == TYPE_AABB, "AABB roundtrips with exact type")
	_check(loaded_root.get_param("p_t2d").is_equal_approx(t2d) and typeof(loaded_root.get_param("p_t2d")) == TYPE_TRANSFORM2D, "Transform2D roundtrips with exact type")
	_check(loaded_root.get_param("p_basis").is_equal_approx(basis) and typeof(loaded_root.get_param("p_basis")) == TYPE_BASIS, "Basis roundtrips with exact type")
	_check(loaded_root.get_param("p_t3d").is_equal_approx(t3d) and typeof(loaded_root.get_param("p_t3d")) == TYPE_TRANSFORM3D, "Transform3D roundtrips with exact type")
	_check(loaded_tree.blackboard.get_var("bb_v2i") == v2i, "Blackboard Vector2i roundtrips")
	_check(loaded_tree.blackboard.get_var("bb_v4i") == v4i, "Blackboard Vector4i roundtrips")

	# Strict whitelist tests:
	_check(not BTTree.validate_dict({"root_id": 1, "nodes": [{"id": 1, "children_ids": [], "parameters": {"bad": {"__bt_type": "UnknownCustom", "value": [1, 2]}}}]}).is_empty(), "unknown __bt_type rejected by whitelist")
	_check(not BTTree.validate_dict({"root_id": 1, "nodes": [{"id": 1, "children_ids": [], "parameters": {"bad": {"__bt_type": "Vector2i", "value": [1]}}}]}).is_empty(), "Vector2i with missing component rejected")
	_check(not BTTree.validate_dict({"root_id": 1, "nodes": [{"id": 1, "children_ids": [], "parameters": {"bad": {"__bt_type": "Vector2i", "value": [1.5, 2]}}}]}).is_empty(), "Vector2i with non-integer component rejected")
	_check(not BTTree.validate_dict({"root_id": 1, "nodes": [{"id": 1, "children_ids": [], "parameters": {"bad": {"__bt_type": "Vector4", "value": [1, 2, 3]}}}]}).is_empty(), "Vector4 with wrong component count rejected")

# ------------------------------------------------------------- Fix 7: Fast ID allocation & collision prevention
func _test_id_alloc_perf() -> void:
	var tree := BTTree.new()
	var root := BTTask.new()
	tree.set_root(root)
	_check(root.id == 1, "root task assigned id 1")

	for i in range(200):
		var leaf := BTTask.new()
		tree.add_node(leaf)

	_check(tree.node_list.size() == 201, "200 nodes added to tree")
	var id_set := {}
	var has_duplicate := false
	for node in tree.node_list:
		if id_set.has(node.id):
			has_duplicate = true
			break
		id_set[node.id] = true
	_check(not has_duplicate, "all allocated IDs are unique")

	# Test explicit ID jumps
	var explicit_node := BTTask.new()
	explicit_node.id = 500
	tree.add_node(explicit_node)
	_check(tree.get_node_by_id(500) == explicit_node, "explicit node id 500 added and retrievable via get_node_by_id")

	var next_node := BTTask.new()
	tree.add_node(next_node)
	_check(next_node.id == 501, "next auto-allocated id advances past explicit high id")

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
