@tool
class_name BTViewer
extends Control
## Generic Behavior Tree Editor & Viewer for Godot 4 Editor.
## Visualizes and edits Behavior Trees (`BTTree`) using Graph View, Hierarchy View,
## an interactive Inspector, and raw JSON code editing.
## Connects via `BTTreeSourceProvider` or directly loads generic `BTTree` models.

# Theme colors
const COLOR_ROOT := Color(0.42, 0.13, 0.66, 1.0)        # Violet / Purple
const COLOR_COMPOSITE := Color(0.11, 0.31, 0.85, 1.0)   # Blue
const COLOR_DECORATOR := Color(0.06, 0.46, 0.43, 1.0)   # Teal
const COLOR_ACTION := Color(0.02, 0.47, 0.34, 1.0)      # Emerald Green
const COLOR_CONDITION := Color(0.71, 0.33, 0.04, 1.0)   # Amber / Orange
const COLOR_PLACEHOLDER := Color(0.73, 0.11, 0.11, 1.0) # Red
const COLOR_PANEL_BG := Color(0.12, 0.13, 0.16, 1.0)

const GRAPH_X_GAP := 310.0
const GRAPH_Y_GAP := 130.0

# State
var undo_redo: UndoRedo = UndoRedo.new()
var _is_restoring_undo_redo: bool = false
var tree_source: BTTreeSourceProvider = null
var current_tree: BTTree = null
var current_tree_name: String = ""
var _json_draft: String = ""
var _json_draft_tree: BTTree = null
var _json_draft_modified := false
var _json_baseline := ""
var _model_baseline := ""
var _previous_tab := 0
var _pending_action: Callable
var _confirm_dialog: ConfirmationDialog
var _new_tree_dialog: ConfirmationDialog
var _new_tree_line_edit: LineEdit
var _save_as_dialog: FileDialog
var _save_as_confirm_dialog: ConfirmationDialog
var _pending_save_as_path: String = ""
var _delete_confirm_dialog: ConfirmationDialog
var _pending_delete_action: Callable
var _is_persisted_to_source: bool = false
var _persisted_source_name: String = ""
var _registry: BTTaskRegistry = null
var selected_node_id: int = -1

var _search_filter: String = ""
var _filter_placeholders_only: bool = false
var _graph_nodes_by_id: Dictionary = {} # id -> GraphNode
var _hierarchy_items: Dictionary = {} # id -> TreeItem
var _stats: Dictionary = {"total": 0, "root": 0, "composite": 0, "decorator": 0, "leaf": 0, "placeholder": 0}
var _suppress_inspector_rebuild: bool = false
var _is_rendering: bool = false
var _source_dialog: Window = null

# UI References - Toolbar
var _tree_option_button: OptionButton
var _reload_button: Button
var _save_button: Button
var _save_as_button: Button
var _source_button: Button
var _new_tree_button: Button
var _add_task_menu_button: MenuButton
var _frame_all_button: Button
var _search_line_edit: LineEdit
var _ph_check_box: CheckBox
var _tab_bar: TabBar
var _stats_label: Label
var _source_label: Label

# UI References - Central Views
var _view_container: PanelContainer
var _graph_edit: GraphEdit
var _hierarchy_tree: Tree
var _json_editor_container: VBoxContainer
var _json_text_edit: TextEdit
var _json_status_label: Label

# UI References - Inspector
var _inspector_panel: PanelContainer
var _inspector_container: VBoxContainer
var _inspector_title: Label
var _inspector_content: RichTextLabel
var _inspector_form_container: VBoxContainer
var _task_name_edit: LineEdit
var _params_container: VBoxContainer
var _bb_container: VBoxContainer

func _init() -> void:
	name = "BTViewer"
	anchor_right = 1.0
	anchor_bottom = 1.0
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(700, 400)
	_build_ui()

func _ensure_built() -> void:
	if _tree_option_button == null:
		_build_ui()
	if tree_source == null:
		var custom_provider_path: String = ProjectSettings.get_setting("behavior_tree/custom_source_provider", "")
		if custom_provider_path != "" and ResourceLoader.exists(custom_provider_path):
			var ProviderScript = load(custom_provider_path)
			if ProviderScript != null:
				var provider = ProviderScript.new()
				if provider is BTTreeSourceProvider:
					# Apply directly: the initial wiring must never prompt for
					# unsaved changes (there is nothing loaded yet anyway).
					_apply_tree_source(provider)
					return
		# Default to a file source so the panel is usable right after the
		# plugin is enabled; the folder can be changed with "📁 Source…".
		var default_dir: String = "res://behavior_trees" if DirAccess.dir_exists_absolute("res://behavior_trees") else "res://"
		_apply_tree_source(BTFileTreeSource.new(default_dir))

func _ready() -> void:
	_ensure_built()

# ---------------------------------------------------------------- Public API
func undo() -> void:
	if undo_redo.has_undo():
		undo_redo.undo()

func redo() -> void:
	if undo_redo.has_redo():
		undo_redo.redo()

func has_undo() -> bool:
	return undo_redo.has_undo()

func has_redo() -> bool:
	return undo_redo.has_redo()

func clear_undo_history() -> void:
	undo_redo.clear_history()

func _shortcut_input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.is_pressed() or key_event.is_echo():
		return
	var is_ctrl := key_event.ctrl_pressed or key_event.meta_pressed
	if not is_ctrl:
		return

	if key_event.keycode == KEY_Z:
		if key_event.shift_pressed:
			redo()
		else:
			undo()
		if is_inside_tree():
			accept_event()
	elif key_event.keycode == KEY_Y and not key_event.shift_pressed:
		redo()
		if is_inside_tree():
			accept_event()

