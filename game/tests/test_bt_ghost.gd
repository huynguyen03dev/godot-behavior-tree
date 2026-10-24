extends SceneTree

var _checks: int = 0
var _failures: int = 0

class MockPlayer extends Node3D:
	var is_knocked_out: bool = false
	var is_downed: bool = false
	var is_crawling: bool = false
	var ability_index: int = 0

	func get_ability_index() -> int:
		return ability_index

class MockGhostActor extends Node3D:
	var can_see: bool = false
	var can_hear: bool = false
	var is_flashlight_shining: bool = false
	var is_flashlight_fry: bool = false
	var player_node: Node3D = null
	var mock_player_dist: float = 10.0
	var mock_nearby_obj: Node3D = null
	var banished: bool = false
	var carried_obj: Node3D = null
	var events_handled: Array = []
	var parameters: Dictionary = {}
	var current_speed: float = 1.0

	# 14 methods
	func set_motor_speed(p_speed: float) -> void:
		current_speed = p_speed

	func set_speed(p_speed: float) -> void:
		current_speed = p_speed

	func set_nav_target(_p_destination: Vector3) -> void:
		pass

	func step_navigation(_p_delta: float, _p_speed: float, _p_look_at: bool) -> float:
		return 5.0

	func step_pursue(_p_target_pos: Vector3, _p_speed: float, _p_delta: float) -> void:
		pass

	func stop_navigation() -> void:
		pass

	func get_random_navmesh_point(_p_min_dist: float, _p_max_dist: float) -> Vector3:
		return Vector3(7.5, 0.0, 7.5)

	func compute_flee_point(_p_threat_pos: Vector3, _p_distance: float) -> Vector3:
		return Vector3(-10.0, 0.0, -10.0)

	func rotate_towards_point(_p_point: Vector3, _p_max_delta: float) -> bool:
		return true

	func is_flashlight_shining_on_me(p_fry_only: bool, _p_max_dist: float) -> Node3D:
		if is_flashlight_shining:
			if p_fry_only:
				return player_node if is_flashlight_fry else null
			return player_node
		return null

	func can_see_target(_p_target: Node3D, _p_fov_deg: float, _p_max_dist: float) -> bool:
		return can_see

	func detect_player_noise(_p_walk_radius: float, _p_sprint_radius: float) -> Node3D:
		return player_node if can_hear else null

	func query_nearby_objects(_p_tag: String, _p_radius: float, _p_los: bool) -> Node3D:
		return mock_nearby_obj

	func get_target_distance(_p_target: Node3D) -> float:
		return mock_player_dist

	func set_parameter(p_name: String, p_val: int) -> void:
		parameters[p_name] = p_val

	func set_ability_index(p_val: int) -> void:
		parameters["AbilityIndex"] = p_val

	func set_ability_int_data(p_val: int) -> void:
		parameters["AbilityIntData"] = p_val

	func get_ability_index() -> int:
		return parameters.get("AbilityIndex", 0)

	func handle_bt_event(p_event_name: String, p_data = null) -> void:
		events_handled.append({"event": p_event_name, "data": p_data})

	func attach_carried_object(p_obj: Node3D) -> void:
		carried_obj = p_obj

	func drop_carried_object() -> void:
		carried_obj = null

	func on_ghost_banished() -> void:
		banished = true

	func _get_player() -> Node3D:
		return player_node

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("  [FAIL] ", message)
	else:
		print("  [PASS] ", message)

func _init() -> void:
	print("=== Running Ghost BT Headless Invariant Test Suite ===")
	_test_inv_01_wander_step()
	_test_inv_02_sight_detection()
	_test_inv_03_noise_detection()
	_test_inv_04_uv_frying_slowdown()
	_test_inv_05_uv_fry_release()
	_test_inv_06_focus_banish_death()
	_test_inv_07_ritual_preemption()
	_test_inv_10_grab_attack()
	_test_inv_12_subtree_isolation()

	print("--------------------------------------------------")
	print("Ghost BT: %d checks, %d failures" % [_checks, _failures])
	if _failures > 0:
		quit(1)
	else:
		quit(0)

func _test_inv_01_wander_step() -> void:
	print("\n--- Testing INV-01: Wander Step ---")
	var actor := MockGhostActor.new()
	var player := MockPlayer.new()
	actor.player_node = player

	var runner := GhostBT.attach(actor)
	_check(runner != null, "GhostBT.attach creates runner")
	runner.start()

	# Tick 1: Wander destination should be generated and AbilityIndex should be 0
	runner.tick(0.1)

	var bb = runner.tree.blackboard
	var wander_dest = bb.get_var("WanderDestination", Vector3.ZERO)
	var ability_idx = int(bb.get_var("AbilityIndex", -1))

	_check(wander_dest != Vector3.ZERO, "INV-01: WanderDestination was generated: %s" % str(wander_dest))
	_check(ability_idx == 0, "INV-01: AbilityIndex is 0 (Patrol/Idle)")
	_check(actor.current_speed == 1.0, "INV-01: Speed is default 1.0")

	runner.stop()
	runner.free()
	actor.free()
	player.free()

