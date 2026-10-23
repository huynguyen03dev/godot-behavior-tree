class_name BTTree
extends BTTreeNative

func _init() -> void:
	blackboard = BTBlackboard.new()
	registry = BTTaskRegistry.new()

static func from_dict(data: Dictionary, registry = null) -> BTTree:
	return BTTreeNative.from_dict(data, registry)

static func validate_dict(data: Dictionary, registry = null):
	var out := PackedStringArray()
	for e in BTTreeNative.validate_dict(data, registry):
		out.append(str(e))
	return out
