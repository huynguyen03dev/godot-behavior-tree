extends Control
## Complex Demo: Villager Colony Life-Sim Showcase with Modular Reused SubTrees.
##
## Demonstrates a deep Sims/RPG-style villager simulation driven by Behavior Trees:
## - 6 autonomous villagers with personal needs (hunger, energy, social, safety) decaying over time.
## - Simulated Day/Night cycle (Morning, Afternoon Work, Evening Social, Night Sleep).
## - Modular jobs (Farmer, Guard, Merchant, Cook) and routines (Sleep, Eat, Socialize, Threat)
##   implemented as REUSED SUBTREES loaded from JSON on disk via BTSubTree.
## - Strict Blackboard scoping: is_shared=true variables live in parent scope;
##   is_shared=false variables are private to child subtrees and do not leak.
## - Emergency Threat preemption: Wolf attacks immediately abort working/eating villagers
##   via LOWER_PRIORITY conditional abort on the main tree root selector.

const HUB_SCENE_PATH := "res://demo/complex/complex_demo.tscn"
const BOSS_SCENE_PATH := "res://demo/complex/boss_demo.tscn"
const SQUAD_SCENE_PATH := "res://demo/complex/squad_demo.tscn"
const GUARD_SCENE_PATH := "res://demo/complex/guard_stealth_demo.tscn"

const SUBTREE_DIR := "res://demo/complex/villager_subtrees"

# ---------------------------------------------------------------- Data Structures & Tasks

class Villager extends Node:
	var id: int
	var villager_name: String
	var role: String # "farmer", "guard", "merchant", "cook"
	var color: Color

	# Needs (0 to 100)
	var hunger: float = 85.0
	var energy: float = 90.0
	var social: float = 80.0
	var safety: float = 100.0

	# Spatial state
	var position: Vector2 = Vector2.ZERO
	var target_position: Vector2 = Vector2.ZERO
	var current_location_name: String = "home"
	var current_action_name: String = "Awake"
	var current_subtree_name: String = "main"

	# Locations map (Vector2 positions in arena)
	var locations: Dictionary = {}

	# Behavior Tree & Runner
	var runner: BTRunner = null
	var tree: BTTree = null

	# Lifecycle & Verification Metrics
	var total_starts: int = 0
	var total_ends: int = 0
	var total_aborts: int = 0
	var total_updates: int = 0
	var double_abort_errors: int = 0
	var update_without_start_errors: int = 0
	var end_without_start_errors: int = 0

	# Node execution tracking: node_key -> count
	var executed_tasks: Dictionary = {}

	func _init(p_id: int, p_name: String, p_role: String, p_color: Color) -> void:
		id = p_id
		name = p_name
		villager_name = p_name
		role = p_role
		color = p_color

	func record_task_start(task: BTTask) -> void:
		total_starts += 1
		var key := _get_task_key(task)
		executed_tasks[key] = executed_tasks.get(key, 0) + 1

	func record_task_end(task: BTTask) -> void:
		total_ends += 1

	func record_task_abort(task: BTTask) -> void:
		total_aborts += 1

	func _get_task_key(task: BTTask) -> String:
		return "%s_%d" % [task.type_name, task.id]


class VillagerTask extends BTTask:
	var is_started: bool = false
	var was_aborted: bool = false
	var duration_ticks: int = 1
	var current_tick: int = 0

	func _get_villager() -> Villager:
		if owner != null and owner is BTRunner:
			var r := owner as BTRunner
			if r.actor != null and r.actor is Villager:
				return r.actor as Villager
		return null

	func _get_demo() -> Node:
		var v := _get_villager()
		if v != null and v.runner != null and v.runner.get_parent() != null:
			return v.runner.get_parent()
		return null

	func on_start() -> void:
		is_started = true
		was_aborted = false
		current_tick = 0
		duration_ticks = int(get_param("ticks", 1))
		var v := _get_villager()
		if v != null:
			v.record_task_start(self)
			v.current_action_name = friendly_name if friendly_name != "" else type_name

	func on_abort() -> void:
		var v := _get_villager()
		if not is_started:
			if v != null: v.update_without_start_errors += 1
			return
		if was_aborted:
			if v != null: v.double_abort_errors += 1
			return
		was_aborted = true
		is_started = false
		if v != null:
			v.record_task_abort(self)
			v.current_action_name = "Aborted: " + (friendly_name if friendly_name != "" else type_name)

	func on_end() -> void:
		if was_aborted:
			return # Already accounted for in aborts
		var v := _get_villager()
		if not is_started:
			if v != null: v.end_without_start_errors += 1
			return
		is_started = false
		if v != null:
			v.record_task_end(self)

	func _apply_shared_and_private_vars() -> void:
		var shared_var := str(get_param("shared_var", ""))
		if shared_var != "" and blackboard != null:
			var cur_val: Variant = get_blackboard_var(shared_var, 0)
			if cur_val is int or cur_val is float:
				set_blackboard_var(shared_var, cur_val + 1)

		var private_var := str(get_param("private_var", ""))
		if private_var != "" and blackboard != null:
			var cur_priv: Variant = get_blackboard_var(private_var, 0)
			if cur_priv is int or cur_priv is float:
				set_blackboard_var(private_var, cur_priv + 1)


# ------------------------------------------------ Custom Task Implementations

class VillagerConditionNeed extends VillagerTask:
	func _init() -> void:
		type_name = "VillagerConditionNeed"
		category = "Condition"

	func evaluate_condition(_runner: BTRunner) -> int:
		var v := _get_villager()
		if v == null: return BTStatus.FAILURE
		var need := str(get_param("need_type", "hunger"))
		var threshold := float(get_param("threshold", 30.0))
		var op := str(get_param("operator", "<="))
		var val := 100.0
		match need:
			"hunger": val = v.hunger
			"energy": val = v.energy
			"social": val = v.social
			"safety": val = v.safety

		var met := false
		if op == "<=": met = (val <= threshold)
		elif op == ">=": met = (val >= threshold)
		elif op == "<": met = (val < threshold)
		elif op == ">": met = (val > threshold)
		return BTStatus.SUCCESS if met else BTStatus.FAILURE

	func on_update() -> int:
		var v := _get_villager()
		if v != null and not is_started:
			v.update_without_start_errors += 1
		return evaluate_condition(owner as BTRunner)


class VillagerConditionSchedule extends VillagerTask:
	func _init() -> void:
		type_name = "VillagerConditionSchedule"
		category = "Condition"

	func evaluate_condition(_runner: BTRunner) -> int:
		var demo := _get_demo()
		if demo == null: return BTStatus.FAILURE
		var target_phase := str(get_param("phase", "work"))
		var cur_phase: String = demo.current_phase
		if target_phase == "work":
			return BTStatus.SUCCESS if (cur_phase == "morning" or cur_phase == "afternoon") else BTStatus.FAILURE
		return BTStatus.SUCCESS if (cur_phase == target_phase) else BTStatus.FAILURE

	func on_update() -> int:
		var v := _get_villager()
		if v != null and not is_started:
			v.update_without_start_errors += 1
		return evaluate_condition(owner as BTRunner)


class VillagerConditionThreat extends VillagerTask:
	func _init() -> void:
		type_name = "VillagerConditionThreat"
		category = "Condition"

	func evaluate_condition(_runner: BTRunner) -> int:
		var demo := _get_demo()
		if demo == null: return BTStatus.FAILURE
		return BTStatus.SUCCESS if demo.threat_active else BTStatus.FAILURE

	func on_update() -> int:
		var v := _get_villager()
		if v != null and not is_started:
			v.update_without_start_errors += 1
		return evaluate_condition(owner as BTRunner)


