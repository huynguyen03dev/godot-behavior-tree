extends Control
## Complex Demo: Guard Stealth AI with FOV Perception, Memory Decay & TimeLimit.
##
## Demonstrates realistic stealth awareness mechanics:
## - 90° FOV perception cone with distance (100 units) and facing dot product checks.
## - Monotonic simulated time-based blackboard memory decay (3.0s duration).
## - Alert escalation: Patrol -> Curious (moving to last-seen) -> Search (sweeping) -> Chase (visual contact).
## - TimeLimit decorator bounding search behavior, cleanly returning to Patrol on give-up.
## - Reactive preemption: LOWER_PRIORITY on root selector and SELF aborts on sequences.

const HUB_SCENE_PATH := "res://demo/complex/complex_demo.tscn"
const BOSS_SCENE_PATH := "res://demo/complex/boss_demo.tscn"
const SQUAD_SCENE_PATH := "res://demo/complex/squad_demo.tscn"

class GuardActor:
	var pos: Vector2 = Vector2.ZERO
	var facing: Vector2 = Vector2(1, 0)
	var speed: float = 20.0
	var waypoints: Array[Vector2] = [Vector2(0, 0), Vector2(40, 0)]
	var current_wp: int = 0
	var alert_level: String = "Patrol"

class PlayerActor:
	var pos: Vector2 = Vector2(200, 200)
	var is_hidden: bool = false

# Actors & BT
var guard: GuardActor = null
var player: PlayerActor = null
var runner: BTRunner = null
var tree: BTTree = null

var auto_tick: bool = false
var tick_timer: float = 0.0
var tick_interval: float = 0.1
var player_move_speed: float = 60.0

# UI references
var map_rect: Control = null
var alert_banner: PanelContainer = null
var alert_label: Label = null
var status_label: Label = null
var auto_tick_button: Button = null

# ---------------------------------------------------------------- BT Tasks

class ConditionCanSeePlayer extends BTTask:
	var guard: GuardActor
	var player: PlayerActor
	var max_dist: float = 100.0
	var fov_cos: float = cos(deg_to_rad(45.0)) # 90 degree cone

	func _init(p_guard: GuardActor, p_player: PlayerActor) -> void:
		guard = p_guard
		player = p_player
		type_name = "ConditionCanSeePlayer"
		category = "Condition"

	func evaluate_condition(p_runner: BTRunner) -> int:
		if player.is_hidden:
			return BTStatus.FAILURE
		var dist := guard.pos.distance_to(player.pos)
		if dist > max_dist:
			return BTStatus.FAILURE
		var dir := (player.pos - guard.pos).normalized()
		var dot := guard.facing.dot(dir)
		if dot < fov_cos:
			return BTStatus.FAILURE

		# Spotted! Form memory on blackboard
		set_blackboard_var("has_memory", true)
		set_blackboard_var("last_seen_pos", player.pos)
		var current_time := p_runner.time if p_runner != null else 0.0
		set_blackboard_var("time_last_seen", current_time)
		return BTStatus.SUCCESS

	func on_update() -> int:
		return evaluate_condition(owner as BTRunner)


class ActionChase extends BTTask:
	var guard: GuardActor
	var player: PlayerActor
	var updates := 0

	func _init(p_guard: GuardActor, p_player: PlayerActor) -> void:
		guard = p_guard
		player = p_player
		type_name = "ActionChase"
		category = "Action"

	func on_start() -> void:
		guard.alert_level = "Chase"

	func on_update() -> int:
		updates += 1
		guard.alert_level = "Chase"
		var dir := (player.pos - guard.pos).normalized()
		if dir.length() > 0.01:
			guard.facing = dir
			var r := owner as BTRunner
			var dt: float = r.delta if r != null else 0.1
			guard.pos += dir * guard.speed * dt
		set_blackboard_var("last_seen_pos", player.pos)
		if owner != null and owner is BTRunner:
			set_blackboard_var("time_last_seen", (owner as BTRunner).time)
		return BTStatus.RUNNING


