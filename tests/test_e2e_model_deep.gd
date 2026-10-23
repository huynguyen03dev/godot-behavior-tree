extends SceneTree

var _checks := 0
var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(cond: bool, label: String, expected: Variant = true, actual: Variant = null) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label, "\n  expected: ", expected, "\n  actual:   ", actual)

func _finish() -> void:
	print("Model deep E2E: %d checks, %d failures" % [_checks, _failures])
	if _failures > 0:
		quit(1)
	else:
		quit(0)

func _approx_equal(a: Variant, b: Variant) -> bool:
	if (typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT) and (typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT):
		var fa := float(a)
		var fb := float(b)
		if is_nan(fa) and is_nan(fb):
			return true
		if is_inf(fa) and is_inf(fb):
			return (fa > 0.0) == (fb > 0.0)
		return is_equal_approx(fa, fb)

	if typeof(a) != typeof(b):
		return false

	match typeof(a):
		TYPE_VECTOR2:
			return (a as Vector2).is_equal_approx(b as Vector2)
		TYPE_VECTOR2I:
			return (a as Vector2i) == (b as Vector2i)
		TYPE_VECTOR3:
			return (a as Vector3).is_equal_approx(b as Vector3)
		TYPE_VECTOR3I:
			return (a as Vector3i) == (b as Vector3i)
		TYPE_VECTOR4:
			var v1 := a as Vector4
			var v2 := b as Vector4
			return is_equal_approx(v1.x, v2.x) and is_equal_approx(v1.y, v2.y) and is_equal_approx(v1.z, v2.z) and is_equal_approx(v1.w, v2.w)
		TYPE_VECTOR4I:
			return (a as Vector4i) == (b as Vector4i)
		TYPE_COLOR:
			return (a as Color).is_equal_approx(b as Color)
		TYPE_RECT2:
			return (a as Rect2).is_equal_approx(b as Rect2)
		TYPE_RECT2I:
			return (a as Rect2i) == (b as Rect2i)
		TYPE_QUATERNION:
			return (a as Quaternion).is_equal_approx(b as Quaternion)
		TYPE_PLANE:
			return (a as Plane).is_equal_approx(b as Plane)
		TYPE_AABB:
			return (a as AABB).is_equal_approx(b as AABB)
		TYPE_TRANSFORM2D:
			return (a as Transform2D).is_equal_approx(b as Transform2D)
		TYPE_BASIS:
			return (a as Basis).is_equal_approx(b as Basis)
		TYPE_TRANSFORM3D:
			return (a as Transform3D).is_equal_approx(b as Transform3D)
		TYPE_PROJECTION:
			var p1 := a as Projection
			var p2 := b as Projection
			for row in 4:
				for col in 4:
					if not is_equal_approx(p1[row][col], p2[row][col]):
						return false
			return true
		TYPE_ARRAY:
			var arr1 := a as Array
			var arr2 := b as Array
			if arr1.size() != arr2.size():
				return false
			for i in arr1.size():
				if not _approx_equal(arr1[i], arr2[i]):
					return false
			return true
		TYPE_DICTIONARY:
			var d1 := a as Dictionary
			var d2 := b as Dictionary
			if d1.size() != d2.size():
				return false
			for k in d1.keys():
				if not d2.has(k) or not _approx_equal(d1[k], d2[k]):
					return false
			return true
		_:
			return a == b

func _run() -> void:
	print("--- Running Model Deep E2E Tests ---")
	_test_group1_round_trip()
	_test_group2_corrupted_data()
	_test_group3_blackboard()
	_test_group4_param_binding()
	_test_group5_schema_coercion()
	_test_group6_id_and_reparent()
	_test_group7_stats_and_sources()
	_test_group8_large_trees()
	_finish()

# ==============================================================================
# GROUP 1: Round-trip: tree JSON -> from_dict -> to_dict -> from_dict stability
# Every encoded type: Vector2/2i/3/3i/4/4i, Color, Rect2/2i, Quaternion, Plane,
# AABB, Transform2D/3D, Basis, Projection, nested Array/Dict, float inf/-inf/nan.
# ==============================================================================
func _test_group1_round_trip() -> void:
	print("Running Group 1: Round-trip serialization & all encoded types...")
	var tree := BTTree.new()
	tree.tree_name = "RoundTripTree"
	tree.description = "Deep test for all types and serialization stability"
	tree.metadata = {
		"version": 42,
		"author": "QA",
		"tags": ["deep", "e2e"]
	}

	var root := BTComposite.BTSequence.new()
	root.abort_type = BTComposite.AbortType.BOTH
	tree.set_root(root)

	var leaf := BTTask.new()
	leaf.friendly_name = "TypeProbeLeaf"
	tree.connect_parent_child(root, leaf)

	var test_values := {
		"vec2": Vector2(1.5, -2.5),
		"vec2i": Vector2i(10, -20),
		"vec3": Vector3(1.1, 2.2, -3.3),
		"vec3i": Vector3i(100, 200, -300),
		"vec4": Vector4(1.0, 2.0, 3.0, -4.0),
		"vec4i": Vector4i(1, 2, 3, -4),
		"color": Color(0.2, 0.4, 0.6, 0.8),
		"rect2": Rect2(1.0, 2.0, 10.0, 20.0),
		"rect2i": Rect2i(1, 2, 10, 20),
		"quat": Quaternion(0.0, 0.707107, 0.0, 0.707107),
		"plane": Plane(0.0, 1.0, 0.0, 5.0),
		"aabb": AABB(Vector3(1, 2, 3), Vector3(4, 5, 6)),
		"xform2d": Transform2D(Vector2(1, 2), Vector2(3, 4), Vector2(5, 6)),
		"basis": Basis(Vector3(1, 0, 0), Vector3(0, 2, 0), Vector3(0, 0, 3)),
		"xform3d": Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)), Vector3(10, 20, 30)),
		"projection": Projection(Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 1)),
		"nested_dict": {"str": "hello", "arr": [1, 2, Vector2(3, 4)], "inner": {"c": Color.GREEN}},
		"float_inf": INF,
		"float_neg_inf": -INF,
		"float_nan": NAN,
	}

	for k in test_values.keys():
		leaf.set_param(k, test_values[k])

	for k in test_values.keys():
		tree.blackboard.set_var(k, test_values[k])
	var bb_var_obj: BTBlackboard.Variable = tree.blackboard.get_variable_obj("vec2")
	if bb_var_obj != null:
		bb_var_obj.is_shared = false
		bb_var_obj.description = "Private vec2 variable"

	var dict1 := tree.to_dict()
	var json_str := JSON.stringify(dict1)
	var dict1_parsed: Variant = JSON.parse_string(json_str)
	_check(dict1_parsed is Dictionary, "G1: JSON serialization produces valid dictionary")

	var tree2 := BTTree.from_dict(dict1_parsed as Dictionary)
	_check(tree2 != null, "G1: from_dict succeeds on serialized tree")
	if tree2 == null:
		return

	_check(tree2.tree_name == tree.tree_name, "G1: tree_name matches after round-trip", tree.tree_name, tree2.tree_name)
	_check(tree2.description == tree.description, "G1: description matches after round-trip", tree.description, tree2.description)
	_check(tree2.metadata.get("version") == 42, "G1: metadata matches after round-trip", 42, tree2.metadata.get("version"))
	_check(tree2.get_node_count() == 2, "G1: node count matches after round-trip", 2, tree2.get_node_count())
	_check(tree2.root_task != null and tree2.root_task.id == root.id, "G1: root_task id matches", root.id, tree2.root_task.id if tree2.root_task else -1)
	_check(tree2.root_task.abort_type == BTComposite.AbortType.BOTH, "G1: composite abort_type preserved", BTComposite.AbortType.BOTH, tree2.root_task.abort_type)

	var leaf2 := tree2.get_node_by_id(leaf.id)
	_check(leaf2 != null, "G1: leaf retrieved by id in tree2")
	if leaf2 != null:
		_check(leaf2.parent == tree2.root_task, "G1: leaf parent pointer restored correctly")
		_check(tree2.root_task.children.size() == 1 and tree2.root_task.children[0] == leaf2, "G1: root children array restored correctly")

		for k in test_values.keys():
			var expected_val = test_values[k]
			var actual_val = leaf2.get_param(k)
			_check(_approx_equal(expected_val, actual_val), "G1: task param '%s' round-trips correctly" % k, expected_val, actual_val)

	for k in test_values.keys():
		var expected_val = test_values[k]
		var actual_val = tree2.blackboard.get_var(k)
		_check(_approx_equal(expected_val, actual_val), "G1: blackboard var '%s' round-trips correctly" % k, expected_val, actual_val)

	var bb2_var_obj: BTBlackboard.Variable = tree2.blackboard.get_variable_obj("vec2")
	_check(bb2_var_obj != null and bb2_var_obj.is_shared == false, "G1: blackboard variable is_shared preserved as false", false, bb2_var_obj.is_shared if bb2_var_obj else null)
	_check(bb2_var_obj != null and bb2_var_obj.description == "Private vec2 variable", "G1: blackboard variable description preserved", "Private vec2 variable", bb2_var_obj.description if bb2_var_obj else null)

	var dict2 := tree2.to_dict()
	var tree3 := BTTree.from_dict(dict2)
	_check(tree3 != null, "G1: tree3 created from dict2")
	if tree3 != null:
		var dict3 := tree3.to_dict()
		_check(dict2.get("root_id") == dict3.get("root_id"), "G1: idempotent root_id", dict2.get("root_id"), dict3.get("root_id"))
		_check(dict2.get("tree_name") == dict3.get("tree_name"), "G1: idempotent tree_name", dict2.get("tree_name"), dict3.get("tree_name"))
		_check(dict2.get("nodes").size() == dict3.get("nodes").size(), "G1: idempotent nodes size", dict2.get("nodes").size(), dict3.get("nodes").size())

