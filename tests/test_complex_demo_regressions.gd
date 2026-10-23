extends SceneTree
## Regression tests for complex behavior-tree demo scenes.
##
## Validates that the promoted complex demo scenes (Boss AI, Squad AI, Guard Stealth)
## run deterministically headless and uphold the behavioral milestones verified in e2e:
## - Boss AI: 3-phase transitions, Cooldown attacks, LOWER_PRIORITY dodge preemption, SELF aborts.
## - Squad AI: 4 runners, shared blackboard, atomic role claims, mutex invariants, dynamic rebalance.
## - Guard Stealth AI: 90° FOV perception cone, monotonic memory decay, TimeLimit search, patrol give-up.

const BOSS_SCENE := preload("res://demo/complex/boss_demo.tscn")
const SQUAD_SCENE := preload("res://demo/complex/squad_demo.tscn")
const GUARD_SCENE := preload("res://demo/complex/guard_stealth_demo.tscn")
const HUB_SCENE := preload("res://demo/complex/complex_demo.tscn")

var failures := 0
var checks := 0

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
	else:
		print("PASS: " + description)

func _initialize() -> void:
	print("==================================================")
	print(" Running Complex Demo Regression Test Suite")
	print("==================================================")

	await _test_boss_ai()
	await _test_squad_ai()
	await _test_guard_stealth_ai()
	await _test_hub_scene()

	print("==================================================")
	print("Complex demo regression tests: %d checks, %d failures" % [checks, failures])
	print("==================================================")
	quit(1 if failures else 0)

# ---------------------------------------------------------------- Test 1: Boss AI

func _test_boss_ai() -> void:
	print("\n--- Testing Boss AI Demo ---")
	var boss: Node = BOSS_SCENE.instantiate()
	root.add_child(boss)
	await process_frame
	boss.auto_tick = false

	_check(boss.runner != null, "boss: creates runner on start")
	_check(boss.runner != null and boss.runner.is_running, "boss: runner is running")
	_check(boss.get_hp() == 100.0, "boss: initial HP is 100")

	# SCENARIO 1: Phase 1 Combo Execution
	boss.tick_manual(0.1) # Tick 1: Combo step 1/3
	_check(boss.combo_starts == 1, "boss tick 1: combo should start")
	_check(boss.combo_updates == 1, "boss tick 1: combo has 1 update")

	boss.tick_manual(0.1) # Tick 2: Combo step 2/3
	_check(boss.combo_updates == 2, "boss tick 2: combo has 2 updates")
	_check(boss.combo_aborts == 0, "boss tick 2: no combo aborts yet")

	# SCENARIO 2: Preemption by Dodge (LOWER_PRIORITY on root selector)
	boss.trigger_danger()
	boss.tick_manual(0.1) # Tick 3: Dodge preempts Combo immediately
	_check(boss.combo_aborts == 1, "boss tick 3: combo MUST be aborted exactly once by dodge")
	_check(boss.combo_ends == 1, "boss tick 3: combo on_end called on abort")
	_check(boss.dodge_starts == 1, "boss tick 3: dodge started")
	_check(boss.dodge_updates == 1, "boss tick 3: dodge ran tick 1")

	boss.tick_manual(0.1) # Tick 4: Dodge step 2 (completes and clears danger)
	_check(boss.dodge_ends == 1, "boss tick 4: dodge finished cleanly")
	_check(boss.tree.blackboard.get_var("danger") == false, "boss tick 4: danger flag cleared by dodge")

	# Resumed Phase 1: fresh combo
	boss.tick_manual(0.1) # Tick 5
	_check(boss.combo_starts == 2, "boss tick 5: fresh combo started after dodge")
	_check(boss.combo_updates == 3, "boss tick 5: combo at step 1")

	boss.tick_manual(0.1) # Tick 6
	_check(boss.combo_updates == 4, "boss tick 6: combo at step 2")

	# SCENARIO 3: Phase 1 -> Phase 2 Transition Preemption (SELF abort on sequence)
	boss.set_hp(55.0) # Mid-combo damage drops HP to 55 (Phase 2 range: 30..70)
	boss.tick_manual(0.1) # Tick 7
	_check(boss.combo_aborts == 2, "boss tick 7: combo aborted cleanly on phase 1 -> 2 shift")
	_check(boss.ranged_starts == 1, "boss tick 7: phase 2 ranged attack started")
	_check(boss.ranged_updates == 1, "boss tick 7: phase 2 ranged attack updated")

	boss.tick_manual(0.1) # Tick 8: Ranged step 2/3
	_check(boss.ranged_updates == 2, "boss tick 8: ranged step 2")

	# SCENARIO 4: Phase 2 -> Phase 3 Transition Preemption (SELF abort on sequence)
	boss.set_hp(20.0) # Mid-ranged damage drops HP to 20 (Phase 3 range: < 30)
	boss.tick_manual(0.1) # Tick 9
	_check(boss.ranged_aborts == 1, "boss tick 9: ranged attack aborted cleanly on phase 2 -> 3 shift")
	_check(boss.aoe_starts == 1, "boss tick 9: phase 3 AoE attack started")
	_check(boss.aoe_updates == 1, "boss tick 9: phase 3 AoE attack updated")

	boss.tick_manual(0.1) # Tick 10: AoE step 2/4
	_check(boss.aoe_updates == 2, "boss tick 10: AoE step 2")

	# SCENARIO 5: Phase 3 -> Phase 1 Healing Preemption (LOWER_PRIORITY preemption)
	boss.set_hp(90.0) # Boss heals mid-AoE to 90 (Phase 1)
	boss.tick_manual(0.1) # Tick 11
	_check(boss.aoe_aborts == 1, "boss tick 11: AoE attack aborted cleanly when healed to phase 1")
	_check(boss.combo_starts == 3, "boss tick 11: returned to phase 1 combo")

	boss.free()
	await process_frame

