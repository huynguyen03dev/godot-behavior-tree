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
	var external_mappings := {}
	for key in _tree_files.keys():
		var path: String = _tree_files[key]
		if not _is_in_directory(path):
			external_mappings[key] = path
	_scan_directory()
	for key in external_mappings.keys():
		if not _tree_files.has(key):
			_tree_files[key] = external_mappings[key]

func _is_in_directory(path: String) -> bool:
	var dir_norm := _directory_path.simplify_path()
	var path_norm := path.simplify_path()
	if dir_norm == "res://" or dir_norm == "user://":
		return path_norm.begins_with(dir_norm)
	return path_norm == dir_norm or path_norm.begins_with(dir_norm + "/")

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
		var base_key := path.get_file().get_basename()
		if not _tree_files.has(base_key):
			_tree_files[base_key] = path
	return tree

func save_tree(identifier: String, tree: BTTree) -> bool:
	last_error = ""
	if tree == null or identifier == "":
		last_error = "tree is null or identifier is empty"
		return false
	var data := tree.to_dict()
	var errors := BTTree.validate_dict(data, tree.registry)
	if not errors.is_empty():
		last_error = errors[0]
		push_error("BTFileTreeSource: refusing to save tree '%s': %s" % [identifier, "; ".join(errors)])
		return false
	var path := _resolve_save_path(identifier)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var err_msg := "BTFileTreeSource: failed to open file for writing at '%s'" % path
		push_error(err_msg)
		last_error = err_msg
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	var base_key := identifier.get_file().get_basename()
	if _tree_files.has(base_key):
		if _tree_files[base_key] != path:
			push_warning("BTFileTreeSource: basename '%s' already maps to '%s'; keeping existing mapping instead of '%s'" % [base_key, _tree_files[base_key], path])
	else:
		_tree_files[base_key] = path
	return true

## Relative identifiers resolve under the source directory (appending ".json"
## when missing); res://, user:// and absolute paths are used as-is.
func _resolve_save_path(identifier: String) -> String:
	if identifier.begins_with("res://") or identifier.begins_with("user://") or identifier.is_absolute_path():
		return identifier
	if _tree_files.has(identifier):
		return _tree_files[identifier]
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
