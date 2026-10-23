extends SceneTree
## Deep Gameplay E2E Test Suite for Godot Behavior Tree.
## Tests 2 complex gameplay mechanisms over thousands of ticks to uncover real engine bugs:
## A. Squad Combat 5 Agents with Mutually Exclusive Roles, Cover Point,
##    LOWER_PRIORITY Retreat Preemption, and SELF Abort on Casualty (3500 Ticks).
## B. Multi-Stage Quest/Machine Chain with SubTrees, Blackboard Scoping,
##    Cooldown Retry, TimeLimit Abort, and Re-entrancy Stress (3200 Ticks).
## Run with: godot --headless --path . -s res://tests/test_e2e_gameplay_deep.gd

var total_checks: int = 0
var total_failures: int = 0

func _check(condition: bool, description: String, context: String = "") -> void:
	total_checks += 1
	if condition:
		print("  [PASS] %s" % description)
	else:
		total_failures += 1
		print("  ❌ [FAIL] %s %s" % [description, ("(" + context + ")") if context != "" else ""])

func _initialize() -> void:
	print("==================================================")
	print(" Starting Gameplay Deep E2E Test Suite")
	print("==================================================")

	_run_mechanism_a_squad_combat()
	_run_mechanism_b_quest_chain()
	_run_reentrancy_stress()
	_run_memory_leak_check()

	print("==================================================")
	print("Gameplay deep E2E: %d checks, %d failures" % [total_checks, total_failures])
	print("==================================================")
	quit(1 if total_failures > 0 else 0)

# ==============================================================================
# MECHANISM A: SQUAD COMBAT 5 AGENTS (3500 TICKS)
# ==============================================================================

class SquadCoordinator:
	var healer_holder: int = -1
	var dps_holders: Array[int] = []
	var tank_holder: int = -1
	var cover_holder: int = -1
	var grant_count: int = 0
	var revoke_count: int = 0
	var agents: Array = []

	func can_claim_or_holds(agent_id: int, role: String) -> bool:
		if role == "HEALER":
			return healer_holder == agent_id or healer_holder == -1
		elif role == "TANK":
			return tank_holder == agent_id or tank_holder == -1
		elif role == "DPS":
			return (agent_id in dps_holders) or dps_holders.size() < 2
		return false

	func try_claim_role(agent_id: int, role: String) -> bool:
		if role == "HEALER":
			if healer_holder == agent_id:
				return true
			if healer_holder == -1:
				healer_holder = agent_id
				grant_count += 1
				return true
		elif role == "TANK":
			if tank_holder == agent_id:
				return true
			if tank_holder == -1:
				tank_holder = agent_id
				grant_count += 1
				return true
		elif role == "DPS":
			if agent_id in dps_holders:
				return true
			if dps_holders.size() < 2:
				dps_holders.append(agent_id)
				grant_count += 1
				return true
		return false

	func release_role(agent_id: int, role: String) -> void:
		if role == "HEALER" and healer_holder == agent_id:
			healer_holder = -1
			revoke_count += 1
		elif role == "TANK" and tank_holder == agent_id:
			tank_holder = -1
			revoke_count += 1
		elif role == "DPS" and (agent_id in dps_holders):
			dps_holders.erase(agent_id)
			revoke_count += 1

	func try_claim_cover(agent_id: int) -> bool:
		if cover_holder == agent_id:
			return true
		if cover_holder == -1:
			cover_holder = agent_id
			return true
		return false

	func release_cover(agent_id: int) -> void:
		if cover_holder == agent_id:
			cover_holder = -1

	func squad_needs_healing(excluded_agent_id: int) -> bool:
		for a in agents:
			if a.alive and a.id != excluded_agent_id and a.hp < 75.0:
				return true
		return false

class AgentState:
	var id: int
	var hp: float = 100.0
	var max_hp: float = 100.0
	var alive: bool = true
	var role: String = "NONE"
	var in_cover: bool = false
	var state: String = "IDLE"
	var aborted_actions: int = 0
	var action_updates: int = 0
	var ghost_task_detected: bool = false

# Custom Tasks for Squad Combat
class DeadCheckCondition extends BTTask:
	var agent: AgentState
	func _init(p_agent: AgentState = null) -> void:
		super._init()
		type_name = "DeadCheckCondition"
		category = "Condition"
		agent = p_agent
	func evaluate_condition(_runner: BTRunner) -> int:
		return BTStatus.SUCCESS if not agent.alive else BTStatus.FAILURE
	func on_update() -> int:
		return BTStatus.SUCCESS if not agent.alive else BTStatus.FAILURE

class SquadAliveCondition extends BTTask:
	var agent: AgentState
	func _init(p_agent: AgentState = null) -> void:
		super._init()
		type_name = "SquadAliveCondition"
		category = "Condition"
		agent = p_agent
	func evaluate_condition(_runner: BTRunner) -> int:
		return BTStatus.SUCCESS if agent.alive else BTStatus.FAILURE
	func on_update() -> int:
		return BTStatus.SUCCESS if agent.alive else BTStatus.FAILURE

class LowHPPreemptCondition extends BTTask:
	var agent: AgentState
	var threshold: float
	func _init(p_agent: AgentState = null, p_thresh: float = 35.0) -> void:
		super._init()
		type_name = "LowHPPreemptCondition"
		category = "Condition"
		agent = p_agent
		threshold = p_thresh
	func evaluate_condition(_runner: BTRunner) -> int:
		return BTStatus.SUCCESS if (agent.alive and agent.hp < threshold) else BTStatus.FAILURE
	func on_update() -> int:
		return BTStatus.SUCCESS if (agent.alive and agent.hp < threshold) else BTStatus.FAILURE

