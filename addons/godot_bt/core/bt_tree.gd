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

func _init() -> void:
	blackboard = BTBlackboard.new()
	registry = BTTaskRegistry.new()

# ---------------------------------------------------------------- Builder API
func add_node(task: BTTask) -> BTTask:
	if task == null:
		return null
	if not node_list.has(task):
		if task.id < 0 or get_node_by_id(task.id) != null:
			var next_id := 1
			while get_node_by_id(next_id) != null:
				next_id += 1
			task.id = next_id
		task.blackboard = blackboard
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
	if not parent_task is BTParentTask and not ("children" in parent_task and parent_task.children is Array):
		return
	var ancestor: BTTask = parent_task
	while ancestor != null:
		if ancestor == child_task:
			return
		ancestor = ancestor.parent
	if child_task.parent != null and child_task.parent != parent_task:
		return
	add_node(parent_task)
	add_node(child_task)
	if parent_task is BTParentTask:
		(parent_task as BTParentTask).add_child_task(child_task)
	elif "children" in parent_task:
		if parent_task.children is Array and not parent_task.children.has(child_task):
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
	node_list.erase(task)

func get_node_by_id(id: int) -> BTTask:
	for n in node_list:
		if n != null and n.id == id:
			return n
	return null

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

		nodes_data.append({
			"id": task.id,
			"friendly_name": task.friendly_name,
			"type_name": task.type_name,
			"category": task.category,
			"is_placeholder": task.is_placeholder,
			"parent_id": task.parent.id if (task.parent != null and "id" in task.parent) else -1,
			"children_ids": child_ids,
			"parameters": _encode_value(task.parameters)
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

static func validate_dict(data: Dictionary) -> PackedStringArray:
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
		if str(node.get("type_name", "")) in ["Sequence", "Selector", "Parallel", "RandomSequence", "RandomSelector"] and parameters.has("abort_type"):
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
	for id in by_id:
		var node: Dictionary = by_id[id]
		if not node.get("children_ids", []) is Array:
			continue
		var child_ids: Array = node.get("children_ids", [])
		for child_value in child_ids:
			var child: int = int(child_value) if _is_integer_id(child_value) else -1
			if child < 0 or not by_id.has(child):
				errors.append("node %d references missing child %s" % [id, str(child)])
				continue
			parents[child] += 1
			edges[id].append(child)
		if str(node.get("type_name", "")) in ["Inverter", "ReturnSuccess", "ReturnFailure", "Repeater", "UntilSuccess", "UntilFailure", "Cooldown", "TimeLimit"] and child_ids.size() > 1:
			errors.append("decorator %d has multiple children" % id)
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

static func _has_cycle(id: int, edges: Dictionary, colors: Dictionary) -> bool:
	colors[id] = 1
	for child in edges[id]:
		if colors[child] == 1 or (colors[child] == 0 and _has_cycle(child, edges, colors)):
			return true
	colors[id] = 2
	return false

static func _valid_encoded(value: Variant) -> bool:
	if value is float and not is_finite(value): return false
	if value is Array:
		for item in value:
			if not _valid_encoded(item): return false
	elif value is Dictionary:
		if value.has("__bt_type") and value["__bt_type"] in ["Vector2", "Vector3", "Color"]:
			if value.size() != 2 or not value.has("value") or not value.value is Array:
				return false
			var expected := {"Vector2": 2, "Vector3": 3, "Color": 4}.get(value["__bt_type"], -1)
			if expected < 0 or value.value.size() != expected: return false
			for component in value.value:
				if not (component is int or component is float) or (component is float and not is_finite(component)): return false
		else:
			for key in value:
				if not _valid_encoded(value[key]): return false
	return true

static func _encode_value(value: Variant) -> Variant:
	if value is Vector2: return {"__bt_type":"Vector2", "value":[value.x, value.y]}
	if value is Vector3: return {"__bt_type":"Vector3", "value":[value.x, value.y, value.z]}
	if value is Color: return {"__bt_type":"Color", "value":[value.r, value.g, value.b, value.a]}
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
	if value is Dictionary and value.size() == 2 and value.has("__bt_type") and value.has("value") and value["__bt_type"] in ["Vector2", "Vector3", "Color"] and _valid_encoded(value):
		var v: Array = value.value
		match value.__bt_type:
			"Vector2": return Vector2(v[0], v[1])
			"Vector3": return Vector3(v[0], v[1], v[2])
			"Color": return Color(v[0], v[1], v[2], v[3])
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
	var errors := validate_dict(data)
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
		task.category = str(n_dict.get("category", task.category))
		task.parameters = {}
		for parameter_key in n_dict.get("parameters", {}):
			task.parameters[parameter_key] = _decode_value(n_dict.parameters[parameter_key])
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
