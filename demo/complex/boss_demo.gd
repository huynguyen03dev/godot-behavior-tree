extends Control
## Complex Demo: 3-Phase Boss AI with Reactive Preemption.
##
## Demonstrates a multi-phase boss encounter driven by a single behavior tree:
## - 3-Phase HP-threshold subtrees (Phase 1 >70%, Phase 2 30-70%, Phase 3 <30%).
## - Cooldown-gated attack patterns (Combo: 2s CD, Ranged: 3s CD, AoE: 4s CD) with basic fallback.
## - LOWER_PRIORITY conditional abort on root selector for reactive Dodge preemption.
## - SELF conditional abort on phase sequences so health changes immediately abort current actions.

const HUB_SCENE_PATH := "res://demo/complex/complex_demo.tscn"
const SQUAD_SCENE_PATH := "res://demo/complex/squad_demo.tscn"
const GUARD_SCENE_PATH := "res://demo/complex/guard_stealth_demo.tscn"

# Lifecycle tracking (mirrors test_boss_ai.gd milestones)
var combo_starts := 0
var combo_updates := 0
var combo_aborts := 0
var combo_ends := 0

var ranged_starts := 0
var ranged_updates := 0
var ranged_aborts := 0
var ranged_ends := 0

var aoe_starts := 0
var aoe_updates := 0
var aoe_aborts := 0
var aoe_ends := 0

var dodge_starts := 0
var dodge_updates := 0
var dodge_ends := 0

# Runtime state
var runner: BTRunner = null
var tree: BTTree = null
var auto_tick: bool = false
var tick_timer: float = 0.0
var tick_interval: float = 0.25

var current_action_name: String = "Idle"
var telegraph_type: String = "none" # "none", "combo", "ranged", "aoe", "dodge"
var telegraph_step: int = 0
var visual_hp: float = 100.0

# UI references
var arena_rect: Control = null
var hp_bar: ProgressBar = null
var hp_label: Label = null
var phase_label: Label = null
var action_label: Label = null
var stats_label: Label = null
var danger_indicator: PanelContainer = null
var auto_tick_button: Button = null

# ---------------------------------------------------------------- BT Task Definitions

class BossConditionHP extends BTTask:
	var min_hp: float = 0.0
	var max_hp: float = 100.0

	func _init(p_min: float = 0.0, p_max: float = 100.0) -> void:
		type_name = "BossConditionHP"
		category = "Condition"
		min_hp = p_min
		max_hp = p_max

	func evaluate_condition(_runner: BTRunner) -> int:
		var hp: float = float(get_blackboard_var("hp", 100.0))
		return BTStatus.SUCCESS if (hp >= min_hp and hp <= max_hp) else BTStatus.FAILURE

	func on_update() -> int:
		return evaluate_condition(owner as BTRunner)


class BossConditionDanger extends BTTask:
	func _init() -> void:
		type_name = "BossConditionDanger"
		category = "Condition"

	func evaluate_condition(_runner: BTRunner) -> int:
		var d: bool = bool(get_blackboard_var("danger", false))
		return BTStatus.SUCCESS if d else BTStatus.FAILURE

	func on_update() -> int:
		return evaluate_condition(owner as BTRunner)


class BossActionDodge extends BTTask:
	var demo: Node = null
	var ticks_left := 2

	func _init(p_demo: Node = null) -> void:
		type_name = "BossActionDodge"
		category = "Action"
		demo = p_demo

	func on_start() -> void:
		if demo != null:
			demo.dodge_starts += 1
			demo.current_action_name = "Dodge (1/2)"
			demo.telegraph_type = "dodge"
			demo.telegraph_step = 1
		ticks_left = 2

	func on_update() -> int:
		if demo != null:
			demo.dodge_updates += 1
		ticks_left -= 1
		if ticks_left <= 0:
			set_blackboard_var("danger", false)
			if demo != null:
				demo.current_action_name = "None"
				demo.telegraph_type = "none"
			return BTStatus.SUCCESS
		if demo != null:
			demo.current_action_name = "Dodge (2/2)"
			demo.telegraph_step = 2
		return BTStatus.RUNNING

	func on_end() -> void:
		if demo != null:
			demo.dodge_ends += 1
		super.on_end()


