class_name BTMemoryTreeSource
extends BTTreeSourceProvider
## In-memory Behavior Tree Source Provider for dynamically generated trees and unit tests.

var _trees: Dictionary = {} # name -> BTTree

func get_source_name() -> String:
	return "Memory BT Source"

func register_tree(name: String, tree: BTTree) -> void:
	if tree != null:
		tree.tree_name = name
		_trees[name] = tree

func list_trees() -> Array:
	var keys = _trees.keys()
	keys.sort()
	return keys

func load_tree(identifier: String) -> BTTree:
	return _trees.get(identifier, null)

func save_tree(identifier: String, tree: BTTree) -> bool:
	last_error = ""
	if tree == null or identifier == "":
		last_error = "tree is null or identifier is empty"
		return false
	var errors := BTTree.validate_dict(tree.to_dict(), tree.registry)
	if not errors.is_empty():
		last_error = errors[0]
		push_error("BTMemoryTreeSource: refusing to store tree '%s': %s" % [identifier, "; ".join(errors)])
		return false
	register_tree(identifier, tree)
	return true