class ConditionHasMemory extends BTTask:
	var memory_duration: float = 3.0

	func _init(p_dur: float = 3.0) -> void:
		memory_duration = p_dur
		type_name = "ConditionHasMemory"
		category = "Condition"

	func evaluate_condition(p_runner: BTRunner) -> int:
		var has_mem: bool = bool(get_blackboard_var("has_memory", false))
		if not has_mem:
			return BTStatus.FAILURE
		var t_seen: float = float(get_blackboard_var("time_last_seen", 0.0))
		var cur_time: float = p_runner.time if p_runner != null else 0.0
		if cur_time - t_seen > memory_duration:
			set_blackboard_var("has_memory", false)
			return BTStatus.FAILURE
		return BTStatus.SUCCESS

	func on_update() -> int:
		return evaluate_condition(owner as BTRunner)


class ActionInvestigateAndSearch extends BTTask:
	var guard: GuardActor
	var sweep_step := 0
	var updates := 0

	func _init(p_guard: GuardActor) -> void:
		guard = p_guard
		type_name = "ActionInvestigateAndSearch"
		category = "Action"

	func on_start() -> void:
		sweep_step = 0

	func on_update() -> int:
		updates += 1
		var last_seen: Vector2 = get_blackboard_var("last_seen_pos", guard.pos)
		var dist := guard.pos.distance_to(last_seen)

		if dist > 5.0:
			# Curious: Moving to investigate last-seen point
			guard.alert_level = "Curious"
			var dir := (last_seen - guard.pos).normalized()
			guard.facing = dir
			var r := owner as BTRunner
			var dt: float = r.delta if r != null else 0.1
			guard.pos += dir * guard.speed * dt
			return BTStatus.RUNNING

		# Reached point: Search sweep
		guard.alert_level = "Search"
		sweep_step += 1
		if sweep_step == 1:
			guard.facing = Vector2(-1, 0)
			return BTStatus.RUNNING
		elif sweep_step == 2:
			guard.facing = Vector2(1, 0)
			return BTStatus.RUNNING
		else:
			set_blackboard_var("has_memory", false)
			return BTStatus.SUCCESS


class ActionPatrol extends BTTask:
	var guard: GuardActor
	var updates := 0

	func _init(p_guard: GuardActor) -> void:
		guard = p_guard
		type_name = "ActionPatrol"
		category = "Action"

	func on_start() -> void:
		guard.alert_level = "Patrol"

	func on_update() -> int:
		updates += 1
		guard.alert_level = "Patrol"
		if guard.waypoints.is_empty():
			return BTStatus.RUNNING
		var target_wp := guard.waypoints[guard.current_wp]
		var dist := guard.pos.distance_to(target_wp)
		if dist < 2.0:
			guard.current_wp = (guard.current_wp + 1) % guard.waypoints.size()
			target_wp = guard.waypoints[guard.current_wp]
		var dir := (target_wp - guard.pos).normalized()
		if dir.length() > 0.01:
			guard.facing = dir
			var r := owner as BTRunner
			var dt: float = r.delta if r != null else 0.1
			guard.pos += dir * guard.speed * dt
		return BTStatus.RUNNING

# ---------------------------------------------------------------- Tree Construction

func _build_guard_tree() -> BTTree:
	var bt := BTTree.new()

	var rep := BTDecorator.BTRepeater.new()
	rep.repeat_forever = true
	bt.set_root(rep)

	var root_sel := BTComposite.BTSelector.new()
	root_sel.set_abort_type(BTComposite.AbortType.LOWER_PRIORITY)
	bt.connect_parent_child(rep, root_sel)

	# 1. Chase Branch (Priority 1)
	var chase_seq := BTComposite.BTSequence.new()
	chase_seq.set_abort_type(BTComposite.AbortType.SELF)
	var cond_see := ConditionCanSeePlayer.new(guard, player)
	var act_chase := ActionChase.new(guard, player)
	bt.connect_parent_child(root_sel, chase_seq)
	bt.connect_parent_child(chase_seq, cond_see)
	bt.connect_parent_child(chase_seq, act_chase)

	# 2. Search Branch (Priority 2)
	var search_seq := BTComposite.BTSequence.new()
	search_seq.set_abort_type(BTComposite.AbortType.SELF)
	var cond_mem := ConditionHasMemory.new(3.0)
	var time_limit_search := BTDecorator.BTTimeLimit.new()
	time_limit_search.time_limit = 2.0
	var act_search := ActionInvestigateAndSearch.new(guard)
	bt.connect_parent_child(root_sel, search_seq)
	bt.connect_parent_child(search_seq, cond_mem)
	bt.connect_parent_child(search_seq, time_limit_search)
	bt.connect_parent_child(time_limit_search, act_search)

	# 3. Patrol Branch (Priority 3 - Fallback)
	var act_patrol := ActionPatrol.new(guard)
	bt.connect_parent_child(root_sel, act_patrol)

	return bt

