class_name UIHUD
extends CanvasLayer

@onready var prompt_label: Label = $CenterContainer/PromptLabel
@onready var rats_burnt_label: Label = $TopLeftMargin/VBox/OfferingsLabel
@onready var rat_bag_label: Label = $TopLeftMargin/VBox/BookLabel
@onready var keys_label: Label = $TopLeftMargin/VBox/InventoryLabel
@onready var lives_label: Label = $TopLeftMargin/VBox/LivesLabel

@onready var stamina_bar: ProgressBar = $BottomRightMargin/VBox/StaminaContainer/StaminaBar
@onready var uv_bar: ProgressBar = $BottomRightMargin/VBox/UVContainer/UVBar
@onready var flashlight_label: Label = $BottomRightMargin/VBox/FlashlightLabel

@onready var damage_overlay: ColorRect = $DamageOverlay
@onready var win_panel: PanelContainer = $WinPanel
@onready var loss_panel: PanelContainer = $LossPanel
@onready var pause_panel: PanelContainer = $PausePanel

var _damage_alpha: float = 0.0

func _ready() -> void:
	if win_panel: win_panel.visible = false
	if loss_panel: loss_panel.visible = false
	if pause_panel: pause_panel.visible = false
	if damage_overlay: damage_overlay.modulate.a = 0.0

func _process(delta: float) -> void:
	if _damage_alpha > 0.0:
		_damage_alpha = max(0.0, _damage_alpha - delta * 2.0)
		if damage_overlay:
			damage_overlay.modulate.a = _damage_alpha

func set_prompt(text: String) -> void:
	if prompt_label:
		prompt_label.text = text

func update_rats_burnt(burnt: int, max_val: int = 9) -> void:
	if rats_burnt_label:
		rats_burnt_label.text = "Rats Sacrificed: %d / %d" % [burnt, max_val]

func update_rat_inventory(carried: int, max_carried: int = 3) -> void:
	if rat_bag_label:
		rat_bag_label.text = "Rats in Bag: %d / %d" % [carried, max_carried]

func update_keys(keys_list: Array) -> void:
	if keys_label:
		if keys_list.is_empty():
			keys_label.text = "Keys Held: [None]"
		else:
			keys_label.text = "Keys Held: " + ", ".join(keys_list)

func update_lives(grabs_taken: int, max_grabs: int = 3) -> void:
	if lives_label:
		var hearts := ""
		var remaining = max(0, max_grabs - grabs_taken)
		for i in range(remaining):
			hearts += "♥ "
		for i in range(grabs_taken):
			hearts += "♡ "
		lives_label.text = "Sanity: %s (%d/%d grabs)" % [hearts.strip_edges(), grabs_taken, max_grabs]

func update_stamina(current: float, max_val: float) -> void:
	if stamina_bar:
		stamina_bar.max_value = max_val
		stamina_bar.value = current

func update_uv_battery(current: float, max_val: float) -> void:
	if uv_bar:
		uv_bar.max_value = max_val
		uv_bar.value = current

func update_flashlight(is_on: bool, is_uv: bool) -> void:
	if flashlight_label:
		if not is_on:
			flashlight_label.text = "Light: OFF [F to toggle]"
		elif is_uv:
			flashlight_label.text = "Light: UV FOCUS (FRYING) [RMB]"
		else:
			flashlight_label.text = "Light: Tactical White [RMB for UV]"

func flash_damage() -> void:
	_damage_alpha = 0.65

func show_win_screen() -> void:
	if win_panel:
		win_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func show_loss_screen() -> void:
	if loss_panel:
		loss_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func toggle_pause() -> void:
	if pause_panel:
		pause_panel.visible = not pause_panel.visible
		if pause_panel.visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
