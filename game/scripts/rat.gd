class_name Rat
extends Area3D

signal caught(player: Node)

@export var rat_id: int = 0
var is_caught: bool = false
var is_placed_on_pit: bool = false
var is_eating_hay: bool = false

var bt_runner: Variant = null
var is_using_bt: bool = false

var locomotion_state: String = "idle" # "idle", "flee", "wander"
var _flee_target_node: Node3D = null
var _flee_timer: float = 0.0
var _wander_target: Vector3 = Vector3.ZERO
var _wander_timer: float = 0.0

var _wiggle_timer: float = 0.0
var _base_pos: Vector3 = Vector3.ZERO

@onready var mesh_root: Node3D = $MeshRoot
@onready var squeak_player: AudioStreamPlayer3D = $AudioStreamPlayer3D

func _ready() -> void:
	add_to_group("Rat")
	add_to_group("Interactable")
	# Collision Layer 4 (Interactable, bit 8)
	collision_layer = 8
	collision_mask = 0
	_base_pos = global_position
	_wiggle_timer = randf() * TAU
	_setup_mesh()
	_setup_squeak_audio()
	_init_bt_or_fallback()

func _init_bt_or_fallback() -> void:
	if ResourceLoader.exists("res://game/scripts/bt/rat_bt.gd"):
		var rat_bt_script = load("res://game/scripts/bt/rat_bt.gd")
		if rat_bt_script and rat_bt_script.has_method("attach"):
			bt_runner = rat_bt_script.attach(self)
			if bt_runner != null:
				add_child(bt_runner)
				bt_runner.start()
				is_using_bt = true
				print("[Rat] Attached RatBT runner successfully.")
				return
	is_using_bt = false

func _setup_mesh() -> void:
	# Check if Blender model rat.glb exists, else use procedural low-poly rat
	if ResourceLoader.exists("res://game/assets/models/rat.glb"):
		var rat_scene = load("res://game/assets/models/rat.glb")
		if rat_scene:
			var inst = rat_scene.instantiate()
			mesh_root.add_child(inst)
			return

	# TODO: Replace primitive rat with rat.glb once produced by Blender agent
	# Procedural rat representation: small dark capsule + tail
	var body_mesh := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.09
	cap.height = 0.28
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.2, 0.18) # Dark brown rodent fur
	mat.roughness = 0.9
	body_mesh.mesh = cap
	body_mesh.material_override = mat
	body_mesh.rotation.x = deg_to_rad(90.0)
	mesh_root.add_child(body_mesh)

	# Glowing red beady eyes
	var eyes := OmniLight3D.new()
	eyes.light_color = Color(1.0, 0.1, 0.05)
	eyes.light_energy = 0.3
	eyes.omni_range = 0.8
	eyes.position = Vector3(0.0, 0.06, -0.12)
	mesh_root.add_child(eyes)

func _process(delta: float) -> void:
	if is_caught or is_placed_on_pit:
		if mesh_root:
			mesh_root.position = Vector3.ZERO
		return

	_wiggle_timer += delta * 6.0
	# Subtle nervous scurry / sniffing twitch
	if mesh_root:
		mesh_root.position.x = sin(_wiggle_timer * 1.5) * 0.03
		mesh_root.position.z = cos(_wiggle_timer) * 0.03
		mesh_root.rotation.y += sin(_wiggle_timer * 2.0) * delta * 0.8

func _physics_process(delta: float) -> void:
	if is_caught or is_placed_on_pit:
		return

	# Active flee impulse (e.g. immediately upon being dropped by player)
	if locomotion_state == "flee" and _flee_timer > 0.0:
		_flee_timer -= delta
		if _flee_timer <= 0.0:
			locomotion_state = "idle"
		var flee_from_pos: Vector3
		if _flee_target_node and is_instance_valid(_flee_target_node):
			flee_from_pos = _flee_target_node.global_position
		else:
			flee_from_pos = global_position - global_transform.basis.z
		var flee_dir := (global_position - flee_from_pos)
		flee_dir.y = 0.0
		if flee_dir.length_squared() < 0.001:
			flee_dir = Vector3.FORWARD
		else:
			flee_dir = flee_dir.normalized()
		
		var move_step := flee_dir * 3.5 * delta
		global_position += move_step
		
		var look_target := global_position + flee_dir
		if not is_nan(look_target.x) and not is_nan(look_target.z):
			look_at(Vector3(look_target.x, global_position.y, look_target.z), Vector3.UP)
		return

	if is_using_bt:
		# BT runner handles autonomous wander/eating behavior
		return