class VillagerConditionRole extends VillagerTask:
	func _init() -> void:
		type_name = "VillagerConditionRole"
		category = "Condition"

	func evaluate_condition(_runner: BTRunner) -> int:
		var v := _get_villager()
		if v == null: return BTStatus.FAILURE
		var target_role := str(get_param("role", "civilian"))
		if target_role == "civilian":
			return BTStatus.SUCCESS if (v.role != "guard") else BTStatus.FAILURE
		return BTStatus.SUCCESS if (v.role == target_role) else BTStatus.FAILURE

	func on_update() -> int:
		var v := _get_villager()
		if v != null and not is_started:
			v.update_without_start_errors += 1
		return evaluate_condition(owner as BTRunner)


class VillagerConditionStock extends VillagerTask:
	func _init() -> void:
		type_name = "VillagerConditionStock"
		category = "Condition"

	func evaluate_condition(_runner: BTRunner) -> int:
		var demo := _get_demo()
		if demo == null: return BTStatus.FAILURE
		var resource := str(get_param("resource", "food"))
		var min_amt := int(get_param("min_amount", 1))
		var amt := 0
		if resource == "food": amt = demo.food_stock
		elif resource == "gold": amt = demo.village_gold
		return BTStatus.SUCCESS if (amt >= min_amt) else BTStatus.FAILURE

	func on_update() -> int:
		var v := _get_villager()
		if v != null and not is_started:
			v.update_without_start_errors += 1
		return evaluate_condition(owner as BTRunner)


class VillagerConditionTaskReady extends VillagerTask:
	func _init() -> void:
		type_name = "VillagerConditionTaskReady"
		category = "Condition"

	func evaluate_condition(_runner: BTRunner) -> int:
		var demo := _get_demo()
		if demo == null: return BTStatus.SUCCESS
		var key := str(get_param("task_key", "ready"))
		return BTStatus.SUCCESS if demo.is_task_ready(key) else BTStatus.FAILURE

	func on_update() -> int:
		var v := _get_villager()
		if v != null and not is_started:
			v.update_without_start_errors += 1
		return evaluate_condition(owner as BTRunner)


class VillagerActionMoveTo extends VillagerTask:
	var loc_name: String = "home"

	func _init() -> void:
		type_name = "VillagerActionMoveTo"
		category = "Action"

	func on_start() -> void:
		super.on_start()
		loc_name = str(get_param("location", "home"))
		var v := _get_villager()
		if v != null:
			v.current_location_name = loc_name
			if v.locations.has(loc_name):
				v.target_position = v.locations[loc_name]

	func on_update() -> int:
		var v := _get_villager()
		if v != null and not is_started:
			v.update_without_start_errors += 1
		current_tick += 1
		if v != null:
			# Smoothly interpolate position towards target
			v.position = v.position.lerp(v.target_position, 0.6)
		if current_tick >= duration_ticks:
			if v != null: v.position = v.target_position
			return BTStatus.SUCCESS
		return BTStatus.RUNNING


class VillagerActionWork extends VillagerTask:
	func _init() -> void:
		type_name = "VillagerActionWork"
		category = "Action"

	func on_update() -> int:
		var v := _get_villager()
		if v != null and not is_started:
			v.update_without_start_errors += 1
		current_tick += 1
		if v != null:
			v.energy = max(0.0, v.energy - 0.5)
			v.hunger = max(0.0, v.hunger - 0.4)
		if current_tick >= duration_ticks:
			_apply_shared_and_private_vars()
			var demo := _get_demo()
			if demo != null:
				var f_delta := int(get_param("food_delta", 0))
				if f_delta > 0: demo.food_stock += f_delta
				var g_delta := int(get_param("gold_delta", 0))
				if g_delta > 0: demo.village_gold += g_delta
			return BTStatus.SUCCESS
		return BTStatus.RUNNING


class VillagerActionEat extends VillagerTask:
	func _init() -> void:
		type_name = "VillagerActionEat"
		category = "Action"

	func on_update() -> int:
		var v := _get_villager()
		if v != null and not is_started:
			v.update_without_start_errors += 1
		current_tick += 1
		var restore := float(get_param("hunger_restore", 35.0))
		if v != null:
			v.hunger = min(100.0, v.hunger + (restore / float(max(1, duration_ticks))))
		if current_tick >= duration_ticks:
			_apply_shared_and_private_vars()
			var demo := _get_demo()
			var src := str(get_param("source", "granary"))
			if demo != null and (src == "granary" or src == "table"):
				demo.food_stock = max(0, demo.food_stock - 1)
			return BTStatus.SUCCESS
		return BTStatus.RUNNING


class VillagerActionSleep extends VillagerTask:
	func _init() -> void:
		type_name = "VillagerActionSleep"
		category = "Action"

	func on_update() -> int:
		var v := _get_villager()
		if v != null and not is_started:
			v.update_without_start_errors += 1
		current_tick += 1
		var restore := float(get_param("energy_restore", 30.0))
		if v != null:
			v.energy = min(100.0, v.energy + restore)
		if current_tick >= duration_ticks:
			_apply_shared_and_private_vars()
			return BTStatus.SUCCESS
		return BTStatus.RUNNING


class VillagerActionSocialize extends VillagerTask:
	func _init() -> void:
		type_name = "VillagerActionSocialize"
		category = "Action"

	func on_update() -> int:
		var v := _get_villager()
		if v != null and not is_started:
			v.update_without_start_errors += 1
		current_tick += 1
		var restore := float(get_param("social_restore", 25.0))
		if v != null:
			v.social = min(100.0, v.social + restore)
		if current_tick >= duration_ticks:
			_apply_shared_and_private_vars()
			return BTStatus.SUCCESS
		return BTStatus.RUNNING


class VillagerActionThreat extends VillagerTask:
	func _init() -> void:
		type_name = "VillagerActionThreat"
		category = "Action"

	func on_update() -> int:
		var v := _get_villager()
		if v != null and not is_started:
			v.update_without_start_errors += 1
		current_tick += 1
		var resp := str(get_param("response_type", "cower"))
		if v != null:
			if resp == "guard_attack":
				var demo := _get_demo()
				if demo != null:
					demo.wolf_health = max(0, demo.wolf_health - 1)
					if demo.wolf_health <= 0:
						demo.threat_active = false
			elif resp == "cower":
				v.safety = max(10.0, v.safety + 5.0)
		if current_tick >= duration_ticks:
			_apply_shared_and_private_vars()
			return BTStatus.SUCCESS
		return BTStatus.RUNNING


class VillagerActionIdle extends VillagerTask:
	func _init() -> void:
		type_name = "VillagerActionIdle"
		category = "Action"

	func on_update() -> int:
		var v := _get_villager()
		if v != null and not is_started:
			v.update_without_start_errors += 1
		current_tick += 1
		if current_tick >= duration_ticks:
			return BTStatus.SUCCESS
		return BTStatus.RUNNING


# ------------------------------------------------ Simulation State & Properties

var villagers: Array[Villager] = []
var task_registry: BTTaskRegistry = null
var tree_source: BTFileTreeSource = null

# Colony Simulation Clock & Economy
var colony_time: float = 8.0 # 0.0 to 24.0 hours
var day_count: int = 1
var current_phase: String = "morning" # morning, afternoon, evening, night
var food_stock: int = 35
var village_gold: int = 20
var threat_active: bool = false
var wolf_health: int = 4
var threat_pos: Vector2 = Vector2(460, 190)

# Task readiness flags for variety
var _ready_timer := 0
var _task_states: Dictionary = {
	"crops_ripe": true, "soil_dry": true, "weeds_grown": true, "orchard_ready": true, "pests_spotted": true,
	"watchtower_due": true, "gate_due": true, "palisade_due": true, "drill_due": true, "armory_due": true,
	"customer_waiting": true, "stall_open": true, "restock_needed": true, "audit_due": true,
	"pot_ready": true, "veggies_ready": true, "story_ready": true
}

