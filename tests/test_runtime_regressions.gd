extends SceneTree

class Probe extends BTTask:
	var results: Array[int] = [BTStatus.RUNNING]
	var calls := 0
	var ends := 0
	var aborts := 0
	var callback_runner: BTRunner
	var interrupt_on_update := false
	var condition := false
	func on_update() -> int:
		calls += 1
		if interrupt_on_update and owner is BTRunner:
			(owner as BTRunner).interrupt(self)
		return results[min(calls - 1, results.size() - 1)]
	func evaluate_condition(_runner: BTRunner) -> int:
		return BTStatus.SUCCESS if condition else BTStatus.FAILURE
	func on_end() -> void:
		ends += 1
		if callback_runner != null:
			var r := callback_runner
			callback_runner = null
			r.stop()
	func on_abort() -> void:
		aborts += 1
		super.on_abort()

class ProbeCondition extends Probe:
	func _init() -> void:
		category = "Condition"
	func on_update() -> int:
		calls += 1
		return BTStatus.SUCCESS if condition else BTStatus.FAILURE

class CallbackProbe extends Probe:
	var start_callback: Callable
	var awake_callback: Callable
	var update_callback: Callable
	func on_start() -> void:
		if start_callback.is_valid(): start_callback.call()
	func on_awake() -> void:
		if awake_callback.is_valid(): awake_callback.call()
	func on_update() -> int:
		calls += 1
		if update_callback.is_valid(): update_callback.call()
		return results[min(calls - 1, results.size() - 1)]

class OrderedRandomSequence extends BTComposite.BTRandomSequence:
	func on_start() -> void:
		super.on_start()
		_shuffled_order = [1, 0]

class OrderedRandomSelector extends BTComposite.BTRandomSelector:
	func on_start() -> void:
		super.on_start()
		_shuffled_order = [1, 0]

class DeltaProbe extends BTTask:
	var deltas: Array[float] = []
	func _init() -> void:
		type_name = "DeltaProbe"
	func on_update() -> int:
		if owner is BTRunner:
			deltas.append((owner as BTRunner).delta)
		return BTStatus.RUNNING

class NestedTickProbe extends BTTask:
	var calls := 0
	func _init() -> void:
		type_name = "NestedTickProbe"
	func on_update() -> int:
		calls += 1
		if calls == 1 and owner is BTRunner:
			(owner as BTRunner).tick()
		return BTStatus.SUCCESS

## Legacy-style condition (category "Condition", no evaluate_condition override)
## that can stop the runner from its on_update, used to probe abort reevaluation.
class LegacyStopCondition extends BTTask:
	var calls := 0
	var armed := false
	var succeed := false
	func _init() -> void:
		type_name = "LegacyStopCondition"
		category = "Condition"
	func on_update() -> int:
		calls += 1
		if armed and owner is BTRunner:
			(owner as BTRunner).stop()
		return BTStatus.SUCCESS if succeed else BTStatus.FAILURE

var checks := 0
var failures := 0

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)

func _runner(tree: BTTree) -> BTRunner:
	var runner := BTRunner.new(tree)
	root.add_child(runner)
	return runner

func _pair_tree(parent: BTParentTask, a: BTTask, b: BTTask) -> BTTree:
	var tree := BTTree.new()
	tree.set_root(parent)
	tree.connect_parent_child(parent, a)
	tree.connect_parent_child(parent, b)
	return tree

func _finish(runner: BTRunner) -> void:
	if is_instance_valid(runner):
		runner.stop()
		runner.queue_free()