class BossActionCombo extends BTTask:
	var demo: Node = null
	var current_step := 0

	func _init(p_demo: Node = null) -> void:
		type_name = "BossActionCombo"
		category = "Action"
		demo = p_demo

	func on_start() -> void:
		if demo != null:
			demo.combo_starts += 1
			demo.current_action_name = "Combo Strike (1/3)"
			demo.telegraph_type = "combo"
			demo.telegraph_step = 1
		current_step = 0

	func on_update() -> int:
		if demo != null:
			demo.combo_updates += 1
		current_step += 1
		if demo != null:
			demo.current_action_name = "Combo Strike (%d/3)" % current_step
			demo.telegraph_step = current_step
		if current_step >= 3:
			if demo != null:
				demo.current_action_name = "None"
				demo.telegraph_type = "none"
			return BTStatus.SUCCESS
		return BTStatus.RUNNING

	func on_abort() -> void:
		if demo != null:
			demo.combo_aborts += 1
			demo.current_action_name = "Aborted"
			demo.telegraph_type = "none"
		super.on_abort()

	func on_end() -> void:
		if demo != null:
			demo.combo_ends += 1
		super.on_end()


class BossActionRanged extends BTTask:
	var demo: Node = null
	var current_step := 0

	func _init(p_demo: Node = null) -> void:
		type_name = "BossActionRanged"
		category = "Action"
		demo = p_demo

	func on_start() -> void:
		if demo != null:
			demo.ranged_starts += 1
			demo.current_action_name = "Ranged Barrage (1/3)"
			demo.telegraph_type = "ranged"
			demo.telegraph_step = 1
		current_step = 0

	func on_update() -> int:
		if demo != null:
			demo.ranged_updates += 1
		current_step += 1
		if demo != null:
			demo.current_action_name = "Ranged Barrage (%d/3)" % current_step
			demo.telegraph_step = current_step
		if current_step >= 3:
			if demo != null:
				demo.current_action_name = "None"
				demo.telegraph_type = "none"
			return BTStatus.SUCCESS
		return BTStatus.RUNNING

	func on_abort() -> void:
		if demo != null:
			demo.ranged_aborts += 1
			demo.current_action_name = "Aborted"
			demo.telegraph_type = "none"
		super.on_abort()

	func on_end() -> void:
		if demo != null:
			demo.ranged_ends += 1
		super.on_end()


class BossActionAoE extends BTTask:
	var demo: Node = null
	var current_step := 0

	func _init(p_demo: Node = null) -> void:
		type_name = "BossActionAoE"
		category = "Action"
		demo = p_demo

	func on_start() -> void:
		if demo != null:
			demo.aoe_starts += 1
			demo.current_action_name = "AoE Overdrive (1/4)"
			demo.telegraph_type = "aoe"
			demo.telegraph_step = 1
		current_step = 0

	func on_update() -> int:
		if demo != null:
			demo.aoe_updates += 1
		current_step += 1
		if demo != null:
			demo.current_action_name = "AoE Overdrive (%d/4)" % current_step
			demo.telegraph_step = current_step
		if current_step >= 4:
			if demo != null:
				demo.current_action_name = "None"
				demo.telegraph_type = "none"
			return BTStatus.SUCCESS
		return BTStatus.RUNNING

	func on_abort() -> void:
		if demo != null:
			demo.aoe_aborts += 1
			demo.current_action_name = "Aborted"
			demo.telegraph_type = "none"
		super.on_abort()

	func on_end() -> void:
		if demo != null:
			demo.aoe_ends += 1
		super.on_end()


class BossActionBasicFallback extends BTTask:
	var demo: Node = null

	func _init(p_demo: Node = null) -> void:
		type_name = "BossActionBasicFallback"
		category = "Action"
		demo = p_demo

	func on_start() -> void:
		if demo != null:
			demo.current_action_name = "Basic Attack"
			demo.telegraph_type = "none"

	func on_update() -> int:
		return BTStatus.SUCCESS

# ---------------------------------------------------------------- Tree Construction

func _build_task_registry() -> BTTaskRegistry:
	var reg := BTTaskRegistry.new()
	reg.register_task("BossConditionHP", func(): return BossConditionHP.new(), "Condition")
	reg.register_task("BossConditionDanger", func(): return BossConditionDanger.new(), "Condition")
	reg.register_task("BossActionDodge", func(): return BossActionDodge.new(self), "Action")
	reg.register_task("BossActionCombo", func(): return BossActionCombo.new(self), "Action")
	reg.register_task("BossActionRanged", func(): return BossActionRanged.new(self), "Action")
	reg.register_task("BossActionAoE", func(): return BossActionAoE.new(self), "Action")
	reg.register_task("BossActionBasicFallback", func(): return BossActionBasicFallback.new(self), "Action")
	return reg