# ==============================================================================
# GROUP 2: Corrupted & Malformed Data
# validate_dict must return descriptive errors; from_dict must return null
# (never crash, never create a half-baked tree).
# ==============================================================================
func _make_valid_tree_dict() -> Dictionary:
	return {
		"tree_name": "BaseValid",
		"description": "Template",
		"root_id": 1,
		"nodes": [
			{
				"id": 1,
				"friendly_name": "Seq",
				"type_name": "Sequence",
				"category": "Composite",
				"is_placeholder": false,
				"parent_id": -1,
				"children_ids": [2],
				"parameters": {}
			},
			{
				"id": 2,
				"friendly_name": "Leaf",
				"type_name": "BTTask",
				"category": "Task",
				"is_placeholder": false,
				"parent_id": 1,
				"children_ids": [],
				"parameters": {}
			}
		],
		"blackboard": {},
		"metadata": {}
	}

func _assert_corrupted(data: Dictionary, label: String, expected_error_substr: String = "") -> void:
	var errors := BTTree.validate_dict(data)
	_check(errors.size() > 0, "G2: validate_dict flags %s" % label, "errors.size() > 0", "got %d errors" % errors.size())
	if expected_error_substr != "":
		var found := false
		for err in errors:
			if err.find(expected_error_substr) != -1:
				found = true
				break
		_check(found, "G2: error description for %s contains '%s'" % [label, expected_error_substr], expected_error_substr, str(errors))
	var tree = BTTree.from_dict(data)
	_check(tree == null, "G2: from_dict returns null for %s" % label, null, tree)