func _record_mutation(action_name: String, mutation_callable: Callable, keep_inspector: bool = false) -> void:
	if current_tree == null:
		return
	if _is_restoring_undo_redo:
		mutation_callable.call()
		return

	var before_selection := selected_node_id
	var before_snapshot := JSON.stringify(current_tree.to_dict(), "\t")
	if keep_inspector:
		_suppress_inspector_rebuild = true
	mutation_callable.call()
	if keep_inspector:
		_suppress_inspector_rebuild = false

	var after_selection := selected_node_id
	var after_snapshot := JSON.stringify(current_tree.to_dict(), "\t")
	if after_snapshot == before_snapshot:
		return

	undo_redo.create_action(action_name)
	undo_redo.add_do_method(_restore_snapshot.bind(after_snapshot, action_name == "Move Nodes", after_selection))
	undo_redo.add_undo_method(_restore_snapshot.bind(before_snapshot, action_name == "Move Nodes", before_selection))
	undo_redo.commit_action(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if undo_redo != null and is_instance_valid(undo_redo):
			undo_redo.free()
			undo_redo = null

func _restore_snapshot(snapshot: String, is_move_action: bool = false, target_selection: int = -2) -> void:
	if snapshot == "":
		return
	var parsed = JSON.parse_string(snapshot)
	if not (parsed is Dictionary):
		return
	_is_restoring_undo_redo = true

	var live_positions: Dictionary = {}
	if not is_move_action and current_tree != null and current_tree.metadata.has("node_positions"):
		for id in _graph_nodes_by_id.keys():
			var gn: GraphNode = _graph_nodes_by_id[id]
			if is_instance_valid(gn):
				live_positions[str(id)] = [gn.position_offset.x, gn.position_offset.y]

	var nodes_data: Array = parsed.get("nodes", [])
	var restored: BTTree
	if nodes_data.is_empty():
		restored = BTTree.new()
		restored.tree_name = str(parsed.get("tree_name", "Untitled Tree"))
		restored.description = str(parsed.get("description", ""))
		restored.metadata = parsed.get("metadata", {}).duplicate(true)
		restored.registry = _active_registry()
	else:
		restored = BTTree.from_dict(parsed, _active_registry())
	if restored != null:
		var parsed_name = str(parsed.get("tree_name", ""))
		if parsed_name != "":
			restored.tree_name = parsed_name
			current_tree_name = parsed_name
		elif current_tree_name != "":
			restored.tree_name = current_tree_name

		if not is_move_action and not live_positions.is_empty():
			var meta_pos = restored.metadata.get("node_positions", {})
			if not (meta_pos is Dictionary):
				meta_pos = {}
			else:
				meta_pos = meta_pos.duplicate(true)
			for id_str in live_positions.keys():
				if restored.get_node_by_id(int(id_str)) != null:
					meta_pos[id_str] = live_positions[id_str]
			restored.metadata["node_positions"] = meta_pos

		for n_dict in nodes_data:
			var nid: int = int(n_dict.get("id", -1))
			var t := restored.get_node_by_id(nid)
			if t != null:
				if n_dict.has("category"):
					t.category = str(n_dict.get("category"))
				if n_dict.has("is_placeholder"):
					t.is_placeholder = bool(n_dict.get("is_placeholder"))
		current_tree = restored
		_stats = current_tree.get_stats()
		_update_stats_label()
		_json_draft_modified = false
		_json_baseline = snapshot
		_json_draft = snapshot
		_json_draft_tree = current_tree
		if _json_text_edit != null:
			_json_text_edit.text = snapshot

		if target_selection != -2:
			selected_node_id = target_selection
		if selected_node_id >= 0 and current_tree.get_node_by_id(selected_node_id) == null:
			selected_node_id = -1

		_render_current_tree()
		if selected_node_id >= 0:
			select_node_by_id(selected_node_id)
		else:
			_update_inspector()
		_select_tree_option(current_tree_name)
	_is_restoring_undo_redo = false

func set_tree_source(p_source: BTTreeSourceProvider) -> void:
	if _tree_option_button == null:
		_build_ui()
	if _source_label != null:
		_source_label.visible = true
		_source_label.text = "Source: %s" % (p_source.get_source_name() if p_source != null else "None")
	# Switching the source discards the tree that is open, so it goes through
	# the same dirty-check as every other destructive action.
	if _has_unsaved_changes():
		_request_action(func(): _apply_tree_source(p_source))
	else:
		_apply_tree_source(p_source)

## Points the viewer at a folder of behavior tree JSON files.
func set_source_directory(dir_path: String) -> void:
	set_tree_source(BTFileTreeSource.new(dir_path))

func _apply_tree_source(p_source: BTTreeSourceProvider) -> void:
	tree_source = p_source
	clear_undo_history()
	_clear_views()
	current_tree = null
	current_tree_name = ""
	selected_node_id = -1
	_json_draft = ""
	_json_draft_tree = null
	_json_draft_modified = false
	_json_baseline = ""
	_model_baseline = ""
	_is_persisted_to_source = false
	_persisted_source_name = ""
	if _json_text_edit != null:
		_json_text_edit.text = ""
	if _source_label != null:
		_source_label.visible = true
		_source_label.text = "Source: %s" % (tree_source.get_source_name() if tree_source != null else "None")
	_render_current_tree()
	_refresh_tree_list()

func load_generic_tree(p_tree: BTTree, p_name: String = "", clear_undo: bool = true) -> bool:
	if p_tree == null:
		return false
	if clear_undo:
		clear_undo_history()
	_clear_views()
	if _json_draft_tree != null and _json_draft_tree != p_tree:
		_json_draft = ""
		_json_draft_tree = null
	current_tree = p_tree
	if p_name != "":
		current_tree_name = p_name
		if p_tree.tree_name != p_name:
			p_tree.tree_name = p_name
	else:
		current_tree_name = p_tree.tree_name
	_is_persisted_to_source = false
	_persisted_source_name = ""
	_json_draft_modified = false
	_json_baseline = JSON.stringify(p_tree.to_dict(), "\t")
	_model_baseline = _json_baseline
	_json_draft = _json_baseline
	_json_draft_tree = p_tree
	if _json_text_edit != null:
		_json_text_edit.text = _json_draft
	if "registry" in p_tree and p_tree.registry is BTTaskRegistry:
		_registry = p_tree.registry
	else:
		_registry = BTTaskRegistry.new()
	_reset_filters()
	if _add_task_menu_button != null:
		_setup_add_task_menu(_add_task_menu_button.get_popup())
	if _tree_option_button != null:
		for i in _tree_option_button.item_count:
			if _tree_option_button.get_item_text(i) == current_tree_name:
				_tree_option_button.select(i)
				break
	_stats = current_tree.get_stats()
	_update_stats_label()
	_render_current_tree()
	return true

func load_tree_by_name(p_name: String) -> bool:
	if tree_source == null:
		return false
	var tree := tree_source.load_tree(p_name)
	if tree == null:
		return false
	var ok := load_generic_tree(tree, p_name)
	if ok:
		_is_persisted_to_source = true
		_persisted_source_name = p_name
	return ok

func load_tree_file(p_file_path: String) -> bool:
	if tree_source == null:
		return false
	var tree := tree_source.load_tree(p_file_path)
	if tree == null:
		return false
	var base := p_file_path.get_file().get_basename()
	var ok := load_generic_tree(tree, base)
	if ok:
		_is_persisted_to_source = true
		_persisted_source_name = base
	return ok

func select_node_by_id(node_id: int) -> void:
	selected_node_id = node_id
	# Setting GraphNode.selected emits node_selected / node_deselected, which
	# would rebuild the inspector a second time. Suppress the handlers and
	# rebuild exactly once below.
	_suppress_inspector_rebuild = true
	for nid in _graph_nodes_by_id.keys():
		var gn: GraphNode = _graph_nodes_by_id[nid]
		gn.selected = (nid == node_id)
	_suppress_inspector_rebuild = false
	_update_inspector()

func set_search_filter(query: String) -> void:
	_search_filter = query.strip_edges().to_lower()
	_apply_filters()
	_render_hierarchy()

func set_placeholder_filter(only_placeholders: bool) -> void:
	_filter_placeholders_only = only_placeholders
	_apply_filters()
	_render_hierarchy()

func get_current_tree_stats() -> Dictionary:
	return _stats.duplicate()

# ---------------------------------------------------------------- UI Construction
func _build_ui() -> void:
	var root_vbox := VBoxContainer.new()
	root_vbox.anchor_right = 1.0
	root_vbox.anchor_bottom = 1.0
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root_vbox)

	# 1. Top Toolbar (2 clean responsive rows)
	var toolbar := PanelContainer.new()
	var tb_vbox := VBoxContainer.new()
	tb_vbox.add_theme_constant_override("separation", 4)
	toolbar.add_child(tb_vbox)
	root_vbox.add_child(toolbar)

	# Row 1: Tree selection & authoring actions
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	tb_vbox.add_child(row1)

	var label_select := Label.new()
	label_select.text = "Behavior Tree:"
	row1.add_child(label_select)

	_tree_option_button = OptionButton.new()
	_tree_option_button.custom_minimum_size = Vector2(220, 26)
	_tree_option_button.item_selected.connect(_on_tree_selected)
	row1.add_child(_tree_option_button)

	_reload_button = Button.new()
	_reload_button.text = "🔄 Reload"
	_reload_button.tooltip_text = "Reload current tree from source"
	_reload_button.pressed.connect(_on_reload_pressed)
	row1.add_child(_reload_button)

	_save_button = Button.new()
	_save_button.text = "💾 Save"
	_save_button.tooltip_text = "Save changes back to source file"
	_save_button.pressed.connect(_on_save_pressed)
	row1.add_child(_save_button)

	_save_as_button = Button.new()
	_save_as_button.text = "💾 Save As…"
	_save_as_button.tooltip_text = "Save current tree under a new name or file"
	_save_as_button.pressed.connect(_on_save_as_pressed)
	row1.add_child(_save_as_button)

	_source_button = Button.new()
	_source_button.text = "📁 Source…"
	_source_button.tooltip_text = "Choose the folder that holds the behavior tree JSON files"
	_source_button.pressed.connect(_on_source_button_pressed)
	row1.add_child(_source_button)

	_new_tree_button = Button.new()
	_new_tree_button.text = "＋ New"
	_new_tree_button.tooltip_text = "Create a new behavior tree with an empty Sequence root"
	_new_tree_button.pressed.connect(_on_new_tree_pressed)
	row1.add_child(_new_tree_button)

	row1.add_child(VSeparator.new())

	_add_task_menu_button = MenuButton.new()
	_add_task_menu_button.text = "Add Task"
	_add_task_menu_button.tooltip_text = "Insert a new task into the current behavior tree"
	_setup_add_task_menu(_add_task_menu_button.get_popup())
	row1.add_child(_add_task_menu_button)

	_frame_all_button = Button.new()
	_frame_all_button.text = "🎯 Frame All"
	_frame_all_button.tooltip_text = "Center view on all nodes"
	_frame_all_button.pressed.connect(_on_frame_all_pressed)
	row1.add_child(_frame_all_button)

	# Row 2: Search filter, options, and view tabs
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	tb_vbox.add_child(row2)

	var label_search := Label.new()
	label_search.text = "🔍 Filter:"
	row2.add_child(label_search)

	_search_line_edit = LineEdit.new()
	_search_line_edit.placeholder_text = "Filter task name or type..."
	_search_line_edit.custom_minimum_size = Vector2(200, 24)
	_search_line_edit.text_changed.connect(_on_search_changed)
	row2.add_child(_search_line_edit)

	_ph_check_box = CheckBox.new()
	_ph_check_box.text = "Placeholders Only ⚠️"
	_ph_check_box.toggled.connect(_on_placeholder_filter_toggled)
	row2.add_child(_ph_check_box)

	row2.add_child(VSeparator.new())

	_tab_bar = TabBar.new()
	_tab_bar.clip_tabs = false
	_tab_bar.add_tab("📊 Graph")
	_tab_bar.add_tab("🌳 Tree")
	_tab_bar.add_tab("📝 JSON")
	_tab_bar.tab_changed.connect(_on_tab_changed)
	row2.add_child(_tab_bar)

	_source_label = Label.new()
	_source_label.text = "Source: %s" % (tree_source.get_source_name() if tree_source != null else "None")
	_source_label.visible = true
	row2.add_child(_source_label)

	# 2. Central Split Container
	var hsplit := HSplitContainer.new()
	hsplit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(hsplit)

	# View Container (Left)
	_view_container = PanelContainer.new()
	_view_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view_container.size_flags_stretch_ratio = 2.4
	_view_container.custom_minimum_size = Vector2(400, 250)
	hsplit.add_child(_view_container)

	# GraphEdit
	_graph_edit = GraphEdit.new()
	_graph_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph_edit.right_disconnects = false
	_graph_edit.node_selected.connect(_on_graph_node_selected)
	_graph_edit.node_deselected.connect(_on_graph_node_deselected)
	_graph_edit.connection_request.connect(_on_graph_connection_request)
	_graph_edit.disconnection_request.connect(_on_graph_disconnection_request)
	_graph_edit.delete_nodes_request.connect(_on_graph_delete_nodes_request)
	if ClassDB.class_has_signal("GraphEdit", "end_node_move"):
		_graph_edit.end_node_move.connect(_on_graph_end_node_move)
	else:
		_graph_edit.node_added.connect(_on_graph_node_added)
	_view_container.add_child(_graph_edit)

	# Hierarchy Tree
	_hierarchy_tree = Tree.new()
	_hierarchy_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hierarchy_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hierarchy_tree.columns = 5
	_hierarchy_tree.set_column_title(0, "Node")
	_hierarchy_tree.set_column_title(1, "Type")
	_hierarchy_tree.set_column_title(2, "Category")
	_hierarchy_tree.set_column_title(3, "Status")
	_hierarchy_tree.set_column_title(4, "ID")
	_hierarchy_tree.column_titles_visible = true
	_hierarchy_tree.hide_root = false
	_hierarchy_tree.item_selected.connect(_on_hierarchy_item_selected)
	_hierarchy_tree.visible = false
	_view_container.add_child(_hierarchy_tree)

	# JSON Editor View
	_json_editor_container = VBoxContainer.new()
	_json_editor_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_json_editor_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_json_editor_container.visible = false

	var json_tb := HBoxContainer.new()
	var apply_json_btn := Button.new()
	apply_json_btn.text = "⚡ Apply JSON to Tree"
	apply_json_btn.pressed.connect(_on_apply_json_pressed)
	json_tb.add_child(apply_json_btn)

	var revert_json_btn := Button.new()
	revert_json_btn.text = "↩ Revert Draft"
	revert_json_btn.tooltip_text = "Discard unapplied JSON draft edits and restore from current tree"
	revert_json_btn.pressed.connect(_on_revert_json_draft_pressed)
	json_tb.add_child(revert_json_btn)

	_json_status_label = Label.new()
	_json_status_label.text = "Edit JSON directly and click 'Apply JSON to Tree'"
	_json_status_label.modulate = Color(0.7, 0.7, 0.7, 1.0)
	json_tb.add_child(_json_status_label)
	_json_editor_container.add_child(json_tb)

	_json_text_edit = TextEdit.new()
	_json_text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_json_text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_json_text_edit.text_changed.connect(func():
		if _json_draft_tree == current_tree and current_tree != null:
			_json_draft_modified = _json_text_edit.text != _json_baseline
	)
	_json_editor_container.add_child(_json_text_edit)
	_view_container.add_child(_json_editor_container)

	# Inspector Panel (Right)
	_inspector_panel = PanelContainer.new()
	_inspector_panel.custom_minimum_size = Vector2(340, 250)
	_inspector_panel.size_flags_horizontal = Control.SIZE_FILL
	_inspector_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspector_panel.size_flags_stretch_ratio = 1.0
	hsplit.add_child(_inspector_panel)

	# Add MarginContainer to pad inspector nicely
	var margin_c := MarginContainer.new()
	margin_c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin_c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin_c.add_theme_constant_override("margin_left", 8)
	margin_c.add_theme_constant_override("margin_right", 12)
	margin_c.add_theme_constant_override("margin_top", 8)
	margin_c.add_theme_constant_override("margin_bottom", 8)
	_inspector_panel.add_child(margin_c)

	_inspector_container = VBoxContainer.new()
	_inspector_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspector_container.add_theme_constant_override("separation", 6)
	margin_c.add_child(_inspector_container)

	_inspector_title = Label.new()
	_inspector_title.text = "Task Inspector"
	_inspector_title.add_theme_font_size_override("font_size", 14)
	_inspector_container.add_child(_inspector_title)
	_inspector_container.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inspector_container.add_child(scroll)

	_inspector_form_container = VBoxContainer.new()
	_inspector_form_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector_form_container.add_theme_constant_override("separation", 8)
	scroll.add_child(_inspector_form_container)

	_inspector_content = RichTextLabel.new()
	_inspector_content.fit_content = true
	_inspector_content.bbcode_enabled = true
	_inspector_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector_content.text = "[color=gray]Select a node in the graph or hierarchy to inspect and edit.[/color]"
	_inspector_form_container.add_child(_inspector_content)

	# 3. Bottom Status Bar
	var status_bar := PanelContainer.new()
	_stats_label = Label.new()
	_stats_label.text = "Ready."
	status_bar.add_child(_stats_label)
	root_vbox.add_child(status_bar)
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.dialog_text = "Discard unapplied changes?"
	_confirm_dialog.confirmed.connect(_confirm_pending_action)
	_confirm_dialog.canceled.connect(_cancel_pending_action)
	add_child(_confirm_dialog)

	_new_tree_dialog = ConfirmationDialog.new()
	_new_tree_dialog.title = "New Behavior Tree"
	_new_tree_dialog.ok_button_text = "Create"
	var ntd_vbox := VBoxContainer.new()
	var ntd_lbl := Label.new()
	ntd_lbl.text = "Tree Name:"
	ntd_vbox.add_child(ntd_lbl)
	_new_tree_line_edit = LineEdit.new()
	_new_tree_line_edit.custom_minimum_size = Vector2(250, 0)
	ntd_vbox.add_child(_new_tree_line_edit)
	_new_tree_dialog.add_child(ntd_vbox)
	_new_tree_dialog.confirmed.connect(_on_new_tree_dialog_confirmed)
	_new_tree_line_edit.text_submitted.connect(func(_t: String):
		_new_tree_dialog.hide()
		_on_new_tree_dialog_confirmed()
	)
	add_child(_new_tree_dialog)

	_save_as_dialog = FileDialog.new()
	_save_as_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_as_dialog.access = FileDialog.ACCESS_RESOURCES
	_save_as_dialog.filters = PackedStringArray(["*.json ; JSON Behavior Trees"])
	_save_as_dialog.title = "Save Behavior Tree As"
	_save_as_dialog.file_selected.connect(_on_save_as_file_selected)
	add_child(_save_as_dialog)

	_save_as_confirm_dialog = ConfirmationDialog.new()
	_save_as_confirm_dialog.title = "Confirm Overwrite"
	_save_as_confirm_dialog.dialog_text = "File already exists. Overwrite?"
	_save_as_confirm_dialog.confirmed.connect(_on_save_as_overwrite_confirmed)
	add_child(_save_as_confirm_dialog)

	_delete_confirm_dialog = ConfirmationDialog.new()
	_delete_confirm_dialog.title = "Confirm Deletion"
	_delete_confirm_dialog.confirmed.connect(_on_delete_confirmed)
	add_child(_delete_confirm_dialog)