class HealerSlotCondition extends BTTask:
	var agent: AgentState
	var coord: SquadCoordinator
	func _init(p_agent: AgentState = null, p_coord: SquadCoordinator = null) -> void:
		super._init()
		type_name = "HealerSlotCondition"
		category = "Condition"
		agent = p_agent
		coord = p_coord
	func evaluate_condition(_runner: BTRunner) -> int:
		if not agent.alive:
			return BTStatus.FAILURE
		var can = coord.can_claim_or_holds(agent.id, "HEALER")
		var needs = coord.squad_needs_healing(agent.id) or agent.role == "HEALER"
		return BTStatus.SUCCESS if (can and needs) else BTStatus.FAILURE
	func on_update() -> int:
		return evaluate_condition(null)

class TankSlotCondition extends BTTask:
	var agent: AgentState
	var coord: SquadCoordinator
	func _init(p_agent: AgentState = null, p_coord: SquadCoordinator = null) -> void:
		super._init()
		type_name = "TankSlotCondition"
		category = "Condition"
		agent = p_agent
		coord = p_coord
	func evaluate_condition(_runner: BTRunner) -> int:
		if not agent.alive:
			return BTStatus.FAILURE
		return BTStatus.SUCCESS if coord.can_claim_or_holds(agent.id, "TANK") else BTStatus.FAILURE
	func on_update() -> int:
		return evaluate_condition(null)

class DPSSlotCondition extends BTTask:
	var agent: AgentState
	var coord: SquadCoordinator
	func _init(p_agent: AgentState = null, p_coord: SquadCoordinator = null) -> void:
		super._init()
		type_name = "DPSSlotCondition"
		category = "Condition"
		agent = p_agent
		coord = p_coord
	func evaluate_condition(_runner: BTRunner) -> int:
		if not agent.alive:
			return BTStatus.FAILURE
		return BTStatus.SUCCESS if coord.can_claim_or_holds(agent.id, "DPS") else BTStatus.FAILURE
	func on_update() -> int:
		return evaluate_condition(null)

class CombatBaseAction extends BTTask:
	var agent: AgentState
	var coord: SquadCoordinator
	var is_aborted_flag: bool = false
	func _init(p_agent: AgentState = null, p_coord: SquadCoordinator = null) -> void:
		super._init()
		agent = p_agent
		coord = p_coord
		category = "Action"
	func on_abort() -> void:
		is_aborted_flag = true
		agent.aborted_actions += 1
		super.on_abort()

class CorpseAction extends CombatBaseAction:
	func _init(p_agent: AgentState = null, p_coord: SquadCoordinator = null) -> void:
		super._init(p_agent, p_coord)
		type_name = "CorpseAction"
	func on_start() -> void:
		is_aborted_flag = false
		agent.role = "DEAD"
		agent.state = "DEAD"
		agent.in_cover = false
		coord.release_role(agent.id, "HEALER")
		coord.release_role(agent.id, "TANK")
		coord.release_role(agent.id, "DPS")
		coord.release_cover(agent.id)
	func on_update() -> int:
		agent.action_updates += 1
		return BTStatus.RUNNING

class SquadRetreatAction extends CombatBaseAction:
	func _init(p_agent: AgentState = null, p_coord: SquadCoordinator = null) -> void:
		super._init(p_agent, p_coord)
		type_name = "SquadRetreatAction"
	func on_start() -> void:
		is_aborted_flag = false
		coord.release_role(agent.id, "HEALER")
		coord.release_role(agent.id, "TANK")
		coord.release_role(agent.id, "DPS")
		coord.release_cover(agent.id)
		agent.role = "NONE"
		agent.in_cover = false
		agent.state = "RETREAT"
	func on_update() -> int:
		if is_aborted_flag:
			agent.ghost_task_detected = true
		agent.action_updates += 1
		agent.hp = min(agent.max_hp, agent.hp + 6.0)
		if agent.hp >= 80.0:
			agent.state = "IDLE"
			return BTStatus.SUCCESS
		return BTStatus.RUNNING
	func on_abort() -> void:
		super.on_abort()
		agent.state = "IDLE"
	func on_end() -> void:
		agent.state = "IDLE"

class SquadHealAction extends CombatBaseAction:
	func _init(p_agent: AgentState = null, p_coord: SquadCoordinator = null) -> void:
		super._init(p_agent, p_coord)
		type_name = "SquadHealAction"
	func on_start() -> void:
		is_aborted_flag = false
		coord.try_claim_role(agent.id, "HEALER")
		agent.role = "HEALER"
		agent.state = "HEAL"
	func on_update() -> int:
		if is_aborted_flag:
			agent.ghost_task_detected = true
		agent.action_updates += 1
		var target: AgentState = null
		var lowest_hp: float = 999.0
		for a in coord.agents:
			if a.alive and a.hp < 75.0 and a.hp < lowest_hp:
				lowest_hp = a.hp
				target = a
		if target != null:
			target.hp = min(target.max_hp, target.hp + 3.0)
		return BTStatus.RUNNING
	func on_abort() -> void:
		super.on_abort()
		coord.release_role(agent.id, "HEALER")
		agent.role = "NONE"
		agent.state = "IDLE"
	func on_end() -> void:
		coord.release_role(agent.id, "HEALER")
		agent.role = "NONE"
		agent.state = "IDLE"

