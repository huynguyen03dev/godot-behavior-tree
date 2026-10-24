class_name Altar
extends StaticBody3D

signal rat_burnt(new_count: int)
signal ritual_complete

@export var required_rats: int = 9
var burnt_count: int = 0

@onready var altar_light: OmniLight3D = $AltarLight
@onready var flame_particles: OmniLight3D = $FlameLight
@onready var candle_lights: Node3D = $CandleLights
@onready var visual_root: Node3D = $Visual

var _burn_effect_timer: float = 0.0

func _ready() -> void:
	add_to_group("Altar")
	add_to_group("Interactable")
	# Collision: Layer 1 (World) | Layer 4 (Interactable bit 8)
	collision_layer = 1 | 8
	collision_mask = 0

	if visual_root and visual_root.get_node_or_null("AltarModel") == null:
		if ResourceLoader.exists("res://game/assets/models/altar.glb"):
			var altar_scene = load("res://game/assets/models/altar.glb")
			if altar_scene:
				var inst = altar_scene.instantiate()
				inst.name = "AltarModel"
				visual_root.add_child(inst)

	_update_visuals()

func _process(delta: float) -> void:
	if _burn_effect_timer > 0.0:
		_burn_effect_timer -= delta
		if flame_particles:
			flame_particles.visible = true
			flame_particles.light_energy = randf_range(3.0, 6.0)
	else:
		if flame_particles:
			flame_particles.visible = false

func get_burnt_count() -> int:
	return burnt_count

func is_ritual_ready() -> bool:
	return burnt_count >= required_rats

func get_interaction_text(player: Node = null) -> String:
	return "Ancient Altar (Decorative) — The Sacrifice Pit is in the Backyard!"

func interact(player: Node) -> bool:
	# Altar is now purely decorative. Ritual takes place at Sacrifice Pit in Backyard.
	return false

func _update_visuals() -> void:
	if altar_light:
		altar_light.light_energy = 0.6 + float(burnt_count) * 0.45
		if burnt_count >= required_rats:
			altar_light.light_color = Color(0.9, 0.2, 1.0) # Violet victory glow
		else:
			altar_light.light_color = Color(1.0, 0.35 + float(burnt_count) * 0.06, 0.1)

	if candle_lights:
		var candles = candle_lights.get_children()
		for i in range(candles.size()):
			if candles[i] is Light3D:
				candles[i].visible = (i < burnt_count or burnt_count == 0)
