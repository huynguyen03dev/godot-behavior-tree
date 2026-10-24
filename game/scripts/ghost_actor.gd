class_name GhostActor
extends CharacterBody3D

signal grabbed_player(player: Node)
signal ghost_banished

# State & Speed variables
var current_speed: float = 1.0
var base_speed: float = 1.0
var ability_index: int = 0      # 0=Idle/Wander, 201=Attack, 202=Pursue, 203=Flee, 204=Death/Banished
var ability_int_data: int = 0   # 666=Hit by UV Flashlight

var is_banished: bool = false
var carried_object: Node3D = null

# Timers & procedural animation
var _sway_time: float = 0.0
var _bob_time: float = 0.0
var _grab_cooldown: float = 0.0
var _nav_target: Vector3 = Vector3.ZERO
var _cached_player: Node3D = null

# Nodes
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var visual_root: Node3D = $Visual
@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var eyes_light: OmniLight3D = $Visual/EyesLight
@onready var carry_socket: Marker3D = $Visual/CarrySocket
@onready var brain_node: Node = $GhostBrain

func _ready() -> void:
	add_to_group("Ghost")
	# Collision: Layer 3 (Ghost, bit 4)
	collision_layer = 4
	# Collision mask: Layer 1 (World, bit 1)
	collision_mask = 1

	if nav_agent:
		nav_agent.path_desired_distance = 0.5
		nav_agent.target_desired_distance = 0.5
		nav_agent.avoidance_enabled = false

	if visual_root and visual_root.get_node_or_null("GhostModel") == null:
		if ResourceLoader.exists("res://game/assets/models/ghost.glb"):
			var ghost_scene = load("res://game/assets/models/ghost.glb")
			if ghost_scene:
				var inst = ghost_scene.instantiate()
				inst.name = "GhostModel"
				inst.scale = Vector3(0.85, 0.85, 0.85)
				visual_root.add_child(inst)

	_init_procedural_audio()

func _physics_process(delta: float) -> void:
	if is_banished:
		velocity = Vector3.ZERO
		return

	if _grab_cooldown > 0.0:
		_grab_cooldown -= delta

	# Check grab condition: when chasing or attacking and in close range
	if _grab_cooldown <= 0.0 and (ability_index == 201 or ability_index == 202):
		_check_grab_distance()

	# Procedural bobbing & animation in code
	_process_procedural_animation(delta)

	move_and_slide()

func _process_procedural_animation(delta: float) -> void:
	if not visual_root:
		return

	_bob_time += delta * 2.5
	var bob_y: float = sin(_bob_time) * 0.08
	visual_root.position.y = bob_y

	# Breathing pulse
	var pulse: float = 1.0 + sin(_bob_time * 1.5) * 0.02
	visual_root.scale = Vector3(pulse, pulse, pulse)

	# Reaction to UV Flashlight (Hit 666)
	if ability_int_data == 666:
		var jitter_x = (randf() - 0.5) * 0.08
		var jitter_z = (randf() - 0.5) * 0.08
		visual_root.position.x = jitter_x
		visual_root.position.z = jitter_z
		if eyes_light:
			eyes_light.light_color = Color(1.0, 0.2, 0.2)
			eyes_light.light_energy = 4.0
	else:
		visual_root.position.x = 0.0
		visual_root.position.z = 0.0
		if eyes_light:
			if ability_index == 201 or ability_index == 202:
				eyes_light.light_color = Color(1.0, 0.1, 0.1) # Glowing red in chase
				eyes_light.light_energy = 2.5
			else:
				eyes_light.light_color = Color(0.2, 0.8, 1.0) # Pale cyan in wander
				eyes_light.light_energy = 1.0

func _check_grab_distance() -> void:
	var player = _get_player()
	if player and is_instance_valid(player):
		var dist = global_position.distance_to(player.global_position)
		if dist <= 0.8:
			_grab_player(player)

func _grab_player(player: Node) -> void:
	_grab_cooldown = 2.5
	ability_index = 201 # Attack
	emit_signal("grabbed_player", player)
	var tree = get_tree()
	if tree and tree.current_scene:
		var scene = tree.current_scene
		var gm = scene if scene.has_method("on_player_grabbed") else scene.get_node_or_null("GameManager")
		if gm and gm.has_method("on_player_grabbed"):
			gm.on_player_grabbed(self)

