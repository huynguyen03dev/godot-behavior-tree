class_name BTTree
extends RefCounted
## Generic Behavior Tree data model.
## Manages node hierarchy, Blackboard integration, statistics, and Serialization/Deserialization.

var tree_name: String = "Untitled Tree"
var description: String = ""
var root_task: BTTask = null
var node_list: Array = [] # Array[BTTask]
var blackboard: BTBlackboard = null
var metadata: Dictionary = {}
var registry: BTTaskRegistry = null
var _next_id_hint: int = 1
var _nodes_by_id: Dictionary = {} # int -> BTTask

func _init() -> void:
	blackboard = BTBlackboard.new()
	registry = BTTaskRegistry.new()

# ---------------------------------------------------------------- Builder API
func add_node(task: BTTask) -> BTTask:
	if task == null:
		return null
	if not node_list.has(task):
		if task.id >= 0 and not _nodes_by_id.has(task.id):
			if task.id >= _next_id_hint:
				_next_id_hint = task.id + 1
		else:
			while _nodes_by_id.has(_next_id_hint):
				_next_id_hint += 1
			task.id = _next_id_hint
			_next_id_hint += 1
		task.blackboard = blackboard
		_nodes_by_id[task.id] = task
		node_list.append(task)
	return task

func set_root(task: BTTask) -> void:
	add_node(task)
	if task.category == "" or task.category == "Task" or task.category == "Action":
		task.category = "Root"
	root_task = task

func connect_parent_child(parent_task: BTTask, child_task: BTTask) -> void:
	if parent_task == null or child_task == null or parent_task == child_task:
		return
	if child_task == root_task:
		return
	if not parent_task is BTParentTask and not ("children" in parent_task and parent_task.children is Array):
		return
	var ancestor: BTTask = parent_task
	while ancestor != null:
		if ancestor == child_task:
			return
		ancestor = ancestor.parent
	add_node(parent_task)
	add_node(child_task)
	if parent_task is BTParentTask:
		# add_child_task reparents a child that already has a different parent,
		# so moving a node from one parent to another is allowed here.
		(parent_task as BTParentTask).add_child_task(child_task)
	elif "children" in parent_task and parent_task.children is Array:
		if not parent_task.children.has(child_task):
			if child_task.parent != null and child_task.parent != parent_task:
				disconnect_parent_child(child_task.parent, child_task)
			parent_task.children.append(child_task)
			child_task.parent = parent_task

func disconnect_parent_child(parent_task: BTTask, child_task: BTTask) -> void:
	if parent_task == null or child_task == null:
		return
	if parent_task is BTParentTask:
		(parent_task as BTParentTask).remove_child_task(child_task)
	elif "children" in parent_task and parent_task.children is Array:
		parent_task.children.erase(child_task)
		if child_task.parent == parent_task:
			child_task.parent = null

func remove_node(task: BTTask) -> void:
	if task == null:
		return
	if task.parent != null:
		disconnect_parent_child(task.parent, task)
	if "children" in task and task.children is Array:
		for c in task.children.duplicate():
			if c != null:
				disconnect_parent_child(task, c)
	if task == root_task:
		root_task = null
	_nodes_by_id.erase(task.id)
	node_list.erase(task)

func get_node_by_id(id: int) -> BTTask:
	return _nodes_by_id.get(id, null)

func get_node_count() -> int:
	return node_list.size()

func get_stats() -> Dictionary:
	var total := node_list.size()
	var roots := 0
	var composites := 0
	var decorators := 0
	var leaves := 0
	var placeholders := 0

	for task in node_list:
		if task == null:
			continue
		if task.is_placeholder:
			placeholders += 1

		if task == root_task or task.category == "Root":
			roots += 1

		if task is BTDecorator or task.category == "Decorator":
			decorators += 1
		elif task is BTComposite or task.category == "Composite" or (task is BTParentTask and not (task is BTDecorator)):
			composites += 1
		elif task != root_task and task.category != "Root":
			leaves += 1
		elif task == root_task and not (task is BTParentTask):
			leaves += 1

	return {
		"total": total,
		"root": roots,
		"composite": composites,
		"decorator": decorators,
		"leaf": leaves,
		"placeholder": placeholders
	}

# ---------------------------------------------------------------- Serialization

const BUILTIN_COMPOSITE_TYPES := ["Sequence", "Selector", "Parallel", "RandomSequence", "RandomSelector"]
const BUILTIN_DECORATOR_TYPES := ["Inverter", "ReturnSuccess", "ReturnFailure", "Repeater", "UntilSuccess", "UntilFailure", "Cooldown", "TimeLimit"]