# ---------------------------------------------------------------- Lifecycle

func _ready() -> void:
	_init_simulation()

	if DisplayServer.get_name() == "headless":
		auto_tick = false
	else:
		auto_tick = true

	_build_ui()
	_update_ui_state()

func _physics_process(delta: float) -> void:
	_handle_input(delta)
	if not auto_tick:
		return
	tick_timer += delta
	if tick_timer >= tick_interval:
		tick_timer = 0.0
		tick_manual(tick_interval)

func _handle_input(delta: float) -> void:
	if player == null:
		return
	var move_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if move_dir.length_squared() > 0.001:
		player.pos += move_dir * player_move_speed * delta
		_update_ui_state()
		if map_rect != null:
			map_rect.queue_redraw()

func _exit_tree() -> void:
	_cleanup_runner()

func _cleanup_runner() -> void:
	if runner != null and is_instance_valid(runner):
		runner.stop()
		runner.free()
		runner = null
	tree = null

func _init_simulation() -> void:
	_cleanup_runner()
	guard = GuardActor.new()
	player = PlayerActor.new()

	tree = _build_guard_tree()
	runner = BTRunner.new(tree)
	add_child(runner)
	runner.set_process(false)
	runner.start()

# ---------------------------------------------------------------- Public Control API

func tick_manual(delta: float = 0.1) -> int:
	if runner == null or not is_instance_valid(runner) or not runner.is_running:
		return BTStatus.INACTIVE
	var status := runner.tick(delta)
	_update_ui_state()
	if map_rect != null:
		map_rect.queue_redraw()
	return status

func set_player_pos(new_pos: Vector2) -> void:
	if player != null:
		player.pos = new_pos
	_update_ui_state()
	if map_rect != null:
		map_rect.queue_redraw()

func set_player_hidden(hidden: bool) -> void:
	if player != null:
		player.is_hidden = hidden
	_update_ui_state()
	if map_rect != null:
		map_rect.queue_redraw()

func set_guard_pos(new_pos: Vector2) -> void:
	if guard != null:
		guard.pos = new_pos
	_update_ui_state()
	if map_rect != null:
		map_rect.queue_redraw()

