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

func _init() -> void:
	blackboard = BTBlackboard.new()

# ---------------------------------------------------------------- Builder API
func add_node(task: BTTask) -> BTTask:
	if task == null:
		return null
	if not node_list.has(task):
		if task.id < 0:
			task.id = node_list.size() + 1
		task.blackboard = blackboard
		node_list.append(task)
	return task

func set_root(task: BTTask) -> void:
	add_node(task)
	if task.category == "" or task.category == "Task" or task.category == "Action":
		task.category = "Root"
	root_task = task

func connect_parent_child(parent_task: BTTask, child_task: BTTask) -> void:
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
			"parameters": task.parameters.duplicate(true)
		})

	var bb_data := {}
	if blackboard != null:
		for var_name in blackboard.get_all_variables().keys():
			var variable: BTBlackboard.Variable = blackboard.get_variable_obj(var_name)
			bb_data[var_name] = {
				"value": variable.value,
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

static func from_dict(data: Dictionary, registry: BTTaskRegistry = null) -> BTTree:
	var tree := BTTree.new()
	tree.tree_name = str(data.get("tree_name", "Untitled Tree"))
	tree.description = str(data.get("description", ""))
	tree.metadata = data.get("metadata", {}).duplicate()

	if registry == null:
		registry = BTTaskRegistry.new()

	var nodes_data: Array = data.get("nodes", [])
	var id_to_task := {}
	var parent_map := {}
	var children_map := {}

	# 1. Create tasks
	for n_dict in nodes_data:
		var nid: int = int(n_dict.get("id", 0))
		var type_name: String = str(n_dict.get("type_name", "BTTask"))
		var task: BTTask = registry.create_task(type_name)
		task.id = nid
		task.friendly_name = str(n_dict.get("friendly_name", type_name))
		task.category = str(n_dict.get("category", task.category))
		if n_dict.has("is_placeholder"):
			task.is_placeholder = bool(n_dict.get("is_placeholder"))
		task.parameters = n_dict.get("parameters", {}).duplicate()

		tree.add_node(task)
		id_to_task[nid] = task
		parent_map[nid] = int(n_dict.get("parent_id", -1))
		children_map[nid] = n_dict.get("children_ids", [])

	# 2. Connect parent-child
	for nid in children_map.keys():
		var p_task: BTTask = id_to_task.get(nid, null)
		if p_task != null:
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
			tree.blackboard.set_var(str(k), serialized.get("value"), str(serialized.get("type_name", "Variant")))
			var variable: BTBlackboard.Variable = tree.blackboard.get_variable_obj(str(k))
			variable.is_shared = bool(serialized.get("is_shared", true))
			variable.description = str(serialized.get("description", ""))
		else:
			# Backward-compatible with the original scalar blackboard format.
			tree.blackboard.set_var(str(k), serialized)

	return tree