func _test_group2_corrupted_data() -> void:
	print("Running Group 2: Corrupted data rejection...")

	# 1. nodes not an array
	var d := _make_valid_tree_dict()
	d["nodes"] = "not_an_array"
	_assert_corrupted(d, "nodes is string", "nodes must be an array")

	d = _make_valid_tree_dict()
	d["nodes"] = 123
	_assert_corrupted(d, "nodes is int", "nodes must be an array")

	d = _make_valid_tree_dict()
	d["nodes"] = {}
	_assert_corrupted(d, "nodes is dictionary", "nodes must be an array")

	# 2. Duplicate node id
	d = _make_valid_tree_dict()
	d["nodes"][1]["id"] = 1
	_assert_corrupted(d, "duplicate node id", "invalid or duplicate node id")

	# 3. Negative node id
	d = _make_valid_tree_dict()
	d["nodes"][1]["id"] = -5
	_assert_corrupted(d, "negative node id", "invalid or duplicate node id")

	# 4. Non-integer node id
	d = _make_valid_tree_dict()
	d["nodes"][1]["id"] = 1.5
	_assert_corrupted(d, "float node id 1.5", "must have an integer id")

	d = _make_valid_tree_dict()
	d["nodes"][1]["id"] = "two"
	_assert_corrupted(d, "string node id", "must have an integer id")

	d = _make_valid_tree_dict()
	d["nodes"][1]["id"] = null
	_assert_corrupted(d, "null node id", "must have an integer id")

	# 5. children_ids references missing child
	d = _make_valid_tree_dict()
	d["nodes"][0]["children_ids"] = [999]
	_assert_corrupted(d, "missing child 999", "references missing child")

	# 6. Multiple parents
	d = {
		"root_id": 1,
		"nodes": [
			{"id": 1, "type_name": "Sequence", "children_ids": [2, 3], "parameters": {}},
			{"id": 2, "type_name": "Sequence", "children_ids": [3], "parameters": {}},
			{"id": 3, "type_name": "BTTask", "children_ids": [], "parameters": {}}
		]
	}
	_assert_corrupted(d, "multiple parents for node 3", "multiple parents")

	# 7. Root has a parent
	d = {
		"root_id": 1,
		"nodes": [
			{"id": 1, "type_name": "Sequence", "children_ids": [2], "parameters": {}},
			{"id": 2, "type_name": "Sequence", "children_ids": [1], "parameters": {}}
		]
	}
	_assert_corrupted(d, "root has parent", "root node cannot have a parent")

	# 8. Cycles
	# 2-node cycle (root 1 -> 2, and 2 -> 1, but root 1 having parent was tested; let's test child cycle: root 1 -> 2 -> 3 -> 2)
	d = {
		"root_id": 1,
		"nodes": [
			{"id": 1, "type_name": "Sequence", "children_ids": [2], "parameters": {}},
			{"id": 2, "type_name": "Sequence", "children_ids": [3], "parameters": {}},
			{"id": 3, "type_name": "Sequence", "children_ids": [2], "parameters": {}}
		]
	}
	_assert_corrupted(d, "2-node cycle between children", "multiple parents")

	# Cycle without multiple parents (e.g. root cycle when root_id not pointing to cycle root, or pure cycle)
	d = {
		"root_id": 1,
		"nodes": [
			{"id": 1, "type_name": "Sequence", "children_ids": [2], "parameters": {}},
			{"id": 2, "type_name": "Sequence", "children_ids": [3], "parameters": {}},
			{"id": 3, "type_name": "Sequence", "children_ids": [1], "parameters": {}}
		]
	}
	_assert_corrupted(d, "3-node cycle", "cycle")

	# 9. Decorator with multiple children
	d = {
		"root_id": 1,
		"nodes": [
			{"id": 1, "type_name": "Inverter", "children_ids": [2, 3], "parameters": {}},
			{"id": 2, "type_name": "BTTask", "children_ids": [], "parameters": {}},
			{"id": 3, "type_name": "BTTask", "children_ids": [], "parameters": {}}
		]
	}
	_assert_corrupted(d, "decorator with multiple children", "decorator 1 has multiple children")

	# 10. Leaf node has children
	# Consistent validation: without a registry, validate_dict uses the default facade
	# registry just like from_dict. BTTask is known to be a leaf and rejected if it has children.
	d = {
		"root_id": 1,
		"nodes": [
			{"id": 1, "type_name": "Sequence", "children_ids": [2], "parameters": {}},
			{"id": 2, "type_name": "BTTask", "children_ids": [3], "parameters": {}},
			{"id": 3, "type_name": "BTTask", "children_ids": [], "parameters": {}}
		]
	}
	# a) validate_dict without registry: flags leaf node having children
	var errs_no_reg := BTTree.validate_dict(d)
	var found_leaf_err_no_reg := false
	for err in errs_no_reg:
		if err.find("cannot hold them") != -1:
			found_leaf_err_no_reg = true
			break
	_check(found_leaf_err_no_reg, "G2: validate_dict without registry flags leaf node with children containing 'cannot hold them'", true, str(errs_no_reg))

	# b) validate_dict with explicit registry: flags leaf node having children
	var reg := BTTaskRegistry.new()
	var errs_reg := BTTree.validate_dict(d, reg)
	var found_leaf_err := false
	for err in errs_reg:
		if err.find("cannot hold them") != -1:
			found_leaf_err = true
			break
	_check(found_leaf_err, "G2: validate_dict with registry flags leaf node with children containing 'cannot hold them'", true, str(errs_reg))

	# c) from_dict returns null and validate_dict / from_dict share consistent verdict
	var tree_no_reg = BTTree.from_dict(d)
	var tree_with_reg = BTTree.from_dict(d, reg)
	_check(tree_no_reg == null and tree_with_reg == null, "G2: from_dict returns null (strict default registry and explicit registry)", true, [tree_no_reg == null, tree_with_reg == null])
	_check((errs_no_reg.size() > 0) == (tree_no_reg == null), "G2: validate_dict and from_dict give consistent verdict (both error / both null)", true, [errs_no_reg.size() > 0, tree_no_reg == null])

	# 11. Metadata wrong type
	d = _make_valid_tree_dict()
	d["metadata"] = [1, 2, 3]
	_assert_corrupted(d, "metadata is array", "metadata must be a dictionary")

	# 12. Blackboard wrong type
	d = _make_valid_tree_dict()
	d["blackboard"] = "not_a_dict"
	_assert_corrupted(d, "blackboard is string", "blackboard must be a dictionary")

	# 13. Encoded values wrong shape/length/type
	var malformed_encodings := [
		["Vector2 len 1", {"__bt_type": "Vector2", "value": [1.0]}],
		["Vector2 len 3", {"__bt_type": "Vector2", "value": [1.0, 2.0, 3.0]}],
		["Vector2i float element", {"__bt_type": "Vector2i", "value": [1.5, 2.0]}],
		["Vector3 len 2", {"__bt_type": "Vector3", "value": [1.0, 2.0]}],
		["Vector3i non-int", {"__bt_type": "Vector3i", "value": [1, "bad", 3]}],
		["Vector4 len 3", {"__bt_type": "Vector4", "value": [1.0, 2.0, 3.0]}],
		["Vector4i float element", {"__bt_type": "Vector4i", "value": [1, 2, 3, 4.5]}],
		["Color len 5", {"__bt_type": "Color", "value": [1.0, 2.0, 3.0, 4.0, 5.0]}],
		["Rect2 len 3", {"__bt_type": "Rect2", "value": [1.0, 2.0, 3.0]}],
		["Rect2i float element", {"__bt_type": "Rect2i", "value": [1, 2, 3.5, 4]}],
		["Quaternion len 3", {"__bt_type": "Quaternion", "value": [1.0, 2.0, 3.0]}],
		["Plane len 3", {"__bt_type": "Plane", "value": [1.0, 2.0, 3.0]}],
		["AABB len 5", {"__bt_type": "AABB", "value": [1.0, 2.0, 3.0, 4.0, 5.0]}],
		["Transform2D len 5", {"__bt_type": "Transform2D", "value": [1, 2, 3, 4, 5]}],
		["Basis len 8", {"__bt_type": "Basis", "value": [1, 2, 3, 4, 5, 6, 7, 8]}],
		["Transform3D len 11", {"__bt_type": "Transform3D", "value": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]}],
		["Projection len 15", {"__bt_type": "Projection", "value": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]}],
		["float invalid string", {"__bt_type": "float", "value": "huge"}],
		["float non-string value", {"__bt_type": "float", "value": 123}],
		["unknown __bt_type", {"__bt_type": "UnsupportedType", "value": [1, 2]}],
		["extra key in tag", {"__bt_type": "Vector2", "value": [1.0, 2.0], "extra": 123}],
	]

	for item in malformed_encodings:
		var name: String = item[0]
		var bad_val = item[1]
		# In task parameters
		var d_param := _make_valid_tree_dict()
		d_param["nodes"][1]["parameters"] = {"bad": bad_val}
		_assert_corrupted(d_param, "param with " + name, "malformed encoded value")

		# In blackboard
		var d_bb := _make_valid_tree_dict()
		d_bb["blackboard"] = {"bad_bb": {"value": bad_val}}
		_assert_corrupted(d_bb, "blackboard with " + name, "malformed encoded value")

	# 14. Composite with invalid abort_type (> 3 or < 0 or non-int)
	d = _make_valid_tree_dict()
	d["nodes"][0]["parameters"]["abort_type"] = 5
	_assert_corrupted(d, "composite abort_type 5", "abort_type must be an integer from 0 to 3")

	d = _make_valid_tree_dict()
	d["nodes"][0]["parameters"]["abort_type"] = -1
	_assert_corrupted(d, "composite abort_type -1", "abort_type must be an integer from 0 to 3")

	d = _make_valid_tree_dict()
	d["nodes"][0]["parameters"]["abort_type"] = "invalid"
	_assert_corrupted(d, "composite abort_type string", "abort_type must be an integer from 0 to 3")

	# 15. Invalid root_id
	d = _make_valid_tree_dict()
	d["root_id"] = 999
	_assert_corrupted(d, "root_id non-existent", "root_id must identify an existing node")

	# 16. Empty tree
	d = _make_valid_tree_dict()
	d["nodes"] = []
	_assert_corrupted(d, "empty tree", "tree must contain nodes")

