class_name BTStopBehaviorTree
extends BTGhostTaskBase

func on_update() -> int:
	var actor = _get_actor()
	if actor != null and actor.has_method("on_ghost_banished"):
		actor.on_ghost_banished()

	if owner != null and owner.has_method("stop"):
		owner.stop()

	return BTStatus.SUCCESS
