extends Control
## Complex Demo: RTS Commander AI with Large-Scale Behavior Tree & Combat Micro Subtrees.
##
## Architectural Showcase:
## - Strategic Commander Tree (>= 800 nodes up to 2000+ nodes) managing base economy, production, and high-level strategy.
## - Military Layer: 4 independent Squad BTRunners executing combat micro subtrees via BTSubTree.
## - Shared Blackboard coordination: mutual exclusion on target assignments (no two squads focus the same enemy).
## - Reactive Transitions: Army-vs-Enemy strength drives dynamic shifts (Expand / Defend / Push / Harass / Retreat).
## - Live Performance Metrics: µs/tick over rolling window, executions vs budget cap, tree node totals.

const HUB_SCENE_PATH := "res://demo/complex/complex_demo.tscn"
const SQUAD_SCENE_PATH := "res://demo/complex/squad_demo.tscn"
const BOSS_SCENE_PATH := "res://demo/complex/boss_demo.tscn"
const GUARD_SCENE_PATH := "res://demo/complex/guard_stealth_demo.tscn"

const SQUAD_MICRO_TREE_PATH := "res://demo/complex/rts_data/squad_micro_tree.json"
const COMMANDER_800_TREE_PATH := "res://demo/complex/rts_data/commander_800_tree.json"

enum StrategicStance { RETREAT = 0, DEFEND = 1, HARASS = 2, EXPAND = 3, PUSH = 4 }

# ---------------------------------------------------------------- Simulation Models

class EnemyUnit extends RefCounted:
	var id: int
	var pos: Vector2
	var hp: float = 60.0
	var max_hp: float = 60.0
	var dps: float = 6.0
	var is_alive: bool = true
	var speed: float = 18.0

	func _init(p_id: int, p_pos: Vector2, p_hp: float = 60.0, p_dps: float = 6.0) -> void:
		id = p_id
		pos = p_pos
		hp = p_hp
		max_hp = p_hp
		dps = p_dps

class SquadAgent extends RefCounted:
	var id: int
	var pos: Vector2
	var target_pos: Vector2
	var hp: float = 100.0
	var max_hp: float = 100.0
	var dps: float = 12.0
	var range_dist: float = 55.0
	var is_alive: bool = true
	var current_action: String = "Idle"
	var assigned_target_id: int = -1
	var color: Color
	var runner: BTRunner
	var tree: BTTree
	var subtree_task: BTSubTree

	func _init(p_id: int, p_pos: Vector2, p_color: Color) -> void:
		id = p_id
		pos = p_pos
		target_pos = p_pos
		color = p_color

# ---------------------------------------------------------------- Instrumented Tasks for Coverage & Lifecycle

class RTSInstrumentedTask extends BTTask:
	static var global_starts: Dictionary = {} # task_id -> int
	static var global_ends: Dictionary = {} # task_id -> int
	static var global_aborts: Dictionary = {} # task_id -> int
	static var global_updates: Dictionary = {} # task_id -> int
	static var live_instances: int = 0

	var starts_count: int = 0
	var ends_count: int = 0
	var aborts_count: int = 0
	var updates_count: int = 0
	var _was_aborted: bool = false

	func _init() -> void:
		super._init()
		live_instances += 1

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			live_instances -= 1

	func on_start() -> void:
		starts_count += 1
		global_starts[id] = global_starts.get(id, 0) + 1
		_was_aborted = false
		super.on_start()

	func on_end() -> void:
		if not _was_aborted:
			ends_count += 1
			global_ends[id] = global_ends.get(id, 0) + 1
		super.on_end()

	func on_abort() -> void:
		_was_aborted = true
		aborts_count += 1
		global_aborts[id] = global_aborts.get(id, 0) + 1
		super.on_abort()

	func on_update() -> int:
		updates_count += 1
		global_updates[id] = global_updates.get(id, 0) + 1
		return BTStatus.SUCCESS

# ---------------------------------------------------------------- Custom Composites for RTS Commander

class RoundRobinSelector extends BTComposite:
	var rr_cursor: int = 0
	var _children_tried: int = 0

	func _init() -> void:
		super._init()
		type_name = "RoundRobinSelector"
		friendly_name = "RoundRobinSelector"
		category = "Composite"

	func on_start() -> void:
		super.on_start()
		if children.is_empty():
			last_status = BTStatus.FAILURE
			return
		rr_cursor = (rr_cursor + 1) % children.size()
		current_child_index = rr_cursor
		_children_tried = 0
		last_status = BTStatus.RUNNING

	func can_execute() -> bool:
		return _children_tried < children.size() and last_status == BTStatus.RUNNING

	func on_child_executed(child_index: int, child_status: int) -> void:
		super.on_child_executed(child_index, child_status)
		_children_tried += 1
		if child_status == BTStatus.SUCCESS:
			last_status = BTStatus.SUCCESS
		elif child_status == BTStatus.FAILURE:
			if _children_tried >= children.size():
				last_status = BTStatus.FAILURE
			else:
				current_child_index = (current_child_index + 1) % children.size()
		elif child_status == BTStatus.RUNNING:
			last_status = BTStatus.RUNNING

	func override_status(_status: int) -> int:
		return last_status


# --- Commander Tree Specific Tasks ---

class CondResourceCheck extends RTSInstrumentedTask:
	var demo_ref: Control
	var threshold: float
	var res_type: String

	func _init(p_demo: Control = null, p_type: String = "minerals", p_thresh: float = 50.0) -> void:
		super._init()
		demo_ref = p_demo
		res_type = p_type
		threshold = p_thresh
		category = "Condition"
		type_name = "CondResourceCheck"

	func evaluate_condition(_runner: BTRunner) -> int:
		if demo_ref == null: return BTStatus.FAILURE
		var val: float = demo_ref.minerals if res_type == "minerals" else demo_ref.energy
		return BTStatus.SUCCESS if val >= threshold else BTStatus.FAILURE

	func on_update() -> int:
		super.on_update()
		return evaluate_condition(owner as BTRunner)

class ActionProduceUnit extends RTSInstrumentedTask:
	var demo_ref: Control
	var unit_type: String
	var cost_min: float
	var cost_eng: float
	var build_ticks: int
	var current_ticks: int = 0

	func _init(p_demo: Control = null, p_unit: String = "Marine", p_min: float = 20.0, p_eng: float = 0.0, p_ticks: int = 1) -> void:
		super._init()
		demo_ref = p_demo
		unit_type = p_unit
		cost_min = p_min
		cost_eng = p_eng
		build_ticks = p_ticks
		category = "Action"
		type_name = "ActionProduceUnit"

	func on_start() -> void:
		super.on_start()
		current_ticks = build_ticks
		if demo_ref != null and demo_ref.minerals >= cost_min and demo_ref.energy >= cost_eng:
			demo_ref.minerals -= cost_min
			demo_ref.energy -= cost_eng
			demo_ref.production_queue.append(unit_type)

	func on_update() -> int:
		super.on_update()
		current_ticks -= 1
		if current_ticks <= 0:
			if demo_ref != null:
				demo_ref.production_queue.erase(unit_type)
				demo_ref.army_strength += 10.0
				demo_ref.total_units_produced += 1
			return BTStatus.SUCCESS
		return BTStatus.RUNNING