func to_dict() -> Dictionary:
	var nodes_data: Array = []
	for task in node_list:
		if task == null:
			continue
		var child_ids: Array = []
		if "children" in task and task.children is Array:
			for c in task.children:
				if c != null and "id" in c:
					child_ids.append(c.id)

		var params: Dictionary = task.parameters.duplicate() if task.parameters is Dictionary else {}
		if task.has_method("get_parameter_schema"):
			var schema: Variant = task.call("get_parameter_schema")
			if schema is Dictionary:
				for k in schema.keys():
					if not params.has(k):
						var entry = schema[k]
						if entry is Dictionary and entry.has("default"):
							params[k] = entry["default"]
		if task is BTComposite:
			var composite := task as BTComposite
			if not params.has("abort_type") and composite.abort_type != BTComposite.AbortType.NONE:
				params["abort_type"] = composite.abort_type

		nodes_data.append({
			"id": task.id,
			"friendly_name": task.friendly_name,
			"type_name": task.type_name,
			"category": task.category,
			"is_placeholder": task.is_placeholder,
			"parent_id": task.parent.id if (task.parent != null and "id" in task.parent) else -1,
			"children_ids": child_ids,
			"parameters": _encode_value(params)
		})

	var bb_data := {}
	if blackboard != null:
		for var_name in blackboard.get_all_variables().keys():
			var variable: BTBlackboard.Variable = blackboard.get_variable_obj(var_name)
			bb_data[var_name] = {
				"value": _encode_value(variable.value),
				"type_name": variable.type_name,
				"is_shared": variable.is_shared,
				"description": variable.description
			}

	return {
		"tree_name": tree_name,
		"description": description,
		"root_id": root_task.id if root_task != null else -1,
		"nodes": nodes_data,
		"blackboard": bb_data,
		"metadata": metadata
	}

## Validates serialized tree data. Without a registry only builtin type names
## are known (backwards compatible); with a registry, the task the registry
## creates decides whether a node may hold children and whether it is a
## single-child decorator, exactly like from_dict does.
static func validate_dict(data: Dictionary, registry: BTTaskRegistry = null) -> PackedStringArray:
	var errors := PackedStringArray()
	if not data.get("nodes", null) is Array:
		errors.append("nodes must be an array")
		return errors
	if not data.get("metadata", {}) is Dictionary: errors.append("metadata must be a dictionary")
	if not data.get("blackboard", {}) is Dictionary: errors.append("blackboard must be a dictionary")
	else:
		for key in data.get("blackboard", {}):
			var entry = data.blackboard[key]
			var encoded = entry.get("value") if entry is Dictionary and entry.has("value") else entry
			if not _valid_encoded(encoded): errors.append("blackboard variable %s contains malformed encoded value" % str(key))
	var by_id := {}
	for i in range(data.nodes.size()):
		var node = data.nodes[i]
		if not node is Dictionary or not _is_integer_id(node.get("id", null)):
			errors.append("node %d must have an integer id" % i)
			continue
		var id: int = int(node.id)
		if id < 0 or by_id.has(id): errors.append("invalid or duplicate node id %d" % id)
		by_id[id] = node
		if not node.get("parameters", {}) is Dictionary: errors.append("node %d parameters must be a dictionary" % id)
		if not node.get("children_ids", []) is Array: errors.append("node %d children_ids must be an array" % id)
		var parameters: Dictionary = node.get("parameters", {}) if node.get("parameters", {}) is Dictionary else {}
		for parameter_value in parameters.values():
			if not _valid_encoded(parameter_value):
				errors.append("node %d contains malformed encoded value" % id)
				break
		if BUILTIN_COMPOSITE_TYPES.has(str(node.get("type_name", ""))) and parameters.has("abort_type"):
			var abort_value: Variant = parameters["abort_type"]
			if not _is_integer_id(abort_value) or int(abort_value) < 0 or int(abort_value) > 3:
				errors.append("node %d abort_type must be an integer from 0 to 3" % id)
	var root_value = data.get("root_id", null)
	var root_id: int = int(root_value) if _is_integer_id(root_value) else -1
	if root_id < 0 or not by_id.has(root_id): errors.append("root_id must identify an existing node")
	if by_id.is_empty(): errors.append("tree must contain nodes")
	var parents := {}
	var edges := {}
	for id in by_id: parents[id] = 0; edges[id] = []
	var shape_cache := {}
	for id in by_id:
		var node: Dictionary = by_id[id]
		if not node.get("children_ids", []) is Array:
			continue
		var child_ids: Array = node.get("children_ids", [])
		if not child_ids.is_empty():
			var type_name := str(node.get("type_name", ""))
			var shape: Dictionary
			if shape_cache.has(type_name):
				shape = shape_cache[type_name]
			else:
				shape = _node_parent_shape(node, registry)
				shape_cache[type_name] = shape
			if not shape.can_have_children:
				errors.append("node %d of type '%s' has children but cannot hold them" % [id, str(node.get("type_name", ""))])
			elif shape.is_decorator and child_ids.size() > 1:
				errors.append("decorator %d has multiple children" % id)
		for child_value in child_ids:
			var child: int = int(child_value) if _is_integer_id(child_value) else -1
			if child < 0 or not by_id.has(child):
				errors.append("node %d references missing child %s" % [id, str(child)])
				continue
			parents[child] += 1
			edges[id].append(child)
	for id in by_id:
		if parents[id] > 1: errors.append("node %d has multiple parents" % id)
	if by_id.has(root_id) and parents[root_id] > 0:
		errors.append("root node cannot have a parent")
	var colors := {}
	for id in by_id: colors[id] = 0
	for start_id in by_id:
		if colors[start_id] == 0 and _has_cycle(start_id, edges, colors):
			errors.append("hierarchy contains a cycle")
			break
	return errors

