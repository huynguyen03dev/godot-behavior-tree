class_name FarmhouseBuilder
extends RefCounted

## Programmatically constructs the 2-story + basement Farmhouse layout
## using 4x4m grid modules (floor_module.glb, wall_module.glb, ceiling_module.glb)
## and attaches static collision bodies + creates NavMesh geometry.

const GRID_SIZE = 4.0
const WALL_HEIGHT = 3.0

var floor_scene: PackedScene
var wall_scene: PackedScene
var ceiling_scene: PackedScene
var crate_scene: PackedScene
var barrel_scene: PackedScene
var rug_scene: PackedScene
var painting_scene: PackedScene

func _init() -> void:
	if ResourceLoader.exists("res://game/assets/models/floor_module.glb"):
		floor_scene = load("res://game/assets/models/floor_module.glb")
	if ResourceLoader.exists("res://game/assets/models/wall_module.glb"):
		wall_scene = load("res://game/assets/models/wall_module.glb")
	if ResourceLoader.exists("res://game/assets/models/ceiling_module.glb"):
		ceiling_scene = load("res://game/assets/models/ceiling_module.glb")
	if ResourceLoader.exists("res://game/assets/models/crate.glb"):
		crate_scene = load("res://game/assets/models/crate.glb")
	if ResourceLoader.exists("res://game/assets/models/barrel.glb"):
		barrel_scene = load("res://game/assets/models/barrel.glb")
	if ResourceLoader.exists("res://game/assets/models/rug.glb"):
		rug_scene = load("res://game/assets/models/rug.glb")
	if ResourceLoader.exists("res://game/assets/models/painting.glb"):
		painting_scene = load("res://game/assets/models/painting.glb")

static func build_farmhouse(parent: Node3D) -> void:
	var builder = FarmhouseBuilder.new()
	builder._construct(parent)

func _construct(root: Node3D) -> void:
	var house = Node3D.new()
	house.name = "HouseGeometry"
	root.add_child(house)
	
	# 1. Basement: Y = -3.0 (4x3 cells, X in [-1, 2], Z in [-2, 1])
	_build_floor_level(house, "Basement", -3.0, -1, 2, -2, 1)
	
	# 2. Ground Floor: Y = 0.0 (5x4 cells, X in [-2, 2], Z in [-2, 1])
	_build_floor_level(house, "GroundFloor", 0.0, -2, 2, -2, 1)
	
	# 3. Second Floor: Y = 3.0 (5x4 cells, X in [-2, 2], Z in [-2, 1])
	# Full matching footprint ensures roof & upper rooms completely seal the house
	_build_floor_level(house, "SecondFloor", 3.0, -2, 2, -2, 1)
	
	# 4. Realistic 12-Step Wooden Staircases with side railings and under-stair cladding:
	# (a) Stairs to Second Floor: from ( -4.0, 0.0, 0.0 ) rising North to ( -4.0, 3.0, -3.36 )
	_build_stepped_stairs(house, "StairsSecondFloor", Vector3(-4.0, 0.0, 0.0), true, 3.0, 1.1)
	
	# (b) Stairs to Basement: from ( 4.0, 0.0, 0.0 ) descending North to ( 4.0, -3.0, -3.36 )
	_build_stepped_stairs(house, "StairsBasement", Vector3(4.0, 0.0, 0.0), false, 3.0, 1.1)
	
	# 5. Interior Walls & Props
	_build_interior_features(house)

