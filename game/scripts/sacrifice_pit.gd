class_name SacrificePit
extends StaticBody3D

signal rat_burnt(new_count: int)
signal ritual_complete

@export var required_rats: int = 9
var burnt_count: int = 0

var has_rat_placed: bool = false
var has_fuel: bool = false
var is_burning: bool = false

var _burn_timer: float = 0.0

@onready var flame_light: OmniLight3D = $FlameLight
@onready var pit_light: OmniLight3D = $PitLight
@onready var fire_audio: AudioStreamPlayer3D = $FireAudio
@onready var rat_visual_mount: Node3D = $RatVisualMount
@onready var fuel_visual: MeshInstance3D = $Visual/FuelPuddle

var rat_scene: PackedScene = preload("res://game/scenes/rat.tscn")
var _placed_rat_instance: Node3D = null

func _ready() -> void:
	add_to_group("SacrificePit")
	add_to_group("Interactable")
	# Collision: Layer 1 (World) | Layer 4 (Interactable bit 8)
	collision_layer = 1 | 8
	collision_mask = 0
	
	_setup_fire_audio()
	_update_visuals()

func _setup_fire_audio() -> void:
	var sample_rate: int = 22050
	var duration: float = 0.5
	var num_samples: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples)
	for i in range(num_samples):
		var noise := randf() * 2.0 - 1.0
		var crackle := 1.0 if randf() < 0.05 else 0.3
		var val := int(clamp((noise * crackle) * 110.0, -128.0, 127.0))
		if val < 0: val += 256
		data[i] = val
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	if fire_audio:
		fire_audio.stream = stream

func _process(delta: float) -> void:
	if is_burning:
		_burn_timer -= delta
		if flame_light:
			flame_light.visible = true
			flame_light.light_energy = randf_range(3.5, 7.0)
			flame_light.light_color = Color(1.0, randf_range(0.2, 0.45), 0.05)
		if _burn_timer <= 0.0:
			_finish_burn()

func get_burnt_count() -> int:
	return burnt_count

func is_ritual_ready() -> bool:
	return burnt_count >= required_rats

func get_interaction_text(player: Node = null) -> String:
	if is_burning:
		return "Burning sacrificial offering..."
	if is_ritual_ready():
		return "Ritual Complete! Molly has been banished!"
	
	if has_rat_placed and has_fuel:
		return "Press [E] to ignite sacrifice (%d/%d)" % [burnt_count, required_rats]
	elif has_rat_placed and not has_fuel:
		if player and player.has_method("has_gasoline") and player.has_gasoline():
			return "Press [E] to pour gasoline"
		return "Rat placed — pour gasoline (%d/%d)" % [burnt_count, required_rats]
	elif not has_rat_placed and has_fuel:
		if player and player.has_method("get_rat_count") and player.get_rat_count() > 0:
			return "Press [E] to place rat on fueled pit"
		return "Fuel poured — place a rat to burn (%d/%d)" % [burnt_count, required_rats]
	else:
		if player and player.has_method("get_rat_count") and player.get_rat_count() > 0:
			return "Press [E] to place rat (%d/%d)" % [burnt_count, required_rats]
		elif player and player.has_method("has_gasoline") and player.has_gasoline():
			return "Press [E] to pour gasoline (%d/%d)" % [burnt_count, required_rats]
		return "Sacrifice Pit (%d/%d Rats Sacrificed). Place rat & pour gasoline to burn." % [burnt_count, required_rats]

func interact(player: Node) -> bool:
	if is_burning or is_ritual_ready():
		return false

	# Step 3: Ignite if both rat placed and gasoline poured
	if has_rat_placed and has_fuel:
		_start_burn()
		return true

	# Step 1 or 2: Pour gasoline if held and not yet fueled
	if player and player.has_method("has_gasoline") and player.has_gasoline() and not has_fuel:
		if player.consume_gasoline():
			has_fuel = true
			_update_visuals()
			print("[SacrificePit] Gasoline poured into the sacrifice pit!")
			return true

	# Step 1 or 2: Place rat if held and not yet placed
	if player and player.has_method("get_rat_count") and player.get_rat_count() > 0 and not has_rat_placed:
		if player.consume_rat():
			has_rat_placed = true
			_spawn_placed_rat()
			_update_visuals()
			print("[SacrificePit] Rat placed on sacrifice pit!")
			return true

	return false

func _spawn_placed_rat() -> void:
	if _placed_rat_instance and is_instance_valid(_placed_rat_instance):
		_placed_rat_instance.queue_free()
		_placed_rat_instance = null
	
	if rat_scene and rat_visual_mount:
		_placed_rat_instance = rat_scene.instantiate() as Node3D
		# Mark as placed so it lies motionless and cannot be caught
		if "is_placed_on_pit" in _placed_rat_instance:
			_placed_rat_instance.is_placed_on_pit = true
		_placed_rat_instance.position = Vector3.ZERO
		rat_visual_mount.add_child(_placed_rat_instance)

func _start_burn() -> void:
	is_burning = true
	_burn_timer = 1.5
	if fire_audio:
		fire_audio.play()
	_update_visuals()
	print("[SacrificePit] Ignited! Consuming sacrificial offering...")

func _finish_burn() -> void:
	is_burning = false
	has_rat_placed = false
	has_fuel = false
	if _placed_rat_instance and is_instance_valid(_placed_rat_instance):
		_placed_rat_instance.queue_free()
		_placed_rat_instance = null
	if fire_audio:
		fire_audio.stop()
	
	burnt_count += 1
	_update_visuals()
	emit_signal("rat_burnt", burnt_count)
	print("[SacrificePit] Offering burned! Burnt count: %d/%d" % [burnt_count, required_rats])
	
	if burnt_count >= required_rats:
		emit_signal("ritual_complete")

func _update_visuals() -> void:
	if fuel_visual:
		fuel_visual.visible = has_fuel or is_burning
	if flame_light:
		flame_light.visible = is_burning
	if pit_light:
		if is_burning:
			pit_light.light_color = Color(1.0, 0.4, 0.1)
			pit_light.light_energy = 3.0
		elif is_ritual_ready():
			pit_light.light_color = Color(0.9, 0.2, 1.0) # Violet victory
			pit_light.light_energy = 2.5
		elif has_fuel and has_rat_placed:
			pit_light.light_color = Color(1.0, 0.6, 0.2)
			pit_light.light_energy = 1.2
		else:
			pit_light.light_color = Color(0.8, 0.35, 0.15)
			pit_light.light_energy = 0.5 + float(burnt_count) * 0.15
