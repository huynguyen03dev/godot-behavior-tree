extends Control
## Complex Demo: Squad Tactical Coordination AI with Shared Blackboard & Mutual Exclusion.
##
## Demonstrates multi-agent decentralized role negotiation:
## - 4 independent agents driven by individual BTRunners.
## - 1 shared BTBlackboard coordinating tactical assignments.
## - Atomic role claims (Attacker, Flanker, Reloader, Reserve).
## - Strict mutual exclusion: an agent cannot hold multiple roles; single-occupant roles cannot double-book.
## - Dynamic role rebalancing when an agent depletes ammo or is killed in action.

const HUB_SCENE_PATH := "res://demo/complex/complex_demo.tscn"
const BOSS_SCENE_PATH := "res://demo/complex/boss_demo.tscn"
const GUARD_SCENE_PATH := "res://demo/complex/guard_stealth_demo.tscn"

class SquadAgent:
	var id: int
	var pos: Vector2i
	var ammo: int = 5
	var is_alive: bool = true
	var current_role: String = "None"
	var runner: BTRunner
	var tree: BTTree
	var color: Color

	func _init(p_id: int, p_pos: Vector2i, p_ammo: int, p_color: Color) -> void:
		id = p_id
		pos = p_pos
		ammo = p_ammo
		color = p_color

# Simulation state
var shared_bb: BTBlackboard = null
var agents: Array[SquadAgent] = []
var target_pos: Vector2i = Vector2i(5, 5)
var mutex_violations: int = 0
var tick_count: int = 0

var auto_tick: bool = false
var tick_timer: float = 0.0
var tick_interval: float = 0.35

# UI References
var field_rect: Control = null
var auto_tick_button: Button = null
var roles_label: Label = null
var mutex_label: Label = null
var agent_cards_vbox: VBoxContainer = null

# ---------------------------------------------------------------- BT Tasks

class ConditionNeedsReload extends BTTask:
	var agent: SquadAgent

	func _init(p_agent: SquadAgent) -> void:
		agent = p_agent
		type_name = "ConditionNeedsReload"
		category = "Condition"

	func evaluate_condition(_runner: BTRunner) -> int:
		return BTStatus.SUCCESS if (agent.is_alive and agent.ammo <= 0) else BTStatus.FAILURE

	func on_update() -> int:
		return evaluate_condition(owner as BTRunner)


class ActionReload extends BTTask:
	var agent: SquadAgent
	var reload_ticks := 2

	func _init(p_agent: SquadAgent) -> void:
		agent = p_agent
		type_name = "ActionReload"
		category = "Action"

	func on_start() -> void:
		reload_ticks = 2
		agent.current_role = "Reloader"
		set_blackboard_var("reloader_id", agent.id)

	func on_update() -> int:
		reload_ticks -= 1
		if reload_ticks <= 0:
			agent.ammo = 5
			set_blackboard_var("reloader_id", -1)
			agent.current_role = "None"
			return BTStatus.SUCCESS
		return BTStatus.RUNNING

	func on_abort() -> void:
		if get_blackboard_var("reloader_id", -1) == agent.id:
			set_blackboard_var("reloader_id", -1)
		agent.current_role = "None"
		super.on_abort()


class ConditionCanBeAttacker extends BTTask:
	var agent: SquadAgent

	func _init(p_agent: SquadAgent) -> void:
		agent = p_agent
		type_name = "ConditionCanBeAttacker"
		category = "Condition"

	func evaluate_condition(_runner: BTRunner) -> int:
		if not agent.is_alive or agent.ammo <= 0:
			return BTStatus.FAILURE
		var att: int = get_blackboard_var("attacker_id", -1)
		if att == -1 or att == agent.id:
			return BTStatus.SUCCESS
		return BTStatus.FAILURE

	func on_update() -> int:
		return evaluate_condition(owner as BTRunner)


class ActionAttackRole extends BTTask:
	var agent: SquadAgent

	func _init(p_agent: SquadAgent) -> void:
		agent = p_agent
		type_name = "ActionAttackRole"
		category = "Action"

	func on_start() -> void:
		agent.current_role = "Attacker"
		set_blackboard_var("attacker_id", agent.id)

	func on_update() -> int:
		if agent.ammo <= 0:
			if get_blackboard_var("attacker_id", -1) == agent.id:
				set_blackboard_var("attacker_id", -1)
			agent.current_role = "None"
			return BTStatus.FAILURE
		agent.ammo -= 1
		return BTStatus.RUNNING

	func on_abort() -> void:
		if get_blackboard_var("attacker_id", -1) == agent.id:
			set_blackboard_var("attacker_id", -1)
		agent.current_role = "None"
		super.on_abort()