static func _is_integer_id(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and floor(value) == value)

## Decides whether a serialized node may hold children and whether it is a
## single-child decorator. With a registry the decision comes from the task the
## registry creates (the same predicate from_dict applies); without one only
## builtin type names are known and unknown types stay permissive for
## backwards compatibility.
static func _node_parent_shape(node: Dictionary, registry: BTTaskRegistry) -> Dictionary:
	var type_name := str(node.get("type_name", ""))
	if registry != null:
		var created: BTTask = registry.create_task(type_name)
		if created is BTParentTask:
			return {
				"can_have_children": true,
				"is_decorator": created is BTDecorator or registry.get_category(type_name) == "Decorator"
			}
		elif created != null and "children" in created and created.children is Array:
			return {"can_have_children": true, "is_decorator": false}
		return {"can_have_children": false, "is_decorator": false}
	if BUILTIN_DECORATOR_TYPES.has(type_name):
		return {"can_have_children": true, "is_decorator": true}
	if BUILTIN_COMPOSITE_TYPES.has(type_name):
		return {"can_have_children": true, "is_decorator": false}
	return {"can_have_children": true, "is_decorator": false}

static func _has_cycle(id: int, edges: Dictionary, colors: Dictionary) -> bool:
	colors[id] = 1
	for child in edges[id]:
		if colors[child] == 1 or (colors[child] == 0 and _has_cycle(child, edges, colors)):
			return true
	colors[id] = 2
	return false

const TAGGED_TYPE_SIZES := {
	"Vector2": 2,
	"Vector2i": 2,
	"Vector3": 3,
	"Vector3i": 3,
	"Vector4": 4,
	"Vector4i": 4,
	"Color": 4,
	"Rect2": 4,
	"Rect2i": 4,
	"Quaternion": 4,
	"Plane": 4,
	"AABB": 6,
	"Transform2D": 6,
	"Basis": 9,
	"Transform3D": 12,
	"Projection": 16,
}

const INTEGER_TAGGED_TYPES := ["Vector2i", "Vector3i", "Vector4i", "Rect2i"]

static func _valid_encoded(value: Variant) -> bool:
	if value == null or value is bool or value is int or value is String:
		return true
	if value is float:
		return is_finite(value)
	if value is Array:
		for item in value:
			if not _valid_encoded(item):
				return false
		return true
	if value is Dictionary:
		if value.has("__bt_type"):
			if value.size() != 2 or not value.has("value"):
				return false
			var type_tag: Variant = value["__bt_type"]
			if type_tag == "float":
				var tag_val: Variant = value["value"]
				return tag_val is String and ["inf", "-inf", "nan"].has(tag_val)
			if type_tag is String and TAGGED_TYPE_SIZES.has(type_tag):
				if not (value.value is Array):
					return false
				var arr: Array = value.value
				if arr.size() != TAGGED_TYPE_SIZES[type_tag]:
					return false
				var is_int_type: bool = INTEGER_TAGGED_TYPES.has(type_tag)
				for comp in arr:
					if is_int_type:
						if not (comp is int or (comp is float and is_finite(comp) and floor(comp) == comp)):
							return false
					else:
						if not (comp is int or comp is float) or (comp is float and not is_finite(comp)):
							return false
				return true
			return false
		for key in value:
			if not _valid_encoded(value[key]):
				return false
		return true
	return false

