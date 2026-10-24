class_name BTRatTaskBase
extends BTTask

func _get_param_any(keys: Array, default_val = null):
	for k in keys:
		var v = get_param(str(k), null)
		if v != null:
			return v
	return default_val

func _get_bb(key: String, default_val = null):
	if key.begins_with("$") or key.begins_with("@"):
		key = key.substr(1)
	return get_blackboard_var(key, default_val)

func _set_bb(key: String, val) -> void:
	if key.begins_with("$") or key.begins_with("@"):
		key = key.substr(1)
	set_blackboard_var(key, val)

func _get_actor() -> Node:
	if owner != null and "actor" in owner:
		return owner.actor
	return null

func _get_delta() -> float:
	if owner != null and "delta" in owner:
		return float(owner.delta)
	return 0.1

static func get_node_pos(node) -> Vector3:
	if node is Node3D:
		return node.global_position if node.is_inside_tree() else node.position
	return Vector3.ZERO

func _is_actor_disabled() -> bool:
	var actor := _get_actor()
	if actor == null:
		return false
	if "is_caught" in actor and bool(actor.is_caught):
		return true
	if "is_placed_on_pit" in actor and bool(actor.is_placed_on_pit):
		return true
	return false
