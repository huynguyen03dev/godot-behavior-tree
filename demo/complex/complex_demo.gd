extends Control
## Complex Demos Hub Scene for Godot Behavior Tree (godot_bt).
##
## Asset Library showcase hub linking three production-grade AI architectures:
## 1. Boss AI: 3-Phase tree, Cooldown attacks, LOWER_PRIORITY dodge preemption, SELF aborts.
## 2. Squad AI: 4 Runners, 1 shared blackboard, atomic role claims, mutual exclusion, dynamic rebalance.
## 3. Guard Stealth AI: 90° FOV cone perception, monotonic memory decay, TimeLimit search, patrol fallback.

const BOSS_SCENE_PATH := "res://demo/complex/boss_demo.tscn"
const SQUAD_SCENE_PATH := "res://demo/complex/squad_demo.tscn"
const GUARD_SCENE_PATH := "res://demo/complex/guard_stealth_demo.tscn"
const VILLAGER_SCENE_PATH := "res://demo/complex/villager_demo.tscn"
const RTS_SCENE_PATH := "res://demo/complex/rts_demo.tscn"
const BASE_DEMO_PATH := "res://demo/demo.tscn"

func _ready() -> void:
	_build_ui()

func open_boss_demo() -> void:
	get_tree().change_scene_to_file(BOSS_SCENE_PATH)

func open_squad_demo() -> void:
	get_tree().change_scene_to_file(SQUAD_SCENE_PATH)

func open_guard_demo() -> void:
	get_tree().change_scene_to_file(GUARD_SCENE_PATH)

func open_villager_demo() -> void:
	get_tree().change_scene_to_file(VILLAGER_SCENE_PATH)

func open_rts_demo() -> void:
	get_tree().change_scene_to_file(RTS_SCENE_PATH)

func open_base_demo() -> void:
	get_tree().change_scene_to_file(BASE_DEMO_PATH)

func _build_ui() -> void:
	# Root dark background
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.14)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = 20
	margin.offset_top = 14
	margin.offset_right = -20
	margin.offset_bottom = -14
	add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 16)
	margin.add_child(main_vbox)

	# Header
	var title_lbl := Label.new()
	title_lbl.text = "Godot Behavior Tree — Complex AI Mechanics Showcase"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(title_lbl)

	var subtitle_lbl := Label.new()
	subtitle_lbl.text = "Deterministic, production-ready AI architectures built with godot_bt (Pure GDScript, zero external assets)"
	subtitle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_lbl.custom_minimum_size = Vector2(0, 0)
	main_vbox.add_child(subtitle_lbl)

	var cards_scroll := ScrollContainer.new()
	cards_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(cards_scroll)

	var cards_grid := GridContainer.new()
	cards_grid.columns = 3
	cards_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_grid.add_theme_constant_override("h_separation", 16)
	cards_grid.add_theme_constant_override("v_separation", 16)
	cards_scroll.add_child(cards_grid)

	# Card 1: Boss AI
	var card_boss := _create_demo_card(
		"1. 3-Phase Boss AI",
		"Reactive Multi-Phase Boss",
		"• HP-threshold phase subtrees (100% ➔ 70% ➔ 30%)\n" +
		"• LOWER_PRIORITY dodge preemption + SELF phase aborts\n" +
		"• Cooldown-gated Combo/Ranged/AoE with lifecycle counters",
		"▶ Launch Boss AI Demo",
		open_boss_demo,
		Color(0.85, 0.25, 0.25)
	)
	cards_grid.add_child(card_boss)

	# Card 2: Squad AI
	var card_squad := _create_demo_card(
		"2. Squad Tactical AI",
		"Decentralized Role Claims",
		"• 4 agents, 4 BTRunners, 1 shared BTBlackboard\n" +
		"• Atomic role claims: Attacker/Flanker/Reloader/Reserve\n" +
		"• Dynamic rebalance on ammo-out or death, 0 mutex violations",
		"▶ Launch Squad AI Demo",
		open_squad_demo,
		Color(0.2, 0.65, 0.95)
	)
	cards_grid.add_child(card_squad)

	# Card 3: Guard Stealth AI
	var card_guard := _create_demo_card(
		"3. Guard Stealth AI",
		"Perception & Memory Decay",
		"• 90° FOV cone perception with distance + dot checks\n" +
		"• Monotonic memory decay (3.0s) ➔ Patrol fallback\n" +
		"• TimeLimit-bounded search sweeps, WASD player",
		"▶ Launch Guard Stealth Demo",
		open_guard_demo,
		Color(0.25, 0.8, 0.45)
	)
	cards_grid.add_child(card_guard)

	# Card 4: Colony Life-Sim
	var card_villager := _create_demo_card(
		"4. Colony Life-Sim",
		"Needs, Jobs & Subtree Reuse",
		"• 6 villagers with needs decay and day/night schedules\n" +
		"• 8 reusable job/routine subtrees from JSON (416 nodes)\n" +
		"• Shared vs private blackboard scoping, live coverage HUD",
		"▶ Launch Colony Demo",
		open_villager_demo,
		Color(0.9, 0.7, 0.25)
	)
	cards_grid.add_child(card_villager)

	# Card 5: RTS Commander
	var card_rts := _create_demo_card(
		"5. RTS Commander",
		"Large-Tree Strategy + Squad Micro",
		"• 850-node strategic commander tree (scales to 2000)\n" +
		"• 4 squad micro subtrees, target mutex, 5 stances\n" +
		"• Live perf overlay: µs/tick, coverage, execution budget",
		"▶ Launch RTS Demo",
		open_rts_demo,
		Color(0.65, 0.4, 0.85)
	)
	cards_grid.add_child(card_rts)

	# Bottom Footer Bar
	var footer_hbox := HBoxContainer.new()
	footer_hbox.add_theme_constant_override("separation", 16)
	main_vbox.add_child(footer_hbox)

	var btn_base := Button.new()
	btn_base.text = "⮌ Open Standard Viewer Demo (demo/demo.tscn)"
	btn_base.pressed.connect(open_base_demo)
	footer_hbox.add_child(btn_base)

	var info_lbl := Label.new()
	info_lbl.text = "All demos run deterministically in headless test suites and interactively in the Godot editor."
	info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer_hbox.add_child(info_lbl)

func _create_demo_card(title: String, subtitle: String, desc: String, btn_text: String, callback: Callable, accent_color: Color) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.offset_left = 8
	margin.offset_top = 8
	margin.offset_right = -8
	margin.offset_bottom = -8
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = title
	vbox.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = subtitle
	sub_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(sub_lbl)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var desc_lbl := Label.new()
	desc_lbl.text = desc
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(desc_lbl)

	var btn := Button.new()
	btn.text = btn_text
	btn.custom_minimum_size = Vector2(0, 32)
	btn.pressed.connect(callback)
	vbox.add_child(btn)

	return panel