func reset_demo() -> void:
	_init_simulation()
	_update_ui_state()
	if map_rect != null:
		map_rect.queue_redraw()

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
	title_lbl.text = "Guard Stealth AI: 90° FOV Cone, Memory Decay & TimeLimit Search"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_bar.add_child(title_lbl)

	var btn_boss := Button.new()
	btn_boss.text = "Boss AI ➔"
	btn_boss.pressed.connect(func(): get_tree().change_scene_to_file(BOSS_SCENE_PATH))
	nav_bar.add_child(btn_boss)

	var btn_squad := Button.new()
	btn_squad.text = "Squad AI ➔"
	btn_squad.pressed.connect(func(): get_tree().change_scene_to_file(SQUAD_SCENE_PATH))
	nav_bar.add_child(btn_squad)

	# Main Area
	var content_hbox := HBoxContainer.new()
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", 12)
	main_vbox.add_child(content_hbox)

	# Map Visualizer
	map_rect = Control.new()
	map_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_rect.draw.connect(_on_map_draw)
	content_hbox.add_child(map_rect)

	# Right Panel: Controls & Telemetry
	var right_panel := PanelContainer.new()
	right_panel.custom_minimum_size = Vector2(380, 0)
	content_hbox.add_child(right_panel)

	var panel_vbox := VBoxContainer.new()
	panel_vbox.add_theme_constant_override("separation", 8)
	right_panel.add_child(panel_vbox)

	var alert_hdr := Label.new()
	alert_hdr.text = "=== GUARD ALERT STATE ==="
	panel_vbox.add_child(alert_hdr)

	alert_banner = PanelContainer.new()
	alert_label = Label.new()
	alert_label.text = "ALERT: PATROL"
	alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	alert_banner.add_child(alert_label)
	panel_vbox.add_child(alert_banner)

	status_label = Label.new()
	panel_vbox.add_child(status_label)

	var ctrl_hdr := Label.new()
	ctrl_hdr.text = "=== INTERACTIVE TEST CONTROLS ==="
	panel_vbox.add_child(ctrl_hdr)

	var btn_toggle_hide := Button.new()
	btn_toggle_hide.text = "Toggle Player Hidden (Cover)"
	btn_toggle_hide.pressed.connect(func(): set_player_hidden(not player.is_hidden))
	panel_vbox.add_child(btn_toggle_hide)

	var pos_hbox := HBoxContainer.new()
	panel_vbox.add_child(pos_hbox)

	var btn_front := Button.new()
	btn_front.text = "Place Player in FOV (50, 0)"
	btn_front.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_front.pressed.connect(func():
		set_player_pos(Vector2(50, 0))
		set_player_hidden(false)
	)
	pos_hbox.add_child(btn_front)

	var btn_away := Button.new()
	btn_away.text = "Place Player Far (200, 200)"
	btn_away.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_away.pressed.connect(func(): set_player_pos(Vector2(200, 200)))
	pos_hbox.add_child(btn_away)

	var btn_decay := Button.new()
	btn_decay.text = "⏩ Wait 3.5s (Trigger Memory Decay)"
	btn_decay.pressed.connect(func(): tick_manual(3.5))
	panel_vbox.add_child(btn_decay)

	var btn_reset := Button.new()
	btn_reset.text = "↺ Reset Guard & Player"
	btn_reset.pressed.connect(reset_demo)
	panel_vbox.add_child(btn_reset)

	var sim_hdr := Label.new()
	sim_hdr.text = "=== SIMULATION & INPUT ==="
	panel_vbox.add_child(sim_hdr)

	var hint_lbl := Label.new()
	hint_lbl.text = "Interactive tip: Use WASD or Arrow Keys\nto move the blue player in real time!"
	panel_vbox.add_child(hint_lbl)

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

func _update_ui_state() -> void:
	if guard == null or player == null or tree == null or tree.blackboard == null:
		return

	var alert := guard.alert_level
	if alert_label != null:
		alert_label.text = "ALERT LEVEL: %s" % alert.to_upper()

	var has_mem: bool = bool(tree.blackboard.get_var("has_memory", false))
	var last_seen: Vector2 = tree.blackboard.get_var("last_seen_pos", Vector2.ZERO)
	var t_seen: float = float(tree.blackboard.get_var("time_last_seen", 0.0))
	var cur_time: float = runner.time if runner != null else 0.0
	var mem_remaining: float = max(0.0, 3.0 - (cur_time - t_seen)) if has_mem else 0.0

	var dist := guard.pos.distance_to(player.pos)
	var dir := (player.pos - guard.pos).normalized()
	var in_fov := (dist <= 100.0) and (guard.facing.dot(dir) >= cos(deg_to_rad(45.0))) and not player.is_hidden

	if status_label != null:
		status_label.text = (
			"Guard Pos: (%.1f, %.1f) Facing: (%.1f, %.1f)\n" +
			"Player Pos: (%.1f, %.1f) Hidden: %s\n" +
			"Dist to Player: %.1f | In Vision: %s\n" +
			"Memory: %s (Time left: %.1fs)\n" +
			"Last Seen Pos: (%.1f, %.1f)"
		) % [
			guard.pos.x, guard.pos.y, guard.facing.x, guard.facing.y,
			player.pos.x, player.pos.y, str(player.is_hidden),
			dist, ("YES" if in_fov else "NO"),
			("ACTIVE" if has_mem else "EXPIRED"), mem_remaining,
			last_seen.x, last_seen.y
		]

func _sim_to_screen(sim_pos: Vector2, center: Vector2) -> Vector2:
	# Scales 0..40 waypoint range into visible screen coordinate
	return center + (sim_pos - Vector2(20.0, 0.0)) * 2.8