class ActionTechUpgrade extends RTSInstrumentedTask:
	var demo_ref: Control
	var tech_name: String
	var cost_min: float
	var cost_eng: float

	func _init(p_demo: Control = null, p_tech: String = "Weapons1", p_min: float = 40.0, p_eng: float = 20.0) -> void:
		super._init()
		demo_ref = p_demo
		tech_name = p_tech
		cost_min = p_min
		cost_eng = p_eng
		category = "Action"
		type_name = "ActionTechUpgrade"

	func on_update() -> int:
		super.on_update()
		if demo_ref != null:
			if not demo_ref.tech_unlocked.has(tech_name) and demo_ref.minerals >= cost_min and demo_ref.energy >= cost_eng:
				demo_ref.minerals -= cost_min
				demo_ref.energy -= cost_eng
				demo_ref.tech_unlocked[tech_name] = true
				return BTStatus.SUCCESS
		return BTStatus.SUCCESS

class CondStrategicStance extends RTSInstrumentedTask:
	var demo_ref: Control
	var target_stance: int

	func _init(p_demo: Control = null, p_stance: int = 0) -> void:
		super._init()
		demo_ref = p_demo
		target_stance = p_stance
		category = "Condition"
		type_name = "CondStrategicStance"

	func evaluate_condition(_runner: BTRunner) -> int:
		if demo_ref == null: return BTStatus.FAILURE
		return BTStatus.SUCCESS if int(demo_ref.current_stance) == target_stance else BTStatus.FAILURE

	func on_update() -> int:
		super.on_update()
		return evaluate_condition(owner as BTRunner)

class ActionExecuteStrategicOrder extends RTSInstrumentedTask:
	var demo_ref: Control
	var order_type: String

	func _init(p_demo: Control = null, p_order: String = "Patrol") -> void:
		super._init()
		demo_ref = p_demo
		order_type = p_order
		category = "Action"
		type_name = "ActionExecuteStrategicOrder"

	func on_update() -> int:
		super.on_update()
		if demo_ref != null:
			demo_ref.last_strategic_order = order_type
		return BTStatus.SUCCESS

# --- Squad Combat Micro Tasks ---

class CondMicroHealthLow extends RTSInstrumentedTask:
	var squad: SquadAgent

	func _init(p_squad: SquadAgent = null) -> void:
		super._init()
		squad = p_squad
		category = "Condition"
		type_name = "CondMicroHealthLow"

	func evaluate_condition(_runner: BTRunner) -> int:
		if squad == null or not squad.is_alive: return BTStatus.FAILURE
		return BTStatus.SUCCESS if (squad.hp / squad.max_hp) <= 0.35 else BTStatus.FAILURE

	func on_update() -> int:
		super.on_update()
		return evaluate_condition(owner as BTRunner)

class ActionMicroRetreatHeal extends RTSInstrumentedTask:
	var demo_ref: Control
	var squad: SquadAgent

	func _init(p_demo: Control = null, p_squad: SquadAgent = null) -> void:
		super._init()
		demo_ref = p_demo
		squad = p_squad
		category = "Action"
		type_name = "ActionMicroRetreatHeal"

	func on_start() -> void:
		super.on_start()
		if squad != null:
			squad.current_action = "Retreat & Repair"
			if demo_ref != null and squad.assigned_target_id != -1:
				demo_ref.release_target(squad.id, squad.assigned_target_id)
				squad.assigned_target_id = -1

	func on_update() -> int:
		super.on_update()
		if squad == null or not squad.is_alive: return BTStatus.FAILURE
		# Move towards base (left)
		squad.target_pos = Vector2(80.0, 160.0 + squad.id * 50.0)
		squad.hp = minf(squad.max_hp, squad.hp + 12.0)
		if squad.hp >= squad.max_hp * 0.9:
			return BTStatus.SUCCESS
		return BTStatus.RUNNING

class CondMicroOutnumbered extends RTSInstrumentedTask:
	var demo_ref: Control
	var squad: SquadAgent

	func _init(p_demo: Control = null, p_squad: SquadAgent = null) -> void:
		super._init()
		demo_ref = p_demo
		squad = p_squad
		category = "Condition"
		type_name = "CondMicroOutnumbered"

	func evaluate_condition(_runner: BTRunner) -> int:
		if demo_ref == null or squad == null or not squad.is_alive: return BTStatus.FAILURE
		var nearby_enemies := 0
		for e in demo_ref.enemies:
			if e.is_alive and squad.pos.distance_to(e.pos) < 140.0:
				nearby_enemies += 1
		return BTStatus.SUCCESS if nearby_enemies >= 3 else BTStatus.FAILURE

	func on_update() -> int:
		super.on_update()
		return evaluate_condition(owner as BTRunner)

class ActionMicroKite extends RTSInstrumentedTask:
	var demo_ref: Control
	var squad: SquadAgent

	func _init(p_demo: Control = null, p_squad: SquadAgent = null) -> void:
		super._init()
		demo_ref = p_demo
		squad = p_squad
		category = "Action"
		type_name = "ActionMicroKite"

	func on_start() -> void:
		super.on_start()
		if squad != null:
			squad.current_action = "Kiting Enemies"

	func on_update() -> int:
		super.on_update()
		if squad == null or not squad.is_alive: return BTStatus.FAILURE
		squad.target_pos = squad.pos + Vector2(-30.0, 0.0)
		return BTStatus.SUCCESS

class CondMicroHasTarget extends RTSInstrumentedTask:
	var demo_ref: Control
	var squad: SquadAgent

	func _init(p_demo: Control = null, p_squad: SquadAgent = null) -> void:
		super._init()
		demo_ref = p_demo
		squad = p_squad
		category = "Condition"
		type_name = "CondMicroHasTarget"

	func evaluate_condition(_runner: BTRunner) -> int:
		if demo_ref == null or squad == null or not squad.is_alive: return BTStatus.FAILURE
		if squad.assigned_target_id != -1:
			var tgt = demo_ref.get_enemy_by_id(squad.assigned_target_id)
			if tgt != null and tgt.is_alive:
				return BTStatus.SUCCESS
		var best_tgt = demo_ref.claim_lowest_hp_target(squad.id, squad.pos)
		if best_tgt != null:
			squad.assigned_target_id = best_tgt.id
			return BTStatus.SUCCESS
		return BTStatus.FAILURE

	func on_update() -> int:
		super.on_update()
		return evaluate_condition(owner as BTRunner)