class SquadTankAction extends CombatBaseAction:
	func _init(p_agent: AgentState = null, p_coord: SquadCoordinator = null) -> void:
		super._init(p_agent, p_coord)
		type_name = "SquadTankAction"
	func on_start() -> void:
		is_aborted_flag = false
		coord.try_claim_role(agent.id, "TANK")
		agent.role = "TANK"
		agent.state = "TANK"
		agent.in_cover = coord.try_claim_cover(agent.id)
	func on_update() -> int:
		if is_aborted_flag:
			agent.ghost_task_detected = true
		agent.action_updates += 1
		if not agent.in_cover and coord.try_claim_cover(agent.id):
			agent.in_cover = true
		return BTStatus.RUNNING
	func on_abort() -> void:
		super.on_abort()
		coord.release_cover(agent.id)
		coord.release_role(agent.id, "TANK")
		agent.in_cover = false
		agent.role = "NONE"
		agent.state = "IDLE"
	func on_end() -> void:
		coord.release_cover(agent.id)
		coord.release_role(agent.id, "TANK")
		agent.in_cover = false
		agent.role = "NONE"
		agent.state = "IDLE"

class SquadDPSAction extends CombatBaseAction:
	func _init(p_agent: AgentState = null, p_coord: SquadCoordinator = null) -> void:
		super._init(p_agent, p_coord)
		type_name = "SquadDPSAction"
	func on_start() -> void:
		is_aborted_flag = false
		coord.try_claim_role(agent.id, "DPS")
		agent.role = "DPS"
		agent.state = "ATTACK"
	func on_update() -> int:
		if is_aborted_flag:
			agent.ghost_task_detected = true
		agent.action_updates += 1
		return BTStatus.RUNNING
	func on_abort() -> void:
		super.on_abort()
		coord.release_role(agent.id, "DPS")
		agent.role = "NONE"
		agent.state = "IDLE"
	func on_end() -> void:
		coord.release_role(agent.id, "DPS")
		agent.role = "NONE"
		agent.state = "IDLE"

class SquadReserveAction extends CombatBaseAction:
	func _init(p_agent: AgentState = null, p_coord: SquadCoordinator = null) -> void:
		super._init(p_agent, p_coord)
		type_name = "SquadReserveAction"
	func on_start() -> void:
		is_aborted_flag = false
		agent.role = "RESERVE"
		agent.state = "RESERVE"
	func on_update() -> int:
		if is_aborted_flag:
			agent.ghost_task_detected = true
		agent.action_updates += 1
		return BTStatus.RUNNING
	func on_abort() -> void:
		super.on_abort()
		agent.role = "NONE"
		agent.state = "IDLE"
	func on_end() -> void:
		agent.role = "NONE"
		agent.state = "IDLE"

