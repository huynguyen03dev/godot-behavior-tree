class_name GameManager
extends Node3D

signal game_ended(is_win: bool)

@export var max_grabs: int = 3
@export var target_rats: int = 9
@export var ghost_respawn_time: float = 30.0

var downed_count: int = 0
var burnt_rats: int = 0
var is_game_over: bool = false
var is_win: bool = false

var _ghost_dead: bool = false
var _ghost_respawn_timer: float = 0.0

@onready var player: PlayerController = $Player
@onready var ghost: GhostActor = $Ghost
@onready var altar: Altar = $Altar
@onready var sacrifice_pit: SacrificePit = $SacrificePit
@onready var hud: UIHUD = $UIHUD
@onready var nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var level_root: Node3D = $NavigationRegion3D/LevelRoot
@onready var rats_container: Node3D = $RatsContainer
@onready var trash_cans_container: Node3D = $TrashCansContainer
@onready var doors_container: Node3D = $DoorsContainer
@onready var pickups_container: Node3D = $PickupsContainer

var rat_scene: PackedScene = preload("res://game/scenes/rat.tscn")
var trash_can_scene: PackedScene = preload("res://game/scenes/trash_can.tscn")
var door_scene: PackedScene = preload("res://game/scenes/door.tscn")
var pickup_scene: PackedScene = preload("res://game/scenes/pickup_item.tscn")

func _ready() -> void:
	print("[GameManager] Initializing Devour: The Farmhouse (Molly)...")
	# 1. Build Farmhouse Architecture
	if level_root:
		FarmhouseBuilder.build_farmhouse(level_root)
	
	# 2. Populate Spawns
	_spawn_doors()
	_spawn_pickups()
	_spawn_trash_cans()
	_spawn_initial_rats()
	
	# 3. Connect signals
	_connect_signals()
	_update_initial_hud()
	
	print("[GameManager] Farmhouse initialized successfully.")

func _connect_signals() -> void:
	if player and hud:
		player.rat_count_changed.connect(func(c): hud.update_rat_inventory(c))
		player.gasoline_count_changed.connect(func(c): hud.update_gasoline(c))
		player.keys_changed.connect(func(k): hud.update_keys(k))
		player.stamina_changed.connect(func(c, m): hud.update_stamina(c, m))
		player.uv_battery_changed.connect(func(c, m): hud.update_uv_battery(c, m))
		player.flashlight_state_changed.connect(func(on, uv): hud.update_flashlight(on, uv))
		player.interaction_prompt_changed.connect(func(t): hud.set_prompt(t))

	if sacrifice_pit:
		sacrifice_pit.rat_burnt.connect(_on_rat_burnt)
		sacrifice_pit.ritual_complete.connect(_on_ritual_complete)
	elif altar:
		# Fallback if sacrifice_pit not present
		altar.rat_burnt.connect(_on_rat_burnt)
		altar.ritual_complete.connect(_on_ritual_complete)

	if ghost:
		ghost.ghost_banished.connect(_on_ghost_banished_signal)

func _update_initial_hud() -> void:
	if hud:
		hud.update_rats_burnt(0, target_rats)
		hud.update_rat_inventory(0)
		hud.update_gasoline(0)
		hud.update_keys([])
		hud.update_lives(0, max_grabs)
		hud.update_stamina(100.0, 100.0)
		hud.update_uv_battery(5.0, 5.0)
		hud.update_flashlight(true, false)

func _process(delta: float) -> void:
	if is_game_over:
		if Input.is_key_pressed(KEY_R):
			get_tree().reload_current_scene()
		return

	if Input.is_action_just_pressed("ui_cancel") or (Input.is_key_pressed(KEY_ESCAPE) and not Input.is_action_just_pressed("ui_cancel")):
		if hud:
			hud.toggle_pause()

	# Ghost respawn handling (30s cooldown after banish)
	if _ghost_dead and ghost and is_instance_valid(ghost):
		_ghost_respawn_timer -= delta
		if _ghost_respawn_timer <= 0.0:
			_ghost_dead = false
			var spawn_pos = Vector3(4.0, -2.9, 0.0) # Basement altar/pentagram
			ghost.respawn_at(spawn_pos)
			print("[GameManager] Molly has risen again from the dark basement!")

func on_player_grabbed(ghost_ref: GhostActor = null) -> void:
	if is_game_over:
		return

	downed_count += 1
	if hud:
		hud.flash_damage()
		hud.update_lives(downed_count, max_grabs)

	print("[GameManager] Molly grabbed player! Total grabs: %d/%d" % [downed_count, max_grabs])

	if downed_count >= max_grabs:
		_trigger_defeat()
	else:
		# Repel ghost to give player breathing room
		if ghost and is_instance_valid(ghost) and player and is_instance_valid(player):
			var repel_dir := (ghost.global_position - player.global_position).normalized()
			repel_dir.y = 0.0
			ghost.global_position += repel_dir * 8.0
			ghost.set_parameter("AbilityIndex", 0) # Reset to wander

