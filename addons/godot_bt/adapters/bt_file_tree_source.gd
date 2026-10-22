class_name BTFileTreeSource
extends BTTreeSourceProvider
## Generic Tree Source Provider that scans and loads Behavior Tree files (`.json`) from any directory.
## Fully decoupled and project-agnostic.

var _directory_path: String = ""
var _tree_files: Dictionary = {} # tree_name -> resolved file path
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

## Rescans the source directory. Mappings registered by load_tree for files
## outside the directory are kept so later saves still target those files.
func refresh() -> void:
	var loaded_external := {}
	for key in _tree_files.keys():
		loaded_external[key] = _tree_files[key]
	_scan_directory()
	for key in loaded_external.keys():
		if not _tree_files.has(key):
			_tree_files[key] = loaded_external[key]

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

	var tree = BTTree.from_dict(data, _registry)
	if tree != null:
		# Remember the resolved file so a later save_tree by basename updates
		# this file instead of creating a new one in the source directory.
		_tree_files[path.get_file().get_basename()] = path
	return tree

func save_tree(identifier: String, tree: BTTree) -> bool:
	if tree == null or identifier == "":
		return false
	var data := tree.to_dict()
	var errors := BTTree.validate_dict(data, tree.registry)
	if not errors.is_empty():
		push_error("BTFileTreeSource: refusing to save tree '%s': %s" % [identifier, "; ".join(errors)])
		return false
	var path := _resolve_save_path(identifier)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	_tree_files[identifier.get_file().get_basename()] = path
	return true

## Relative identifiers resolve under the source directory (appending ".json"
## when missing); res://, user:// and absolute paths are used as-is.
func _resolve_save_path(identifier: String) -> String:
	if _tree_files.has(identifier):
		return _tree_files[identifier]
	if identifier.begins_with("res://") or identifier.begins_with("user://") or identifier.is_absolute_path():
		return identifier
	return _directory_path.path_join(identifier if identifier.ends_with(".json") else identifier + ".json")

func _scan_directory() -> void:
	_tree_files.clear()
	# Open the directory through its res:// or user:// path instead of a
	# globalized filesystem path so listing also works in exported PCK builds.
	var dir = DirAccess.open(_directory_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var tname = file_name.get_basename()
			_tree_files[tname] = _directory_path.path_join(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