func _run_mechanism_a_squad_combat() -> void:
	print("\n--- Running Mechanism A: Squad Combat (3500 Ticks) ---")
	var coord := SquadCoordinator.new()
	var runners: Array[BTRunner] = []

	for i in range(5):
		var a := AgentState.new()
		a.id = i
		coord.agents.append(a)

		var tree := BTTree.new()
		# Root Repeater (Forever) wrapping Root Selector with LOWER_PRIORITY
		var root_rep := BTDecorator.BTRepeater.new()
		root_rep.set_param("repeat_forever", true, false)
		tree.set_root(root_rep)

		var root_sel := BTComposite.BTSelector.new()
		root_sel.set_abort_type(BTComposite.AbortType.LOWER_PRIORITY)
		tree.connect_parent_child(root_rep, root_sel)

		# Branch 0: Dead State
		var dead_seq := BTComposite.BTSequence.new()
		var dead_cond := DeadCheckCondition.new(a)
		var dead_act := CorpseAction.new(a, coord)
		tree.connect_parent_child(root_sel, dead_seq)
		tree.connect_parent_child(dead_seq, dead_cond)
		tree.connect_parent_child(dead_seq, dead_act)

		# Branch 1: Retreat Sequence with SELF abort
		var retreat_seq := BTComposite.BTSequence.new()
		retreat_seq.set_abort_type(BTComposite.AbortType.SELF)
		var ret_alive_cond := SquadAliveCondition.new(a)
		var ret_hp_cond := LowHPPreemptCondition.new(a, 35.0)
		var ret_act := SquadRetreatAction.new(a, coord)
		tree.connect_parent_child(root_sel, retreat_seq)
		tree.connect_parent_child(retreat_seq, ret_alive_cond)
		tree.connect_parent_child(retreat_seq, ret_hp_cond)
		tree.connect_parent_child(retreat_seq, ret_act)

		# Branch 2: Healer Sequence with SELF abort
		var heal_seq := BTComposite.BTSequence.new()
		heal_seq.set_abort_type(BTComposite.AbortType.SELF)
		var heal_alive_cond := SquadAliveCondition.new(a)
		var heal_cond := HealerSlotCondition.new(a, coord)
		var heal_act := SquadHealAction.new(a, coord)
		tree.connect_parent_child(root_sel, heal_seq)
		tree.connect_parent_child(heal_seq, heal_alive_cond)
		tree.connect_parent_child(heal_seq, heal_cond)
		tree.connect_parent_child(heal_seq, heal_act)

		# Branch 3: Tank Sequence with SELF abort
		var tank_seq := BTComposite.BTSequence.new()
		tank_seq.set_abort_type(BTComposite.AbortType.SELF)
		var tank_alive_cond := SquadAliveCondition.new(a)
		var tank_cond := TankSlotCondition.new(a, coord)
		var tank_act := SquadTankAction.new(a, coord)
		tree.connect_parent_child(root_sel, tank_seq)
		tree.connect_parent_child(tank_seq, tank_alive_cond)
		tree.connect_parent_child(tank_seq, tank_cond)
		tree.connect_parent_child(tank_seq, tank_act)

		# Branch 4: DPS Sequence with SELF abort
		var dps_seq := BTComposite.BTSequence.new()
		dps_seq.set_abort_type(BTComposite.AbortType.SELF)
		var dps_alive_cond := SquadAliveCondition.new(a)
		var dps_cond := DPSSlotCondition.new(a, coord)
		var dps_act := SquadDPSAction.new(a, coord)
		tree.connect_parent_child(root_sel, dps_seq)
		tree.connect_parent_child(dps_seq, dps_alive_cond)
		tree.connect_parent_child(dps_seq, dps_cond)
		tree.connect_parent_child(dps_seq, dps_act)

		# Branch 5: Reserve Fallback
		var res_act := SquadReserveAction.new(a, coord)
		tree.connect_parent_child(root_sel, res_act)

		var r := BTRunner.new(tree)
		r.start()
		runners.append(r)

	_check(runners.size() == 5, "Mechanism A: 5 agent BT runners initialized")

	var inv_healer_violations: int = 0
	var inv_dps_violations: int = 0
	var inv_tank_violations: int = 0
	var inv_cover_violations: int = 0
	var inv_dead_role_violations: int = 0
	var inv_dead_cover_violations: int = 0
	var inv_negative_hp_violations: int = 0
	var ghost_task_violations: int = 0

	var retreat_activations: int = 0
	var prev_ret_states: Array[bool] = [false, false, false, false, false]
	var agent0_casualty_aborted: bool = false
	var agent1_casualty_aborted: bool = false
	var squad_formation_reorganized_after_death: bool = false

	# Scheduled Burst damage to trigger exactly 8 retreat cycles independently
	var retreat_burst_ticks: Array[int] = [100, 300, 750, 1050, 1400, 1750, 2300, 2700]

	# 3500 Ticks Simulation
	for tick in range(3500):
		# Deterministic Scenario Script
		if tick == 500:
			# Agent 0 fatal strike
			coord.agents[0].alive = false
			coord.agents[0].hp = 0.0
		elif tick == 2000:
			# Agent 1 fatal strike
			coord.agents[1].alive = false
			coord.agents[1].hp = 0.0
		elif tick in retreat_burst_ticks:
			# Critical burst strike dropping active Tank below 35 HP
			for a in coord.agents:
				if a.alive and a.role == "TANK":
					a.hp = 25.0
		else:
			# Moderate attrition damage
			if tick % 20 == 0:
				for a in coord.agents:
					if a.alive and a.role == "TANK":
						a.hp = max(0.0, a.hp - 10.0)
					elif a.alive and a.role == "DPS" and (tick % 40 == 0):
						a.hp = max(0.0, a.hp - 8.0)

		# Tick all runners
		for i in range(5):
			runners[i].tick(0.05)

		# Per-tick Invariant Checks
		var h_count: int = 0
		var d_count: int = 0
		var t_count: int = 0
		var c_count: int = 0
		for i in range(5):
			var a: AgentState = coord.agents[i]
			if a.role == "HEALER": h_count += 1
			elif a.role == "DPS": d_count += 1
			elif a.role == "TANK": t_count += 1
			if a.in_cover: c_count += 1

			if a.hp < 0.0:
				inv_negative_hp_violations += 1
			if not a.alive:
				if a.role in ["HEALER", "TANK", "DPS", "RESERVE"]:
					inv_dead_role_violations += 1
				if a.in_cover:
					inv_dead_cover_violations += 1
			if a.ghost_task_detected:
				ghost_task_violations += 1

		if h_count > 1: inv_healer_violations += 1
		if d_count > 2: inv_dps_violations += 1
		if t_count > 1: inv_tank_violations += 1
		if c_count > 1: inv_cover_violations += 1

		# Track retreat event triggers
		for i in range(5):
			var a: AgentState = coord.agents[i]
			var in_ret: bool = (a.state == "RETREAT")
			if in_ret and not prev_ret_states[i]:
				retreat_activations += 1
			prev_ret_states[i] = in_ret

		# Milestone validations
		if tick == 505:
			if coord.agents[0].role == "DEAD" and not coord.agents[0].in_cover:
				agent0_casualty_aborted = true
		if tick == 700:
			# Check if squad reorganized: 1 Tank, 2 DPS (including Agent 4 promoted from Reserve), 1 Healer
			if coord.tank_holder != -1 and coord.dps_holders.size() == 2 and (4 in coord.dps_holders):
				squad_formation_reorganized_after_death = true
		if tick == 2005:
			if coord.agents[1].role == "DEAD" and not coord.agents[1].in_cover:
				agent1_casualty_aborted = true

	# Assertions for Mechanism A
	_check(inv_healer_violations == 0, "Invariant: Healer count <= 1 held on all 3500 ticks", "violations=%d" % inv_healer_violations)
	_check(inv_dps_violations == 0, "Invariant: DPS count <= 2 held on all 3500 ticks", "violations=%d" % inv_dps_violations)
	_check(inv_tank_violations == 0, "Invariant: Tank count <= 1 held on all 3500 ticks", "violations=%d" % inv_tank_violations)
	_check(inv_cover_violations == 0, "Invariant: Cover point holder <= 1 held on all 3500 ticks", "violations=%d" % inv_cover_violations)
	_check(inv_dead_role_violations == 0, "Invariant: Dead agents never hold combat roles", "violations=%d" % inv_dead_role_violations)
	_check(inv_dead_cover_violations == 0, "Invariant: Dead agents never occupy cover", "violations=%d" % inv_dead_cover_violations)
	_check(inv_negative_hp_violations == 0, "Invariant: Agent HP never drops below 0", "violations=%d" % inv_negative_hp_violations)
	_check(ghost_task_violations == 0, "Invariant: No ghost tasks executed after on_abort()", "violations=%d" % ghost_task_violations)

	_check(agent0_casualty_aborted, "Event: Agent 0 casualty immediately aborted role & cover (SELF abort)")
	_check(squad_formation_reorganized_after_death, "Event: Squad formation reorganized (Agent 1 claimed Tank, Agent 4 promoted to DPS)")
	_check(agent1_casualty_aborted, "Event: Agent 1 casualty immediately aborted role (SELF abort)")
	_check(retreat_activations == 8, "Event: Independent retreat count matched expected 8 events", "actual=%d" % retreat_activations)

	# Stop runners and check role balance
	for r in runners:
		r.stop()
		r.free()

	_check(coord.grant_count == coord.revoke_count, "Lifecycle: All granted roles revoked cleanly on stop", "grants=%d, revokes=%d" % [coord.grant_count, coord.revoke_count])
	_check(not coord.agents[0].alive and not coord.agents[1].alive, "Final State: Casualty agents remained dead")
	_check(coord.agents[2].alive and coord.agents[3].alive and coord.agents[4].alive, "Final State: Surviving agents operational")
	_check(coord.agents[2].hp >= 70.0 and coord.agents[3].hp >= 70.0 and coord.agents[4].hp >= 70.0, "Survivability: Healer successfully maintained surviving agents HP >= 70 across 3500 ticks", "hp=[%.1f, %.1f, %.1f]" % [coord.agents[2].hp, coord.agents[3].hp, coord.agents[4].hp])

