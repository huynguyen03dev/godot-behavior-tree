class_name BTTreeSourceProvider
extends RefCounted
## Abstract interface for Behavior Tree source providers (JSON files, Resources, Memory, Network).

func get_source_name() -> String:
	return "Generic BT Source"

func list_trees() -> Array: # Array[String]
	return []

func load_tree(identifier: String) -> BTTree:
	return null

func get_tree_path(identifier: String) -> String:
	return identifier

func save_tree(identifier: String, tree: BTTree) -> bool:
	return false