func _build_floor_level(parent: Node3D, level_name: String, y_pos: float, min_x: int, max_x: int, min_z: int, max_z: int) -> void:
	var level = Node3D.new()
	level.name = level_name
	level.position.y = y_pos
	parent.add_child(level)
	
	# 1. Floors & Ceilings
	var seen_ceilings = {}
	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
			var pos = Vector3(x * GRID_SIZE, 0, z * GRID_SIZE)
			
			# Opening rules:
			# - Ground Floor: basement stairs shaft at (x=1, z=-1) opens down.
			#   Stairwell to 2nd floor spans x=-1, z in [-1, 0]; standard 4x4 ceiling tile
			#   is skipped and replaced with exact tailored infill slabs around the 1.3x3.0m opening.
			# - Second Floor: standard 4x4 floor tiles skipped at x=-1, z in [-1, 0]
			#   and replaced with matching walkable floor slabs and parapet walls.
			# - Ceilings: Basement and SecondFloor have full ceilings everywhere.
			var skip_floor = false
			var skip_ceiling = false
			
			if level_name == "GroundFloor":
				if x == 1 and z == -1:
					skip_floor = true # opening down into basement stairwell
				if x == -1 and (z == -1 or z == 0):
					skip_ceiling = true # custom stairwell opening footprint
			elif level_name == "SecondFloor":
				if x == -1 and (z == -1 or z == 0):
					skip_floor = true # custom stairwell floor opening footprint
			elif level_name == "Basement":
				pass
			
			if not skip_floor:
				_place_tile(level, pos, floor_scene, Color(0.25, 0.18, 0.12), Vector3(GRID_SIZE, 0.2, GRID_SIZE), true)
			
			if not skip_ceiling:
				var ceil_pos = pos + Vector3(0, WALL_HEIGHT, 0)
				_place_tile(level, ceil_pos, ceiling_scene, Color(0.2, 0.15, 0.1), Vector3(GRID_SIZE, 0.2, GRID_SIZE), false)
				_place_ceiling_backer(level, pos + Vector3(0, WALL_HEIGHT + 0.05, 0))
				var grid_x_ok = is_zero_approx(fmod(abs(pos.x), GRID_SIZE))
				var grid_z_ok = is_zero_approx(fmod(abs(pos.z), GRID_SIZE))
				var ceil_key = Vector2(pos.x, pos.z)
				if seen_ceilings.has(ceil_key):
					push_error("[CeilingAudit] DUPLICATE ceiling at %s on %s" % [ceil_key, level_name])
				seen_ceilings[ceil_key] = true
				print("[CeilingAudit] %s ceiling tile: (%4.1f, %4.1f, %4.1f) | grid_aligned: %s" % [
					level_name, ceil_pos.x, ceil_pos.y, ceil_pos.z, (grid_x_ok and grid_z_ok)
				])
	
	# Build custom infill slabs around the stairwell opening (X[-4.65, -3.35], Z[-3.36, -0.36])
	if level_name == "GroundFloor":
		_build_stairwell_ceiling(level)
		_build_stairwell_casing(level)
	elif level_name == "SecondFloor":
		_build_stairwell_floor(level)
		_build_stairwell_parapet(level)
	
	# 2. Outer boundary walls & Cornice beams (sealing wall-ceiling junctions)
	# North walls (Z = min_z - 0.5)
	for x in range(min_x, max_x + 1):
		var pos = Vector3(x * GRID_SIZE, 0, min_z * GRID_SIZE - GRID_SIZE * 0.5)
		_place_wall(level, pos, 0.0)
		_place_cornice(level, Vector3(pos.x, WALL_HEIGHT - 0.05, pos.z + 0.12), 0.0)
	
	# South walls (Z = max_z + 0.5)
	for x in range(min_x, max_x + 1):
		var pos = Vector3(x * GRID_SIZE, 0, max_z * GRID_SIZE + GRID_SIZE * 0.5)
		if level_name == "GroundFloor" and x == 0:
			# Opening for front entrance, but keep top beam/cornice
			_place_cornice(level, Vector3(pos.x, WALL_HEIGHT - 0.05, pos.z - 0.12), PI)
			continue
		_place_wall(level, pos, PI)
		_place_cornice(level, Vector3(pos.x, WALL_HEIGHT - 0.05, pos.z - 0.12), PI)
		
	# West walls (X = min_x - 0.5)
	for z in range(min_z, max_z + 1):
		var pos = Vector3(min_x * GRID_SIZE - GRID_SIZE * 0.5, 0, z * GRID_SIZE)
		_place_wall(level, pos, PI * 0.5)
		_place_cornice(level, Vector3(pos.x + 0.12, WALL_HEIGHT - 0.05, pos.z), PI * 0.5)
		
	# East walls (X = max_x + 0.5)
	for z in range(min_z, max_z + 1):
		var pos = Vector3(max_x * GRID_SIZE + GRID_SIZE * 0.5, 0, z * GRID_SIZE)
		_place_wall(level, pos, -PI * 0.5)
		_place_cornice(level, Vector3(pos.x - 0.12, WALL_HEIGHT - 0.05, pos.z), -PI * 0.5)