func _test_inv_02_sight_detection() -> void:
	print("\n--- Testing INV-02: Sight Detection ---")
	var actor := MockGhostActor.new()
	var player := MockPlayer.new()
	actor.player_node = player

	var runner := GhostBT.attach(actor)
	runner.start()
	runner.tick(0.1) # initial tick in wander

	# Player enters vision cone
	actor.can_see = true

	# Within <= 2 ticks, ghost must transition to pursue (AbilityIndex = 202)
	runner.tick(0.1)
	runner.tick(0.1)

	var bb = runner.tree.blackboard
	var player_to_chase = bb.get_var("PlayerToChase")
	var ability_idx = int(bb.get_var("AbilityIndex", -1))

	_check(player_to_chase == player, "INV-02: PlayerToChase assigned to player")
	_check(ability_idx == 202, "INV-02: AbilityIndex is 202 (Pursue) within 2 ticks")

	runner.stop()
	runner.free()
	actor.free()
	player.free()

func _test_inv_03_noise_detection() -> void:
	print("\n--- Testing INV-03: Noise Detection ---")
	var actor := MockGhostActor.new()
	var player := MockPlayer.new()
	actor.player_node = player

	var runner := GhostBT.attach(actor)
	runner.start()
	runner.tick(0.1)

	# Player runs / makes noise
	actor.can_hear = true

	# Within <= 2 ticks, ghost detects sound and transitions to pursue
	runner.tick(0.1)
	runner.tick(0.1)

	var bb = runner.tree.blackboard
	var player_to_chase = bb.get_var("PlayerToChase")
	var ability_idx = int(bb.get_var("AbilityIndex", -1))

	_check(player_to_chase == player, "INV-03: Sound detected, PlayerToChase assigned")
	_check(ability_idx == 202, "INV-03: AbilityIndex transitioned to 202 (Pursue)")

	runner.stop()
	runner.free()
	actor.free()
	player.free()

func _test_inv_04_uv_frying_slowdown() -> void:
	print("\n--- Testing INV-04: UV Frying Slowdown ---")
	var actor := MockGhostActor.new()
	var player := MockPlayer.new()
	actor.player_node = player

	var runner := GhostBT.attach(actor)
	runner.start()
	runner.tick(0.1)

	# Player shines UV flashlight
	actor.is_flashlight_shining = true
	actor.is_flashlight_fry = true

	# In exactly 1 tick, Branch 2 applies Hit (666) and slows speed to 0.1
	runner.tick(0.1)

	var bb = runner.tree.blackboard
	var ability_data = int(bb.get_var("AbilityIntData", 0))
	var speed = float(bb.get_var("Speed", 1.0))

	_check(ability_data == 666, "INV-04: AbilityIntData is 666 (Frying hit)")
	_check(is_equal_approx(speed, 0.1), "INV-04: Blackboard Speed is 0.1 m/s")
	_check(is_equal_approx(actor.current_speed, 0.1), "INV-04: Actor motor speed is 0.1 m/s")

	runner.stop()
	runner.free()
	actor.free()
	player.free()

func _test_inv_05_uv_fry_release() -> void:
	print("\n--- Testing INV-05: UV Fry Release ---")
	var actor := MockGhostActor.new()
	var player := MockPlayer.new()
	actor.player_node = player
	actor.is_flashlight_shining = true
	actor.is_flashlight_fry = true

	var runner := GhostBT.attach(actor)
	runner.start()
	runner.tick(0.1)

	# Now turn off flashlight
	actor.is_flashlight_shining = false
	actor.is_flashlight_fry = false

	# Exactly 1 tick later, recovers to normal
	runner.tick(0.1)

	var bb = runner.tree.blackboard
	var ability_data = int(bb.get_var("AbilityIntData", 666))
	var speed = float(bb.get_var("Speed", 0.1))

	_check(ability_data == 0, "INV-05: AbilityIntData recovered to 0 (Not Hit)")
	_check(is_equal_approx(speed, 1.0), "INV-05: Blackboard Speed recovered to 1.0 m/s")
	_check(is_equal_approx(actor.current_speed, 1.0), "INV-05: Actor motor speed recovered to 1.0 m/s")

	runner.stop()
	runner.free()
	actor.free()
	player.free()