static func _encode_value(value: Variant) -> Variant:
	if value is float and not is_finite(value):
		# JSON.stringify mangles non-finite floats; store them as tagged values.
		if value > 0.0:
			return {"__bt_type": "float", "value": "inf"}
		if value < 0.0:
			return {"__bt_type": "float", "value": "-inf"}
		return {"__bt_type": "float", "value": "nan"}
	if value is Vector2: return {"__bt_type": "Vector2", "value": [value.x, value.y]}
	if value is Vector2i: return {"__bt_type": "Vector2i", "value": [value.x, value.y]}
	if value is Vector3: return {"__bt_type": "Vector3", "value": [value.x, value.y, value.z]}
	if value is Vector3i: return {"__bt_type": "Vector3i", "value": [value.x, value.y, value.z]}
	if value is Vector4: return {"__bt_type": "Vector4", "value": [value.x, value.y, value.z, value.w]}
	if value is Vector4i: return {"__bt_type": "Vector4i", "value": [value.x, value.y, value.z, value.w]}
	if value is Color: return {"__bt_type": "Color", "value": [value.r, value.g, value.b, value.a]}
	if value is Rect2: return {"__bt_type": "Rect2", "value": [value.position.x, value.position.y, value.size.x, value.size.y]}
	if value is Rect2i: return {"__bt_type": "Rect2i", "value": [value.position.x, value.position.y, value.size.x, value.size.y]}
	if value is Quaternion: return {"__bt_type": "Quaternion", "value": [value.x, value.y, value.z, value.w]}
	if value is Plane: return {"__bt_type": "Plane", "value": [value.normal.x, value.normal.y, value.normal.z, value.d]}
	if value is AABB: return {"__bt_type": "AABB", "value": [value.position.x, value.position.y, value.position.z, value.size.x, value.size.y, value.size.z]}
	if value is Transform2D: return {"__bt_type": "Transform2D", "value": [value.x.x, value.x.y, value.y.x, value.y.y, value.origin.x, value.origin.y]}
	if value is Basis: return {"__bt_type": "Basis", "value": [value.x.x, value.x.y, value.x.z, value.y.x, value.y.y, value.y.z, value.z.x, value.z.y, value.z.z]}
	if value is Transform3D: return {"__bt_type": "Transform3D", "value": [value.basis.x.x, value.basis.x.y, value.basis.x.z, value.basis.y.x, value.basis.y.y, value.basis.y.z, value.basis.z.x, value.basis.z.y, value.basis.z.z, value.origin.x, value.origin.y, value.origin.z]}
	if value is Projection: return {"__bt_type": "Projection", "value": [value.x.x, value.x.y, value.x.z, value.x.w, value.y.x, value.y.y, value.y.z, value.y.w, value.z.x, value.z.y, value.z.z, value.z.w, value.w.x, value.w.y, value.w.z, value.w.w]}
	if value is Array:
		var result := []
		for v in value: result.append(_encode_value(v))
		return result
	if value is Dictionary:
		var result := {}
		for k in value: result[k] = _encode_value(value[k])
		return result
	return value

static func _decode_value(value: Variant) -> Variant:
	if value is Dictionary and value.size() == 2 and value.has("__bt_type") and value.has("value") and _valid_encoded(value):
		var tag: String = str(value["__bt_type"])
		if tag == "float":
			match str(value.value):
				"inf": return INF
				"-inf": return -INF
				"nan": return NAN
		var v: Array = value.value if value.value is Array else []
		match tag:
			"Vector2": return Vector2(v[0], v[1])
			"Vector2i": return Vector2i(int(v[0]), int(v[1]))
			"Vector3": return Vector3(v[0], v[1], v[2])
			"Vector3i": return Vector3i(int(v[0]), int(v[1]), int(v[2]))
			"Vector4": return Vector4(v[0], v[1], v[2], v[3])
			"Vector4i": return Vector4i(int(v[0]), int(v[1]), int(v[2]), int(v[3]))
			"Color": return Color(v[0], v[1], v[2], v[3])
			"Rect2": return Rect2(v[0], v[1], v[2], v[3])
			"Rect2i": return Rect2i(int(v[0]), int(v[1]), int(v[2]), int(v[3]))
			"Quaternion": return Quaternion(v[0], v[1], v[2], v[3])
			"Plane": return Plane(v[0], v[1], v[2], v[3])
			"AABB": return AABB(Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]))
			"Transform2D": return Transform2D(Vector2(v[0], v[1]), Vector2(v[2], v[3]), Vector2(v[4], v[5]))
			"Basis": return Basis(Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]), Vector3(v[6], v[7], v[8]))
			"Transform3D": return Transform3D(Basis(Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]), Vector3(v[6], v[7], v[8])), Vector3(v[9], v[10], v[11]))
			"Projection": return Projection(Vector4(v[0], v[1], v[2], v[3]), Vector4(v[4], v[5], v[6], v[7]), Vector4(v[8], v[9], v[10], v[11]), Vector4(v[12], v[13], v[14], v[15]))
	if value is Array:
		var result := []
		for v in value: result.append(_decode_value(v))
		return result
	if value is Dictionary:
		var result := {}
		for k in value: result[k] = _decode_value(value[k])
		return result
	return value

