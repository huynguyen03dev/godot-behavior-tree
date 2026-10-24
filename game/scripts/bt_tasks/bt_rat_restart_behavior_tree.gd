class_name BTRatRestartBehaviorTree
extends BTRatTaskBase

func on_update() -> int:
	if owner != null and "tree" in owner and owner.tree != null:
		var root = owner.tree.get_root()
		if root != null and root.has_method("reset"):
			root.reset()
	return BTStatus.SUCCESS