class ConditionCanBeFlanker extends BTTask:
	var agent: SquadAgent

	func _init(p_agent: SquadAgent) -> void:
		agent = p_agent
		type_name = "ConditionCanBeFlanker"
		category = "Condition"

	func evaluate_condition(_runner: BTRunner) -> int:
		if not agent.is_alive or agent.ammo <= 0:
			return BTStatus.FAILURE
		var flk: int = get_blackboard_var("flanker_id", -1)
		if flk == -1 or flk == agent.id:
			return BTStatus.SUCCESS
		return BTStatus.FAILURE

	func on_update() -> int:
		return evaluate_condition(owner as BTRunner)


class ActionFlankRole extends BTTask:
	var agent: SquadAgent

	func _init(p_agent: SquadAgent) -> void:
		agent = p_agent
		type_name = "ActionFlankRole"
		category = "Action"

	func on_start() -> void:
		agent.current_role = "Flanker"
		set_blackboard_var("flanker_id", agent.id)

	func on_update() -> int:
		if agent.ammo <= 0:
			if get_blackboard_var("flanker_id", -1) == agent.id:
				set_blackboard_var("flanker_id", -1)
			agent.current_role = "None"
			return BTStatus.FAILURE
		return BTStatus.RUNNING

	func on_abort() -> void:
		if get_blackboard_var("flanker_id", -1) == agent.id:
			set_blackboard_var("flanker_id", -1)
		agent.current_role = "None"
		super.on_abort()


class ActionReserve extends BTTask:
	var agent: SquadAgent

	func _init(p_agent: SquadAgent) -> void:
		agent = p_agent
		type_name = "ActionReserve"
		category = "Action"

	func on_start() -> void:
		agent.current_role = "Reserve"

	func on_update() -> int:
		return BTStatus.RUNNING

	func on_abort() -> void:
		agent.current_role = "None"
		super.on_abort()

# ---------------------------------------------------------------- Tree Construction

func _build_agent_tree(agent: SquadAgent, p_shared_bb: BTBlackboard) -> BTTree:
	var bt := BTTree.new()
	bt.blackboard = p_shared_bb

	var rep := BTDecorator.BTRepeater.new()
	rep.repeat_forever = true
	bt.set_root(rep)

	var root_sel := BTComposite.BTSelector.new()
	root_sel.set_abort_type(BTComposite.AbortType.LOWER_PRIORITY)
	bt.connect_parent_child(rep, root_sel)

	# 1. Reloader Branch (Priority 1)
	var rel_seq := BTComposite.BTSequence.new()
	rel_seq.set_abort_type(BTComposite.AbortType.SELF)
	var cond_rel := ConditionNeedsReload.new(agent)
	var act_rel := ActionReload.new(agent)
	bt.connect_parent_child(root_sel, rel_seq)
	bt.connect_parent_child(rel_seq, cond_rel)
	bt.connect_parent_child(rel_seq, act_rel)

	# 2. Attacker Branch (Priority 2)
	var att_seq := BTComposite.BTSequence.new()
	att_seq.set_abort_type(BTComposite.AbortType.SELF)
	var cond_att := ConditionCanBeAttacker.new(agent)
	var act_att := ActionAttackRole.new(agent)
	bt.connect_parent_child(root_sel, att_seq)
	bt.connect_parent_child(att_seq, cond_att)
	bt.connect_parent_child(att_seq, act_att)

	# 3. Flanker Branch (Priority 3)
	var flk_seq := BTComposite.BTSequence.new()
	flk_seq.set_abort_type(BTComposite.AbortType.SELF)
	var cond_flk := ConditionCanBeFlanker.new(agent)
	var act_flk := ActionFlankRole.new(agent)
	bt.connect_parent_child(root_sel, flk_seq)
	bt.connect_parent_child(flk_seq, cond_flk)
	bt.connect_parent_child(flk_seq, act_flk)

	# 4. Reserve Branch (Fallback)
	var act_res := ActionReserve.new(agent)
	bt.connect_parent_child(root_sel, act_res)

	return bt

# ---------------------------------------------------------------- Lifecycle

func _ready() -> void:
	_init_simulation()

	# Headless check
	if DisplayServer.get_name() == "headless":
		auto_tick = false
	else:
		auto_tick = true

	_build_ui()
	_update_ui_state()

func _physics_process(delta: float) -> void:
	if not auto_tick:
		return
	tick_timer += delta
	if tick_timer >= tick_interval:
		tick_timer = 0.0
		tick_all(tick_interval)