# Execution & Timing Metrics
var total_simulation_ticks: int = 0
var tick_times_usec: Array[int] = []
var auto_tick: bool = false
var tick_timer: float = 0.0
var tick_interval: float = 0.25

# Node coverage dictionary across ALL trees: node_unique_key -> true
var global_executed_node_keys: Dictionary = {}

# UI Elements
var arena_control: Control = null
var clock_label: Label = null
var food_gold_label: Label = null
var threat_label: Label = null
var node_count_label: Label = null
var scoping_label: Label = null
var coverage_label: Label = null
var auto_tick_button: Button = null
var villager_cards_container: VBoxContainer = null


# ------------------------------------------------ Lifecycle & Setup

func _ready() -> void:
	task_registry = _build_task_registry()
	tree_source = BTFileTreeSource.new(SUBTREE_DIR, task_registry)

	_init_colony()

	if DisplayServer.get_name() == "headless":
		auto_tick = false
	else:
		auto_tick = true

	_build_ui()
	_update_ui()

func _physics_process(delta: float) -> void:
	if not auto_tick:
		return
	tick_timer += delta
	if tick_timer >= tick_interval:
		tick_timer = 0.0
		tick_manual(tick_interval)

func _exit_tree() -> void:
	for v in villagers:
		if v.runner != null and is_instance_valid(v.runner):
			v.runner.stop()
			v.runner.free()
			v.runner = null
		if is_instance_valid(v):
			v.queue_free()

func _build_task_registry() -> BTTaskRegistry:
	var reg := BTTaskRegistry.new()
	reg.register_task("VillagerConditionNeed", func(): return VillagerConditionNeed.new(), "Condition")
	reg.register_task("VillagerConditionSchedule", func(): return VillagerConditionSchedule.new(), "Condition")
	reg.register_task("VillagerConditionThreat", func(): return VillagerConditionThreat.new(), "Condition")
	reg.register_task("VillagerConditionRole", func(): return VillagerConditionRole.new(), "Condition")
	reg.register_task("VillagerConditionStock", func(): return VillagerConditionStock.new(), "Condition")
	reg.register_task("VillagerConditionTaskReady", func(): return VillagerConditionTaskReady.new(), "Condition")
	reg.register_task("VillagerActionMoveTo", func(): return VillagerActionMoveTo.new(), "Action")
	reg.register_task("VillagerActionWork", func(): return VillagerActionWork.new(), "Action")
	reg.register_task("VillagerActionEat", func(): return VillagerActionEat.new(), "Action")
	reg.register_task("VillagerActionSleep", func(): return VillagerActionSleep.new(), "Action")
	reg.register_task("VillagerActionSocialize", func(): return VillagerActionSocialize.new(), "Action")
	reg.register_task("VillagerActionThreat", func(): return VillagerActionThreat.new(), "Action")
	reg.register_task("VillagerActionIdle", func(): return VillagerActionIdle.new(), "Action")
	return reg

func _init_colony() -> void:
	villagers.clear()

	# Create 6 Villagers: 2 Farmers, 2 Guards, 1 Merchant, 1 Cook
	var v_alden := Villager.new(1, "Alden", "farmer", Color(0.92, 0.72, 0.28))
	var v_bera := Villager.new(2, "Bera", "farmer", Color(0.96, 0.82, 0.38))
	var v_cedric := Villager.new(3, "Cedric", "guard", Color(0.38, 0.68, 0.98))
	var v_daphne := Villager.new(4, "Daphne", "guard", Color(0.28, 0.52, 0.88))
	var v_elric := Villager.new(5, "Elric", "merchant", Color(0.42, 0.88, 0.52))
	var v_fiona := Villager.new(6, "Fiona", "cook", Color(0.98, 0.48, 0.38))

	villagers = [v_alden, v_bera, v_cedric, v_daphne, v_elric, v_fiona]

	# Landmark coordinates in Arena
	var shared_locations := {
		"campfire": Vector2(300, 270),
		"granary": Vector2(230, 260),
		"dining_table": Vector2(250, 310),
		"safe_bunker": Vector2(130, 110),
		"water_well": Vector2(180, 390),
		"crop_field": Vector2(140, 450),
		"furrow": Vector2(180, 450),
		"orchard": Vector2(230, 450),
		"field_fence": Vector2(90, 470),
		"tool_shed": Vector2(90, 410),
		"watchtower": Vector2(440, 120),
		"north_gate": Vector2(410, 190),
		"south_palisade": Vector2(410, 440),
		"bastion": Vector2(420, 280),
		"training_dummy": Vector2(380, 310),
		"armory": Vector2(380, 380),
		"market_stall": Vector2(320, 175),
		"warehouse": Vector2(370, 160),
		"ledger_desk": Vector2(310, 215),
		"caravan_stop": Vector2(360, 215),
		"cauldron": Vector2(310, 370),
		"prep_table": Vector2(270, 410),
		"tavern_kitchen": Vector2(310, 410),
		"scullery": Vector2(350, 410),
		"clay_oven": Vector2(360, 370),
		"herb_garden": Vector2(260, 460),
		"berry_bush": Vector2(190, 500),
		"plaza": Vector2(300, 230),
		"threat": Vector2(460, 190)
	}

	# Unique home beds and work stations
	v_alden.locations = shared_locations.duplicate()
	v_alden.locations["home"] = Vector2(110, 160)
	v_alden.locations["tool_shed"] = Vector2(85, 430)
	v_alden.locations["crop_field"] = Vector2(130, 470)
	v_alden.locations["furrow"] = Vector2(170, 470)
	v_alden.locations["orchard"] = Vector2(210, 470)
	v_alden.position = v_alden.locations["home"]

	v_bera.locations = shared_locations.duplicate()
	v_bera.locations["home"] = Vector2(150, 160)
	v_bera.locations["tool_shed"] = Vector2(145, 430)
	v_bera.locations["crop_field"] = Vector2(150, 470)
	v_bera.locations["furrow"] = Vector2(190, 470)
	v_bera.locations["orchard"] = Vector2(230, 470)
	v_bera.position = v_bera.locations["home"]

	v_cedric.locations = shared_locations.duplicate()
	v_cedric.locations["home"] = Vector2(110, 205)
	v_cedric.locations["bastion"] = Vector2(420, 260)
	v_cedric.locations["training_dummy"] = Vector2(370, 310)
	v_cedric.locations["watchtower"] = Vector2(440, 110)
	v_cedric.position = v_cedric.locations["home"]

	v_daphne.locations = shared_locations.duplicate()
	v_daphne.locations["home"] = Vector2(150, 205)
	v_daphne.locations["bastion"] = Vector2(420, 300)
	v_daphne.locations["training_dummy"] = Vector2(390, 310)
	v_daphne.locations["watchtower"] = Vector2(440, 130)
	v_daphne.position = v_daphne.locations["home"]

	v_elric.locations = shared_locations.duplicate()
	v_elric.locations["home"] = Vector2(110, 250)
	v_elric.locations["market_stall"] = Vector2(315, 175)
	v_elric.locations["ledger_desk"] = Vector2(310, 215)
	v_elric.position = v_elric.locations["home"]

	v_fiona.locations = shared_locations.duplicate()
	v_fiona.locations["home"] = Vector2(150, 250)
	v_fiona.locations["tavern_kitchen"] = Vector2(310, 410)
	v_fiona.locations["prep_table"] = Vector2(270, 410)
	v_fiona.position = v_fiona.locations["home"]

	# Build Main Trees for each villager
	for v in villagers:
		add_child(v)
		var job_path := ""
		match v.role:
			"farmer": job_path = "demo/complex/villager_subtrees/farmer_job.json"
			"guard": job_path = "demo/complex/villager_subtrees/guard_job.json"
			"merchant": job_path = "demo/complex/villager_subtrees/merchant_job.json"
			"cook": job_path = "demo/complex/villager_subtrees/cook_job.json"

		v.tree = _build_villager_main_tree(v, job_path)
		v.runner = BTRunner.new(v.tree)
		v.runner.actor = v
		add_child(v.runner)
		v.runner.set_process(false)
		v.runner.start()

		# Instrument runner task starts for coverage
		v.runner.task_started.connect(func(task: BTTask):
			_record_global_node_execution("v%d_main_%d" % [v.id, task.id])
			# If this is a SubTree node, also attach to its sub_runner
			if task is BTSubTree:
				var sub: BTSubTree = task as BTSubTree
				v.current_subtree_name = sub.tree_path.get_file().get_basename()
				var sub_run: BTRunner = sub.get("sub_runner")
				if sub_run != null and not sub_run.task_started.is_connected(_on_sub_runner_task_started):
					sub_run.task_started.connect(_on_sub_runner_task_started.bind(v.current_subtree_name))
		)