class ActionMicroFocusFire extends RTSInstrumentedTask:
	var demo_ref: Control
	var squad: SquadAgent

	func _init(p_demo: Control = null, p_squad: SquadAgent = null) -> void:
		super._init()
		demo_ref = p_demo
		squad = p_squad
		category = "Action"
		type_name = "ActionMicroFocusFire"

	func on_start() -> void:
		super.on_start()
		if squad != null:
			squad.current_action = "Focus Firing #%d" % squad.assigned_target_id

	func on_update() -> int:
		super.on_update()
		if demo_ref == null or squad == null or not squad.is_alive: return BTStatus.FAILURE
		var tgt = demo_ref.get_enemy_by_id(squad.assigned_target_id)
		if tgt == null or not tgt.is_alive:
			demo_ref.release_target(squad.id, squad.assigned_target_id)
			squad.assigned_target_id = -1
			return BTStatus.SUCCESS

		squad.target_pos = tgt.pos
		var dist = squad.pos.distance_to(tgt.pos)
		if dist <= squad.range_dist:
			tgt.hp -= squad.dps
			if tgt.hp <= 0.0:
				tgt.is_alive = false
				demo_ref.release_target(squad.id, squad.assigned_target_id)
				squad.assigned_target_id = -1
				demo_ref.minerals += 25.0
				return BTStatus.SUCCESS
			return BTStatus.RUNNING
		else:
			return BTStatus.RUNNING

class ActionMicroEngage extends RTSInstrumentedTask:
	var demo_ref: Control
	var squad: SquadAgent

	func _init(p_demo: Control = null, p_squad: SquadAgent = null) -> void:
		super._init()
		demo_ref = p_demo
		squad = p_squad
		category = "Action"
		type_name = "ActionMicroEngage"

	func on_start() -> void:
		super.on_start()
		if squad != null:
			squad.current_action = "Advancing to Engage"

	func on_update() -> int:
		super.on_update()
		if demo_ref == null or squad == null or not squad.is_alive: return BTStatus.FAILURE
		squad.target_pos = Vector2(480.0, 180.0 + squad.id * 40.0)
		return BTStatus.SUCCESS

class ActionMicroHoldFormation extends RTSInstrumentedTask:
	var demo_ref: Control
	var squad: SquadAgent

	func _init(p_demo: Control = null, p_squad: SquadAgent = null) -> void:
		super._init()
		demo_ref = p_demo
		squad = p_squad
		category = "Action"
		type_name = "ActionMicroHoldFormation"

	func on_start() -> void:
		super.on_start()
		if squad != null:
			squad.current_action = "Holding Formation"

	func on_update() -> int:
		super.on_update()
		return BTStatus.SUCCESS

# ---------------------------------------------------------------- State & Variables

# Resources & Production
var minerals: float = 200.0
var energy: float = 100.0
var army_strength: float = 40.0
var enemy_strength: float = 0.0
var current_stance: StrategicStance = StrategicStance.EXPAND
var production_queue: Array[String] = []
var tech_unlocked: Dictionary = {}
var total_units_produced: int = 0
var last_strategic_order: String = "None"

# Military Layer
var squads: Array[SquadAgent] = []
var enemies: Array[EnemyUnit] = []
var shared_bb: BTBlackboard = null
var commander_tree: BTTree = null
var commander_runner: BTRunner = null
var target_claims: Dictionary = {} # squad_id -> enemy_id
var target_mutex_violations: int = 0

# Ticking & Simulation Loop
var tick_count: int = 0
var auto_tick: bool = false
var tick_timer: float = 0.0
var tick_interval: float = 0.15
var sim_speed: float = 1.0
var enemy_spawn_timer: float = 0.0
var enemy_id_counter: int = 1
const EXECUTION_BUDGET_CAP: int = 150

# Performance Rolling Window
var perf_us_window: Array[float] = []
var perf_exec_window: Array[int] = []
var max_measured_us: float = 0.0
var max_measured_exec: int = 0

# UI Controls
var field_rect: Control = null
var stance_label: Label = null
var res_label: Label = null
var perf_label: Label = null
var squad_cards_vbox: VBoxContainer = null
var btn_auto_tick: Button = null

# ---------------------------------------------------------------- Lifecycle & Setup

func _ready() -> void:
	_init_simulation()
	if DisplayServer.get_name() == "headless":
		auto_tick = false
	else:
		auto_tick = true
	_build_ui()
	_update_ui_state()

func _physics_process(delta: float) -> void:
	if not auto_tick:
		return
	tick_timer += delta * sim_speed
	if tick_timer >= tick_interval:
		tick_timer = 0.0
		tick_all(tick_interval)

func _exit_tree() -> void:
	_cleanup_runners()

func _cleanup_runners() -> void:
	if commander_runner != null and is_instance_valid(commander_runner):
		commander_runner.stop()
		commander_runner.free()
		commander_runner = null
	commander_tree = null

	for s in squads:
		if s.runner != null and is_instance_valid(s.runner):
			s.runner.stop()
			s.runner.free()
			s.runner = null
		s.tree = null
		s.subtree_task = null
	squads.clear()
	enemies.clear()
	target_claims.clear()

func _init_simulation(commander_node_target: int = 850) -> void:
	_cleanup_runners()
	minerals = 250.0
	energy = 120.0
	army_strength = 60.0
	enemy_strength = 0.0
	current_stance = StrategicStance.EXPAND
	production_queue.clear()
	tech_unlocked.clear()
	total_units_produced = 0
	last_strategic_order = "Initialize Base"
	target_mutex_violations = 0
	tick_count = 0
	enemy_id_counter = 1
	perf_us_window.clear()
	perf_exec_window.clear()

	# 1. Setup Shared Blackboard
	shared_bb = BTBlackboard.new()
	shared_bb.set_var("strategic_stance", int(current_stance))
	shared_bb.set_var("army_strength", army_strength)
	shared_bb.set_var("enemy_strength", enemy_strength)
	shared_bb.set_var("target_claims", target_claims)

	# 2. Ensure Micro Subtree JSON exists
	_ensure_micro_subtree_json()

	# 3. Create 4 Squad Agents with Micro Subtrees
	var colors := [Color(0.2, 0.6, 1.0), Color(0.1, 0.9, 0.5), Color(1.0, 0.6, 0.1), Color(0.8, 0.3, 0.9)]
	for i in range(4):
		var sq := SquadAgent.new(i, Vector2(100.0, 140.0 + i * 65.0), colors[i])
		sq.tree = _build_squad_micro_tree(sq, shared_bb)
		sq.runner = BTRunner.new(sq.tree)
		sq.runner.max_task_executions_per_tick = EXECUTION_BUDGET_CAP
		add_child(sq.runner)
		sq.runner.set_process(false)
		sq.runner.start()
		squads.append(sq)

	# 4. Generate & Setup Commander Tree
	commander_tree = _generate_commander_tree(commander_node_target)
	commander_runner = BTRunner.new(commander_tree)
	commander_runner.max_task_executions_per_tick = EXECUTION_BUDGET_CAP
	add_child(commander_runner)
	commander_runner.set_process(false)
	commander_runner.start()

