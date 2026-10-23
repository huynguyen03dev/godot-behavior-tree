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
const BASE_DEMO_PATH := "res://demo/demo.tscn"

func _ready() -> void:
	_build_ui()

func open_boss_demo() -> void:
	get_tree().change_scene_to_file(BOSS_SCENE_PATH)

func open_squad_demo() -> void:
	get_tree().change_scene_to_file(SQUAD_SCENE_PATH)

func open_guard_demo() -> void:
	get_tree().change_scene_to_file(GUARD_SCENE_PATH)

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
	margin.offset_left = 32
	margin.offset_top = 24
	margin.offset_right = -32
	margin.offset_bottom = -24
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

	var cards_hbox := HBoxContainer.new()
	cards_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards_hbox.add_theme_constant_override("separation", 16)
	main_vbox.add_child(cards_hbox)

	# Card 1: Boss AI
	var card_boss := _create_demo_card(
		"1. 3-Phase Boss AI",
		"Reactive Multi-Phase Boss",
		"• HP-threshold phase subtrees (100% ➔ 70% ➔ 30%)\n" +
		"• Cooldown-gated special attacks (Combo 2s, Ranged 3s, AoE 4s)\n" +
		"• LOWER_PRIORITY dodge preemption on incoming danger\n" +
		"• SELF conditional aborts on health changes\n" +
		"• Clean on_abort lifecycle without ghost states",
		"▶ Launch Boss AI Demo",
		open_boss_demo,
		Color(0.85, 0.25, 0.25)
	)
	cards_hbox.add_child(card_boss)

	# Card 2: Squad AI
	var card_squad := _create_demo_card(
		"2. Squad Tactical AI",
		"Decentralized Role Claims",
		"• 4 independent agents driven by individual BTRunners\n" +
		"• 1 shared BTBlackboard coordinating tactical roles\n" +
		"• Atomic role claims (Attacker, Flanker, Reloader, Reserve)\n" +
		"• Strict mutual exclusion verified each tick\n" +
		"• Dynamic role rebalance when an agent depletes ammo or dies",
		"▶ Launch Squad AI Demo",
		open_squad_demo,
		Color(0.2, 0.65, 0.95)
	)
	cards_hbox.add_child(card_squad)

	# Card 3: Guard Stealth AI
	var card_guard := _create_demo_card(
		"3. Guard Stealth AI",
		"Perception & Memory Decay",
		"• 90° FOV cone perception with dot product & distance checks\n" +
		"• Monotonic simulated time-based memory decay (3.0s)\n" +
		"• Alert escalation: Patrol ➔ Curious ➔ Search ➔ Chase\n" +
		"• TimeLimit decorator bounding search sweep\n" +
		"• Clean give-up fallback resuming patrol route",
		"▶ Launch Guard Stealth Demo",
		open_guard_demo,
		Color(0.25, 0.8, 0.45)
	)
	cards_hbox.add_child(card_guard)

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
	margin.offset_left = 12
	margin.offset_top = 12
	margin.offset_right = -12
	margin.offset_bottom = -12
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = title
	vbox.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = subtitle
	vbox.add_child(sub_lbl)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var desc_lbl := Label.new()
	desc_lbl.text = desc
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_lbl)

	var btn := Button.new()
	btn.text = btn_text
	btn.custom_minimum_size = Vector2(0, 40)
	btn.pressed.connect(callback)
	vbox.add_child(btn)

	return panel