func _setup_add_task_menu(popup: PopupMenu) -> void:
	popup.clear()
	if not popup.id_pressed.is_connected(_on_add_task_menu_item_pressed):
		popup.id_pressed.connect(_on_add_task_menu_item_pressed)
	var registry := _active_registry()
	for type_name in registry.get_registered_types():
		var category: String = registry.get_category(type_name)
		popup.add_item("%s (%s)" % [type_name, category], 1000 + popup.item_count)
		popup.set_item_metadata(popup.item_count - 1, type_name)

# ---------------------------------------------------------------- Tree List & Switching
func _refresh_tree_list() -> void:
	_tree_option_button.clear()
	if tree_source == null:
		return
	var trees: Array = tree_source.list_trees()
	for i in trees.size():
		_tree_option_button.add_item(trees[i], i)
	if trees.is_empty():
		_stats_label.text = "⚠️ No Behavior Trees found in source."
	else:
		var loaded := false
		for i in trees.size():
			if load_tree_by_name(trees[i]):
				_tree_option_button.select(i)
				loaded = true
				break
		if not loaded:
			_stats_label.text = "❌ Failed to load tree '%s'" % trees[0]

func _select_tree_option(name: String) -> void:
	if _tree_option_button == null:
		return
	for i in _tree_option_button.item_count:
		if _tree_option_button.get_item_text(i) == name:
			_tree_option_button.select(i)
			return

## Rebuilds the tree dropdown without changing the loaded tree.
func _sync_tree_options() -> void:
	if tree_source == null or _tree_option_button == null:
		return
	var current := current_tree_name
	_tree_option_button.clear()
	for t in tree_source.list_trees():
		_tree_option_button.add_item(t)
	_select_tree_option(current)

func _on_tree_selected(idx: int) -> void:
	var tname := _tree_option_button.get_item_text(idx)
	var previous_name := current_tree_name
	_request_action(func(): load_tree_by_name(tname))
	if _confirm_dialog.visible:
		for i in _tree_option_button.item_count:
			if _tree_option_button.get_item_text(i) == previous_name:
				_tree_option_button.select(i)
				break

func _on_reload_pressed() -> void:
	# Rescan the source first so files added since the last scan show up.
	if tree_source != null and tree_source.has_method("refresh"):
		tree_source.refresh()
		_sync_tree_options()
	if current_tree_name != "":
		var tree_name := current_tree_name
		_request_action(func(): _reload_tree(tree_name))

func _reload_tree(tree_name: String) -> void:
	var loaded := load_tree_by_name(tree_name)
	if not loaded:
		_json_draft_modified = false
		if current_tree != null:
			var serialized := JSON.stringify(current_tree.to_dict(), "\t")
			_json_draft = serialized
			_json_baseline = serialized
			_json_draft_tree = current_tree
			if _json_text_edit != null:
				_json_text_edit.text = serialized
			if _stats_label != null:
				_stats_label.text = "⚠️ Tree '%s' not found on disk; discarded unapplied draft." % tree_name
		else:
			if _stats_label != null:
				_stats_label.text = "❌ Failed to reload tree '%s'." % tree_name

func _on_revert_json_draft_pressed() -> void:
	revert_json_draft()

func revert_json_draft() -> void:
	if current_tree == null:
		return
	var serialized := JSON.stringify(current_tree.to_dict(), "\t")
	_json_draft = serialized
	_json_baseline = serialized
	_json_draft_tree = current_tree
	_json_draft_modified = false
	if _json_text_edit != null:
		_json_text_edit.text = serialized
	if _json_status_label != null:
		_json_status_label.text = "Draft reverted to current tree."
		_json_status_label.modulate = Color(0.7, 0.7, 0.7, 1.0)

func _on_save_pressed() -> void:
	save_current_tree()

func _on_save_as_pressed() -> void:
	if current_tree == null:
		return
	if _save_as_dialog == null:
		return
	var default_filename := "%s.json" % current_tree_name
	_save_as_dialog.current_file = default_filename
	_save_as_dialog.popup_centered_ratio(0.6)

func _on_save_as_file_selected(path: String) -> void:
	if path.strip_edges() == "":
		return
	var target_tree_name := path.get_file().get_basename()
	var is_different_existing := false
	if FileAccess.file_exists(path) and (target_tree_name != _persisted_source_name or not _is_persisted_to_source):
		is_different_existing = true
	elif tree_source != null and tree_source.list_trees().has(target_tree_name) and (target_tree_name != _persisted_source_name or not _is_persisted_to_source):
		is_different_existing = true

	if is_different_existing:
		_pending_save_as_path = path
		if _save_as_confirm_dialog != null:
			_save_as_confirm_dialog.dialog_text = "File '%s' already exists for a different tree. Overwrite?" % path.get_file()
			_save_as_confirm_dialog.popup_centered()
		return
	save_tree_as(path)

func _on_save_as_overwrite_confirmed() -> void:
	if _save_as_confirm_dialog != null:
		_save_as_confirm_dialog.hide()
	if _pending_save_as_path != "":
		var path := _pending_save_as_path
		_pending_save_as_path = ""
		save_tree_as(path)

func save_tree_as(target_path: String) -> bool:
	if current_tree == null:
		return false
	if _json_draft_modified:
		if _stats_label != null:
			_stats_label.text = "Unapplied JSON edits; apply JSON before saving."
		return false
	var new_name := target_path.get_file().get_basename()
	if new_name == "":
		new_name = target_path
	current_tree.tree_name = new_name
	current_tree_name = new_name

	var ok := false
	if tree_source != null:
		var identifier := target_path if (target_path.contains("/") or target_path.ends_with(".json")) else new_name
		ok = tree_source.save_tree(identifier, current_tree)
		if not ok and tree_source is BTMemoryTreeSource:
			ok = tree_source.save_tree(new_name, current_tree)
	if not ok and (target_path.begins_with("res://") or target_path.begins_with("user://") or target_path.is_absolute_path()):
		var dir := target_path.get_base_dir()
		if dir != "" and not DirAccess.dir_exists_absolute(dir):
			DirAccess.make_dir_recursive_absolute(dir)
		var file = FileAccess.open(target_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(current_tree.to_dict(), "\t"))
			file.close()
			ok = true

	if ok:
		_is_persisted_to_source = true
		_persisted_source_name = new_name
		_model_baseline = JSON.stringify(current_tree.to_dict(), "\t")
		if _stats_label != null:
			_stats_label.text = "✅ Saved tree as '%s' successfully." % new_name
		_sync_tree_options()
	else:
		if _stats_label != null:
			var last_err = tree_source.get("last_error") if tree_source != null else ""
			if last_err is String and not last_err.is_empty():
				_stats_label.text = "❌ %s" % last_err
			else:
				_stats_label.text = "❌ Failed to save tree as '%s'." % new_name
	return ok

func can_auto_save() -> bool:
	if current_tree == null or tree_source == null:
		return false
	if not _is_persisted_to_source:
		return false
	if _persisted_source_name == "" or _persisted_source_name != current_tree_name:
		return false
	return true

func auto_save_external_data() -> bool:
	if not can_auto_save():
		if current_tree != null and not _is_persisted_to_source:
			if _stats_label != null:
				_stats_label.text = "ℹ️ Skipped autosave for unsaved tree '%s'." % current_tree_name
		return false
	return save_current_tree()

## Writes the model through the provider.
## Returns true when the tree was written.
func save_current_tree() -> bool:
	if current_tree == null or tree_source == null:
		return false
	if _json_draft_modified:
		_stats_label.text = "Unapplied JSON edits; apply JSON before saving."
		return false
	var ok: bool = tree_source.save_tree(current_tree_name, current_tree)
	if ok:
		_is_persisted_to_source = true
		_persisted_source_name = current_tree_name
		_model_baseline = JSON.stringify(current_tree.to_dict(), "\t")
		_stats_label.text = "✅ Saved tree '%s' successfully." % current_tree_name
		_sync_tree_options()
	else:
		var last_err = tree_source.get("last_error")
		if last_err is String and not last_err.is_empty():
			_stats_label.text = "❌ %s" % last_err
		else:
			_stats_label.text = "❌ Failed to save tree '%s'." % current_tree_name
	return ok

func _on_tab_changed(tab: int) -> void:
	if _previous_tab == 2 and _json_text_edit != null and current_tree != null:
		_json_draft = _json_text_edit.text
		_json_draft_tree = current_tree
		_json_draft_modified = _json_draft != _json_baseline
	_graph_edit.visible = (tab == 0)
	_hierarchy_tree.visible = (tab == 1)
	_json_editor_container.visible = (tab == 2)
	if tab == 2 and current_tree != null:
		var serialized := JSON.stringify(current_tree.to_dict(), "\t")
		if _json_draft_tree != current_tree or not _json_draft_modified:
			_json_draft = serialized
			_json_draft_tree = current_tree
			_json_baseline = serialized
		_json_text_edit.text = _json_draft
	_previous_tab = tab