# ---------------------------------------------------------------- Test 2: Squad AI

func _test_squad_ai() -> void:
	print("\n--- Testing Squad AI Demo ---")
	var squad: Node = SQUAD_SCENE.instantiate()
	root.add_child(squad)
	await process_frame
	squad.auto_tick = false

	_check(squad.agents.size() == 4, "squad: initialized with 4 agents")
	_check(squad.shared_bb != null, "squad: shared blackboard initialized")

	# TICK 1: Initial Role Claiming
	squad.tick_all(0.1)
	_check(squad.mutex_violations == 0, "squad tick 1: no mutex violations")
	_check(squad.agents[0].current_role == "Attacker", "squad tick 1: agent 0 claimed Attacker")
	_check(squad.agents[1].current_role == "Flanker", "squad tick 1: agent 1 claimed Flanker")
	_check(squad.agents[2].current_role == "Reserve", "squad tick 1: agent 2 in Reserve")
	_check(squad.agents[3].current_role == "Reserve", "squad tick 1: agent 3 in Reserve")

	# TICK 2: Attacker Shoots (ammo 2 -> 1)
	squad.tick_all(0.1)
	_check(squad.mutex_violations == 0, "squad tick 2: no mutex violations")
	_check(squad.agents[0].ammo == 1, "squad tick 2: agent 0 ammo decremented to 1")

	# TICK 3: Attacker Shoots (ammo 1 -> 0, depleting ammo)
	squad.tick_all(0.1)
	_check(squad.agents[0].ammo == 0, "squad tick 3: agent 0 ammo depleted to 0")

	# TICK 4: Role Rebalance After Ammo Depletion
	# A0 -> Reloader, A1 -> Attacker, A2 -> Flanker, A3 -> Reserve
	squad.tick_all(0.1)
	_check(squad.mutex_violations == 0, "squad tick 4: no mutex violations")
	_check(squad.agents[0].current_role == "Reloader", "squad tick 4: agent 0 transitioned to Reloader")
	_check(squad.agents[1].current_role == "Attacker", "squad tick 4: agent 1 promoted to Attacker")
	_check(squad.agents[2].current_role == "Flanker", "squad tick 4: agent 2 promoted to Flanker")
	_check(squad.agents[3].current_role == "Reserve", "squad tick 4: agent 3 remains in Reserve")

	# TICK 5: Mid-fight Agent 1 DIES in combat
	squad.kill_agent(1)
	_check(not squad.agents[1].is_alive, "squad tick 5 pre: agent 1 marked dead")
	_check(squad.agents[1].current_role == "Dead", "squad tick 5 pre: agent 1 role is Dead")

	squad.tick_all(0.1)
	_check(squad.mutex_violations == 0, "squad tick 5: no mutex violations")
	_check(squad.agents[2].current_role == "Attacker", "squad tick 5: agent 2 promoted to Attacker after agent 1 death")
	_check(squad.agents[3].current_role == "Flanker", "squad tick 5: agent 3 promoted to Flanker after agent 1 death")

	# TICK 6: Agent 0 finishes reload and returns to pool
	squad.tick_all(0.1)
	_check(squad.mutex_violations == 0, "squad tick 6: no mutex violations")
	_check(squad.agents[0].ammo == 5, "squad tick 6: agent 0 fully reloaded")
	_check(squad.agents[0].current_role == "Reserve", "squad tick 6: agent 0 joined Reserve")
	_check(squad.agents[2].current_role == "Attacker", "squad tick 6: agent 2 still Attacker")
	_check(squad.agents[3].current_role == "Flanker", "squad tick 6: agent 3 still Flanker")

	squad.free()
	await process_frame

