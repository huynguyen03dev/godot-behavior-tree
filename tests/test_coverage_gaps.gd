extends SceneTree
## Coverage gap test suite for Godot Behavior Tree.
## Targets previously uncovered runtime behaviors:
##  - AbortType.BOTH on BTSelector (LOWER_PRIORITY preemption and sequence guard aborts)
##  - AbortType.BOTH on BTSequence (guard-prefix SELF aborts and composite nesting)
##  - BTReturnSuccess runtime execution, override, and condition wrapping
##  - BTUntilSuccess runtime loop count and RUNNING passthrough
##  - BTUntilFailure runtime loop count and RUNNING passthrough
##  - BTCooldown consumed on completion vs not consumed on abort
##  - BTTimeLimit firing and child interruption with simulated delta time

class PureCondition extends BTTask:
	var condition_met: bool = false
	var eval_count: int = 0
	var update_count: int = 0

	func _init(p_met: bool = false) -> void:
		super._init()
		type_name = "PureCondition"
		category = "Condition"
		condition_met = p_met

	func evaluate_condition(_runner: BTRunner) -> int:
		eval_count += 1
		return BTStatus.SUCCESS if condition_met else BTStatus.FAILURE

	func on_update() -> int:
		update_count += 1
		return BTStatus.SUCCESS if condition_met else BTStatus.FAILURE

class MockRunningAction extends BTTask:
	var update_count: int = 0
	var abort_called: bool = false
	var end_called: bool = false

	func _init() -> void:
		super._init()
		type_name = "MockRunningAction"
		category = "Action"

	func on_update() -> int:
		update_count += 1
		return BTStatus.RUNNING

	func on_abort() -> void:
		abort_called = true
		super.on_abort()

	func on_end() -> void:
		end_called = true
		super.on_end()

class MockSequenceAction extends BTTask:
	var results: Array[int] = []
	var update_count: int = 0
	var abort_called: bool = false
	var end_called: bool = false

	func _init(p_results: Array[int] = []) -> void:
		super._init()
		type_name = "MockSequenceAction"
		category = "Action"
		results = p_results

	func on_update() -> int:
		var status: int = BTStatus.SUCCESS
		if update_count < results.size():
			status = results[update_count]
		elif not results.is_empty():
			status = results.back()
		update_count += 1
		return status

	func on_abort() -> void:
		abort_called = true
		super.on_abort()

	func on_end() -> void:
		end_called = true
		super.on_end()

var checks: int = 0
var failures: int = 0

func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		failures += 1
		printerr("FAIL: %s" % description)

func _runner(tree: BTTree) -> BTRunner:
	var runner := BTRunner.new(tree)
	root.add_child(runner)
	return runner

func _finish(runner: BTRunner) -> void:
	if is_instance_valid(runner):
		runner.stop()
		runner.queue_free()

func _create_test_registry() -> BTTaskRegistry:
	var reg := BTTaskRegistry.new()
	reg.register_task("PureCondition", func(): return PureCondition.new(), "Condition")
	reg.register_task("MockRunningAction", func(): return MockRunningAction.new(), "Action")
	reg.register_task("MockSequenceAction", func(): return MockSequenceAction.new(), "Action")
	return reg