func _on_apply_json_pressed() -> void:
	if _json_text_edit.text.strip_edges() == "":
		return
	var json = JSON.new()
	var error = json.parse(_json_text_edit.text)
	if error != OK:
		_json_status_label.text = "❌ JSON Parse Error: %s (line %d)" % [json.get_error_message(), json.get_error_line()]
		_json_status_label.modulate = COLOR_PLACEHOLDER
		return
	var parsed_data = json.data
	if not (parsed_data is Dictionary):
		_json_status_label.text = "❌ Root JSON must be an Object/Dictionary."
		_json_status_label.modulate = COLOR_PLACEHOLDER
		return
	if not parsed_data.has("nodes") or not parsed_data.nodes is Array or parsed_data.nodes.is_empty():
		_json_status_label.text = "❌ Tree must contain a non-empty 'nodes' array."
		_json_status_label.modulate = COLOR_PLACEHOLDER
		return
	var errors: PackedStringArray = BTTree.validate_dict(parsed_data, _active_registry())
	if not errors.is_empty():
		_json_status_label.text = "❌ Invalid tree: %s" % errors[0]
		_json_status_label.modulate = COLOR_PLACEHOLDER
		return
	var new_tree = BTTree.from_dict(parsed_data, _active_registry())
	if new_tree == null:
		_json_status_label.text = "❌ Tree data is invalid; current tree was not changed."
		_json_status_label.modulate = COLOR_PLACEHOLDER
		return
	# The JSON tab can go stale: the Inspector stays editable while the JSON
	# tab is open, so the model may have changed since this text was captured.
	if current_tree != null and JSON.stringify(current_tree.to_dict(), "\t") != _json_baseline:
		_pending_action = _apply_parsed_tree.bind(new_tree)
		_confirm_dialog.dialog_text = "The model changed since this JSON was captured; applying discards those changes. Continue?"
		_confirm_dialog.popup_centered()
		return
	_apply_parsed_tree(new_tree)

func _apply_parsed_tree(new_tree: BTTree) -> void:
	_record_mutation("Apply JSON", func():
		var target_name := new_tree.tree_name if new_tree.tree_name.strip_edges() != "" else current_tree_name
		var persisted_model_baseline := _model_baseline
		load_generic_tree(new_tree, target_name, false)
		current_tree_name = target_name
		_model_baseline = persisted_model_baseline
		_json_baseline = JSON.stringify(current_tree.to_dict(), "\t")
		_json_draft = _json_baseline
		_json_draft_tree = current_tree
		_json_draft_modified = false
		if _json_text_edit != null:
			_json_text_edit.text = _json_draft
		_json_status_label.text = "✅ Tree updated successfully from JSON!"
		_json_status_label.modulate = COLOR_ACTION
		_sync_tree_options()
	)

func _on_search_changed(query: String) -> void:
	set_search_filter(query)

func _on_placeholder_filter_toggled(pressed: bool) -> void:
	set_placeholder_filter(pressed)

func _on_frame_all_pressed() -> void:
	if _graph_nodes_by_id.is_empty():
		return
	var min_pos := Vector2(999999, 999999)
	for gn in _graph_nodes_by_id.values():
		min_pos.x = min(min_pos.x, gn.position_offset.x)
		min_pos.y = min(min_pos.y, gn.position_offset.y)
	_graph_edit.scroll_offset = min_pos - Vector2(40, 40)

# ---------------------------------------------------------------- Source & New Tree
## Opens a folder picker so the user can point the editor at the folder that
## holds the behavior tree JSON files.
func _on_source_button_pressed() -> void:
	if _source_dialog != null and is_instance_valid(_source_dialog):
		_source_dialog.popup_centered_ratio(0.6)
		return
	# EditorFileDialog is only available inside the editor and only there it
	# can browse res://; everywhere else the plain FileDialog is used.
	var picker_class := "FileDialog"
	if Engine.is_editor_hint() and ClassDB.class_exists("EditorFileDialog"):
		picker_class = "EditorFileDialog"
	if not ClassDB.class_exists(picker_class):
		_stats_label.text = "❌ No folder picker is available in this build."
		return
	var instance = ClassDB.instantiate(picker_class)
	if instance == null or not (instance is Window):
		_stats_label.text = "❌ Could not open the folder picker."
		return
	var dialog: Window = instance
	dialog.set("access", ClassDB.class_get_integer_constant(picker_class, "ACCESS_RESOURCES"))
	dialog.set("file_mode", ClassDB.class_get_integer_constant(picker_class, "FILE_MODE_OPEN_DIR"))
	dialog.set("title", "Choose Behavior Tree Folder")
	dialog.connect("dir_selected", _on_source_dir_selected)
	add_child(dialog)
	_source_dialog = dialog
	dialog.popup_centered_ratio(0.6)

func _on_source_dir_selected(dir_path: String) -> void:
	if _source_dialog != null and is_instance_valid(_source_dialog):
		_source_dialog.queue_free()
		_source_dialog = null
	if dir_path == "":
		return
	set_source_directory(dir_path)

## Returns all tree names currently known from the source, dropdown, and active tree.
func _get_existing_tree_names() -> Array[String]:
	var names: Array[String] = []
	if tree_source != null:
		for t in tree_source.list_trees():
			if not names.has(str(t)):
				names.append(str(t))
	if _tree_option_button != null:
		for i in _tree_option_button.item_count:
			var item_text := _tree_option_button.get_item_text(i)
			if not names.has(item_text):
				names.append(item_text)
	if current_tree_name != "" and not names.has(current_tree_name):
		names.append(current_tree_name)
	return names

## Finds the first unused name of form prefix, prefix_1, prefix_2...
func _get_next_unused_tree_name(prefix: String = "new_tree") -> String:
	var existing := _get_existing_tree_names()
	if not existing.has(prefix):
		return prefix
	var idx := 1
	while true:
		var candidate := "%s_%d" % [prefix, idx]
		if not existing.has(candidate):
			return candidate
		idx += 1
	return prefix

## Creates a new tree with an empty Sequence root. The tree stays dirty until
## it is saved to the source.
func _on_new_tree_pressed() -> void:
	_request_action(_prompt_new_tree)

func _prompt_new_tree() -> void:
	var default_name := _get_next_unused_tree_name()
	if _new_tree_line_edit != null:
		_new_tree_line_edit.text = default_name
	if _new_tree_dialog != null:
		_new_tree_dialog.popup_centered()

func _on_new_tree_dialog_confirmed() -> void:
	if _new_tree_dialog != null:
		_new_tree_dialog.hide()
	var chosen_name := _new_tree_line_edit.text.strip_edges() if _new_tree_line_edit != null else ""
	if chosen_name == "":
		chosen_name = _get_next_unused_tree_name()
	_create_new_tree(chosen_name)

func _create_new_tree(p_name: String = "") -> void:
	if p_name.strip_edges() == "":
		p_name = _get_next_unused_tree_name()
	var tree := BTTree.new()
	var root_task := BTComposite.BTSequence.new()
	root_task.id = 1
	root_task.friendly_name = "Root"
	root_task.category = "Root"
	tree.tree_name = p_name
	tree.set_root(root_task)
	load_generic_tree(tree, p_name)
	_is_persisted_to_source = false
	_persisted_source_name = ""
	if _tree_option_button != null:
		var found_idx := -1
		for i in _tree_option_button.item_count:
			if _tree_option_button.get_item_text(i) == p_name:
				found_idx = i
				break
		if found_idx >= 0:
			_tree_option_button.select(found_idx)
		else:
			_tree_option_button.add_item(p_name)
			_tree_option_button.select(_tree_option_button.item_count - 1)
	# Nothing has been written to the source yet, so the tree counts as dirty.
	_model_baseline = ""
	_stats_label.text = "🆕 Created '%s'. Save to write it to the source." % p_name

# ---------------------------------------------------------------- Node Adding & Editing
func _on_add_task_menu_item_pressed(id: int) -> void:
	if current_tree == null:
		return
	var registry := _active_registry()
	var popup := _add_task_menu_button.get_popup()
	var type_name := ""
	for i in popup.item_count:
		if popup.get_item_id(i) == id:
			type_name = str(popup.get_item_metadata(i))
			break
	if type_name == "":
		# Unknown menu entry: do not silently fall back to a Sequence.
		_stats_label.text = "❌ Unknown task type in the Add Task menu."
		return
	var category: String = registry.get_category(type_name)

	var new_task := registry.create_task(type_name)
	if new_task == null:
		return
	new_task.friendly_name = type_name
	new_task.category = category

	# Generate new unique ID
	var max_id := 0
	for t in current_tree.node_list:
		if t != null and t.id > max_id:
			max_id = t.id
	new_task.id = max_id + 1

	# Attach the new task so it is reachable from the root instead of floating
	# in the graph as an invisible orphan.
	_record_mutation("Add Task", func():
		var parent := _find_attachment_parent()
		if parent == null:
			if current_tree.root_task != null:
				_stats_label.text = "Cannot attach: root '%s' cannot take children; select a node that can take children" % current_tree.root_task.friendly_name
				return
			current_tree.add_node(new_task)
			current_tree.set_root(new_task)
		else:
			current_tree.add_node(new_task)
			current_tree.connect_parent_child(parent, new_task)
			if new_task.parent != parent:
				_stats_label.text = "⚠️ Could not attach the new task; it was added as an unattached node."
		_stats = current_tree.get_stats()
		_update_stats_label()
		_render_current_tree()
		select_node_by_id(new_task.id)
	)

## The node a newly added task should be attached to: the selected node when it
## can hold children, otherwise the root.
func _find_attachment_parent() -> BTTask:
	if current_tree == null:
		return null
	if selected_node_id >= 0:
		var selected := current_tree.get_node_by_id(selected_node_id)
		if selected != null and _can_accept_child(selected):
			return selected
	if current_tree.root_task != null and _can_accept_child(current_tree.root_task):
		return current_tree.root_task
	return null

## Whether a task can take another task as a child.
func _can_accept_child(task: BTTask) -> bool:
	if task == null:
		return false
	if task is BTParentTask:
		if task is BTDecorator:
			return (task as BTParentTask).children.is_empty()
		return true
	return false

# ---------------------------------------------------------------- Rendering
func _render_current_tree() -> void:
	if current_tree == null:
		_clear_views()
		_update_inspector()
		return

	_is_rendering = true
	_render_graph()
	_is_rendering = false
	_render_hierarchy()
	_apply_filters()
	_update_inspector()

func _clear_views() -> void:
	_graph_edit.clear_connections()
	for child in _graph_edit.get_children().duplicate():
		if child is GraphNode:
			child.free()
	_graph_nodes_by_id.clear()
	_hierarchy_tree.clear()
	_hierarchy_items.clear()
	selected_node_id = -1

