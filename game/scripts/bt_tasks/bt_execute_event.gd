class_name BTExecuteEvent
extends BTGhostTaskBase

func on_update() -> int:
	var event_name: String = str(_get_param_any(["event_name", "EventName"], ""))
	var target_key = _get_param_any(["target_object", "targetGameObject"], null)
	var target = null
	if target_key != null:
		target = _get_bb(str(target_key))

	var actor = _get_actor()
	if actor != null and actor.has_method("handle_bt_event"):
		actor.handle_bt_event(event_name, target)

	return BTStatus.SUCCESS