func _on_sub_runner_task_started(task: BTTask, subtree_name: String) -> void:
	_record_global_node_execution("%s_node_%d" % [subtree_name, task.id])

func _record_global_node_execution(key: String) -> void:
	global_executed_node_keys[key] = true

# ------------------------------------------------ Main Behavior Tree Construction

func _build_villager_main_tree(v: Villager, job_path: String) -> BTTree:
	var bt := BTTree.new()
	bt.tree_name = "%sMainAI" % v.name
	bt.description = "Main Behavior Tree for %s (%s) with preemption and reused SubTrees." % [v.name, v.role]
	bt.registry = task_registry

	# Root: Repeater forever
	var root_rep := BTDecorator.BTRepeater.new()
	root_rep.repeat_forever = true
	root_rep.friendly_name = "LifeSim Repeater"
	bt.set_root(root_rep)

	# Root Selector with LOWER_PRIORITY conditional abort
	var root_sel := BTComposite.BTSelector.new()
	root_sel.set_abort_type(BTComposite.AbortType.LOWER_PRIORITY)
	root_sel.friendly_name = "Main Priority Selector (LOWER_PRIORITY Abort)"
	bt.connect_parent_child(root_rep, root_sel)

	# 1. Emergency Threat Branch (Top priority: Wolf attack!)
	var seq_threat := BTComposite.BTSequence.new()
	seq_threat.set_abort_type(BTComposite.AbortType.SELF)
	seq_threat.friendly_name = "Threat Priority Branch"
	var cond_threat := VillagerConditionThreat.new()
	cond_threat.friendly_name = "Threat Active?"
	var sub_threat := BTSubTree.new("demo/complex/villager_subtrees/threat_response.json")
	sub_threat.friendly_name = "SubTree: Threat Response"
	bt.connect_parent_child(root_sel, seq_threat)
	bt.connect_parent_child(seq_threat, cond_threat)
	bt.connect_parent_child(seq_threat, sub_threat)

	# 2. Critical Starvation Branch (hunger <= 25)
	var seq_starve := BTComposite.BTSequence.new()
	seq_starve.set_abort_type(BTComposite.AbortType.SELF)
	seq_starve.friendly_name = "Critical Starvation Branch"
	var cond_starve := VillagerConditionNeed.new()
	cond_starve.parameters = {"need_type": "hunger", "threshold": 25.0, "operator": "<="}
	cond_starve.friendly_name = "Hunger <= 25%?"
	var sub_eat_crit := BTSubTree.new("demo/complex/villager_subtrees/eat_routine.json")
	sub_eat_crit.friendly_name = "SubTree: Emergency Dining"
	bt.connect_parent_child(root_sel, seq_starve)
	bt.connect_parent_child(seq_starve, cond_starve)
	bt.connect_parent_child(seq_starve, sub_eat_crit)

	# 3. Exhaustion Sleep Branch (energy <= 20)
	var seq_exhaust := BTComposite.BTSequence.new()
	seq_exhaust.set_abort_type(BTComposite.AbortType.SELF)
	seq_exhaust.friendly_name = "Exhaustion Collapse Branch"
	var cond_exhaust := VillagerConditionNeed.new()
	cond_exhaust.parameters = {"need_type": "energy", "threshold": 20.0, "operator": "<="}
	cond_exhaust.friendly_name = "Energy <= 20%?"
	var sub_sleep_crit := BTSubTree.new("demo/complex/villager_subtrees/sleep_routine.json")
	sub_sleep_crit.friendly_name = "SubTree: Exhaustion Sleep"
	bt.connect_parent_child(root_sel, seq_exhaust)
	bt.connect_parent_child(seq_exhaust, cond_exhaust)
	bt.connect_parent_child(seq_exhaust, sub_sleep_crit)

	# 4. Scheduled Night Sleep Branch (phase == "night")
	var seq_night := BTComposite.BTSequence.new()
	seq_night.set_abort_type(BTComposite.AbortType.SELF)
	seq_night.friendly_name = "Night Schedule Sleep Branch"
	var cond_night := VillagerConditionSchedule.new()
	cond_night.parameters = {"phase": "night"}
	cond_night.friendly_name = "Is Night Time?"
	var sub_sleep_night := BTSubTree.new("demo/complex/villager_subtrees/sleep_routine.json")
	sub_sleep_night.friendly_name = "SubTree: Night Slumber"
	bt.connect_parent_child(root_sel, seq_night)
	bt.connect_parent_child(seq_night, cond_night)
	bt.connect_parent_child(seq_night, sub_sleep_night)

	# 5. Regular Mealtime Appetite Branch (hunger <= 55 and food available)
	var seq_eat := BTComposite.BTSequence.new()
	seq_eat.set_abort_type(BTComposite.AbortType.SELF)
	seq_eat.friendly_name = "Mealtime Appetite Branch"
	var cond_hungry := VillagerConditionNeed.new()
	cond_hungry.parameters = {"need_type": "hunger", "threshold": 55.0, "operator": "<="}
	cond_hungry.friendly_name = "Hunger <= 55%?"
	var cond_food := VillagerConditionStock.new()
	cond_food.parameters = {"resource": "food", "min_amount": 1}
	cond_food.friendly_name = "Granary Food Stock > 0?"
	var sub_eat_reg := BTSubTree.new("demo/complex/villager_subtrees/eat_routine.json")
	sub_eat_reg.friendly_name = "SubTree: Mealtime Routine"
	bt.connect_parent_child(root_sel, seq_eat)
	bt.connect_parent_child(seq_eat, cond_hungry)
	bt.connect_parent_child(seq_eat, cond_food)
	bt.connect_parent_child(seq_eat, sub_eat_reg)

	# 6. Evening Campfire Social Branch (phase == "evening" and social <= 75)
	var seq_social := BTComposite.BTSequence.new()
	seq_social.set_abort_type(BTComposite.AbortType.SELF)
	seq_social.friendly_name = "Evening Campfire Social Branch"
	var cond_eve := VillagerConditionSchedule.new()
	cond_eve.parameters = {"phase": "evening"}
	cond_eve.friendly_name = "Is Evening?"
	var cond_soc := VillagerConditionNeed.new()
	cond_soc.parameters = {"need_type": "social", "threshold": 75.0, "operator": "<="}
	cond_soc.friendly_name = "Social <= 75%?"
	var sub_soc := BTSubTree.new("demo/complex/villager_subtrees/socialize_routine.json")
	sub_soc.friendly_name = "SubTree: Campfire Social"
	bt.connect_parent_child(root_sel, seq_social)
	bt.connect_parent_child(seq_social, cond_eve)
	bt.connect_parent_child(seq_social, cond_soc)
	bt.connect_parent_child(seq_social, sub_soc)

	# 7. Day Work Shift Branch (phase in ["morning", "afternoon"])
	var seq_work := BTComposite.BTSequence.new()
	seq_work.set_abort_type(BTComposite.AbortType.SELF)
	seq_work.friendly_name = "Day Work Shift Branch"
	var cond_work := VillagerConditionSchedule.new()
	cond_work.parameters = {"phase": "work"}
	cond_work.friendly_name = "Is Work Hours?"
	var sub_job := BTSubTree.new(job_path)
	sub_job.friendly_name = "SubTree: Job Shift (%s)" % v.role.capitalize()
	bt.connect_parent_child(root_sel, seq_work)
	bt.connect_parent_child(seq_work, cond_work)
	bt.connect_parent_child(seq_work, sub_job)

	# 8. Morning Prep Shift Branch
	var seq_prep := BTComposite.BTSequence.new()
	seq_prep.set_abort_type(BTComposite.AbortType.SELF)
	seq_prep.friendly_name = "Morning Preparation Branch"
	var cond_morn := VillagerConditionSchedule.new()
	cond_morn.parameters = {"phase": "morning"}
	cond_morn.friendly_name = "Is Morning Phase?"
	var sub_job_morn := BTSubTree.new(job_path)
	sub_job_morn.friendly_name = "SubTree: Morning Job Readiness"
	bt.connect_parent_child(root_sel, seq_prep)
	bt.connect_parent_child(seq_prep, cond_morn)
	bt.connect_parent_child(seq_prep, sub_job_morn)

	# 9. Plaza Leisure Walk (free time)
	var seq_plaza := BTComposite.BTSequence.new()
	seq_plaza.friendly_name = "Plaza Stroll Leisure Branch"
	var cond_free := VillagerConditionSchedule.new()
	cond_free.parameters = {"phase": "free"}
	cond_free.friendly_name = "Is Free Hours?"
	var act_walk_plaza := VillagerActionMoveTo.new()
	act_walk_plaza.parameters = {"location": "plaza", "ticks": 1}
	act_walk_plaza.friendly_name = "Walk to Plaza"
	var act_chat := VillagerActionSocialize.new()
	act_chat.parameters = {"activity": "chat", "social_restore": 15.0, "ticks": 1}
	act_chat.friendly_name = "Chat with Passing Villagers"
	bt.connect_parent_child(root_sel, seq_plaza)
	bt.connect_parent_child(seq_plaza, cond_free)
	bt.connect_parent_child(seq_plaza, act_walk_plaza)
	bt.connect_parent_child(seq_plaza, act_chat)

	# 10. Colony Idle Standby Fallback
	var seq_idle := BTComposite.BTSequence.new()
	seq_idle.friendly_name = "Village Standby Fallback"
	var act_idle := VillagerActionIdle.new()
	act_idle.parameters = {"ticks": 1}
	act_idle.friendly_name = "Rest and Catch Breath"
	var act_contemplate := VillagerActionWork.new()
	act_contemplate.parameters = {"job_action": "contemplate_village", "ticks": 1}
	act_contemplate.friendly_name = "Contemplate Colony Growth"
	bt.connect_parent_child(root_sel, seq_idle)
	bt.connect_parent_child(seq_idle, act_idle)
	bt.connect_parent_child(seq_idle, act_contemplate)

	return bt