func _on_map_draw() -> void:
	if map_rect == null or guard == null or player == null or tree == null:
		return
	var size := map_rect.size
	if size.x < 10 or size.y < 10:
		return

	# Background room
	map_rect.draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.13, 0.18), true)
	var center := size * 0.5

	# Patrol Waypoints & dashed route
	var wp0_screen := _sim_to_screen(Vector2(0, 0), center)
	var wp1_screen := _sim_to_screen(Vector2(40, 0), center)
	map_rect.draw_line(wp0_screen, wp1_screen, Color(0.3, 0.4, 0.5, 0.5), 2.0)
	map_rect.draw_circle(wp0_screen, 6.0, Color(0.3, 0.6, 0.8))
	map_rect.draw_circle(wp1_screen, 6.0, Color(0.3, 0.6, 0.8))

	# Screen positions
	var guard_screen := _sim_to_screen(guard.pos, center)
	var player_screen := _sim_to_screen(player.pos, center)

	# Render 90° FOV Cone
	var fov_radius := 100.0 * 2.8
	var cone_color := Color(0.2, 0.8, 0.3, 0.22) # Green for Patrol
	match guard.alert_level:
		"Curious": cone_color = Color(0.9, 0.8, 0.2, 0.25) # Yellow
		"Search": cone_color = Color(0.95, 0.55, 0.1, 0.3) # Orange
		"Chase": cone_color = Color(0.95, 0.2, 0.2, 0.35) # Red

	var facing_angle := guard.facing.angle()
	var half_fov := deg_to_rad(45.0)
	var cone_pts: PackedVector2Array = [guard_screen]
	var arc_steps := 24
	for step in range(arc_steps + 1):
		var a := (facing_angle - half_fov) + (float(step) / float(arc_steps)) * (half_fov * 2.0)
		cone_pts.append(guard_screen + Vector2.from_angle(a) * fov_radius)

	map_rect.draw_colored_polygon(cone_pts, cone_color)
	map_rect.draw_polyline(cone_pts, Color(cone_color.r, cone_color.g, cone_color.b, 0.8), 1.5)

	# Last-Seen Memory Ghost Marker with fading alpha
	var has_mem: bool = bool(tree.blackboard.get_var("has_memory", false))
	if has_mem:
		var last_seen_sim: Vector2 = tree.blackboard.get_var("last_seen_pos", guard.pos)
		var t_seen: float = float(tree.blackboard.get_var("time_last_seen", 0.0))
		var cur_time: float = runner.time if runner != null else 0.0
		var alpha: float = clampf(1.0 - (cur_time - t_seen) / 3.0, 0.1, 0.9)
		var ghost_screen := _sim_to_screen(last_seen_sim, center)
		map_rect.draw_arc(ghost_screen, 18.0, 0.0, TAU, 24, Color(1.0, 0.8, 0.2, alpha), 2.0)
		map_rect.draw_line(ghost_screen + Vector2(-12, 0), ghost_screen + Vector2(12, 0), Color(1.0, 0.8, 0.2, alpha), 1.5)
		map_rect.draw_line(ghost_screen + Vector2(0, -12), ghost_screen + Vector2(0, 12), Color(1.0, 0.8, 0.2, alpha), 1.5)

	# Guard Body & Pointer
	map_rect.draw_circle(guard_screen, 20.0, Color(0.85, 0.3, 0.25))
	map_rect.draw_arc(guard_screen, 20.0, 0.0, TAU, 24, Color.WHITE, 2.0)
	var pointer_end := guard_screen + guard.facing * 28.0
	map_rect.draw_line(guard_screen, pointer_end, Color.WHITE, 3.0)

	# Player Body
	if player.is_hidden:
		map_rect.draw_circle(player_screen, 16.0, Color(0.2, 0.4, 0.7, 0.3))
		map_rect.draw_arc(player_screen, 16.0, 0.0, TAU, 16, Color(0.4, 0.7, 1.0, 0.5), 1.5)
	else:
		map_rect.draw_circle(player_screen, 16.0, Color(0.2, 0.6, 1.0))
		map_rect.draw_arc(player_screen, 16.0, 0.0, TAU, 24, Color.WHITE, 2.0)