# ==============================================================================
# GROUP 3: Blackboard: scoping, shadowing, signals, and dynamic hierarchy
# ==============================================================================
func _test_group3_blackboard() -> void:
	print("Running Group 3: Blackboard scoping, shadowing, and signals...")

	var sig_events: Array = []
	var on_var_changed = func(vname: String, new_val, old_val):
		sig_events.append({"name": vname, "new": new_val, "old": old_val})

	# 1. Basic set_var and initial signal
	var bb_root := BTBlackboard.new()
	bb_root.variable_changed.connect(on_var_changed)
	sig_events.clear()
	bb_root.set_var("health", 100, "int")
	_check(bb_root.get_var("health") == 100, "G3: bb_root gets newly set var 'health'", 100, bb_root.get_var("health"))
	_check(sig_events.size() == 1, "G3: set_var emits exactly 1 signal on creation", 1, sig_events.size())
	if sig_events.size() > 0:
		_check(sig_events[0]["name"] == "health", "G3: signal var_name is 'health'", "health", sig_events[0]["name"])
		_check(sig_events[0]["new"] == 100, "G3: signal new_val is 100", 100, sig_events[0]["new"])
		_check(sig_events[0]["old"] == null, "G3: signal old_val is null on creation", null, sig_events[0]["old"])

	# Update existing var
	sig_events.clear()
	bb_root.set_var("health", 80)
	_check(bb_root.get_var("health") == 80, "G3: bb_root gets updated var 'health'", 80, bb_root.get_var("health"))
	_check(sig_events.size() == 1, "G3: set_var emits 1 signal on update", 1, sig_events.size())
	if sig_events.size() > 0:
		_check(sig_events[0]["new"] == 80, "G3: signal new_val is 80", 80, sig_events[0]["new"])
		_check(sig_events[0]["old"] == 100, "G3: signal old_val is 100 on update", 100, sig_events[0]["old"])

	# 2. Scoped inheritance: Child reads parent var
	var bb_child := BTBlackboard.new()
	bb_child.parent_scope = bb_root
	_check(bb_child.parent_scope == bb_root, "G3: parent_scope set successfully")
	_check(bb_child.has_var("health"), "G3: child has_var true for parent's var")
	_check(bb_child.get_var("health") == 80, "G3: child get_var returns parent's var value", 80, bb_child.get_var("health"))

	# 3. Write-through to ancestor when shared:
	var child_sig_events: Array = []
	var on_child_var_changed = func(vname: String, new_val, old_val):
		child_sig_events.append({"name": vname, "new": new_val, "old": old_val})
	bb_child.variable_changed.connect(on_child_var_changed)

	sig_events.clear()
	child_sig_events.clear()
	bb_child.set_var("health", 50)
	_check(bb_root.get_var("health") == 50, "G3: write-through updates ancestor's shared var", 50, bb_root.get_var("health"))
	_check(bb_child.get_var("health") == 50, "G3: child sees updated shared var", 50, bb_child.get_var("health"))
	_check(not bb_child.get_all_variables().has("health"), "G3: shared var not stored locally in child")
	_check(sig_events.size() == 1, "G3: ancestor emits variable_changed on write-through", 1, sig_events.size())
	if sig_events.size() > 0:
		_check(sig_events[0]["new"] == 50 and sig_events[0]["old"] == 80, "G3: ancestor signal has correct old/new")
	_check(child_sig_events.size() == 0, "G3: child does not emit signal when write-through went to parent", 0, child_sig_events.size())

	# 4. Shadowing: Private variable in ancestor creates local shadow in child
	sig_events.clear()
	bb_root.set_var_local("secret", "top_secret", "String", false) # is_shared = false
	_check(bb_root.has_var("secret"), "G3: bb_root has private var 'secret'")
	_check(bb_child.has_var("secret"), "G3: child has_var finds ancestor private var")
	_check(bb_child.get_var("secret") == "top_secret", "G3: child can read ancestor private var", "top_secret", bb_child.get_var("secret"))

	child_sig_events.clear()
	bb_child.set_var("secret", "local_override")
	_check(bb_root.get_var("secret") == "top_secret", "G3: ancestor private var NOT overwritten by child set_var", "top_secret", bb_root.get_var("secret"))
	_check(bb_child.get_var("secret") == "local_override", "G3: child gets local shadow value", "local_override", bb_child.get_var("secret"))
	_check(bb_child.get_all_variables().has("secret"), "G3: shadow var is stored locally in child")
	_check(child_sig_events.size() == 1, "G3: child emits signal when creating shadow var", 1, child_sig_events.size())
	if child_sig_events.size() > 0:
		_check(child_sig_events[0]["old"] == null, "G3: child shadow creation old_val is null", null, child_sig_events[0]["old"])

	# 5. set_var_local does not touch parent (even if parent has shared var)
	bb_child.set_var_local("health", 999, "int", false)
	_check(bb_child.get_var("health") == 999, "G3: child has local health 999", 999, bb_child.get_var("health"))
	_check(bb_root.get_var("health") == 50, "G3: parent health untouched by child set_var_local", 50, bb_root.get_var("health"))

	# 6. get_var defaults and non-existent
	_check(bb_child.get_var("missing", "fallback") == "fallback", "G3: get_var returns custom default", "fallback", bb_child.get_var("missing", "fallback"))
	_check(bb_child.get_var("missing") == null, "G3: get_var returns null by default", null, bb_child.get_var("missing"))
	_check(not bb_child.has_var("missing"), "G3: has_var false for missing key")

	# 7. remove_var: returns bool and emits signal
	child_sig_events.clear()
	var removed_nonexistent := bb_child.remove_var("does_not_exist")
	_check(not removed_nonexistent, "G3: remove_var returns false for non-existent key", false, removed_nonexistent)
	_check(child_sig_events.size() == 0, "G3: no signal emitted when removing non-existent key", 0, child_sig_events.size())

	var removed_health := bb_child.remove_var("health")
	_check(removed_health, "G3: remove_var returns true when removing existing local key", true, removed_health)
	_check(child_sig_events.size() == 1, "G3: remove_var emits 1 signal", 1, child_sig_events.size())
	if child_sig_events.size() > 0:
		_check(child_sig_events[0]["name"] == "health", "G3: remove_var signal name", "health", child_sig_events[0]["name"])
		_check(child_sig_events[0]["new"] == null, "G3: remove_var signal new_val is null", null, child_sig_events[0]["new"])
		_check(child_sig_events[0]["old"] == 999, "G3: remove_var signal old_val is previous value", 999, child_sig_events[0]["old"])

	# After removing local 'health', reading 'health' falls back to parent's 'health' (50)
	_check(bb_child.has_var("health"), "G3: after removing local health, child still sees parent health")
	_check(bb_child.get_var("health") == 50, "G3: child gets parent health value after local removal", 50, bb_child.get_var("health"))

	# 8. get_all_vars merges scopes in correct order (parent first, local wins)
	var bb_grandparent := BTBlackboard.new()
	var bb_p := BTBlackboard.new()
	var bb_c := BTBlackboard.new()
	bb_p.parent_scope = bb_grandparent
	bb_c.parent_scope = bb_p

	bb_grandparent.set_var("a", "gp_a")
	bb_grandparent.set_var("b", "gp_b")
	bb_grandparent.set_var("c", "gp_c")

	bb_p.set_var("b", "p_b") # overrides b
	bb_c.set_var("c", "c_c") # overrides c
	bb_c.set_var("d", "c_d") # child-only

	var all_vars := bb_c.get_all_vars()
	_check(all_vars.size() == 4, "G3: get_all_vars returns 4 merged keys", 4, all_vars.size())
	_check(all_vars.get("a") == "gp_a", "G3: all_vars 'a' is from grandparent", "gp_a", all_vars.get("a"))
	_check(all_vars.get("b") == "p_b", "G3: all_vars 'b' is overridden by parent", "p_b", all_vars.get("b"))
	_check(all_vars.get("c") == "c_c", "G3: all_vars 'c' is overridden by child", "c_c", all_vars.get("c"))
	_check(all_vars.get("d") == "c_d", "G3: all_vars 'd' is from child", "c_d", all_vars.get("d"))

	# 9. Dynamic parent_scope switching
	var bb_alt := BTBlackboard.new()
	bb_alt.set_var("alt_key", 777)
	bb_c.parent_scope = bb_alt
	_check(bb_c.has_var("alt_key"), "G3: child has_var for new parent_scope")
	_check(bb_c.get_var("alt_key") == 777, "G3: child get_var from new parent_scope", 777, bb_c.get_var("alt_key"))
	_check(not bb_c.has_var("a"), "G3: child no longer has_var from old parent_scope")
	bb_c.parent_scope = null
	_check(not bb_c.has_var("alt_key"), "G3: child has_var false after parent_scope cleared")

	# 10. clear() clears local vars
	bb_c.set_var("k1", 1)
	bb_c.clear()
	_check(bb_c.get_all_variables().size() == 0, "G3: clear() empties local variables", 0, bb_c.get_all_variables().size())

