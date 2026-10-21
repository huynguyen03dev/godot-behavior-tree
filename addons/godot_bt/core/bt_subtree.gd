class_name BTSubTree
extends BTTask
## SubTree task (BehaviorReference / ExternalBehavior).
## Embeds and executes an external behavior tree seamlessly within the parent tree.

var tree_path: String = ""
var _sub_tree: BTTree = null
var _sub_runner: BTRunner = null

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
	_load_subtree()

func _load_subtree() -> void:
	var path: String = str(get_param("tree_path", tree_path))
	if path == "":
		return

	# Load file
	var actual_path = path
	if not actual_path.begins_with("res://") and not actual_path.begins_with("user://"):
		actual_path = "res://".path_join(actual_path)
	if not actual_path.ends_with(".json"):
		actual_path += ".json"

	if not FileAccess.file_exists(actual_path):
		return

	var file = FileAccess.open(actual_path, FileAccess.READ)
	if file == null:
		return

	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
		_sub_tree = BTTree.from_dict(json.data)
		# Share parent blackboard with subtree
		if blackboard != null:
			_sub_tree.blackboard = blackboard
			for node in _sub_tree.node_list:
				if node != null:
					node.blackboard = blackboard

		_sub_runner = BTRunner.new(_sub_tree)

func on_start() -> void:
	super.on_start()
	if _sub_tree == null:
		_load_subtree()
	if _sub_runner != null:
		# Sync blackboard and owner
		_sub_tree.blackboard = blackboard
		for node in _sub_tree.node_list:
			if node != null:
				node.blackboard = blackboard
				node.owner = owner
		_sub_runner.start()

func on_update() -> int:
	if _sub_runner == null or _sub_tree == null or _sub_tree.root_task == null:
		return BTStatus.FAILURE
	var status = _sub_runner.tick()
	return status

func on_end() -> void:
	super.on_end()
	if _sub_runner != null and _sub_runner.is_running:
		_sub_runner.stop()

func on_abort() -> void:
	if _sub_runner != null and _sub_runner.is_running:
		_sub_runner.stop()
	super.on_abort()