func _exit_tree() -> void:
	_cleanup_runners()

func _cleanup_runners() -> void:
	for a in agents:
		if a.runner != null and is_instance_valid(a.runner):
			a.runner.stop()
			a.runner.free()
			a.runner = null
		a.tree = null
	agents.clear()

func _init_simulation() -> void:
	_cleanup_runners()
	agents.clear()
	mutex_violations = 0
	tick_count = 0

	shared_bb = BTBlackboard.new()
	shared_bb.set_var("attacker_id", -1)
	shared_bb.set_var("flanker_id", -1)
	shared_bb.set_var("reloader_id", -1)
	shared_bb.set_var("target_pos", target_pos)

	# Create 4 agents matching test_squad_ai.gd
	# Agent 0: 3 ammo (tests reload transition)
	# Agents 1-3: 5 ammo
	var a0 := SquadAgent.new(0, Vector2i(0, 0), 3, Color(0.25, 0.6, 0.95))
	var a1 := SquadAgent.new(1, Vector2i(0, 2), 5, Color(0.15, 0.8, 0.65))
	var a2 := SquadAgent.new(2, Vector2i(2, 0), 5, Color(0.95, 0.55, 0.2))
	var a3 := SquadAgent.new(3, Vector2i(1, 1), 5, Color(0.7, 0.4, 0.9))
	agents = [a0, a1, a2, a3]

	for a in agents:
		a.tree = _build_agent_tree(a, shared_bb)
		a.runner = BTRunner.new(a.tree)
		add_child(a.runner)
		a.runner.set_process(false)
		a.runner.start()

# ---------------------------------------------------------------- Simulation API

func check_mutual_exclusion() -> void:
	var attacker: int = shared_bb.get_var("attacker_id", -1)
	var flanker: int = shared_bb.get_var("flanker_id", -1)
	var reloader: int = shared_bb.get_var("reloader_id", -1)

	if attacker != -1 and attacker == flanker:
		mutex_violations += 1
	if attacker != -1 and attacker == reloader:
		mutex_violations += 1
	if flanker != -1 and flanker == reloader:
		mutex_violations += 1

func tick_all(delta: float = 0.1) -> void:
	tick_count += 1
	for a in agents:
		if a.is_alive and a.runner != null and is_instance_valid(a.runner) and a.runner.is_running:
			a.runner.tick(delta)
	check_mutual_exclusion()
	_update_ui_state()
	if field_rect != null:
		field_rect.queue_redraw()

func kill_agent(id: int) -> void:
	if id < 0 or id >= agents.size():
		return
	var a := agents[id]
	a.is_alive = false
	if a.runner != null and is_instance_valid(a.runner):
		a.runner.stop()
	a.current_role = "Dead"
	if shared_bb.get_var("attacker_id", -1) == id:
		shared_bb.set_var("attacker_id", -1)
	if shared_bb.get_var("flanker_id", -1) == id:
		shared_bb.set_var("flanker_id", -1)
	if shared_bb.get_var("reloader_id", -1) == id:
		shared_bb.set_var("reloader_id", -1)
	_update_ui_state()
	if field_rect != null:
		field_rect.queue_redraw()

func deplete_ammo(id: int) -> void:
	if id < 0 or id >= agents.size():
		return
	agents[id].ammo = 0
	_update_ui_state()
	if field_rect != null:
		field_rect.queue_redraw()

func reset_demo() -> void:
	_init_simulation()
	_update_ui_state()
	if field_rect != null:
		field_rect.queue_redraw()