# ------------------------------------------------ Simulation Loop

func tick_manual(delta: float = 0.1) -> void:
	total_simulation_ticks += 1
	_ready_timer += 1

	# 1. Advance Colony Clock (0.05 hr = 3 minutes per tick)
	colony_time += 0.05
	if colony_time >= 24.0:
		colony_time -= 24.0
		day_count += 1

	# Determine Schedule Phase
	if colony_time >= 6.0 and colony_time < 12.0:
		current_phase = "morning"
	elif colony_time >= 12.0 and colony_time < 18.0:
		current_phase = "afternoon"
	elif colony_time >= 18.0 and colony_time < 22.0:
		current_phase = "evening"
	else:
		current_phase = "night"

	# 2. Cycle dynamic task states every few ticks
	if _ready_timer % 4 == 0:
		for k in _task_states:
			_task_states[k] = true

	# 3. Needs Decay and Village Tick
	for v in villagers:
		# Hunger decays continuously
		v.hunger = max(0.0, v.hunger - 0.08)
		# Energy decays while awake
		if current_phase != "night":
			v.energy = max(0.0, v.energy - 0.06)
		# Social decays
		v.social = max(0.0, v.social - 0.05)
		# Safety: 0 during threat attack, 100 otherwise
		if threat_active:
			v.safety = 0.0
		else:
			v.safety = min(100.0, v.safety + 5.0)

		# 4. Tick Behavior Tree Runner with µs timing
		if v.runner != null and is_instance_valid(v.runner) and v.runner.is_running:
			var t0 := Time.get_ticks_usec()
			v.runner.tick(delta)
			var elapsed := Time.get_ticks_usec() - t0
			tick_times_usec.append(elapsed)

	_update_ui()
	if arena_control != null:
		arena_control.queue_redraw()

func is_task_ready(key: String) -> bool:
	return _task_states.get(key, true)

func spawn_threat() -> void:
	threat_active = true
	wolf_health = 4
	for v in villagers:
		v.safety = 0.0
	_update_ui()
	if arena_control != null:
		arena_control.queue_redraw()

func clear_threat() -> void:
	threat_active = false
	for v in villagers:
		v.safety = 100.0
	_update_ui()
	if arena_control != null:
		arena_control.queue_redraw()

func feed_all() -> void:
	food_stock += 15
	for v in villagers:
		v.hunger = min(100.0, v.hunger + 40.0)
	_update_ui()
	if arena_control != null:
		arena_control.queue_redraw()

func advance_time(hours: float) -> void:
	colony_time += hours
	while colony_time >= 24.0:
		colony_time -= 24.0
		day_count += 1
	_update_ui()
	if arena_control != null:
		arena_control.queue_redraw()

func reset_demo() -> void:
	colony_time = 8.0
	day_count = 1
	food_stock = 35
	village_gold = 20
	threat_active = false
	wolf_health = 4
	total_simulation_ticks = 0
	tick_times_usec.clear()
	global_executed_node_keys.clear()

	for v in villagers:
		if v.runner != null and is_instance_valid(v.runner):
			v.runner.stop()
			v.runner.free()
			v.runner = null

	_init_colony()
	_update_ui()
	if arena_control != null:
		arena_control.queue_redraw()

# ------------------------------------------------ Verification & Metrics APIs

var _cached_subtree_node_count: int = -1

func get_total_node_count() -> int:
	var total := get_main_trees_node_count() + get_subtree_files_node_count()
	return total

func get_main_trees_node_count() -> int:
	var sum := 0
	for v in villagers:
		if v.tree != null:
			sum += v.tree.get_node_count()
	return sum

func get_subtree_files_node_count() -> int:
	if _cached_subtree_node_count >= 0:
		return _cached_subtree_node_count
	if tree_source == null:
		return 0
	var sum := 0
	var trees := tree_source.list_trees()
	for tname in trees:
		var st: BTTree = tree_source.load_tree(tname)
		if st != null:
			sum += st.get_node_count()
	_cached_subtree_node_count = sum
	return sum

func get_executed_node_count() -> int:
	return global_executed_node_keys.size()

func get_coverage_ratio() -> float:
	var total := get_total_node_count()
	if total == 0: return 0.0
	return float(get_executed_node_count()) / float(total)

func get_tick_percentiles() -> Dictionary:
	if tick_times_usec.is_empty():
		return {"p50": 0, "p90": 0, "p99": 0, "count": 0}
	var sorted := tick_times_usec.duplicate()
	sorted.sort()
	var n := sorted.size()
	var p50: int = sorted[int(n * 0.50)]
	var p90: int = sorted[int(n * 0.90)]
	var p99: int = sorted[int(n * 0.99)]
	return {"p50": p50, "p90": p90, "p99": p99, "count": n}

