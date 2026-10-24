class_name PlayerController
extends CharacterBody3D

signal rat_count_changed(count: int)
signal keys_changed(keys_list: Array)
signal stamina_changed(current: float, max_val: float)
signal uv_battery_changed(current: float, max_val: float)
signal flashlight_state_changed(is_on: bool, is_uv: bool)
signal interaction_prompt_changed(text: String)

# Movement constants
const WALK_SPEED: float = 3.5
const SPRINT_SPEED: float = 6.0
const CROUCH_SPEED: float = 1.8
const GRAVITY: float = 9.8

const MOUSE_SENSITIVITY: float = 0.0025
const MIN_PITCH: float = deg_to_rad(-80.0)
const MAX_PITCH: float = deg_to_rad(80.0)

const STAND_HEIGHT: float = 1.6
const CROUCH_HEIGHT: float = 0.9

# Stamina
@export var max_stamina: float = 100.0
var current_stamina: float = 100.0
var stamina_drain_rate: float = 25.0
var stamina_recovery_rate: float = 30.0
var stamina_recovery_delay: float = 2.0
var _stamina_delay_timer: float = 0.0

# UV Flashlight Battery
@export var max_uv_battery: float = 5.0
var current_uv_battery: float = 5.0
var uv_drain_rate: float = 1.0 # Drains in 5s
var uv_recovery_rate: float = 0.5 # Recovers in 10s

# State flags for Ghost AI detection
var is_sprinting: bool = false
var is_walking: bool = false
var is_crouching: bool = false
var flashlight_on: bool = true
var flashlight_uv: bool = false

# Farmhouse Inventory
const MAX_RATS_CARRIED: int = 3
var rat_count: int = 0
var collected_keys: Array[String] = []
var fuse_count: int = 0

# Footsteps
var _footstep_timer: float = 0.0
var _footstep_stream: AudioStreamWAV = null

# Node references
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight_spot: SpotLight3D = $Head/Camera3D/FlashlightMount/SpotLight3D
@onready var flashlight_mesh: Node3D = $Head/Camera3D/FlashlightMount/FlashlightMesh
@onready var hand_socket: Marker3D = $Head/Camera3D/HandSocket
@onready var interact_ray: RayCast3D = $Head/Camera3D/InteractRayCast
@onready var footstep_player: AudioStreamPlayer3D = $FootstepPlayer
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var _current_target_interactable: Node = null

func _ready() -> void:
	add_to_group("Player")
	# Collision: Layer 2 (Player)
	collision_layer = 2
	# Collision mask: Layer 1 (World) | Layer 4 (Interactables)
	collision_mask = 1 | 8

	_setup_procedural_footstep_audio()
	_update_flashlight_mode()

	if not Engine.is_editor_hint():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		head.rotation.x = clamp(head.rotation.x, MIN_PITCH, MAX_PITCH)
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			flashlight_on = not flashlight_on
			_update_flashlight_mode()
			emit_signal("flashlight_state_changed", flashlight_on, flashlight_uv)
		elif event.keycode == KEY_E:
			_try_interact()
		elif event.keycode == KEY_ESCAPE:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		if velocity.y < 0:
			velocity.y = 0.0

	# Crouch input
	var want_crouch = Input.is_key_pressed(KEY_CTRL)
	is_crouching = want_crouch
	var target_head_y = CROUCH_HEIGHT if is_crouching else STAND_HEIGHT
	head.position.y = lerp(head.position.y, target_head_y, delta * 10.0)

	# Movement direction
	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S): input_dir.y += 1.0
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D): input_dir.x += 1.0
	input_dir = input_dir.normalized()

	# Sprint input & stamina management
	var want_sprint = Input.is_key_pressed(KEY_SHIFT) and input_dir.length_squared() > 0.0 and not is_crouching
	if want_sprint and current_stamina > 0.0:
		is_sprinting = true
		is_walking = false
		current_stamina = max(0.0, current_stamina - stamina_drain_rate * delta)
		_stamina_delay_timer = stamina_recovery_delay
	else:
		is_sprinting = false
		is_walking = input_dir.length_squared() > 0.0
		if _stamina_delay_timer > 0.0:
			_stamina_delay_timer -= delta
		else:
			current_stamina = min(max_stamina, current_stamina + stamina_recovery_rate * delta)

	emit_signal("stamina_changed", current_stamina, max_stamina)

	# UV Flashlight Focus (Right Mouse Button hold)
	var want_uv = (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.is_key_pressed(KEY_ALT))) and flashlight_on
	if want_uv and current_uv_battery > 0.0:
		if not flashlight_uv:
			flashlight_uv = true
			_update_flashlight_mode()
			emit_signal("flashlight_state_changed", flashlight_on, flashlight_uv)
		current_uv_battery = max(0.0, current_uv_battery - uv_drain_rate * delta)
		if current_uv_battery <= 0.0:
			flashlight_uv = false
			_update_flashlight_mode()
			emit_signal("flashlight_state_changed", flashlight_on, flashlight_uv)
	else:
		if flashlight_uv:
			flashlight_uv = false
			_update_flashlight_mode()
			emit_signal("flashlight_state_changed", flashlight_on, flashlight_uv)
		current_uv_battery = min(max_uv_battery, current_uv_battery + uv_recovery_rate * delta)

	emit_signal("uv_battery_changed", current_uv_battery, max_uv_battery)

	# Compute target speed
	var speed: float = WALK_SPEED
	if is_crouching:
		speed = CROUCH_SPEED
	elif is_sprinting:
		speed = SPRINT_SPEED

	var direction = (global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	if direction.length_squared() > 0.0:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed * delta * 10.0)
		velocity.z = move_toward(velocity.z, 0.0, speed * delta * 10.0)

	move_and_slide()

	# Footsteps
	_process_footsteps(delta, input_dir.length_squared() > 0.0 and is_on_floor())

	# Interaction check
	_check_interaction()

