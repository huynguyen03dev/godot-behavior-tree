extends SceneTree

# ==============================================================================
# Game E2E Test Suite for Devour Clone (Farmhouse - Molly)
# Tests real game scene (res://game/scenes/main.tscn) without mock.
# Verifies 19 invariants from TEST_PLAN.md & DESIGN.md.
# ==============================================================================

var _checks: int = 0
var _failures: int = 0
var _bugs: Array = []

func _check(condition: bool, description: String, bug_info: Dictionary = {}) -> void:
	_checks += 1
	if condition:
		print("  [PASS] %s" % description)
	else:
		_failures += 1
		print("  [FAIL] %s" % description)
		if not bug_info.is_empty():
			_bugs.append(bug_info)
			print("         -> BUG [%s]: %s (Expected: %s, Actual: %s)" % [
				bug_info.get("severity", "MAJOR"),
				bug_info.get("invariant", ""),
				bug_info.get("expected", ""),
				bug_info.get("actual", "")
			])

func _initialize() -> void:
	print("=== Running Devour Farmhouse E2E Headless Test Suite ===")

	await _run_gameplay_tests()
	await _run_scene_lifecycle_leak_test()

	print("--------------------------------------------------")
	print("Game E2E: %d checks, %d failures" % [_checks, _failures])

	if _failures > 0:
		print("\n=== SUMMARY OF DETECTED BUGS (%d) ===" % _bugs.size())
		for b in _bugs:
			print("- [%s] %s: %s" % [b.get("severity"), b.get("invariant"), b.get("description")])
			print("  Expected: %s" % b.get("expected"))
			print("  Actual:   %s" % b.get("actual"))
		quit(1)
	else:
		quit(0)

