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
var _registry: BTTaskRegistry = null
var selected_node_id: int = -1

var _search_filter: String = ""
var _filter_placeholders_only: bool = false
var _graph_nodes_by_id: Dictionary = {} # id -> GraphNode
var _stats: Dictionary = {"total": 0, "root": 0, "composite": 0, "decorator": 0, "leaf": 0, "placeholder": 0}

# UI References - Toolbar
var _tree_option_button: OptionButton
var _reload_button: Button
var _save_button: Button
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
				set_tree_source(ProviderScript.new())
		else:
			set_tree_source(BTMemoryTreeSource.new())

func _ready() -> void:
	_ensure_built()

# ---------------------------------------------------------------- Public API
func set_tree_source(p_source: BTTreeSourceProvider) -> void:
	if _tree_option_button == null:
		_build_ui()
	tree_source = p_source
	if _source_label != null:
		_source_label.text = "Source: %s" % (tree_source.get_source_name() if tree_source != null else "None")
	_refresh_tree_list()

func load_generic_tree(p_tree: BTTree, p_name: String = "") -> bool:
	if p_tree == null:
		return false
	if _json_draft_tree != null and _json_draft_tree != p_tree:
		_json_draft = ""
		_json_draft_tree = null
	current_tree = p_tree
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
	if _add_task_menu_button != null:
		_setup_add_task_menu(_add_task_menu_button.get_popup())
	current_tree_name = p_name if p_name != "" else p_tree.tree_name
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
	return load_generic_tree(tree, p_name)

func load_tree_file(p_file_path: String) -> bool:
	if tree_source == null:
		return false
	var tree := tree_source.load_tree(p_file_path)
	if tree == null:
		return false
	return load_generic_tree(tree, p_file_path.get_file().get_basename())

func select_node_by_id(node_id: int) -> void:
	selected_node_id = node_id
	for nid in _graph_nodes_by_id.keys():
		var gn: GraphNode = _graph_nodes_by_id[nid]
		gn.selected = (nid == node_id)
	_update_inspector()

func set_search_filter(query: String) -> void:
	_search_filter = query.strip_edges().to_lower()
	_apply_filters()

func set_placeholder_filter(only_placeholders: bool) -> void:
	_filter_placeholders_only = only_placeholders
	_apply_filters()

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
	_source_label.text = ""
	_source_label.visible = false
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
	add_child(_confirm_dialog)

func _setup_add_task_menu(popup: PopupMenu) -> void:
	popup.clear()
	if not popup.id_pressed.is_connected(_on_add_task_menu_item_pressed):
		popup.id_pressed.connect(_on_add_task_menu_item_pressed)
	var registry := current_tree.registry if current_tree != null and current_tree.registry != null else BTTaskRegistry.new()
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
	if trees.size() > 0:
		_tree_option_button.select(0)
		load_tree_by_name(trees[0])
	else:
		_stats_label.text = "⚠️ No Behavior Trees found in source."

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
	if current_tree_name != "":
		var tree_name := current_tree_name
		_request_action(func(): load_tree_by_name(tree_name))

func _on_save_pressed() -> void:
	if current_tree == null or tree_source == null:
		return
	if _json_draft_modified:
		_stats_label.text = "Unapplied JSON edits; apply JSON before saving."
		return
	var ok: bool = tree_source.save_tree(current_tree_name, current_tree)
	if ok:
		_model_baseline = JSON.stringify(current_tree.to_dict(), "\t")
		_stats_label.text = "✅ Saved tree '%s' successfully." % current_tree_name
	else:
		_stats_label.text = "❌ Failed to save tree '%s'." % current_tree_name

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
	var errors: PackedStringArray = BTTree.validate_dict(parsed_data)
	if not errors.is_empty():
		_json_status_label.text = "❌ Invalid tree: %s" % errors[0]
		_json_status_label.modulate = COLOR_PLACEHOLDER
		return
	var new_tree = BTTree.from_dict(parsed_data, _registry)
	if new_tree == null:
		_json_status_label.text = "❌ Tree data is invalid; current tree was not changed."
		_json_status_label.modulate = COLOR_PLACEHOLDER
		return
	var persisted_model_baseline := _model_baseline
	load_generic_tree(new_tree, current_tree_name)
	_model_baseline = persisted_model_baseline
	_json_baseline = JSON.stringify(current_tree.to_dict(), "\t")
	_json_draft = _json_baseline
	_json_draft_tree = current_tree
	_json_draft_modified = false
	_json_text_edit.text = _json_draft
	_json_status_label.text = "✅ Tree updated successfully from JSON!"
	_json_status_label.modulate = COLOR_ACTION

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