func _get_player() -> Node3D:
	if _cached_player and is_instance_valid(_cached_player):
		return _cached_player
	var tree = get_tree()
	if tree:
		var players = tree.get_nodes_in_group("Player")
		if players.size() > 0:
			_cached_player = players[0] as Node3D
			return _cached_player
	return null

# ==============================================================================
# ACTOR API IMPLEMENTATION (TASKS.md Section 7 Contract)
# ==============================================================================

# --- Motor & Movement ---

func set_motor_speed(p_speed: float) -> void:
	current_speed = p_speed

func set_speed(p_speed: float) -> void:
	set_motor_speed(p_speed)

func set_nav_target(p_destination: Vector3) -> void:
	_nav_target = p_destination
	if nav_agent:
		nav_agent.target_position = p_destination

func step_navigation(p_delta: float, p_speed: float, p_look_at: bool) -> float:
	if is_banished:
		velocity = Vector3.ZERO
		return 999.0

	var dest: Vector3 = _nav_target
	if nav_agent and not nav_agent.is_navigation_finished():
		var next_pos: Vector3 = nav_agent.get_next_path_position()
		var dir: Vector3 = (next_pos - global_position).normalized()
		dir.y = 0.0
		if dir.length_squared() > 0.001:
			dir = dir.normalized()
			velocity.x = dir.x * p_speed
			velocity.z = dir.z * p_speed
			if p_look_at:
				rotate_towards_point(next_pos, 180.0 * p_delta)
		dest = next_pos
	else:
		# Fallback direct steering towards target
		var dir: Vector3 = (_nav_target - global_position)
		dir.y = 0.0
		if dir.length() > 0.2:
			dir = dir.normalized()
			velocity.x = dir.x * p_speed
			velocity.z = dir.z * p_speed
			if p_look_at:
				rotate_towards_point(_nav_target, 180.0 * p_delta)
		else:
			velocity.x = 0.0
			velocity.z = 0.0

	return global_position.distance_to(_nav_target)

func move_towards(p_dest: Vector3, p_speed: float, p_delta: float) -> float:
	set_nav_target(p_dest)
	return step_navigation(p_delta, p_speed, true)

func step_pursue(p_target_pos: Vector3, p_speed: float, p_delta: float) -> void:
	if is_banished:
		velocity = Vector3.ZERO
		return

	if nav_agent:
		nav_agent.target_position = p_target_pos

	var target_to_steer := p_target_pos
	if nav_agent and not nav_agent.is_navigation_finished():
		target_to_steer = nav_agent.get_next_path_position()

	_sway_time += p_delta * 1.5
	var to_target: Vector3 = (target_to_steer - global_position)
	to_target.y = 0.0
	if to_target.length_squared() < 0.001:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var forward: Vector3 = to_target.normalized()
	# Perpendicular sway vector on XZ plane
	var side := Vector3(-forward.z, 0.0, forward.x)
	var sway: Vector3 = side * (sin(_sway_time) * 0.25)
	var move_dir: Vector3 = (forward + sway).normalized()

	velocity.x = move_dir.x * p_speed
	velocity.z = move_dir.z * p_speed

	rotate_towards_point(p_target_pos, 360.0 * p_delta)

func pursue(p_target_pos: Vector3, p_speed: float, p_delta: float) -> void:
	step_pursue(p_target_pos, p_speed, p_delta)

func stop_navigation() -> void:
	velocity = Vector3.ZERO
	if nav_agent:
		nav_agent.target_position = global_position

func get_random_navmesh_point(p_min_dist: float, p_max_dist: float) -> Vector3:
	var angle := randf() * TAU
	var dist := randf_range(p_min_dist, p_max_dist)
	var offset := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	var candidate := global_position + offset

	# Try query closest point on NavServer
	var default_map = get_world_3d().navigation_map
	if default_map.is_valid() and NavigationServer3D.map_get_iteration_id(default_map) > 0:
		var closest = NavigationServer3D.map_get_closest_point(default_map, candidate)
		if closest != Vector3.ZERO:
			return closest

	return candidate

func compute_flee_point(p_threat_pos: Vector3, p_distance: float) -> Vector3:
	var flee_dir: Vector3 = (global_position - p_threat_pos)
	flee_dir.y = 0.0
	if flee_dir.length_squared() < 0.001:
		flee_dir = Vector3(1.0, 0.0, 0.0)
	else:
		flee_dir = flee_dir.normalized()

	var dest: Vector3 = global_position + flee_dir * p_distance
	var default_map = get_world_3d().navigation_map
	if default_map.is_valid() and NavigationServer3D.map_get_iteration_id(default_map) > 0:
		var closest = NavigationServer3D.map_get_closest_point(default_map, dest)
		if closest != Vector3.ZERO:
			return closest
	return dest

