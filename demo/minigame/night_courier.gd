extends Node2D

const W := 1152.0
const H := 720.0
const PARCELS := [Vector2(175, 185), Vector2(570, 545), Vector2(970, 180)]
const EXIT := Rect2(1000, 565, 100, 76)
const START := Vector2(100, 595)
const SPEED := 205.0
const GUARD_SPEED := 90.0
const DETECT := 225.0

class Guard extends Node2D:
	var game: Node2D
	var route: Array[Vector2] = []
	var waypoint := 1
	var last_seen := Vector2.ZERO
	var searching := false
	var behavior := "PATROL"
	var search_wait := 0.0
	var runner: BTRunner
	func sees_courier() -> bool: return global_position.distance_to(game.player) < DETECT
	func move_guard(target: Vector2, speed: float, delta: float) -> bool:
		global_position = global_position.move_toward(target, speed * delta)
		return global_position.distance_to(target) < 9.0
	func patrol(delta: float) -> void:
		global_position = global_position.move_toward(route[waypoint], GUARD_SPEED * delta)
		if global_position.distance_to(route[waypoint]) < 4.0: waypoint = 1 - waypoint
	func chase_started() -> void:
		behavior = "CHASE"
		game.event_counts["chase_starts"] += 1
	func chase_aborted() -> void:
		behavior = "SEARCH"
		game.event_counts["chase_aborts"] += 1
	func search_started() -> void:
		behavior = "SEARCH"
		search_wait = 0.0
		game.event_counts["search_starts"] += 1

class WatchCondition extends BTTask:
	func _init() -> void:
		type_name = "CanSeeCourier"
		category = "Condition"
	func on_update() -> int:
		return BTStatus.SUCCESS if owner.actor.sees_courier() else BTStatus.FAILURE
	func evaluate_condition(runner_arg: BTRunner) -> int:
		return BTStatus.SUCCESS if runner_arg.actor.sees_courier() else BTStatus.FAILURE

class HeardCondition extends BTTask:
	func _init() -> void:
		type_name = "HasLastSeen"
		category = "Condition"
	func on_update() -> int:
		return BTStatus.SUCCESS if owner.actor.searching else BTStatus.FAILURE
	func evaluate_condition(runner_arg: BTRunner) -> int:
		return BTStatus.SUCCESS if runner_arg.actor.searching else BTStatus.FAILURE

class ChaseAction extends BTTask:
	func _init() -> void:
		type_name = "ChaseCourier"
		category = "Action"
	func on_start() -> void: owner.actor.chase_started()
	func on_update() -> int:
		owner.actor.move_guard(owner.actor.last_seen, GUARD_SPEED * 1.35, owner.delta)
		return BTStatus.RUNNING
	func on_abort() -> void:
		owner.actor.chase_aborted()
		on_end()

class SearchAction extends BTTask:
	func _init() -> void:
		type_name = "SearchLastSeen"
		category = "Action"
	func on_start() -> void: owner.actor.search_started()
	func on_update() -> int:
		var guard: Guard = owner.actor
		if not guard.move_guard(guard.last_seen, GUARD_SPEED, owner.delta): return BTStatus.RUNNING
		guard.search_wait += owner.delta
		if guard.search_wait < 1.0: return BTStatus.RUNNING
		guard.searching = false
		guard.behavior = "PATROL"
		return BTStatus.SUCCESS

class PatrolAction extends BTTask:
	func _init() -> void:
		type_name = "PatrolRoute"
		category = "Action"
	func on_update() -> int:
		owner.actor.patrol(owner.delta)
		return BTStatus.RUNNING

var phase := "title"
var player := START
var hp := 3
var parcels := 0
var elapsed := 0.0
var invuln := 0.0
var dash_time := 0.0
var dash_cooldown := 0.0
var guards: Array[Guard] = []
var telemetry_path := ""
var telemetry_elapsed := 0.0
var physics_steps := 0
var event_counts := {"patrol": 0, "chase_starts": 0, "chase_aborts": 0, "search_starts": 0}
var round_number := 0
var status_label := "PATROL"
var phase_events: Array[Dictionary] = []

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--playtest-state="): telemetry_path = arg.trim_prefix("--playtest-state=")
	start_round()

func make_tree() -> BTTree:
	var tree := BTTree.new()
	var root := BTComposite.BTSelector.new()
	root.set_abort_type(BTComposite.AbortType.LOWER_PRIORITY)
	var chase := BTComposite.BTSequence.new()
	chase.set_abort_type(BTComposite.AbortType.SELF)
	var watch := WatchCondition.new()
	var chase_action := ChaseAction.new()
	var search := BTComposite.BTSequence.new()
	var heard := HeardCondition.new()
	var search_action := SearchAction.new()
	var patrol_action := PatrolAction.new()
	for task in [root, chase, watch, chase_action, search, heard, search_action, patrol_action]: tree.add_node(task)
	tree.set_root(root)
	tree.connect_parent_child(root, chase)
	tree.connect_parent_child(chase, watch)
	tree.connect_parent_child(chase, chase_action)
	tree.connect_parent_child(root, search)
	tree.connect_parent_child(search, heard)
	tree.connect_parent_child(search, search_action)
	tree.connect_parent_child(root, patrol_action)
	return tree