# ---------------------------------------------------------------- UI Setup & Rendering

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.08, 0.12)
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

	# Top Navigation Bar
	var nav_bar := HBoxContainer.new()
	nav_bar.add_theme_constant_override("separation", 12)
	main_vbox.add_child(nav_bar)

	var btn_hub := Button.new()
	btn_hub.text = "⮌ Complex Hub"
	btn_hub.pressed.connect(func(): get_tree().change_scene_to_file(HUB_SCENE_PATH))
	nav_bar.add_child(btn_hub)

	var title_lbl := Label.new()
	title_lbl.text = "Squad AI Showcase: 4 Runners, 1 Shared Blackboard & Mutual Exclusion"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_bar.add_child(title_lbl)

	var btn_boss := Button.new()
	btn_boss.text = "Boss AI ➔"
	btn_boss.pressed.connect(func(): get_tree().change_scene_to_file(BOSS_SCENE_PATH))
	nav_bar.add_child(btn_boss)

	var btn_guard := Button.new()
	btn_guard.text = "Guard Stealth ➔"
	btn_guard.pressed.connect(func(): get_tree().change_scene_to_file(GUARD_SCENE_PATH))
	nav_bar.add_child(btn_guard)

	# Main Area
	var content_hbox := HBoxContainer.new()
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", 12)
	main_vbox.add_child(content_hbox)

	# Tactical Map Visualizer
	field_rect = Control.new()
	field_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field_rect.draw.connect(_on_field_draw)
	content_hbox.add_child(field_rect)

	# Right Panel: Controls & Roles
	var right_panel := PanelContainer.new()
	right_panel.custom_minimum_size = Vector2(380, 0)
	content_hbox.add_child(right_panel)

	var panel_vbox := VBoxContainer.new()
	panel_vbox.add_theme_constant_override("separation", 8)
	right_panel.add_child(panel_vbox)

	var roles_hdr := Label.new()
	roles_hdr.text = "=== SHARED BLACKBOARD ROLES ==="
	panel_vbox.add_child(roles_hdr)

	roles_label = Label.new()
	panel_vbox.add_child(roles_label)

	mutex_label = Label.new()
	panel_vbox.add_child(mutex_label)

	var agents_hdr := Label.new()
	agents_hdr.text = "=== AGENT STATUS & KILL SWITCHES ==="
	panel_vbox.add_child(agents_hdr)

	agent_cards_vbox = VBoxContainer.new()
	agent_cards_vbox.add_theme_constant_override("separation", 4)
	panel_vbox.add_child(agent_cards_vbox)

	for i in range(4):
		var card := Label.new()
		card.name = "AgentCard%d" % i
		agent_cards_vbox.add_child(card)

	var btn_kill_hbox := HBoxContainer.new()
	panel_vbox.add_child(btn_kill_hbox)

	for i in range(4):
		var btn_k := Button.new()
		btn_k.text = "Kill A%d" % i
		btn_k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_k.pressed.connect(func(): kill_agent(i))
		btn_kill_hbox.add_child(btn_k)

	var extra_ctrl_hbox := HBoxContainer.new()
	panel_vbox.add_child(extra_ctrl_hbox)

	var btn_deplete0 := Button.new()
	btn_deplete0.text = "Empty A0 Ammo"
	btn_deplete0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_deplete0.pressed.connect(func(): deplete_ammo(0))
	extra_ctrl_hbox.add_child(btn_deplete0)

	var btn_reset := Button.new()
	btn_reset.text = "↺ Reset Squad"
	btn_reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_reset.pressed.connect(reset_demo)
	extra_ctrl_hbox.add_child(btn_reset)

	var sim_hdr := Label.new()
	sim_hdr.text = "=== SIMULATION STEPPING ==="
	panel_vbox.add_child(sim_hdr)

	var step_hbox := HBoxContainer.new()
	panel_vbox.add_child(step_hbox)

	var btn_step := Button.new()
	btn_step.text = "▶ Step Tick (All Agents)"
	btn_step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_step.pressed.connect(func(): tick_all(0.1))
	step_hbox.add_child(btn_step)

	auto_tick_button = Button.new()
	auto_tick_button.text = "Auto-Tick: " + ("ON" if auto_tick else "OFF")
	auto_tick_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto_tick_button.pressed.connect(func():
		auto_tick = not auto_tick
		auto_tick_button.text = "Auto-Tick: " + ("ON" if auto_tick else "OFF")
	)
	step_hbox.add_child(auto_tick_button)

func _update_ui_state() -> void:
	if shared_bb == null:
		return

	var att: int = shared_bb.get_var("attacker_id", -1)
	var flk: int = shared_bb.get_var("flanker_id", -1)
	var rel: int = shared_bb.get_var("reloader_id", -1)

	if roles_label != null:
		roles_label.text = (
			"Attacker: %s\n" +
			"Flanker: %s\n" +
			"Reloader: %s"
		) % [
			"Agent " + str(att) if att != -1 else "None (-1)",
			"Agent " + str(flk) if flk != -1 else "None (-1)",
			"Agent " + str(rel) if rel != -1 else "None (-1)"
		]

	if mutex_label != null:
		if mutex_violations == 0:
			mutex_label.text = "Mutex Status: OK (0 violations)"
		else:
			mutex_label.text = "Mutex Status: VIOLATION DETECTED! (%d)" % mutex_violations

	if agent_cards_vbox != null:
		var cards := agent_cards_vbox.get_children()
		for i in range(min(cards.size(), agents.size())):
			var a := agents[i]
			var card := cards[i] as Label
			if card != null:
				var ammo_str := "●".repeat(a.ammo) + "○".repeat(max(0, 5 - a.ammo))
				card.text = "A%d: [%s] Ammo: %s (%d) Alive: %s" % [
					a.id, a.current_role, ammo_str, a.ammo, str(a.is_alive)
				]

