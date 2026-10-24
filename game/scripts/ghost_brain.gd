class_name GhostBrain
extends Node

## Controller brain for GhostActor.
## Automatically loads and attaches GhostBT from 'res://game/scripts/bt/ghost_bt.gd'
## when available. If not yet created by BT agent, provides a full GDScript
## fallback loop reproducing the exact Devour Ghost_42115 behavior.

var actor: GhostActor = null
var bt_runner: Variant = null
var is_using_bt_addon: bool = false

# Fallback loop state
var _wander_target: Vector3 = Vector3.ZERO
var _wander_timer: float = 0.0
var _chase_target: Node3D = null
var _chase_lost_timer: float = 0.0
var _uv_fry_timer: float = 0.0

func _ready() -> void:
	actor = get_parent() as GhostActor
	if not actor:
		push_error("[GhostBrain] Must be child of GhostActor")
		return

	_init_brain()

func _init_brain() -> void:
	# Try to load official BT bridge from BT agent
	if ResourceLoader.exists("res://game/scripts/bt/ghost_bt.gd"):
		var ghost_bt_script = load("res://game/scripts/bt/ghost_bt.gd")
		if ghost_bt_script and ghost_bt_script.has_method("attach"):
			bt_runner = ghost_bt_script.attach(actor)
			if bt_runner != null:
				add_child(bt_runner)
				bt_runner.start()
				is_using_bt_addon = true
				print("[GhostBrain] Successfully attached GhostBT runner via ghost_bt.gd")
				return

	push_warning("[GhostBrain] res://game/scripts/bt/ghost_bt.gd not available yet. Operating in standalone fallback mode (full Wander/Perception/Fry/Pursue logic).")
	is_using_bt_addon = false
	_wander_target = actor.global_position

func stop_brain() -> void:
	if bt_runner and is_instance_valid(bt_runner):
		bt_runner.stop()

func start_brain() -> void:
	if bt_runner and is_instance_valid(bt_runner):
		bt_runner.start()

func _exit_tree() -> void:
	stop_brain()

func _physics_process(delta: float) -> void:
	if is_using_bt_addon:
		# BT Runner handles execution automatically
		return

	if not actor or actor.is_banished:
		return

	# --- Branch 1 & 2: Flashlight UV Frying & Hit Reaction ---
	var uv_player = actor.is_flashlight_shining_on_me(true, 6.0)
	if uv_player != null:
		actor.set_parameter("AbilityIntData", 666)
		actor.set_motor_speed(0.1) # Drastic slowdown when UV fried
		_uv_fry_timer += delta
		if _uv_fry_timer >= 1.5:
			# Banished!
			_uv_fry_timer = 0.0
			actor.set_parameter("AbilityIndex", 204)
			actor.on_ghost_banished()
			return
	else:
		if actor.ability_int_data == 666:
			actor.set_parameter("AbilityIntData", 0)
			actor.set_motor_speed(actor.base_speed)
		_uv_fry_timer = max(0.0, _uv_fry_timer - delta * 0.5)

	# --- Branch 0.3: Ritual Book Defense ---
	var nearby_book = actor.query_nearby_objects("RitualBook", 6.0, true)
	if nearby_book and is_instance_valid(nearby_book):
		var book_on_altar = nearby_book.get("is_placed_on_altar")
		if not book_on_altar and actor.carried_object != nearby_book:
			actor.set_parameter("AbilityIndex", 202)
			actor.step_pursue(nearby_book.global_position, 1.8, delta)
			if actor.global_position.distance_to(nearby_book.global_position) <= 0.8:
				actor.attach_carried_object(nearby_book)
				actor.set_parameter("AbilityIndex", 203)
			return

	if actor.carried_object != null:
		# Flee with ritual book
		actor.set_parameter("AbilityIndex", 203)
		var player = actor._get_player()
		if player and actor.global_position.distance_to(player.global_position) <= 6.0:
			var flee_point = actor.compute_flee_point(player.global_position, 8.0)
			actor.move_towards(flee_point, 3.0, delta)
		else:
			actor.move_towards(_wander_target, 1.5, delta)
		return

	# --- Branch 0.2: Perception & Senses ---
	var player = actor._get_player()
	if player and is_instance_valid(player):
		var can_see = actor.can_see_target(player, 75.0, 20.0)
		var hear_noise = actor.detect_player_noise(1.5, 15.0)
		var see_light = actor.is_flashlight_shining_on_me(false, 15.0)

		# Check if player is hidden
		var player_hidden = (player.has_method("get_ability_index") and player.get_ability_index() == 108)

		if not player_hidden and (can_see or hear_noise != null or see_light != null):
			_chase_target = player
			_chase_lost_timer = 0.0
			if actor.ability_index != 202:
				actor.set_parameter("AbilityIndex", 202) # Pursue
				actor.handle_bt_event("OnGhostPursue")
		elif _chase_target != null:
			_chase_lost_timer += delta
			if _chase_lost_timer >= 3.0: # Lost target for 3.0s -> return to wander
				_chase_target = null
				actor.set_parameter("AbilityIndex", 0)

	# --- Movement Execution ---
	if _chase_target != null:
		actor.step_pursue(_chase_target.global_position, actor.current_speed, delta)
	else:
		_wander_timer -= delta
		if _wander_timer <= 0.0:
			_wander_timer = randf_range(4.0, 7.0)
			_wander_target = actor.get_random_navmesh_point(5.0, 10.0)
			actor.set_nav_target(_wander_target)
		actor.step_navigation(delta, actor.current_speed, true)