func start_round() -> void:
	for guard in guards:
		if is_instance_valid(guard):
			if guard.runner != null: guard.runner.stop()
			guard.free()
	guards.clear()
	round_number += 1
	event_counts = {"patrol": 0, "chase_starts": 0, "chase_aborts": 0, "search_starts": 0}
	physics_steps = 0
	player = START
	hp = 3
	parcels = 0
	elapsed = 0.0
	invuln = 0.0
	dash_time = 0.0
	dash_cooldown = 0.0
	var specs: Array[Dictionary] = [
		{"pos": Vector2(370, 175), "route": [Vector2(330,175), Vector2(510,175)]},
		{"pos": Vector2(780, 430), "route": [Vector2(690,430), Vector2(900,430)]}
	]
	for spec in specs:
		var guard := Guard.new()
		guard.game = self
		guard.position = spec["pos"]
		guard.route.assign(spec["route"])
		guard.last_seen = START
		add_child(guard)
		guard.runner = BTRunner.new(make_tree())
		guard.runner.actor = guard
		guard.add_child(guard.runner)
		guard.runner.set_process(false)
		guard.runner.start()
		guards.append(guard)
	_set_phase("title")
	_refresh_state()

func _set_phase(next_phase: String) -> void:
	if phase == next_phase: return
	var previous_phase := phase
	phase_events.append({"from": phase, "to": next_phase, "elapsed": elapsed, "round": round_number})
	phase = next_phase
	for guard in guards:
		if guard.runner == null: continue
		if next_phase == "playing":
			if previous_phase == "paused":
				guard.runner.pause(false)
			else:
				if not guard.runner.is_running: guard.runner.start()
				guard.runner.pause(false)
		elif next_phase == "paused":
			guard.runner.pause(true)
		else:
			guard.runner.stop()

func _refresh_state() -> void:
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if phase == "title" and event.keycode in [KEY_ENTER, KEY_SPACE]: _set_phase("playing")
	elif phase == "playing" and event.keycode in [KEY_ESCAPE, KEY_P]: _set_phase("paused")
	elif phase == "paused" and event.keycode in [KEY_ESCAPE, KEY_P]: _set_phase("playing")
	elif phase in ["won", "lost"] and event.keycode == KEY_R: start_round()
	elif phase == "playing" and event.keycode == KEY_SPACE and dash_cooldown <= 0:
		dash_time = 0.18
		dash_cooldown = 1.0
	_refresh_state()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if phase == "title": _set_phase("playing")
		elif phase in ["won", "lost"]: start_round()
		_refresh_state()

func _physics_process(delta: float) -> void:
	physics_steps += 1
	if phase != "playing":
		_write_telemetry(delta)
		return
	elapsed += delta
	invuln = maxf(0.0, invuln-delta)
	dash_cooldown = maxf(0.0, dash_cooldown-delta)
	dash_time = maxf(0.0, dash_time-delta)
	var move := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if Input.is_key_pressed(KEY_A): move.x -= 1.0
	if Input.is_key_pressed(KEY_D): move.x += 1.0
	if Input.is_key_pressed(KEY_W): move.y -= 1.0
	if Input.is_key_pressed(KEY_S): move.y += 1.0
	if move.length() > 1.0: move = move.normalized()
	player += move * SPEED * (2.2 if dash_time > 0.0 else 1.0) * delta
	player.x = clampf(player.x, 38.0, W-38.0)
	player.y = clampf(player.y, 85.0, H-38.0)
	for i in range(PARCELS.size()):
		if not _has_parcel(i) and player.distance_to(PARCELS[i]) < 32.0: parcels |= 1 << i
	for guard in guards:
		if not guard.runner.is_running: guard.runner.start()
		if guard.sees_courier():
			guard.last_seen = player
			guard.searching = true
		guard.runner.tick(delta)
		if guard.behavior == "PATROL" and guard.runner.ticks % 45 == 1: event_counts["patrol"] += 1
		if guard.position.distance_to(player) < 30.0 and invuln <= 0.0:
			hp -= 1
			invuln = 1.25
			if hp <= 0:
				_set_phase("lost")
				break
	if phase == "playing" and parcels == 7 and EXIT.has_point(player): _set_phase("won")
	if not guards.is_empty():
		var guard_labels: Array[String] = []
		for i in range(guards.size()): guard_labels.append("G%d %s" % [i + 1, guards[i].behavior])
		status_label = " | ".join(guard_labels)
	_refresh_state()
	_write_telemetry(delta)

func _has_parcel(index: int) -> bool:
	return (parcels & (1 << index)) != 0

func _parcel_count() -> int:
	var count := 0
	for i in range(3):
		if _has_parcel(i): count += 1
	return count