# ==============================================================================
# GROUP 4: Param binding: @key, $key, @@literal, $$literal, missing fallback & warn once
# ==============================================================================
func _test_group4_param_binding() -> void:
	print("Running Group 4: Param binding (@, $, @@, $$, missing fallback, warn once)...")

	var bb := BTBlackboard.new()
	bb.set_var("target_name", "Goblin")
	bb.set_var("speed", 4.5)
	bb.set_var("coords", Vector2(100, 200))

	var task := BTTask.new()
	task.blackboard = bb

	# 1. String binding format: @key and $key
	task.parameters["p_at"] = "@target_name"
	task.parameters["p_dollar"] = "$speed"
	task.parameters["p_vec"] = "@coords"

	_check(task.is_param_blackboard("p_at"), "G4: is_param_blackboard true for '@target_name'")
	_check(task.is_param_blackboard("p_dollar"), "G4: is_param_blackboard true for '$speed'")
	_check(task.get_param_blackboard_key("p_at") == "target_name", "G4: get_param_blackboard_key returns 'target_name'")
	_check(task.get_param_blackboard_key("p_dollar") == "speed", "G4: get_param_blackboard_key returns 'speed'")

	_check(task.get_param("p_at") == "Goblin", "G4: get_param resolves '@target_name' to 'Goblin'")
	_check(task.get_param("p_dollar") == 4.5, "G4: get_param resolves '$speed' to 4.5")
	_check(task.get_param("p_vec") == Vector2(100, 200), "G4: get_param resolves '@coords' to Vector2")

	# 2. Escaped literal: @@key and $$key
	task.parameters["p_esc_at"] = "@@literal_at"
	task.parameters["p_esc_dollar"] = "$$literal_dollar"

	_check(not task.is_param_blackboard("p_esc_at"), "G4: is_param_blackboard false for '@@literal_at'")
	_check(not task.is_param_blackboard("p_esc_dollar"), "G4: is_param_blackboard false for '$$literal_dollar'")
	_check(task.get_param_blackboard_key("p_esc_at") == "", "G4: get_param_blackboard_key empty for '@@'")
	_check(task.get_param_blackboard_key("p_esc_dollar") == "", "G4: get_param_blackboard_key empty for '$$'")
	_check(task.get_param("p_esc_at") == "@literal_at", "G4: get_param strips leading @ for @@", "@literal_at", task.get_param("p_esc_at"))
	_check(task.get_param("p_esc_dollar") == "$literal_dollar", "G4: get_param strips leading $ for $$", "$literal_dollar", task.get_param("p_esc_dollar"))

	# 3. Dictionary binding format: {is_blackboard: true, key: "target_name"}
	task.set_param("p_dict", "target_name", true)
	_check(task.is_param_blackboard("p_dict"), "G4: is_param_blackboard true for dict binding")
	_check(task.get_param_blackboard_key("p_dict") == "target_name", "G4: get_param_blackboard_key returns key for dict binding")
	_check(task.get_param("p_dict") == "Goblin", "G4: get_param resolves dict binding to 'Goblin'")

	# Non-blackboard dict
	task.parameters["p_regular_dict"] = {"is_blackboard": false, "key": "target_name"}
	_check(not task.is_param_blackboard("p_regular_dict"), "G4: is_param_blackboard false for dict with is_blackboard=false")
	_check(task.get_param_blackboard_key("p_regular_dict") == "", "G4: get_param_blackboard_key empty for non-bb dict")
	_check(task.get_param("p_regular_dict") is Dictionary, "G4: get_param returns raw dict when not bb")

	# 4. Missing key fallback + warn once (_warned_bindings)
	task.parameters["p_missing_str"] = "@missing_var"
	task.parameters["p_missing_dict"] = {"is_blackboard": true, "key": "missing_dict_var"}

	# First read: returns default_val and records in warned_bindings
	var res1 = task.get_param("p_missing_str", "default_val_1")
	_check(res1 == "default_val_1", "G4: missing str binding returns fallback default", "default_val_1", res1)
	var warned: Dictionary = task._warned_bindings
	_check(warned.has("p_missing_str"), "G4: _warned_bindings contains 'p_missing_str'")

	# Second read: still returns default_val
	var res2 = task.get_param("p_missing_str", "default_val_2")
	_check(res2 == "default_val_2", "G4: second read of missing str binding returns fallback default", "default_val_2", res2)

	# Missing dict binding
	var res3 = task.get_param("p_missing_dict", 999)
	_check(res3 == 999, "G4: missing dict binding returns fallback default", 999, res3)
	warned = task._warned_bindings
	_check(warned.has("p_missing_dict"), "G4: _warned_bindings contains 'p_missing_dict'")

	# Missing param completely (not in parameters dict)
	_check(task.get_param("completely_missing", 123) == 123, "G4: missing param name returns default")
	_check(not task.is_param_blackboard("completely_missing"), "G4: is_param_blackboard false for missing param name")
	_check(task.get_param_blackboard_key("completely_missing") == "", "G4: get_param_blackboard_key empty for missing param name")