# ---------------------------------------------------------------- Node Adding & Editing
func _on_add_task_menu_item_pressed(id: int) -> void:
	if current_tree == null:
		return
	var type_name := "Sequence"
	var category := "Composite"
	var popup := _add_task_menu_button.get_popup()
	for i in popup.item_count:
		if popup.get_item_id(i) == id:
			type_name = str(popup.get_item_metadata(i))
			category = _registry.get_category(type_name) if _registry != null else "Action"
			break
	if type_name == "":
		return

	if _registry == null:
		_registry = BTTaskRegistry.new()
	var new_task := _registry.create_task(type_name)
	new_task.friendly_name = type_name
	new_task.category = category

	# Generate new unique ID
	var max_id := 0
	for t in current_tree.node_list:
		if t != null and t.id > max_id:
			max_id = t.id
	new_task.id = max_id + 1

	current_tree.add_node(new_task)
	_stats = current_tree.get_stats()
	_update_stats_label()
	_render_current_tree()
	select_node_by_id(new_task.id)

# ---------------------------------------------------------------- Rendering
func _render_current_tree() -> void:
	_clear_views()
	if current_tree == null:
		return

	_render_graph()
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
	selected_node_id = -1

func _render_graph() -> void:
	if current_tree == null or current_tree.node_list.is_empty():
		return

	var positions := _compute_tree_layout()

	for task in current_tree.node_list:
		if task == null:
			continue
		var gnode := GraphNode.new()
		gnode.name = "Node_%d" % task.id
		gnode.title = "[%d] %s" % [task.id, task.friendly_name]
		gnode.resizable = false
		gnode.draggable = true

		var pos = positions.get(task.id, Vector2(50, 50))
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

		var is_root: bool = (task == current_tree.root_task or task.category == "Root")
		var is_parent: bool = (task is BTParentTask or ("children" in task and not task.children.is_empty()) or task.category == "Composite" or task.category == "Decorator")

		var has_input: bool = not is_root
		var has_output: bool = is_parent

		var slot_color: Color = COLOR_ROOT if is_root else _get_category_color(task.category)
		gnode.set_slot(0, has_input, 0, slot_color, has_output, 0, slot_color)

		_graph_edit.add_child(gnode)
		_graph_nodes_by_id[task.id] = gnode

	# Connections
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

func _render_hierarchy() -> void:
	if current_tree == null or current_tree.node_list.is_empty():
		return

	var root_task := current_tree.root_task
	if root_task == null:
		root_task = current_tree.node_list[0]

	var tree_item_map := {}
	_add_hierarchy_item_recursive(null, root_task, tree_item_map)

func _add_hierarchy_item_recursive(parent_item: TreeItem, task: BTTask, item_map: Dictionary) -> void:
	if task == null:
		return

	var item := _hierarchy_tree.create_item(parent_item)
	item.set_metadata(0, task.id)
	item.set_text(0, task.friendly_name)
	item.set_text(1, task.type_name)
	item.set_text(2, task.category)
	item.set_text(3, "⚠️ Placeholder" if task.is_placeholder else "Ready")
	item.set_text(4, str(task.id))

	var color := COLOR_ROOT if task == current_tree.root_task else _get_category_color(task.category)
	item.set_custom_color(0, color)
	item.set_custom_color(3, COLOR_PLACEHOLDER if task.is_placeholder else COLOR_ACTION)

	item_map[task.id] = item

	var kids: Array = []
	if "children" in task and task.children is Array:
		kids = task.children

	for child in kids:
		if child != null:
			_add_hierarchy_item_recursive(item, child, item_map)

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

# ---------------------------------------------------------------- Filtering
func _apply_filters() -> void:
	if current_tree == null:
		return

	for task in current_tree.node_list:
		if task == null:
			continue
		var match_search := true
		if _search_filter != "":
			var text_content: String = (str(task.friendly_name) + " " + str(task.type_name) + " " + str(task.category)).to_lower()
			match_search = text_content.contains(_search_filter)

		var match_ph := true
		if _filter_placeholders_only:
			match_ph = task.is_placeholder

		var visible_state := (match_search and match_ph)
		if _graph_nodes_by_id.has(task.id):
			var gn: GraphNode = _graph_nodes_by_id[task.id]
			gn.modulate = Color.WHITE if visible_state else Color(1.0, 1.0, 1.0, 0.2)

