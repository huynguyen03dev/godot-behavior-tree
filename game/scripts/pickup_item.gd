class_name PickupItem
extends Area3D

enum ItemType { KEY, FUSE, BATTERY, FIRST_AID, FOOD, GASOLINE }

@export var item_type: ItemType = ItemType.KEY
@export var key_id: String = ""
@export var item_name: String = "Item"

@onready var mesh_root: Node3D = $MeshRoot

var _bob_timer: float = 0.0

func _ready() -> void:
	add_to_group("Pickup")
	add_to_group("Interactable")
	collision_layer = 8 # Layer 4 (Interactable)
	collision_mask = 0
	_setup_visual()

func _setup_visual() -> void:
	var glb_path := ""
	match item_type:
		ItemType.KEY:
			glb_path = "res://game/assets/models/key.glb"
		ItemType.FUSE:
			glb_path = "res://game/assets/models/fuse.glb"
		ItemType.BATTERY:
			glb_path = "res://game/assets/models/battery.glb"
		ItemType.FIRST_AID:
			glb_path = "res://game/assets/models/first_aid.glb"
		ItemType.FOOD:
			glb_path = "res://game/assets/models/food.glb"
		ItemType.GASOLINE:
			glb_path = "res://game/assets/models/gasoline.glb"

	if glb_path != "" and ResourceLoader.exists(glb_path):
		var sc = load(glb_path)
		if sc:
			mesh_root.add_child(sc.instantiate())
			return

	# Procedural primitive representations for sub-items (fallback)
	var mesh_inst := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	match item_type:
		ItemType.KEY:
			var b := BoxMesh.new()
			b.size = Vector3(0.08, 0.22, 0.04)
			mat.albedo_color = Color(0.85, 0.7, 0.2) # Brass
			mat.metallic = 0.8
			mesh_inst.mesh = b
		ItemType.FUSE:
			var c := CylinderMesh.new()
			c.top_radius = 0.05
			c.bottom_radius = 0.05
			c.height = 0.18
			mat.albedo_color = Color(0.9, 0.9, 0.9)
			mat.metallic = 0.5
			mesh_inst.mesh = c
		ItemType.BATTERY:
			var c := CylinderMesh.new()
			c.top_radius = 0.06
			c.bottom_radius = 0.06
			c.height = 0.16
			mat.albedo_color = Color(0.2, 0.5, 0.9) # Blue battery
			mesh_inst.mesh = c
		ItemType.FIRST_AID:
			var b := BoxMesh.new()
			b.size = Vector3(0.25, 0.18, 0.12)
			mat.albedo_color = Color(0.9, 0.1, 0.1) # Red medkit
			mesh_inst.mesh = b
		ItemType.FOOD:
			var b := BoxMesh.new()
			b.size = Vector3(0.15, 0.1, 0.15)
			mat.albedo_color = Color(0.6, 0.4, 0.2) # Brown ration
			mesh_inst.mesh = b
		ItemType.GASOLINE:
			# TODO: Replace primitive gasoline can with gasoline.glb once produced by Blender agent
			var b := BoxMesh.new()
			b.size = Vector3(0.22, 0.30, 0.14)
			mat.albedo_color = Color(0.85, 0.12, 0.12) # Bright red fuel can
			mat.roughness = 0.5
			mesh_inst.mesh = b
			# Jerrycan spout
			var spout := MeshInstance3D.new()
			var spout_mesh := CylinderMesh.new()
			spout_mesh.top_radius = 0.025
			spout_mesh.bottom_radius = 0.025
			spout_mesh.height = 0.08
			var spout_mat := StandardMaterial3D.new()
			spout_mat.albedo_color = Color(0.1, 0.1, 0.1)
			spout.mesh = spout_mesh
			spout.material_override = spout_mat
			spout.position = Vector3(0.06, 0.18, 0.0)
			spout.rotation.z = deg_to_rad(-20.0)
			mesh_inst.add_child(spout)

	mesh_inst.material_override = mat
	mesh_root.add_child(mesh_inst)

func _process(delta: float) -> void:
	_bob_timer += delta * 2.0
	if mesh_root:
		mesh_root.position.y = sin(_bob_timer) * 0.04
		mesh_root.rotate_y(delta * 1.5)

func get_interaction_text() -> String:
	return "Press [E] to take " + item_name

func interact(player: Node) -> bool:
	match item_type:
		ItemType.KEY:
			if player.has_method("add_key"):
				player.add_key(key_id, item_name)
				queue_free()
				return true
		ItemType.FUSE:
			if player.has_method("add_fuse"):
				player.add_fuse()
				queue_free()
				return true
		ItemType.BATTERY:
			if player.has_method("recharge_battery"):
				player.recharge_battery()
				queue_free()
				return true
		ItemType.FIRST_AID:
			var gm = get_tree().current_scene.get_node_or_null("GameManager")
			if gm and gm.has_method("heal_player"):
				gm.heal_player()
				queue_free()
				return true
		ItemType.FOOD:
			if player.has_method("restore_stamina"):
				player.restore_stamina()
				queue_free()
				return true
		ItemType.GASOLINE:
			if player.has_method("add_gasoline"):
				player.add_gasoline()
				queue_free()
				return true
	return false