func _place_tile(parent: Node3D, pos: Vector3, packed: PackedScene, fallback_color: Color, box_size: Vector3, add_floor_collision: bool) -> void:
	var n: Node3D
	if packed:
		n = packed.instantiate() as Node3D
	else:
		var mi = MeshInstance3D.new()
		var bm = BoxMesh.new()
		bm.size = box_size
		var mat = StandardMaterial3D.new()
		mat.albedo_color = fallback_color
		mat.roughness = 0.85
		mi.mesh = bm
		mi.material_override = mat
		n = mi
		
	n.position = pos
	parent.add_child(n)
	
	if add_floor_collision:
		var sb = StaticBody3D.new()
		sb.collision_layer = 1 # World layer
		sb.collision_mask = 0
		var col = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = box_size
		col.shape = shape
		sb.add_child(col)
		sb.position = pos
		parent.add_child(sb)

## Places a solid backing slab directly above the ceiling to completely prevent any rays escaping to the sky
func _place_ceiling_backer(parent: Node3D, pos: Vector3) -> void:
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = Vector3(GRID_SIZE + 0.2, 0.1, GRID_SIZE + 0.2)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.12, 0.09) # Dark timber subfloor
	mat.roughness = 0.95
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)

## Places a horizontal wooden cornice trim beam along wall-ceiling junctions
func _place_cornice(parent: Node3D, pos: Vector3, rot_y: float) -> void:
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = Vector3(GRID_SIZE + 0.1, 0.18, 0.25)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.14, 0.09) # Dark rustic wood crown molding
	mat.roughness = 0.85
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = rot_y
	parent.add_child(mi)

func _place_wall(parent: Node3D, pos: Vector3, rot_y: float) -> void:
	var n: Node3D
	if wall_scene:
		n = wall_scene.instantiate() as Node3D
	else:
		var mi = MeshInstance3D.new()
		var bm = BoxMesh.new()
		bm.size = Vector3(GRID_SIZE, WALL_HEIGHT, 0.25)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.25, 0.18)
		mat.roughness = 0.9
		mi.mesh = bm
		mi.material_override = mat
		mi.position.y = WALL_HEIGHT * 0.5
		n = mi
		
	n.position = pos
	n.rotation.y = rot_y
	parent.add_child(n)
	
	# Wall collision
	var sb = StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(GRID_SIZE, WALL_HEIGHT, 0.25)
	col.shape = shape
	col.position.y = WALL_HEIGHT * 0.5
	sb.add_child(col)
	sb.position = pos
	sb.rotation.y = rot_y
	parent.add_child(sb)