func assert_lifecycle_balance() -> Dictionary:
	var all_balanced := true
	var details := []
	for v in villagers:
		# If the runner is currently active/running, exactly 1 active leaf action is currently executing.
		# When stopped/aborted, starts == ends + aborts exactly.
		var active_running_tasks := 1 if (v.runner != null and v.runner.is_running) else 0
		var balanced := (v.total_starts == v.total_ends + v.total_aborts + active_running_tasks)
		if not balanced: all_balanced = false
		if v.double_abort_errors > 0 or v.update_without_start_errors > 0 or v.end_without_start_errors > 0:
			all_balanced = false
		details.append({
			"name": v.name,
			"starts": v.total_starts,
			"ends": v.total_ends,
			"aborts": v.total_aborts,
			"active_running": active_running_tasks,
			"double_aborts": v.double_abort_errors,
			"update_without_starts": v.update_without_start_errors,
			"balanced": balanced
		})
	return {"all_balanced": all_balanced, "villagers": details}

# ------------------------------------------------ UI Setup & Custom Drawing

func _build_ui() -> void:
	# Root dark background (raw anchors to prevent 0x0 bug in 4.7)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.10)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	var main_vbox := VBoxContainer.new()
	main_vbox.anchor_right = 1.0
	main_vbox.anchor_bottom = 1.0
	main_vbox.offset_left = 10
	main_vbox.offset_top = 8
	main_vbox.offset_right = -10
	main_vbox.offset_bottom = -8
	main_vbox.add_theme_constant_override("separation", 6)
	add_child(main_vbox)

	# 1. Top Navigation & Global Controls Bar
	var nav_bar := HBoxContainer.new()
	nav_bar.add_theme_constant_override("separation", 6)
	main_vbox.add_child(nav_bar)

	var btn_hub := Button.new()
	btn_hub.text = "⮌ Hub"
	btn_hub.pressed.connect(func(): get_tree().change_scene_to_file(HUB_SCENE_PATH))
	nav_bar.add_child(btn_hub)

	var btn_boss := Button.new()
	btn_boss.text = "Boss AI"
	btn_boss.pressed.connect(func(): get_tree().change_scene_to_file(BOSS_SCENE_PATH))
	nav_bar.add_child(btn_boss)

	var btn_squad := Button.new()
	btn_squad.text = "Squad AI"
	btn_squad.pressed.connect(func(): get_tree().change_scene_to_file(SQUAD_SCENE_PATH))
	nav_bar.add_child(btn_squad)

	var btn_guard := Button.new()
	btn_guard.text = "Guard AI"
	btn_guard.pressed.connect(func(): get_tree().change_scene_to_file(GUARD_SCENE_PATH))
	nav_bar.add_child(btn_guard)

	var title_lbl := Label.new()
	title_lbl.text = "Colony Life-Sim"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_bar.add_child(title_lbl)

	# Action Controls
	var btn_threat := Button.new()
	btn_threat.text = "Threat"
	btn_threat.pressed.connect(func():
		if threat_active: clear_threat()
		else: spawn_threat()
	)
	nav_bar.add_child(btn_threat)

	var btn_feed := Button.new()
	btn_feed.text = "Feed"
	btn_feed.pressed.connect(feed_all)
	nav_bar.add_child(btn_feed)

	var btn_time := Button.new()
	btn_time.text = "+4h"
	btn_time.pressed.connect(func(): advance_time(4.0))
	nav_bar.add_child(btn_time)

	var btn_step := Button.new()
	btn_step.text = "Step"
	btn_step.pressed.connect(func(): tick_manual(0.1))
	nav_bar.add_child(btn_step)

	auto_tick_button = Button.new()
	auto_tick_button.text = "Pause" if auto_tick else "Auto"
	auto_tick_button.pressed.connect(func():
		auto_tick = not auto_tick
		auto_tick_button.text = "Pause" if auto_tick else "Auto"
	)
	nav_bar.add_child(auto_tick_button)

	var btn_reset := Button.new()
	btn_reset.text = "Reset"
	btn_reset.pressed.connect(reset_demo)
	nav_bar.add_child(btn_reset)

	# 2. Main Area Split: Left Arena (Map) / Right Dashboard (Cards)
	var content_hbox := HBoxContainer.new()
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", 10)
	main_vbox.add_child(content_hbox)

	# Left: Colony Arena
	var arena_panel := PanelContainer.new()
	arena_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arena_panel.size_flags_stretch_ratio = 1.0
	content_hbox.add_child(arena_panel)

	arena_control = Control.new()
	arena_control.draw.connect(_on_draw_arena)
	arena_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	arena_panel.add_child(arena_control)

	# Right: Colony Dashboard & Villager Cards Scroll
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 1.0
	content_hbox.add_child(right_panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	right_panel.add_child(scroll)

	var dash_vbox := VBoxContainer.new()
	dash_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dash_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(dash_vbox)

	# Status Summary Header
	var summary_box := VBoxContainer.new()
	summary_box.add_theme_constant_override("separation", 2)
	dash_vbox.add_child(summary_box)

	clock_label = Label.new()
	clock_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	clock_label.text = "Day 1 - 08:00 AM (Morning)"
	summary_box.add_child(clock_label)

	food_gold_label = Label.new()
	food_gold_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	food_gold_label.text = "Granary: 35 food | Treasury: 20 gold"
	summary_box.add_child(food_gold_label)

	threat_label = Label.new()
	threat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	threat_label.text = "Threat: Village Safe"
	summary_box.add_child(threat_label)

	node_count_label = Label.new()
	node_count_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node_count_label.text = "Total Active Nodes: %d (Main: %d + Subtrees: %d)" % [get_total_node_count(), get_main_trees_node_count(), get_subtree_files_node_count()]
	summary_box.add_child(node_count_label)

	coverage_label = Label.new()
	coverage_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	coverage_label.text = "Executed Coverage: 0% | p50: 0µs p99: 0µs"
	summary_box.add_child(coverage_label)

	# Blackboard Scoping Live Proof Panel
	var scoping_panel := PanelContainer.new()
	dash_vbox.add_child(scoping_panel)
	var scoping_vbox := VBoxContainer.new()
	scoping_panel.add_child(scoping_vbox)

	var sc_title := Label.new()
	sc_title.text = "Blackboard Scoping Demonstration:"
	sc_title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.4))
	scoping_vbox.add_child(sc_title)

	scoping_label = Label.new()
	scoping_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scoping_label.text = "is_shared: true -> Lives in parent scope (visible on villager BB)\nis_shared: false -> Private to subtree (isolated in child scope)"
	scoping_vbox.add_child(scoping_label)

	# Villager Cards Container
	villager_cards_container = VBoxContainer.new()
	villager_cards_container.add_theme_constant_override("separation", 6)
	dash_vbox.add_child(villager_cards_container)

	_build_villager_cards()

func _style_bar(bar: ProgressBar, fill_col: Color) -> void:
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = Color(0.14, 0.17, 0.22)
	bg_sb.corner_radius_top_left = 3
	bg_sb.corner_radius_bottom_left = 3
	bg_sb.corner_radius_top_right = 3
	bg_sb.corner_radius_bottom_right = 3

	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = fill_col
	fill_sb.corner_radius_top_left = 3
	fill_sb.corner_radius_bottom_left = 3
	fill_sb.corner_radius_top_right = 3
	fill_sb.corner_radius_bottom_right = 3

	bar.add_theme_stylebox_override("background", bg_sb)
	bar.add_theme_stylebox_override("fill", fill_sb)