func _initialize() -> void:
	print("Running Behavior Tree Coverage Gap Tests...")
	_test_abort_both_selector()
	_test_abort_both_sequence()
	_test_return_success_runtime()
	_test_until_success_runtime()
	_test_until_failure_runtime()
	_test_cooldown_consumption_and_abort()
	_test_timelimit_running_child()

	print("Coverage gaps suite: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

# ---------------------------------------------------------------- AbortType.BOTH on Selector
func _test_abort_both_selector() -> void:
	var reg := _create_test_registry()

	# Case 1: Selector with AbortType.BOTH (LOWER_PRIORITY half):
	# Higher-priority condition flip preempts the running lower-priority branch.
	var tree1 := BTTree.new()
	tree1.registry = reg
	var sel1: BTComposite.BTSelector = reg.create_task("Selector")
	sel1.set_abort_type(BTComposite.AbortType.BOTH)
	tree1.set_root(sel1)

	var high_seq1: BTComposite.BTSequence = reg.create_task("Sequence")
	var cond_high1: PureCondition = reg.create_task("PureCondition")
	cond_high1.condition_met = false
	var act_high1: MockRunningAction = reg.create_task("MockRunningAction")
	tree1.connect_parent_child(sel1, high_seq1)
	tree1.connect_parent_child(high_seq1, cond_high1)
	tree1.connect_parent_child(high_seq1, act_high1)

	var act_low1: MockRunningAction = reg.create_task("MockRunningAction")
	tree1.connect_parent_child(sel1, act_low1)

	var r1 := _runner(tree1)
	r1.start()
	var s1_tick1 := r1.tick()
	_check(s1_tick1 == BTStatus.RUNNING, "Selector BOTH (LowerPriority half): tick 1 status is RUNNING")
	_check(act_low1.update_count == 1 and not act_low1.abort_called, "Selector BOTH: low-priority branch runs on tick 1")
	_check(act_high1.update_count == 0, "Selector BOTH: high-priority branch has not executed")

	# Flip high condition to true -> on tick 2, selector aborts low branch and switches to high branch
	cond_high1.condition_met = true
	var s1_tick2 := r1.tick()
	_check(s1_tick2 == BTStatus.RUNNING, "Selector BOTH: tick 2 status is RUNNING after preemption")
	_check(act_low1.abort_called, "Selector BOTH: lower-priority active branch was aborted on high condition flip")
	_check(act_high1.update_count == 1, "Selector BOTH: higher-priority branch is now executing")
	_check(cond_high1.eval_count >= 1, "Selector BOTH: pure condition evaluated via evaluate_condition")
	_finish(r1)

	# Case 2: Combined behavior where active branch's sequence guard also matters:
	# Root Selector has AbortType.BOTH. Active branch is a Sequence with AbortType.BOTH and a guard.
	# When active sequence's guard fails, sequence aborts its own child and fails, so selector completes.
	var tree2 := BTTree.new()
	tree2.registry = reg
	var sel2: BTComposite.BTSelector = reg.create_task("Selector")
	sel2.set_abort_type(BTComposite.AbortType.BOTH)
	tree2.set_root(sel2)

	var high_seq2: BTComposite.BTSequence = reg.create_task("Sequence")
	var cond_high2: PureCondition = reg.create_task("PureCondition")
	cond_high2.condition_met = false
	var act_high2: MockRunningAction = reg.create_task("MockRunningAction")
	tree2.connect_parent_child(sel2, high_seq2)
	tree2.connect_parent_child(high_seq2, cond_high2)
	tree2.connect_parent_child(high_seq2, act_high2)

	var low_seq2: BTComposite.BTSequence = reg.create_task("Sequence")
	low_seq2.set_abort_type(BTComposite.AbortType.BOTH)
	var cond_low_guard: PureCondition = reg.create_task("PureCondition")
	cond_low_guard.condition_met = true
	var act_low2: MockRunningAction = reg.create_task("MockRunningAction")
	tree2.connect_parent_child(sel2, low_seq2)
	tree2.connect_parent_child(low_seq2, cond_low_guard)
	tree2.connect_parent_child(low_seq2, act_low2)

	var r2 := _runner(tree2)
	r2.start()
	var s2_tick1 := r2.tick()
	_check(s2_tick1 == BTStatus.RUNNING, "Selector BOTH + Sequence BOTH: tick 1 running low sequence")
	_check(act_low2.update_count == 1, "Selector BOTH + Sequence BOTH: active low child started")

	# Flip low sequence guard to false (high condition remains false).
	# Low sequence reevaluates its guard condition (< cur_idx), aborts act_low2 and fails itself.
	cond_low_guard.condition_met = false
	var s2_tick2 := r2.tick()
	_check(s2_tick2 == BTStatus.FAILURE, "Selector BOTH + Sequence BOTH: sequence guard failure fails sequence and tree")
	_check(act_low2.abort_called, "Selector BOTH + Sequence BOTH: active sequence child was aborted on guard failure")
	_check(cond_low_guard.eval_count >= 1, "Selector BOTH + Sequence BOTH: sequence guard reevaluated via evaluate_condition")
	_finish(r2)

	# Case 3: Selector BOTH with both branches active re-evaluating:
	# If low sequence guard is true, but high condition becomes true:
	var tree3 := BTTree.new()
	tree3.registry = reg
	var sel3: BTComposite.BTSelector = reg.create_task("Selector")
	sel3.set_abort_type(BTComposite.AbortType.BOTH)
	tree3.set_root(sel3)

	var high_seq3: BTComposite.BTSequence = reg.create_task("Sequence")
	var cond_high3: PureCondition = reg.create_task("PureCondition")
	cond_high3.condition_met = false
	var act_high3: MockRunningAction = reg.create_task("MockRunningAction")
	tree3.connect_parent_child(sel3, high_seq3)
	tree3.connect_parent_child(high_seq3, cond_high3)
	tree3.connect_parent_child(high_seq3, act_high3)

	var low_seq3: BTComposite.BTSequence = reg.create_task("Sequence")
	low_seq3.set_abort_type(BTComposite.AbortType.BOTH)
	var guard3: PureCondition = reg.create_task("PureCondition")
	guard3.condition_met = true
	var act_low3: MockRunningAction = reg.create_task("MockRunningAction")
	tree3.connect_parent_child(sel3, low_seq3)
	tree3.connect_parent_child(low_seq3, guard3)
	tree3.connect_parent_child(low_seq3, act_low3)

	var r3 := _runner(tree3)
	r3.start()
	r3.tick()
	_check(act_low3.update_count == 1, "Selector BOTH tree 3: low sequence running")

	# High flips to true while guard3 is still true
	cond_high3.condition_met = true
	var s3_tick2 := r3.tick()
	_check(s3_tick2 == BTStatus.RUNNING, "Selector BOTH tree 3: preempts to high sequence")
	_check(act_low3.abort_called, "Selector BOTH tree 3: low sequence child aborted on selector preemption")
	_check(act_high3.update_count == 1, "Selector BOTH tree 3: high sequence action running")
	_finish(r3)

# ---------------------------------------------------------------- AbortType.BOTH on Sequence
func _test_abort_both_sequence() -> void:
	var reg := _create_test_registry()

	# Case 1: Standalone Sequence with AbortType.BOTH (guard-prefix SELF behavior).
	var tree := BTTree.new()
	tree.registry = reg
	var seq: BTComposite.BTSequence = reg.create_task("Sequence")
	seq.set_abort_type(BTComposite.AbortType.BOTH)
	tree.set_root(seq)

	var guard: PureCondition = reg.create_task("PureCondition")
	guard.condition_met = true
	var action: MockRunningAction = reg.create_task("MockRunningAction")
	tree.connect_parent_child(seq, guard)
	tree.connect_parent_child(seq, action)

	var r := _runner(tree)
	r.start()
	var s1 := r.tick()
	_check(s1 == BTStatus.RUNNING, "Sequence BOTH: tick 1 running action")
	_check(action.update_count == 1 and not action.abort_called, "Sequence BOTH: action active on tick 1")

	# Guard flips to false
	guard.condition_met = false
	var s2 := r.tick()
	_check(s2 == BTStatus.FAILURE, "Sequence BOTH: guard flip causes sequence to return FAILURE")
	_check(action.abort_called, "Sequence BOTH: running action aborted on guard flip")
	_check(guard.eval_count >= 1, "Sequence BOTH: guard evaluated via evaluate_condition")
	_finish(r)

	# Case 2: Sequence with AbortType.BOTH containing a nested Selector
	var tree2 := BTTree.new()
	tree2.registry = reg
	var root_seq: BTComposite.BTSequence = reg.create_task("Sequence")
	root_seq.set_abort_type(BTComposite.AbortType.BOTH)
	tree2.set_root(root_seq)

	var root_guard: PureCondition = reg.create_task("PureCondition")
	root_guard.condition_met = true
	var nested_sel: BTComposite.BTSelector = reg.create_task("Selector")
	nested_sel.set_abort_type(BTComposite.AbortType.BOTH)
	var nested_action: MockRunningAction = reg.create_task("MockRunningAction")
	tree2.connect_parent_child(root_seq, root_guard)
	tree2.connect_parent_child(root_seq, nested_sel)
	tree2.connect_parent_child(nested_sel, nested_action)

	var r2 := _runner(tree2)
	r2.start()
	r2.tick()
	_check(nested_action.update_count == 1, "Sequence BOTH wrapping Selector: child running")

	root_guard.condition_met = false
	var nested_s2 := r2.tick()
	_check(nested_s2 == BTStatus.FAILURE, "Sequence BOTH wrapping Selector: root guard aborts entire branch")
	_check(nested_action.abort_called, "Sequence BOTH wrapping Selector: deeply nested child aborted")
	_finish(r2)

# ---------------------------------------------------------------- BTReturnSuccess
func _test_return_success_runtime() -> void:
	var reg := _create_test_registry()

	# Child fails -> BTReturnSuccess returns SUCCESS
	var tree1 := BTTree.new()
	tree1.registry = reg
	var ret_succ1: BTDecorator.BTReturnSuccess = reg.create_task("ReturnSuccess")
	tree1.set_root(ret_succ1)
	var fail_act: MockSequenceAction = reg.create_task("MockSequenceAction")
	fail_act.results = [BTStatus.FAILURE]
	tree1.connect_parent_child(ret_succ1, fail_act)

	var r1 := _runner(tree1)
	r1.start()
	var s1 := r1.tick()
	_check(s1 == BTStatus.SUCCESS, "BTReturnSuccess: FAILURE child status overridden to SUCCESS")
	_check(fail_act.update_count == 1, "BTReturnSuccess: child was executed once")
	_finish(r1)

	# Child succeeds -> BTReturnSuccess returns SUCCESS
	var tree2 := BTTree.new()
	tree2.registry = reg
	var ret_succ2: BTDecorator.BTReturnSuccess = reg.create_task("ReturnSuccess")
	tree2.set_root(ret_succ2)
	var succ_act: MockSequenceAction = reg.create_task("MockSequenceAction")
	succ_act.results = [BTStatus.SUCCESS]
	tree2.connect_parent_child(ret_succ2, succ_act)

	var r2 := _runner(tree2)
	r2.start()
	var s2 := r2.tick()
	_check(s2 == BTStatus.SUCCESS, "BTReturnSuccess: SUCCESS child remains SUCCESS")
	_finish(r2)

	# Child running -> BTReturnSuccess passes RUNNING through
	var tree3 := BTTree.new()
	tree3.registry = reg
	var ret_succ3: BTDecorator.BTReturnSuccess = reg.create_task("ReturnSuccess")
	tree3.set_root(ret_succ3)
	var run_act: MockRunningAction = reg.create_task("MockRunningAction")
	tree3.connect_parent_child(ret_succ3, run_act)

	var r3 := _runner(tree3)
	r3.start()
	var s3 := r3.tick()
	_check(s3 == BTStatus.RUNNING, "BTReturnSuccess: RUNNING child status passes through as RUNNING")
	_finish(r3)

	# Abort re-evaluation condition wrapper support:
	# BTReturnSuccess wrapping a failing condition in an abort check reevaluates as SUCCESS
	var tree4 := BTTree.new()
	tree4.registry = reg
	var sel4: BTComposite.BTSelector = reg.create_task("Selector")
	sel4.set_abort_type(BTComposite.AbortType.LOWER_PRIORITY)
	tree4.set_root(sel4)

	var high_seq4: BTComposite.BTSequence = reg.create_task("Sequence")
	var ret_succ4: BTDecorator.BTReturnSuccess = reg.create_task("ReturnSuccess")
	var failing_cond: PureCondition = reg.create_task("PureCondition")
	failing_cond.condition_met = false
	var act_high4: MockRunningAction = reg.create_task("MockRunningAction")
	tree4.connect_parent_child(sel4, high_seq4)
	tree4.connect_parent_child(high_seq4, ret_succ4)
	tree4.connect_parent_child(ret_succ4, failing_cond)
	tree4.connect_parent_child(high_seq4, act_high4)

	var act_low4: MockRunningAction = reg.create_task("MockRunningAction")
	tree4.connect_parent_child(sel4, act_low4)

	var r4 := _runner(tree4)
	r4.start()
	# Because failing_cond returns FAILURE, but ret_succ4 decorates it to SUCCESS,
	# high_seq4 condition check passes immediately on tick 1!
	var s4 := r4.tick()
	_check(s4 == BTStatus.RUNNING and act_high4.update_count == 1, "BTReturnSuccess: condition wrapper evaluated to SUCCESS in sequence")
	_check(act_low4.update_count == 0, "BTReturnSuccess: lower priority never ran due to wrapped condition success")
	_finish(r4)

# ---------------------------------------------------------------- BTUntilSuccess
func _test_until_success_runtime() -> void:
	var reg := _create_test_registry()

	# Child fails twice then succeeds: loop count and tick semantics
	var tree1 := BTTree.new()
	tree1.registry = reg
	var until_succ: BTDecorator.BTUntilSuccess = reg.create_task("UntilSuccess")
	tree1.set_root(until_succ)
	var multi_act: MockSequenceAction = reg.create_task("MockSequenceAction")
	multi_act.results = [BTStatus.FAILURE, BTStatus.FAILURE, BTStatus.SUCCESS]
	tree1.connect_parent_child(until_succ, multi_act)

	var r1 := _runner(tree1)
	r1.start()
	var t1 := r1.tick()
	_check(t1 == BTStatus.RUNNING and multi_act.update_count == 1, "BTUntilSuccess: tick 1 child failure yields RUNNING")
	var t2 := r1.tick()
	_check(t2 == BTStatus.RUNNING and multi_act.update_count == 2, "BTUntilSuccess: tick 2 second failure yields RUNNING")
	var t3 := r1.tick()
	_check(t3 == BTStatus.SUCCESS and multi_act.update_count == 3, "BTUntilSuccess: tick 3 child success completes with SUCCESS (3 iterations)")
	_finish(r1)

	# RUNNING passthrough: child returns RUNNING
	var tree2 := BTTree.new()
	tree2.registry = reg
	var until_succ2: BTDecorator.BTUntilSuccess = reg.create_task("UntilSuccess")
	tree2.set_root(until_succ2)
	var run_act: MockSequenceAction = reg.create_task("MockSequenceAction")
	run_act.results = [BTStatus.RUNNING, BTStatus.RUNNING, BTStatus.SUCCESS]
	tree2.connect_parent_child(until_succ2, run_act)

	var r2 := _runner(tree2)
	r2.start()
	var rt1 := r2.tick()
	_check(rt1 == BTStatus.RUNNING and run_act.update_count == 1, "BTUntilSuccess: child RUNNING passes through on tick 1")
	var rt2 := r2.tick()
	_check(rt2 == BTStatus.RUNNING and run_act.update_count == 2, "BTUntilSuccess: child RUNNING passes through on tick 2")
	var rt3 := r2.tick()
	_check(rt3 == BTStatus.SUCCESS and run_act.update_count == 3, "BTUntilSuccess: finishes on SUCCESS")
	_finish(r2)

# ---------------------------------------------------------------- BTUntilFailure
func _test_until_failure_runtime() -> void:
	var reg := _create_test_registry()

	# Child succeeds twice then fails: loop count and tick semantics
	var tree1 := BTTree.new()
	tree1.registry = reg
	var until_fail: BTDecorator.BTUntilFailure = reg.create_task("UntilFailure")
	tree1.set_root(until_fail)
	var multi_act: MockSequenceAction = reg.create_task("MockSequenceAction")
	multi_act.results = [BTStatus.SUCCESS, BTStatus.SUCCESS, BTStatus.FAILURE]
	tree1.connect_parent_child(until_fail, multi_act)

	var r1 := _runner(tree1)
	r1.start()
	var t1 := r1.tick()
	_check(t1 == BTStatus.RUNNING and multi_act.update_count == 1, "BTUntilFailure: tick 1 child success yields RUNNING")
	var t2 := r1.tick()
	_check(t2 == BTStatus.RUNNING and multi_act.update_count == 2, "BTUntilFailure: tick 2 second success yields RUNNING")
	var t3 := r1.tick()
	_check(t3 == BTStatus.FAILURE and multi_act.update_count == 3, "BTUntilFailure: tick 3 child failure completes with FAILURE (3 iterations)")
	_finish(r1)

	# RUNNING passthrough
	var tree2 := BTTree.new()
	tree2.registry = reg
	var until_fail2: BTDecorator.BTUntilFailure = reg.create_task("UntilFailure")
	tree2.set_root(until_fail2)
	var run_act: MockSequenceAction = reg.create_task("MockSequenceAction")
	run_act.results = [BTStatus.RUNNING, BTStatus.RUNNING, BTStatus.FAILURE]
	tree2.connect_parent_child(until_fail2, run_act)

	var r2 := _runner(tree2)
	r2.start()
	var rt1 := r2.tick()
	_check(rt1 == BTStatus.RUNNING and run_act.update_count == 1, "BTUntilFailure: child RUNNING passes through on tick 1")
	var rt2 := r2.tick()
	_check(rt2 == BTStatus.RUNNING and run_act.update_count == 2, "BTUntilFailure: child RUNNING passes through on tick 2")
	var rt3 := r2.tick()
	_check(rt3 == BTStatus.FAILURE and run_act.update_count == 3, "BTUntilFailure: finishes on FAILURE")
	_finish(r2)

# ---------------------------------------------------------------- Cooldown
func _test_cooldown_consumption_and_abort() -> void:
	var reg := _create_test_registry()

	# Cooldown consumed on completion vs not consumed on abort:
	# Tick sequence with a running child, interrupt, verify next entry respects cooldown.
	var tree := BTTree.new()
	tree.registry = reg
	var seq: BTComposite.BTSequence = reg.create_task("Sequence")
	tree.set_root(seq)

	var cd: BTDecorator.BTCooldown = reg.create_task("Cooldown")
	cd.cooldown_time = 1.0
	var child_act: MockSequenceAction = reg.create_task("MockSequenceAction")
	# Run 1: returns RUNNING (gets interrupted)
	# Run 2: returns SUCCESS (completes normally -> cooldown consumed)
	# Run 3: should not be reached if cooldown blocks
	# Run 4: returns SUCCESS (after cooldown expires)
	child_act.results = [BTStatus.RUNNING, BTStatus.SUCCESS, BTStatus.SUCCESS, BTStatus.SUCCESS]
	tree.connect_parent_child(seq, cd)
	tree.connect_parent_child(cd, child_act)

	var trailing_act: MockSequenceAction = reg.create_task("MockSequenceAction")
	trailing_act.results = [BTStatus.SUCCESS]
	tree.connect_parent_child(seq, trailing_act)

	var r := _runner(tree)

	# Step 1: Start and tick at t=0.0 -> child returns RUNNING
	r.start()
	var s1 := r.tick(0.0)
	_check(s1 == BTStatus.RUNNING and child_act.update_count == 1, "Cooldown: child is RUNNING on tick 1")
	_check(r.is_running and s1 == BTStatus.RUNNING, "Cooldown: runner is RUNNING without consuming cooldown")

	# Step 2: Interrupt the sequence while child is running
	r.interrupt(seq)
	_check(child_act.abort_called, "Cooldown: child was aborted by interrupt")
	_check(not r.is_running, "Cooldown: not consumed when aborted while RUNNING")

	# Step 3: Immediate restart at t=0.1 (well before 1.0s cooldown)
	# Since previous execution was aborted, cooldown was NOT consumed -> must allow entry!
	r.start()
	var s2 := r.tick(0.1)
	_check(s2 == BTStatus.SUCCESS, "Cooldown: not consumed on abort; allows next entry at t=0.1")
	_check(child_act.update_count == 2, "Cooldown: child executed second time and succeeded")
	_check(cd.last_status == BTStatus.SUCCESS and is_equal_approx(r.time, 0.1), "Cooldown: completed successfully at t=0.1")

	# Step 4: Next entry at t=0.5 (within cooldown window, elapsed = 0.4 < 1.0) -> must fail!
	r.start()
	var s3 := r.tick(0.4) # runner.time is now 0.5
	_check(s3 == BTStatus.FAILURE, "Cooldown: blocked on next entry within cooldown window at t=0.5")
	_check(child_act.update_count == 2, "Cooldown: child was NOT executed while on cooldown")

	# Step 5: Advance simulated time past cooldown: t=1.2 (elapsed = 1.1 >= 1.0) -> allows entry!
	r.start()
	var s4 := r.tick(0.7) # runner.time is now 1.2
	_check(s4 == BTStatus.SUCCESS, "Cooldown: opens again after simulated time exceeds cooldown")
	_check(child_act.update_count == 3, "Cooldown: child executed after cooldown expiration")
	_finish(r)

# ---------------------------------------------------------------- TimeLimit
func _test_timelimit_running_child() -> void:
	var reg := _create_test_registry()

	# TimeLimit firing on a running child (simulated time)
	var tree := BTTree.new()
	tree.registry = reg
	var tl: BTDecorator.BTTimeLimit = reg.create_task("TimeLimit")
	tl.time_limit = 1.0
	tree.set_root(tl)

	var run_act: MockRunningAction = reg.create_task("MockRunningAction")
	tree.connect_parent_child(tl, run_act)

	var r := _runner(tree)
	r.start()

	# Tick 1 with delta 0.0: sets _start_time = 0.0, child starts and returns RUNNING
	var s1 := r.tick(0.0)
	_check(s1 == BTStatus.RUNNING and not run_act.abort_called, "TimeLimit: tick 1 (t=0.0 < 1.0) child still running")

	# Tick 2 with delta 0.5 (runner time 0.5 < 1.0) -> RUNNING
	var s2 := r.tick(0.5)
	_check(s2 == BTStatus.RUNNING and not run_act.abort_called, "TimeLimit: tick 2 (t=0.5 < 1.0) child still running")

	# Tick 3 with delta 0.6 (runner time 1.1 >= 1.0) -> TimeLimit aborts child and fails
	var s3 := r.tick(0.6)
	_check(s3 == BTStatus.FAILURE, "TimeLimit: tick 3 (t=1.1 >= 1.0) returns FAILURE")
	_check(run_act.abort_called, "TimeLimit: running child was aborted when time limit fired")
	_finish(r)