## Builds a realistic 12-step wooden staircase with steps, side handrails, and under-stair enclosure
func _build_stepped_stairs(parent: Node3D, stair_name: String, bottom_pos: Vector3, rises_up: bool, total_height: float, stair_width: float = 1.1) -> void:
	var root_node = Node3D.new()
	root_node.name = stair_name
	parent.add_child(root_node)
	
	var num_steps: int = 12
	var step_h: float = total_height / float(num_steps) # 0.25m per step
	var step_d: float = 0.28 # 0.28m tread depth
	var total_len: float = step_d * float(num_steps) # 3.36m run
	
	var wood_mat = StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.28, 0.2, 0.14) # Stained oak stair tread
	wood_mat.roughness = 0.85
	
	var rail_mat = StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.18, 0.13, 0.09) # Dark walnut handrail
	rail_mat.roughness = 0.8
	
	# 1. Build individual box steps
	for i in range(num_steps):
		var step_sb = StaticBody3D.new()
		step_sb.name = "Step_%d" % i
		step_sb.collision_layer = 1
		step_sb.collision_mask = 0
		
		# Box mesh for tread
		var mi = MeshInstance3D.new()
		var bm = BoxMesh.new()
		bm.size = Vector3(stair_width, step_h, step_d)
		mi.mesh = bm
		mi.material_override = wood_mat
		step_sb.add_child(mi)
		
		# Collision shape for step
		var col = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = bm.size
		col.shape = shape
		step_sb.add_child(col)
		
		# Calculate step coordinate
		# Rising North means moving in -Z as we ascend
		var step_y: float
		var step_z: float
		if rises_up:
			step_y = bottom_pos.y + (float(i) + 0.5) * step_h
			step_z = bottom_pos.z - (float(i) + 0.5) * step_d
		else:
			# Descending to basement: step 0 is highest (near 0), step 11 is lowest (near -3.0)
			step_y = bottom_pos.y - (float(i) + 0.5) * step_h
			step_z = bottom_pos.z - (float(i) + 0.5) * step_d
		
		step_sb.position = Vector3(bottom_pos.x, step_y, step_z)
		root_node.add_child(step_sb)
		
		# Under-stair solid enclosure so you can't see empty space underneath
		var skirt_sb = StaticBody3D.new()
		skirt_sb.collision_layer = 1
		skirt_sb.collision_mask = 0
		var skirt_mi = MeshInstance3D.new()
		var skirt_bm = BoxMesh.new()
		var skirt_h = (float(i) + 1.0) * step_h
		var skirt_base_y = bottom_pos.y if rises_up else (bottom_pos.y - total_height)
		skirt_bm.size = Vector3(stair_width - 0.02, skirt_h, step_d)
		skirt_mi.mesh = skirt_bm
		skirt_mi.material_override = wood_mat
		skirt_sb.add_child(skirt_mi)
		var skirt_y = (skirt_base_y + step_y - step_h * 0.5) * 0.5 if rises_up else (bottom_pos.y - total_height * 0.5)
		skirt_sb.position = Vector3(bottom_pos.x, (step_y - step_h * 0.5) * 0.5 if rises_up else (step_y + (bottom_pos.y - total_height)) * 0.5, step_z)
		# Add to visual tree
		root_node.add_child(skirt_sb)
	
	# 2. Side Stringers / Railings on left and right
	for side in [-1.0, 1.0]:
		var side_x = bottom_pos.x + side * (stair_width * 0.5 + 0.05)
		var rail_sb = StaticBody3D.new()
		rail_sb.collision_layer = 1
		rail_sb.collision_mask = 0
		
		# Sloped handrail board
		var rail_mi = MeshInstance3D.new()
		var rail_bm = BoxMesh.new()
		var diag_len = sqrt(total_len * total_len + total_height * total_height)
		rail_bm.size = Vector3(0.08, 0.9, diag_len)
		rail_mi.mesh = rail_bm
		rail_mi.material_override = rail_mat
		rail_sb.add_child(rail_mi)
		
		var col = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = rail_bm.size
		col.shape = shape
		rail_sb.add_child(col)
		
		var pitch = atan2(total_height, total_len)
		rail_sb.rotation = Vector3(pitch if rises_up else -pitch, 0, 0)
		var mid_y = bottom_pos.y + (total_height * 0.5 if rises_up else -total_height * 0.5) + 0.45
		var mid_z = bottom_pos.z - total_len * 0.5
		rail_sb.position = Vector3(side_x, mid_y, mid_z)
		root_node.add_child(rail_sb)
	
	# 3. Smooth invisible locomotion collision ramp (for perfectly smooth character walking & navmesh)
	var smooth_sb = StaticBody3D.new()
	smooth_sb.name = "LocomotionRamp"
	smooth_sb.collision_layer = 1
	smooth_sb.collision_mask = 0
	var col_smooth = CollisionShape3D.new()
	var box_smooth = BoxShape3D.new()
	var diag_len = sqrt(total_len * total_len + total_height * total_height)
	box_smooth.size = Vector3(stair_width, 0.08, diag_len)
	col_smooth.shape = box_smooth
	smooth_sb.add_child(col_smooth)
	var pitch = atan2(total_height, total_len)
	smooth_sb.rotation = Vector3(pitch if rises_up else -pitch, 0, 0)
	var mid_y = bottom_pos.y + (total_height * 0.5 if rises_up else -total_height * 0.5)
	var mid_z = bottom_pos.z - total_len * 0.5
	smooth_sb.position = Vector3(bottom_pos.x, mid_y, mid_z)
	root_node.add_child(smooth_sb)