func rotate_towards_point(p_point: Vector3, p_max_delta: float) -> bool:
	var local_target: Vector3 = p_point - global_position
	local_target.y = 0.0
	if local_target.length_squared() < 0.001:
		return true

	var target_yaw := atan2(-local_target.x, -local_target.z)
	var current_yaw := rotation.y
	var diff := wrapf(target_yaw - current_yaw, -PI, PI)

	var max_rad := deg_to_rad(p_max_delta)
	if abs(diff) <= max_rad:
		rotation.y = target_yaw
		return true
	else:
		rotation.y += sign(diff) * max_rad
		return false

func look_at_target(p_target_pos: Vector3) -> void:
	rotate_towards_point(p_target_pos, 720.0)

# --- Perception & Sensors ---

func is_flashlight_shining_on_me(p_fry_only: bool, p_max_dist: float) -> Node3D:
	if is_banished:
		return null

	var player = _get_player()
	if not player or not is_instance_valid(player):
		return null

	# Check if player flashlight is turned on
	var light_on: bool = bool(player.get("flashlight_on"))
	if not light_on:
		return null

	# If fry_only is requested, player must be in focused UV mode
	if p_fry_only:
		var uv_active: bool = bool(player.get("flashlight_uv"))
		if not uv_active:
			return null

	# Distance check
	var ghost_center: Vector3 = global_position + Vector3(0.0, 1.2, 0.0)
	var player_cam = player.get_node_or_null("Head/Camera3D")
	var cam_pos: Vector3 = player_cam.global_position if player_cam else (player.global_position + Vector3(0.0, 1.6, 0.0))
	var dist: float = cam_pos.distance_to(ghost_center)
	if dist > p_max_dist:
		return null

	# Angle check: player camera facing towards ghost
	var cam_forward: Vector3 = -player_cam.global_transform.basis.z if player_cam else -player.global_transform.basis.z
	var to_ghost: Vector3 = (ghost_center - cam_pos).normalized()
	var dot: float = cam_forward.dot(to_ghost)
	# Half angle: 30 deg for normal (cos ~0.866), 20 deg for UV (cos ~0.939)
	var min_cos: float = 0.92 if p_fry_only else 0.82
	if dot < min_cos:
		return null

	# Raycast check for line of sight (mask Layer 1 = World)
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(cam_pos, ghost_center, 1) # Layer 1 World
	var hit = space_state.intersect_ray(query)
	if hit.is_empty():
		return player
	return null

func can_see_target(p_target: Node3D, p_fov_deg: float, p_max_dist: float) -> bool:
	if is_banished or not p_target or not is_instance_valid(p_target):
		return false

	var ghost_eyes: Vector3 = global_position + Vector3(0.0, 1.7, 0.0)
	var target_center: Vector3 = p_target.global_position + Vector3(0.0, 1.2, 0.0)
	var dist: float = ghost_eyes.distance_to(target_center)
	if dist > p_max_dist:
		return false

	# Vision cone angle check
	var forward: Vector3 = -global_transform.basis.z
	var to_target: Vector3 = (target_center - ghost_eyes).normalized()
	var dot: float = forward.dot(to_target)
	var half_angle_rad: float = deg_to_rad(p_fov_deg * 0.5)
	if dot < cos(half_angle_rad):
		return false

	# Line of sight physics raycast (mask 1 World)
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ghost_eyes, target_center, 1)
	var hit = space_state.intersect_ray(query)
	return hit.is_empty()

func is_player_visible(p_target: Node3D = null) -> bool:
	var t = p_target if p_target else _get_player()
	return can_see_target(t, 75.0, 20.0)

func detect_player_noise(p_walk_radius: float, p_sprint_radius: float) -> Node3D:
	if is_banished:
		return null

	var player = _get_player()
	if not player or not is_instance_valid(player):
		return null

	# If player is crouching, noise is 0
	if bool(player.get("is_crouching")):
		return null

	var dist: float = global_position.distance_to(player.global_position)
	if bool(player.get("is_sprinting")) and dist <= p_sprint_radius:
		return player
	if bool(player.get("is_walking")) and dist <= p_walk_radius:
		return player

	return null