# ==============================================================================
# GROUP 5: Schema coercion & persistence: Repeater, Cooldown, TimeLimit
# ==============================================================================
func _test_group5_schema_coercion() -> void:
	print("Running Group 5: Schema coercion and decorator parameter persistence...")

	# 1. Repeater: property setter -> to_dict persistence
	var tree := BTTree.new()
	var repeater := BTDecorator.BTRepeater.new()
	repeater.count = 7
	repeater.repeat_forever = true
	repeater.end_on_failure = true
	tree.set_root(repeater)

	var child := BTTask.new()
	tree.connect_parent_child(repeater, child)

	var schema: Dictionary = repeater.get_parameter_schema()
	_check(schema.has("count") and schema.has("repeat_forever") and schema.has("end_on_failure"), "G5: Repeater get_parameter_schema has all 3 keys")
	_check(schema["count"]["type"] == "int", "G5: count schema type is int")
	_check(schema["repeat_forever"]["type"] == "bool", "G5: repeat_forever schema type is bool")
	_check(schema["end_on_failure"]["type"] == "bool", "G5: end_on_failure schema type is bool")

	var tree_dict := tree.to_dict()
	var nodes_arr: Array = tree_dict.get("nodes", [])
	_check(nodes_arr.size() == 2, "G5: tree_dict has 2 nodes")
	var rep_dict: Dictionary = nodes_arr[0]
	var rep_params: Dictionary = rep_dict.get("parameters", {})
	_check(rep_params.get("count") == 7, "G5: repeater count persists in to_dict", 7, rep_params.get("count"))
	_check(rep_params.get("repeat_forever") == true, "G5: repeater repeat_forever persists in to_dict", true, rep_params.get("repeat_forever"))
	_check(rep_params.get("end_on_failure") == true, "G5: repeater end_on_failure persists in to_dict", true, rep_params.get("end_on_failure"))

	# 2. Cooldown: property setter -> to_dict persistence
	var tree_cd := BTTree.new()
	var cd := BTDecorator.BTCooldown.new()
	cd.cooldown_time = 3.5
	tree_cd.set_root(cd)
	var cd_child := BTTask.new()
	tree_cd.connect_parent_child(cd, cd_child)

	var cd_schema: Dictionary = cd.get_parameter_schema()
	_check(cd_schema.has("cooldown_time"), "G5: Cooldown get_parameter_schema has cooldown_time")
	_check(cd_schema["cooldown_time"]["type"] == "float", "G5: cooldown_time schema type is float")

	var cd_dict := tree_cd.to_dict()
	var cd_params: Dictionary = cd_dict["nodes"][0]["parameters"]
	_check(_approx_equal(cd_params.get("cooldown_time"), 3.5), "G5: cooldown_time persists in to_dict", 3.5, cd_params.get("cooldown_time"))

	# 3. TimeLimit: property setter -> to_dict persistence
	var tree_tl := BTTree.new()
	var tl := BTDecorator.BTTimeLimit.new()
	tl.time_limit = 10.25
	tree_tl.set_root(tl)
	var tl_child := BTTask.new()
	tree_tl.connect_parent_child(tl, tl_child)

	var tl_schema: Dictionary = tl.get_parameter_schema()
	_check(tl_schema.has("time_limit"), "G5: TimeLimit get_parameter_schema has time_limit")
	_check(tl_schema["time_limit"]["type"] == "float", "G5: time_limit schema type is float")

	var tl_dict := tree_tl.to_dict()
	var tl_params: Dictionary = tl_dict["nodes"][0]["parameters"]
	_check(_approx_equal(tl_params.get("time_limit"), 10.25), "G5: time_limit persists in to_dict", 10.25, tl_params.get("time_limit"))

	# 4. from_dict coercion: loading strings/floats into typed properties
	var coerce_dict := {
		"root_id": 1,
		"nodes": [
			{
				"id": 1,
				"type_name": "Repeater",
				"category": "Decorator",
				"parent_id": -1,
				"children_ids": [2],
				"parameters": {
					"count": "15",              # string "15" -> int 15
					"repeat_forever": "true",    # string "true" -> bool true
					"end_on_failure": 1.9        # float 1.9 -> bool true
				}
			},
			{
				"id": 2,
				"type_name": "Cooldown",
				"category": "Decorator",
				"parent_id": 1,
				"children_ids": [3],
				"parameters": {
					"cooldown_time": "8.5"       # string "8.5" -> float 8.5
				}
			},
			{
				"id": 3,
				"type_name": "TimeLimit",
				"category": "Decorator",
				"parent_id": 2,
				"children_ids": [4],
				"parameters": {
					"time_limit": 20             # int 20 -> float 20.0
				}
			},
			{
				"id": 4,
				"type_name": "BTTask",
				"category": "Action",
				"parent_id": 3,
				"children_ids": [],
				"parameters": {}
			}
		]
	}

	var coerced_tree := BTTree.from_dict(coerce_dict)
	_check(coerced_tree != null, "G5: from_dict successfully builds tree with coerced types")
	if coerced_tree != null:
		var n1: BTDecorator.BTRepeater = coerced_tree.get_node_by_id(1) as BTDecorator.BTRepeater
		_check(n1 != null, "G5: node 1 is BTRepeater")
		if n1 != null:
			_check(n1.count == 15, "G5: string '15' coerced to int 15", 15, n1.count)
			_check(n1.repeat_forever == true, "G5: string 'true' coerced to bool true", true, n1.repeat_forever)
			_check(n1.end_on_failure == true, "G5: float 1.9 coerced to bool true", true, n1.end_on_failure)

		var n2: BTDecorator.BTCooldown = coerced_tree.get_node_by_id(2) as BTDecorator.BTCooldown
		_check(n2 != null, "G5: node 2 is BTCooldown")
		if n2 != null:
			_check(_approx_equal(n2.cooldown_time, 8.5), "G5: string '8.5' coerced to float 8.5", 8.5, n2.cooldown_time)

		var n3: BTDecorator.BTTimeLimit = coerced_tree.get_node_by_id(3) as BTDecorator.BTTimeLimit
		_check(n3 != null, "G5: node 3 is BTTimeLimit")
		if n3 != null:
			_check(_approx_equal(n3.time_limit, 20.0), "G5: int 20 coerced to float 20.0", 20.0, n3.time_limit)