static func from_dict(data: Dictionary, registry: BTTaskRegistry = null) -> BTTree:
	# Validate with the registry that will build the tree so validate_dict and
	# from_dict always agree on which nodes may hold children.
	var validation_registry := registry if registry != null else BTTaskRegistry.new()
	var errors := validate_dict(data, validation_registry)
	if not errors.is_empty():
		push_error("Invalid behavior tree data: " + "; ".join(errors))
		return null
	var tree := BTTree.new()
	tree.tree_name = str(data.get("tree_name", "Untitled Tree"))
	tree.description = str(data.get("description", ""))
	tree.metadata = data.get("metadata", {}).duplicate()

	if registry == null:
		registry = tree.registry
	tree.registry = registry

	var nodes_data: Array = data.get("nodes", [])
	var id_to_task := {}
	var children_map := {}

	# 1. Create tasks
	for n_dict in nodes_data:
		var nid: int = int(n_dict.get("id", 0))
		var type_name: String = str(n_dict.get("type_name", "BTTask"))
		var task: BTTask = registry.create_task(type_name)
		task.id = nid
		task.friendly_name = str(n_dict.get("friendly_name", type_name))
		# Types known to the registry own their category (create_task already
		# applied it); the JSON category is only a fallback for placeholders
		# and unknown types.
		if not registry.has_task(type_name):
			task.category = str(n_dict.get("category", task.category))
		task.parameters = {}
		for parameter_key in n_dict.get("parameters", {}):
			task.parameters[parameter_key] = _decode_value(n_dict.parameters[parameter_key])
		if task.has_method("get_parameter_schema"):
			var schema: Variant = task.call("get_parameter_schema")
			if schema is Dictionary:
				for k in schema.keys():
					if task.parameters.has(k):
						var val = task.parameters[k]
						var entry = schema[k]
						if entry is Dictionary and entry.has("type"):
							match entry["type"]:
								"int": val = int(val)
								"float": val = float(val)
								"bool": val = BTTask.coerce_bool(val, bool(entry.get("default", false)))
						task.set(k, val)
		if task is BTComposite and task.parameters.has("abort_type"):
			(task as BTComposite).set_abort_type(int(task.parameters["abort_type"]))

		tree.add_node(task)
		id_to_task[nid] = task
		children_map[nid] = n_dict.get("children_ids", [])

	# 2. Connect parent-child
	for nid in children_map.keys():
		var p_task: BTTask = id_to_task.get(nid, null)
		if p_task != null:
			var has_children_array: bool = "children" in p_task and p_task.children is Array
			if not has_children_array and not children_map[nid].is_empty():
				push_error("Invalid behavior tree data: leaf node %d has children" % nid)
				return null
			if (p_task is BTDecorator or p_task.category == "Decorator") and children_map[nid].size() > 1:
				push_error("Invalid behavior tree data: decorator %d has multiple children" % nid)
				return null
			for cid in children_map[nid]:
				var c_task: BTTask = id_to_task.get(int(cid), null)
				if c_task != null:
					tree.connect_parent_child(p_task, c_task)

	# 3. Assign root
	var root_id: int = int(data.get("root_id", -1))
	if id_to_task.has(root_id):
		tree.set_root(id_to_task[root_id])
	elif not tree.node_list.is_empty():
		tree.set_root(tree.node_list[0])

	# 4. Blackboard
	var bb_data: Dictionary = data.get("blackboard", {})
	for k in bb_data.keys():
		var serialized = bb_data[k]
		if serialized is Dictionary and serialized.has("value"):
			tree.blackboard.set_var(str(k), _decode_value(serialized.get("value")), str(serialized.get("type_name", "Variant")))
			var variable: BTBlackboard.Variable = tree.blackboard.get_variable_obj(str(k))
			variable.is_shared = bool(serialized.get("is_shared", true))
			variable.description = str(serialized.get("description", ""))
		else:
			# Backward-compatible with the original scalar blackboard format.
			tree.blackboard.set_var(str(k), serialized)

	return tree