func query_nearby_objects(p_tag: String, p_radius: float, p_los: bool) -> Node3D:
	if is_banished:
		return null

	var objects = get_tree().get_nodes_in_group(p_tag)
	var closest_obj: Node3D = null
	var min_dist: float = p_radius

	for obj in objects:
		if obj is Node3D and is_instance_valid(obj):
			var d = global_position.distance_to(obj.global_position)
			if d <= min_dist:
				if p_los:
					var space = get_world_3d().direct_space_state
					var query = PhysicsRayQueryParameters3D.create(
						global_position + Vector3(0, 1.5, 0),
						obj.global_position + Vector3(0, 0.5, 0),
						1
					)
					var hit = space.intersect_ray(query)
					if not hit.is_empty():
						continue
				min_dist = d
				closest_obj = obj

	return closest_obj

func get_target_distance(p_target: Node3D) -> float:
	if p_target and is_instance_valid(p_target):
		return global_position.distance_to(p_target.global_position)
	return 999.0

# --- State & Events ---

func set_parameter(p_name: String, p_val: int) -> void:
	if p_name == "AbilityIndex":
		ability_index = p_val
		if ability_index == 204:
			on_ghost_banished()
	elif p_name == "AbilityIntData":
		ability_int_data = p_val

func set_ability_index(p_val: int) -> void:
	set_parameter("AbilityIndex", p_val)

func set_ability_int_data(p_val: int) -> void:
	set_parameter("AbilityIntData", p_val)

func get_ability_index() -> int:
	return ability_index

func handle_bt_event(p_event_name: String, p_data = null) -> void:
	match p_event_name:
		"OnSpawnRitualBook":
			drop_carried_object()
		"OnGhostPursue":
			ability_index = 202
			_play_scream()
		"SetLookAtEntity":
			if p_data is Node3D:
				rotate_towards_point(p_data.global_position, 360.0)

func attach_carried_object(p_obj: Node3D) -> void:
	if not p_obj or not is_instance_valid(p_obj):
		return
	carried_object = p_obj
	if carry_socket:
		p_obj.get_parent().remove_child(p_obj)
		carry_socket.add_child(p_obj)
		p_obj.transform = Transform3D.IDENTITY
	else:
		p_obj.get_parent().remove_child(p_obj)
		visual_root.add_child(p_obj)
		p_obj.position = Vector3(0.0, 1.0, -0.4)

func drop_carried_object() -> void:
	if carried_object and is_instance_valid(carried_object):
		if carried_object.has_method("drop_to_ground"):
			carried_object.drop_to_ground(global_position + Vector3(0.0, 0.2, 0.0))
		carried_object = null

func stop_brain() -> void:
	if brain_node and brain_node.has_method("stop_brain"):
		brain_node.stop_brain()

func start_brain() -> void:
	if brain_node and brain_node.has_method("start_brain"):
		brain_node.start_brain()

func on_ghost_banished() -> void:
	if is_banished:
		return
	is_banished = true
	ability_index = 204
	ability_int_data = 0
	stop_navigation()
	drop_carried_object()
	stop_brain()
	if visual_root:
		visual_root.visible = false
	collision_layer = 0
	emit_signal("ghost_banished")
	var tree = get_tree()
	if tree and tree.current_scene:
		var scene = tree.current_scene
		var gm = scene if scene.has_method("on_ghost_banished") else scene.get_node_or_null("GameManager")
		if gm and gm.has_method("on_ghost_banished"):
			gm.on_ghost_banished()

func respawn_at(spawn_pos: Vector3) -> void:
	global_position = spawn_pos
	is_banished = false
	ability_index = 0
	ability_int_data = 0
	current_speed = base_speed
	collision_layer = 4
	if visual_root:
		visual_root.visible = true
	stop_navigation()
	start_brain()

# --- Procedural Ghost Audio ---

func _init_procedural_audio() -> void:
	var sample_rate: int = 22050
	var duration: float = 0.35
	var num_samples: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples)
	for i in range(num_samples):
		var t := float(i) / float(num_samples)
		# Eerie howling sweep
		var freq := 300.0 + sin(t * PI * 2.0) * 120.0
		var s := sin(t * duration * freq * TAU) * (1.0 - t) * 0.4
		var val := int(clamp(s * 127.0, -128.0, 127.0))
		if val < 0: val += 256
		data[i] = val
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	if audio_player:
		audio_player.stream = stream

func _play_scream() -> void:
	if audio_player and audio_player.stream:
		audio_player.pitch_scale = randf_range(0.85, 1.15)
		audio_player.play()
