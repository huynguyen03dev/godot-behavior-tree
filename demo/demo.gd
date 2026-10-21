extends Control
## Standalone Demo Scene for Godot Behavior Tree.
## Embeds the BTViewer and provides interactive controls to test tree loading,
## live blackboard variable modification, and tick execution.

@onready var viewer: BTViewer = $VBoxContainer/BTViewer
@onready var log_label: RichTextLabel = $VBoxContainer/BottomPanel/HBoxContainer/LogLabel

var _runner: BTRunner = null
var _tree: BTTree = null

func _ready() -> void:
	var provider = BTFileTreeSource.new("res://demo/data")
	viewer.set_tree_source(provider)
	viewer.load_tree_file("res://demo/data/patrol_ai.json")
	_tree = viewer.current_tree
	if _tree != null:
		_runner = BTRunner.new(_tree)
		_log("[color=green]Ready![/color] Loaded 'PatrolAndCombatAI'. Press buttons below to test live execution.")

func _on_step_tick_pressed() -> void:
	if _runner == null:
		return
	var status = _runner.tick()
	var status_str = "RUNNING"
	match status:
		BTStatus.SUCCESS: status_str = "[color=green]SUCCESS[/color]"
		BTStatus.FAILURE: status_str = "[color=red]FAILURE[/color]"
		BTStatus.RUNNING: status_str = "[color=yellow]RUNNING[/color]"
		BTStatus.INACTIVE: status_str = "[color=gray]INACTIVE[/color]"
	_log("Executed Tick -> Result: %s" % status_str)

func _on_toggle_target_pressed() -> void:
	if _tree == null or _tree.blackboard == null:
		return
	var current = bool(_tree.blackboard.get_var("has_target", false))
	_tree.blackboard.set_var("has_target", not current)
	_log("Toggled 'has_target' to: [b]%s[/b]" % str(not current))

func _on_damage_agent_pressed() -> void:
	if _tree == null or _tree.blackboard == null:
		return
	var hp = int(_tree.blackboard.get_var("health", 100))
	hp = max(0, hp - 30)
	_tree.blackboard.set_var("health", hp)
	_log("Agent damaged! Health is now: [b]%d[/b]" % hp)

func _log(msg: String) -> void:
	if log_label != null:
		log_label.append_text(msg + "\n")
