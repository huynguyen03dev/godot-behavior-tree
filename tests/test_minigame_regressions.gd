extends SceneTree

const GAME_SCENE := preload("res://demo/minigame/night_courier.tscn")
const EXIT := Rect2(1000, 565, 100, 76)

var failures := 0
var checks := 0

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
	else:
		print("PASS: " + description)

func _new_game() -> Node:
	var game: Node = GAME_SCENE.instantiate()
	root.add_child.call_deferred(game)
	await process_frame
	game.set_physics_process(false)
	for guard in game.guards:
		guard.runner.set_process(false)
	var enter := InputEventKey.new()
	enter.pressed = true
	enter.keycode = KEY_ENTER
	game._unhandled_key_input(enter)
	_check(game.phase == "playing", "actual Enter handler starts gameplay")
	return game

func _dispose(game: Node) -> void:
	game.free()
	await process_frame

func _initialize() -> void:
	await _test_lethal_contact()
	await _test_nonlethal_contact()
	await _test_ordinary_win()
	print("Minigame regression tests: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_lethal_contact() -> void:
	var game = await _new_game()
	game.hp = 1
	game.parcels = 7
	game.player = EXIT.get_center()
	game.guards[0].position = game.player
	game.guards[1].position = Vector2(110, 110)
	var second_ticks: int = game.guards[1].runner.ticks
	game._physics_process(1.0 / 60.0)
	_check(game.phase == "lost", "lethal guard contact remains lost rather than becoming won")
	var event_phases: Array = []
	for event in game.phase_events: event_phases.append(event.to)
	_check(not event_phases.has("won"), "lethal frame emits no won phase event")
	_check(game.guards[1].runner.ticks == second_ticks, "guards after lethal contact are not ticked")
	_check(game.guards.all(func(guard): return not guard.runner.is_running), "all runners stop after lethal contact")
	var elapsed: float = game.elapsed
	var hp: int = game.hp
	var player: Vector2 = game.player
	var positions: Array = game.guards.map(func(guard): return guard.position)
	game._physics_process(1.0 / 60.0)
	_check(game.elapsed == elapsed and game.hp == hp and game.player == player, "terminal physics step leaves gameplay state unchanged")
	_check(game.guards.map(func(guard): return guard.position) == positions, "terminal physics step leaves guard positions unchanged")
	await _dispose(game)

func _test_nonlethal_contact() -> void:
	var game = await _new_game()
	game.hp = 2
	game.parcels = 7
	game.player = EXIT.get_center()
	game.guards[0].position = game.player
	game.guards[1].position = Vector2(110, 110)
	game._physics_process(1.0 / 60.0)
	_check(game.phase == "won" and game.hp == 1, "nonlethal exit contact wins and applies one damage")
	_check(game.guards.all(func(guard): return not guard.runner.is_running), "all runners stop after nonlethal win")
	await _dispose(game)

func _test_ordinary_win() -> void:
	var game = await _new_game()
	game.parcels = 7
	game.player = EXIT.get_center()
	for guard in game.guards: guard.position = Vector2(110, 110)
	game._physics_process(1.0 / 60.0)
	_check(game.phase == "won" and game.hp == 3, "ordinary exit win preserves health")
	_check(game.guards.all(func(guard): return not guard.runner.is_running), "all runners stop after ordinary win")
	await _dispose(game)
