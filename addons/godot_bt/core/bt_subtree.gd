class_name BTSubTree
extends BTTask

func _init(p_path := "") -> void:
	_setup_kind("SubTree", "SubTree", "Action")
	if p_path != "":
		tree_path = p_path