func _build_villager_cards() -> void:
	for child in villager_cards_container.get_children():
		child.queue_free()

	for v in villagers:
		var card := PanelContainer.new()
		var card_sb := StyleBoxFlat.new()
		card_sb.bg_color = Color(0.09, 0.12, 0.16, 0.95)
		card_sb.border_width_left = 4
		card_sb.border_color = v.color
		card_sb.corner_radius_top_left = 4
		card_sb.corner_radius_bottom_left = 4
		card_sb.corner_radius_top_right = 4
		card_sb.corner_radius_bottom_right = 4
		card_sb.content_margin_left = 8
		card_sb.content_margin_top = 6
		card_sb.content_margin_right = 8
		card_sb.content_margin_bottom = 6
		card.add_theme_stylebox_override("panel", card_sb)

		var card_vbox := VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", 2)
		card.add_child(card_vbox)

		# Header
		var header := HBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.text = "%s (%s)" % [v.name, v.role.capitalize()]
		name_lbl.add_theme_color_override("font_color", v.color)
		header.add_child(name_lbl)

		var sub_badge := Label.new()
		sub_badge.name = "SubtreeBadge_%d" % v.id
		sub_badge.text = " — [%s]" % v.current_subtree_name
		sub_badge.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
		header.add_child(sub_badge)
		card_vbox.add_child(header)

		# Action & Location
		var act_lbl := Label.new()
		act_lbl.name = "ActionLabel_%d" % v.id
		act_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		act_lbl.text = "Action: %s @ %s" % [v.current_action_name, v.current_location_name]
		card_vbox.add_child(act_lbl)

		# Need Progress Bars (4 columns: Hunger & Energy on row 1, Social & Safety on row 2)
		var needs_grid := GridContainer.new()
		needs_grid.columns = 4
		needs_grid.add_theme_constant_override("h_separation", 6)
		needs_grid.add_theme_constant_override("v_separation", 2)
		card_vbox.add_child(needs_grid)

		# Hunger
		var h_lbl := Label.new()
		h_lbl.text = "Hunger:"
		needs_grid.add_child(h_lbl)
		var h_bar := ProgressBar.new()
		h_bar.name = "HungerBar_%d" % v.id
		h_bar.value = v.hunger
		h_bar.custom_minimum_size = Vector2(90, 13)
		h_bar.show_percentage = true
		_style_bar(h_bar, Color(0.85, 0.55, 0.25))
		needs_grid.add_child(h_bar)

		# Energy
		var e_lbl := Label.new()
		e_lbl.text = "Energy:"
		needs_grid.add_child(e_lbl)
		var e_bar := ProgressBar.new()
		e_bar.name = "EnergyBar_%d" % v.id
		e_bar.value = v.energy
		e_bar.custom_minimum_size = Vector2(90, 13)
		e_bar.show_percentage = true
		_style_bar(e_bar, Color(0.25, 0.75, 0.45))
		needs_grid.add_child(e_bar)

		# Social
		var s_lbl := Label.new()
		s_lbl.text = "Social:"
		needs_grid.add_child(s_lbl)
		var s_bar := ProgressBar.new()
		s_bar.name = "SocialBar_%d" % v.id
		s_bar.value = v.social
		s_bar.custom_minimum_size = Vector2(90, 13)
		s_bar.show_percentage = true
		_style_bar(s_bar, Color(0.85, 0.35, 0.75))
		needs_grid.add_child(s_bar)

		# Safety
		var safe_lbl := Label.new()
		safe_lbl.text = "Safety:"
		needs_grid.add_child(safe_lbl)
		var safe_bar := ProgressBar.new()
		safe_bar.name = "SafetyBar_%d" % v.id
		safe_bar.value = v.safety
		safe_bar.custom_minimum_size = Vector2(90, 13)
		safe_bar.show_percentage = true
		_style_bar(safe_bar, Color(0.25, 0.65, 0.95))
		needs_grid.add_child(safe_bar)

		# Scoped Variables Live Line
		var vars_lbl := Label.new()
		vars_lbl.name = "VarsLabel_%d" % v.id
		vars_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card_vbox.add_child(vars_lbl)

		# Lifecycle Stats
		var stats_lbl := Label.new()
		stats_lbl.name = "StatsLabel_%d" % v.id
		stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card_vbox.add_child(stats_lbl)

		villager_cards_container.add_child(card)

func _update_ui() -> void:
	if clock_label == null: return

	var hr := int(colony_time)
	var mn := int((colony_time - float(hr)) * 60.0)
	var ampm := "AM" if hr < 12 else "PM"
	var disp_hr := hr if hr <= 12 else hr - 12
	if disp_hr == 0: disp_hr = 12
	clock_label.text = "Day %d - %02d:%02d %s [%s Cycle]" % [day_count, disp_hr, mn, ampm, current_phase.capitalize()]

	food_gold_label.text = "Granary: %d food | Treasury: %d gold" % [food_stock, village_gold]

	if threat_active:
		threat_label.text = "⚠️ EMERGENCY: Wolf Attack Active! (Wolf HP: %d)" % wolf_health
		threat_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	else:
		threat_label.text = "Threat: Village Peaceful & Safe"
		threat_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))

	node_count_label.text = "Total Active Nodes: %d (Main: %d + Subtrees: %d)" % [get_total_node_count(), get_main_trees_node_count(), get_subtree_files_node_count()]

	var cov := get_coverage_ratio() * 100.0
	var percs := get_tick_percentiles()
	coverage_label.text = "Executed Nodes: %d/%d (%.1f%%) | Tick p50: %dµs p99: %dµs" % [get_executed_node_count(), get_total_node_count(), cov, percs["p50"], percs["p99"]]

	# Scoping demonstration text
	if villagers.size() > 0:
		var v0 := villagers[0]
		var v_guard := villagers[2]
		var f_prod: Variant = v0.tree.blackboard.get_var("food_produced", 0) if v0.tree != null else 0
		var has_priv: bool = v0.tree.blackboard.has_var("field_harvest_count") if v0.tree != null else false
		var rep_count: Variant = v_guard.tree.blackboard.get_var("patrol_reports", 0) if v_guard.tree != null else 0
		var guard_priv: bool = v_guard.tree.blackboard.has_var("drill_reps") if v_guard.tree != null else false

		scoping_label.text = "• Alden: 'food_produced'=%s (Shared: Parent has=true) | 'field_harvest_count' (Private: Parent has=%s)\n• Cedric: 'patrol_reports'=%s (Shared: Parent has=true) | 'drill_reps' (Private: Parent has=%s)" % [
			str(f_prod), str(has_priv), str(rep_count), str(guard_priv)
		]

	# Update cards
	for v in villagers:
		var sub_badge: Label = villager_cards_container.find_child("SubtreeBadge_%d" % v.id, true, false)
		if sub_badge != null:
			sub_badge.text = " — [%s]" % v.current_subtree_name

		var act_lbl: Label = villager_cards_container.find_child("ActionLabel_%d" % v.id, true, false)
		if act_lbl != null:
			act_lbl.text = "Action: %s (@ %s)" % [v.current_action_name, v.current_location_name]

		var h_bar: ProgressBar = villager_cards_container.find_child("HungerBar_%d" % v.id, true, false)
		if h_bar != null: h_bar.value = v.hunger
		var e_bar: ProgressBar = villager_cards_container.find_child("EnergyBar_%d" % v.id, true, false)
		if e_bar != null: e_bar.value = v.energy
		var s_bar: ProgressBar = villager_cards_container.find_child("SocialBar_%d" % v.id, true, false)
		if s_bar != null: s_bar.value = v.social
		var safe_bar: ProgressBar = villager_cards_container.find_child("SafetyBar_%d" % v.id, true, false)
		if safe_bar != null: safe_bar.value = v.safety

		var vars_lbl: Label = villager_cards_container.find_child("VarsLabel_%d" % v.id, true, false)
		if vars_lbl != null and v.tree != null:
			match v.role:
				"farmer":
					vars_lbl.text = "Shared 'food_produced': %s | Private 'field_harvest_count' in parent: %s" % [
						str(v.tree.blackboard.get_var("food_produced", 0)),
						"NO (isolated)" if not v.tree.blackboard.has_var("field_harvest_count") else "LEAKED"
					]
				"guard":
					vars_lbl.text = "Shared 'patrol_reports': %s | Private 'drill_reps' in parent: %s" % [
						str(v.tree.blackboard.get_var("patrol_reports", 0)),
						"NO (isolated)" if not v.tree.blackboard.has_var("drill_reps") else "LEAKED"
					]
				"merchant":
					vars_lbl.text = "Shared 'village_gold': %s | Private 'coins_counted' in parent: %s" % [
						str(v.tree.blackboard.get_var("village_gold", 0)),
						"NO (isolated)" if not v.tree.blackboard.has_var("coins_counted") else "LEAKED"
					]
				"cook":
					vars_lbl.text = "Shared 'meals_served': %s | Private 'veggies_chopped' in parent: %s" % [
						str(v.tree.blackboard.get_var("meals_served", 0)),
						"NO (isolated)" if not v.tree.blackboard.has_var("veggies_chopped") else "LEAKED"
					]

		var stats_lbl: Label = villager_cards_container.find_child("StatsLabel_%d" % v.id, true, false)
		if stats_lbl != null:
			var balanced := (v.total_starts == v.total_ends + v.total_aborts)
			stats_lbl.text = "Starts: %d | Ends: %d | Aborts: %d [%s]" % [
				v.total_starts, v.total_ends, v.total_aborts,
				"✓ Balanced" if balanced else "⚠ Unbalanced"
			]
			stats_lbl.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6) if balanced else Color(1.0, 0.4, 0.4))