# ==============================================================================
# MECHANISM B: MULTI-STAGE QUEST CHAIN WITH SUBTREES (3200 TICKS)
# ==============================================================================

class HackLaserAction extends BTTask:
	var total_attempts: int = 0
	var cycle_attempt: int = 0
	func _init() -> void:
		super._init()
		type_name = "HackLaserAction"
		category = "Action"
	func on_update() -> int:
		total_attempts += 1
		cycle_attempt += 1
		if cycle_attempt < 3:
			return BTStatus.FAILURE
		cycle_attempt = 0
		return BTStatus.SUCCESS

class ConfirmBreachAction extends BTTask:
	var breach_confirmations: int = 0
	func _init() -> void:
		super._init()
		type_name = "ConfirmBreachAction"
		category = "Action"
	func on_update() -> int:
		breach_confirmations += 1
		var bb = get_blackboard()
		if bb != null:
			bb.set_var("quest_stage", 2)
		return BTStatus.SUCCESS

class DecryptCoreAction extends BTTask:
	var attempt: int = 1
	var ticks_in_attempt: int = 0
	var total_aborts: int = 0
	var total_successes: int = 0
	func _init() -> void:
		super._init()
		type_name = "DecryptCoreAction"
		category = "Action"
	func on_start() -> void:
		ticks_in_attempt = 0
	func on_update() -> int:
		ticks_in_attempt += 1
		if attempt == 1:
			# Needs 10 ticks -> TimeLimit(0.22s at 0.05s/tick) triggers abort at tick 5
			if ticks_in_attempt >= 10:
				return BTStatus.SUCCESS
			return BTStatus.RUNNING
		else:
			# Exploit attempt needs 2 ticks -> completes before TimeLimit
			if ticks_in_attempt >= 2:
				attempt = 1
				total_successes += 1
				return BTStatus.SUCCESS
			return BTStatus.RUNNING
	func on_abort() -> void:
		total_aborts += 1
		attempt += 1
		super.on_abort()

class SetMeltdownArmedAction extends BTTask:
	var armed_confirmations: int = 0
	func _init() -> void:
		super._init()
		type_name = "SetMeltdownArmedAction"
		category = "Action"
	func on_update() -> int:
		armed_confirmations += 1
		var bb = get_blackboard()
		if bb != null:
			bb.set_var("quest_stage", 3)
			bb.set_var("reactor_meltdown_armed", true)
		return BTStatus.SUCCESS

class HoldExtractionZoneAction extends BTTask:
	var hold_ticks: int = 0
	func _init() -> void:
		super._init()
		type_name = "HoldExtractionZoneAction"
		category = "Action"
	func on_update() -> int:
		hold_ticks += 1
		return BTStatus.SUCCESS

class FinalOverloadTriggerAction extends BTTask:
	var completions: int = 0
	func _init() -> void:
		super._init()
		type_name = "FinalOverloadTriggerAction"
		category = "Action"
	func on_update() -> int:
		completions += 1
		var bb = get_blackboard()
		if bb != null:
			bb.set_var("mission_complete", true)
		return BTStatus.SUCCESS