func _render_graph() -> void:
	if current_tree == null or current_tree.node_list.is_empty():
		_graph_edit.clear_connections()
		for id in _graph_nodes_by_id.keys():
			var node = _graph_nodes_by_id[id]
			if is_instance_valid(node):
				node.free()
		_graph_nodes_by_id.clear()
		return

	var positions := _compute_tree_layout()
	_lay_out_orphans(positions)
	_apply_saved_positions(positions)

	var current_ids := {}
	for task in current_tree.node_list:
		if task != null:
			current_ids[task.id] = true

	# Free nodes that disappeared
	var stale_ids: Array = []
	for old_id in _graph_nodes_by_id.keys():
		if not current_ids.has(old_id):
			stale_ids.append(old_id)
	for old_id in stale_ids:
		var node = _graph_nodes_by_id[old_id]
		if is_instance_valid(node):
			node.free()
		_graph_nodes_by_id.erase(old_id)

	# Update existing nodes or create new ones
	for task in current_tree.node_list:
		if task == null:
			continue
		var is_root: bool = (task == current_tree.root_task or task.category == "Root")
		var is_parent: bool = (task is BTParentTask or ("children" in task and not task.children.is_empty()) or task.category == "Composite" or task.category == "Decorator")
		var has_input: bool = not is_root
		var has_output: bool = is_parent
		var slot_color: Color = COLOR_ROOT if is_root else _get_category_color(task.category)
		var pos: Vector2 = positions.get(task.id, Vector2(50, 50))

		var gnode: GraphNode = _graph_nodes_by_id.get(task.id, null)
		if gnode != null and is_instance_valid(gnode):
			gnode.title = "[%d] %s" % [task.id, task.friendly_name]
			gnode.position_offset = pos
			gnode.set_slot(0, has_input, 0, slot_color, has_output, 0, slot_color)
			# Update labels inside vbox
			var vbox: VBoxContainer = null
			for child in gnode.get_children():
				if child is VBoxContainer:
					vbox = child
					break
			if vbox != null:
				for child in vbox.get_children():
					child.free()
				var type_label := Label.new()
				type_label.text = task.type_name
				type_label.modulate = Color(0.85, 0.85, 0.85, 1.0)
				vbox.add_child(type_label)

				var cat_badge := Label.new()
				cat_badge.text = task.category.to_upper()
				cat_badge.add_theme_font_size_override("font_size", 10)
				cat_badge.modulate = _get_category_color(task.category)
				vbox.add_child(cat_badge)

				if task.is_placeholder:
					var ph_badge := Label.new()
					ph_badge.text = "⚠️ PLACEHOLDER"
					ph_badge.add_theme_font_size_override("font_size", 10)
					ph_badge.modulate = COLOR_PLACEHOLDER
					vbox.add_child(ph_badge)
		else:
			gnode = GraphNode.new()
			gnode.name = "Node_%d" % task.id
			gnode.title = "[%d] %s" % [task.id, task.friendly_name]
			gnode.resizable = false
			gnode.draggable = true
			gnode.position_offset = pos

			var vbox := VBoxContainer.new()
			var type_label := Label.new()
			type_label.text = task.type_name
			type_label.modulate = Color(0.85, 0.85, 0.85, 1.0)
			vbox.add_child(type_label)

			var cat_badge := Label.new()
			cat_badge.text = task.category.to_upper()
			cat_badge.add_theme_font_size_override("font_size", 10)
			cat_badge.modulate = _get_category_color(task.category)
			vbox.add_child(cat_badge)

			if task.is_placeholder:
				var ph_badge := Label.new()
				ph_badge.text = "⚠️ PLACEHOLDER"
				ph_badge.add_theme_font_size_override("font_size", 10)
				ph_badge.modulate = COLOR_PLACEHOLDER
				vbox.add_child(ph_badge)

			gnode.add_child(vbox)
			gnode.set_slot(0, has_input, 0, slot_color, has_output, 0, slot_color)
			_graph_edit.add_child(gnode)
			_graph_nodes_by_id[task.id] = gnode

	# Connections
	_graph_edit.clear_connections()
	for task in current_tree.node_list:
		if task == null:
			continue
		var kids: Array = []
		if "children" in task and task.children is Array:
			kids = task.children

		for child in kids:
			if child != null and "id" in child:
				var from_name := "Node_%d" % task.id
				var to_name := "Node_%d" % child.id
				if _graph_nodes_by_id.has(task.id) and _graph_nodes_by_id.has(child.id):
					_graph_edit.connect_node(from_name, 0, to_name, 0)

func _is_task_matching_filter(task: BTTask) -> bool:
	if task == null:
		return false
	var match_search := true
	if _search_filter != "":
		var text_content: String = (str(task.friendly_name) + " " + str(task.type_name) + " " + str(task.category)).to_lower()
		match_search = text_content.contains(_search_filter)

	var match_ph := true
	if _filter_placeholders_only:
		match_ph = task.is_placeholder
	return match_search and match_ph

func _collect_filtered_tree_info() -> Dictionary:
	var matching_ids := {}
	var ancestor_ids := {}
	var has_filter := (_search_filter != "" or _filter_placeholders_only)
	if not has_filter or current_tree == null:
		return {"has_filter": has_filter, "matching": matching_ids, "ancestors": ancestor_ids}

	# Identify matching nodes
	for task in current_tree.node_list:
		if task != null and _is_task_matching_filter(task):
			matching_ids[task.id] = true
			var curr: BTTask = task.parent
			while curr != null:
				ancestor_ids[curr.id] = true
				curr = curr.parent

	return {"has_filter": has_filter, "matching": matching_ids, "ancestors": ancestor_ids}

func _render_hierarchy() -> void:
	_hierarchy_tree.clear()
	_hierarchy_items.clear()
	if current_tree == null or current_tree.node_list.is_empty():
		return

	var filter_info := _collect_filtered_tree_info()
	var root_task := current_tree.root_task
	if root_task == null:
		root_task = current_tree.node_list[0]

	_add_hierarchy_item_recursive(null, root_task, filter_info)

	# Nodes that are not reachable from the root are listed separately so they
	# are not invisible in the hierarchy.
	var orphans := _collect_orphan_tasks()
	if not orphans.is_empty():
		var group: TreeItem = null
		for orphan in orphans:
			if not filter_info.has_filter or filter_info.matching.has(orphan.id) or filter_info.ancestors.has(orphan.id):
				if group == null:
					group = _hierarchy_tree.create_item()
					group.set_text(0, "(unattached)")
					group.set_custom_color(0, COLOR_PLACEHOLDER)
				_add_hierarchy_item_recursive(group, orphan, filter_info)

func _add_hierarchy_item_recursive(parent_item: TreeItem, task: BTTask, filter_info: Dictionary = {}) -> void:
	if task == null:
		return

	var has_filter: bool = filter_info.get("has_filter", false)
	var is_match: bool = true
	var is_ancestor_only: bool = false
	if has_filter:
		var matching: Dictionary = filter_info.get("matching", {})
		var ancestors: Dictionary = filter_info.get("ancestors", {})
		var in_matching := matching.has(task.id)
		var in_ancestors := ancestors.has(task.id)
		if not in_matching and not in_ancestors:
			return
		if in_matching:
			is_match = true
		else:
			is_ancestor_only = true

	var item := _hierarchy_tree.create_item(parent_item)
	item.set_metadata(0, task.id)
	item.set_text(0, task.friendly_name)
	item.set_text(1, task.type_name)
	item.set_text(2, task.category)
	item.set_text(3, "⚠️ Placeholder" if task.is_placeholder else "Ready")
	item.set_text(4, str(task.id))

	if is_ancestor_only:
		var dim_color := Color(0.6, 0.6, 0.6, 0.5)
		item.set_custom_color(0, dim_color)
		item.set_custom_color(1, dim_color)
		item.set_custom_color(2, dim_color)
		item.set_custom_color(3, dim_color)
		item.set_custom_color(4, dim_color)
	else:
		var color := COLOR_ROOT if task == current_tree.root_task else _get_category_color(task.category)
		item.set_custom_color(0, color)
		item.set_custom_color(3, COLOR_PLACEHOLDER if task.is_placeholder else COLOR_ACTION)

	_hierarchy_items[task.id] = item

	var kids: Array = []
	if "children" in task and task.children is Array:
		kids = task.children

	for child in kids:
		if child != null:
			_add_hierarchy_item_recursive(item, child, filter_info)

# ---------------------------------------------------------------- Layout Calculation
func _compute_tree_layout() -> Dictionary:
	var positions := {}
	var root_task := current_tree.root_task
	if root_task == null and not current_tree.node_list.is_empty():
		root_task = current_tree.node_list[0]
	if root_task == null:
		return positions

	var current_y := 0.0
	var depth_map := {}
	var y_map := {}

	_layout_dfs(root_task, 0, depth_map, y_map, [current_y])

	for id in depth_map.keys():
		var depth = depth_map[id]
		var y_val = y_map[id]
		positions[id] = Vector2(40.0 + depth * GRAPH_X_GAP, 40.0 + y_val * GRAPH_Y_GAP)

	return positions

func _layout_dfs(task: BTTask, depth: int, depth_map: Dictionary, y_map: Dictionary, next_y_ref: Array) -> float:
	depth_map[task.id] = depth
	var kids: Array = []
	if "children" in task and task.children is Array:
		kids = task.children

	if kids.is_empty():
		var my_y: float = next_y_ref[0]
		y_map[task.id] = my_y
		next_y_ref[0] = my_y + 1.0
		return my_y

	var child_ys: Array = []
	for child in kids:
		if child != null and "id" in child:
			var cy = _layout_dfs(child, depth + 1, depth_map, y_map, next_y_ref)
			child_ys.append(cy)

	var my_y: float = (child_ys.front() + child_ys.back()) / 2.0
	y_map[task.id] = my_y
	return my_y

# ---------------------------------------------------------------- Node Positions
## Saved graph positions, keyed by node id. The ids survive a JSON round trip
## as strings, so they are normalized on read.
func _get_saved_positions() -> Dictionary:
	if current_tree == null:
		return {}
	var saved = current_tree.metadata.get("node_positions", {})
	return saved if saved is Dictionary else {}

## Overrides the computed layout with the positions the user dragged the nodes
## to. Nodes without a saved position keep their auto layout.
func _apply_saved_positions(positions: Dictionary) -> void:
	var saved := _get_saved_positions()
	for key in saved.keys():
		var id := int(key)
		if current_tree == null or current_tree.get_node_by_id(id) == null:
			continue
		var entry = saved[key]
		if entry is Array and entry.size() == 2:
			positions[id] = Vector2(float(entry[0]), float(entry[1]))

func _are_positions_equal(a: Variant, b: Variant) -> bool:
	if not (a is Dictionary) or not (b is Dictionary):
		return false
	if a.size() != b.size():
		return false
	for k in a.keys():
		var str_k := str(k)
		var b_val = null
		if b.has(k):
			b_val = b[k]
		elif b.has(str_k):
			b_val = b[str_k]
		else:
			return false
		var a_val = a[k]
		if not (a_val is Array) or not (b_val is Array) or a_val.size() != 2 or b_val.size() != 2:
			return false
		if not is_equal_approx(float(a_val[0]), float(b_val[0])) or not is_equal_approx(float(a_val[1]), float(b_val[1])):
			return false
	return true

## Stores the current graph positions in the tree metadata. Ids of deleted
## nodes disappear because only the nodes currently in the graph are written.
func _save_node_positions(record_undo: bool = false) -> void:
	if current_tree == null or _is_rendering:
		return
	var new_positions := {}
	for id in _graph_nodes_by_id.keys():
		var gn: GraphNode = _graph_nodes_by_id[id]
		if is_instance_valid(gn):
			new_positions[str(id)] = [gn.position_offset.x, gn.position_offset.y]

	var old_positions = current_tree.metadata.get("node_positions", {})
	if record_undo and undo_redo != null and not _is_restoring_undo_redo:
		if not _are_positions_equal(old_positions, new_positions):
			_record_mutation("Move Nodes", func():
				current_tree.metadata["node_positions"] = new_positions.duplicate(true)
			, true)
			return

	current_tree.metadata["node_positions"] = new_positions

## Drops the saved positions of nodes that are no longer part of the tree.
func _prune_node_positions() -> void:
	if current_tree == null:
		return
	var saved := _get_saved_positions()
	if saved.is_empty():
		return
	var pruned := {}
	for key in saved.keys():
		if current_tree.get_node_by_id(int(key)) != null:
			pruned[key] = saved[key]
	current_tree.metadata["node_positions"] = pruned

func _on_graph_end_node_move() -> void:
	_save_node_positions(true)

## Fallback for engines without GraphEdit.end_node_move: every node reports
## its own position changes.
func _on_graph_node_added(node: Node) -> void:
	if node is GraphNode:
		(node as GraphNode).position_offset_changed.connect(_on_node_position_changed)

func _on_node_position_changed() -> void:
	_save_node_positions()