# ---------------------------------------------------------------- Tree Generation

func _ensure_micro_subtree_json() -> void:
	if FileAccess.file_exists(SQUAD_MICRO_TREE_PATH):
		return
	var dir := SQUAD_MICRO_TREE_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var m_tree := BTTree.new()
	m_tree.tree_name = "SquadMicroTree"
	var m_root := BTComposite.BTSelector.new()
	m_root.id = 1
	m_root.set_abort_type(BTComposite.AbortType.LOWER_PRIORITY)
	m_tree.set_root(m_root)

	var cid := 2
	# 1. Retreat
	var r_seq := BTComposite.BTSequence.new(); r_seq.id = cid; cid += 1; m_tree.connect_parent_child(m_root, r_seq)
	var c_ret := BTTask.new(); c_ret.id = cid; cid += 1; c_ret.type_name = "CondMicroHealthLow"; c_ret.category = "Condition"; m_tree.connect_parent_child(r_seq, c_ret)
	var a_ret := BTTask.new(); a_ret.id = cid; cid += 1; a_ret.type_name = "ActionMicroRetreatHeal"; a_ret.category = "Action"; m_tree.connect_parent_child(r_seq, a_ret)
	# 2. Kite
	var k_seq := BTComposite.BTSequence.new(); k_seq.id = cid; cid += 1; m_tree.connect_parent_child(m_root, k_seq)
	var c_kite := BTTask.new(); c_kite.id = cid; cid += 1; c_kite.type_name = "CondMicroOutnumbered"; c_kite.category = "Condition"; m_tree.connect_parent_child(k_seq, c_kite)
	var a_kite := BTTask.new(); a_kite.id = cid; cid += 1; a_kite.type_name = "ActionMicroKite"; a_kite.category = "Action"; m_tree.connect_parent_child(k_seq, a_kite)
	# 3. Focus Fire
	var f_seq := BTComposite.BTSequence.new(); f_seq.id = cid; cid += 1; m_tree.connect_parent_child(m_root, f_seq)
	var c_foc := BTTask.new(); c_foc.id = cid; cid += 1; c_foc.type_name = "CondMicroHasTarget"; c_foc.category = "Condition"; m_tree.connect_parent_child(f_seq, c_foc)
	var a_foc := BTTask.new(); a_foc.id = cid; cid += 1; a_foc.type_name = "ActionMicroFocusFire"; a_foc.category = "Action"; m_tree.connect_parent_child(f_seq, a_foc)
	# 4. Engage
	var e_seq := BTComposite.BTSequence.new(); e_seq.id = cid; cid += 1; m_tree.connect_parent_child(m_root, e_seq)
	var a_eng := BTTask.new(); a_eng.id = cid; cid += 1; a_eng.type_name = "ActionMicroEngage"; a_eng.category = "Action"; m_tree.connect_parent_child(e_seq, a_eng)
	# 5. Hold
	var a_hld := BTTask.new(); a_hld.id = cid; cid += 1; a_hld.type_name = "ActionMicroHoldFormation"; a_hld.category = "Action"; m_tree.connect_parent_child(m_root, a_hld)

	var f := FileAccess.open(SQUAD_MICRO_TREE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(m_tree.to_dict(), "\t"))
		f.close()

func _build_squad_micro_tree(squad: SquadAgent, p_bb: BTBlackboard) -> BTTree:
	var tree := BTTree.new()
	tree.blackboard = p_bb

	var rep := BTDecorator.BTRepeater.new()
	rep.id = 1
	rep.repeat_forever = true
	tree.set_root(rep)

	var root_sel := BTComposite.BTSelector.new()
	root_sel.id = 2
	root_sel.set_abort_type(BTComposite.AbortType.LOWER_PRIORITY)
	tree.connect_parent_child(rep, root_sel)

	var cid := 3
	# Priority 1: Retreat & Heal
	var ret_seq := BTComposite.BTSequence.new(); ret_seq.id = cid; cid += 1
	ret_seq.set_abort_type(BTComposite.AbortType.SELF)
	var cond_ret := CondMicroHealthLow.new(squad); cond_ret.id = cid; cid += 1
	var act_ret := ActionMicroRetreatHeal.new(self, squad); act_ret.id = cid; cid += 1
	tree.connect_parent_child(root_sel, ret_seq)
	tree.connect_parent_child(ret_seq, cond_ret)
	tree.connect_parent_child(ret_seq, act_ret)

	# Priority 2: Kite when Outnumbered
	var kite_seq := BTComposite.BTSequence.new(); kite_seq.id = cid; cid += 1
	kite_seq.set_abort_type(BTComposite.AbortType.SELF)
	var cond_kite := CondMicroOutnumbered.new(self, squad); cond_kite.id = cid; cid += 1
	var act_kite := ActionMicroKite.new(self, squad); act_kite.id = cid; cid += 1
	tree.connect_parent_child(root_sel, kite_seq)
	tree.connect_parent_child(kite_seq, cond_kite)
	tree.connect_parent_child(kite_seq, act_kite)

	# Priority 3: Focus Fire Lowest HP
	var focus_seq := BTComposite.BTSequence.new(); focus_seq.id = cid; cid += 1
	focus_seq.set_abort_type(BTComposite.AbortType.SELF)
	var cond_foc := CondMicroHasTarget.new(self, squad); cond_foc.id = cid; cid += 1
	var act_foc := ActionMicroFocusFire.new(self, squad); act_foc.id = cid; cid += 1
	tree.connect_parent_child(root_sel, focus_seq)
	tree.connect_parent_child(focus_seq, cond_foc)
	tree.connect_parent_child(focus_seq, act_foc)

	# Priority 4: Advance & Engage
	var eng_seq := BTComposite.BTSequence.new(); eng_seq.id = cid; cid += 1
	var act_eng := ActionMicroEngage.new(self, squad); act_eng.id = cid; cid += 1
	tree.connect_parent_child(root_sel, eng_seq)
	tree.connect_parent_child(eng_seq, act_eng)

	# Priority 5: Hold Formation (Fallback)
	var act_hold := ActionMicroHoldFormation.new(self, squad); act_hold.id = cid; cid += 1
	tree.connect_parent_child(root_sel, act_hold)

	return tree

