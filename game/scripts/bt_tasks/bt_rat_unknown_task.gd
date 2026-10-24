class_name BTRatUnknownTask
extends BTRatTaskBase

var task_mode: String = "" # "player", "hay", "seek"
var magnitude: float = 2.0
var returned_var_name: String = ""

func on_awake() -> void:
	var sjson: String = str(_get_param_any(["StringJSONSerialization"], ""))
	if sjson.is_empty():
		return
	var test_json := JSON.new()
	if test_json.parse(sjson) == OK and test_json.data is Dictionary:
		var d: Dictionary = test_json.data
		var type_name: String = str(d.get("Type", ""))
		var name_str: String = str(d.get("Name", ""))

		if "GoatWithinDistance" in type_name or "Near" in name_str:
			var players_mode = d.get("SharedBoolplayersMode", {}).get("BooleanmValue", false)
			var hay_mode = d.get("SharedBoolhayMode", {}).get("BooleanmValue", false)
			magnitude = float(d.get("SharedFloatmagnitude", {}).get("SinglemValue", 2.0))
			returned_var_name = str(d.get("SharedGameObjectreturnedObject", {}).get("Name", ""))

			if players_mode or "Player" in name_str:
				task_mode = "player"
				if returned_var_name.is_empty():
					returned_var_name = "PlayerWithinDistance"
			elif hay_mode or "Hay" in name_str:
				task_mode = "hay"
				if returned_var_name.is_empty():
					returned_var_name = "Hay"
		elif "GoatSeek" in type_name or "Seek" in name_str:
			task_mode = "seek"

func on_update() -> int:
	var actor := _get_actor()
	if actor == null:
		return BTStatus.FAILURE

	if task_mode == "player":
		var player = null
		if actor.has_method("get_player"):
			player = actor.get_player()
		elif _get_bb("Players") is Array and not (_get_bb("Players") as Array).is_empty():
			player = (_get_bb("Players") as Array)[0]

		if player is Node3D:
			var dist = get_node_pos(actor).distance_to(get_node_pos(player))
			if dist <= magnitude:
				if not returned_var_name.is_empty():
					_set_bb(returned_var_name, player)
				return BTStatus.SUCCESS

		return BTStatus.FAILURE

	elif task_mode == "hay":
		var hay_obj = _get_bb("Hay")
		if hay_obj is Node3D:
			var dist = get_node_pos(actor).distance_to(get_node_pos(hay_obj))
			if dist <= magnitude:
				return BTStatus.SUCCESS
		return BTStatus.FAILURE

	elif task_mode == "seek":
		if _is_actor_disabled():
			return BTStatus.RUNNING
		var hay_target = _get_bb("Hay")
		if hay_target is Node3D:
			var hay_pos = get_node_pos(hay_target)
			var seek_speed: float = float(_get_bb("SeekSpeed", 0.4))
			if actor.has_method("move_towards_point"):
				actor.move_towards_point(hay_pos, seek_speed)
			if get_node_pos(actor).distance_to(hay_pos) <= 0.5:
				return BTStatus.SUCCESS
			return BTStatus.RUNNING
		return BTStatus.FAILURE

	return BTStatus.SUCCESS

func evaluate_condition(_runner) -> int:
	return on_update()