func _initialize() -> void:
	var parallel := BTComposite.BTParallel.new()
	var active := Probe.new()
	var done := Probe.new()
	done.results = [BTStatus.SUCCESS]
	var r := _runner(_pair_tree(parallel, active, done))
	r.start()
	_check(r.tick() == BTStatus.RUNNING and active.calls == 1 and done.calls == 1, "Parallel asymmetric success leaves active branch running")
	active.results = [BTStatus.RUNNING, BTStatus.SUCCESS]
	_check(r.tick() == BTStatus.SUCCESS and active.ends == 1, "Parallel completes after remaining branch succeeds")
	_finish(r)

	parallel = BTComposite.BTParallel.new()
	active = Probe.new()
	done = Probe.new()
	done.results = [BTStatus.FAILURE]
	r = _runner(_pair_tree(parallel, active, done)); r.start()
	_check(r.tick() == BTStatus.FAILURE and active.aborts == 1, "Parallel failure cleans up still-running branch")
	_finish(r)

	var seq0 := BTComposite.BTSequence.new()
	var seq1 := BTComposite.BTSequence.new()
	var seq2 := BTComposite.BTSequence.new()
	var leaf := Probe.new(); leaf.results = [BTStatus.SUCCESS]
	var deep_tree := BTTree.new(); deep_tree.set_root(seq0)
	deep_tree.connect_parent_child(seq0, seq1); deep_tree.connect_parent_child(seq1, seq2); deep_tree.connect_parent_child(seq2, leaf)
	r = _runner(deep_tree); r.executions_per_tick = BTRunner.ExecutionsPerTick.COUNT; r.max_task_executions_per_tick = 1; r.start()
	for i in 4:
		if r.is_running: r.tick()
		_check(r.task_executions <= 1, "Nested depth-three sequence respects budget at tick %d" % (i + 1))
	_check(leaf.calls == 1 and leaf.last_status == BTStatus.SUCCESS, "Budgeted nested sequence makes progress and executes leaf")
	_finish(r)

	parallel = BTComposite.BTParallel.new(); var p1 := Probe.new(); var p2 := Probe.new()
	r = _runner(_pair_tree(parallel, p1, p2)); r.executions_per_tick = BTRunner.ExecutionsPerTick.COUNT; r.max_task_executions_per_tick = 1; r.start()
	for _i in 4: r.tick()
	_check(p1.calls > 0 and p2.calls > 0, "Parallel budget dispatch is fair to both running children within four ticks")
	_finish(r)

	var run_tree := BTTree.new(); leaf = Probe.new(); run_tree.set_root(leaf)
	r = _runner(run_tree); r.start(); r.tick(); r.pause(); r.pause(false); r.tick(); var resumed_calls := leaf.calls; r.stop(); r.tick()
	_check(resumed_calls == 2 and leaf.calls == resumed_calls, "Pause/resume continues ticking and stop prevents extra ticks")
	_finish(r)

	leaf = Probe.new(); run_tree = BTTree.new(); run_tree.set_root(leaf); r = _runner(run_tree); r.max_ticks = 1; r.start(); r.tick(); r.tick()
	_check(not r.is_running and leaf.ends == 1, "max_ticks stops runner and cleans active task")
	_finish(r)

	leaf = Probe.new(); run_tree = BTTree.new(); run_tree.set_root(leaf); r = BTRunner.new(run_tree); r.start(); r.tick(); r.free()
	_check(leaf.ends == 1, "Freeing unparented active runner ends task once")

	leaf = Probe.new(); run_tree = BTTree.new(); run_tree.set_root(leaf); r = _runner(run_tree); leaf.callback_runner = r; r.start(); r.tick(); r.stop()
	_check(leaf.ends == 1 and not r.is_running, "on_end callback can reentrantly stop runner once")
	_finish(r)

	var timeout := BTDecorator.BTTimeLimit.new(); timeout.time_limit = 0.0
	var nested_parent := BTComposite.BTSequence.new(); leaf = Probe.new()
	var timeout_tree := BTTree.new(); timeout_tree.set_root(timeout); timeout_tree.connect_parent_child(timeout, nested_parent); timeout_tree.connect_parent_child(nested_parent, leaf)
	r = _runner(timeout_tree); r.start(); var timed_status := r.tick()
	_check(timed_status == BTStatus.FAILURE and leaf.aborts == 1 and leaf.ends == 1, "TimeLimit aborts running descendant exactly once")
	_finish(r)

	var parent := BTComposite.BTSequence.new(); var child := Probe.new(); parent.add_child_task(child)
	var weak_parent: WeakRef = weakref(parent); var weak_child: WeakRef = weakref(child); parent = null; child = null
	_check(weak_parent.get_ref() == null and weak_child.get_ref() == null, "Weak parent/child references release after tree references drop")

	var repeater := BTDecorator.BTRepeater.new(); repeater.parameters["count"] = 3; leaf = Probe.new(); leaf.results = [BTStatus.SUCCESS]
	var repeat_tree := BTTree.new(); repeat_tree.set_root(repeater); repeat_tree.connect_parent_child(repeater, leaf)
	r = _runner(repeat_tree); r.executions_per_tick = BTRunner.ExecutionsPerTick.COUNT; r.max_task_executions_per_tick = 1; r.start()
	for _i in 8:
		if r.is_running: r.tick()
	_check(leaf.calls == 3 and not r.is_running, "Count-three repeater performs exactly three executions across ticks")
	_finish(r)

	repeater = BTDecorator.BTRepeater.new(); repeater.count = 0; repeater.repeat_forever = true; leaf = Probe.new(); leaf.results = [BTStatus.SUCCESS]
	repeat_tree = BTTree.new(); repeat_tree.set_root(repeater); repeat_tree.connect_parent_child(repeater, leaf); r = _runner(repeat_tree)
	r.executions_per_tick = BTRunner.ExecutionsPerTick.COUNT; r.max_task_executions_per_tick = 0; r.start()
	for _i in 3: r.tick()
	_check(leaf.calls == 3 and r.is_running, "COUNT-mode forever repeater yields once per tick")
	_finish(r)

	leaf = Probe.new(); leaf.results = [BTStatus.SUCCESS]; run_tree = BTTree.new(); run_tree.set_root(leaf); r = _runner(run_tree); r.start(); r.tick(); r.pause(false)
	_check(not r.is_running, "pause(false) on completed tree does not restart runner")
	_finish(r)

	seq0 = BTComposite.BTSequence.new(); var guard := ProbeCondition.new(); guard.condition = true; leaf = Probe.new()
	var interrupt_tree := BTTree.new(); interrupt_tree.set_root(seq0); interrupt_tree.connect_parent_child(seq0, guard); interrupt_tree.connect_parent_child(seq0, leaf)
	r = _runner(interrupt_tree); r.start(); r.tick(); r.interrupt(leaf, BTStatus.FAILURE); var calls_before := leaf.calls; var propagated := r.tick()
	_check(propagated == BTStatus.FAILURE and leaf.calls == calls_before, "Interrupt of active non-root leaf propagates failure without another leaf update")
	_finish(r)

	leaf = Probe.new(); run_tree = BTTree.new(); run_tree.set_root(leaf); r = _runner(run_tree); var finished_signals := [0]
	r.tree_finished.connect(func(_status: int) -> void: finished_signals[0] += 1)
	r.start(); r.tick(); r.interrupt(leaf, BTStatus.FAILURE)
	_check(r.last_status == BTStatus.FAILURE and finished_signals[0] == 1 and not r.is_running, "Interrupting root sets final status and emits completion once")
	_finish(r)

	var abort_sel := BTComposite.BTSelector.new(); abort_sel.set_abort_type(BTComposite.AbortType.LOWER_PRIORITY)
	var high_seq := BTComposite.BTSequence.new(); var wrapper: BTDecorator = BTDecorator.BTInverter.new(); var wrapped_condition := ProbeCondition.new(); wrapped_condition.condition = true; wrapper.add_child_task(wrapped_condition)
	var high_action := Probe.new(); high_seq.add_child_task(wrapper); high_seq.add_child_task(high_action)
	var low_action := Probe.new(); var abort_tree := BTTree.new(); abort_tree.set_root(abort_sel); abort_tree.connect_parent_child(abort_sel, high_seq); abort_tree.connect_parent_child(abort_sel, low_action)
	r = _runner(abort_tree); r.start(); r.tick(); wrapped_condition.condition = false; r.tick()
	_check(low_action.aborts == 1 and high_action.calls == 1 and wrapped_condition.calls == 2, "Inverter guard is pure and successful preemption starts high branch")
	_finish(r)

	abort_sel = BTComposite.BTSelector.new(); abort_sel.set_abort_type(BTComposite.AbortType.LOWER_PRIORITY)
	high_seq = BTComposite.BTSequence.new(); wrapper = BTDecorator.BTReturnFailure.new(); wrapped_condition = ProbeCondition.new(); wrapped_condition.condition = false; wrapper.add_child_task(wrapped_condition)
	high_action = Probe.new(); high_seq.add_child_task(wrapper); high_seq.add_child_task(high_action); low_action = Probe.new()
	abort_tree = BTTree.new(); abort_tree.set_root(abort_sel); abort_tree.connect_parent_child(abort_sel, high_seq); abort_tree.connect_parent_child(abort_sel, low_action)
	r = _runner(abort_tree); r.start(); r.tick(); r.tick(); wrapped_condition.condition = true; r.tick()
	_check(low_action.aborts == 0 and low_action.calls == 3 and high_action.calls == 0 and wrapped_condition.calls == 1, "ReturnFailure guard never preempts whether its condition succeeds or fails")
	_finish(r)

	var random_seq := OrderedRandomSequence.new(); random_seq.set_abort_type(BTComposite.AbortType.SELF)
	guard = ProbeCondition.new(); guard.condition = true; var random_action := Probe.new()
	var random_tree := BTTree.new(); random_tree.set_root(random_seq); random_tree.connect_parent_child(random_seq, random_action); random_tree.connect_parent_child(random_seq, guard)
	r = _runner(random_tree); r.start(); r.tick(); guard.condition = false; r.tick()
	_check(random_action.aborts == 1 and random_action.calls == 1, "RandomSequence abort follows execution order to correct active action")
	_finish(r)

	var random_sel := OrderedRandomSelector.new(); random_sel.set_abort_type(BTComposite.AbortType.LOWER_PRIORITY)
	low_action = Probe.new(); guard = ProbeCondition.new(); guard.condition = false
	var selector_tree := BTTree.new(); selector_tree.set_root(random_sel); selector_tree.connect_parent_child(random_sel, low_action); selector_tree.connect_parent_child(random_sel, guard)
	r = _runner(selector_tree); r.start(); r.tick(); guard.condition = true; r.tick()
	_check(low_action.aborts == 1 and low_action.calls == 1 and guard.calls == 2, "RandomSelector higher-priority guard preempts correct running action")
	_finish(r)

	leaf = Probe.new(); leaf.interrupt_on_update = true; leaf.results = [BTStatus.SUCCESS]
	run_tree = BTTree.new(); run_tree.set_root(leaf); r = _runner(run_tree); var self_finished := [0]
	r.tree_finished.connect(func(_status: int) -> void: self_finished[0] += 1)
	r.start(); var self_status := r.tick()
	_check(self_status == BTStatus.FAILURE and leaf.last_status == BTStatus.FAILURE and leaf.ends == 1 and self_finished[0] == 1, "Root self-interrupt during update preserves failure and completes once")
	_finish(r)

	seq0 = BTComposite.BTSequence.new(); var self_leaf := Probe.new(); self_leaf.interrupt_on_update = true; var untouched := Probe.new()
	interrupt_tree = BTTree.new(); interrupt_tree.set_root(seq0); interrupt_tree.connect_parent_child(seq0, self_leaf); interrupt_tree.connect_parent_child(seq0, untouched)
	r = _runner(interrupt_tree); r.start(); r.tick()
	_check(untouched.calls == 0 and self_leaf.ends == 1, "Non-root self-interrupt fails sequence without updating sibling")
	_finish(r)

	seq0 = BTComposite.BTSequence.new(); var ending := Probe.new(); ending.results = [BTStatus.SUCCESS]; ending.callback_runner = _runner(_pair_tree(seq0, ending, Probe.new()))
	# Replace callback with a terminal callback that stops from on_end.
	var ending_runner := ending.callback_runner; ending_runner.start(); ending_runner.tick()
	_check(ending.ends == 1, "Terminal on_end stop does not double-end task or advance sibling")
	_finish(ending_runner)

	var restart_leaf := CallbackProbe.new(); restart_leaf.results = [BTStatus.SUCCESS]
	run_tree = BTTree.new(); run_tree.set_root(restart_leaf); r = _runner(run_tree); var restart_guard := [false]; var restart_finished := [0]
	r.tree_finished.connect(func(_status: int) -> void: restart_finished[0] += 1)
	var restart_callback := func(task: BTTask, _status: int) -> void:
		if task == restart_leaf and not restart_guard[0]:
			restart_guard[0] = true
			r.start()
	r.task_finished.connect(restart_callback)
	r.start(); r.tick()
	_check(r.is_running and r.ticks == 0 and restart_leaf.calls == 1 and restart_finished[0] == 0, "task_finished restart keeps new run active and old tick cannot overwrite reset state")
	r.task_finished.disconnect(restart_callback)
	_finish(r)

	var old_seq := BTComposite.BTSequence.new(); var old_done := Probe.new(); old_done.results = [BTStatus.SUCCESS]; var old_sibling := Probe.new()
	var tree_a := BTTree.new(); tree_a.set_root(old_seq); tree_a.connect_parent_child(old_seq, old_done); tree_a.connect_parent_child(old_seq, old_sibling)
	var replacement := Probe.new(); var tree_b := BTTree.new(); tree_b.set_root(replacement); r = _runner(tree_a); var swapped := [false]
	var swap_callback := func(task: BTTask, _status: int) -> void:
		if task == old_done and not swapped[0]:
			swapped[0] = true
			r.set_tree(tree_b); r.start()
	r.task_finished.connect(swap_callback)
	r.start(); r.tick(); r.tick()
	_check(old_sibling.calls == 0 and replacement.calls == 1, "task_finished tree swap suppresses old siblings and replacement runs on next tick")
	r.task_finished.disconnect(swap_callback)
	_finish(r)

	var stopped_leaf := CallbackProbe.new(); stopped_leaf.start_callback = func() -> void: (stopped_leaf.owner as BTRunner).stop()
	run_tree = BTTree.new(); run_tree.set_root(stopped_leaf); r = _runner(run_tree); r.start(); r.tick()
	_check(stopped_leaf.calls == 0, "on_start stop prevents update")
	stopped_leaf.start_callback = Callable()
	_finish(r)

	var awake_leaf := CallbackProbe.new(); var awake_guard := [false]; var awake_calls := [0]
	awake_leaf.awake_callback = func() -> void:
		awake_calls[0] += 1
		if not awake_guard[0]:
			awake_guard[0] = true
			var task_runner := awake_leaf.owner as BTRunner
			task_runner.set_tree(task_runner.tree); task_runner.start()
	run_tree = BTTree.new(); run_tree.set_root(awake_leaf); r = _runner(run_tree); awake_leaf.results = [BTStatus.RUNNING]; r.start()
	_check(awake_calls[0] == 2 and r.is_running and r.ticks == 0, "on_awake tree replacement and guarded restart leaves fresh run initialized")
	awake_leaf.awake_callback = Callable()
	_finish(r)

	repeater = BTDecorator.BTRepeater.new(); repeater.parameters["count"] = 3; timeout = BTDecorator.BTTimeLimit.new(); timeout.time_limit = 0.0
	leaf = Probe.new(); var repeat_timeout_tree := BTTree.new(); repeat_timeout_tree.set_root(repeater); repeat_timeout_tree.connect_parent_child(repeater, timeout); repeat_timeout_tree.connect_parent_child(timeout, leaf)
	r = _runner(repeat_timeout_tree); r.start()
	for _i in 8:
		if r.is_running: r.tick()
	_check(not r.is_running and leaf.calls == 3 and leaf.aborts == 3 and leaf.ends == 3 and repeater.last_status == BTStatus.FAILURE, "Count-three repeater retries timed-out running leaf exactly thrice then fails")
	var post_completion_ticks := r.ticks; r.tick()
	_check(r.ticks == post_completion_ticks, "Completed timeout repeater leaves no pending terminal skip")
	_finish(r)

	# ---- P16: tick_log gated behind debug_log and capped at 512 ----
	var fx_log_leaf := Probe.new()
	var fx_log_tree := BTTree.new(); fx_log_tree.set_root(fx_log_leaf)
	r = _runner(fx_log_tree); r.start()
	for _i in 2000:
		r.tick()
	_check(r.tick_log.size() == 0, "P16 tick_log stays empty with debug_log off after 2000 ticks")
	r.debug_log = true
	r.start()
	for _i in 3:
		r.tick()
	_check(r.tick_log.size() == 3, "P16 tick_log records one entry per tick with debug_log on")
	for _i in 2000:
		r.tick()
	_check(r.tick_log.size() > 0 and r.tick_log.size() <= 512, "P16 tick_log capped at 512 entries with debug_log on")
	_finish(r)

	# ---- P1/P2: get_param binding resolution and @@/$$ escapes ----
	var fx_bb := BTBlackboard.new(); fx_bb.set_var("hp", 42, "int")
	var fx_task := BTTask.new(); fx_task.blackboard = fx_bb
	fx_task.parameters["bound"] = "@hp"
	fx_task.parameters["missing"] = "@nope"
	fx_task.parameters["dollar_bound"] = "$hp"
	fx_task.parameters["dollar_missing"] = "$nope"
	fx_task.parameters["esc_at"] = "@@foo"
	fx_task.parameters["esc_dollar"] = "$$foo"
	_check(int(fx_task.get_param("bound", -1)) == 42 and int(fx_task.get_param("dollar_bound", -1)) == 42, "P1 @/$ bindings resolve existing blackboard keys")
	_check(fx_task.get_param("missing", "D") == "D" and fx_task.get_param("dollar_missing", "D") == "D", "P1 unresolvable @/$ bindings return default_val instead of the literal")
	var fx_null_bb_task := BTTask.new(); fx_null_bb_task.parameters["x"] = "@hp"
	_check(fx_null_bb_task.get_param("x", 99) == 99, "P1 @ binding with null blackboard returns default_val")
	_check(fx_task.get_param("esc_at", "") == "@foo" and fx_task.get_param("esc_dollar", "") == "$foo", "P2 @@/$$ escapes return literal strings")
	_check(not fx_task.is_param_blackboard("esc_at") and not fx_task.is_param_blackboard("esc_dollar"), "P2 escaped strings are not detected as blackboard params")
	_check(fx_task.get_param_blackboard_key("esc_at") == "" and fx_task.get_param_blackboard_key("esc_dollar") == "", "P2 escaped strings expose no blackboard key")
	_check(fx_task.is_param_blackboard("bound") and fx_task.get_param_blackboard_key("dollar_bound") == "hp", "P1 @/$ bindings still detected with their key")

	# ---- P9: interrupt on a never-started task is a no-op ----
	var fx_seq := BTComposite.BTSequence.new()
	var fx_a := Probe.new(); fx_a.results = [BTStatus.SUCCESS]
	var fx_b := Probe.new(); fx_b.results = [BTStatus.SUCCESS]
	var fx_int_tree := BTTree.new(); fx_int_tree.set_root(fx_seq)
	fx_int_tree.connect_parent_child(fx_seq, fx_a); fx_int_tree.connect_parent_child(fx_seq, fx_b)
	r = _runner(fx_int_tree); r.start()
	r.interrupt(fx_b, BTStatus.FAILURE)
	var fx_int_status := r.tick()
	_check(fx_int_status == BTStatus.SUCCESS and fx_a.calls == 1 and fx_b.calls == 1, "P9 interrupting a never-started non-root task is a no-op")
	_finish(r)

	# ---- P3: update_interval accumulates elapsed time, drift-free ----
	var fx_delta_leaf := DeltaProbe.new()
	var fx_delta_tree := BTTree.new(); fx_delta_tree.set_root(fx_delta_leaf)
	r = _runner(fx_delta_tree)
	r.update_interval = BTRunner.UpdateInterval.SPECIFIED_SECONDS
	r.update_interval_seconds = 0.5
	r.start()
	for _i in 5:
		r._process(0.1)
	_check(r.ticks == 1 and fx_delta_leaf.deltas.size() == 1 and abs(fx_delta_leaf.deltas[0] - 0.5) < 0.0001, "P3 five 0.1s frames produce one 0.5s tick")
	_finish(r)

	# EVERY_FRAME mode (the default) must tick every frame with the frame delta
	var fx_frame_leaf := DeltaProbe.new()
	var fx_frame_tree := BTTree.new(); fx_frame_tree.set_root(fx_frame_leaf)
	r = _runner(fx_frame_tree); r.start()
	r._process(0.1)
	_check(r.ticks == 1 and fx_frame_leaf.deltas.size() == 1 and abs(fx_frame_leaf.deltas[0] - 0.1) < 0.0001, "P3 EVERY_FRAME _process ticks each frame with the frame delta")
	_finish(r)

	# ---- P5: simulated time drives TimeLimit and Cooldown ----
	var fx_time_leaf := Probe.new()
	var fx_time_tree := BTTree.new(); fx_time_tree.set_root(fx_time_leaf)
	r = _runner(fx_time_tree); r.start()
	r.tick(0.1)
	r.start()
	r.tick(0.2)
	_check(abs(r.time - 0.3) < 0.0001, "P5 runner.time accumulates tick deltas and survives restarts")
	_finish(r)

	var fx_tl := BTDecorator.BTTimeLimit.new(); fx_tl.time_limit = 0.05
	var fx_tl_leaf := Probe.new()
	var fx_tl_tree := BTTree.new(); fx_tl_tree.set_root(fx_tl); fx_tl_tree.connect_parent_child(fx_tl, fx_tl_leaf)
	r = _runner(fx_tl_tree); r.start()
	var fx_tl_always_running := true
	for _i in 5:
		if r.tick(0.0) != BTStatus.RUNNING:
			fx_tl_always_running = false
	_check(fx_tl_always_running and fx_tl_leaf.aborts == 0, "P5 TimeLimit with zero delta never expires")
	var fx_tl_status := r.tick(0.06)
	_check(fx_tl_status == BTStatus.FAILURE and fx_tl_leaf.aborts == 1, "P5 TimeLimit fails once simulated delta passes the limit")
	_finish(r)

	var fx_cd := BTDecorator.BTCooldown.new(); fx_cd.cooldown_time = 0.5
	var fx_cd_leaf := Probe.new(); fx_cd_leaf.results = [BTStatus.SUCCESS]
	var fx_cd_tree := BTTree.new(); fx_cd_tree.set_root(fx_cd); fx_cd_tree.connect_parent_child(fx_cd, fx_cd_leaf)
	r = _runner(fx_cd_tree); r.start()
	_check(r.tick(0.0) == BTStatus.SUCCESS, "P5 Cooldown first run succeeds")
	r.start()
	_check(r.tick(0.0) == BTStatus.FAILURE, "P5 Cooldown blocks with no simulated time elapsed")
	r.start()
	_check(r.tick(0.35) == BTStatus.FAILURE, "P5 Cooldown still blocks before simulated time elapses")
	r.start()
	_check(r.tick(0.15) == BTStatus.SUCCESS, "P5 Cooldown opens as simulated time advances past the window")
	_finish(r)

	# ---- P13: max_task_executions_per_tick applies in NO_LIMIT mode ----
	var fx_bseq := BTComposite.BTSequence.new()
	var fx_b1 := Probe.new(); fx_b1.results = [BTStatus.SUCCESS]
	var fx_b2 := Probe.new(); fx_b2.results = [BTStatus.SUCCESS]
	var fx_b3 := Probe.new(); fx_b3.results = [BTStatus.SUCCESS]
	var fx_budget_tree := BTTree.new(); fx_budget_tree.set_root(fx_bseq)
	fx_budget_tree.connect_parent_child(fx_bseq, fx_b1)
	fx_budget_tree.connect_parent_child(fx_bseq, fx_b2)
	fx_budget_tree.connect_parent_child(fx_bseq, fx_b3)
	r = _runner(fx_budget_tree)
	r.max_task_executions_per_tick = 1
	r.start()
	var fx_budget_status := r.tick()
	_check(fx_budget_status == BTStatus.RUNNING and fx_b1.calls == 1 and fx_b2.calls == 0 and fx_b3.calls == 0 and r.task_executions == 1, "P13 budget applies with NO_LIMIT enum: first tick runs only one leaf")
	r.tick()
	var fx_budget_final := r.tick()
	_check(fx_budget_final == BTStatus.SUCCESS and fx_b2.calls == 1 and fx_b3.calls == 1, "P13 budgeted sequence still completes across ticks")
	_finish(r)

	# ---- P17: Parallel tolerates placeholder children ----
	var fx_par := BTComposite.BTParallel.new()
	var fx_par_run := Probe.new()
	var fx_ph: BTTask = BTTaskRegistry.BTUnknownTask.new("MissingTask")
	var fx_par_tree := BTTree.new(); fx_par_tree.set_root(fx_par)
	fx_par_tree.connect_parent_child(fx_par, fx_par_run)
	fx_par_tree.connect_parent_child(fx_par, fx_ph)
	r = _runner(fx_par_tree); r.start()
	var fx_par_s1 := r.tick()
	var fx_par_s2 := r.tick()
	_check(fx_par_s1 == BTStatus.RUNNING and fx_par_s2 == BTStatus.RUNNING and r.is_running and fx_par_run.aborts == 0 and fx_par_run.calls == 2, "P17 Parallel with placeholder sibling stays running and never aborts it")
	_check(fx_par._warned_placeholders.size() == 1, "P17 placeholder sibling warned exactly once")
	_finish(r)

	var fx_only_par := BTComposite.BTParallel.new()
	var fx_only_ph: BTTask = BTTaskRegistry.BTUnknownTask.new("OnlyPlaceholder")
	var fx_only_tree := BTTree.new(); fx_only_tree.set_root(fx_only_par)
	fx_only_tree.connect_parent_child(fx_only_par, fx_only_ph)
	r = _runner(fx_only_tree); r.start()
	var fx_only_status := r.tick()
	_check(fx_only_status == BTStatus.INACTIVE and not r.is_running, "P17 Parallel of only placeholders returns INACTIVE")
	_finish(r)

	# ---- P19: decorator parameter schemas; direct assignment still works ----
	var fx_rep := BTDecorator.BTRepeater.new(); fx_rep.count = 4
	var fx_rep_schema: Dictionary = fx_rep.get_parameter_schema()
	_check(fx_rep_schema.has("count") and fx_rep_schema["count"]["type"] == "int" and int(fx_rep_schema["count"]["default"]) == 4, "P19 Repeater schema exposes typed count with current value")
	_check(fx_rep_schema.has("repeat_forever") and fx_rep_schema["repeat_forever"]["type"] == "bool" and fx_rep_schema.has("end_on_failure") and fx_rep_schema["end_on_failure"]["type"] == "bool", "P19 Repeater schema exposes bool flags")
	_check(fx_rep.parameters.is_empty(), "P19 schema does not inject defaults into parameters")
	var fx_cd_schema: Dictionary = BTDecorator.BTCooldown.new().get_parameter_schema()
	_check(fx_cd_schema.has("cooldown_time") and fx_cd_schema["cooldown_time"]["type"] == "float" and abs(float(fx_cd_schema["cooldown_time"]["default"]) - 1.0) < 0.0001, "P19 Cooldown schema exposes cooldown_time as float")
	var fx_tl_schema: Dictionary = BTDecorator.BTTimeLimit.new().get_parameter_schema()
	_check(fx_tl_schema.has("time_limit") and fx_tl_schema["time_limit"]["type"] == "float" and abs(float(fx_tl_schema["time_limit"]["default"]) - 5.0) < 0.0001, "P19 TimeLimit schema exposes time_limit as float")
	var fx_dir_rep := BTDecorator.BTRepeater.new(); fx_dir_rep.count = 3
	var fx_dir_leaf := Probe.new(); fx_dir_leaf.results = [BTStatus.SUCCESS]
	var fx_dir_tree := BTTree.new(); fx_dir_tree.set_root(fx_dir_rep); fx_dir_tree.connect_parent_child(fx_dir_rep, fx_dir_leaf)
	r = _runner(fx_dir_tree); r.start()
	for _i in 4:
		if r.is_running:
			r.tick()
	_check(fx_dir_leaf.calls == 3 and not r.is_running, "P19 direct property assignment still configures the repeater without parameters")
	_finish(r)

	# ---- P22: safe bool coercion for string-typed parameters ----
	_check(BTTask.coerce_bool("true") == true and BTTask.coerce_bool("1") == true, "P22 coerce_bool parses true strings")
	_check(BTTask.coerce_bool("false") == false and BTTask.coerce_bool("0") == false, "P22 coerce_bool parses false strings")
	_check(BTTask.coerce_bool("junk", true) == true and BTTask.coerce_bool(null, false) == false, "P22 coerce_bool falls back on unparseable values")
	_check(BTTask.coerce_bool(1) == true and BTTask.coerce_bool(0) == false and BTTask.coerce_bool(2.5) == true and BTTask.coerce_bool(true) == true, "P22 coerce_bool handles bool/int/float")
	var fx_srep := BTDecorator.BTRepeater.new()
	fx_srep.parameters["repeat_forever"] = "true"
	fx_srep.parameters["end_on_failure"] = "false"
	fx_srep.count = 1
	var fx_sleaf := Probe.new(); fx_sleaf.results = [BTStatus.SUCCESS]
	var fx_stree := BTTree.new(); fx_stree.set_root(fx_srep); fx_stree.connect_parent_child(fx_srep, fx_sleaf)
	r = _runner(fx_stree); r.start()
	for _i in 3:
		r.tick()
	_check(fx_sleaf.calls == 3 and r.is_running, "P22 string \"true\" repeat_forever runs forever without script errors")
	var fx_srep2 := BTDecorator.BTRepeater.new()
	fx_srep2.parameters["repeat_forever"] = "false"
	fx_srep2.parameters["end_on_failure"] = "true"
	fx_srep2.count = 2
	var fx_sleaf2 := Probe.new(); fx_sleaf2.results = [BTStatus.SUCCESS]
	var fx_stree2 := BTTree.new(); fx_stree2.set_root(fx_srep2); fx_stree2.connect_parent_child(fx_srep2, fx_sleaf2)
	r = _runner(fx_stree2); r.start()
	for _i in 3:
		if r.is_running:
			r.tick()
	_check(fx_sleaf2.calls == 2 and not r.is_running, "P22 string \"false\" repeat_forever respects count without script errors")
	_finish(r)

	# ---- P20: stop() emits task_finished for started tasks ----
	var fx_stop_seq := BTComposite.BTSequence.new()
	var fx_stop_leaf := Probe.new()
	var fx_stop_tree := BTTree.new(); fx_stop_tree.set_root(fx_stop_seq)
	fx_stop_tree.connect_parent_child(fx_stop_seq, fx_stop_leaf)
	r = _runner(fx_stop_tree)
	var fx_started: Array = []
	var fx_finished: Array = []
	r.task_started.connect(func(t) -> void: fx_started.append(t))
	r.task_finished.connect(func(t, s: int) -> void: fx_finished.append([t, s]))
	r.start(); r.tick()
	_check(fx_started.size() == 2 and fx_started[0] == fx_stop_seq and fx_started[1] == fx_stop_leaf, "P20 tick starts sequence and leaf")
	r.stop()
	_check(fx_finished.size() == 2 and fx_finished[0][0] == fx_stop_seq and fx_finished[1][0] == fx_stop_leaf and fx_finished[1][1] == BTStatus.RUNNING, "P20 stop() emits task_finished for every started task after on_end")
	_finish(r)

	# ---- P10: re-entrant tick() is refused ----
	var fx_nested := NestedTickProbe.new()
	var fx_nested_tree := BTTree.new(); fx_nested_tree.set_root(fx_nested)
	r = _runner(fx_nested_tree); r.start()
	var fx_nested_status := r.tick()
	_check(fx_nested_status == BTStatus.SUCCESS and fx_nested.calls == 1 and r.ticks == 1, "P10 re-entrant tick from a leaf is ignored and runs exactly once")
	_finish(r)

	# ---- P4: start() propagates tree.blackboard to every task ----
	var fx_bb_leaf := Probe.new()
	var fx_bb_tree := BTTree.new(); fx_bb_tree.set_root(fx_bb_leaf)
	var fx_new_bb := BTBlackboard.new(); fx_new_bb.set_var("x", 7, "int")
	fx_bb_tree.blackboard = fx_new_bb
	r = _runner(fx_bb_tree); r.start()
	_check(fx_bb_leaf.blackboard == fx_new_bb and fx_bb_leaf.get_blackboard_var("x", -1) == 7, "P4 start() propagates a replaced tree.blackboard to every task")
	_finish(r)

	# ---- S12: tick unwinds after a legacy condition stops the runner during abort reevaluation ----
	var fx_stop_sel := BTComposite.BTSelector.new()
	fx_stop_sel.set_abort_type(BTComposite.AbortType.LOWER_PRIORITY)
	var fx_legacy_cond := LegacyStopCondition.new()
	var fx_stop_high := BTComposite.BTSequence.new()
	var fx_high_action := Probe.new()
	var fx_low_action2 := Probe.new()
	var fx_sel_tree := BTTree.new(); fx_sel_tree.set_root(fx_stop_sel)
	fx_sel_tree.connect_parent_child(fx_stop_sel, fx_stop_high)
	fx_sel_tree.connect_parent_child(fx_stop_high, fx_legacy_cond)
	fx_sel_tree.connect_parent_child(fx_stop_high, fx_high_action)
	fx_sel_tree.connect_parent_child(fx_stop_sel, fx_low_action2)
	r = _runner(fx_sel_tree); r.start(); r.tick()
	fx_legacy_cond.armed = true
	fx_legacy_cond.succeed = true
	r.tick()
	_check(fx_legacy_cond.calls == 2 and fx_high_action.calls == 0 and not r.is_running, "S12 tick unwinds after a condition stops the runner during abort reevaluation")
	_finish(r)

	# ---- S4: task_aborted signal on interruption ----
	var fx_abort_seq := BTComposite.BTSequence.new()
	var fx_abort_leaf := Probe.new()
	var fx_abort_tree := BTTree.new(); fx_abort_tree.set_root(fx_abort_seq)
	fx_abort_tree.connect_parent_child(fx_abort_seq, fx_abort_leaf)
	r = _runner(fx_abort_tree)
	var fx_aborted: Array = []
	var fx_abort_finished: Array = []
	r.task_aborted.connect(func(t) -> void: fx_aborted.append(t))
	r.task_finished.connect(func(t, s: int) -> void: fx_abort_finished.append([t, s]))
	r.start(); r.tick()
	r.interrupt(fx_abort_leaf, BTStatus.FAILURE)
	_check(fx_aborted.size() == 1 and fx_aborted[0] == fx_abort_leaf, "S4 task_aborted fires for the interrupted task")
	_check(fx_abort_finished.size() == 1 and fx_abort_finished[0][0] == fx_abort_leaf and fx_abort_finished[0][1] == BTStatus.FAILURE, "S4 aborted task still reports task_finished(FAILURE) for compatibility")
	_finish(r)

	# ---- L1: BTSubTree caches failed loads and warns once ----
	var fx_missing_st := BTSubTree.new("res://nonexistent_subtree_path_xyz.json")
	var fx_st_tree := BTTree.new()
	fx_st_tree.set_root(fx_missing_st)
	r = _runner(fx_st_tree)
	var st_statuses: Array[int] = []
	for _i in range(3):
		r.start()
		st_statuses.append(r.tick(0.1))
	_check(st_statuses == [BTStatus.FAILURE, BTStatus.FAILURE, BTStatus.FAILURE], "L1 missing subtree returns FAILURE across 3 start/tick cycles")
	_check(fx_missing_st._load_failure_warned == true, "L1 load failure warned flag is set")
	_check(fx_missing_st._loaded_path != "", "L1 failed load caches loaded path")
	_finish(r)

	# ---- L8: stop() clears _ticking backstop ----
	var fx_l8_leaf := Probe.new()
	fx_l8_leaf.results = [BTStatus.SUCCESS]
	var fx_l8_tree := BTTree.new(); fx_l8_tree.set_root(fx_l8_leaf)
	r = _runner(fx_l8_tree)
	r.start()
	r._ticking = true
	r.stop()
	r.start()
	var fx_l8_status := r.tick(0.1)
	_check(fx_l8_leaf.calls == 1 and fx_l8_status == BTStatus.SUCCESS, "L8 stop() resets _ticking backstop so wedged runner can tick again")
	_finish(r)

	print("Runtime regression suite: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