func _generate_commander_tree(target_nodes: int = 850) -> BTTree:
	var tree := BTTree.new()
	tree.tree_name = "RTS_Commander_%d" % target_nodes

	var rep := BTDecorator.BTRepeater.new()
	rep.id = 1
	rep.repeat_forever = true
	tree.set_root(rep)

	var root_sel := BTComposite.BTRandomSelector.new()
	root_sel.id = 2
	root_sel.friendly_name = "CommanderMasterSelector"
	tree.connect_parent_child(rep, root_sel)

	var cur_id := 3

	# -------------------------------------------------------------
	# Branch 1: High Priority Crisis Response (~32 nodes)
	# -------------------------------------------------------------
	var crisis_sel := BTComposite.BTRandomSelector.new()
	crisis_sel.id = cur_id; cur_id += 1
	crisis_sel.friendly_name = "EmergencyCrisisSelector"
	tree.connect_parent_child(root_sel, crisis_sel)

	for i in range(10):
		var c_seq := BTComposite.BTSequence.new()
		c_seq.id = cur_id; cur_id += 1
		c_seq.friendly_name = "CrisisProtocol_%d" % i
		tree.connect_parent_child(crisis_sel, c_seq)

		var cond := CondResourceCheck.new(self, "energy" if i % 2 == 0 else "minerals", 5.0 + i * 2.0)
		cond.id = cur_id; cur_id += 1
		cond.friendly_name = "CrisisCond_%d" % i
		tree.connect_parent_child(c_seq, cond)

		var act := ActionExecuteStrategicOrder.new(self, "CrisisOrder_%d" % i)
		act.id = cur_id; cur_id += 1
		act.friendly_name = "CrisisAct_%d" % i
		tree.connect_parent_child(c_seq, act)

	# -------------------------------------------------------------
	# Branch 2: Strategic Playbooks (Retreat, Defend, Harass, Expand, Push)
	# -------------------------------------------------------------
	var playbook_sel := BTComposite.BTSelector.new()
	playbook_sel.id = cur_id; cur_id += 1
	playbook_sel.friendly_name = "PlaybookSelector"
	tree.connect_parent_child(root_sel, playbook_sel)

	var stances_meta := [
		{"name": "Retreat", "val": StrategicStance.RETREAT},
		{"name": "Defend", "val": StrategicStance.DEFEND},
		{"name": "Harass", "val": StrategicStance.HARASS},
		{"name": "Expand", "val": StrategicStance.EXPAND},
		{"name": "Push", "val": StrategicStance.PUSH}
	]

	for st in stances_meta:
		var st_seq := BTComposite.BTSequence.new()
		st_seq.id = cur_id; cur_id += 1
		st_seq.friendly_name = "Stance_%s_Seq" % st.name
		tree.connect_parent_child(playbook_sel, st_seq)

		var st_cond := CondStrategicStance.new(self, st.val)
		st_cond.id = cur_id; cur_id += 1
		st_cond.friendly_name = "CondStanceIs_%s" % st.name
		tree.connect_parent_child(st_seq, st_cond)

		var st_sub_rand := BTComposite.BTRandomSelector.new()
		st_sub_rand.id = cur_id; cur_id += 1
		st_sub_rand.friendly_name = "%s_TacticalRand" % st.name
		tree.connect_parent_child(st_seq, st_sub_rand)

		for sub in range(5):
			var sub_seq := BTComposite.BTSequence.new()
			sub_seq.id = cur_id; cur_id += 1
			sub_seq.friendly_name = "%s_TacticalStep_%d" % [st.name, sub]
			tree.connect_parent_child(st_sub_rand, sub_seq)

			var sub_cond := CondResourceCheck.new(self, "minerals", 5.0 + sub * 2.0)
			sub_cond.id = cur_id; cur_id += 1
			sub_cond.friendly_name = "%s_Cond_%d" % [st.name, sub]
			tree.connect_parent_child(sub_seq, sub_cond)

			var sub_act := ActionExecuteStrategicOrder.new(self, "%s_Order_%d" % [st.name, sub])
			sub_act.id = cur_id; cur_id += 1
			sub_act.friendly_name = "%s_Act_%d" % [st.name, sub]
			tree.connect_parent_child(sub_seq, sub_act)

	# -------------------------------------------------------------
	# Branch 3: Tech Upgrades (RandomSelector to explore tech options)
	# -------------------------------------------------------------
	var tech_sel := BTComposite.BTRandomSelector.new()
	tech_sel.id = cur_id; cur_id += 1
	tech_sel.friendly_name = "TechTreeSelector"
	tree.connect_parent_child(root_sel, tech_sel)

	for t in range(10):
		var t_seq := BTComposite.BTSequence.new()
		t_seq.id = cur_id; cur_id += 1
		t_seq.friendly_name = "TechSeq_%d" % t
		tree.connect_parent_child(tech_sel, t_seq)

		var t_cond := CondResourceCheck.new(self, "energy", 5.0 + t * 2.0)
		t_cond.id = cur_id; cur_id += 1
		t_cond.friendly_name = "TechCond_%d" % t
		tree.connect_parent_child(t_seq, t_cond)

		var t_act := ActionTechUpgrade.new(self, "Upgrade_%d" % t, 10.0 + t * 2.0, 5.0 + t * 2.0)
		t_act.id = cur_id; cur_id += 1
		t_act.friendly_name = "TechAct_%d" % t
		tree.connect_parent_child(t_seq, t_act)

	# -------------------------------------------------------------
	# Branch 4: Scalable Production & Economic Operations (RandomSelector Grid)
	# -------------------------------------------------------------
	var prod_sel := BTComposite.BTRandomSelector.new()
	prod_sel.id = cur_id; cur_id += 1
	prod_sel.friendly_name = "ProductionGridSelector"
	tree.connect_parent_child(root_sel, prod_sel)

	var unit_names := ["ScoutDrone", "Marine", "Marauder", "SiegeTank", "Battlecruiser"]
	var remaining_needed := target_nodes - (cur_id - 1)
	var num_build_branches := int(ceil(float(max(remaining_needed, 30)) / 3.0))

	for b in range(num_build_branches):
		if (cur_id - 1) >= target_nodes:
			break
		var b_seq := BTComposite.BTSequence.new()
		b_seq.id = cur_id; cur_id += 1
		b_seq.friendly_name = "BuildSeq_%d" % b
		tree.connect_parent_child(prod_sel, b_seq)

		if (cur_id - 1) < target_nodes:
			var utype: String = unit_names[b % unit_names.size()]
			var cost: float = 5.0 + (b % 4) * 3.0
			var b_cond := CondResourceCheck.new(self, "minerals", cost)
			b_cond.id = cur_id; cur_id += 1
			b_cond.friendly_name = "BuildCond_%d" % b
			tree.connect_parent_child(b_seq, b_cond)

		if (cur_id - 1) < target_nodes:
			var utype: String = unit_names[b % unit_names.size()]
			var cost: float = 5.0 + (b % 4) * 3.0
			var b_act := ActionProduceUnit.new(self, utype, cost, 0.0, 1)
			b_act.id = cur_id; cur_id += 1
			b_act.friendly_name = "BuildAct_%d" % b
			tree.connect_parent_child(b_seq, b_act)

	# If slightly under due to rounding, add single leaf actions to prod_sel
	while (cur_id - 1) < target_nodes:
		var pad_act := ActionExecuteStrategicOrder.new(self, "EcoSurvey_%d" % cur_id)
		pad_act.id = cur_id; cur_id += 1
		pad_act.friendly_name = "PadAct_%d" % cur_id
		tree.connect_parent_child(prod_sel, pad_act)

	# Persist the canonical 850-node artifact only; other sizes are scratch
	# trees for the scale-sweep test and must not clobber this file.
	if target_nodes == 850:
		var dir := COMMANDER_800_TREE_PATH.get_base_dir()
		if not DirAccess.dir_exists_absolute(dir):
			DirAccess.make_dir_recursive_absolute(dir)
		var f := FileAccess.open(COMMANDER_800_TREE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(tree.to_dict(), "\t"))
			f.close()

	return tree