func get_interaction_text() -> String:
	if is_placed_on_pit:
		return ""
	return "Press [E] to catch Rat"

func interact(player: Node) -> bool:
	if is_caught or is_placed_on_pit:
		return false

	if player.has_method("add_rat"):
		if player.add_rat():
			is_caught = true
			emit_signal("caught", player)
			play_squeak()
			queue_free()
			return true
	return false

# --- Actor Contract for RatBT ---

func get_player() -> Node3D:
	return get_tree().get_first_node_in_group("Player") as Node3D

func set_locomotion_state(state: String) -> void:
	locomotion_state = state

func move_towards_point(target: Vector3, speed: float, delta: float = 0.0) -> void:
	if is_caught or is_placed_on_pit:
		return
	var dt: float = delta
	if dt <= 0.0:
		dt = get_physics_process_delta_time()
	if dt <= 0.0:
		dt = get_process_delta_time()
	if dt <= 0.0:
		dt = 1.0 / 60.0
	var dir := (target - global_position)
	dir.y = 0.0
	if dir.length_squared() > 0.01:
		var step := dir.normalized() * speed * dt
		global_position += step
		var look_target := global_position + dir.normalized()
		if is_inside_tree():
			look_at(Vector3(look_target.x, global_position.y, look_target.z), Vector3.UP)

func get_random_navmesh_point(min_radius: float = 4.0, max_radius: float = 12.0) -> Vector3:
	var angle := randf() * TAU
	var dist := randf_range(min_radius, max_radius)
	var offset := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	var candidate := global_position + offset
	var nav_map := get_world_3d().get_navigation_map() if is_inside_tree() else RID()
	if nav_map.is_valid() and NavigationServer3D.map_get_iteration_id(nav_map) > 0:
		var closest := NavigationServer3D.map_get_closest_point(nav_map, candidate)
		if closest != Vector3.ZERO and candidate.distance_to(closest) < 4.0:
			return closest
	return candidate

func flee_from(target_node: Node3D, speed: float = 3.5, delta: float = 0.0) -> Vector3:
	if is_caught or is_placed_on_pit:
		return global_position
	_flee_target_node = target_node
	locomotion_state = "flee"
	_flee_timer = 5.0
	play_squeak()
	var flee_from_pos := target_node.global_position if target_node else (global_position - global_transform.basis.z)
	var flee_dir := (global_position - flee_from_pos)
	flee_dir.y = 0.0
	if flee_dir.length_squared() < 0.001:
		flee_dir = Vector3.FORWARD
	var dest := global_position + flee_dir.normalized() * 5.0
	var dt: float = delta
	if dt <= 0.0:
		dt = get_physics_process_delta_time()
	if dt <= 0.0:
		dt = get_process_delta_time()
	if dt <= 0.0:
		dt = 1.0 / 60.0
	move_towards_point(dest, speed, dt)
	return dest

func get_shared_bool(key: String) -> bool:
	match key.to_lower():
		"eating", "eating_hay":
			return is_eating_hay
		"fleeing", "flee":
			return locomotion_state == "flee"
		"caught":
			return is_caught
		"placed", "is_placed_on_pit":
			return is_placed_on_pit
	return false

func play_squeak() -> void:
	if squeak_player and squeak_player.stream:
		squeak_player.play()

func _setup_squeak_audio() -> void:
	var sample_rate: int = 22050
	var duration: float = 0.12
	var num_samples: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples)
	for i in range(num_samples):
		var t := float(i) / float(num_samples)
		var freq := 2400.0 + sin(t * 20.0) * 800.0
		var env := exp(-t * 12.0)
		var s := sin(t * duration * freq * TAU) * env * 0.3
		var val := int(clamp(s * 127.0, -128.0, 127.0))
		if val < 0: val += 256
		data[i] = val
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	if squeak_player:
		squeak_player.stream = stream