func _build_boss_tree() -> BTTree:
	var bt := BTTree.new()
	bt.registry = _build_task_registry()

	var rep := BTDecorator.BTRepeater.new()
	rep.repeat_forever = true
	bt.set_root(rep)

	var root_sel := BTComposite.BTSelector.new()
	root_sel.set_abort_type(BTComposite.AbortType.LOWER_PRIORITY)
	bt.connect_parent_child(rep, root_sel)

	# 1. Top-priority Dodge Branch (Sequence: DangerCondition -> ActionDodge)
	var dodge_seq := BTComposite.BTSequence.new()
	var cond_danger := BossConditionDanger.new()
	var act_dodge := BossActionDodge.new(self)
	bt.connect_parent_child(root_sel, dodge_seq)
	bt.connect_parent_child(dodge_seq, cond_danger)
	bt.connect_parent_child(dodge_seq, act_dodge)

	# 2. Phase 1 Branch (HP > 70): Sequence(SELF) -> [ConditionHP, Phase1Selector]
	var p1_seq := BTComposite.BTSequence.new()
	p1_seq.set_abort_type(BTComposite.AbortType.SELF)
	var cond_p1 := BossConditionHP.new(71.0, 100.0)
	var p1_sel := BTComposite.BTSelector.new()
	var cd_combo := BTDecorator.BTCooldown.new()
	cd_combo.cooldown_time = 2.0
	var act_combo := BossActionCombo.new(self)
	var act_p1_fallback := BossActionBasicFallback.new(self)
	bt.connect_parent_child(root_sel, p1_seq)
	bt.connect_parent_child(p1_seq, cond_p1)
	bt.connect_parent_child(p1_seq, p1_sel)
	bt.connect_parent_child(p1_sel, cd_combo)
	bt.connect_parent_child(cd_combo, act_combo)
	bt.connect_parent_child(p1_sel, act_p1_fallback)

	# 3. Phase 2 Branch (30 <= HP <= 70): Sequence(SELF) -> [ConditionHP, Phase2Selector]
	var p2_seq := BTComposite.BTSequence.new()
	p2_seq.set_abort_type(BTComposite.AbortType.SELF)
	var cond_p2 := BossConditionHP.new(30.0, 70.0)
	var p2_sel := BTComposite.BTSelector.new()
	var cd_ranged := BTDecorator.BTCooldown.new()
	cd_ranged.cooldown_time = 3.0
	var act_ranged := BossActionRanged.new(self)
	var act_p2_fallback := BossActionBasicFallback.new(self)
	bt.connect_parent_child(root_sel, p2_seq)
	bt.connect_parent_child(p2_seq, cond_p2)
	bt.connect_parent_child(p2_seq, p2_sel)
	bt.connect_parent_child(p2_sel, cd_ranged)
	bt.connect_parent_child(cd_ranged, act_ranged)
	bt.connect_parent_child(p2_sel, act_p2_fallback)

	# 4. Phase 3 Branch (HP < 30): Sequence(SELF) -> [ConditionHP, Phase3Selector]
	var p3_seq := BTComposite.BTSequence.new()
	p3_seq.set_abort_type(BTComposite.AbortType.SELF)
	var cond_p3 := BossConditionHP.new(0.0, 29.9)
	var p3_sel := BTComposite.BTSelector.new()
	var cd_aoe := BTDecorator.BTCooldown.new()
	cd_aoe.cooldown_time = 4.0
	var act_aoe := BossActionAoE.new(self)
	var act_p3_fallback := BossActionBasicFallback.new(self)
	bt.connect_parent_child(root_sel, p3_seq)
	bt.connect_parent_child(p3_seq, cond_p3)
	bt.connect_parent_child(p3_seq, p3_sel)
	bt.connect_parent_child(p3_sel, cd_aoe)
	bt.connect_parent_child(cd_aoe, act_aoe)
	bt.connect_parent_child(p3_sel, act_p3_fallback)

	return bt

# ---------------------------------------------------------------- Lifecycle

