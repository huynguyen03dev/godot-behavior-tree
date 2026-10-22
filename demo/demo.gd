extends Control
## Standalone Demo Scene for Godot Behavior Tree.
## Embeds the BTViewer and provides interactive controls to test tree loading,
## live blackboard variable modification, and tick execution.

@onready var viewer: BTViewer = $VBoxContainer/BTViewer
@onready var log_label: RichTextLabel = $VBoxContainer/BottomPanel/HBoxContainer/LogLabel

var _runner: BTRunner = null
var _tree: BTTree = null

## Demo-local leaf tasks. The addon only registers composites and decorators
## by default, so the leaves of the shipped sample tree would load as
## placeholders and every tick would report INACTIVE. These give the sample
## tree real conditions and actions to execute.
class DemoCondition extends BTTask:
	func _init() -> void:
		super._init()
		type_name = "Condition"
		category = "Condition"

	func on_update() -> int:
		var variable := str(get_param("variable", ""))
		if variable == "":
			return BTStatus.SUCCESS
		var threshold := float(get_param("threshold", 0.0))
		var value := float(get_blackboard_var(variable, threshold))
		return BTStatus.SUCCESS if value > threshold else BTStatus.FAILURE

class DemoAction extends BTTask:
	func _init() -> void:
		super._init()
		type_name = "Action"
		category = "Action"

func _ready() -> void:
	var provider = BTFileTreeSource.new("res://demo/data", _build_task_registry())
	viewer.set_tree_source(provider)
	viewer.load_tree_file("res://demo/data/patrol_ai.json")
	_tree = viewer.current_tree
	if _tree != null:
		_create_runner(_tree)
	_log("[color=green]Ready![/color] Loaded 'PatrolAndCombatAI'. Press buttons below to test live execution.")

## Registry used to build the demo trees. It extends the addon defaults with
## the demo leaf tasks so the sample tree runs instead of stalling on
## placeholder nodes.
func _build_task_registry() -> BTTaskRegistry:
	var registry := BTTaskRegistry.new()
	registry.register_task("Condition", func(): return DemoCondition.new(), "Condition")
	registry.register_task("Action", func(): return DemoAction.new(), "Action")
	return registry

## Creates and starts a runner for a tree. The runner becomes a child of the
## demo so it follows the scene's Node lifecycle, and processing is disabled
## because the demo ticks the tree manually.
func _create_runner(p_tree: BTTree) -> void:
	_runner = BTRunner.new(p_tree)
	add_child(_runner)
	_runner.set_process(false)
	_runner.start()

## The viewer swaps `current_tree` whenever JSON is applied, which orphans the
## runner bound to the previous tree. Re-bind the runner to the viewer's tree
## before every use so the demo always drives the tree on screen.
func _sync_runner() -> void:
	if viewer == null:
		return
	if viewer.current_tree == _tree and _runner != null and is_instance_valid(_runner):
		return
	_free_runner()
	_tree = viewer.current_tree
	if _tree != null:
		_create_runner(_tree)

## Stops and releases the current runner. Required because a runner that is
## not freed stays alive after the demo scene is gone.
func _free_runner() -> void:
	if _runner == null:
		return
	if is_instance_valid(_runner):
		_runner.stop()
		_runner.free()
	_runner = null

func _exit_tree() -> void:
	_free_runner()

func _on_step_tick_pressed() -> void:
	_sync_runner()
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
	_sync_runner()
	if _tree == null or _tree.blackboard == null:
		return
	var current = bool(_tree.blackboard.get_var("has_target", false))
	_tree.blackboard.set_var("has_target", not current)
	_log("Toggled 'has_target' to: [b]%s[/b]" % str(not current))

func _on_damage_agent_pressed() -> void:
	_sync_runner()
	if _tree == null or _tree.blackboard == null:
		return
	var hp = int(_tree.blackboard.get_var("health", 100))
	hp = max(0, hp - 30)
	_tree.blackboard.set_var("health", hp)
	_log("Agent damaged! Health is now: [b]%d[/b]" % hp)

func _log(msg: String) -> void:
	if log_label != null:
		log_label.append_text(msg + "\n")
