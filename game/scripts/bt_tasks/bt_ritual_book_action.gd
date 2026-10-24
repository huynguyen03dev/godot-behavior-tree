class_name BTRitualBookAction
extends BTGhostTaskBase

func on_update() -> int:
	var action_type: String = str(_get_param_any(["action_type"], "can_carry"))
	var book_var = _get_param_any(["book_variable", "interactable", "entityObject", "targetGameObject"], "$RitualBook")

	var book = null
	if str(book_var).begins_with("$") or str(book_var).begins_with("@"):
		book = _get_bb(str(book_var))
	elif book_var is Object:
		book = book_var

	var actor = _get_actor()

	match action_type:
		"can_carry":
			return BTStatus.SUCCESS
		"detach":
			# BoltDetach decision: reparent RitualBook (Altar -> hand Ghost/Player)
			if actor != null and book is Node3D and actor.has_method("attach_carried_object"):
				actor.attach_carried_object(book)
			return BTStatus.SUCCESS
		"get_metadata":
			_set_bb("RitualBookMetadata", "CursedBook_01")
			return BTStatus.SUCCESS
		"set_carry_name":
			if actor != null and book is Node3D and actor.has_method("attach_carried_object"):
				actor.attach_carried_object(book)
			return BTStatus.SUCCESS

	return BTStatus.SUCCESS