func _run_gameplay_tests() -> void:
	var main_scene_res = load("res://game/scenes/main.tscn")
	if not main_scene_res:
		_check(false, "Load main.tscn", {
			"invariant": "SCENE_LOAD",
			"severity": "BLOCKER",
			"description": "res://game/scenes/main.tscn could not be loaded",
			"expected": "Valid PackedScene",
			"actual": "null"
		})
		return

	var main = main_scene_res.instantiate()
	root.add_child(main)
	current_scene = main

	for i in range(5):
		await process_frame
		await physics_frame

	var gm = main as GameManager
	var player = main.get_node_or_null("Player") as PlayerController
	var ghost = main.get_node_or_null("Ghost") as GhostActor
	var altar = main.get_node_or_null("Altar") as Altar
	var pit = main.get_node_or_null("SacrificePit") as SacrificePit
	var hud = main.get_node_or_null("UIHUD") as UIHUD
	var rats_container = main.get_node_or_null("RatsContainer")

	_check(gm != null, "GameManager instance valid")
	_check(player != null, "PlayerController instance valid")
	_check(ghost != null, "GhostActor instance valid")
	_check(altar != null, "Altar instance valid")
	_check(pit != null, "SacrificePit instance valid")
	_check(rats_container != null, "RatsContainer instance valid")

	if not (gm and player and ghost and altar and pit and rats_container):
		print("Critical nodes missing, aborting scene tests.")
		main.queue_free()
		return

	var ghost_brain = ghost.get_node_or_null("GhostBrain")
	var runner = ghost_brain.bt_runner if ghost_brain else null
	var runner_auto_started = runner != null and runner.is_running
	_check(runner_auto_started, "Ghost BT Runner attached and running by GhostBrain", {
		"invariant": "GHOST_BRAIN_RUNNER",
		"severity": "BLOCKER",
		"description": "GhostBrain attaches GhostBT runner but never calls runner.start() and never adds it to SceneTree, leaving Molly completely inert in gameplay",
		"expected": "runner != null and runner.is_running == true",
		"actual": "runner != null, runner.is_running == false"
	})

	# Start runner explicitly if not auto-started to allow headless E2E verification of tree logic
	if runner and not runner.is_running:
		runner.start()

	# ==========================================================================
	# INV-13: Rat Spawn Bounds & NavMesh
	# ==========================================================================
	print("\n--- Testing INV-13: Rat Spawn Bounds & NavMesh ---")
	var initial_rats = rats_container.get_children()
	_check(initial_rats.size() == 11, "INV-13: Exactly 11 initial rats spawned in RatsContainer", {
		"invariant": "INV-13",
		"severity": "MAJOR",
		"description": "Initial rat spawn count mismatch",
		"expected": "11 rats",
		"actual": "%d rats" % initial_rats.size()
	})

	var nav_region = main.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	var nav_map: RID = nav_region.get_navigation_map() if nav_region else main.get_world_3d().get_navigation_map()

	var all_in_bounds: bool = true
	var all_on_navmesh: bool = true
	var max_nav_dist: float = 0.0

	for rat in initial_rats:
		var pos = rat.global_position
		# Map bounds for Farmhouse: X in [-12, 12], Z in [-12, 12], Y in [-2, 8]
		if pos.x < -12.0 or pos.x > 12.0 or pos.z < -12.0 or pos.z > 12.0:
			all_in_bounds = false

		var closest = NavigationServer3D.map_get_closest_point(nav_map, pos)
		var dist = pos.distance_to(closest)
		if dist > max_nav_dist:
			max_nav_dist = dist
		if dist >= 1.0:
			all_on_navmesh = false

	_check(all_in_bounds, "INV-13: All 11 rats spawned inside farmhouse boundary")
	_check(all_on_navmesh, "INV-13: All rats within < 1.0m of valid NavMesh surface (max offset: %.2fm)" % max_nav_dist, {
		"invariant": "INV-13",
		"severity": "MAJOR",
		"description": "NavigationRegion3D navigation_mesh is unbaked (polygon count == 0); rats are not on a valid navmesh surface",
		"expected": "max distance to navmesh < 1.0m",
		"actual": "max distance = %.2fm (closest point is Vector3.ZERO due to unbaked mesh)" % max_nav_dist
	})

	# ==========================================================================
	# INV-14: Rat Pickup & Inventory Capacity
	# ==========================================================================
	print("\n--- Testing INV-14: Rat Pickup & Inventory Capacity ---")
	_check(player.rat_count == 0, "INV-14: Player initially holds 0 rats")
	var rat0 = initial_rats[0] as Rat
	var rat1 = initial_rats[1] as Rat
	var rat2 = initial_rats[2] as Rat
	var rat3 = initial_rats[3] as Rat

	var pickup0 = rat0.interact(player)
	_check(pickup0 and player.rat_count == 1 and rat0.is_caught, "INV-14: First rat picked up -> player.rat_count == 1 and rat.is_caught")

	var pickup1 = rat1.interact(player)
	var pickup2 = rat2.interact(player)
	_check(pickup1 and pickup2 and player.rat_count == 3, "INV-14: Second and third rats picked up -> player.rat_count == 3 (max capacity)")

	var pickup3 = rat3.interact(player)
	_check(not pickup3 and player.rat_count == 3 and not rat3.is_caught, "INV-14: Fourth rat pickup rejected when inventory full (capacity 3)")

	# ==========================================================================
	# INV-15: Altar Rat Burn & Count
	# ==========================================================================
	print("\n--- Testing INV-15: Altar Rat Burn & Count ---")
	var pre_burn_count = altar.burnt_count
	var pre_player_rats = player.rat_count
	var burn_res = altar.interact(player)

	_check(burn_res, "INV-15: Player successfully offered rat to Altar")
	_check(altar.burnt_count == pre_burn_count + 1, "INV-15: altar.burnt_count incremented to %d" % altar.burnt_count)
	_check(gm.burnt_rats == altar.burnt_count, "INV-15: game_manager.burnt_rats synchronized with altar (%d)" % gm.burnt_rats)
	_check(player.rat_count == pre_player_rats - 1, "INV-15: Player held rat consumed (%d -> %d)" % [pre_player_rats, player.rat_count])

	altar._process(0.1)
	var flame_active = altar._burn_effect_timer > 0.0 and altar.flame_particles and altar.flame_particles.visible
	_check(flame_active, "INV-15: Altar burn flame visual effect is active/visible")

	# ==========================================================================
	# INV-17: Locked Door & Key
	# ==========================================================================
	print("\n--- Testing INV-17: Locked Door & Key ---")
	var doors = main.get_tree().get_nodes_in_group("Door")
	var cellar_door: FarmhouseDoor = null
	for d in doors:
		if d is FarmhouseDoor and d.is_locked and d.key_id == "basement_key":
			cellar_door = d
			break

	if cellar_door:
		var initial_locked = cellar_door.is_locked
		var open_without_key = cellar_door.interact(player)
		_check(not open_without_key and cellar_door.is_locked and not cellar_door.is_open,
			"INV-17: Locked door refuses to open without Key")

		player.add_key(cellar_door.key_id)
		_check(player.has_key(cellar_door.key_id), "INV-17: Player received key '%s'" % cellar_door.key_id)

		var open_with_key = cellar_door.interact(player)
		_check(open_with_key and not cellar_door.is_locked and cellar_door.is_open,
			"INV-17: Door unlocks and opens with Key")
		_check(not player.has_key(cellar_door.key_id),
			"INV-17: Key consumed upon unlocking door")

		# Toggle close and open again - should not lock again
		cellar_door.interact(player) # close
		var re_open = cellar_door.interact(player) # open
		_check(re_open and not cellar_door.is_locked and cellar_door.is_open,
			"INV-17: Unlocked door remains permanently unlocked without needing key again")
	else:
		_check(false, "INV-17: Locked cellar door found in scene", {
			"invariant": "INV-17",
			"severity": "MAJOR",
			"description": "No locked FarmhouseDoor with key_id 'basement_key' found in group Door",
			"expected": "At least 1 locked FarmhouseDoor with basement_key",
			"actual": "0 locked doors found"
		})

	# ==========================================================================
	# INV-18: Fuse & Electrical Power
	# ==========================================================================
	print("\n--- Testing INV-18: Fuse & Electrical Power ---")
	var fusebox = main.find_child("FuseBox", true, false)
	if fusebox == null:
		fusebox = main.find_child("fusebox", true, false)
	if fusebox == null:
		var interactables = main.get_tree().get_nodes_in_group("Interactable")
		for item in interactables:
			if "fuse" in item.name.to_lower():
				fusebox = item
				break

	_check(fusebox != null, "INV-18: FuseBox interactable node exists in farmhouse", {
		"invariant": "INV-18",
		"severity": "MAJOR",
		"description": "FuseBox node does not exist in main.tscn; hallway light is hardcoded ON at startup without circuit breaker logic",
		"expected": "FuseBox interactable node in scene connecting fuse item to hallway lights",
		"actual": "null (no fusebox node or script in repo)"
	})

	# ==========================================================================
	# INV-19: Molly Speed Scaling
	# ==========================================================================
	print("\n--- Testing INV-19: Molly Speed Scaling ---")
	var speed_task = BTGhostPursue.new()
	var speeds = speed_task.default_speeds
	var s0 = float(speeds[0])
	var s4 = float(speeds[clampi(4, 0, speeds.size() - 1)])
	var s8 = float(speeds[clampi(8, 0, speeds.size() - 1)])

	_check(s0 >= 1.0 and s0 <= 1.3, "INV-19: Base speed at 0 burnt rats (%.2f m/s in [1.0, 1.3])" % s0)
	_check(s4 > s0 and s4 >= 1.6 and s4 <= 2.0, "INV-19: Scaled speed at 4 burnt rats (%.2f m/s in (s0, 2.0])" % s4)
	_check(s8 > s4 and s8 <= 2.53, "INV-19: Max enrage speed at 8 burnt rats (%.2f m/s in (s4, 2.53])" % s8)
	_check(s0 < s4 and s4 < s8, "INV-19: Molly pursuit speed is strictly monotonically increasing with burnt_count")

	# ==========================================================================
	# Ghost AI in Real Game Scene (Sight, UV Frying, Hearing, Movement)
	# ==========================================================================
	print("\n--- Testing Ghost AI in Real Game Scene ---")
	var bb = runner.tree.blackboard

	# 1. Sight Detection (INV-02)
	ghost.global_position = Vector3(0, 0, 0)
	ghost.rotation = Vector3.ZERO # facing -Z
	player.global_position = Vector3(0, 0, -5) # 5m in front of ghost
	player.flashlight_on = false
	player.flashlight_uv = false

	_check(ghost.can_see_target(player, 75.0, 20.0), "Ghost sight frustum detects player in front at 5m")

	for i in range(2):
		runner.tick(0.1)

	var ability_idx = int(bb.get_var("AbilityIndex", 0))
	var player_to_chase = bb.get_var("PlayerToChase")
	_check(ability_idx == 202 and player_to_chase == player,
		"INV-02: Sight detection triggers AbilityIndex == 202 (Pursue) and assigns PlayerToChase within <= 2 ticks")

	# 2. UV Flashlight Slowdown (INV-04)
	player.flashlight_on = true
	player.flashlight_uv = true
	var cam = player.get_node_or_null("Head/Camera3D")
	var ghost_center = ghost.global_position + Vector3(0.0, 1.2, 0.0)
	if cam:
		cam.look_at(ghost_center, Vector3.UP)
	else:
		player.look_at(ghost_center, Vector3.UP)

	runner.tick(0.1)
	ghost._physics_process(0.1)

	var ability_int_data = int(bb.get_var("AbilityIntData", 0))
	var bb_speed = float(bb.get_var("Speed", 1.0))
	_check(ability_int_data == 666 and bb_speed <= 0.2 and ghost.current_speed <= 0.2,
		"INV-04: UV Flashlight causes AbilityIntData == 666 and slows Molly speed to 0.1 m/s (actual: %.2f)" % ghost.current_speed)

	# 3. Noise Detection (INV-03)
	player.flashlight_on = false
	player.flashlight_uv = false
	runner.tick(0.1) # Recover from UV branch

	ghost.global_position = Vector3(0, 0, 0)
	ghost.rotation = Vector3.ZERO # facing -Z
	player.global_position = Vector3(0, 0, 5) # behind ghost
	player.is_crouching = false
	player.is_sprinting = true
	player.is_walking = false

	var can_see_behind = ghost.can_see_target(player, 75.0, 20.0)
	var heard_noise = ghost.detect_player_noise(1.5, 15.0) != null
	_check(not can_see_behind and heard_noise, "Ghost cannot see player behind (out of FOV) but detects sprint noise")

	# Reset BB pursuit state to test pure sound trigger
	runner.stop()
	runner.start()
	bb.set_var("AbilityIndex", 0)
	bb.set_var("AbilityIntData", 0)
	bb.set_var("PlayerToChase", null)

	for i in range(2):
		runner.tick(0.1)

	var sound_ability_idx = int(bb.get_var("AbilityIndex", 0))
	var sound_target = bb.get_var("PlayerToChase")
	_check(sound_ability_idx == 202 and sound_target == player,
		"INV-03: Sound detection alone transitions AbilityIndex to 202 (Pursue) within <= 2 ticks")

	# 4. Ghost Movement & NavMesh Utilization
	var initial_ghost_pos = ghost.global_position
	for i in range(5):
		runner.tick(0.1)
		ghost._physics_process(0.1)

	var moved_dist = initial_ghost_pos.distance_to(ghost.global_position)
	_check(moved_dist > 0.05, "Ghost moves physically towards target during pursuit (displaced %.3fm)" % moved_dist)

	var nav_path_points = ghost.nav_agent.get_current_navigation_path().size() if ghost.nav_agent else 0
	_check(nav_path_points > 0, "Ghost navigation utilizes baked NavMesh path points (actual points: %d)" % nav_path_points, {
		"invariant": "INV-13_NAVMESH",
		"severity": "MAJOR",
		"description": "Ghost navigation agent path is empty; ghost movement relies entirely on direct fallback steering because NavMesh is unbaked",
		"expected": "nav_agent.get_current_navigation_path().size() > 0",
		"actual": "path size = %d" % nav_path_points
	})

	# ==========================================================================
	# INV-11: Defeat State on 3 Grabs
	# ==========================================================================
	print("\n--- Testing INV-11: Defeat State on 3 Grabs ---")
	gm.downed_count = 0
	gm.is_game_over = false
	gm.is_win = false

	ghost._grab_player(player)
	_check(gm.downed_count == 1 and not gm.is_game_over, "INV-11: Grab 1 increments downed_count to 1 and game continues", {
		"invariant": "INV-11",
		"severity": "MAJOR",
		"description": "Duplicate grab dispatch: ghost._grab_player emits signal and directly calls gm.on_player_grabbed, causing 1 grab to count twice",
		"expected": "downed_count == 1",
		"actual": "downed_count == %d" % gm.downed_count
	})

	# Test defeat trigger transition when reaching 3 grabs
	gm.downed_count = 2
	gm.is_game_over = false
	ghost._grab_player(player)
	_check(gm.is_game_over and not gm.is_win,
		"INV-11: Reaching 3 grabs triggers Defeat (is_game_over == true, is_win == false)")

	var loss_shown = hud.loss_panel and hud.loss_panel.visible
	_check(loss_shown, "INV-11: UIHUD loss_panel is visible on defeat")

	# ==========================================================================
	# INV-16: Win State on 9 Burnt Rats & Runner Stop
	# ==========================================================================
	print("\n--- Testing INV-16: Win State on 9 Burnt Rats & Runner Stop ---")
	# Reset game over flags for ritual completion test
	gm.is_game_over = false
	gm.is_win = false
	if hud.loss_panel:
		hud.loss_panel.visible = false

	# Burn rats until 9 total
	while altar.burnt_count < 9:
		player.rat_count = 1
		altar.interact(player)

	_check(altar.burnt_count == 9 and gm.burnt_rats == 9, "Altar reached ritual target of 9 burnt rats")
	_check(gm.is_game_over and gm.is_win, "INV-16: Ritual completion sets is_game_over == true and is_win == true")

	var win_shown = hud.win_panel and hud.win_panel.visible
	_check(win_shown, "INV-16: UIHUD win_panel is visible on victory")

	_check(not runner.is_running, "INV-16: Ghost BT runner is stopped on victory (is_running == false)", {
		"invariant": "INV-16",
		"severity": "MAJOR",
		"description": "Ghost BT runner is never stopped on victory (_trigger_victory does not call runner.stop() or ghost.stop_brain())",
		"expected": "runner.is_running == false",
		"actual": "runner.is_running == true"
	})

	# Cleanup main scene
	main.queue_free()
	for i in range(5):
		await process_frame
		await physics_frame

