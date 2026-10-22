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

	print("Runtime regression suite: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