func _draw() -> void:
	draw_rect(Rect2(0,0,W,H), Color("101b26"))
	for x in range(32, int(W), 48): draw_line(Vector2(x,80), Vector2(x,H), Color("172633"), 1)
	for y in range(80, int(H), 48): draw_line(Vector2(0,y), Vector2(W,y), Color("172633"), 1)
	draw_rect(Rect2(0,0,W,74), Color("0a121b"))
	draw_string(ThemeDB.fallback_font, Vector2(30,42), "NIGHT COURIER", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("8ff0d0"))
	draw_string(ThemeDB.fallback_font, Vector2(350,40), "PARCELS  %d / 3     ♥ %d     TIME  %02d:%02d" % [_parcel_count(), hp, int(elapsed)/60, int(elapsed)%60], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	draw_rect(EXIT, Color("1d5447") if parcels == 7 else Color("303b43"))
	draw_rect(EXIT, Color("8ff0d0"), false, 3)
	draw_string(ThemeDB.fallback_font, EXIT.position+Vector2(10,44), "EXIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	for i in range(PARCELS.size()):
		if not _has_parcel(i):
			draw_rect(Rect2(PARCELS[i]-Vector2(14,11), Vector2(28,22)), Color("edb965"))
			draw_line(PARCELS[i]+Vector2(-14,0),PARCELS[i]+Vector2(14,0),Color("fff0c4"),2)
	for guard in guards:
		draw_circle(guard.position, DETECT, Color(0.95,0.25,0.25,0.07))
		draw_arc(guard.position, DETECT, 0, TAU, 80, Color(0.95,0.3,0.3,0.22), 1)
		draw_circle(guard.position, 17, Color("f36d6d"))
		draw_circle(guard.position+Vector2(6,-5), 3, Color("fff3dd"))
		var guard_index := guards.find(guard) + 1
		draw_string(ThemeDB.fallback_font, guard.position + Vector2(-20, -25), "G%d %s" % [guard_index, guard.behavior], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("fff0c4"))
	draw_circle(player, 14, Color("70d8ef") if invuln <= 0 or int(elapsed*10)%2 == 0 else Color("ffffff"))
	draw_circle(player+Vector2(5,-5),3,Color("09212a"))
	draw_rect(Rect2(20,H-43,W-40,30), Color("0a121b", 0.94))
	draw_string(ThemeDB.fallback_font, Vector2(24,H-22), "WASD / ARROWS  MOVE     SPACE  DASH     P / ESC  PAUSE     GUARDS: %s" % status_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("e1edf4"))
	var dash_status := "DASH READY" if dash_cooldown <= 0 else "DASH %.1f" % dash_cooldown
	draw_string(ThemeDB.fallback_font, Vector2(W-190,42), dash_status, HORIZONTAL_ALIGNMENT_RIGHT, 160, 16, Color("8ff0d0") if dash_cooldown <= 0 else Color("edb965"))
	if phase != "playing":
		draw_rect(Rect2(0,74,W,H-74), Color(0,0,0,.72))
		var title := "NIGHT COURIER" if phase == "title" else ("ROUTE COMPLETE" if phase == "won" else ("CAUGHT IN THE NIGHT" if phase == "lost" else "PAUSED"))
		draw_string(ThemeDB.fallback_font, Vector2(0,295), title, HORIZONTAL_ALIGNMENT_CENTER, W, 44, Color("8ff0d0"))
		if phase == "title":
			draw_string(ThemeDB.fallback_font, Vector2(0,350), "WASD / arrows move  •  Space dash  •  P / Esc pause", HORIZONTAL_ALIGNMENT_CENTER, W, 18, Color.WHITE)
			draw_string(ThemeDB.fallback_font, Vector2(0,382), "Collect all three parcels, then reach the green exit. Enter / click to begin.", HORIZONTAL_ALIGNMENT_CENTER, W, 18, Color.WHITE)
		else:
			var sub := "R / click to run the route again" if phase in ["won","lost"] else "P / Escape to resume"
			draw_string(ThemeDB.fallback_font, Vector2(0,350), sub, HORIZONTAL_ALIGNMENT_CENTER, W, 18, Color.WHITE)

func _write_telemetry(delta: float) -> void:
	if telemetry_path.is_empty(): return
	telemetry_elapsed += delta
	if telemetry_elapsed < 0.2: return
	telemetry_elapsed = 0.0
	var guard_states: Array[Dictionary] = []
	for guard in guards:
		guard_states.append({"position": [guard.position.x,guard.position.y], "behavior": guard.behavior, "searching": guard.searching, "runner_ticks": guard.runner.ticks, "runner_is_processing": guard.runner.is_processing()})
	var viewport := get_viewport()
	var state := {"phase":phase, "phase_events":phase_events, "player":{"position":[player.x,player.y], "hp":hp, "parcels":_parcel_count()}, "guards":guard_states, "counters":event_counts, "round":round_number, "runner_count":guards.size(), "physics_steps":physics_steps, "visible_rect":[viewport.get_visible_rect().position.x, viewport.get_visible_rect().position.y, viewport.get_visible_rect().size.x, viewport.get_visible_rect().size.y], "elapsed":elapsed, "dash_cooldown":dash_cooldown, "dash_time":dash_time, "invuln":invuln}
	var file := FileAccess.open(telemetry_path, FileAccess.WRITE)
	if file != null:
		file.store_line(JSON.stringify(state))
		file.close()
	print(JSON.stringify(state))