func _build_interior_features(parent: Node3D) -> void:
	# Crates & barrels in corners
	_spawn_prop(parent, crate_scene, Vector3(6.0, 0.0, -2.0), Vector3.ZERO)
	_spawn_prop(parent, crate_scene, Vector3(6.5, 0.0, -1.2), Vector3(0, 0.4, 0))
	_spawn_prop(parent, barrel_scene, Vector3(-6.0, 0.0, -6.0), Vector3.ZERO)
	_spawn_prop(parent, barrel_scene, Vector3(-5.2, 0.0, -6.2), Vector3.ZERO)
	_spawn_prop(parent, rug_scene, Vector3(0.0, 0.02, 0.0), Vector3.ZERO)
	_spawn_prop(parent, painting_scene, Vector3(0.0, 1.8, -9.8), Vector3.ZERO) # Placed against North wall
	
	# Basement clutter
	_spawn_prop(parent, barrel_scene, Vector3(2.0, -3.0, 0.0), Vector3.ZERO)
	_spawn_prop(parent, crate_scene, Vector3(-2.0, -3.0, -2.0), Vector3.ZERO)

func _spawn_prop(parent: Node3D, packed: PackedScene, pos: Vector3, rot: Vector3) -> void:
	if not packed:
		return
	var inst = packed.instantiate() as Node3D
	inst.position = pos
	inst.rotation = rot
	parent.add_child(inst)
	
	var sb = StaticBody3D.new()
	sb.collision_layer = 1
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.9, 0.9, 0.9)
	col.shape = shape
	col.position.y = 0.45
	sb.add_child(col)
	sb.position = pos
	parent.add_child(sb)

# -----------------------------------------------------------------------------
# Custom Stairwell Infill & Parapets
# Opening footprint: X in [-4.65, -3.35] (width 1.3m), Z in [-3.36, -0.36] (length 3.0m).
# Surrounding cells: x = -1, z in [-1, 0] covers X in [-6.0, -2.0], Z in [-6.0, +2.0].
# -----------------------------------------------------------------------------

func _build_stairwell_ceiling(level: Node3D) -> void:
	# GroundFloor ceiling is at local Y = WALL_HEIGHT (3.0)
	var y = WALL_HEIGHT
	var mat_color = Color(0.2, 0.15, 0.1)
	
	# 1. North ceiling slab: covers X[-6.0, -2.0], Z[-6.0, -3.36] (covers HallwayDimLight at -4, 2.3, -4)
	# Size: X=4.0, Y=0.2, Z=2.64 | Center: X=-4.0, Z=(-6.0 + -3.36)/2 = -4.68
	_place_slab(level, Vector3(-4.0, y, -4.68), Vector3(4.0, 0.2, 2.64), mat_color, false)
	_place_slab(level, Vector3(-4.0, y + 0.05, -4.68), Vector3(4.1, 0.02, 2.74), Color(0.05, 0.04, 0.03), false)
	
	# 2. South ceiling slab: covers X[-6.0, -2.0], Z[-0.36, +2.0]
	# Size: X=4.0, Y=0.2, Z=2.36 | Center: X=-4.0, Z=(-0.36 + 2.0)/2 = 0.82
	_place_slab(level, Vector3(-4.0, y, 0.82), Vector3(4.0, 0.2, 2.36), mat_color, false)
	_place_slab(level, Vector3(-4.0, y + 0.05, 0.82), Vector3(4.1, 0.02, 2.46), Color(0.05, 0.04, 0.03), false)
	
	# 3. West ceiling slab: covers X[-6.0, -4.65], Z[-3.36, -0.36]
	# Size: X=1.35, Y=0.2, Z=3.00 | Center: X=(-6.0 + -4.65)/2 = -5.325, Z=(-3.36 + -0.36)/2 = -1.86
	_place_slab(level, Vector3(-5.325, y, -1.86), Vector3(1.35, 0.2, 3.0), mat_color, false)
	_place_slab(level, Vector3(-5.325, y + 0.05, -1.86), Vector3(1.45, 0.02, 3.1), Color(0.05, 0.04, 0.03), false)
	
	# 4. East ceiling slab: covers X[-3.35, -2.0], Z[-3.36, -0.36]
	# Size: X=1.35, Y=0.2, Z=3.00 | Center: X=(-3.35 + -2.0)/2 = -2.675, Z=-1.86
	_place_slab(level, Vector3(-2.675, y, -1.86), Vector3(1.35, 0.2, 3.0), mat_color, false)
	_place_slab(level, Vector3(-2.675, y + 0.05, -1.86), Vector3(1.45, 0.02, 3.1), Color(0.05, 0.04, 0.03), false)