# ---------------------------------------------------------------- Orphans
## Tasks that cannot be reached from the root through the child links.
func _collect_orphan_tasks() -> Array:
	var orphans: Array = []
	if current_tree == null:
		return orphans
	var reachable := {}
	var root_task := current_tree.root_task
	if root_task == null and not current_tree.node_list.is_empty():
		root_task = current_tree.node_list[0]
	var stack: Array = []
	if root_task != null:
		stack.append(root_task)
	while not stack.is_empty():
		var task: BTTask = stack.pop_back()
		if task == null or reachable.has(task.id):
			continue
		reachable[task.id] = true
		if "children" in task and task.children is Array:
			for child in task.children:
				if child != null:
					stack.append(child)
	for task in current_tree.node_list:
		if task != null and not reachable.has(task.id):
			orphans.append(task)
	return orphans

## Places the unattached nodes in a band below the tree.
func _lay_out_orphans(positions: Dictionary) -> void:
	var orphans := _collect_orphan_tasks()
	if orphans.is_empty():
		return
	var band_y := 0.0
	for pos in positions.values():
		band_y = max(band_y, pos.y)
	band_y += GRAPH_Y_GAP
	for i in orphans.size():
		positions[orphans[i].id] = Vector2(40.0 + i * GRAPH_X_GAP, band_y)

# ---------------------------------------------------------------- Filtering
## Clears the search and placeholder filters. Called when a tree is loaded so
## a new tree does not inherit the filters of the previous one.
func _reset_filters() -> void:
	_search_filter = ""
	_filter_placeholders_only = false
	if _search_line_edit != null:
		_search_line_edit.text = ""
	if _ph_check_box != null:
		_ph_check_box.set_pressed_no_signal(false)

func _apply_filters() -> void:
	if current_tree == null:
		return

	for task in current_tree.node_list:
		if task == null:
			continue
		var visible_state := _is_task_matching_filter(task)
		if _graph_nodes_by_id.has(task.id):
			var gn: GraphNode = _graph_nodes_by_id[task.id]
			gn.visible = visible_state

func _capture_inspector_focus() -> Dictionary:
	var viewport := get_viewport()
	if viewport == null:
		return {}
	var focused = viewport.gui_get_focus_owner()
	if focused == null:
		return {}
	if focused is LineEdit:
		var fid = focused.get_meta("field_id", "")
		if fid != "":
			return {
				"type": "line_edit",
				"field_id": fid,
				"caret_column": focused.caret_column
			}
	return {}

func _restore_inspector_focus(focus_info: Dictionary) -> void:
	if focus_info.is_empty():
		return
	var field_id: String = focus_info.get("field_id", "")
	if field_id == "":
		return
	var control := _find_control_by_field_id(_inspector_form_container, field_id)
	if control != null and control is LineEdit:
		control.grab_focus()
		control.caret_column = mini(focus_info.get("caret_column", 0), control.text.length())

func _find_control_by_field_id(root: Node, field_id: String) -> Control:
	if root == null:
		return null
	if root is Control and root.has_meta("field_id") and root.get_meta("field_id") == field_id:
		return root as Control
	if root is SpinBox:
		var le := (root as SpinBox).get_line_edit()
		if le.has_meta("field_id") and le.get_meta("field_id") == field_id:
			return le
	for child in root.get_children():
		var found := _find_control_by_field_id(child, field_id)
		if found != null:
			return found
	return null

# ---------------------------------------------------------------- Inspector
func _update_inspector() -> void:
	var focus_info := _capture_inspector_focus()
	# Clear previous dynamic form controls. remove_child + queue_free detaches
	# the old controls right away, so the container never accumulates stale
	# controls (and their closures never point at an old task).
	for child in _inspector_form_container.get_children():
		if child != _inspector_content:
			_inspector_form_container.remove_child(child)
			child.queue_free()

	if current_tree == null or selected_node_id < 0:
		_inspector_title.text = "Task Inspector"
		_inspector_content.text = "[color=gray]Select a node in the graph or hierarchy to inspect and edit.[/color]"
		_inspector_content.visible = true
		return

	var task := current_tree.get_node_by_id(selected_node_id)
	if task == null:
		_inspector_title.text = "Task [#%d]" % selected_node_id
		_inspector_content.text = "[color=red]Data not found for Task ID %d[/color]" % selected_node_id
		_inspector_content.visible = true
		return

	_inspector_title.text = "[%d] %s" % [task.id, task.friendly_name]

	# Build Read-only Info text
	var b := ""
	b += "[b]Type:[/b] %s\n" % _bb_escape(str(task.type_name))
	b += "[b]Category:[/b] %s\n" % _bb_escape(str(task.category))
	b += "[b]Status:[/b] %s\n" % ("[color=red]⚠️ PLACEHOLDER[/color]" if task.is_placeholder else "[color=green]Ready[/color]")

	var parent_id := -1
	if task.parent != null and "id" in task.parent:
		parent_id = task.parent.id
	b += "[b]Parent ID:[/b] %s\n" % (str(parent_id) if parent_id >= 0 else "None (Root)")

	var child_ids: Array = []
	if "children" in task and task.children is Array:
		for c in task.children:
			if c != null and "id" in c:
				child_ids.append(c.id)
	b += "[b]Children IDs:[/b] %s\n\n" % (str(child_ids) if not child_ids.is_empty() else "None (Leaf)")

	_inspector_content.text = b
	_inspector_content.visible = true

	# Dynamic Editable Controls
	# 1. Edit Name Row
	var name_row := HBoxContainer.new()
	var name_lbl := Label.new()
	name_lbl.text = "Name:"
	name_lbl.custom_minimum_size = Vector2(70, 0)
	name_row.add_child(name_lbl)

	var name_edit := LineEdit.new()
	name_edit.text = task.friendly_name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.set_meta("field_id", "task_name")
	var initial_name := task.friendly_name
	var commit_name := func(new_text: String):
		if new_text == initial_name:
			return
		_record_mutation("Rename Task", func():
			task.friendly_name = new_text
			if _graph_nodes_by_id.has(task.id):
				_graph_nodes_by_id[task.id].title = "[%d] %s" % [task.id, new_text]
			_inspector_title.text = "[%d] %s" % [task.id, new_text]
			if _hierarchy_items.has(task.id):
				var item: TreeItem = _hierarchy_items[task.id]
				item.set_text(0, new_text)
		, true)
		initial_name = new_text
	name_edit.text_submitted.connect(commit_name)
	name_edit.focus_exited.connect(func(): commit_name.call(name_edit.text))
	name_row.add_child(name_edit)
	_inspector_form_container.add_child(name_row)

	# Composite Abort Type
	if task is BTComposite:
		var abort_row := HBoxContainer.new()
		var abort_lbl := Label.new()
		abort_lbl.text = "Abort Type:"
		abort_lbl.custom_minimum_size = Vector2(70, 0)
		abort_row.add_child(abort_lbl)

		var abort_opt := OptionButton.new()
		abort_opt.add_item("None", BTComposite.AbortType.NONE)
		abort_opt.add_item("Self", BTComposite.AbortType.SELF)
		abort_opt.add_item("Lower Priority", BTComposite.AbortType.LOWER_PRIORITY)
		abort_opt.add_item("Both", BTComposite.AbortType.BOTH)
		abort_opt.select((task as BTComposite).abort_type)
		abort_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		abort_opt.item_selected.connect(func(idx: int):
			_record_mutation("Change Abort Type", func():
				(task as BTComposite).set_abort_type(idx)
			)
		)
		abort_row.add_child(abort_opt)
		_inspector_form_container.add_child(abort_row)

	_inspector_form_container.add_child(HSeparator.new())

	# 2. Parameters Section
	var param_header := Label.new()
	param_header.text = "Parameters:"
	param_header.add_theme_font_size_override("font_size", 12)
	_inspector_form_container.add_child(param_header)

	var params_box := VBoxContainer.new()
	params_box.add_theme_constant_override("separation", 4)
	_inspector_form_container.add_child(params_box)

	for k in _collect_parameter_keys(task):
		params_box.add_child(_build_parameter_row(task, str(k)))

	# Add Parameter Row
	var add_param_row := HBoxContainer.new()
	var new_p_key := LineEdit.new()
	new_p_key.placeholder_text = "New param key..."
	new_p_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_param_row.add_child(new_p_key)

	var new_p_val := LineEdit.new()
	new_p_val.placeholder_text = "Value..."
	new_p_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_param_row.add_child(new_p_val)

	var add_p_btn := Button.new()
	add_p_btn.text = "+ Add"
	add_p_btn.pressed.connect(func():
		var pk = new_p_key.text.strip_edges()
		if pk != "":
			_record_mutation("Add Parameter", func():
				task.parameters[pk] = _coerce_new_param_value(new_p_val.text.strip_edges())
				_update_inspector()
			)
	)
	add_param_row.add_child(add_p_btn)
	_inspector_form_container.add_child(add_param_row)

	_inspector_form_container.add_child(HSeparator.new())

	# 3. Blackboard Variables Section
	if current_tree.blackboard != null:
		var bb_header := Label.new()
		bb_header.text = "Blackboard Variables:"
		bb_header.add_theme_font_size_override("font_size", 12)
		_inspector_form_container.add_child(bb_header)

		var bb_box := VBoxContainer.new()
		bb_box.add_theme_constant_override("separation", 4)
		_inspector_form_container.add_child(bb_box)

		var vars = current_tree.blackboard.get_all_variables()
		for vname in vars.keys():
			var v = vars[vname]
			var var_capture = v
			var bb_row := HBoxContainer.new()
			var v_lbl := Label.new()
			v_lbl.text = v.name + " (" + v.type_name + "):"
			v_lbl.custom_minimum_size = Vector2(110, 0)
			bb_row.add_child(v_lbl)

			var val_edit := LineEdit.new()
			val_edit.text = str(v.value)
			val_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			val_edit.set_meta("field_id", "bb_var_%s" % var_capture.name)
			var initial_bb_val := val_edit.text
			var commit_bb_var := func(nv: String):
				if nv == initial_bb_val:
					return
				var parsed := _parse_editor_value(nv, var_capture.value)
				if typeof(parsed) == typeof(var_capture.value):
					_record_mutation("Edit Blackboard Variable", func():
						current_tree.blackboard.set_var(var_capture.name, parsed, var_capture.type_name)
					, true)
					initial_bb_val = nv
			val_edit.text_submitted.connect(commit_bb_var)
			val_edit.focus_exited.connect(func(): commit_bb_var.call(val_edit.text))
			bb_row.add_child(val_edit)

			var del_v_btn := Button.new()
			del_v_btn.text = "✕"
			del_v_btn.pressed.connect(func():
				_record_mutation("Delete Blackboard Variable", func():
					current_tree.blackboard.remove_var(var_capture.name)
					_update_inspector()
				)
			)
			bb_row.add_child(del_v_btn)

			bb_box.add_child(bb_row)

		# Add Blackboard Variable Row
		var add_bb_row := HBoxContainer.new()
		var new_v_name := LineEdit.new()
		new_v_name.placeholder_text = "New var name..."
		new_v_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_bb_row.add_child(new_v_name)

		var new_v_val := LineEdit.new()
		new_v_val.placeholder_text = "Value..."
		new_v_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_bb_row.add_child(new_v_val)

		var add_v_btn := Button.new()
		add_v_btn.text = "+ Add"
		add_v_btn.pressed.connect(func():
			var vn = new_v_name.text.strip_edges()
			if vn != "":
				_record_mutation("Add Blackboard Variable", func():
					var val_parsed = _coerce_new_param_value(new_v_val.text.strip_edges())
					current_tree.blackboard.set_var(vn, val_parsed)
					_update_inspector()
				)
		)
		add_bb_row.add_child(add_v_btn)
		_inspector_form_container.add_child(add_bb_row)

	_inspector_form_container.add_child(HSeparator.new())

	# 4. Action Buttons
	var set_root_btn := Button.new()
	set_root_btn.text = "⭐ Set as Root"
	set_root_btn.tooltip_text = "Make this node the root of the behavior tree"
	set_root_btn.disabled = (task == current_tree.root_task)
	set_root_btn.pressed.connect(func():
		_set_as_root(task)
	)
	_inspector_form_container.add_child(set_root_btn)

	var del_node_btn := Button.new()
	del_node_btn.text = "🗑️ Delete Node"
	del_node_btn.modulate = Color(1.0, 0.5, 0.5, 1.0)
	del_node_btn.pressed.connect(func():
		_delete_task(task)
	)
	_inspector_form_container.add_child(del_node_btn)

	_restore_inspector_focus(focus_info)