func _ready() -> void:
	reset_lifecycle()
	tree = _build_boss_tree()
	tree.blackboard.set_var("hp", 100.0)
	tree.blackboard.set_var("danger", false)
	visual_hp = 100.0

	runner = BTRunner.new(tree)
	runner.actor = self
	add_child(runner)
	runner.set_process(false)
	runner.start()

	# In headless mode (tests/CLI), default auto_tick to false. In interactive, default true.
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
		tick_manual(tick_interval)

func _exit_tree() -> void:
	if runner != null and is_instance_valid(runner):
		runner.stop()
		runner.free()
		runner = null

# ---------------------------------------------------------------- Public Control API

func reset_lifecycle() -> void:
	combo_starts = 0
	combo_updates = 0
	combo_aborts = 0
	combo_ends = 0
	ranged_starts = 0
	ranged_updates = 0
	ranged_aborts = 0
	ranged_ends = 0
	aoe_starts = 0
	aoe_updates = 0
	aoe_aborts = 0
	aoe_ends = 0
	dodge_starts = 0
	dodge_updates = 0
	dodge_ends = 0

func set_hp(new_hp: float) -> void:
	if tree != null and tree.blackboard != null:
		tree.blackboard.set_var("hp", new_hp)
	visual_hp = new_hp
	_update_ui_state()
	if arena_rect != null:
		arena_rect.queue_redraw()

func get_hp() -> float:
	if tree != null and tree.blackboard != null:
		return float(tree.blackboard.get_var("hp", 100.0))
	return visual_hp

func trigger_danger() -> void:
	if tree != null and tree.blackboard != null:
		tree.blackboard.set_var("danger", true)
	_update_ui_state()
	if arena_rect != null:
		arena_rect.queue_redraw()

func tick_manual(delta: float = 0.1) -> int:
	if runner == null or not is_instance_valid(runner) or not runner.is_running:
		return BTStatus.INACTIVE
	var status := runner.tick(delta)
	_update_ui_state()
	if arena_rect != null:
		arena_rect.queue_redraw()
	return status

func reset_demo() -> void:
	reset_lifecycle()
	if runner != null and is_instance_valid(runner):
		runner.stop()
		runner.free()
		runner = null
	tree = _build_boss_tree()
	tree.blackboard.set_var("hp", 100.0)
	tree.blackboard.set_var("danger", false)
	visual_hp = 100.0
	current_action_name = "Idle"
	telegraph_type = "none"
	telegraph_step = 0
	runner = BTRunner.new(tree)
	runner.actor = self
	add_child(runner)
	runner.set_process(false)
	runner.start()
	_update_ui_state()
	if arena_rect != null:
		arena_rect.queue_redraw()

# ---------------------------------------------------------------- UI Setup & Rendering