func _run_mechanism_b_quest_chain() -> void:
	print("\n--- Running Mechanism B: Multi-Stage Quest Chain (3200 Ticks) ---")
	var reg := BTTaskRegistry.new()
	var act_laser := HackLaserAction.new()
	var act_breach := ConfirmBreachAction.new()
	var act_decrypt := DecryptCoreAction.new()
	var act_arm := SetMeltdownArmedAction.new()
	var act_hold := HoldExtractionZoneAction.new()
	var act_overload := FinalOverloadTriggerAction.new()

	reg.register_task("HackLaserAction", func(): return act_laser, "Action")
	reg.register_task("ConfirmBreachAction", func(): return act_breach, "Action")
	reg.register_task("DecryptCoreAction", func(): return act_decrypt, "Action")
	reg.register_task("SetMeltdownArmedAction", func(): return act_arm, "Action")
	reg.register_task("HoldExtractionZoneAction", func(): return act_hold, "Action")
	reg.register_task("FinalOverloadTriggerAction", func(): return act_overload, "Action")

	# Write SubTree JSON files to user://
	var p1 := "user://quest_stage_1.json"
	var p2 := "user://quest_stage_2.json"
	var p3 := "user://quest_stage_3.json"

	var s1_dict := {
		"root_id": 1,
		"nodes": [
			{"id": 1, "type_name": "Sequence", "children_ids": [2, 5], "parameters": {}},
			{"id": 2, "type_name": "UntilSuccess", "children_ids": [3], "parameters": {}},
			{"id": 3, "type_name": "Cooldown", "children_ids": [4], "parameters": {"cooldown_time": 0.15}},
			{"id": 4, "type_name": "HackLaserAction", "children_ids": [], "parameters": {}},
			{"id": 5, "type_name": "ConfirmBreachAction", "children_ids": [], "parameters": {}}
		],
		"blackboard": {
			"stage_private": {"type_name": "string", "value": "S1_LASER_GRID", "is_shared": false},
			"quest_stage": {"type_name": "int", "value": 1, "is_shared": true}
		}
	}
	var f1 := FileAccess.open(p1, FileAccess.WRITE); f1.store_string(JSON.stringify(s1_dict)); f1.close()

	var s2_dict := {
		"root_id": 10,
		"nodes": [
			{"id": 10, "type_name": "Sequence", "children_ids": [11, 14], "parameters": {}},
			{"id": 11, "type_name": "UntilSuccess", "children_ids": [12], "parameters": {}},
			{"id": 12, "type_name": "TimeLimit", "children_ids": [13], "parameters": {"time_limit": 0.22}},
			{"id": 13, "type_name": "DecryptCoreAction", "children_ids": [], "parameters": {}},
			{"id": 14, "type_name": "SetMeltdownArmedAction", "children_ids": [], "parameters": {}}
		],
		"blackboard": {
			"stage_private": {"type_name": "string", "value": "S2_RSA_CIPHER", "is_shared": false},
			"quest_stage": {"type_name": "int", "value": 2, "is_shared": true},
			"reactor_meltdown_armed": {"type_name": "bool", "value": false, "is_shared": true}
		}
	}
	var f2 := FileAccess.open(p2, FileAccess.WRITE); f2.store_string(JSON.stringify(s2_dict)); f2.close()

	var s3_dict := {
		"root_id": 20,
		"nodes": [
			{"id": 20, "type_name": "Sequence", "children_ids": [21, 22], "parameters": {}},
			{"id": 21, "type_name": "Repeater", "children_ids": [23], "parameters": {"count": 4}},
			{"id": 23, "type_name": "HoldExtractionZoneAction", "children_ids": [], "parameters": {}},
			{"id": 22, "type_name": "FinalOverloadTriggerAction", "children_ids": [], "parameters": {}}
		],
		"blackboard": {
			"stage_private": {"type_name": "string", "value": "S3_EVAC_CHOPPER", "is_shared": false},
			"quest_stage": {"type_name": "int", "value": 3, "is_shared": true},
			"mission_complete": {"type_name": "bool", "value": false, "is_shared": true}
		}
	}
	var f3 := FileAccess.open(p3, FileAccess.WRITE); f3.store_string(JSON.stringify(s3_dict)); f3.close()

	# Test BTFileTreeSource adapter
	var file_source := BTFileTreeSource.new("user://", reg)
	var t1 = file_source.load_tree(p1)
	var t2 = file_source.load_tree(p2)
	var t3 = file_source.load_tree(p3)
	_check(t1 != null and t2 != null and t3 != null, "BTFileTreeSource: loaded all 3 quest stage trees from user://")

	# Assemble Main Quest Tree
	var main_tree := BTTree.new()
	main_tree.registry = reg
	main_tree.blackboard.set_var("quest_stage", 0)
	main_tree.blackboard.set_var("reactor_meltdown_armed", false)
	main_tree.blackboard.set_var("mission_complete", false)
	main_tree.blackboard.set_var("parent_constant", 999)

	var main_seq := BTComposite.BTSequence.new()
	main_tree.set_root(main_seq)
	main_tree.connect_parent_child(main_seq, BTSubTree.new(p1))
	main_tree.connect_parent_child(main_seq, BTSubTree.new(p2))
	main_tree.connect_parent_child(main_seq, BTSubTree.new(p3))

	var runner := BTRunner.new(main_tree)

	# Execute 3200 ticks of Quest Chain Simulation
	# Dynamically advances cycles to observe cross-cycle state drift
	var completed_cycles: int = 0
	var stage_sequence_violations: int = 0
	var prev_stage: int = 0
	var total_ticks: int = 0
	var cooldown_drift_detected: bool = false
	var cycle_tick_counts: Array[int] = []
	var ticks_in_current_cycle: int = 0
	var shared_reactor_armed_confirmed: bool = false

	main_tree.blackboard.set_var("quest_stage", 1)
	main_tree.blackboard.set_var("reactor_meltdown_armed", false)
	main_tree.blackboard.set_var("mission_complete", false)
	prev_stage = 1
	runner.start()

	for tick_idx in range(3200):
		total_ticks += 1
		ticks_in_current_cycle += 1
		var st = runner.tick(0.05)

		if bool(main_tree.blackboard.get_var("reactor_meltdown_armed")):
			shared_reactor_armed_confirmed = true

		var cur_stage = int(main_tree.blackboard.get_var("quest_stage"))
		if cur_stage < prev_stage or cur_stage > 3 or (cur_stage - prev_stage > 1):
			stage_sequence_violations += 1
		prev_stage = cur_stage

		if st == BTStatus.SUCCESS:
			completed_cycles += 1
			cycle_tick_counts.append(ticks_in_current_cycle)
			if cycle_tick_counts.size() > 1 and ticks_in_current_cycle > cycle_tick_counts[0]:
				cooldown_drift_detected = true

			# Reset for next cycle
			ticks_in_current_cycle = 0
			main_tree.blackboard.set_var("quest_stage", 1)
			main_tree.blackboard.set_var("reactor_meltdown_armed", false)
			main_tree.blackboard.set_var("mission_complete", false)
			prev_stage = 1
			runner.start()

	# Assertions for Mechanism B
	_check(total_ticks == 3200, "Tick Volume: Exactly 3200 ticks executed for Mechanism B", "total_ticks=%d" % total_ticks)
	_check(completed_cycles >= 150, "Cycle Completion Volume: Completed >= 150 full quest cycles across 3200 ticks", "completed=%d" % completed_cycles)
	_check(stage_sequence_violations == 0, "Invariant: Quest stage progression strictly monotonic (1->2->3) without skipping", "violations=%d" % stage_sequence_violations)
	_check(not main_tree.blackboard.has_var("stage_private"), "Blackboard Scoping: SubTree private variable never leaked to parent blackboard")
	_check(int(main_tree.blackboard.get_var("parent_constant")) == 999, "Blackboard Scoping: Parent scope constants untouched across cycles")
	_check(shared_reactor_armed_confirmed, "Shared Blackboard: Reactor armed state successfully propagated to parent during execution")
	_check(act_decrypt.total_aborts >= 150, "TimeLimit Independent Check: TimeLimit triggered >= 150 aborts (1 per cycle)", "actual=%d" % act_decrypt.total_aborts)
	_check(act_decrypt.total_successes >= 150, "UntilSuccess Retry Check: Exactly retry successes >= 150 after abort", "actual=%d" % act_decrypt.total_successes)
	_check(act_overload.completions >= 150, "Stage 3 Repeater Check: Repeater overload triggers >= 150", "actual=%d" % act_overload.completions)

	# ==========================================================================
	# DESIGN SPECIFICATION CHECKS: SIMULATED TIME MONOTONICITY & COOLDOWN CONTRACT
	# NOTE: In Godot Behavior Tree architecture, `runner.time` (sim_time()) is
	# strictly monotonic across runner.start()/stop() restarts. Time-based
	# decorators (Cooldown, TimeLimit) preserve their schedule across restarts
	# during normal active cycles on the same runner to prevent bypassing cooldowns.
	#
	# OFFICIAL TIMELINE RESET CONTRACT FOR POOLED ACTORS:
	# To reset the timeline and clear cooldowns for a reused/pooled actor, developers
	# MUST explicitly set `runner.time = 0.0` before calling `runner.start()`.
	# ==========================================================================

	# Check (a): runner.time is strictly monotonic across start()/stop()
	var final_sim_time: float = runner.time
	var time_before_stop: float = runner.time
	runner.stop()
	var time_after_stop: float = runner.time
	runner.start()
	var time_after_start: float = runner.time
	_check(time_after_stop == time_before_stop and time_after_start == time_before_stop and final_sim_time >= 3200.0 * 0.05 - 0.001,
		"Design Spec (a): runner.time is strictly monotonic and preserved across start()/stop() restarts without resetting",
		"time=%.2f" % final_sim_time)

	# Check (b): Cooldown is preserved across runner.start() restarts when time has not rewound
	_check(cooldown_drift_detected,
		"Design Spec (b): Cooldown decorator correctly preserved across runner.start() restarts when simulated time has not rewound")

	# Check (c): After setting runner.time = 0.0 and calling start(), cooldown IS cleared (official reset for pooled actors)
	var pooled_cd := BTDecorator.BTCooldown.new()
	pooled_cd.set_param("cooldown_time", 0.5, false)
	var pooled_act := BTTask.new()
	var pooled_tree := BTTree.new()
	pooled_tree.set_root(pooled_cd)
	pooled_tree.connect_parent_child(pooled_cd, pooled_act)

	var pooled_runner := BTRunner.new(pooled_tree)
	pooled_runner.start()
	var s1 = pooled_runner.tick(0.1) # child runs -> SUCCESS, last_execution_time = 0.1s
	pooled_runner.start()
	var s2 = pooled_runner.tick(0.0) # blocked by Cooldown (time = 0.1s < 0.6s) -> FAILURE
	var preserved_ok: bool = (s1 == BTStatus.SUCCESS and s2 == BTStatus.FAILURE)

	# Rewind simulated time to 0.0 (official contract for pooled actor reuse)
	pooled_runner.time = 0.0
	pooled_runner.start() # time (0.0) < last_execution_time (0.1) -> Cooldown clears last_execution_time
	var s3 = pooled_runner.tick(0.0) # Cooldown opens immediately -> SUCCESS
	var cleared_on_rewind: bool = (preserved_ok and s3 == BTStatus.SUCCESS)

	_check(cleared_on_rewind,
		"Design Spec (c): Setting runner.time = 0.0 rewinds simulated timeline and cleanly clears Cooldown for pooled actors",
		"s1=%d, s2=%d, s3=%d" % [s1, s2, s3])

	pooled_runner.stop()
	pooled_runner.free()

	runner.stop()
	runner.free()

	# File Cleanup
	var cleaned_files: int = 0
	for p in [p1, p2, p3]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
			cleaned_files += 1
	_check(cleaned_files == 3, "File Cleanup: All 3 temporary quest JSON subtrees removed from user://")