# ---------------------------------------------------------------- Inspector Helpers
## The registry the editor uses for the current tree.
func _active_registry() -> BTTaskRegistry:
	if current_tree != null and current_tree.registry != null:
		return current_tree.registry
	if _registry != null:
		return _registry
	return BTTaskRegistry.new()

## Escapes square brackets so user supplied names do not break the BBCode of
## the inspector text.
func _bb_escape(text: String) -> String:
	return text.replace("[", "[lb]")

## The typed parameter schema a task exposes, if any.
func _get_parameter_schema(task: BTTask) -> Dictionary:
	if task != null and task.has_method("get_parameter_schema"):
		var schema = task.call("get_parameter_schema")
		if schema is Dictionary:
			return schema
	return {}

## Parameter keys to show: the ones the task already has plus the ones its
## schema declares, so a fresh Repeater still shows count / repeat_forever.
func _collect_parameter_keys(task: BTTask) -> Array:
	var keys: Array = []
	for k in task.parameters.keys():
		var key := str(k)
		if key.begins_with("_") or key == "abort_type":
			continue
		keys.append(key)
	for k in _get_parameter_schema(task).keys():
		var key := str(k)
		if not keys.has(key):
			keys.append(key)
	return keys

## The kind of value a parameter holds: "bool", "int", "float", "vector" or
## "string". The schema wins over the stored value.
func _param_value_type(schema_entry: Dictionary, current_value: Variant, has_value: bool) -> String:
	if not schema_entry.is_empty():
		return str(schema_entry.get("type", "string"))
	if not has_value:
		return "string"
	match typeof(current_value):
		TYPE_BOOL: return "bool"
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_COLOR: return "vector"
	return "string"

## The Variant type a parameter must keep while it is edited.
func _param_variant_type(value_type: String, current_value: Variant, has_value: bool) -> int:
	match value_type:
		"bool": return TYPE_BOOL
		"int": return TYPE_INT
		"float": return TYPE_FLOAT
		"vector": return typeof(current_value) if has_value else TYPE_STRING
	return TYPE_STRING

## Builds the row of a single parameter: label, blackboard toggle, value
## control and delete button.
func _build_parameter_row(task: BTTask, key: String) -> Control:
	var p_row := HBoxContainer.new()
	var k_lbl := Label.new()
	k_lbl.text = key + ":"
	k_lbl.custom_minimum_size = Vector2(90, 0)
	p_row.add_child(k_lbl)

	var is_bb := task.is_param_blackboard(key)
	var key_capture = key
	var has_value: bool = task.parameters.has(key)
	var current_value: Variant = task.parameters.get(key, null)
	var schema_entry: Dictionary = _get_parameter_schema(task).get(key, {})
	var value_type := _param_value_type(schema_entry, current_value, has_value)
	var expected_type := _param_variant_type(value_type, current_value, has_value)
	var previous: Variant = current_value if has_value else schema_entry.get("default", null)

	var bb_toggle_btn := Button.new()
	bb_toggle_btn.text = "🏷️ BB" if is_bb else "Val"
	bb_toggle_btn.tooltip_text = "Toggle literal value vs Blackboard variable binding"
	bb_toggle_btn.custom_minimum_size = Vector2(45, 0)
	bb_toggle_btn.pressed.connect(func():
		_record_mutation("Toggle Parameter Blackboard", func():
			if is_bb:
				var cur_key = task.get_param_blackboard_key(key_capture)
				task.set_param(key_capture, cur_key, false)
			else:
				var cur_val = str(task.parameters.get(key_capture, ""))
				task.set_param(key_capture, cur_val if cur_val != "" else key_capture, true)
			_update_inspector()
		)
	)
	p_row.add_child(bb_toggle_btn)

	if is_bb:
		var bb_edit := LineEdit.new()
		bb_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bb_edit.text = task.get_param_blackboard_key(key_capture)
		bb_edit.placeholder_text = "Blackboard key..."
		bb_edit.set_meta("field_id", "param_bb_%s" % key_capture)
		var initial_bb_key := bb_edit.text
		var commit_bb_key := func(new_key: String):
			var stripped := new_key.strip_edges()
			if stripped == initial_bb_key:
				return
			_record_mutation("Edit Parameter Blackboard Key", func():
				task.set_param(key_capture, stripped, true)
			, true)
			initial_bb_key = stripped
		bb_edit.text_submitted.connect(commit_bb_key)
		bb_edit.focus_exited.connect(func(): commit_bb_key.call(bb_edit.text))
		p_row.add_child(bb_edit)
	else:
		p_row.add_child(_build_value_control(task, key_capture, value_type, expected_type, previous))

	var del_p_btn := Button.new()
	del_p_btn.text = "✕"
	del_p_btn.pressed.connect(func():
		_record_mutation("Delete Parameter", func():
			task.parameters.erase(key_capture)
			_update_inspector()
		)
	)
	p_row.add_child(del_p_btn)
	return p_row

## The typed control for a parameter value.
func _build_value_control(task: BTTask, key: String, value_type: String, expected_type: int, previous: Variant) -> Control:
	match value_type:
		"bool":
			var cb := CheckBox.new()
			cb.button_pressed = BTTask.coerce_bool(previous, false)
			cb.toggled.connect(func(pressed: bool):
				_record_mutation("Edit Parameter", func():
					task.parameters[key] = pressed
				, true)
			)
			return cb
		"int":
			var int_spin := SpinBox.new()
			int_spin.min_value = -1000000000.0
			int_spin.max_value = 1000000000.0
			int_spin.step = 1.0
			var start_val: int = int(round(previous)) if previous != null else 0
			int_spin.value = float(start_val)
			int_spin.set_meta("field_id", "param_spin_%s" % key)
			var le_int := int_spin.get_line_edit()
			le_int.set_meta("field_id", "param_spin_le_%s" % key)
			var last_committed_int := start_val
			var commit_int := func():
				var curr := int(round(int_spin.value))
				if curr == last_committed_int:
					return
				last_committed_int = curr
				_record_mutation("Edit Parameter", func():
					task.parameters[key] = curr
				, true)
			le_int.text_submitted.connect(func(_t): commit_int.call())
			le_int.focus_exited.connect(commit_int)
			int_spin.focus_exited.connect(commit_int)
			int_spin.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and not event.pressed:
					commit_int.call()
			)
			return int_spin
		"float":
			var float_spin := SpinBox.new()
			float_spin.min_value = -1000000000.0
			float_spin.max_value = 1000000000.0
			float_spin.step = 0.1
			var start_fval: float = float(previous) if previous != null else 0.0
			float_spin.value = start_fval
			float_spin.set_meta("field_id", "param_spin_%s" % key)
			var le_float := float_spin.get_line_edit()
			le_float.set_meta("field_id", "param_spin_le_%s" % key)
			var last_committed_float := start_fval
			var commit_float := func():
				var curr := float_spin.value
				if is_equal_approx(curr, last_committed_float):
					return
				last_committed_float = curr
				_record_mutation("Edit Parameter", func():
					task.parameters[key] = curr
				, true)
			le_float.text_submitted.connect(func(_t): commit_float.call())
			le_float.focus_exited.connect(commit_float)
			float_spin.focus_exited.connect(commit_float)
			float_spin.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and not event.pressed:
					commit_float.call()
			)
			return float_spin
		_:
			var v_edit := LineEdit.new()
			v_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v_edit.text = str(previous) if previous != null else ""
			v_edit.placeholder_text = "Literal value..."
			v_edit.set_meta("field_id", "param_val_%s" % key)
			var initial_v_text := v_edit.text
			var commit_v := func(new_val: String):
				if new_val == initial_v_text:
					return
				var curr: Variant = task.parameters.get(key, previous)
				var coerced := _coerce_param_value(new_val, curr, expected_type)
				_record_mutation("Edit Parameter", func():
					task.parameters[key] = coerced
				, true)
				initial_v_text = new_val
			v_edit.text_submitted.connect(commit_v)
			v_edit.focus_exited.connect(func(): commit_v.call(v_edit.text))
			return v_edit

## Converts edited text into a value of the type the parameter already has.
## An input that does not match the type is rejected and the old value stays.
func _coerce_param_value(text: String, previous: Variant, expected_type: int) -> Variant:
	match expected_type:
		TYPE_BOOL:
			return BTTask.coerce_bool(text, previous if previous is bool else false)
		TYPE_INT:
			if text.is_valid_int():
				return int(text)
			return previous
		TYPE_FLOAT:
			if text.is_valid_float():
				return float(text)
			return previous
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_COLOR:
			var parsed = _parse_vector_or_color(text, expected_type)
			if parsed != null and typeof(parsed) == expected_type:
				return parsed
			return previous
	return text

func _parse_vector_or_color(text: String, expected_type: int) -> Variant:
	var s := text.strip_edges()
	var inside := ""
	match expected_type:
		TYPE_VECTOR2:
			if s.to_lower().begins_with("vector2(") and s.ends_with(")"):
				inside = s.substr(8, s.length() - 9)
			elif s.begins_with("(") and s.ends_with(")"):
				inside = s.substr(1, s.length() - 2)
			else:
				var v = str_to_var(s)
				return v if typeof(v) == TYPE_VECTOR2 else null
			var parts := inside.split(",")
			if parts.size() != 2:
				return null
			var p0 := parts[0].strip_edges()
			var p1 := parts[1].strip_edges()
			if (p0.is_valid_float() or p0.is_valid_int()) and (p1.is_valid_float() or p1.is_valid_int()):
				return Vector2(float(p0), float(p1))
			return null

		TYPE_VECTOR3:
			if s.to_lower().begins_with("vector3(") and s.ends_with(")"):
				inside = s.substr(8, s.length() - 9)
			elif s.begins_with("(") and s.ends_with(")"):
				inside = s.substr(1, s.length() - 2)
			else:
				var v = str_to_var(s)
				return v if typeof(v) == TYPE_VECTOR3 else null
			var parts := inside.split(",")
			if parts.size() != 3:
				return null
			var p0 := parts[0].strip_edges()
			var p1 := parts[1].strip_edges()
			var p2 := parts[2].strip_edges()
			if (p0.is_valid_float() or p0.is_valid_int()) and (p1.is_valid_float() or p1.is_valid_int()) and (p2.is_valid_float() or p2.is_valid_int()):
				return Vector3(float(p0), float(p1), float(p2))
			return null

		TYPE_COLOR:
			if s.to_lower().begins_with("color(") and s.ends_with(")"):
				inside = s.substr(6, s.length() - 7)
			elif s.begins_with("(") and s.ends_with(")"):
				inside = s.substr(1, s.length() - 2)
			else:
				var v = str_to_var(s)
				return v if typeof(v) == TYPE_COLOR else null
			var parts := inside.split(",")
			if parts.size() == 4:
				var p0 := parts[0].strip_edges()
				var p1 := parts[1].strip_edges()
				var p2 := parts[2].strip_edges()
				var p3 := parts[3].strip_edges()
				if (p0.is_valid_float() or p0.is_valid_int()) and (p1.is_valid_float() or p1.is_valid_int()) and (p2.is_valid_float() or p2.is_valid_int()) and (p3.is_valid_float() or p3.is_valid_int()):
					return Color(float(p0), float(p1), float(p2), float(p3))
			elif parts.size() == 3:
				var p0 := parts[0].strip_edges()
				var p1 := parts[1].strip_edges()
				var p2 := parts[2].strip_edges()
				if (p0.is_valid_float() or p0.is_valid_int()) and (p1.is_valid_float() or p1.is_valid_int()) and (p2.is_valid_float() or p2.is_valid_int()):
					return Color(float(p0), float(p1), float(p2), 1.0)
			return null
	return null