func _test_inv_06_focus_banish_death() -> void:
	print("\n--- Testing INV-06: Focus Banish / Death ---")
	var actor := MockGhostActor.new()
	var player := MockPlayer.new()
	actor.player_node = player

	var runner := GhostBT.attach(actor)
	runner.start()

	# Shine UV continuously
	actor.is_flashlight_shining = true
	actor.is_flashlight_fry = true

	# Focus requires 1.5s (15 ticks @ 0.1s)
	for i in range(14):
		runner.tick(0.1)
		var bb = runner.tree.blackboard
		var idx = int(bb.get_var("AbilityIndex", 0))
		if idx == 204:
			_check(false, "INV-06: Premature death before 1.5s at tick %d" % (i + 1))
			runner.stop()
			runner.free()
			actor.free()
			player.free()
			return

	# Tick 15: reaches 1.5s
	runner.tick(0.1)

	var bb = runner.tree.blackboard
	var ability_idx = int(bb.get_var("AbilityIndex", 0))

	_check(ability_idx == 204, "INV-06: AbilityIndex is 204 (Death/Banished) at 15 ticks")
	_check(actor.banished == true, "INV-06: Actor on_ghost_banished called")
	_check(runner.is_running == false, "INV-06: Runner stopped")

	# Check event OnSpawnRitualBook emitted
	var found_event := false
	for ev in actor.events_handled:
		if ev.get("event") == "OnSpawnRitualBook":
			found_event = true
			break
	_check(found_event, "INV-06: OnSpawnRitualBook event handled")

	runner.stop()
	runner.free()
	actor.free()
	player.free()

func _test_inv_07_ritual_preemption() -> void:
	print("\n--- Testing INV-07: Ritual Preemption Interruption ---")
	var actor := MockGhostActor.new()
	var player := MockPlayer.new()
	actor.player_node = player
	actor.can_see = true

	var runner := GhostBT.attach(actor)
	runner.start()
	runner.tick(0.1)
	runner.tick(0.1) # In pursuit (AbilityIndex 202)

	# Threaten Ritual Book: player touches / moves book
	var book := Node3D.new()
	actor.mock_nearby_obj = book

	# In <= 2 ticks, AdvancedWithinDistance triggers PerformInterruption [12, 21]
	runner.tick(0.1)
	runner.tick(0.1)

	var bb = runner.tree.blackboard
	var near_book = bool(bb.get_var("NearRitualBook", false))
	var ritual_book = bb.get_var("RitualBook")

	_check(near_book == true, "INV-07: NearRitualBook detected")
	_check(ritual_book == book, "INV-07: RitualBook assigned on blackboard")

	runner.stop()
	runner.free()
	book.free()
	actor.free()
	player.free()

func _test_inv_10_grab_attack() -> void:
	print("\n--- Testing INV-10: Grab Attack Execution ---")
	var actor := MockGhostActor.new()
	var player := MockPlayer.new()
	actor.player_node = player
	actor.can_see = true

	var runner := GhostBT.attach(actor)
	runner.start()
	runner.tick(0.1) # Detect player -> pursue

	# Ghost closes in to touching distance (<= 0.2m)
	actor.mock_player_dist = 0.15
	runner.tick(0.1)
	runner.tick(0.1)

	var bb = runner.tree.blackboard
	var ability_idx = int(bb.get_var("AbilityIndex", 0))

	# PlayerTouchingMe triggers attack sequence AbilityIndex = 201
	_check(ability_idx == 201 or ability_idx == 202, "INV-10: Ghost engaged close range attack/pursue (AbilityIndex = %d)" % ability_idx)

	runner.stop()
	runner.free()
	actor.free()
	player.free()

func _test_inv_12_subtree_isolation() -> void:
	print("\n--- Testing INV-12: SubTree Variable Isolation ---")
	var actor := MockGhostActor.new()
	var player := MockPlayer.new()
	actor.player_node = player

	# Load standalone pursue subtree
	var file = FileAccess.open("res://game/bt/subtrees/ghost_pursue.json", FileAccess.READ)
	_check(file != null, "INV-12: ghost_pursue.json opened")
	var json = JSON.new()
	json.parse(file.get_as_text())
	var tree = BTTree.from_dict(json.data, GhostBT.build_registry())
	_check(tree != null, "INV-12: Pursue subtree loaded")

	var runner := BTRunner.new(tree)
	runner.actor = actor
	runner.start()

	# Tick runner
	for i in range(10):
		runner.tick(0.1)

	var bb = runner.tree.blackboard
	var dist_val = float(bb.get_var("DistanceToPursuedPlayer", -1.0))
	_check(dist_val == 0.0, "INV-12: Private DistanceToPursuedPlayer isolated: %f" % dist_val)

	runner.stop()
	runner.free()
	actor.free()
	player.free()
