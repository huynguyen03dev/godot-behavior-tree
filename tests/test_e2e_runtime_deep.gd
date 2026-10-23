extends SceneTree

# -----------------------------------------------------------------------------
# Deep Runtime E2E Suite for Godot Behavior Tree (Rust GDExtension)
# -----------------------------------------------------------------------------

var checks := 0
var failures := 0
var failure_details: Array[Dictionary] = []

func _check(condition: bool, description: String, expected = null, actual = null) -> void:
	checks += 1
	if not condition:
		failures += 1
		var msg := "FAIL [%d]: %s" % [checks, description]
		if expected != null or actual != null:
			msg += "\n      Expected: %s\n      Actual:   %s" % [str(expected), str(actual)]
		print(msg)
		failure_details.append({
			"check": checks,
			"description": description,
			"expected": expected,
			"actual": actual
		})

# -----------------------------------------------------------------------------
# Test Helper Tasks
# -----------------------------------------------------------------------------

class DeepProbe extends BTTask:
	var results: Array[int] = [BTStatus.RUNNING]
	var calls := 0
	var starts := 0
	var awakes := 0
	var resets := 0
	var ends := 0
	var aborts := 0
	var pauses: Array[bool] = []
	var events: Array[Dictionary] = []
	var condition := false

	# Re-entrancy hooks
	var on_start_action: Callable
	var on_update_action: Callable
	var on_end_action: Callable
	var on_abort_action: Callable

	func on_awake() -> void:
		awakes += 1

	func on_reset() -> void:
		resets += 1
		super.on_reset()

	func on_start() -> void:
		starts += 1
		if on_start_action.is_valid():
			on_start_action.call()

	func on_update() -> int:
		calls += 1
		if on_update_action.is_valid():
			on_update_action.call()
		if results.is_empty():
			return BTStatus.SUCCESS
		return results[min(calls - 1, results.size() - 1)]

	func on_end() -> void:
		ends += 1
		if on_end_action.is_valid():
			on_end_action.call()

	func on_abort() -> void:
		aborts += 1
		if on_abort_action.is_valid():
			on_abort_action.call()
		super.on_abort()

	func on_pause(paused: bool) -> void:
		pauses.append(paused)

	func on_event(event_name: String, data = null) -> void:
		events.append({"name": event_name, "data": data})

	func evaluate_condition(_runner: BTRunner) -> int:
		calls += 1
		return BTStatus.SUCCESS if condition else BTStatus.FAILURE

class DeepCondition extends DeepProbe:
	func _init() -> void:
		category = "Condition"
	func on_update() -> int:
		calls += 1
		return BTStatus.SUCCESS if condition else BTStatus.FAILURE

class OrderedRandomSeq extends BTComposite.BTRandomSequence:
	func get_execution_order_index(child_index: int) -> int:
		return 1 if child_index == 0 else 0

class OrderedRandomSel extends BTComposite.BTRandomSelector:
	func get_execution_order_index(child_index: int) -> int:
		return 1 if child_index == 0 else 0

func _tree(root: BTTask, children: Array = []) -> BTTree:
	var t := BTTree.new()
	t.set_root(root)
	for c in children:
		if c is BTTask:
			t.connect_parent_child(root, c)
	return t

func _runner(tree: BTTree) -> BTRunner:
	return BTRunner.new(tree)

func _finish(r: BTRunner) -> void:
	if r != null:
		r.stop()
		r.free()

# -----------------------------------------------------------------------------
# Main Test Execution
# -----------------------------------------------------------------------------