## Coerces the value of a freshly added parameter: int, then float, then bool,
## otherwise the text stays a string.
func _coerce_new_param_value(text: String) -> Variant:
	if text.is_valid_int():
		return int(text)
	if text.is_valid_float():
		return float(text)
	var lowered := text.to_lower()
	if lowered == "true":
		return true
	if lowered == "false":
		return false
	return text

func _count_hidden_descendants(task: BTTask) -> int:
	if task == null or current_tree == null:
		return 0
	var has_filter := (_search_filter != "" or _filter_placeholders_only)
	if not has_filter:
		return 0
	var count := 0
	for node in _collect_subtree_nodes(task):
		if node == task:
			continue
		if not _is_task_matching_filter(node):
			count += 1
	return count

func _count_hidden_nodes_in_subtrees(targets: Array) -> int:
	var has_filter := (_search_filter != "" or _filter_placeholders_only)
	if not has_filter:
		return 0
	var count := 0
	var counted: Dictionary = {}
	for task in targets:
		for node in _collect_subtree_nodes(task):
			if not targets.has(node) and not counted.has(node.id):
				counted[node.id] = true
				if not _is_task_matching_filter(node):
					count += 1
	return count

# ---------------------------------------------------------------- Tree Editing
## Removes a task and its whole subtree. The root can never be deleted: the
## tree would have no root and could not be saved or loaded again.
func _delete_task(task: BTTask) -> bool:
	if current_tree == null or task == null:
		return false
	if task == current_tree.root_task:
		_stats_label.text = "❌ Cannot delete the root node '%s'. Use 'Set as Root' on another node first." % task.friendly_name
		return false
	var hidden_count := _count_hidden_descendants(task)
	if hidden_count > 0:
		_pending_delete_action = func():
			_record_mutation("Delete Task", func(): _delete_task_with_descendants(task))
		if _delete_confirm_dialog != null:
			_delete_confirm_dialog.dialog_text = "Deleting '%s' will also delete %d hidden child node(s). Continue?" % [task.friendly_name, hidden_count]
			_delete_confirm_dialog.popup_centered()
		return true
	_record_mutation("Delete Task", func(): _delete_task_with_descendants(task))
	return true

func _delete_task_with_descendants(task: BTTask) -> void:
	for node in _collect_subtree_nodes(task):
		current_tree.remove_node(node)
	_prune_node_positions()
	_stats = current_tree.get_stats()
	_update_stats_label()
	if current_tree.get_node_by_id(selected_node_id) == null:
		selected_node_id = -1
	_render_current_tree()

func _collect_subtree_nodes(task: BTTask) -> Array:
	var collected: Array = [task]
	if "children" in task and task.children is Array:
		for child in task.children:
			if child != null:
				collected.append_array(_collect_subtree_nodes(child))
	return collected

## Promotes a task to the root of the tree.
func _set_as_root(task: BTTask) -> void:
	if current_tree == null or task == null or task == current_tree.root_task:
		return
	_record_mutation("Set as Root", func(): _set_as_root_now(task))

func _set_as_root_now(task: BTTask) -> void:
	var previous_root := current_tree.root_task
	if task.parent != null:
		current_tree.disconnect_parent_child(task.parent, task)
	current_tree.set_root(task)
	if previous_root != null and previous_root != task and previous_root.category == "Root":
		# Only one node may carry the Root category.
		var restored := _active_registry().get_category(previous_root.type_name)
		if restored != "Unknown":
			previous_root.category = restored
	_stats = current_tree.get_stats()
	_update_stats_label()
	_render_current_tree()
	_stats_label.text = "⭐ '%s' is now the root of the tree." % task.friendly_name

## Explains why a connection was rejected by the model.
func _describe_connect_failure(parent: BTTask, child: BTTask) -> String:
	if parent == child:
		return "a node cannot be its own parent."
	if not (parent is BTParentTask):
		return "'%s' cannot hold children." % parent.type_name
	if parent is BTDecorator and not (parent as BTParentTask).children.is_empty() and not (parent as BTParentTask).children.has(child):
		return "the decorator already has a child."
	if _is_descendant_of(child, parent):
		return "the connection would create a cycle."
	return "the model rejected the connection."

## Whether candidate is a descendant of task.
func _is_descendant_of(candidate: BTTask, task: BTTask) -> bool:
	var ancestor: BTTask = task
	while ancestor != null:
		if ancestor == candidate:
			return true
		ancestor = ancestor.parent
	return false

# ---------------------------------------------------------------- Events
func _on_graph_node_selected(node: Node) -> void:
	if _suppress_inspector_rebuild:
		return
	if node is GraphNode:
		for nid in _graph_nodes_by_id.keys():
			if _graph_nodes_by_id[nid] == node:
				selected_node_id = nid
				_update_inspector()
				break

func _on_graph_node_deselected(node: Node) -> void:
	if _suppress_inspector_rebuild:
		return
	if selected_node_id >= 0 and _graph_nodes_by_id.get(selected_node_id) == node:
		selected_node_id = -1
		_update_inspector()

func _on_graph_connection_request(from_node: StringName, _from_port: int, to_node: StringName, _to_port: int) -> void:
	if current_tree == null:
		return
	var from_str := String(from_node)
	var to_str := String(to_node)
	if from_str.begins_with("Node_") and to_str.begins_with("Node_"):
		var p_id = int(from_str.replace("Node_", ""))
		var c_id = int(to_str.replace("Node_", ""))
		var p_task = current_tree.get_node_by_id(p_id)
		var c_task = current_tree.get_node_by_id(c_id)
		if p_task != null and c_task != null and p_task != c_task and (not ("children" in p_task) or not p_task.children.has(c_task)):
			_record_mutation("Connect", func():
				current_tree.connect_parent_child(p_task, c_task)
				if c_task.parent != p_task:
					# The model refused the connection: say why instead of
					# letting the node silently jump back to its old parent.
					_stats_label.text = "❌ Cannot connect: %s" % _describe_connect_failure(p_task, c_task)
				_render_current_tree()
			)

func _on_graph_disconnection_request(from_node: StringName, _from_port: int, to_node: StringName, _to_port: int) -> void:
	if current_tree == null:
		return
	var from_str := String(from_node)
	var to_str := String(to_node)
	if from_str.begins_with("Node_") and to_str.begins_with("Node_"):
		var p_id = int(from_str.replace("Node_", ""))
		var c_id = int(to_str.replace("Node_", ""))
		var p_task = current_tree.get_node_by_id(p_id)
		var c_task = current_tree.get_node_by_id(c_id)
		if p_task != null and c_task != null:
			_record_mutation("Disconnect", func():
				current_tree.disconnect_parent_child(p_task, c_task)
				_render_current_tree()
			)

func _parse_editor_value(text: String, previous: Variant) -> Variant:
	if previous is bool:
		if text.to_lower() == "true": return true
		if text.to_lower() == "false": return false
		return previous
	if previous is int and text.is_valid_int():
		return int(text)
	if previous is float and text.is_valid_float():
		return float(text)
	if previous is int or previous is float:
		return previous
	return text

func _has_unsaved_changes() -> bool:
	if current_tree == null: return false
	return _json_draft_modified or JSON.stringify(current_tree.to_dict(), "\t") != _model_baseline

func _request_action(action: Callable) -> void:
	if _has_unsaved_changes():
		_pending_action = action
		_confirm_dialog.dialog_text = "Discard unapplied changes?"
		_confirm_dialog.popup_centered()
	else:
		action.call()

func _confirm_pending_action() -> void:
	if _pending_action.is_valid():
		var action := _pending_action
		_pending_action = Callable()
		_confirm_dialog.dialog_text = "Discard unapplied changes?"
		_json_draft_modified = false
		if current_tree != null:
			var serialized := JSON.stringify(current_tree.to_dict(), "\t")
			_json_draft = serialized
			_json_baseline = serialized
			_json_draft_tree = current_tree
			if _json_text_edit != null:
				_json_text_edit.text = serialized
		action.call()

func _cancel_pending_action() -> void:
	_pending_action = Callable()
	_confirm_dialog.dialog_text = "Discard unapplied changes?"

func _on_delete_confirmed() -> void:
	if _delete_confirm_dialog != null:
		_delete_confirm_dialog.hide()
	if _pending_delete_action.is_valid():
		var action := _pending_delete_action
		_pending_delete_action = Callable()
		action.call()

func _on_graph_delete_nodes_request(nodes: Array[StringName]) -> void:
	if current_tree == null:
		return
	var targets: Array = []
	var blocked_root := ""
	for nname in nodes:
		var s := String(nname)
		if s.begins_with("Node_"):
			var nid = int(s.replace("Node_", ""))
			var task = current_tree.get_node_by_id(nid)
			if task != null:
				if task == current_tree.root_task:
					# Deleting the root would produce a tree that cannot be
					# loaded again; the user has to pick a new root first.
					blocked_root = task.friendly_name
					continue
				targets.append(task)
	if targets.is_empty():
		if blocked_root != "":
			_stats_label.text = "❌ Cannot delete the root node '%s'. Use 'Set as Root' on another node first." % blocked_root
		return

	var hidden_count := _count_hidden_nodes_in_subtrees(targets)
	if hidden_count > 0:
		_pending_delete_action = func():
			_record_mutation("Delete Tasks", func():
				for task in targets:
					if current_tree.get_node_by_id(task.id) == task:
						_delete_task_with_descendants(task)
			)
		if _delete_confirm_dialog != null:
			_delete_confirm_dialog.dialog_text = "Deleting selected node(s) will also delete %d hidden child node(s). Continue?" % hidden_count
			_delete_confirm_dialog.popup_centered()
		return

	_record_mutation("Delete Tasks", func():
		for task in targets:
			if current_tree.get_node_by_id(task.id) == task:
				_delete_task_with_descendants(task)
	)
	if blocked_root != "":
		_stats_label.text = "❌ Cannot delete the root node '%s'. Use 'Set as Root' on another node first." % blocked_root

func _on_hierarchy_item_selected() -> void:
	var item = _hierarchy_tree.get_selected()
	if item != null:
		var nid = item.get_metadata(0)
		if nid != null:
			select_node_by_id(int(nid))

func _update_stats_label() -> void:
	_stats_label.text = "Tree: %s | Total: %d nodes | 🟣 Root: %d | 🔵 Composite: %d | 🟢 Decorator: %d | 🍃 Leaf: %d | ⚠️ Placeholder: %d" % [
		current_tree_name,
		_stats.get("total", 0),
		_stats.get("root", 0),
		_stats.get("composite", 0),
		_stats.get("decorator", 0),
		_stats.get("leaf", 0),
		_stats.get("placeholder", 0)
	]

func _get_category_color(cat: String) -> Color:
	match cat:
		"Root": return COLOR_ROOT
		"Composite": return COLOR_COMPOSITE
		"Decorator": return COLOR_DECORATOR
		"Action": return COLOR_ACTION
		"Condition": return COLOR_CONDITION
		"Unknown": return COLOR_PLACEHOLDER
		_: return Color.LIGHT_GRAY
