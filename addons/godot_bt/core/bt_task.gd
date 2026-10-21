class_name BTTask
extends RefCounted
## Base task class for the generic Behavior Tree framework.
## Supports both GDScript conventions (snake_case) and Behavior Designer conventions (PascalCase).

var id: int = -1
var friendly_name: String = ""
var type_name: String = "BTTask"
var category: String = "Action" # Root, Composite, Decorator, Action, Condition, Unknown
var is_placeholder: bool = false
var parameters: Dictionary = {}

var blackboard: BTBlackboard = null
var owner: Node = null
var parent: BTTask = null

# Runtime state
var last_status: int = BTStatus.INACTIVE

func _init() -> void:
	if friendly_name == "":
		friendly_name = get_script_name()

func get_script_name() -> String:
	var s = get_script()
	if s != null:
		var gn = s.get_global_name()
		if gn != "":
			return str(gn)
	return type_name

# ---------------------------------------------------------------- Lifecycle
func on_awake() -> void:
	if has_method("OnAwake"):
		call("OnAwake")

func on_reset() -> void:
	last_status = BTStatus.INACTIVE
	if has_method("OnReset"):
		call("OnReset")

func on_start() -> void:
	if has_method("OnStart"):
		call("OnStart")

func on_update() -> int:
	if has_method("OnUpdate"):
		return int(call("OnUpdate"))
	return BTStatus.SUCCESS

func on_end() -> void:
	if has_method("OnEnd"):
		call("OnEnd")

func on_abort() -> void:
	if has_method("OnConditionalAbort"):
		call("OnConditionalAbort")
	elif has_method("OnAbort"):
		call("OnAbort")
	on_end()

func on_pause(paused: bool) -> void:
	if has_method("OnPause"):
		call("OnPause", paused)

func on_event(event_name: String, data: Variant = null) -> void:
	if has_method("OnEvent"):
		call("OnEvent", event_name, data)

# ---------------------------------------------------------------- Parameter & Blackboard Helpers
## Returns the resolved value of a parameter.
## If the parameter is bound to a Blackboard key, it fetches the dynamic value from Blackboard.
func get_param(name: String, default_val: Variant = null) -> Variant:
	if not parameters.has(name):
		return default_val
	var raw = parameters[name]
	if raw is Dictionary and raw.get("is_blackboard", false):
		var bb_key: String = str(raw.get("key", ""))
		return get_blackboard_var(bb_key, default_val)
	elif raw is String:
		if raw.begins_with("@") or raw.begins_with("$"):
			var bb_key: String = raw.substr(1)
			if blackboard != null and blackboard.has_var(bb_key):
				return blackboard.get_var(bb_key, default_val)
	return raw

func set_param(name: String, value: Variant, is_blackboard_key: bool = false) -> void:
	if is_blackboard_key:
		parameters[name] = {
			"is_blackboard": true,
			"key": str(value)
		}
	else:
		parameters[name] = value

func is_param_blackboard(name: String) -> bool:
	if not parameters.has(name):
		return false
	var raw = parameters[name]
	if raw is Dictionary and raw.get("is_blackboard", false):
		return true
	if raw is String and (raw.begins_with("@") or raw.begins_with("$")):
		return true
	return false

func get_param_blackboard_key(name: String) -> String:
	if not parameters.has(name):
		return ""
	var raw = parameters[name]
	if raw is Dictionary and raw.get("is_blackboard", false):
		return str(raw.get("key", ""))
	if raw is String and (raw.begins_with("@") or raw.begins_with("$")):
		return raw.substr(1)
	return ""

# Blackboard helper
func get_blackboard_var(name: String, default_val: Variant = null) -> Variant:
	if blackboard != null:
		return blackboard.get_var(name, default_val)
	return default_val

func set_blackboard_var(name: String, val: Variant) -> void:
	if blackboard != null:
		blackboard.set_var(name, val)
