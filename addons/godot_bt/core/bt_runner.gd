class_name BTRunner
extends BTRunnerNative

enum UpdateInterval { EVERY_FRAME = 0, SPECIFIED_SECONDS = 1 }
enum ExecutionsPerTick { NO_LIMIT = 0, COUNT = 1 }

func _init(p_tree: BTTree = null) -> void:
	if p_tree != null:
		tree = p_tree

func _ready() -> void:
	ready()

func _process(delta: float) -> void:
	process(delta)

func _exit_tree() -> void:
	stop()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		stop()

func tick(p_delta: float = 0.0) -> int:
	return bt_tick(p_delta)

func send_event(event_name: String, data = null) -> void:
	bt_send_event(event_name, data)

func pause(paused: bool = true) -> void:
	bt_pause(paused)

func interrupt(task, status: int = 1) -> void:
	bt_interrupt(task, status)
