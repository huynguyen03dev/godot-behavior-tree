class_name TrashCan
extends StaticBody3D

@export var rats_inside: int = 1
var is_searched: bool = false

@onready var mesh_root: Node3D = $MeshRoot
@onready var spawn_point: Marker3D = $SpawnPoint

func _ready() -> void:
	add_to_group("TrashCan")
	add_to_group("Interactable")
	# Collision Layer 1 (World) | Layer 4 (Interactable, bit 8)
	collision_layer = 1 | 8
	collision_mask = 0
	_setup_mesh()

func _setup_mesh() -> void:
	if ResourceLoader.exists("res://game/assets/models/trash_can.glb"):
		var tc_scene = load("res://game/assets/models/trash_can.glb")
		if tc_scene:
			var inst = tc_scene.instantiate()
			mesh_root.add_child(inst)
			return

	# TODO: Replace primitive trash can with trash_can.glb once produced by Blender agent
	# Procedural metallic galvanized trash can
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.38
	cyl.bottom_radius = 0.34
	cyl.height = 0.85
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.38, 0.4) # Galvanized tin
	mat.metallic = 0.7
	mat.roughness = 0.4
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = cyl
	mesh_inst.material_override = mat
	mesh_inst.position.y = 0.425
	mesh_root.add_child(mesh_inst)

func get_interaction_text() -> String:
	if is_searched:
		return "Trash can (empty)"
	return "Press [E] to search Trash Can"

func interact(player: Node) -> bool:
	if is_searched:
		return false

	is_searched = true
	if rats_inside > 0:
		# Rustle effect & spawn rat or give directly to player
		if player.has_method("add_rat") and player.add_rat():
			rats_inside -= 1
			print("[TrashCan] Player caught a rat hiding inside!")
			return true
		else:
			# If player's bag is full, spawn rat into world
			_spawn_rat_to_world()
			return true
	return false

func _spawn_rat_to_world() -> void:
	var rat_scene = load("res://game/scenes/rat.tscn")
	if rat_scene:
		var r = rat_scene.instantiate()
		var spawn_pos = global_position + Vector3(0.0, 0.2, 0.6)
		get_tree().current_scene.add_child(r)
		r.global_position = spawn_pos