# ---------------------------------------------------------------- Inspector
func _update_inspector() -> void:
	# Clear previous dynamic form controls
	for child in _inspector_form_container.get_children():
		if child != _inspector_content:
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
	b += "[b]Type:[/b] %s\n" % task.type_name
	b += "[b]Category:[/b] %s\n" % task.category
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
	name_edit.text_changed.connect(func(new_text: String):
		task.friendly_name = new_text
		if _graph_nodes_by_id.has(task.id):
			_graph_nodes_by_id[task.id].title = "[%d] %s" % [task.id, new_text]
		_inspector_title.text = "[%d] %s" % [task.id, new_text]
	)
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
			(task as BTComposite).set_abort_type(idx)
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

	for k in task.parameters.keys():
		if k.begins_with("_") or k == "abort_type":
			continue
		var p_row := HBoxContainer.new()
		var k_lbl := Label.new()
		k_lbl.text = _format_param_name(k) + ":"
		k_lbl.custom_minimum_size = Vector2(90, 0)
		p_row.add_child(k_lbl)

		var is_bb := task.is_param_blackboard(k)
		var key_capture = k

		var bb_toggle_btn := Button.new()
		bb_toggle_btn.text = "🏷️ BB" if is_bb else "Val"
		bb_toggle_btn.tooltip_text = "Toggle literal value vs Blackboard variable binding"
		bb_toggle_btn.custom_minimum_size = Vector2(45, 0)
		bb_toggle_btn.pressed.connect(func():
			if is_bb:
				var cur_key = task.get_param_blackboard_key(key_capture)
				task.set_param(key_capture, cur_key, false)
			else:
				var cur_val = str(task.parameters.get(key_capture, ""))
				task.set_param(key_capture, cur_val if cur_val != "" else key_capture, true)
			_update_inspector()
		)
		p_row.add_child(bb_toggle_btn)

		var v_edit := LineEdit.new()
		v_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if is_bb:
			v_edit.text = task.get_param_blackboard_key(key_capture)
			v_edit.placeholder_text = "Blackboard key..."
			v_edit.text_changed.connect(func(new_key: String):
				task.set_param(key_capture, new_key.strip_edges(), true)
			)
		else:
			v_edit.text = str(task.parameters[k])
			v_edit.placeholder_text = "Literal value..."
			v_edit.text_changed.connect(func(new_val: String):
				if new_val.is_valid_int():
					task.parameters[key_capture] = int(new_val)
				elif new_val.is_valid_float():
					task.parameters[key_capture] = float(new_val)
				elif new_val.to_lower() == "true":
					task.parameters[key_capture] = true
				elif new_val.to_lower() == "false":
					task.parameters[key_capture] = false
				else:
					task.parameters[key_capture] = new_val
			)
		p_row.add_child(v_edit)

		var del_p_btn := Button.new()
		del_p_btn.text = "✕"
		del_p_btn.pressed.connect(func():
			task.parameters.erase(key_capture)
			_update_inspector()
		)
		p_row.add_child(del_p_btn)
		params_box.add_child(p_row)

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
			task.parameters[pk] = new_p_val.text.strip_edges()
			_update_inspector()
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
			var bb_row := HBoxContainer.new()
			var v_lbl := Label.new()
			v_lbl.text = v.name + " (" + v.type_name + "):"
			v_lbl.custom_minimum_size = Vector2(110, 0)
			bb_row.add_child(v_lbl)

			var val_edit := LineEdit.new()
			val_edit.text = str(v.value)
			val_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var var_capture = v
			val_edit.text_changed.connect(func(nv: String):
				var parsed := _parse_editor_value(nv, var_capture.value)
				if typeof(parsed) == typeof(var_capture.value):
					current_tree.blackboard.set_var(var_capture.name, parsed, var_capture.type_name)
			)
			bb_row.add_child(val_edit)
			bb_box.add_child(bb_row)

	_inspector_form_container.add_child(HSeparator.new())

	# 4. Action Buttons
	var del_node_btn := Button.new()
	del_node_btn.text = "🗑️ Delete Node"
	del_node_btn.modulate = Color(1.0, 0.5, 0.5, 1.0)
	del_node_btn.pressed.connect(func():
		current_tree.remove_node(task)
		_stats = current_tree.get_stats()
		_update_stats_label()
		_render_current_tree()
	)
	_inspector_form_container.add_child(del_node_btn)

# ---------------------------------------------------------------- Events
func _on_graph_node_selected(node: Node) -> void:
	if node is GraphNode:
		for nid in _graph_nodes_by_id.keys():
			if _graph_nodes_by_id[nid] == node:
				selected_node_id = nid
				_update_inspector()
				break

func _on_graph_node_deselected(node: Node) -> void:
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
			current_tree.connect_parent_child(p_task, c_task)
			_render_current_tree()

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
			current_tree.disconnect_parent_child(p_task, c_task)
			_graph_edit.disconnect_node(from_node, 0, to_node, 0)
			_render_current_tree()

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
		_confirm_dialog.popup_centered()
	else:
		action.call()

func _confirm_pending_action() -> void:
	if _pending_action.is_valid():
		var action := _pending_action
		_pending_action = Callable()
		action.call()

func _on_graph_delete_nodes_request(nodes: Array[StringName]) -> void:
	for nname in nodes:
		var s := String(nname)
		if s.begins_with("Node_"):
			var nid = int(s.replace("Node_", ""))
			var task = current_tree.get_node_by_id(nid)
			if task != null:
				current_tree.remove_node(task)
	_stats = current_tree.get_stats()
	_update_stats_label()
	_render_current_tree()

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

func _format_param_name(raw_key: String) -> String:
	if raw_key == "AbortTypeabortType":
		return "AbortType"
	if raw_key.begins_with("GameObjectList"):
		return "GameObjectList"
	return raw_key