func _build_ui() -> void:
	# Root dark background
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
	title_lbl.text = "Boss AI Showcase: 3-Phase Tree & LOWER_PRIORITY Dodge Preemption"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_bar.add_child(title_lbl)

	var btn_squad := Button.new()
	btn_squad.text = "Squad AI ➔"
	btn_squad.pressed.connect(func(): get_tree().change_scene_to_file(SQUAD_SCENE_PATH))
	nav_bar.add_child(btn_squad)

	var btn_guard := Button.new()
	btn_guard.text = "Guard Stealth ➔"
	btn_guard.pressed.connect(func(): get_tree().change_scene_to_file(GUARD_SCENE_PATH))
	nav_bar.add_child(btn_guard)

	# Content Area: Left Arena Visualizer, Right Control Panel
	var content_hbox := HBoxContainer.new()
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", 12)
	main_vbox.add_child(content_hbox)

	# Arena Visualizer (Custom Draw)
	arena_rect = Control.new()
	arena_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arena_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arena_rect.draw.connect(_on_arena_draw)
	content_hbox.add_child(arena_rect)

	# Right Panel: Controls & Telemetry
	var right_panel := PanelContainer.new()
	right_panel.custom_minimum_size = Vector2(380, 0)
	content_hbox.add_child(right_panel)

	var panel_vbox := VBoxContainer.new()
	panel_vbox.add_theme_constant_override("separation", 8)
	right_panel.add_child(panel_vbox)

	# Phase & Action Status
	var status_header := Label.new()
	status_header.text = "=== BOSS RUNTIME STATUS ==="
	panel_vbox.add_child(status_header)

	hp_bar = ProgressBar.new()
	hp_bar.min_value = 0.0
	hp_bar.max_value = 100.0
	hp_bar.value = 100.0
	hp_bar.custom_minimum_size = Vector2(0, 24)
	panel_vbox.add_child(hp_bar)

	hp_label = Label.new()
	hp_label.text = "HP: 100.0 / 100.0"
	panel_vbox.add_child(hp_label)

	phase_label = Label.new()
	phase_label.text = "Phase: 1 (Melee Frenzy, HP > 70%)"
	panel_vbox.add_child(phase_label)

	action_label = Label.new()
	action_label.text = "Active Attack: Idle"
	panel_vbox.add_child(action_label)

	danger_indicator = PanelContainer.new()
	var danger_lbl := Label.new()
	danger_lbl.text = "⚠️ INCOMING DANGER! (LOWER_PRIORITY Dodge Active)"
	danger_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	danger_indicator.add_child(danger_lbl)
	danger_indicator.visible = false
	panel_vbox.add_child(danger_indicator)

	# Interactive Triggers
	var ctrl_header := Label.new()
	ctrl_header.text = "=== INTERACTIVE TRIGGERS ==="
	panel_vbox.add_child(ctrl_header)

	var btn_danger := Button.new()
	btn_danger.text = "⚠️ TRIGGER DANGER (Instant Dodge Preempt)"
	btn_danger.pressed.connect(trigger_danger)
	panel_vbox.add_child(btn_danger)

	var dmg_hbox := HBoxContainer.new()
	panel_vbox.add_child(dmg_hbox)

	var btn_dmg30 := Button.new()
	btn_dmg30.text = "-30 HP (P2)"
	btn_dmg30.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_dmg30.pressed.connect(func(): set_hp(max(0.0, get_hp() - 30.0)))
	dmg_hbox.add_child(btn_dmg30)

	var btn_dmg50 := Button.new()
	btn_dmg50.text = "-50 HP (P3)"
	btn_dmg50.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_dmg50.pressed.connect(func(): set_hp(max(0.0, get_hp() - 50.0)))
	dmg_hbox.add_child(btn_dmg50)

	var btn_heal40 := Button.new()
	btn_heal40.text = "+40 HP (Heal)"
	btn_heal40.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_heal40.pressed.connect(func(): set_hp(min(100.0, get_hp() + 40.0)))
	dmg_hbox.add_child(btn_heal40)

	var sim_header := Label.new()
	sim_header.text = "=== SIMULATION & STEPPING ==="
	panel_vbox.add_child(sim_header)

	var step_hbox := HBoxContainer.new()
	panel_vbox.add_child(step_hbox)

	var btn_step := Button.new()
	btn_step.text = "▶ Step Tick (0.1s)"
	btn_step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_step.pressed.connect(func(): tick_manual(0.1))
	step_hbox.add_child(btn_step)

	auto_tick_button = Button.new()
	auto_tick_button.text = "Auto-Tick: " + ("ON" if auto_tick else "OFF")
	auto_tick_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto_tick_button.pressed.connect(func():
		auto_tick = not auto_tick
		auto_tick_button.text = "Auto-Tick: " + ("ON" if auto_tick else "OFF")
	)
	step_hbox.add_child(auto_tick_button)

	var btn_reset := Button.new()
	btn_reset.text = "↺ Reset Boss (100 HP)"
	btn_reset.pressed.connect(reset_demo)
	panel_vbox.add_child(btn_reset)

	# Stats & Lifecycle
	var stats_header := Label.new()
	stats_header.text = "=== LIFECYCLE COUNTERS ==="
	panel_vbox.add_child(stats_header)

	stats_label = Label.new()
	panel_vbox.add_child(stats_label)

