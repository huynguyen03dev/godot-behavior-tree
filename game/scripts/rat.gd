class_name Rat
extends Area3D

signal caught(player: Node)

@export var rat_id: int = 0
var is_caught: bool = false

var _wiggle_timer: float = 0.0
var _base_pos: Vector3 = Vector3.ZERO
var _move_dir: Vector3 = Vector3.FORWARD

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
	if is_caught:
		return

	_wiggle_timer += delta * 4.0
	# Subtle nervous scurry / sniffing twitch
	if mesh_root:
		mesh_root.position.x = sin(_wiggle_timer * 1.5) * 0.03
		mesh_root.position.z = cos(_wiggle_timer) * 0.03
		mesh_root.rotation.y += sin(_wiggle_timer * 2.0) * delta * 0.8

func get_interaction_text() -> String:
	return "Press [E] to catch Rat"

func interact(player: Node) -> bool:
	if is_caught:
		return false

	if player.has_method("add_rat"):
		if player.add_rat():
			is_caught = true
			emit_signal("caught", player)
			_play_squeak()
			queue_free()
			return true
	return false

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

func _play_squeak() -> void:
	if squeak_player and squeak_player.stream:
		squeak_player.play()
