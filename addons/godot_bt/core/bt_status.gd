class_name BTStatus
extends RefCounted
## Standard execution status for Behavior Trees (aligned with Unity Behavior Designer / NodeCanvas).

enum Type {
	INACTIVE = 0,
	FAILURE = 1,
	SUCCESS = 2,
	RUNNING = 3
}

const INACTIVE := Type.INACTIVE
const FAILURE := Type.FAILURE
const SUCCESS := Type.SUCCESS
const RUNNING := Type.RUNNING

static func to_string_name(status: int) -> String:
	match status:
		Type.INACTIVE:
			return "Inactive"
		Type.FAILURE:
			return "Failure"
		Type.SUCCESS:
			return "Success"
		Type.RUNNING:
			return "Running"
		_:
			return "Unknown(%d)" % status

static func get_color(status: int) -> Color:
	match status:
		Type.INACTIVE:
			return Color(0.5, 0.5, 0.5, 1.0)
		Type.FAILURE:
			return Color(0.9, 0.2, 0.2, 1.0)
		Type.SUCCESS:
			return Color(0.2, 0.8, 0.3, 1.0)
		Type.RUNNING:
			return Color(0.9, 0.7, 0.1, 1.0)
		_:
			return Color.WHITE