func _update_ui_state() -> void:
	var hp := get_hp()
	var danger: bool = bool(tree.blackboard.get_var("danger", false)) if (tree != null and tree.blackboard != null) else false

	if hp_bar != null:
		hp_bar.value = hp
	if hp_label != null:
		hp_label.text = "HP: %.1f / 100.0" % hp

	if phase_label != null:
		if hp > 70.0:
			phase_label.text = "Phase: 1 (Melee Frenzy, HP > 70%)"
		elif hp >= 30.0:
			phase_label.text = "Phase: 2 (Ranged Barrage, 30% - 70%)"
		else:
			phase_label.text = "Phase: 3 (AoE Overdrive, HP < 30%)"

	if action_label != null:
		action_label.text = "Active Action: %s" % current_action_name

	if danger_indicator != null:
		danger_indicator.visible = danger

	if stats_label != null:
		stats_label.text = (
			"Combo: starts=%d, updates=%d, aborts=%d, ends=%d\n" +
			"Ranged: starts=%d, updates=%d, aborts=%d, ends=%d\n" +
			"AoE: starts=%d, updates=%d, aborts=%d, ends=%d\n" +
			"Dodge: starts=%d, updates=%d, ends=%d"
		) % [
			combo_starts, combo_updates, combo_aborts, combo_ends,
			ranged_starts, ranged_updates, ranged_aborts, ranged_ends,
			aoe_starts, aoe_updates, aoe_aborts, aoe_ends,
			dodge_starts, dodge_updates, dodge_ends
		]

func _on_arena_draw() -> void:
	if arena_rect == null:
		return
	var size := arena_rect.size
	if size.x < 10 or size.y < 10:
		return

	# Arena background frame
	var arena_center := size * 0.5
	var radius := minf(size.x, size.y) * 0.42

	# Floor grid circles & lines
	arena_rect.draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.13, 0.18), true)
	arena_rect.draw_circle(arena_center, radius, Color(0.14, 0.18, 0.25))
	arena_rect.draw_arc(arena_center, radius, 0.0, TAU, 64, Color(0.25, 0.35, 0.48), 2.0)
	arena_rect.draw_arc(arena_center, radius * 0.6, 0.0, TAU, 48, Color(0.2, 0.28, 0.38), 1.0)

	var hp := get_hp()
	var danger: bool = bool(tree.blackboard.get_var("danger", false)) if (tree != null and tree.blackboard != null) else false

	# Boss Color based on phase
	var boss_color := Color(0.9, 0.3, 0.25) # Phase 1 Crimson
	if hp <= 70.0 and hp >= 30.0:
		boss_color = Color(0.65, 0.35, 0.85) # Phase 2 Violet
	elif hp < 30.0:
		boss_color = Color(0.95, 0.5, 0.15) # Phase 3 Molten Orange

	# If dodging, render afterimage and cyan shield
	if telegraph_type == "dodge":
		arena_rect.draw_circle(arena_center + Vector2(-35, 0), 45.0, Color(0.0, 0.8, 0.9, 0.4))
		arena_rect.draw_circle(arena_center + Vector2(35, 0), 45.0, Color(0.0, 0.8, 0.9, 0.4))
		boss_color = Color(0.1, 0.9, 1.0)

	# Telegraph Visuals
	if telegraph_type == "combo":
		# 3 Slash Lines radiating forward
		for s in range(telegraph_step):
			var angle := -0.6 + s * 0.6
			var slash_start := arena_center + Vector2.from_angle(angle) * 55.0
			var slash_end := arena_center + Vector2.from_angle(angle) * (110.0 + s * 30.0)
			arena_rect.draw_line(slash_start, slash_end, Color(1.0, 0.85, 0.2), 4.0)
	elif telegraph_type == "ranged":
		# Projectile laser streaks
		for a in [0.0, 0.5 * PI, PI, 1.5 * PI]:
			var r_end := arena_center + Vector2.from_angle(a + telegraph_step * 0.2) * (radius * 0.85)
			arena_rect.draw_line(arena_center, r_end, Color(0.7, 0.4, 1.0), 3.0)
	elif telegraph_type == "aoe":
		# Expanding AoE pulse ring
		var aoe_radius := radius * (float(telegraph_step) / 4.0)
		arena_rect.draw_circle(arena_center, aoe_radius, Color(1.0, 0.25, 0.1, 0.25))
		arena_rect.draw_arc(arena_center, aoe_radius, 0.0, TAU, 48, Color(1.0, 0.3, 0.15), 3.0)

	# Draw Boss Body
	arena_rect.draw_circle(arena_center, 45.0, boss_color)
	arena_rect.draw_arc(arena_center, 45.0, 0.0, TAU, 32, Color.WHITE, 2.0)

	# Danger marker overlay
	if danger:
		arena_rect.draw_arc(arena_center, 65.0, 0.0, TAU, 32, Color(1.0, 0.1, 0.1), 3.0)