# ---------------------------------------------------------------- Simulation & Coordination API

func claim_lowest_hp_target(squad_id: int, squad_pos: Vector2) -> EnemyUnit:
	var claimed_ids := target_claims.values()
	var best_enemy: EnemyUnit = null
	var lowest_hp: float = 999999.0
	var closest_dist: float = 999999.0

	for e in enemies:
		if not e.is_alive:
			continue
		if claimed_ids.has(e.id):
			continue # Mutual exclusion: do not double-book
		if e.hp < lowest_hp or (is_equal_approx(e.hp, lowest_hp) and squad_pos.distance_to(e.pos) < closest_dist):
			lowest_hp = e.hp
			closest_dist = squad_pos.distance_to(e.pos)
			best_enemy = e

	if best_enemy != null:
		target_claims[squad_id] = best_enemy.id
		shared_bb.set_var("target_claims", target_claims)
	return best_enemy

func release_target(squad_id: int, enemy_id: int) -> void:
	if target_claims.get(squad_id, -1) == enemy_id:
		target_claims.erase(squad_id)
		shared_bb.set_var("target_claims", target_claims)

func get_enemy_by_id(p_id: int) -> EnemyUnit:
	for e in enemies:
		if e.id == p_id:
			return e
	return null

func spawn_enemy_wave(count: int = 3) -> void:
	for i in range(count):
		var y := 120.0 + (enemy_id_counter % 5) * 60.0
		var hp := 40.0 + (enemy_id_counter % 3) * 20.0
		var e := EnemyUnit.new(enemy_id_counter, Vector2(500.0, y), hp)
		enemies.append(e)
		enemy_id_counter += 1

func kill_squad(id: int) -> void:
	if id < 0 or id >= squads.size():
		return
	var sq := squads[id]
	if not sq.is_alive:
		return
	sq.is_alive = false
	sq.hp = 0.0
	sq.current_action = "Destroyed"
	if sq.assigned_target_id != -1:
		release_target(sq.id, sq.assigned_target_id)
		sq.assigned_target_id = -1
	if sq.runner != null and is_instance_valid(sq.runner):
		sq.runner.abort_running()
	_update_army_strength()

func trigger_forced_retreat() -> void:
	current_stance = StrategicStance.RETREAT
	if shared_bb != null:
		shared_bb.set_var("strategic_stance", int(current_stance))
	for sq in squads:
		if sq.is_alive:
			sq.hp = 30.0 # Force low HP triggering retreat micro

func inject_resources(min_amt: float = 150.0, eng_amt: float = 80.0) -> void:
	minerals += min_amt
	energy += eng_amt

func _update_army_strength() -> void:
	var total_hp := 0.0
	for s in squads:
		if s.is_alive:
			total_hp += s.hp
	army_strength = total_hp

	var e_hp := 0.0
	for e in enemies:
		if e.is_alive:
			e_hp += e.hp
	enemy_strength = e_hp

	if shared_bb != null:
		shared_bb.set_var("army_strength", army_strength)
		shared_bb.set_var("enemy_strength", enemy_strength)

	# Dynamic strategic state machine
	if army_strength < 40.0 and enemy_strength > 60.0:
		current_stance = StrategicStance.RETREAT
	elif enemy_strength > army_strength * 1.4:
		current_stance = StrategicStance.DEFEND
	elif enemy_strength == 0.0 and army_strength >= 100.0:
		current_stance = StrategicStance.EXPAND
	elif army_strength > enemy_strength * 1.5 and army_strength >= 120.0:
		current_stance = StrategicStance.PUSH
	else:
		current_stance = StrategicStance.HARASS

	if shared_bb != null:
		shared_bb.set_var("strategic_stance", int(current_stance))

func check_mutual_exclusion() -> void:
	var seen := {}
	for sq_id in target_claims.keys():
		var tid = target_claims[sq_id]
		if tid != -1:
			if seen.has(tid):
				target_mutex_violations += 1
			seen[tid] = sq_id

func tick_all(delta: float = 0.1) -> void:
	var t0 := Time.get_ticks_usec()
	tick_count += 1

	# Passive resource income
	minerals += 6.0
	energy += 3.5

	# Natural enemy wave timer
	enemy_spawn_timer += delta
	if enemy_spawn_timer >= 12.0:
		enemy_spawn_timer = 0.0
		spawn_enemy_wave(3)

	_update_army_strength()

	var total_task_executions := 0

	# 1. Tick Commander Tree
	if commander_runner != null and is_instance_valid(commander_runner) and commander_runner.is_running:
		commander_runner.tick(delta)
		total_task_executions += commander_runner.task_executions

	# 2. Tick Squad Micro Trees
	for s in squads:
		if s.is_alive and s.runner != null and is_instance_valid(s.runner) and s.runner.is_running:
			s.runner.tick(delta)
			total_task_executions += s.runner.task_executions
			# Move squad towards target pos
			s.pos = s.pos.move_toward(s.target_pos, 25.0 * delta)

	# 3. Simulate Enemy Movement & Attack
	for e in enemies:
		if not e.is_alive:
			continue
		# Move towards base / squads
		e.pos = e.pos.move_toward(Vector2(60.0, e.pos.y), e.speed * delta)
		# Attack nearest squad
		for s in squads:
			if s.is_alive and s.pos.distance_to(e.pos) < 60.0:
				s.hp = maxf(0.0, s.hp - e.dps * delta)
				if s.hp <= 0.0:
					kill_squad(s.id)
				break

	# Clean dead enemies
	var alive_enemies: Array[EnemyUnit] = []
	for e in enemies:
		if e.is_alive:
			alive_enemies.append(e)
	enemies = alive_enemies

	check_mutual_exclusion()

	var elapsed_us := float(Time.get_ticks_usec() - t0)
	perf_us_window.append(elapsed_us)
	if perf_us_window.size() > 60:
		perf_us_window.pop_front()
	perf_exec_window.append(total_task_executions)
	if perf_exec_window.size() > 60:
		perf_exec_window.pop_front()

	max_measured_us = maxf(max_measured_us, elapsed_us)
	max_measured_exec = maxi(max_measured_exec, total_task_executions)

	_update_ui_state()
	if field_rect != null:
		field_rect.queue_redraw()

