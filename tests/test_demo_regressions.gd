extends SceneTree
## Regression tests for the demo scene's behavior tree runner lifecycle.
## Covers review item B4/P15: "Step BT Tick" never ran the tree because the
## runner was never started and never added to the tree, applying JSON in the
## viewer orphaned the runner, and the runner leaked on scene exit.

const DEMO_SCENE := preload("res://demo/demo.tscn")

var failures := 0
var checks := 0

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
	else:
		print("PASS: " + description)

func _initialize() -> void:
	await _test_step_tick_runs_the_tree()
	await _test_apply_json_rebinds_the_runner()
	await _test_scene_exit_releases_the_runner()
	print("Demo regression tests: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _new_demo() -> Node:
	var demo: Node = DEMO_SCENE.instantiate()
	root.add_child(demo)
	await process_frame
	await process_frame
	return demo

## Status word the demo writes to its log for a given runner status.
func _status_word(status: int) -> String:
	match status:
		BTStatus.SUCCESS:
			return "SUCCESS"
		BTStatus.FAILURE:
			return "FAILURE"
		BTStatus.RUNNING:
			return "RUNNING"
		_:
			return "INACTIVE"

func _test_step_tick_runs_the_tree() -> void:
	var demo: Node = await _new_demo()
	var runner: BTRunner = demo._runner
	_check(runner != null, "demo creates a runner on start")
	_check(runner != null and runner.is_inside_tree(), "runner is added to the scene tree")
	demo._on_step_tick_pressed()
	_check(runner.ticks == 1, "one Step press executes exactly one tick")
	_check(runner.last_status != BTStatus.INACTIVE, "Step tick reports a real status")
	var log_text: String = demo.log_label.get_parsed_text()
	_check(log_text.contains("Executed Tick -> Result"), "log mentions the executed result")
	_check(log_text.contains("Result: %s" % _status_word(runner.last_status)), "log reports the executed status")
	demo.free()
	await process_frame

func _test_apply_json_rebinds_the_runner() -> void:
	var demo: Node = await _new_demo()
	demo._on_step_tick_pressed()
	var old_runner: BTRunner = demo._runner
	var old_runner_ref: WeakRef = weakref(old_runner)
	var old_tree: BTTree = demo._tree
	var viewer: BTViewer = demo.viewer
	viewer._json_text_edit.text = JSON.stringify(old_tree.to_dict(), "\t")
	viewer._on_apply_json_pressed()
	_check(viewer.current_tree != old_tree, "applying JSON replaces the viewer's tree")
	demo._on_step_tick_pressed()
	var new_runner: BTRunner = demo._runner
	_check(new_runner != old_runner, "a new runner is created for the replaced tree")
	_check(new_runner != null and new_runner.tree == viewer.current_tree, "the new runner drives the viewer's tree")
	_check(new_runner.ticks == 1, "the new runner executed exactly one tick")
	_check(new_runner.last_status != BTStatus.INACTIVE, "the new runner reports a real status")
	_check(old_runner_ref.get_ref() == null, "the orphaned runner is freed")
	demo.free()
	await process_frame

func _test_scene_exit_releases_the_runner() -> void:
	var demo: Node = await _new_demo()
	var runner: BTRunner = demo._runner
	var runner_ref: WeakRef = weakref(runner)
	_check(runner != null and runner.is_inside_tree(), "runner is alive before the scene is freed")
	demo.free()
	await process_frame
	_check(runner_ref.get_ref() == null, "freeing the demo scene releases the runner")
