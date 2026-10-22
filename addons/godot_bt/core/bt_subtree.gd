class_name BTSubTree
extends BTTask
## SubTree task (BehaviorReference / ExternalBehavior).
## Embeds and executes an external behavior tree seamlessly within the parent tree.

var tree_path: String = ""
var _sub_tree: BTTree = null
var _sub_runner: BTRunner = null
var _subtree_loading: bool = false
var _loaded_path: String = ""

func _init(p_path: String = "") -> void:
	super._init()
	type_name = "SubTree"
	friendly_name = "SubTree"
	category = "Action"
	if p_path != "":
		tree_path = p_path
		parameters["tree_path"] = p_path

func on_awake() -> void:
	super.on_awake()
	_ensure_subtree_loaded()

func _resolved_tree_path() -> String:
	var path: String = str(get_param("tree_path", tree_path))
	if path == "":
		return ""
	if not path.begins_with("res://") and not path.begins_with("user://"):
		path = "res://".path_join(path)
	if not path.ends_with(".json"):
		path += ".json"
	return path.simplify_path()

## Loads the subtree only on first use or when tree_path changed; the parsed
## tree is cached across resets so repeated starts do not re-read the file.
func _ensure_subtree_loaded() -> void:
	var normalized_path := _resolved_tree_path()
	if normalized_path == "":
		return
	if _sub_tree != null and normalized_path == _loaded_path:
		return
	_load_subtree(normalized_path)

func _load_subtree(normalized_path: String = "") -> void:
	if _subtree_loading:
		return
	_subtree_loading = true
	if normalized_path == "":
		normalized_path = _resolved_tree_path()
	if normalized_path == "":
		_subtree_loading = false
		return

	_cleanup_runner()
	var parent_runner: BTRunner = owner as BTRunner if owner is BTRunner else null
	if parent_runner != null and parent_runner.subtree_path_stack.has(normalized_path):
		_subtree_loading = false
		return

	if not FileAccess.file_exists(normalized_path):
		_subtree_loading = false
		return

	var file = FileAccess.open(normalized_path, FileAccess.READ)
	if file == null:
		_subtree_loading = false
		return

	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Dictionary and BTTree.validate_dict(json.data).is_empty():
		var task_registry: BTTaskRegistry = owner.tree.registry if owner is BTRunner and owner.tree != null else null
		_sub_tree = BTTree.from_dict(json.data, task_registry)
		# Share parent blackboard with subtree
		if _sub_tree != null and blackboard != null:
			_sub_tree.blackboard = blackboard
			for node in _sub_tree.node_list:
				if node != null:
					node.blackboard = blackboard

		if _sub_tree != null:
			_sub_runner = BTRunner.new(_sub_tree)
			_sub_runner.actor = owner.actor if owner is BTRunner else null
			if parent_runner != null:
				_sub_runner.subtree_path_stack = parent_runner.subtree_path_stack.duplicate()
				_sub_runner.subtree_path_stack.append(normalized_path)
	_loaded_path = normalized_path
	_subtree_loading = false

func _cleanup_runner() -> void:
	if _sub_runner != null:
		_sub_runner.stop()
		if is_instance_valid(_sub_runner):
			_sub_runner.free()
	_sub_runner = null
	_sub_tree = null

func on_start() -> void:
	super.on_start()
	_ensure_subtree_loaded()
	if _sub_runner != null:
		# Sync blackboard and owner
		_sub_tree.blackboard = blackboard
		for node in _sub_tree.node_list:
			if node != null:
				node.blackboard = blackboard
		_sub_runner.actor = owner.actor if owner is BTRunner else null
		_sub_runner.start()

func on_update() -> int:
	if _sub_runner == null or _sub_tree == null or _sub_tree.root_task == null:
		return BTStatus.FAILURE
	_sub_runner.delta = owner.delta if owner is BTRunner else 0.0
	var status = _sub_runner.tick(_sub_runner.delta)
	return status

func on_end() -> void:
	super.on_end()
	if _sub_runner != null:
		_sub_runner.stop()

func on_abort() -> void:
	if _sub_runner != null:
		_sub_runner.stop()
	super.on_abort()

func on_reset() -> void:
	super.on_reset()
	# Keep the parsed subtree cached across resets: only stop the sub-runner.
	# on_start restarts it, and the tree reloads just once the path changes.
	if _sub_runner != null:
		_sub_runner.stop()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# RefCounted predelete runs after this object's refcount reaches zero; do not
		# dispatch through self methods while destruction is in progress.
		var dying_runner: BTRunner = _sub_runner
		_sub_runner = null
		_sub_tree = null
		if dying_runner != null and is_instance_valid(dying_runner):
			dying_runner.stop()
			dying_runner.free()