func heal_player() -> void:
	if downed_count > 0:
		downed_count -= 1
		if hud:
			hud.update_lives(downed_count, max_grabs)
		print("[GameManager] Player healed! Remaining grabs: %d/%d" % [downed_count, max_grabs])

func _on_rat_burnt(new_count: int) -> void:
	burnt_rats = new_count
	if hud:
		hud.update_rats_burnt(new_count, target_rats)

	# Ghost motor speed scales up as rats are burned (1.0 -> 2.53 m/s)
	if ghost and is_instance_valid(ghost):
		var new_speed = 1.0 + float(new_count) * 0.17
		ghost.base_speed = new_speed
		ghost.set_motor_speed(new_speed)
		print("[GameManager] Rat sacrificed! Molly enrages: speed = %.2f m/s" % new_speed)

	if burnt_rats >= target_rats:
		_trigger_victory()

func _on_ritual_complete() -> void:
	if burnt_rats >= target_rats:
		_trigger_victory()

func _trigger_victory() -> void:
	is_game_over = true
	is_win = true
	print("[GameManager] VICTORY! 9 Rats sacrificed. Molly's curse is broken!")
	if ghost and is_instance_valid(ghost):
		ghost.on_ghost_banished()
		if ghost.has_method("stop_brain"):
			ghost.stop_brain()
	if player and is_instance_valid(player):
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
	if hud:
		hud.show_win_screen()
	emit_signal("game_ended", true)

func _exit_tree() -> void:
	if ghost and is_instance_valid(ghost):
		if ghost.ghost_banished.is_connected(_on_ghost_banished_signal):
			ghost.ghost_banished.disconnect(_on_ghost_banished_signal)
		if ghost.has_method("stop_brain"):
			ghost.stop_brain()
	if sacrifice_pit and is_instance_valid(sacrifice_pit):
		if sacrifice_pit.rat_burnt.is_connected(_on_rat_burnt):
			sacrifice_pit.rat_burnt.disconnect(_on_rat_burnt)
		if sacrifice_pit.ritual_complete.is_connected(_on_ritual_complete):
			sacrifice_pit.ritual_complete.disconnect(_on_ritual_complete)
	if altar and is_instance_valid(altar):
		if altar.rat_burnt.is_connected(_on_rat_burnt):
			altar.rat_burnt.disconnect(_on_rat_burnt)
		if altar.ritual_complete.is_connected(_on_ritual_complete):
			altar.ritual_complete.disconnect(_on_ritual_complete)

func _trigger_defeat() -> void:
	is_game_over = true
	is_win = false
	print("[GameManager] DEFEAT! Molly captured player 3 times.")
	if hud:
		hud.show_loss_screen()
	emit_signal("game_ended", false)

func _on_ghost_grabbed_player(p: Node) -> void:
	on_player_grabbed(ghost)

func _on_ghost_banished_signal() -> void:
	if not is_game_over:
		_ghost_dead = true
		_ghost_respawn_timer = ghost_respawn_time
		print("[GameManager] Ghost banished! Respawning in %.1f seconds..." % ghost_respawn_time)

# ==============================================================================
# SPAWNER HELPERS
# ==============================================================================

func _spawn_doors() -> void:
	if not doors_container:
		return
	# Front Porch Door
	_create_door(Vector3(0.0, 0.0, 6.0), 0.0, false, "", "Front Door")
	# Back Door leading to Backyard (Sacrifice Pit)
	_create_door(Vector3(0.0, 0.0, -10.0), 0.0, false, "", "Back Door")
	# Basement Cellar Door (Locked by Basement Key)
	_create_door(Vector3(4.0, 0.0, 0.0), 0.0, true, "basement_key", "Cellar Door")
	# Master Bedroom Door (Locked by Bedroom Key)
	_create_door(Vector3(-4.0, 0.0, -2.0), 0.0, true, "bedroom_key", "Master Bedroom")
	# 2nd Floor Attic Door
	_create_door(Vector3(-4.0, 3.0, -2.0), 0.0, false, "", "Attic Door")

func _create_door(pos: Vector3, rot_y: float, locked: bool, key_str: String, d_name: String) -> void:
	var d = door_scene.instantiate() as FarmhouseDoor
	d.position = pos
	d.rotation.y = rot_y
	d.is_locked = locked
	d.key_id = key_str
	d.door_name = d_name
	doors_container.add_child(d)