func get_perf_stats() -> Dictionary:
	if perf_us_window.is_empty():
		return {"p50_us": 0.0, "p99_us": 0.0, "max_us": 0.0, "p50_exec": 0, "p99_exec": 0, "max_exec": 0}
	var sorted_us := perf_us_window.duplicate()
	sorted_us.sort()
	var sorted_exec := perf_exec_window.duplicate()
	sorted_exec.sort()

	var idx50 := int(floor(sorted_us.size() * 0.5))
	var idx99 := mini(sorted_us.size() - 1, int(floor(sorted_us.size() * 0.99)))

	return {
		"p50_us": sorted_us[idx50],
		"p99_us": sorted_us[idx99],
		"max_us": max_measured_us,
		"p50_exec": sorted_exec[idx50],
		"p99_exec": sorted_exec[idx99],
		"max_exec": max_measured_exec
	}

# ---------------------------------------------------------------- UI Construction & Rendering

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.1)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	var main_vbox := VBoxContainer.new()
	main_vbox.anchor_right = 1.0
	main_vbox.anchor_bottom = 1.0
	main_vbox.offset_left = 12
	main_vbox.offset_top = 8
	main_vbox.offset_right = -12
	main_vbox.offset_bottom = -8
	main_vbox.add_theme_constant_override("separation", 8)
	add_child(main_vbox)

	# 1. Navigation Bar
	var nav_bar := HBoxContainer.new()
	nav_bar.add_theme_constant_override("separation", 10)
	main_vbox.add_child(nav_bar)

	var btn_hub := Button.new()
	btn_hub.text = "⮌ Complex Hub"
	btn_hub.pressed.connect(func(): get_tree().change_scene_to_file(HUB_SCENE_PATH))
	nav_bar.add_child(btn_hub)

	var title_lbl := Label.new()
	title_lbl.text = "RTS Commander AI Showcase: Large Tree (>= 800 Nodes) & Multi-Squad Micro Subtrees"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_bar.add_child(title_lbl)

	var btn_squad := Button.new()
	btn_squad.text = "Squad AI ➔"
	btn_squad.pressed.connect(func(): get_tree().change_scene_to_file(SQUAD_SCENE_PATH))
	nav_bar.add_child(btn_squad)

	var btn_boss := Button.new()
	btn_boss.text = "Boss AI ➔"
	btn_boss.pressed.connect(func(): get_tree().change_scene_to_file(BOSS_SCENE_PATH))
	nav_bar.add_child(btn_boss)

	# 2. Main Content Split
	var content_hbox := HBoxContainer.new()
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", 12)
	main_vbox.add_child(content_hbox)

	# Left: Battlefield 2D View
	field_rect = Control.new()
	field_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field_rect.draw.connect(_on_field_draw)
	content_hbox.add_child(field_rect)

	# Right: Strategic HUD & Performance Overlay
	var right_panel := PanelContainer.new()
	right_panel.custom_minimum_size = Vector2(460, 0)
	content_hbox.add_child(right_panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(scroll)

	var panel_vbox := VBoxContainer.new()
	panel_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(panel_vbox)

	# Performance Overlay
	var perf_hdr := Label.new()
	perf_hdr.text = "=== LIVE PERFORMANCE & ARCHITECTURE ==="
	perf_hdr.modulate = Color(0.2, 0.9, 0.8)
	panel_vbox.add_child(perf_hdr)

	perf_label = Label.new()
	perf_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel_vbox.add_child(perf_label)

	var div1 := HSeparator.new()
	panel_vbox.add_child(div1)

	# Strategic Stance & Economy
	var strat_hdr := Label.new()
	strat_hdr.text = "=== STRATEGIC COMMANDER STATE ==="
	strat_hdr.modulate = Color(1.0, 0.8, 0.2)
	panel_vbox.add_child(strat_hdr)

	stance_label = Label.new()
	stance_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel_vbox.add_child(stance_label)

	res_label = Label.new()
	res_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel_vbox.add_child(res_label)

	var div2 := HSeparator.new()
	panel_vbox.add_child(div2)

	# Squad Status Cards
	var squad_hdr := Label.new()
	squad_hdr.text = "=== SQUAD COMBAT MICRO (SUBTREES) ==="
	squad_hdr.modulate = Color(0.4, 0.7, 1.0)
	panel_vbox.add_child(squad_hdr)

	squad_cards_vbox = VBoxContainer.new()
	squad_cards_vbox.add_theme_constant_override("separation", 4)
	panel_vbox.add_child(squad_cards_vbox)

	for i in range(4):
		var card := Label.new()
		card.name = "SquadCard%d" % i
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		squad_cards_vbox.add_child(card)

	var div3 := HSeparator.new()
	panel_vbox.add_child(div3)

	# Interactive Control Buttons
	var ctrl_hdr := Label.new()
	ctrl_hdr.text = "=== INTERACTIVE STRESS CONTROLS ==="
	panel_vbox.add_child(ctrl_hdr)

	var row_btn1 := HBoxContainer.new()
	row_btn1.add_theme_constant_override("separation", 6)
	panel_vbox.add_child(row_btn1)

	btn_auto_tick = Button.new()
	btn_auto_tick.text = "Pause Auto-Tick" if auto_tick else "Start Auto-Tick"
	btn_auto_tick.pressed.connect(func():
		auto_tick = not auto_tick
		btn_auto_tick.text = "Pause Auto-Tick" if auto_tick else "Start Auto-Tick"
	)
	row_btn1.add_child(btn_auto_tick)

	var btn_step := Button.new()
	btn_step.text = "Step Tick"
	btn_step.pressed.connect(func(): tick_all(tick_interval))
	row_btn1.add_child(btn_step)

	var btn_wave := Button.new()
	btn_wave.text = "+ Enemy Wave"
	btn_wave.pressed.connect(func(): spawn_enemy_wave(4))
	row_btn1.add_child(btn_wave)

	var row_btn2 := HBoxContainer.new()
	row_btn2.add_theme_constant_override("separation", 6)
	panel_vbox.add_child(row_btn2)

	var btn_res := Button.new()
	btn_res.text = "+ Resources"
	btn_res.pressed.connect(func(): inject_resources(200.0, 100.0))
	row_btn2.add_child(btn_res)

	var btn_kill := Button.new()
	btn_kill.text = "Kill Squad 0"
	btn_kill.pressed.connect(func(): kill_squad(0))
	row_btn2.add_child(btn_kill)

	var btn_ret := Button.new()
	btn_ret.text = "Force Retreat"
	btn_ret.pressed.connect(func(): trigger_forced_retreat())
	row_btn2.add_child(btn_ret)

	var btn_reset := Button.new()
	btn_reset.text = "Reset Demo"
	btn_reset.pressed.connect(func():
		_init_simulation()
		_update_ui_state()
		if field_rect != null: field_rect.queue_redraw()
	)
	row_btn2.add_child(btn_reset)

func _update_ui_state() -> void:
	if perf_label == null: return

	var total_nodes := 0
	if commander_tree != null:
		total_nodes += commander_tree.get_node_count()
	for s in squads:
		if s.tree != null:
			total_nodes += s.tree.get_node_count()

	var stats := get_perf_stats()
	perf_label.text = "Tree Nodes Total: %d (Cmdr: %d + 4 Micro Subtrees: %d)\nActive BTRunners: %d (1 Cmdr + %d Squads)\nTick Time: p50: %.1f µs | p99: %.1f µs | Max: %.1f µs\nExecutions/Tick: p50: %d | p99: %d | Cap: %d" % [
		total_nodes,
		commander_tree.get_node_count() if commander_tree != null else 0,
		total_nodes - (commander_tree.get_node_count() if commander_tree != null else 0),
		1 + squads.size(),
		squads.size(),
		stats.p50_us, stats.p99_us, stats.max_us,
		stats.p50_exec, stats.p99_exec, EXECUTION_BUDGET_CAP
	]

	var stance_names := ["RETREAT", "DEFEND", "HARASS", "EXPAND", "PUSH"]
	stance_label.text = "Stance: [%s] | Last Order: %s\nArmy: %.0f vs Enemy: %.0f | Mutex Violations: %d" % [
		stance_names[int(current_stance)],
		last_strategic_order,
		army_strength,
		enemy_strength,
		target_mutex_violations
	]

	res_label.text = "Minerals: %.0f | Energy: %.0f | Queue: %s\nTech Upgrades: %d | Total Units Built: %d" % [
		minerals, energy,
		str(production_queue) if not production_queue.is_empty() else "[Idle]",
		tech_unlocked.size(),
		total_units_produced
	]

	for i in range(squads.size()):
		var s := squads[i]
		var card: Label = squad_cards_vbox.get_node_or_null("SquadCard%d" % i)
		if card != null:
			if not s.is_alive:
				card.text = "Squad #%d: [DESTROYED IN ACTION]" % i
				card.modulate = Color(0.7, 0.3, 0.3)
			else:
				var target_str := ("#%d" % s.assigned_target_id) if s.assigned_target_id != -1 else "None"
				card.text = "Squad #%d: HP %.0f/%.0f | %s (Target: %s)" % [
					i, s.hp, s.max_hp, s.current_action, target_str
				]
				card.modulate = s.color

func _on_field_draw() -> void:
	if field_rect == null: return
	var size := field_rect.size

	# Field background
	field_rect.draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.1, 0.14))

	# Grid lines
	var grid_spacing := 40.0
	for x in range(0, int(size.x), int(grid_spacing)):
		field_rect.draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.12, 0.15, 0.2))
	for y in range(0, int(size.y), int(grid_spacing)):
		field_rect.draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.12, 0.15, 0.2))

	# Player Base Area (Left)
	field_rect.draw_rect(Rect2(Vector2(10, 80), Vector2(70, 320)), Color(0.15, 0.25, 0.4, 0.4))
	field_rect.draw_string(ThemeDB.fallback_font, Vector2(15, 75), "HQ / BASE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.7, 1.0))

	# Enemy Territory (Right)
	field_rect.draw_rect(Rect2(Vector2(size.x - 80, 80), Vector2(70, 320)), Color(0.4, 0.15, 0.15, 0.4))
	field_rect.draw_string(ThemeDB.fallback_font, Vector2(size.x - 75, 75), "ENEMY SPAWN", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.4, 0.4))

	# Draw Squads
	for s in squads:
		if not s.is_alive:
			# Tombstone mark
			field_rect.draw_line(s.pos - Vector2(6, 6), s.pos + Vector2(6, 6), Color(0.6, 0.2, 0.2), 2.0)
			field_rect.draw_line(s.pos - Vector2(-6, 6), s.pos + Vector2(-6, 6), Color(0.6, 0.2, 0.2), 2.0)
			continue

		# Squad circle
		field_rect.draw_circle(s.pos, 12.0, s.color)
		field_rect.draw_arc(s.pos, 13.0, 0, TAU, 16, Color.WHITE, 1.5)

		# Range indicator
		field_rect.draw_arc(s.pos, s.range_dist, 0, TAU, 24, Color(s.color.r, s.color.g, s.color.b, 0.2), 1.0)

		# Target engagement beam
		if s.assigned_target_id != -1:
			var tgt = get_enemy_by_id(s.assigned_target_id)
			if tgt != null and tgt.is_alive:
				field_rect.draw_line(s.pos, tgt.pos, Color(s.color.r, s.color.g, s.color.b, 0.7), 1.5)

		# Health bar
		var hp_pct = s.hp / s.max_hp
		field_rect.draw_rect(Rect2(s.pos + Vector2(-15, -20), Vector2(30, 4)), Color.BLACK)
		field_rect.draw_rect(Rect2(s.pos + Vector2(-15, -20), Vector2(30 * hp_pct, 4)), Color(0.2, 0.9, 0.3) if hp_pct > 0.35 else Color(0.9, 0.2, 0.2))

		# Label
		field_rect.draw_string(ThemeDB.fallback_font, s.pos + Vector2(-12, 22), "SQ%d" % s.id, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

	# Draw Enemies
	for e in enemies:
		if not e.is_alive:
			continue
		var col := Color(0.95, 0.25, 0.25)
		field_rect.draw_circle(e.pos, 10.0, col)
		field_rect.draw_arc(e.pos, 11.0, 0, TAU, 16, Color.BLACK, 1.0)

		# Health bar
		var hp_pct = e.hp / e.max_hp
		field_rect.draw_rect(Rect2(e.pos + Vector2(-12, -18), Vector2(24, 4)), Color.BLACK)
		field_rect.draw_rect(Rect2(e.pos + Vector2(-12, -18), Vector2(24 * hp_pct, 4)), Color(0.9, 0.2, 0.2))

		field_rect.draw_string(ThemeDB.fallback_font, e.pos + Vector2(-10, 20), "E%d" % e.id, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.7, 0.7))