# ==============================================================================
# GROUP 6: Id allocation, reparenting, disconnect, removal
# ==============================================================================
func _test_group6_id_and_reparent() -> void:
	print("Running Group 6: ID allocation, reparenting, disconnect, removal...")

	var tree := BTTree.new()

	# 1. Auto id allocation: strictly increasing
	var root := BTComposite.BTSequence.new()
	tree.set_root(root)
	_check(root.id >= 1, "G6: root auto id is >= 1", ">= 1", root.id)

	var n1 := BTTask.new()
	var n2 := BTTask.new()
	var n3 := BTTask.new()
	tree.add_node(n1)
	tree.add_node(n2)
	tree.add_node(n3)

	_check(n1.id > root.id, "G6: n1 id > root id", "> %d" % root.id, n1.id)
	_check(n2.id > n1.id, "G6: n2 id > n1 id", "> %d" % n1.id, n2.id)
	_check(n3.id > n2.id, "G6: n3 id > n2 id", "> %d" % n2.id, n3.id)

	# 2. Add node with pre-existing id (should be respected if unique)
	var n_custom := BTTask.new()
	n_custom.id = 500
	tree.add_node(n_custom)
	_check(n_custom.id == 500, "G6: custom pre-existing id 500 is preserved", 500, n_custom.id)
	_check(tree.get_node_by_id(500) == n_custom, "G6: get_node_by_id finds custom id 500")

	# 3. Next auto id should be > highest taken id
	var n_after := BTTask.new()
	tree.add_node(n_after)
	_check(n_after.id > 500, "G6: auto id after 500 is > 500", "> 500", n_after.id)

	# 4. Remove node does not cause collision on next auto-id
	var deleted_id := n_after.id
	tree.remove_node(n_after)
	_check(tree.get_node_by_id(deleted_id) == null, "G6: get_node_by_id returns null for removed node")

	var n_new := BTTask.new()
	tree.add_node(n_new)
	_check(n_new.id > deleted_id, "G6: new auto id is strictly greater than deleted id", "> %d" % deleted_id, n_new.id)

	# 5. Connect and Reparenting
	var comp1 := BTComposite.BTSelector.new()
	var comp2 := BTComposite.BTSequence.new()
	var leaf := BTTask.new()
	tree.add_node(comp1)
	tree.add_node(comp2)
	tree.add_node(leaf)

	tree.connect_parent_child(comp1, leaf)
	_check(leaf.parent == comp1, "G6: leaf parent is comp1")
	_check(comp1.children.has(leaf), "G6: comp1 children contains leaf")

	# Reparent leaf to comp2
	tree.connect_parent_child(comp2, leaf)
	_check(leaf.parent == comp2, "G6: leaf parent reparented to comp2")
	_check(comp2.children.has(leaf), "G6: comp2 children contains leaf")
	_check(not comp1.children.has(leaf), "G6: comp1 children no longer contains leaf after reparent")

	# 6. Disconnect
	tree.disconnect_parent_child(comp2, leaf)
	_check(leaf.parent == null, "G6: leaf parent is null after disconnect")
	_check(not comp2.children.has(leaf), "G6: comp2 children does not contain leaf after disconnect")

	# 7. Remove parent node that has children
	var parent_del := BTComposite.BTSequence.new()
	var child_a := BTTask.new()
	var child_b := BTTask.new()
	tree.add_node(parent_del)
	tree.add_node(child_a)
	tree.add_node(child_b)
	tree.connect_parent_child(parent_del, child_a)
	tree.connect_parent_child(parent_del, child_b)

	tree.remove_node(parent_del)
	_check(tree.get_node_by_id(parent_del.id) == null, "G6: parent_del removed from tree")
	_check(child_a.parent == null, "G6: child_a parent cleared after parent removed")
	_check(child_b.parent == null, "G6: child_b parent cleared after parent removed")
	_check(tree.get_node_by_id(child_a.id) == child_a, "G6: child_a still exists in tree")
	_check(tree.get_node_by_id(child_b.id) == child_b, "G6: child_b still exists in tree")

	# 8. Remove root node
	var old_root = tree.root_task
	_check(old_root != null, "G6: tree has root before remove")
	tree.remove_node(old_root)
	_check(tree.root_task == null, "G6: tree.root_task is null after root removed")
	_check(tree.get_node_by_id(old_root.id) == null, "G6: old root removed from by_id map")