func _spawn_pickups() -> void:
	if not pickups_container:
		return
	# Keys
	_create_pickup(Vector3(-6.0, 0.2, 2.0), PickupItem.ItemType.KEY, "basement_key", "Basement Key")
	_create_pickup(Vector3(2.0, -2.8, -2.0), PickupItem.ItemType.KEY, "bedroom_key", "Master Bedroom Key")
	
	# Gasoline Canisters (for Sacrifice Pit ritual)
	_create_pickup(Vector3(-6.0, 0.2, -15.0), PickupItem.ItemType.GASOLINE, "", "Gasoline Can")
	_create_pickup(Vector3(6.0, 0.2, -19.0), PickupItem.ItemType.GASOLINE, "", "Gasoline Can")
	_create_pickup(Vector3(-2.0, -2.8, -1.0), PickupItem.ItemType.GASOLINE, "", "Gasoline Can")
	_create_pickup(Vector3(5.0, 0.2, -2.0), PickupItem.ItemType.GASOLINE, "", "Gasoline Can")

	# Fuses (for electrical boxes / lighting)
	_create_pickup(Vector3(6.0, 0.2, -4.0), PickupItem.ItemType.FUSE, "", "Fuse")
	_create_pickup(Vector3(-2.0, 3.2, -4.0), PickupItem.ItemType.FUSE, "", "Fuse")
	
	# Batteries (for UV flashlight recharge)
	_create_pickup(Vector3(0.0, 0.2, -6.0), PickupItem.ItemType.BATTERY, "", "Flashlight Battery")
	_create_pickup(Vector3(-2.0, -2.8, 2.0), PickupItem.ItemType.BATTERY, "", "Flashlight Battery")
	
	# First Aid Kits (recovers 1 grab / sanity)
	_create_pickup(Vector3(-6.0, 0.2, -4.0), PickupItem.ItemType.FIRST_AID, "", "First Aid Kit")
	
	# Food (instantly restores stamina)
	_create_pickup(Vector3(4.0, 0.2, -2.0), PickupItem.ItemType.FOOD, "", "Canned Beans")
	_create_pickup(Vector3(2.0, 3.2, 0.0), PickupItem.ItemType.FOOD, "", "Dried Rations")

func _create_pickup(pos: Vector3, type: PickupItem.ItemType, key_id: String, item_name: String) -> void:
	var p = pickup_scene.instantiate() as PickupItem
	p.position = pos
	p.item_type = type
	p.key_id = key_id
	p.item_name = item_name
	pickups_container.add_child(p)

func _spawn_trash_cans() -> void:
	if not trash_cans_container:
		return
	var positions = [
		Vector3(6.0, -3.0, 2.0),
		Vector3(-2.0, -3.0, -2.0),
		Vector3(4.0, -3.0, -2.0),
		Vector3(-6.0, 0.0, 4.0),
		Vector3(6.0, 0.0, 4.0),
	]
	for p in positions:
		var tc = trash_can_scene.instantiate() as TrashCan
		tc.position = p
		trash_cans_container.add_child(tc)

func _spawn_initial_rats() -> void:
	if not rats_container:
		return
	# 11 initial rats scattered across Basement, Ground Floor, and 2nd Floor
	var rat_spawns = [
		# Basement (4 rats)
		Vector3(0.0, -2.6, 0.0),
		Vector3(4.0, -2.6, 2.0),
		Vector3(-2.0, -2.6, 0.0),
		Vector3(6.0, -2.6, -2.0),
		# Ground Floor (4 rats)
		Vector3(-4.0, 0.4, 0.88),
		Vector3(4.0, 0.4, -1.5),
		Vector3(-6.0, 0.4, -4.0),
		Vector3(2.0, 0.4, 4.0),
		# Second Floor (3 rats)
		Vector3(-4.0, 3.4, 0.22),
		Vector3(0.0, 3.4, -4.0),
		Vector3(-2.0, 3.4, -2.0)
	]
	
	var nav_map = nav_region.get_navigation_map() if nav_region else get_world_3d().get_navigation_map()
	for i in range(rat_spawns.size()):
		var pos = rat_spawns[i]
		if nav_map.is_valid() and NavigationServer3D.map_get_iteration_id(nav_map) > 0:
			var closest = NavigationServer3D.map_get_closest_point(nav_map, pos)
			if closest != Vector3.ZERO and pos.distance_to(closest) < 2.0:
				pos = closest
		var r = rat_scene.instantiate() as Rat
		r.position = pos
		r.rat_id = i + 1
		rats_container.add_child(r)