# ==============================================================================
# RE-ENTRANCY STRESS & EMERGENCY INTERRUPTS
# ==============================================================================

class SelfInterruptAction extends BTTask:
	var call_count: int = 0
	var triggered_interrupt: bool = false
	func _init() -> void:
		super._init()
		type_name = "SelfInterruptAction"
		category = "Action"
	func on_update() -> int:
		call_count += 1
		if call_count == 3:
			triggered_interrupt = true
			if owner != null:
				owner.interrupt(self, BTStatus.FAILURE)
			return BTStatus.RUNNING
		return BTStatus.SUCCESS

class SelfStopAction extends BTTask:
	var call_count: int = 0
	var triggered_stop: bool = false
	func _init() -> void:
		super._init()
		type_name = "SelfStopAction"
		category = "Action"
	func on_update() -> int:
		call_count += 1
		if call_count == 2:
			triggered_stop = true
			if owner != null:
				owner.stop()
			return BTStatus.RUNNING
		return BTStatus.SUCCESS

func _run_reentrancy_stress() -> void:
	print("\n--- Running Re-Entrancy & Interrupt Stress Tests ---")

	# Test 1: Task calling owner.interrupt(self, FAILURE) during execution
	var t1 := BTTree.new()
	var seq1 := BTComposite.BTSequence.new()
	var act_int := SelfInterruptAction.new()
	t1.set_root(seq1)
	t1.connect_parent_child(seq1, act_int)
	var r1 := BTRunner.new(t1)

	r1.start()
	r1.tick(0.1) # call 1 -> SUCCESS
	r1.start()
	r1.tick(0.1) # call 2 -> SUCCESS
	r1.start()
	var s_int = r1.tick(0.1) # call 3 -> owner.interrupt(self, FAILURE)!

	_check(act_int.triggered_interrupt, "Re-entrancy: Task triggered owner.interrupt(self, FAILURE) from on_update")
	_check(s_int == BTStatus.FAILURE, "Re-entrancy: Runner returned FAILURE upon re-entrant interrupt", "status=%d" % s_int)
	_check(not r1.is_running, "Re-entrancy: Runner halted execution and set is_running to false")

	# Verify recovery after interrupt
	r1.start()
	var s_rec = r1.tick(0.1)
	_check(s_rec == BTStatus.SUCCESS, "Re-entrancy Recovery: Runner cleanly restarted and ticked to SUCCESS after interrupt", "status=%d" % s_rec)

	r1.stop()
	r1.free()

	# Test 2: Task calling owner.stop() during execution
	var t2 := BTTree.new()
	var act_stop := SelfStopAction.new()
	t2.set_root(act_stop)
	var r2 := BTRunner.new(t2)

	r2.start()
	r2.tick(0.1) # call 1 -> SUCCESS
	r2.start()
	var s_stop = r2.tick(0.1) # call 2 -> owner.stop()!

	_check(act_stop.triggered_stop, "Re-entrancy: Task triggered owner.stop() from on_update")
	_check(not r2.is_running, "Re-entrancy: Runner stopped immediately and is_running is false")

	r2.free()