func _init() -> void:
	print("Starting Deep Runtime E2E Suite...")
	_test_group1_reentrancy()
	_test_group2_signals()
	_test_group3_conditional_abort()
	_test_group4_budget()
	_test_group5_runner_controls()
	_test_group6_parallel()
	_test_group7_decorators()
	_test_group8_subtree()
	_test_group9_lifecycle()

	print("Runtime deep E2E: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

# -----------------------------------------------------------------------------
# Group 1: Re-entrancy
# -----------------------------------------------------------------------------
func _test_group1_reentrancy() -> void:
	# 1.1 task calls owner.stop() from on_start
	var p1 := DeepProbe.new()
	var r1 := _runner(_tree(p1))
	p1.on_start_action = func(): r1.stop()
	r1.start()
	r1.tick(0.1)
	_check(not r1.is_running and p1.starts == 1 and p1.calls == 0 and p1.ends == 1,
		"1.1 task calling owner.stop() in on_start unwinds cleanly without on_update",
		{"running": false, "starts": 1, "calls": 0, "ends": 1},
		{"running": r1.is_running, "starts": p1.starts, "calls": p1.calls, "ends": p1.ends})
	_finish(r1)

	# 1.2 task calls owner.stop() from on_update
	var p2 := DeepProbe.new()
	var r2 := _runner(_tree(p2))
	p2.on_update_action = func(): r2.stop()
	r2.start()
	var s2 := r2.tick(0.1)
	_check(not r2.is_running and p2.calls == 1 and p2.ends == 1,
		"1.2 task calling owner.stop() in on_update unwinds cleanly",
		{"running": false, "calls": 1, "ends": 1},
		{"running": r2.is_running, "calls": p2.calls, "ends": p2.ends})
	_finish(r2)

	# 1.3 task calls owner.stop() from on_end
	var p3 := DeepProbe.new()
	p3.results = [BTStatus.SUCCESS]
	var r3 := _runner(_tree(p3))
	var stop_called_in_end := [0]
	p3.on_end_action = func():
		stop_called_in_end[0] += 1
		r3.stop()
	r3.start()
	r3.tick(0.1)
	_check(not r3.is_running and stop_called_in_end[0] == 1 and p3.ends == 1,
		"1.3 task calling owner.stop() in on_end does not recurse infinitely",
		{"ends": 1, "stop_calls": 1},
		{"ends": p3.ends, "stop_calls": stop_called_in_end[0]})
	_finish(r3)

	# 1.4 task calls owner.tick() from on_update (nested tick)
	var p4 := DeepProbe.new()
	var r4 := _runner(_tree(p4))
	var nested_tick_result := [-999]
	p4.on_update_action = func():
		if p4.calls == 1:
			nested_tick_result[0] = r4.tick(0.1)
	r4.start()
	var top_tick_s := r4.tick(0.1)
	_check(p4.calls == 1 and nested_tick_result[0] == BTStatus.INACTIVE,
		"1.4 nested owner.tick() is rejected and returns last_status",
		{"calls": 1, "nested_result": BTStatus.INACTIVE},
		{"calls": p4.calls, "nested_result": nested_tick_result[0]})
	_finish(r4)

	# 1.5 task calls owner.interrupt(self) from on_start
	var p5 := DeepProbe.new()
	var r5 := _runner(_tree(p5))
	p5.on_start_action = func(): r5.interrupt(p5, BTStatus.FAILURE)
	r5.start()
	var s5 := r5.tick(0.1)
	_check(not r5.is_running and p5.starts == 1 and p5.aborts == 1 and p5.calls == 0,
		"1.5 owner.interrupt(self) in on_start aborts branch before on_update",
		{"running": false, "starts": 1, "aborts": 1, "calls": 0},
		{"running": r5.is_running, "starts": p5.starts, "aborts": p5.aborts, "calls": p5.calls})
	_finish(r5)

	# 1.6 task calls owner.pause(true) from on_update
	var p6 := DeepProbe.new()
	var r6 := _runner(_tree(p6))
	p6.on_update_action = func(): r6.pause(true)
	r6.start()
	r6.tick(0.1)
	_check(not r6.is_running and p6.pauses.has(true),
		"1.6 task calling owner.pause(true) in on_update sets runner paused",
		{"is_running": false, "on_pause_called": true},
		{"is_running": r6.is_running, "on_pause_called": p6.pauses.has(true)})
	_finish(r6)

	# 1.7 task calls owner.set_tree() from on_update
	var p7_old := DeepProbe.new()
	var p7_new := DeepProbe.new()
	p7_new.results = [BTStatus.SUCCESS]
	var tree_new := _tree(p7_new)
	var r7 := _runner(_tree(p7_old))
	p7_old.on_update_action = func(): r7.set_tree(tree_new)
	r7.start()
	var s7 := r7.tick(0.1)
	_check(not r7.is_running and p7_old.ends == 1 and r7.tree == tree_new,
		"1.7 task calling owner.set_tree() in on_update cleanly stops old tree and assigns new",
		{"running": false, "old_ends": 1, "new_tree": true},
		{"running": r7.is_running, "old_ends": p7_old.ends, "new_tree": r7.tree == tree_new})
	_finish(r7)

# -----------------------------------------------------------------------------
# Group 2: Signals
# -----------------------------------------------------------------------------
func _test_group2_signals() -> void:
	# 2.1 Full run completion signal count & sequence
	var seq21 := BTComposite.BTSequence.new()
	var c1 := DeepProbe.new()
	c1.results = [BTStatus.SUCCESS]
	var c2 := DeepProbe.new()
	c2.results = [BTStatus.SUCCESS]
	var t21 := BTTree.new()
	t21.set_root(seq21)
	t21.connect_parent_child(seq21, c1)
	t21.connect_parent_child(seq21, c2)
	var r21 := _runner(t21)

	var signal_log: Array[String] = []
	r21.task_started.connect(func(task): signal_log.append("start:" + task.type_name))
	r21.task_finished.connect(func(task, status): signal_log.append("finish:" + task.type_name + ":" + str(status)))
	r21.task_aborted.connect(func(task): signal_log.append("abort:" + task.type_name))
	r21.tree_finished.connect(func(status): signal_log.append("tree_finish:" + str(status)))

	r21.start()
	r21.tick(0.1)

	# Expected: start Sequence, start c1, finish c1 (SUCCESS=2), start c2, finish c2 (SUCCESS=2), finish Sequence (SUCCESS=2), tree_finish (SUCCESS=2)
	var expected_signals := [
		"start:Sequence",
		"start:BTTask",
		"finish:BTTask:2",
		"start:BTTask",
		"finish:BTTask:2",
		"finish:Sequence:2",
		"tree_finish:2"
	]
	_check(signal_log == expected_signals,
		"2.1 Sequence completion emits started/finished in exact parent->child order",
		expected_signals, signal_log)
	_finish(r21)

	# 2.2 Abort signals on sibling failure (Parallel)
	var par22 := BTComposite.BTParallel.new()
	var p22_run := DeepProbe.new()
	var p22_fail := DeepProbe.new()
	p22_fail.results = [BTStatus.FAILURE]
	var t22 := BTTree.new()
	t22.set_root(par22)
	t22.connect_parent_child(par22, p22_run)
	t22.connect_parent_child(par22, p22_fail)
	var r22 := _runner(t22)

	var aborted_tasks: Array[BTTask] = []
	var finished_tasks: Array[BTTask] = []
	r22.task_aborted.connect(func(task): aborted_tasks.append(task))
	r22.task_finished.connect(func(task, _s): finished_tasks.append(task))

	r22.start()
	r22.tick(0.1)

	_check(aborted_tasks.size() == 1 and aborted_tasks[0] == p22_run,
		"2.2 Parallel failure aborts running sibling with task_aborted",
		[p22_run], aborted_tasks)
	_check(p22_run.aborts == 1,
		"2.2 Aborted sibling receives on_abort hook",
		1, p22_run.aborts)
	_finish(r22)

	# 2.3 Stop mid-run emits task_finished with current status, NO tree_finished
	var p23 := DeepProbe.new()
	p23.results = [BTStatus.RUNNING]
	var r23 := _runner(_tree(p23))
	var tree_fin_count := [0]
	var task_fin_count := [0]
	r23.tree_finished.connect(func(_s): tree_fin_count[0] += 1)
	r23.task_finished.connect(func(_t, _s): task_fin_count[0] += 1)
	r23.start()
	r23.tick(0.1)
	r23.stop()
	_check(tree_fin_count[0] == 0 and task_fin_count[0] == 1,
		"2.3 stop() emits task_finished for running tasks but NOT tree_finished",
		{"tree_finished": 0, "task_finished": 1},
		{"tree_finished": tree_fin_count[0], "task_finished": task_fin_count[0]})
	_finish(r23)

	# 2.4 Restarting runner resets signals cleanly without double start emissions
	var p24 := DeepProbe.new()
	p24.results = [BTStatus.RUNNING]
	var r24 := _runner(_tree(p24))
	var start_count := [0]
	r24.task_started.connect(func(_t): start_count[0] += 1)
	r24.start()
	r24.tick(0.1)
	r24.tick(0.1) # second tick while still running should NOT emit task_started
	_check(start_count[0] == 1,
		"2.4 Consecutive ticks while RUNNING do not re-emit task_started",
		1, start_count[0])
	r24.stop()
	r24.start()
	r24.tick(0.1)
	_check(start_count[0] == 2,
		"2.4 After stop and restart, task_started emits exactly once again",
		2, start_count[0])
	_finish(r24)

# -----------------------------------------------------------------------------
# Group 3: Conditional Abort
# -----------------------------------------------------------------------------
func _test_group3_conditional_abort() -> void:
	# 3.1 Selector LOWER_PRIORITY with guard flipping from false to true between ticks
	var sel31 := BTComposite.BTSelector.new()
	sel31.set_abort_type(BTComposite.AbortType.LOWER_PRIORITY)
	var seq_hi := BTComposite.BTSequence.new()
	var cond_hi := DeepCondition.new()
	cond_hi.condition = false
	var act_hi := DeepProbe.new()
	seq_hi.add_child_task(cond_hi)
	seq_hi.add_child_task(act_hi)
	var act_lo := DeepProbe.new()

	var t31 := BTTree.new()
	t31.set_root(sel31)
	t31.connect_parent_child(sel31, seq_hi)
	t31.connect_parent_child(sel31, act_lo)

	var r31 := _runner(t31)
	r31.start()
	var s_tick1 := r31.tick(0.1) # act_lo starts and runs
	_check(act_lo.calls == 1 and act_lo.aborts == 0 and act_hi.calls == 0,
		"3.1 Selector tick 1 runs low-priority action when high guard is false",
		{"lo_calls": 1, "hi_calls": 0},
		{"lo_calls": act_lo.calls, "hi_calls": act_hi.calls})

	cond_hi.condition = true
	var s_tick2 := r31.tick(0.1) # high guard succeeds, act_lo aborted, act_hi starts
	_check(act_lo.aborts == 1 and act_hi.calls == 1,
		"3.1 Selector LOWER_PRIORITY aborts low action and switches to high sequence",
		{"lo_aborts": 1, "hi_calls": 1},
		{"lo_aborts": act_lo.aborts, "hi_calls": act_hi.calls})
	_finish(r31)

	# 3.2 Sequence SELF abort when guard flips from true to false
	var seq32 := BTComposite.BTSequence.new()
	seq32.set_abort_type(BTComposite.AbortType.SELF)
	var cond32 := DeepCondition.new()
	cond32.condition = true
	var act32 := DeepProbe.new()
	seq32.add_child_task(cond32)
	seq32.add_child_task(act32)

	var t32 := BTTree.new()
	t32.set_root(seq32)
	t32.connect_parent_child(seq32, cond32)
	t32.connect_parent_child(seq32, act32)

	var r32 := _runner(t32)
	r32.start()
	r32.tick(0.1)
	_check(act32.calls == 1 and act32.aborts == 0,
		"3.2 Sequence SELF runs action when guard is initially true",
		{"calls": 1, "aborts": 0},
		{"calls": act32.calls, "aborts": act32.aborts})

	cond32.condition = false
	var s32_2 := r32.tick(0.1)
	_check(s32_2 == BTStatus.FAILURE and act32.aborts == 1 and not r32.is_running,
		"3.2 Sequence SELF aborts active action and fails when guard flips to false",
		{"status": BTStatus.FAILURE, "aborts": 1, "running": false},
		{"status": s32_2, "aborts": act32.aborts, "running": r32.is_running})
	_finish(r32)

	# 3.3 Guard wrapped in Inverter inside Selector LOWER_PRIORITY
	var sel33 := BTComposite.BTSelector.new()
	sel33.set_abort_type(BTComposite.AbortType.LOWER_PRIORITY)
	var seq33 := BTComposite.BTSequence.new()
	var inv33 := BTDecorator.BTInverter.new()
	var cond33 := DeepCondition.new()
	cond33.condition = true # Inverter produces FAILURE initially
	inv33.add_child_task(cond33)
	var act33_hi := DeepProbe.new()
	seq33.add_child_task(inv33)
	seq33.add_child_task(act33_hi)
	var act33_lo := DeepProbe.new()

	var t33 := BTTree.new()
	t33.set_root(sel33)
	t33.connect_parent_child(sel33, seq33)
	t33.connect_parent_child(sel33, act33_lo)

	var r33 := _runner(t33)
	r33.start()
	r33.tick(0.1) # lo runs
	_check(act33_lo.calls == 1 and act33_hi.calls == 0,
		"3.3 Inverter guard starts low branch when condition is true (inverted to failure)",
		{"lo_calls": 1, "hi_calls": 0},
		{"lo_calls": act33_lo.calls, "hi_calls": act33_hi.calls})

	cond33.condition = false # Inverter now produces SUCCESS
	r33.tick(0.1)
	_check(act33_lo.aborts == 1 and act33_hi.calls == 1,
		"3.3 Inverter guard preempts low action when condition becomes false (inverted to success)",
		{"lo_aborts": 1, "hi_calls": 1},
		{"lo_aborts": act33_lo.aborts, "hi_calls": act33_hi.calls})
	_finish(r33)

	# 3.4 Guard wrapped in ReturnSuccess inside Sequence SELF
	# ReturnSuccess should ALWAYS evaluate to SUCCESS, so Sequence SELF should NEVER abort!
	var seq34 := BTComposite.BTSequence.new()
	seq34.set_abort_type(BTComposite.AbortType.SELF)
	var ret_succ := BTDecorator.BTReturnSuccess.new()
	var cond34 := DeepCondition.new()
	cond34.condition = false
	ret_succ.add_child_task(cond34)
	var act34 := DeepProbe.new()
	seq34.add_child_task(ret_succ)
	seq34.add_child_task(act34)

	var t34 := BTTree.new()
	t34.set_root(seq34)
	t34.connect_parent_child(seq34, ret_succ)
	t34.connect_parent_child(seq34, act34)

	var r34 := _runner(t34)
	r34.start()
	r34.tick(0.1)
	_check(act34.calls == 1, "3.4 ReturnSuccess allows Sequence to reach action", 1, act34.calls)
	cond34.condition = false
	var s34 := r34.tick(0.1)
	_check(s34 == BTStatus.RUNNING and act34.aborts == 0 and act34.calls == 2,
		"3.4 ReturnSuccess guard never aborts Sequence even when underlying condition fails",
		{"status": BTStatus.RUNNING, "aborts": 0, "calls": 2},
		{"status": s34, "aborts": act34.aborts, "calls": act34.calls})
	_finish(r34)

	# 3.5 Nested composite guard: Sequence with multiple conditions inside Selector
	var sel35 := BTComposite.BTSelector.new()
	sel35.set_abort_type(BTComposite.AbortType.LOWER_PRIORITY)
	var hi_seq35 := BTComposite.BTSequence.new()
	var cond35_a := DeepCondition.new()
	cond35_a.condition = true
	var cond35_b := DeepCondition.new()
	cond35_b.condition = false
	var act35_hi := DeepProbe.new()
	hi_seq35.add_child_task(cond35_a)
	hi_seq35.add_child_task(cond35_b)
	hi_seq35.add_child_task(act35_hi)
	var act35_lo := DeepProbe.new()

	var t35 := BTTree.new()
	t35.set_root(sel35)
	t35.connect_parent_child(sel35, hi_seq35)
	t35.connect_parent_child(sel35, act35_lo)

	var r35 := _runner(t35)
	r35.start()
	r35.tick(0.1)
	_check(act35_lo.calls == 1 and act35_hi.calls == 0,
		"3.5 Multiple conditions: high sequence blocked when cond_b is false",
		{"lo_calls": 1, "hi_calls": 0},
		{"lo_calls": act35_lo.calls, "hi_calls": act35_hi.calls})

	cond35_b.condition = true
	r35.tick(0.1)
	_check(act35_lo.aborts == 1 and act35_hi.calls == 1,
		"3.5 High sequence with multiple conditions triggers abort when all conditions become true",
		{"lo_aborts": 1, "hi_calls": 1},
		{"lo_aborts": act35_lo.aborts, "hi_calls": act35_hi.calls})
	_finish(r35)

# -----------------------------------------------------------------------------
# Group 4: Budget
# -----------------------------------------------------------------------------
func _test_group4_budget() -> void:
	# 4.1 max_task_executions_per_tick = 1 on Sequence with 3 leaves
	var seq41 := BTComposite.BTSequence.new()
	var l1 := DeepProbe.new(); l1.results = [BTStatus.SUCCESS]
	var l2 := DeepProbe.new(); l2.results = [BTStatus.SUCCESS]
	var l3 := DeepProbe.new(); l3.results = [BTStatus.SUCCESS]
	var t41 := _tree(seq41, [l1, l2, l3])
	var r41 := _runner(t41)
	r41.max_task_executions_per_tick = 1
	r41.start()

	# Tick 1: only l1 executes
	var s_t1 := r41.tick(0.1)
	_check(s_t1 == BTStatus.RUNNING and l1.calls == 1 and l2.calls == 0 and r41.task_executions == 1,
		"4.1 Budget 1: tick 1 executes only leaf 1",
		{"status": BTStatus.RUNNING, "l1": 1, "l2": 0, "executions": 1},
		{"status": s_t1, "l1": l1.calls, "l2": l2.calls, "executions": r41.task_executions})

	# Tick 2: only l2 executes
	var s_t2 := r41.tick(0.1)
	_check(s_t2 == BTStatus.RUNNING and l2.calls == 1 and l3.calls == 0 and r41.task_executions == 1,
		"4.1 Budget 1: tick 2 executes only leaf 2 and resets task_executions",
		{"status": BTStatus.RUNNING, "l2": 1, "l3": 0, "executions": 1},
		{"status": s_t2, "l2": l2.calls, "l3": l3.calls, "executions": r41.task_executions})

	# Tick 3: l3 executes, sequence completes
	var s_t3 := r41.tick(0.1)
	_check(s_t3 == BTStatus.SUCCESS and l3.calls == 1 and r41.task_executions == 1,
		"4.1 Budget 1: tick 3 executes leaf 3 and completes tree",
		{"status": BTStatus.SUCCESS, "l3": 1, "executions": 1},
		{"status": s_t3, "l3": l3.calls, "executions": r41.task_executions})
	_finish(r41)

	# 4.2 max_task_executions_per_tick = 2 on Sequence with 5 leaves
	var seq42 := BTComposite.BTSequence.new()
	var leaves42: Array[DeepProbe] = []
	for i in 5:
		var p := DeepProbe.new()
		p.results = [BTStatus.SUCCESS]
		leaves42.append(p)
	var t42 := _tree(seq42, leaves42)
	var r42 := _runner(t42)
	r42.max_task_executions_per_tick = 2
	r42.start()

	r42.tick(0.1) # executes 2
	_check(r42.task_executions == 2 and leaves42[0].calls == 1 and leaves42[1].calls == 1 and leaves42[2].calls == 0,
		"4.2 Budget 2: tick 1 runs exactly 2 tasks",
		{"exec": 2, "l0": 1, "l1": 1, "l2": 0},
		{"exec": r42.task_executions, "l0": leaves42[0].calls, "l1": leaves42[1].calls, "l2": leaves42[2].calls})

	r42.tick(0.1) # executes 2
	_check(r42.task_executions == 2 and leaves42[2].calls == 1 and leaves42[3].calls == 1 and leaves42[4].calls == 0,
		"4.2 Budget 2: tick 2 runs exactly next 2 tasks",
		{"exec": 2, "l2": 1, "l3": 1, "l4": 0},
		{"exec": r42.task_executions, "l2": leaves42[2].calls, "l3": leaves42[3].calls, "l4": leaves42[4].calls})

	r42.tick(0.1) # executes 1
	_check(r42.task_executions == 1 and leaves42[4].calls == 1 and not r42.is_running,
		"4.2 Budget 2: tick 3 runs final task and finishes",
		{"exec": 1, "l4": 1, "running": false},
		{"exec": r42.task_executions, "l4": leaves42[4].calls, "running": r42.is_running})
	_finish(r42)

	# 4.3 SubTree shares budget with parent runner
	var reg_budget := BTTaskRegistry.new()
	var sub_b1 := DeepProbe.new(); sub_b1.results = [BTStatus.SUCCESS]
	var sub_b2 := DeepProbe.new(); sub_b2.results = [BTStatus.SUCCESS]
	reg_budget.register_task("SubB1", func(): return sub_b1, "Action")
	reg_budget.register_task("SubB2", func(): return sub_b2, "Action")

	var sub_json_path := "user://test_budget_share_sub.json"
	var sub_dict := {
		"root_id": 1,
		"nodes": [
			{"id": 1, "type_name": "Sequence", "children_ids": [2, 3], "parameters": {}},
			{"id": 2, "type_name": "SubB1", "children_ids": [], "parameters": {}},
			{"id": 3, "type_name": "SubB2", "children_ids": [], "parameters": {}}
		]
	}
	var f := FileAccess.open(sub_json_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(sub_dict))
	f.close()

	var parent_seq := BTComposite.BTSequence.new()
	var pre_leaf := DeepProbe.new()
	pre_leaf.results = [BTStatus.SUCCESS]
	var sub_task := BTSubTree.new(sub_json_path)
	var t_sub_share := _tree(parent_seq, [pre_leaf, sub_task])
	t_sub_share.registry = reg_budget
	var r_parent := _runner(t_sub_share)
	r_parent.max_task_executions_per_tick = 2
	r_parent.start()

	# Tick 1: pre_leaf (1) + sub_b1 (1) = 2 executions, budget exhausted
	var s_sub_t1 := r_parent.tick(0.1)
	_check(s_sub_t1 == BTStatus.RUNNING and r_parent.task_executions == 2 and pre_leaf.calls == 1 and sub_b1.calls == 1,
		"4.3 Shared budget: parent leaf + subtree leaf together consume tick budget",
		{"status": BTStatus.RUNNING, "exec": 2, "pre_leaf_calls": 1, "sub_b1_calls": 1},
		{"status": s_sub_t1, "exec": r_parent.task_executions, "pre_leaf_calls": pre_leaf.calls, "sub_b1_calls": sub_b1.calls})

	# Tick 2: sub_b2 (1) executes, finishing subtree and parent
	var s_sub_t2 := r_parent.tick(0.1)
	_check(s_sub_t2 == BTStatus.SUCCESS and r_parent.task_executions == 1 and sub_b2.calls == 1 and not r_parent.is_running,
		"4.3 Shared budget: next tick finishes remaining subtree task",
		{"status": BTStatus.SUCCESS, "exec": 1, "sub_b2_calls": 1, "running": false},
		{"status": s_sub_t2, "exec": r_parent.task_executions, "sub_b2_calls": sub_b2.calls, "running": r_parent.is_running})
	_finish(r_parent)

	if FileAccess.file_exists(sub_json_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(sub_json_path))

# -----------------------------------------------------------------------------
# Group 5: Runner Controls
# -----------------------------------------------------------------------------
func _test_group5_runner_controls() -> void:
	# 5.1 max_ticks stops runner after N ticks
	var p51 := DeepProbe.new()
	p51.results = [BTStatus.RUNNING]
	var r51 := _runner(_tree(p51))
	r51.max_ticks = 2
	r51.start()
	r51.tick(0.1) # tick 1
	_check(r51.is_running and r51.ticks == 1, "5.1 Runner running after tick 1 with max_ticks=2", true, r51.is_running)
	r51.tick(0.1) # tick 2
	_check(r51.is_running and r51.ticks == 2, "5.1 Runner running after tick 2 with max_ticks=2", true, r51.is_running)
	var s51_3 := r51.tick(0.1) # tick 3 hits max_ticks
	_check(not r51.is_running and r51.ticks == 2,
		"5.1 Runner stops on tick 3 when ticks >= max_ticks",
		{"running": false, "ticks": 2},
		{"running": r51.is_running, "ticks": r51.ticks})
	_finish(r51)

	# 5.2 pause/resume dispatches on_pause(true/false) to active tasks
	var p52 := DeepProbe.new()
	p52.results = [BTStatus.RUNNING]
	var r52 := _runner(_tree(p52))
	r52.start()
	r52.tick(0.1)
	r52.pause(true)
	_check(p52.pauses == [true] and not r52.is_running,
		"5.2 pause(true) notifies active task with on_pause(true)",
		[true], p52.pauses)

	# tick while paused should not advance time or tick task
	var calls_before := p52.calls
	var time_before := r52.time
	r52.tick(0.5)
	_check(p52.calls == calls_before and r52.time == time_before,
		"5.2 tick while paused is a no-op",
		{"calls": calls_before, "time": time_before},
		{"calls": p52.calls, "time": r52.time})

	r52.pause(false)
	_check(p52.pauses == [true, false] and r52.is_running,
		"5.2 pause(false) notifies active task with on_pause(false) and resumes",
		[true, false], p52.pauses)
	r52.tick(0.1)
	_check(p52.calls == calls_before + 1,
		"5.2 Ticking after resume continues execution",
		calls_before + 1, p52.calls)
	_finish(r52)

	# 5.3 send_event to running and non-running tasks in tree
	var seq53 := BTComposite.BTSequence.new()
	var act_run := DeepProbe.new(); act_run.results = [BTStatus.RUNNING]
	var act_idle := DeepProbe.new(); act_idle.results = [BTStatus.SUCCESS]
	var t53 := _tree(seq53, [act_run, act_idle])
	var r53 := _runner(t53)
	r53.start()
	r53.tick(0.1) # act_run is running, act_idle has not started
	r53.send_event("test_alert", 42)
	_check(act_run.events.size() == 1 and act_idle.events.size() == 1,
		"5.3 send_event broadcasts to both running and non-started tasks in tree",
		{"run_events": 1, "idle_events": 1},
		{"run_events": act_run.events.size(), "idle_events": act_idle.events.size()})
	_finish(r53)

	# 5.4 abort_running when runner is not started
	var p54 := DeepProbe.new()
	var r54 := _runner(_tree(p54))
	r54.abort_running() # should not crash or mark status failure
	_check(not r54.is_running and p54.aborts == 0 and r54.last_status == BTStatus.INACTIVE,
		"5.4 abort_running() on unstarted runner is safe no-op",
		{"running": false, "aborts": 0, "status": BTStatus.INACTIVE},
		{"running": r54.is_running, "aborts": p54.aborts, "status": r54.last_status})
	_finish(r54)

# -----------------------------------------------------------------------------
# Group 6: Parallel
# -----------------------------------------------------------------------------
func _test_group6_parallel() -> void:
	# 6.1 3 branches: branch 0 RUNNING, branch 1 RUNNING, branch 2 fails on tick 2
	var par61 := BTComposite.BTParallel.new()
	var b0 := DeepProbe.new(); b0.results = [BTStatus.RUNNING, BTStatus.RUNNING]
	var b1 := DeepProbe.new(); b1.results = [BTStatus.RUNNING, BTStatus.RUNNING]
	var b2 := DeepProbe.new(); b2.results = [BTStatus.RUNNING, BTStatus.FAILURE]
	var t61 := _tree(par61, [b0, b1, b2])
	var r61 := _runner(t61)
	r61.start()

	# Tick 1: all 3 start and return RUNNING
	var s61_1 := r61.tick(0.1)
	_check(s61_1 == BTStatus.RUNNING and b0.calls == 1 and b1.calls == 1 and b2.calls == 1,
		"6.1 Parallel tick 1: all 3 branches run concurrently",
		{"status": BTStatus.RUNNING, "b0": 1, "b1": 1, "b2": 1},
		{"status": s61_1, "b0": b0.calls, "b1": b1.calls, "b2": b2.calls})

	# Tick 2: b2 fails -> Parallel fails, b0 and b1 must be aborted
	var s61_2 := r61.tick(0.1)
	_check(s61_2 == BTStatus.FAILURE and not r61.is_running,
		"6.1 Parallel tick 2: branch 2 failure causes Parallel to fail and stop",
		{"status": BTStatus.FAILURE, "running": false},
		{"status": s61_2, "running": r61.is_running})
	_check(b0.aborts == 1 and b1.aborts == 1 and b2.aborts == 0,
		"6.1 Parallel failure aborts remaining active sibling branches but not the failed task",
		{"b0_aborts": 1, "b1_aborts": 1, "b2_aborts": 0},
		{"b0_aborts": b0.aborts, "b1_aborts": b1.aborts, "b2_aborts": b2.aborts})
	_finish(r61)

	# 6.2 RUNNING branch keeps Parallel RUNNING even if other branches succeed
	var par62 := BTComposite.BTParallel.new()
	var b62_succ := DeepProbe.new(); b62_succ.results = [BTStatus.SUCCESS]
	var b62_run := DeepProbe.new(); b62_run.results = [BTStatus.RUNNING]
	var t62 := _tree(par62, [b62_succ, b62_run])
	var r62 := _runner(t62)
	r62.start()
	var s62 := r62.tick(0.1)
	_check(s62 == BTStatus.RUNNING and r62.is_running,
		"6.2 Parallel stays RUNNING when one branch succeeds and another is RUNNING",
		BTStatus.RUNNING, s62)
	_finish(r62)

	# 6.3 Placeholder sibling in Parallel does not cause hang or abort
	var par63 := BTComposite.BTParallel.new()
	var b63_act := DeepProbe.new(); b63_act.results = [BTStatus.RUNNING, BTStatus.SUCCESS]
	var b63_ph: BTTask = BTTaskRegistry.BTUnknownTask.new("DummyPlaceholder")
	var t63 := _tree(par63, [b63_act, b63_ph])
	var r63 := _runner(t63)
	r63.start()
	var s63_1 := r63.tick(0.1)
	_check(s63_1 == BTStatus.RUNNING, "6.3 Parallel with placeholder runs active branch on tick 1", BTStatus.RUNNING, s63_1)
	var s63_2 := r63.tick(0.1)
	_check(s63_2 == BTStatus.SUCCESS, "6.3 Parallel with placeholder finishes successfully when active branch succeeds", BTStatus.SUCCESS, s63_2)
	_finish(r63)

# -----------------------------------------------------------------------------
# Group 7: Decorators
# -----------------------------------------------------------------------------
func _test_group7_decorators() -> void:
	# 7.1 Repeater count=3 with succeeding child across ticks
	var rep71 := BTDecorator.BTRepeater.new()
	rep71.count = 3
	var child71 := DeepProbe.new()
	child71.results = [BTStatus.SUCCESS]
	var t71 := _tree(rep71, [child71])
	var r71 := _runner(t71)
	r71.start()

	# Tick 1
	var s71_1 := r71.tick(0.1)
	_check(s71_1 == BTStatus.RUNNING and child71.calls == 1,
		"7.1 Repeater count=3 yields after iteration 1",
		{"status": BTStatus.RUNNING, "calls": 1},
		{"status": s71_1, "calls": child71.calls})
	# Tick 2
	var s71_2 := r71.tick(0.1)
	_check(s71_2 == BTStatus.RUNNING and child71.calls == 2,
		"7.1 Repeater count=3 yields after iteration 2",
		{"status": BTStatus.RUNNING, "calls": 2},
		{"status": s71_2, "calls": child71.calls})
	# Tick 3
	var s71_3 := r71.tick(0.1)
	_check(s71_3 == BTStatus.SUCCESS and child71.calls == 3 and not r71.is_running,
		"7.1 Repeater count=3 completes with SUCCESS after iteration 3",
		{"status": BTStatus.SUCCESS, "calls": 3, "running": false},
		{"status": s71_3, "calls": child71.calls, "running": r71.is_running})
	_finish(r71)

	# 7.2 Repeater end_on_failure = true terminates early on failure
	var rep72 := BTDecorator.BTRepeater.new()
	rep72.count = 5
	rep72.end_on_failure = true
	var child72 := DeepProbe.new()
	child72.results = [BTStatus.SUCCESS, BTStatus.FAILURE]
	var t72 := _tree(rep72, [child72])
	var r72 := _runner(t72)
	r72.start()
	r72.tick(0.1) # iter 1: success
	var s72 := r72.tick(0.1) # iter 2: failure
	_check(s72 == BTStatus.FAILURE and child72.calls == 2 and not r72.is_running,
		"7.2 Repeater end_on_failure terminates immediately on child failure",
		{"status": BTStatus.FAILURE, "calls": 2, "running": false},
		{"status": s72, "calls": child72.calls, "running": r72.is_running})
	_finish(r72)

	# 7.3 UntilSuccess with child failing continuously does NOT freeze in one tick
	var us73 := BTDecorator.BTUntilSuccess.new()
	var child73 := DeepProbe.new()
	child73.results = [BTStatus.FAILURE, BTStatus.FAILURE, BTStatus.SUCCESS]
	var t73 := _tree(us73, [child73])
	var r73 := _runner(t73)
	r73.start()
	var s73_1 := r73.tick(0.1)
	_check(s73_1 == BTStatus.RUNNING and child73.calls == 1,
		"7.3 UntilSuccess yields to next tick when child fails",
		{"status": BTStatus.RUNNING, "calls": 1},
		{"status": s73_1, "calls": child73.calls})
	var s73_2 := r73.tick(0.1)
	_check(s73_2 == BTStatus.RUNNING and child73.calls == 2,
		"7.3 UntilSuccess yields again on second failure",
		{"status": BTStatus.RUNNING, "calls": 2},
		{"status": s73_2, "calls": child73.calls})
	var s73_3 := r73.tick(0.1)
	_check(s73_3 == BTStatus.SUCCESS and child73.calls == 3 and not r73.is_running,
		"7.3 UntilSuccess completes with SUCCESS when child finally succeeds",
		{"status": BTStatus.SUCCESS, "calls": 3},
		{"status": s73_3, "calls": child73.calls})
	_finish(r73)

	# 7.4 Cooldown resets last_execution_time when simulated time rewinds
	var cd74 := BTDecorator.BTCooldown.new()
	cd74.cooldown_time = 10.0
	var child74 := DeepProbe.new()
	child74.results = [BTStatus.SUCCESS]
	var t74 := _tree(cd74, [child74])
	var r74 := _runner(t74)
	r74.start()
	r74.tick(15.0) # executed at time=15.0
	_check(child74.calls == 1, "7.4 Cooldown executes first time", 1, child74.calls)

	# Rewind time to 0.0 and call on_reset
	r74.time = 0.0
	cd74.on_reset()
	r74.start()
	var s74_reset := r74.tick(0.0)
	_check(s74_reset == BTStatus.SUCCESS,
		"7.4 Cooldown on_reset clears cooldown state when time is rewound",
		BTStatus.SUCCESS, s74_reset)

	r74.start()
	r74.tick(1.0)
	_check(child74.calls >= 2,
		"7.4 Cooldown executes again after reset and time rewind",
		true, child74.calls >= 2)
	_finish(r74)

	# 7.5 TimeLimit aborts running child when time limit exceeded
	var tl75 := BTDecorator.BTTimeLimit.new()
	tl75.time_limit = 0.5
	var child75 := DeepProbe.new()
	child75.results = [BTStatus.RUNNING]
	var t75 := _tree(tl75, [child75])
	var r75 := _runner(t75)
	r75.start()
	r75.tick(0.0) # start_time recorded at time=0.0
	r75.tick(0.2) # elapsed 0.2 < 0.5
	_check(r75.is_running and child75.aborts == 0, "7.5 TimeLimit stays running before limit", true, r75.is_running)
	var s75 := r75.tick(0.4) # elapsed 0.6 >= 0.5
	_check(s75 == BTStatus.FAILURE and not r75.is_running and child75.aborts == 1,
		"7.5 TimeLimit aborts child and fails once delta exceeds limit",
		{"status": BTStatus.FAILURE, "running": false, "aborts": 1},
		{"status": s75, "running": r75.is_running, "aborts": child75.aborts})
	_finish(r75)

	# 7.6 Nested Decorator: Inverter inside Repeater
	var rep76 := BTDecorator.BTRepeater.new()
	rep76.count = 2
	rep76.end_on_failure = true
	var inv76 := BTDecorator.BTInverter.new()
	var child76 := DeepProbe.new()
	child76.results = [BTStatus.FAILURE] # Inverter turns this to SUCCESS!
	var t76 := BTTree.new()
	t76.set_root(rep76)
	t76.connect_parent_child(rep76, inv76)
	t76.connect_parent_child(inv76, child76)
	var r76 := _runner(t76)
	r76.start()
	r76.tick(0.1) # iter 1: child fails -> inverter succeeds -> repeater continues
	var s76 := r76.tick(0.1) # iter 2: child fails -> inverter succeeds -> repeater completes count 2
	_check(s76 == BTStatus.SUCCESS and child76.calls == 2 and not r76.is_running,
		"7.6 Inverter inside Repeater: inverted failure allows repeater to complete successfully",
		{"status": BTStatus.SUCCESS, "calls": 2},
		{"status": s76, "calls": child76.calls})
	_finish(r76)

# -----------------------------------------------------------------------------
# Group 8: SubTree
# -----------------------------------------------------------------------------
func _test_group8_subtree() -> void:
	# 8.1 Non-existent subtree file returns FAILURE without crashing
	var sub_missing := BTSubTree.new("res://non_existent_file_987654.json")
	var r81 := _runner(_tree(sub_missing))
	r81.start()
	var s81 := r81.tick(0.1)
	_check(s81 == BTStatus.FAILURE and not r81.is_running,
		"8.1 Non-existent subtree path returns FAILURE without crashing",
		{"status": BTStatus.FAILURE, "running": false},
		{"status": s81, "running": r81.is_running})
	_finish(r81)

	# 8.2 JSON file loading, shared vs private blackboard scoping
	var sub_path := "user://test_deep_sub_bb.json"
	var sub_data := {
		"root_id": 1,
		"nodes": [
			{"id": 1, "type_name": "Task", "children_ids": [], "parameters": {}}
		],
		"blackboard": {
			"shared_var": {"type_name": "int", "value": 100, "is_shared": true},
			"private_var": {"type_name": "int", "value": 200, "is_shared": false}
		}
	}
	var f := FileAccess.open(sub_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(sub_data))
	f.close()

	var sub_node := BTSubTree.new(sub_path)
	var parent_tree := BTTree.new()
	var parent_bb := BTBlackboard.new()
	parent_bb.set_var("parent_val", 999, "int")
	parent_tree.blackboard = parent_bb
	parent_tree.set_root(sub_node)

	var r82 := _runner(parent_tree)
	r82.start()
	var s82 := r82.tick(0.1)

	_check(parent_bb.has_var("shared_var") and parent_bb.get_var("shared_var") == 100,
		"8.2 SubTree shared variable is promoted to parent blackboard",
		true, parent_bb.has_var("shared_var") and parent_bb.get_var("shared_var") == 100)
	_check(not parent_bb.has_var("private_var"),
		"8.2 SubTree private variable is NOT visible in parent blackboard",
		false, parent_bb.has_var("private_var"))

	# Check subtree execution preserves valid tree_path
	_check(sub_node.tree_path == sub_path, "8.2 SubTree tree_path configured and accessible", true, sub_node.tree_path == sub_path)

	_finish(r82)

	# 8.3 Restarting subtree runner multiple times (blackboard re-seeded & caching)
	r82 = _runner(parent_tree)
	r82.start()
	r82.tick(0.1)
	_check(r82.is_running == false, "8.3 SubTree runs and completes on repeated start", false, r82.is_running)
	_finish(r82)

	# 8.4 Freeing subtree task releases its resources
	var sub_to_free := BTSubTree.new(sub_path)
	var t_free := _tree(sub_to_free)
	var r_free := _runner(t_free)
	r_free.start()
	r_free.tick(0.1)
	var weak_sub_task: WeakRef = weakref(sub_to_free)
	_finish(r_free)
	t_free = null
	sub_to_free = null
	_check(weak_sub_task.get_ref() == null,
		"8.4 Releasing subtree task cleans up properly",
		true, weak_sub_task.get_ref() == null)

	# 8.5 Recursive subtree path detection
	var rec_path := "user://test_deep_recursive_sub.json"
	var rec_data := {
		"root_id": 1,
		"nodes": [
			{"id": 1, "type_name": "SubTree", "children_ids": [], "parameters": {"tree_path": rec_path}}
		]
	}
	f = FileAccess.open(rec_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(rec_data))
	f.close()

	var rec_sub := BTSubTree.new(rec_path)
	var r85 := _runner(_tree(rec_sub))
	r85.start()
	var s85 := r85.tick(0.1)
	_check(s85 == BTStatus.FAILURE and not r85.is_running,
		"8.5 Recursive subtree loop is detected and fails safely without infinite recursion",
		{"status": BTStatus.FAILURE, "running": false},
		{"status": s85, "running": r85.is_running})
	_finish(r85)

	# Cleanup test JSON files
	if FileAccess.file_exists(sub_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(sub_path))
	if FileAccess.file_exists(rec_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(rec_path))

# -----------------------------------------------------------------------------
# Group 9: Lifecycle
# -----------------------------------------------------------------------------
func _test_group9_lifecycle() -> void:
	# 9.1 on_awake called exactly once per start()
	var p91 := DeepProbe.new()
	var r91 := _runner(_tree(p91))
	_check(p91.awakes == 0, "9.1 on_awake not called before start", 0, p91.awakes)
	r91.start()
	_check(p91.awakes == 1, "9.1 on_awake called on first start", 1, p91.awakes)
	r91.stop()
	r91.start()
	_check(p91.awakes == 2, "9.1 on_awake called on second start", 2, p91.awakes)
	_finish(r91)

	# 9.2 on_reset is called recursively down the tree on start()
	var seq92 := BTComposite.BTSequence.new()
	var ch92_1 := DeepProbe.new()
	var ch92_2 := DeepProbe.new()
	var t92 := _tree(seq92, [ch92_1, ch92_2])
	var r92 := _runner(t92)
	_check(ch92_1.resets == 0 and ch92_2.resets == 0, "9.2 on_reset not called before start", 0, ch92_1.resets)
	r92.start()
	_check(ch92_1.resets == 1 and ch92_2.resets == 1,
		"9.2 on_reset called recursively on all descendants during start()",
		{"ch1": 1, "ch2": 1},
		{"ch1": ch92_1.resets, "ch2": ch92_2.resets})
	_finish(r92)

	# 9.3 abort_running calls on_abort (and on_end semantics)
	# Check whether on_abort is called on started running tasks when abort_running() is invoked
	var p93 := DeepProbe.new()
	p93.results = [BTStatus.RUNNING]
	var r93 := _runner(_tree(p93))
	r93.start()
	r93.tick(0.1) # task is started and running
	_check(p93.aborts == 0 and p93.ends == 0, "9.3 Task running before abort", 0, p93.aborts)
	r93.abort_running()
	_check(p93.aborts == 1 and not r93.is_running and r93.last_status == BTStatus.FAILURE,
		"9.3 abort_running() calls on_abort() on active task and sets runner status to FAILURE",
		{"aborts": 1, "running": false, "status": BTStatus.FAILURE},
		{"aborts": p93.aborts, "running": r93.is_running, "status": r93.last_status})
	_finish(r93)

	# 9.4 Runner pooling / reuse with new set_tree()
	var tree_a := _tree(DeepProbe.new())
	var tree_b := _tree(DeepProbe.new())
	var r94 := _runner(tree_a)
	r94.start()
	r94.tick(0.1)
	_check(r94.is_running, "9.4 Runner active on tree A", true, r94.is_running)
	r94.set_tree(tree_b)
	_check(not r94.is_running and r94.ticks == 0 and r94.tree == tree_b,
		"9.4 set_tree() cleanly resets runner state and replaces tree",
		{"running": false, "ticks": 0, "tree_match": true},
		{"running": r94.is_running, "ticks": r94.ticks, "tree_match": r94.tree == tree_b})
	r94.start()
	_check(r94.is_running and r94.tree == tree_b, "9.4 Reused runner starts successfully on tree B", true, r94.is_running)
	_finish(r94)