# ==============================================================================
# Scene Lifecycle & Memory Leak Test
# ==============================================================================
func _run_scene_lifecycle_leak_test() -> void:
	print("\n--- Testing Scene Lifecycle & Memory Leaks (2 Cycles) ---")

	var base_objects = Performance.get_monitor(Performance.OBJECT_COUNT)

	# Cycle 1
	var s1 = load("res://game/scenes/main.tscn").instantiate()
	root.add_child(s1)
	current_scene = s1
	for i in range(5):
		await process_frame
		await physics_frame
	s1.queue_free()
	for i in range(5):
		await process_frame
		await physics_frame
	var after_c1_objects = Performance.get_monitor(Performance.OBJECT_COUNT)

	# Cycle 2
	var s2 = load("res://game/scenes/main.tscn").instantiate()
	root.add_child(s2)
	current_scene = s2
	for i in range(5):
		await process_frame
		await physics_frame
	s2.queue_free()
	for i in range(5):
		await process_frame
		await physics_frame
	var after_c2_objects = Performance.get_monitor(Performance.OBJECT_COUNT)
	var orphan_nodes = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)

	var cycle_delta = after_c2_objects - after_c1_objects
	_check(cycle_delta < 300, "Scene object count delta between cycles is bounded (delta: %d)" % cycle_delta)

	_check(orphan_nodes == 0, "No orphan nodes leaked across scene instantiation/destruction cycles (orphans: %d)" % orphan_nodes, {
		"invariant": "LEAK_ORPHAN_NODES",
		"severity": "MINOR",
		"description": "Scene instantiation leaves stray orphan nodes unparented upon queue_free (farmhouse_builder and bt_runner leak unparented nodes)",
		"expected": "0 orphan nodes",
		"actual": "%d orphan nodes" % orphan_nodes
	})