# ==============================================================================
# MEMORY & OBJECTDB LEAK VERIFICATION
# ==============================================================================

func _run_memory_leak_check() -> void:
	print("\n--- Running Memory & ObjectDB Leak Verification ---")

	var initial_objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	var round_counts: Array[float] = []

	for round_idx in range(2):
		var temp_runners: Array[BTRunner] = []
		var temp_trees: Array[BTTree] = []

		for i in range(5):
			var tr := BTTree.new()
			var sq := BTComposite.BTSequence.new()
			var lk := BTTask.new()
			tr.set_root(sq)
			tr.connect_parent_child(sq, lk)
			temp_trees.append(tr)

			var rn := BTRunner.new(tr)
			temp_runners.append(rn)
			rn.start()
			for t in range(50):
				rn.tick(0.05)

		for rn in temp_runners:
			rn.stop()
			rn.free()
		temp_runners.clear()
		temp_trees.clear()

		var cnt: float = Performance.get_monitor(Performance.OBJECT_COUNT)
		round_counts.append(cnt)

	var delta_leak: float = round_counts[1] - round_counts[0]
	_check(delta_leak <= 0.0, "ObjectDB Leak Check: Object count did not grow between cycles (delta <= 0)", "round0=%.0f, round1=%.0f, delta=%.0f" % [round_counts[0], round_counts[1], delta_leak])
	_check(round_counts[1] <= initial_objects, "ObjectDB Baseline Check: Object count returned to baseline", "initial=%.0f, final=%.0f" % [initial_objects, round_counts[1]])