# ---------------------------------------------------------------- Test 3: Guard Stealth AI

func _test_guard_stealth_ai() -> void:
	print("\n--- Testing Guard Stealth AI Demo ---")
	var guard_demo: Node = GUARD_SCENE.instantiate()
	root.add_child(guard_demo)
	await process_frame
	guard_demo.auto_tick = false

	_check(guard_demo.guard != null, "guard: actor initialized")
	_check(guard_demo.player != null, "guard: player initialized")
	_check(guard_demo.runner != null and guard_demo.runner.is_running, "guard: runner running")

	# SCENARIO 1: Guard Patrolling (Player out of sight at (200, 200))
	for t in range(1, 4):
		guard_demo.tick_manual(0.1)
	_check(guard_demo.guard.alert_level == "Patrol", "guard ticks 1-3: guard is patrolling")

	# SCENARIO 2: Player enters FOV (Distance 50, directly ahead)
	guard_demo.set_player_pos(Vector2(50, 0))
	guard_demo.set_player_hidden(false)
	guard_demo.tick_manual(0.1) # Tick 4
	_check(guard_demo.guard.alert_level == "Chase", "guard tick 4: escalated to Chase")
	_check(guard_demo.tree.blackboard.get_var("has_memory") == true, "guard tick 4: perception memory formed")
	_check(guard_demo.tree.blackboard.get_var("last_seen_pos") == Vector2(50, 0), "guard tick 4: last seen position recorded")

	# Tick 5: Continuing chase
	guard_demo.tick_manual(0.1)
	_check(guard_demo.guard.alert_level == "Chase", "guard tick 5: still chasing")

	# SCENARIO 3: Player hides behind cover
	guard_demo.set_player_hidden(true)
	guard_demo.tick_manual(0.1) # Tick 6
	_check(guard_demo.guard.alert_level == "Curious", "guard tick 6: lost sight -> Curious (investigating last seen)")

	# Tick 7: Guard reaches last-seen point, begins Search sweep
	guard_demo.set_guard_pos(Vector2(49, 0))
	guard_demo.tick_manual(0.1)
	_check(guard_demo.guard.alert_level == "Search", "guard tick 7: reached point -> Search sweep")
	_check(guard_demo.guard.facing == Vector2(-1, 0), "guard tick 7: looking left")

	# Tick 8: Second sweep step
	guard_demo.tick_manual(0.1)
	_check(guard_demo.guard.alert_level == "Search", "guard tick 8: still searching")
	_check(guard_demo.guard.facing == Vector2(1, 0), "guard tick 8: looking right")

	# Tick 9: Search completes, memory cleared, gives up
	guard_demo.tick_manual(0.1)
	_check(guard_demo.tree.blackboard.get_var("has_memory") == false, "guard tick 9: memory cleared after sweep")

	# Tick 10: Patrol resumes
	guard_demo.tick_manual(0.1)
	_check(guard_demo.guard.alert_level == "Patrol", "guard tick 10: returned to Patrol after search completed")

	# SCENARIO 4: Memory decay over simulated time
	guard_demo.set_player_pos(Vector2(20, 0))
	guard_demo.set_player_hidden(false)
	guard_demo.tick_manual(0.1) # Tick 11: Spotted again
	_check(guard_demo.guard.alert_level == "Chase", "guard tick 11: spotted again -> Chase")

	guard_demo.set_player_hidden(true)
	guard_demo.tick_manual(0.1) # Tick 12: Lost sight
	_check(guard_demo.guard.alert_level == "Curious", "guard tick 12: lost sight -> Curious")

	# Simulated time passes past memory duration (3.5s elapsed)
	guard_demo.tick_manual(3.5) # Tick 13
	_check(guard_demo.tree.blackboard.get_var("has_memory") == false, "guard tick 13: memory decayed after 3.5s elapsed")

	guard_demo.tick_manual(0.1) # Tick 14
	_check(guard_demo.guard.alert_level == "Patrol", "guard tick 14: returned to Patrol via memory decay")

	guard_demo.free()
	await process_frame

# ---------------------------------------------------------------- Test 4: Hub Scene

func _test_hub_scene() -> void:
	print("\n--- Testing Hub Scene ---")
	var hub: Node = HUB_SCENE.instantiate()
	root.add_child(hub)
	await process_frame
	_check(hub != null, "hub: scene instantiates cleanly")
	_check(hub.has_method("open_boss_demo"), "hub: provides open_boss_demo navigation")
	_check(hub.has_method("open_squad_demo"), "hub: provides open_squad_demo navigation")
	_check(hub.has_method("open_guard_demo"), "hub: provides open_guard_demo navigation")
	hub.free()
	await process_frame