# ------------------------------------------------ Custom Arena Drawing

func _on_draw_arena() -> void:
	if arena_control == null: return
	var size := arena_control.size

	# 1. Base terrain ground
	var ground_color := Color(0.12, 0.16, 0.14)
	arena_control.draw_rect(Rect2(Vector2.ZERO, size), ground_color)

	# 2. Roads and plaza paths
	var road_color := Color(0.24, 0.22, 0.18)
	arena_control.draw_circle(Vector2(300, 270), 55.0, road_color) # Central Plaza
	arena_control.draw_line(Vector2(140, 210), Vector2(300, 270), road_color, 12.0) # Homes to plaza
	arena_control.draw_line(Vector2(300, 270), Vector2(180, 440), road_color, 10.0) # Plaza to fields
	arena_control.draw_line(Vector2(300, 270), Vector2(410, 190), road_color, 10.0) # Plaza to north gate
	arena_control.draw_line(Vector2(300, 270), Vector2(330, 400), road_color, 10.0) # Plaza to tavern

	# 3. Buildings & Landmarks
	# Town Hall / Safe Bunker (Top Left)
	arena_control.draw_rect(Rect2(Vector2(90, 80), Vector2(80, 60)), Color(0.25, 0.28, 0.32))
	arena_control.draw_string(ThemeDB.fallback_font, Vector2(95, 75), "Town Hall", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.9, 0.9))

	# Villager Homes (Left)
	arena_control.draw_rect(Rect2(Vector2(90, 150), Vector2(85, 130)), Color(0.32, 0.24, 0.18))
	arena_control.draw_string(ThemeDB.fallback_font, Vector2(95, 145), "Cottages", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.85, 0.75, 0.65))

	# Farm Fields & Orchard (Bottom Left)
	arena_control.draw_rect(Rect2(Vector2(70, 400), Vector2(180, 110)), Color(0.22, 0.30, 0.16))
	arena_control.draw_string(ThemeDB.fallback_font, Vector2(75, 395), "Wheat Fields & Orchard", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.85, 0.85, 0.5))

	# Market Stall & Warehouse (Top Center)
	arena_control.draw_rect(Rect2(Vector2(290, 130), Vector2(100, 60)), Color(0.35, 0.22, 0.32))
	arena_control.draw_string(ThemeDB.fallback_font, Vector2(295, 125), "Market & Stores", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.75, 0.85))

	# Tavern & Kitchen (Bottom Center)
	arena_control.draw_rect(Rect2(Vector2(260, 350), Vector2(120, 80)), Color(0.36, 0.24, 0.16))
	arena_control.draw_string(ThemeDB.fallback_font, Vector2(265, 345), "Tavern & Hearth", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.95, 0.85, 0.6))

	# Defense Walls & Watchtower (Right)
	arena_control.draw_line(Vector2(410, 80), Vector2(410, 520), Color(0.4, 0.35, 0.3), 8.0)
	arena_control.draw_circle(Vector2(440, 120), 22.0, Color(0.35, 0.40, 0.45))
	arena_control.draw_string(ThemeDB.fallback_font, Vector2(425, 95), "Tower", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1))
	arena_control.draw_rect(Rect2(Vector2(395, 175), Vector2(30, 35)), Color(0.5, 0.25, 0.2))
	arena_control.draw_string(ThemeDB.fallback_font, Vector2(398, 170), "Gate", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1))

	# Central Campfire
	var fire_glow_color := Color(1.0, 0.55, 0.15, 0.4)
	arena_control.draw_circle(Vector2(300, 270), 18.0, fire_glow_color)
	arena_control.draw_circle(Vector2(300, 270), 8.0, Color(1.0, 0.8, 0.2))

	# 4. Draw Threat (Wolf) when active
	if threat_active:
		var w_pos := threat_pos
		arena_control.draw_circle(w_pos, 16.0, Color(0.9, 0.2, 0.2, 0.5))
		arena_control.draw_circle(w_pos, 10.0, Color(0.8, 0.1, 0.1))
		arena_control.draw_string(ThemeDB.fallback_font, w_pos + Vector2(-20, -14), "WOLF PACK", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.3, 0.3))

	# 5. Draw 6 Villagers
	for v in villagers:
		var p := v.position
		# Movement vector line if in transit
		if p.distance_to(v.target_position) > 4.0:
			arena_control.draw_line(p, v.target_position, v.color * Color(1, 1, 1, 0.4), 2.0)

		# Villager Avatar circle
		arena_control.draw_circle(p, 12.0, v.color)
		arena_control.draw_circle(p, 10.0, Color(0.1, 0.1, 0.12))

		# Initials inside avatar
		var initial := v.name.substr(0, 1)
		arena_control.draw_string(ThemeDB.fallback_font, p + Vector2(-4, 4), initial, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, v.color)

		# Centered villager name right below or above avatar (staggered to prevent overlap)
		var tag_y: float = p.y + 16 if (v.id % 2 == 0) else p.y - 24
		arena_control.draw_string(ThemeDB.fallback_font, Vector2(p.x - 25, tag_y), v.name, HORIZONTAL_ALIGNMENT_CENTER, 50, 10, Color(1.0, 1.0, 0.85))

	# 6. Ambient Day/Night Lighting Overlay
	var ambient_color := Color(0, 0, 0, 0)
	match current_phase:
		"morning": ambient_color = Color(1.0, 0.9, 0.7, 0.05) # Warm sunrise glow
		"afternoon": ambient_color = Color(1.0, 1.0, 1.0, 0.0) # Clear bright daylight
		"evening": ambient_color = Color(0.9, 0.5, 0.3, 0.12) # Golden amber dusk
		"night": ambient_color = Color(0.05, 0.08, 0.25, 0.40) # Deep midnight blue
	arena_control.draw_rect(Rect2(Vector2.ZERO, size), ambient_color)
