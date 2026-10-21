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

# Blackboard helper
func get_blackboard_var(name: String, default_val: Variant = null) -> Variant:
	if blackboard != null:
		return blackboard.get_var(name, default_val)
	return default_val

func set_blackboard_var(name: String, val: Variant) -> void:
	if blackboard != null:
		blackboard.set_var(name, val)