func _on_field_draw() -> void:
	if field_rect == null:
		return
	var size := field_rect.size
	if size.x < 10 or size.y < 10:
		return

	# Background tactical grid
	field_rect.draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.13, 0.18), true)
	var cell_w := size.x / 10.0
	var cell_h := size.y / 8.0
	for x in range(11):
		field_rect.draw_line(Vector2(x * cell_w, 0), Vector2(x * cell_w, size.y), Color(0.16, 0.2, 0.28))
	for y in range(9):
		field_rect.draw_line(Vector2(0, y * cell_h), Vector2(size.x, y * cell_h), Color(0.16, 0.2, 0.28))

	# Target marker at grid (7, 4)
	var target_screen := Vector2(7.5 * cell_w, 4.0 * cell_h)
	field_rect.draw_circle(target_screen, 32.0, Color(0.85, 0.2, 0.2, 0.3))
	field_rect.draw_arc(target_screen, 32.0, 0.0, TAU, 32, Color(0.9, 0.2, 0.2), 2.0)
	field_rect.draw_line(target_screen + Vector2(-40, 0), target_screen + Vector2(40, 0), Color(0.9, 0.2, 0.2), 1.5)
	field_rect.draw_line(target_screen + Vector2(0, -40), target_screen + Vector2(0, 40), Color(0.9, 0.2, 0.2), 1.5)

	# Agent layout positions on screen
	var agent_screen_pos: Array[Vector2] = [
		Vector2(2.5 * cell_w, 2.0 * cell_h),
		Vector2(2.5 * cell_w, 3.5 * cell_h),
		Vector2(2.5 * cell_w, 5.0 * cell_h),
		Vector2(1.5 * cell_w, 3.5 * cell_h)
	]

	# Draw agents and interaction lines
	var att: int = shared_bb.get_var("attacker_id", -1) if shared_bb != null else -1
	var flk: int = shared_bb.get_var("flanker_id", -1) if shared_bb != null else -1

	# Attack laser line if active
	if att >= 0 and att < agents.size() and agents[att].is_alive and agents[att].current_role == "Attacker":
		field_rect.draw_line(agent_screen_pos[att], target_screen, Color(1.0, 0.9, 0.2), 3.0)

	# Flank arc if active
	if flk >= 0 and flk < agents.size() and agents[flk].is_alive and agents[flk].current_role == "Flanker":
		var flank_point := Vector2(7.5 * cell_w, 1.5 * cell_h)
		field_rect.draw_line(agent_screen_pos[flk], flank_point, Color(0.3, 0.8, 1.0, 0.7), 2.0)
		field_rect.draw_line(flank_point, target_screen, Color(0.3, 0.8, 1.0), 2.0)

	for i in range(agents.size()):
		var a := agents[i]
		var pos: Vector2 = agent_screen_pos[i]

		if not a.is_alive:
			field_rect.draw_circle(pos, 22.0, Color(0.2, 0.1, 0.1))
			field_rect.draw_line(pos + Vector2(-12, -12), pos + Vector2(12, 12), Color(0.8, 0.2, 0.2), 3.0)
			field_rect.draw_line(pos + Vector2(12, -12), pos + Vector2(-12, 12), Color(0.8, 0.2, 0.2), 3.0)
			continue

		# Agent body
		field_rect.draw_circle(pos, 24.0, a.color)
		field_rect.draw_arc(pos, 24.0, 0.0, TAU, 24, Color.WHITE, 2.0)

		# Role aura / badge
		var role_col := Color(0.5, 0.5, 0.5)
		match a.current_role:
			"Attacker": role_col = Color(0.9, 0.25, 0.2)
			"Flanker": role_col = Color(0.95, 0.8, 0.2)
			"Reloader": role_col = Color(0.2, 0.7, 1.0)
			"Reserve": role_col = Color(0.6, 0.65, 0.7)
		field_rect.draw_arc(pos, 30.0, 0.0, TAU, 24, role_col, 3.0)

		# Ammo dots beneath agent
		for d in range(5):
			var dot_pos := pos + Vector2(-16.0 + float(d) * 8.0, 38.0)
			var dot_color := Color(0.2, 0.85, 0.4) if d < a.ammo else Color(0.3, 0.35, 0.4)
			field_rect.draw_circle(dot_pos, 2.5, dot_color)