# ==============================================================================
# GROUP 7: get_stats & BTFileTreeSource / BTMemoryTreeSource
# ==============================================================================
func _test_group7_stats_and_sources() -> void:
	print("Running Group 7: get_stats and Tree Sources (Memory & File)...")

	# 1. get_stats on mixed tree
	var tree := BTTree.new()
	var root := BTComposite.BTSequence.new()
	tree.set_root(root) # 1 root, 1 composite

	var sel := BTComposite.BTSelector.new() # composite
	var rep := BTDecorator.BTRepeater.new() # decorator
	var leaf1 := BTTask.new()               # leaf
	var leaf2 := BTTask.new()               # leaf
	var placeholder := BTTask.new()
	placeholder.is_placeholder = true      # placeholder + leaf

	tree.connect_parent_child(root, sel)
	tree.connect_parent_child(root, rep)
	tree.connect_parent_child(sel, leaf1)
	tree.connect_parent_child(sel, leaf2)
	tree.connect_parent_child(rep, placeholder)

	var stats: Dictionary = tree.get_stats()
	# Expect: total=6, root=1, composite=2 (root + sel), decorator=1 (rep), leaf=3 (leaf1, leaf2, placeholder), placeholder=1
	_check(stats.get("total") == 6, "G7: stats total is 6", 6, stats.get("total"))
	_check(stats.get("root") == 1, "G7: stats root is 1", 1, stats.get("root"))
	_check(stats.get("composite") == 2, "G7: stats composite is 2", 2, stats.get("composite"))
	_check(stats.get("decorator") == 1, "G7: stats decorator is 1", 1, stats.get("decorator"))
	_check(stats.get("leaf") == 3, "G7: stats leaf is 3", 3, stats.get("leaf"))
	_check(stats.get("placeholder") == 1, "G7: stats placeholder is 1", 1, stats.get("placeholder"))

	# 2. BTMemoryTreeSource
	var mem_source := BTMemoryTreeSource.new()
	_check(mem_source.get_source_name() == "Memory BT Source", "G7: BTMemoryTreeSource source name")

	# Save valid tree
	var saved := mem_source.save_tree("ai_main", tree)
	_check(saved, "G7: BTMemoryTreeSource saves valid tree")
	_check(mem_source.list_trees().has("ai_main"), "G7: BTMemoryTreeSource lists 'ai_main'")

	# Load valid tree
	var loaded := mem_source.load_tree("ai_main")
	_check(loaded != null, "G7: BTMemoryTreeSource loads 'ai_main'")
	_check(loaded.tree_name == "ai_main", "G7: loaded tree has tree_name 'ai_main'")
	_check(loaded.get_node_count() == 6, "G7: loaded tree node count is 6")

	# Load non-existent tree
	var loaded_none := mem_source.load_tree("non_existent")
	_check(loaded_none == null, "G7: BTMemoryTreeSource returns null for non-existent tree")
	_check(mem_source.last_error.contains("not found"), "G7: last_error contains 'not found'", "not found", mem_source.last_error)

	# Load with empty identifier
	var loaded_empty := mem_source.load_tree("")
	_check(loaded_empty == null, "G7: BTMemoryTreeSource returns null for empty identifier")
	_check(mem_source.last_error.contains("empty"), "G7: last_error contains 'empty'", "empty", mem_source.last_error)

	# Save corrupted tree into BTMemoryTreeSource (e.g. leaf with children or corrupted dict)
	var bad_tree := BTTree.new()
	var bad_root := BTComposite.BTSequence.new()
	bad_tree.set_root(bad_root)
	# create multiple parents or cycle
	var bad_child := BTTask.new()
	bad_tree.connect_parent_child(bad_root, bad_child)
	# Manually force cycle or corrupt dictionary
	var corrupt_source_tree := BTTree.new() # empty tree has no nodes
	var save_corrupt := mem_source.save_tree("corrupt", corrupt_source_tree)
	_check(not save_corrupt, "G7: BTMemoryTreeSource refuses to save invalid tree")
	_check(mem_source.last_error != "", "G7: BTMemoryTreeSource populates last_error on refusal")

	# 3. BTFileTreeSource with user:// path
	var user_dir := "user://e2e_trees_test"
	if DirAccess.dir_exists_absolute(user_dir):
		var dir := DirAccess.open(user_dir)
		if dir != null:
			dir.list_dir_begin()
			var fn = dir.get_next()
			while fn != "":
				if not dir.current_is_dir():
					dir.remove(fn)
				fn = dir.get_next()
			dir.list_dir_end()
	else:
		DirAccess.make_dir_recursive_absolute(user_dir)

	var file_source := BTFileTreeSource.new(user_dir)
	_check(file_source.get_directory_path() == user_dir, "G7: BTFileTreeSource directory matches")

	# Save valid tree
	var f_saved := file_source.save_tree("disk_tree", tree)
	_check(f_saved, "G7: BTFileTreeSource saves tree to disk")
	file_source.refresh()
	_check(file_source.list_trees().has("disk_tree"), "G7: BTFileTreeSource lists 'disk_tree'")

	# Load valid tree from disk
	var f_loaded := file_source.load_tree("disk_tree")
	_check(f_loaded != null, "G7: BTFileTreeSource loads 'disk_tree'")
	_check(f_loaded.get_node_count() == 6, "G7: BTFileTreeSource loaded tree has 6 nodes")

	# Load missing file
	var f_none := file_source.load_tree("missing_file")
	_check(f_none == null, "G7: BTFileTreeSource returns null for missing file")
	_check(file_source.last_error.contains("file not found"), "G7: last_error contains 'file not found'", "file not found", file_source.last_error)

	# Save invalid tree
	var f_bad_saved := file_source.save_tree("bad_disk_tree", corrupt_source_tree)
	_check(not f_bad_saved, "G7: BTFileTreeSource refuses to save invalid tree")
	_check(file_source.last_error != "", "G7: BTFileTreeSource last_error populated on refusal")

	# Clean up test files
	var clean_dir := DirAccess.open(user_dir)
	if clean_dir != null:
		clean_dir.list_dir_begin()
		var fn = clean_dir.get_next()
		while fn != "":
			if not clean_dir.current_is_dir():
				clean_dir.remove(fn)
			fn = clean_dir.get_next()
		clean_dir.list_dir_end()

# ==============================================================================
# GROUP 8: Large trees (500 - 2000 nodes)
# ==============================================================================
func _test_group8_large_trees() -> void:
	print("Running Group 8: Large trees (500-2000 nodes, stats, round-trip)...")

	# 1. Dựng 600 nodes bằng code
	var tree_code := BTTree.new()
	tree_code.tree_name = "BigCodeTree"
	var root := BTComposite.BTSequence.new()
	tree_code.set_root(root)

	var current_parent: BTTask = root
	var node_count := 600
	for i in range(1, node_count):
		# Every 20 nodes, create a composite branch
		if i % 20 == 0:
			var branch := BTComposite.BTSelector.new()
			branch.friendly_name = "Branch_%d" % i
			tree_code.connect_parent_child(root, branch)
			current_parent = branch
		else:
			var leaf := BTTask.new()
			leaf.friendly_name = "Leaf_%d" % i
			leaf.parameters["index"] = i
			tree_code.connect_parent_child(current_parent, leaf)

	_check(tree_code.get_node_count() == node_count, "G8: tree_code get_node_count is 600", node_count, tree_code.get_node_count())
	var code_stats := tree_code.get_stats()
	_check(code_stats.get("total") == node_count, "G8: code_stats total is 600", node_count, code_stats.get("total"))

	# get_node_by_id for first and last
	var first_node = tree_code.get_node_by_id(root.id)
	_check(first_node == root, "G8: get_node_by_id correctly retrieves root")

	var all_nodes: Array = tree_code.node_list
	_check(all_nodes.size() == node_count, "G8: tree_code node_list size is 600")
	var last_node: BTTask = all_nodes[all_nodes.size() - 1]
	_check(tree_code.get_node_by_id(last_node.id) == last_node, "G8: get_node_by_id correctly retrieves last node")

	# 2. Round-trip large tree (to_dict -> from_dict)
	var t0 := Time.get_ticks_msec()
	var big_dict := tree_code.to_dict()
	var t_to_dict := Time.get_ticks_msec() - t0

	t0 = Time.get_ticks_msec()
	var restored_big := BTTree.from_dict(big_dict)
	var t_from_dict := Time.get_ticks_msec() - t0

	_check(restored_big != null, "G8: from_dict successfully rebuilt 600-node tree")
	if restored_big != null:
		_check(restored_big.get_node_count() == node_count, "G8: restored tree has 600 nodes", node_count, restored_big.get_node_count())
		var restored_stats := restored_big.get_stats()
		_check(restored_stats.get("total") == node_count, "G8: restored_stats total matches 600", node_count, restored_stats.get("total"))
		_check(restored_stats.get("composite") == code_stats.get("composite"), "G8: composite count matches", code_stats.get("composite"), restored_stats.get("composite"))
		_check(restored_stats.get("leaf") == code_stats.get("leaf"), "G8: leaf count matches", code_stats.get("leaf"), restored_stats.get("leaf"))

		# Check first and last id in restored tree
		var r_first = restored_big.get_node_by_id(root.id)
		var r_last = restored_big.get_node_by_id(last_node.id)
		_check(r_first != null and r_first.id == root.id, "G8: restored tree finds first node by id")
		_check(r_last != null and r_last.id == last_node.id, "G8: restored tree finds last node by id")
		if r_last != null:
			_check(r_last.parameters.get("index") == last_node.parameters.get("index"), "G8: last node parameter 'index' preserved")


