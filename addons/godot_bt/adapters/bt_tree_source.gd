class_name BTTreeSourceProvider
extends RefCounted
## Abstract interface for Behavior Tree source providers (JSON files, Resources, Memory, Network).

var last_error: String = ""

func get_source_name() -> String:
	return "Generic BT Source"

func list_trees() -> Array: # Array[String]
	last_error = ""
	return []

func load_tree(identifier: String) -> BTTree:
	last_error = ""
	return null

func get_tree_path(identifier: String) -> String:
	return identifier

func save_tree(identifier: String, tree: BTTree) -> bool:
	last_error = ""
	return false