func _update_flashlight_mode() -> void:
	if not flashlight_spot:
		return
	flashlight_spot.visible = flashlight_on
	if flashlight_on:
		if flashlight_uv:
			flashlight_spot.light_color = Color(0.65, 0.2, 1.0)
			flashlight_spot.spot_range = 10.0
			flashlight_spot.spot_angle = 18.0
			flashlight_spot.light_energy = 4.5
		else:
			flashlight_spot.light_color = Color(0.95, 0.92, 0.85)
			flashlight_spot.spot_range = 18.0
			flashlight_spot.spot_angle = 32.0
			flashlight_spot.light_energy = 2.0

func _check_interaction() -> void:
	if not interact_ray:
		return
	var collider = interact_ray.get_collider()
	if collider != _current_target_interactable:
		_current_target_interactable = collider
		_update_prompt()

func _update_prompt() -> void:
	if _current_target_interactable:
		var text := ""
		if _current_target_interactable.has_method("get_interaction_text"):
			if _current_target_interactable is Altar:
				text = _current_target_interactable.get_interaction_text(self)
			else:
				text = _current_target_interactable.get_interaction_text()
		else:
			text = "Press [E] to interact"
		emit_signal("interaction_prompt_changed", text)
	else:
		emit_signal("interaction_prompt_changed", "")

func _try_interact() -> void:
	if _current_target_interactable and _current_target_interactable.has_method("interact"):
		_current_target_interactable.interact(self)
		_update_prompt()

# --- Farmhouse Rat & Inventory Mechanics ---

func get_rat_count() -> int:
	return rat_count

func add_rat() -> bool:
	if rat_count < MAX_RATS_CARRIED:
		rat_count += 1
		emit_signal("rat_count_changed", rat_count)
		return true
	print("[Player] Bag is full! Can only carry %d rats at once." % MAX_RATS_CARRIED)
	return false

func consume_rat() -> bool:
	if rat_count > 0:
		rat_count -= 1
		emit_signal("rat_count_changed", rat_count)
		return true
	return false

func add_key(key_id: String, key_name: String = "") -> void:
	if not collected_keys.has(key_id):
		collected_keys.append(key_id)
		emit_signal("keys_changed", collected_keys)
		print("[Player] Acquired key: %s (%s)" % [key_id, key_name])

func has_key(key_id: String) -> bool:
	return collected_keys.has(key_id)

func consume_key(key_id: String) -> bool:
	if collected_keys.has(key_id):
		collected_keys.erase(key_id)
		emit_signal("keys_changed", collected_keys)
		return true
	return false

func add_fuse() -> void:
	fuse_count += 1
	print("[Player] Acquired electrical Fuse!")

func recharge_battery() -> void:
	current_uv_battery = max_uv_battery
	emit_signal("uv_battery_changed", current_uv_battery, max_uv_battery)
	print("[Player] UV Flashlight Battery fully recharged!")

func restore_stamina() -> void:
	current_stamina = max_stamina
	emit_signal("stamina_changed", current_stamina, max_stamina)
	print("[Player] Stamina restored by food!")

# --- BT / AI Sensor Contract ---

func get_ability_index() -> int:
	# 108 is hiding state in Devour
	return 108 if (is_crouching and velocity.length_squared() < 0.01) else 0

# --- Procedural Footsteps ---

func _setup_procedural_footstep_audio() -> void:
	var sample_rate: int = 22050
	var duration: float = 0.07
	var num_samples: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples)
	for i in range(num_samples):
		var t := float(i) / float(num_samples)
		var env := exp(-t * 18.0)
		var noise := (randf() * 2.0 - 1.0) * env
		var val := int(clamp((noise * 0.4) * 127.0, -128.0, 127.0))
		if val < 0: val += 256
		data[i] = val
	_footstep_stream = AudioStreamWAV.new()
	_footstep_stream.format = AudioStreamWAV.FORMAT_8_BITS
	_footstep_stream.mix_rate = sample_rate
	_footstep_stream.data = data
	if footstep_player:
		footstep_player.stream = _footstep_stream

func _process_footsteps(delta: float, moving: bool) -> void:
	if not moving or is_crouching:
		_footstep_timer = 0.0
		return
	var interval: float = 0.28 if is_sprinting else 0.52
	_footstep_timer += delta
	if _footstep_timer >= interval:
		_footstep_timer = 0.0
		if footstep_player and _footstep_stream:
			footstep_player.pitch_scale = randf_range(0.9, 1.1)
			footstep_player.play()