func _build_stairwell_floor(level: Node3D) -> void:
	# SecondFloor floor is at local Y = 0.0
	var y = 0.0
	var mat_color = Color(0.25, 0.18, 0.12)
	
	# North floor slab
	_place_slab(level, Vector3(-4.0, y, -4.68), Vector3(4.0, 0.2, 2.64), mat_color, true)
	# South floor slab
	_place_slab(level, Vector3(-4.0, y, 0.82), Vector3(4.0, 0.2, 2.36), mat_color, true)
	# West floor slab
	_place_slab(level, Vector3(-5.325, y, -1.86), Vector3(1.35, 0.2, 3.0), mat_color, true)
	# East floor slab
	_place_slab(level, Vector3(-2.675, y, -1.86), Vector3(1.35, 0.2, 3.0), mat_color, true)

func _build_stairwell_parapet(level: Node3D) -> void:
	# Parapet railings on SecondFloor around the stair shaft (height 0.9m)
	# West parapet: X = -4.65, Z in [-3.36, -0.36] -> Center Z = -1.86
	_place_slab(level, Vector3(-4.65, 0.45, -1.86), Vector3(0.08, 0.9, 3.0), Color(0.3, 0.22, 0.15), true)
	# East parapet: X = -3.35, Z in [-3.36, -0.36] -> Center Z = -1.86
	_place_slab(level, Vector3(-3.35, 0.45, -1.86), Vector3(0.08, 0.9, 3.0), Color(0.3, 0.22, 0.15), true)
	# South parapet: Z = -0.36, X in [-4.69, -3.31] -> Center X = -4.0, length = 1.38
	_place_slab(level, Vector3(-4.0, 0.45, -0.36), Vector3(1.38, 0.9, 0.08), Color(0.3, 0.22, 0.15), true)
	# North side is the stair exit / landing onto the second floor (Z = -3.36), left open for walking.

func _build_stairwell_casing(level: Node3D) -> void:
	# Trim lining the inner rim of the ceiling hole (Y = 2.9 to 3.1)
	var y = WALL_HEIGHT
	var casing_col = Color(0.28, 0.2, 0.14)
	# West rim
	_place_slab(level, Vector3(-4.65, y, -1.86), Vector3(0.06, 0.22, 3.0), casing_col, false)
	# East rim
	_place_slab(level, Vector3(-3.35, y, -1.86), Vector3(0.06, 0.22, 3.0), casing_col, false)
	# South rim
	_place_slab(level, Vector3(-4.0, y, -0.36), Vector3(1.36, 0.22, 0.06), casing_col, false)
	# North rim
	_place_slab(level, Vector3(-4.0, y, -3.36), Vector3(1.36, 0.22, 0.06), casing_col, false)

func _place_slab(level: Node3D, pos: Vector3, size: Vector3, color: Color, with_collision: bool) -> void:
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = size
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	
	if with_collision:
		var sb = StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var col = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = size
		col.shape = shape
		sb.add_child(col)
		sb.position = pos
		level.add_child(sb)
	
	level.add_child(mi)
