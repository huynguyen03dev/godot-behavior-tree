class_name BTFileTreeSource
extends BTTreeSourceProvider
## Generic Tree Source Provider that scans and loads Behavior Tree files (`.json`) from any directory.
## Fully decoupled and project-agnostic.

var _directory_path: String = ""
var _tree_files: Dictionary = {} # tree_name -> absolute_path
var _registry: BTTaskRegistry = null

func _init(directory: String = "res://", task_registry: BTTaskRegistry = null) -> void:
	_directory_path = directory
	_registry = task_registry
	_scan_directory()

func get_source_name() -> String:
	return "Generic File Trees (%s)" % _directory_path

func get_directory_path() -> String:
	return _directory_path

func list_trees() -> Array:
	var names := _tree_files.keys()
	names.sort()
	return names

func get_tree_path(identifier: String) -> String:
	return _tree_files.get(identifier, identifier)

func load_tree(identifier: String) -> BTTree:
	var path: String = identifier
	if _tree_files.has(identifier):
		path = _tree_files[identifier]
	elif not FileAccess.file_exists(path):
		var full = _directory_path.path_join(identifier if identifier.ends_with(".json") else identifier + ".json")
		if FileAccess.file_exists(full):
			path = full

	if not FileAccess.file_exists(path):
		return null

	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null

	var text = file.get_as_text()
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		return null

	var data = json.data
	if not (data is Dictionary):
		return null

	return BTTree.from_dict(data, _registry)

func save_tree(identifier: String, tree: BTTree) -> bool:
	if tree == null or identifier == "":
		return false
	var path: String = identifier
	if _tree_files.has(identifier):
		path = _tree_files[identifier]
	elif not path.ends_with(".json"):
		path = _directory_path.path_join(identifier + ".json")
	var abs_path = ProjectSettings.globalize_path(path)
	var file = FileAccess.open(abs_path, FileAccess.WRITE)
	if file == null:
		return false
	var json_str = JSON.stringify(tree.to_dict(), "\t")
	file.store_string(json_str)
	file.close()
	_tree_files[identifier] = abs_path
	return true

func _scan_directory() -> void:
	_tree_files.clear()
	var abs_dir = ProjectSettings.globalize_path(_directory_path)
	if not DirAccess.dir_exists_absolute(abs_dir):
		return
	var dir = DirAccess.open(abs_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var tname = file_name.get_basename()
			_tree_files[tname] = abs_dir.path_join(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
