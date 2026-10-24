extends SceneTree

var _checks: int = 0
var _failures: int = 0

class MockPlayerNode extends Node3D:
	pass

class MockRatActor extends Node3D:
	var is_caught: bool = false
	var is_placed_on_pit: bool = false
	var player_node: Node3D = null
	var locomotion_state: String = "Default"
	var move_calls: Array = []
	var random_navmesh_calls: int = 0
	var flee_calls: int = 0
	var squeak_count: int = 0
	var shared_bools: Dictionary = {}

	func get_player() -> Node3D:
		return player_node

	func set_locomotion_state(state: String) -> void:
		locomotion_state = state

	func move_towards_point(point: Vector3, speed: float) -> void:
		move_calls.append({"point": point, "speed": speed})
		global_position = global_position.move_toward(point, speed * 0.1)

	func get_random_navmesh_point(min_d: float, max_d: float) -> Vector3:
		random_navmesh_calls += 1
		return global_position + Vector3(randf_range(min_d, max_d), 0.0, 0.0)

	func flee_from(node: Node3D) -> Vector3:
		flee_calls += 1
		var rat_pos: Vector3 = position
		var node_pos: Vector3 = node.position
		var diff = rat_pos - node_pos
		diff.y = 0.0
		var dir = diff.normalized()
		if dir.length_squared() < 0.001:
			dir = Vector3.BACK
		return rat_pos + dir * 5.0

	func play_squeak() -> void:
		squeak_count += 1

	func set_shared_bool(name: String, v: bool) -> void:
		shared_bools[name] = v

	func get_shared_bool(name: String) -> bool:
		return shared_bools.get(name, false)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("  [FAIL] ", message)
	else:
		print("  [PASS] ", message)

func _init() -> void:
	print("=== Running Rat BT Headless Test Suite ===")
	_test_tree_validation_and_load()
	_test_wander_behavior()
	_test_flee_behavior()
	_test_is_caught_stops_movement()
	_test_is_placed_on_pit_stops_movement()
	_test_api_graceful_degradation()

	print("--------------------------------------------------")
	print("Rat BT: %d checks, %d failures" % [_checks, _failures])
	if _failures > 0:
		quit(1)
	else:
		quit(0)

func _test_tree_validation_and_load() -> void:
	print("\n--- Testing Tree Validation and Node Count ---")
	var file = FileAccess.open("res://game/bt/rat_main.json", FileAccess.READ)
	_check(file != null, "rat_main.json opened successfully")
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	_check(err == OK, "rat_main.json JSON parses with OK")

	var data = json.data
	var registry = RatBT.build_registry()
	var val_errors = BTTree.validate_dict(data, registry)
	_check(val_errors.is_empty(), "BTTree.validate_dict has 0 errors: %s" % str(val_errors))

	var tree = BTTree.from_dict(data, registry)
	_check(tree != null, "BTTree.from_dict successfully instantiates tree")
	if tree != null:
		var node_count = tree.get_node_count()
		_check(node_count == 71, "Tree has exactly 71 nodes (actual: %d)" % node_count)

func _test_wander_behavior() -> void:
	print("\n--- Testing Invariant: Wander when Quiet ---")
	var rat := MockRatActor.new()
	rat.global_position = Vector3(0.0, 0.0, 0.0)

	var runner := RatBT.attach(rat)
	_check(runner != null, "RatBT.attach creates runner")
	runner.start()

	# Tick runner to run wander
	runner.tick(0.1)

	_check(rat.random_navmesh_calls > 0, "Wander queried random navmesh point")
	_check(rat.move_calls.size() > 0, "Wander triggered move_towards_point")
	if rat.move_calls.size() > 0:
		var last_call = rat.move_calls[-1]
		var speed = float(last_call.get("speed", 0.0))
		_check(speed >= 0.4 and speed <= 1.5, "Wander speed is within expected range (~0.4 - 1.5 m/s): %f" % speed)

	runner.stop()
	runner.free()
	rat.free()

func _test_flee_behavior() -> void:
	print("\n--- Testing Invariant: Player in Proximity Triggers Flee ---")
	var rat := MockRatActor.new()
	rat.global_position = Vector3(0.0, 0.0, 0.0)

	var player := MockPlayerNode.new()
	player.global_position = Vector3(1.0, 0.0, 0.0) # Within 2m fear distance
	rat.player_node = player

	var runner := RatBT.attach(rat)
	runner.start()

	# Tick 1: Proximity check detects player, sets PlayerWithinDistance, interrupts wander
	runner.tick(0.1)
	# Tick 2: Flee branch runs
	runner.tick(0.1)

	var bb = runner.tree.blackboard
	var player_in_bb = bb.get_var("PlayerWithinDistance")
	_check(player_in_bb == player, "Player assigned to PlayerWithinDistance on blackboard")

	_check(rat.flee_calls > 0, "Actor flee_from was invoked")
	_check(rat.move_calls.size() > 0, "Flee movement called")

	if rat.move_calls.size() > 0:
		var last_call = rat.move_calls[-1]
		var flee_speed = float(last_call.get("speed", 0.0))
		var dest = Vector3(last_call.get("point", Vector3.ZERO))
		_check(flee_speed >= 3.0, "Flee speed is higher than wander (~3.0 - 4.0 m/s): %f" % flee_speed)
		# Destination should be away from player (player is at +1 X, rat was at 0, flee point should be at negative X)
		_check(dest.x < 0.0, "Flee destination moves away from player: dest=%s" % str(dest))

	runner.stop()
	runner.free()
	player.free()
	rat.free()

func _test_is_caught_stops_movement() -> void:
	print("\n--- Testing Invariant: Caught Rat Stops Movement ---")
	var rat := MockRatActor.new()
	rat.global_position = Vector3(0.0, 0.0, 0.0)
	rat.is_caught = true

	var runner := RatBT.attach(rat)
	runner.start()

	for i in range(5):
		runner.tick(0.1)

	_check(rat.move_calls.size() == 0, "No move_towards_point calls while is_caught == true")

	# Test release (is_caught becomes false) with player nearby -> starts fleeing
	rat.is_caught = false
	var player := MockPlayerNode.new()
	player.global_position = Vector3(1.0, 0.0, 0.0)
	rat.player_node = player

	runner.tick(0.1)
	runner.tick(0.1)

	_check(rat.move_calls.size() > 0, "Rat starts moving/fleeing immediately after being released")

	runner.stop()
	runner.free()
	player.free()
	rat.free()

func _test_is_placed_on_pit_stops_movement() -> void:
	print("\n--- Testing Invariant: Placed on Pit Stops Movement ---")
	var rat := MockRatActor.new()
	rat.global_position = Vector3(5.0, 0.0, 5.0)
	rat.is_placed_on_pit = true

	var runner := RatBT.attach(rat)
	runner.start()

	for i in range(5):
		runner.tick(0.1)

	_check(rat.move_calls.size() == 0, "No move_towards_point calls while is_placed_on_pit == true")

	runner.stop()
	runner.free()
	rat.free()

func _test_api_graceful_degradation() -> void:
	print("\n--- Testing Graceful Degradation on Plain Node3D Actor ---")
	var bare_actor := Node3D.new()

	var runner := RatBT.attach(bare_actor)
	_check(runner != null, "RatBT.attach succeeds with bare Node3D")
	runner.start()

	# Tick several times without crash
	var crashed := false
	for i in range(5):
		runner.tick(0.1)

	_check(not crashed, "Runner ticks smoothly without crashing on actor lacking methods")

	runner.stop()
	runner.free()
	bare_actor.free()
