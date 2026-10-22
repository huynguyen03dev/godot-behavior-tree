extends SceneTree
## Focused authoring-path regressions.

var checks: int = 0
var failures: int = 0

class SnapshotProvider extends BTTreeSourceProvider:
	var snapshots: Dictionary = {}
	var save_count: int = 0
	var registry: BTTaskRegistry

	func _init(p_registry: BTTaskRegistry) -> void:
		registry = p_registry

	func list_trees() -> Array:
		return ["A", "B"]

	func load_tree(identifier: String) -> BTTree:
		if not snapshots.has(identifier):
			return null
		return BTTree.from_dict(snapshots[identifier].duplicate(true), registry)

	func save_tree(identifier: String, tree: BTTree) -> bool:
		save_count += 1
		last_error = ""
		var reg: BTTaskRegistry = registry if registry != null else tree.registry
		var errors := BTTree.validate_dict(tree.to_dict(), reg)
		if not errors.is_empty():
			last_error = errors[0]
			return false
		snapshots[identifier] = JSON.parse_string(JSON.stringify(tree.to_dict()))
		return true

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var viewer = load("res://addons/godot_bt/editor/bt_viewer.gd").new()
	root.add_child(viewer)
	var tree := BTTree.new()
	var root_task := BTComposite.BTSequence.new()
	root_task.id = 1
	tree.set_root(root_task)
	var child := BTTask.new()
	child.id = 2
	tree.connect_parent_child(root_task, child)
	viewer.load_generic_tree(tree, "Regression")
	checks += 1
	failures += int(not _expect(viewer._graph_nodes_by_id.size() == 2, "graph renders tree"))
	viewer._tab_bar.current_tab = 2
	viewer._json_text_edit.text = "draft survives switching"
	viewer._tab_bar.current_tab = 0
	viewer._tab_bar.current_tab = 2
	checks += 1
	failures += int(not _expect(viewer._json_text_edit.text == "draft survives switching", "draft survives tab revisit"))
	viewer._json_text_edit.text = "{}"
	viewer._on_apply_json_pressed()
	checks += 2
	failures += int(not _expect(viewer.current_tree == tree and viewer._stats.total == 2, "empty schema rejected without replacing model"))
	failures += int(not _expect(viewer._json_status_label.text.begins_with("❌"), "invalid data reports failure"))
	tree.blackboard.set_var("probe", 3, "int")
	var signals: Array = []
	tree.blackboard.variable_changed.connect(func(_name, _new, _old): signals.append(true))
	viewer.select_node_by_id(1)
	var edit := _find_line_edit(viewer._inspector_form_container, "3")
	if edit != null:
		edit.text_changed.emit("9")
		edit.text_changed.emit("bad")
	checks += 1
	failures += int(not _expect(edit != null and not signals.is_empty() and tree.blackboard.get_var("probe") == 9 and tree.blackboard.get_variable_obj("probe").type_name == "int", "typed blackboard edit retains type after invalid input"))
	var custom_registry := BTTaskRegistry.new()
	custom_registry.register_task("CustomRegressionTask", func(): return BTTask.new(), "Action")
	tree.registry = custom_registry
	viewer.load_generic_tree(tree, "Regression")
	var popup: PopupMenu = viewer._add_task_menu_button.get_popup()
	var custom_id := -1
	for i in popup.item_count:
		if popup.get_item_metadata(i) == "CustomRegressionTask":
			custom_id = popup.get_item_id(i)
	var before_count := tree.node_list.size()
	if custom_id >= 0:
		popup.id_pressed.emit(custom_id)
	checks += 2
	failures += int(not _expect(tree.node_list.size() == before_count + 1, "popup selection adds custom registered task"))
	failures += int(not _expect(tree.node_list.back().type_name == "CustomRegressionTask", "popup-created task has registered type"))
	var provider := BTMemoryTreeSource.new()
	provider.register_tree("Regression", tree)
	viewer.set_tree_source(provider)
	checks += 1
	failures += int(not _expect(viewer._confirm_dialog.visible, "switching the source with unsaved changes asks for confirmation"))
	viewer._confirm_dialog.confirmed.emit()
	viewer.select_node_by_id(tree.node_list.back().id)
	var name_edit := _find_line_edit(viewer._inspector_form_container, "CustomRegressionTask")
	if name_edit != null:
		name_edit.text_changed.emit("Edited custom")
	viewer._on_save_pressed()
	checks += 2
	failures += int(not _expect(provider.load_tree("Regression").get_node_by_id(tree.node_list.back().id).friendly_name == "Edited custom", "Save persists Inspector model edit"))
	failures += int(not _expect(not viewer._has_unsaved_changes(), "successful Save advances dirty baseline"))
	var original_tree: BTTree = viewer.current_tree
	viewer._tab_bar.current_tab = 2
	var original_json: String = viewer._json_text_edit.text
	viewer._json_text_edit.text = "{}"
	viewer._json_text_edit.text_changed.emit()
	viewer._on_save_pressed()
	checks += 2
	failures += int(not _expect(viewer.current_tree == original_tree and viewer._json_text_edit.text == "{}", "unapplied JSON Save leaves model unchanged"))
	failures += int(not _expect(viewer._stats_label.text.contains("Unapplied JSON"), "unapplied JSON Save warns"))
	viewer._json_text_edit.text = original_json
	viewer._tab_bar.current_tab = 0
	viewer.select_node_by_id(1)
	viewer.current_tree.get_node_by_id(1).friendly_name = "Unsaved model edit"
	viewer._tree_option_button.add_item("Other", 1)
	viewer._tree_option_button.select(1)
	viewer._tree_option_button.item_selected.emit(1)
	var selector_before: int = viewer._tree_option_button.selected
	checks += 3
	failures += int(not _expect(viewer._confirm_dialog.visible, "dirty tree selection opens confirmation"))
	viewer._confirm_dialog.hide()
	failures += int(not _expect(viewer.current_tree == original_tree, "cancel preserves current tree"))
	failures += int(not _expect(viewer._tree_option_button.selected == selector_before, "cancel preserves tree selector"))
	viewer._on_reload_pressed()
	checks += 2
	failures += int(not _expect(viewer._confirm_dialog.visible, "dirty reload opens confirmation"))
	viewer._confirm_dialog.hide()
	failures += int(not _expect(viewer.current_tree == original_tree and viewer._tree_option_button.selected == selector_before, "cancelled reload preserves tree and selector"))
	var snapshot_provider := SnapshotProvider.new(tree.registry)
	var snapshot_a := tree.to_dict()
	snapshot_a["tree_name"] = "A"
	snapshot_provider.snapshots["A"] = JSON.parse_string(JSON.stringify(snapshot_a))
	var snapshot_b := tree.to_dict()
	snapshot_b["tree_name"] = "B"
	snapshot_b["nodes"][0]["friendly_name"] = "Tree B root"
	snapshot_provider.snapshots["B"] = JSON.parse_string(JSON.stringify(snapshot_b))
	viewer.set_tree_source(snapshot_provider)
	checks += 1
	failures += int(not _expect(viewer._confirm_dialog.visible, "switching the source with unsaved changes asks for confirmation"))
	viewer._confirm_dialog.confirmed.emit()
	viewer._tab_bar.current_tab = 2
	var baseline_a: String = viewer._json_text_edit.text
	var edited_a: Dictionary = JSON.parse_string(baseline_a)
	edited_a["nodes"][0]["friendly_name"] = "Edited A root"
	viewer._json_text_edit.text = JSON.stringify(edited_a, "\t")
	viewer._on_apply_json_pressed()
	checks += 2
	failures += int(not _expect(viewer.current_tree.get_node_by_id(1).friendly_name == "Edited A root", "Apply updates current model"))
	failures += int(not _expect(snapshot_provider.save_count == 0 and snapshot_provider.snapshots["A"]["nodes"][0]["friendly_name"] != "Edited A root", "Apply does not mutate provider snapshot"))
	viewer._on_reload_pressed()
	var applied_a: BTTree = viewer.current_tree
	checks += 1
	failures += int(not _expect(viewer._confirm_dialog.visible, "applied model change prompts before reload"))
	viewer._confirm_dialog.hide()
	checks += 1
	failures += int(not _expect(viewer.current_tree == applied_a, "cancelled reload retains unsaved applied model"))
	viewer._on_save_pressed()
	checks += 2
	failures += int(not _expect(snapshot_provider.save_count == 1, "Save calls provider exactly once"))
	failures += int(not _expect(snapshot_provider.snapshots["A"]["nodes"][0]["friendly_name"] == "Edited A root", "Save persists independent serialized snapshot"))
	var second_draft: Dictionary = JSON.parse_string(viewer._json_text_edit.text)
	second_draft["nodes"][0]["friendly_name"] = "Unapplied A root"
	viewer._json_text_edit.text = JSON.stringify(second_draft, "\t")
	viewer._json_text_edit.text_changed.emit()
	viewer._on_save_pressed()
	checks += 1
	failures += int(not _expect(snapshot_provider.save_count == 1, "unapplied JSON blocks Save without provider call"))
	viewer._tree_option_button.select(1)
	viewer._tree_option_button.item_selected.emit(1)
	checks += 2
	failures += int(not _expect(viewer.current_tree_name == "A" and viewer._confirm_dialog.visible, "dirty actual selector change prompts and preserves current tree"))
	failures += int(not _expect(viewer._tree_option_button.selected == 0, "cancelled selector switch restores selection"))
	viewer._confirm_dialog.hide()
	var unsaved_a: Dictionary = JSON.parse_string(viewer._json_text_edit.text)
	unsaved_a["nodes"][0]["friendly_name"] = "Unsaved A root"
	viewer._json_text_edit.text = JSON.stringify(unsaved_a, "\t")
	viewer._json_text_edit.text_changed.emit()
	viewer._on_apply_json_pressed()
	viewer._tree_option_button.select(1)
	viewer._tree_option_button.item_selected.emit(1)
	checks += 3
	failures += int(not _expect(viewer._confirm_dialog.visible and viewer.current_tree_name == "A", "dirty A switch opens confirmation and retains A"))
	viewer._confirm_dialog.confirmed.emit()
	checks += 1
	failures += int(not _expect(viewer.current_tree_name == "B", "confirmed selector change loads tree B"))
	failures += int(not _expect(viewer._json_text_edit.text.contains("Tree B root"), "JSON tab displays tree B rather than stale tree A"))
	failures += int(not _expect(snapshot_provider.save_count == 1, "switch does not save implicitly"))
	var edited_b: Dictionary = JSON.parse_string(viewer._json_text_edit.text)
	edited_b["nodes"][0]["friendly_name"] = "Dirty B root"
	viewer._json_text_edit.text = JSON.stringify(edited_b, "\t")
	viewer._json_text_edit.text_changed.emit()
	viewer._on_apply_json_pressed()
	viewer._tab_bar.current_tab = 0
	var b_model: BTTree = viewer.current_tree
	viewer._tree_option_button.select(0)
	viewer._tree_option_button.item_selected.emit(0)
	checks += 2
	failures += int(not _expect(viewer._confirm_dialog.visible and viewer.current_tree == b_model and viewer.current_tree.get_node_by_id(1).friendly_name == "Dirty B root", "dirty switch to A prompts and retains edited B model"))
	viewer._confirm_dialog.hide()
	viewer._on_reload_pressed()
	viewer._confirm_dialog.confirmed.emit()
	checks += 2
	failures += int(not _expect(viewer.current_tree.get_node_by_id(1).friendly_name == "Tree B root", "confirmed reload restores persisted B model"))
	failures += int(not _expect(viewer._json_text_edit.text.contains("Tree B root"), "confirmed reload refreshes visible JSON from persisted B"))
	viewer.free()
	_test_root_deletion_and_set_as_root()
	_test_save_validation()
	_test_onboarding()
	_test_stale_json_guard()
	_test_set_tree_source_dirty_flow()
	_test_corrupt_tree_status()
	_test_typed_parameters()
	_test_add_task_attachment()
	_test_connection_feedback()
	_test_node_positions()
	_test_dirty_close_hooks()
	_test_inspector_rebuild()
	_test_editor_misc()
	_test_n1_switch_source_clears_state()
	_test_n2_add_task_attachment_guard()
	_test_n4_cancel_pending_action()
	_test_n6_save_external_data_unapplied_json()
	_test_n8_refresh_tree_list_skips_corrupt_to_valid()
	_test_n10_vector_color_parsing()
	_test_n11_new_tree_dropdown_and_save_sync()
	_test_undo_redo_rename()
	_test_undo_redo_add_task_and_history_cleared()
	_test_undo_delete_subtree()
	_test_filtering()
	_test_source_label()
	_test_incremental_render_identity()
	print("Editor regressions: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)

# ---------------------------------------------------------------- B1: root deletion
func _test_root_deletion_and_set_as_root() -> void:
	var viewer := _make_viewer()
	var tree := _tree_with_root()
	var root_task := tree.root_task
	var child := BTTask.new()
	child.id = 2
	child.friendly_name = "Child"
	tree.connect_parent_child(root_task, child)
	viewer.load_generic_tree(tree, "GuardTree")

	# The graph Delete request must refuse to remove the root.
	var names: Array[StringName] = ["Node_1"]
	viewer._on_graph_delete_nodes_request(names)
	checks += 3
	failures += int(not _expect(viewer.current_tree.root_task == root_task, "graph delete keeps the root node"))
	failures += int(not _expect(viewer.current_tree.get_node_count() == 2, "graph delete does not drop the root from the model"))
	failures += int(not _expect(viewer._stats_label.text.contains("Cannot delete the root"), "graph delete reports the refusal"))

	# The inspector Delete button must refuse as well.
	viewer.select_node_by_id(1)
	var del_btn := _find_button(viewer._inspector_form_container, "Delete Node")
	if del_btn != null:
		del_btn.pressed.emit()
	checks += 3
	failures += int(not _expect(del_btn != null, "the inspector offers a Delete Node button"))
	failures += int(not _expect(viewer.current_tree.root_task == root_task, "inspector delete keeps the root node"))
	failures += int(not _expect(viewer._stats_label.text.contains("Cannot delete the root"), "inspector delete reports the refusal"))

	# "Set as Root" promotes another node.
	viewer.select_node_by_id(2)
	var set_root_btn := _find_button(viewer._inspector_form_container, "Set as Root")
	if set_root_btn != null:
		set_root_btn.pressed.emit()
	checks += 4
	failures += int(not _expect(set_root_btn != null, "the inspector offers a Set as Root button"))
	failures += int(not _expect(viewer.current_tree.root_task == child, "Set as Root promotes the selected node"))
	failures += int(not _expect(child.parent == null, "Set as Root detaches the node from its old parent"))
	failures += int(not _expect(root_task.parent == null, "the previous root has no parent afterwards"))
	viewer.free()

# ---------------------------------------------------------------- B1/H2/N3: save validation
func _test_save_validation() -> void:
	var viewer := _make_viewer()
	var provider := SnapshotProvider.new(BTTaskRegistry.new())
	provider.snapshots["Broken"] = {}
	viewer.set_tree_source(provider)
	var tree := _tree_with_root()
	viewer.load_generic_tree(tree, "Broken")
	# Break the tree: without a root the serialized form cannot be loaded again.
	tree.remove_node(tree.root_task)
	viewer._on_save_pressed()
	checks += 3
	failures += int(not _expect(provider.save_count == 1, "an invalid tree calls provider save_tree exactly once"))
	failures += int(not _expect(viewer._stats_label.text.begins_with("❌"), "an invalid tree reports the validation error from provider"))
	failures += int(not _expect(viewer._stats_label.text.contains("root_id"), "the reported error names the problem"))

	# Valid tree: save succeeds and provider is called once
	provider.save_count = 0
	var valid_tree := _tree_with_root()
	viewer.load_generic_tree(valid_tree, "Valid")
	viewer._on_save_pressed()
	checks += 2
	failures += int(not _expect(provider.save_count == 1, "valid tree calls provider save_tree exactly once"))
	failures += int(not _expect(viewer._stats_label.text.begins_with("✅"), "valid tree reports success"))
	viewer.free()

# ---------------------------------------------------------------- B2: onboarding
func _test_onboarding() -> void:
	var viewer := _make_viewer()
	checks += 3
	failures += int(not _expect(viewer.tree_source is BTFileTreeSource, "the editor defaults to a file source"))
	failures += int(not _expect(not viewer._confirm_dialog.visible, "the initial source never prompts"))
	failures += int(not _expect(viewer._source_button != null and viewer._new_tree_button != null, "the toolbar offers a source and a new tree button"))

	viewer._on_new_tree_pressed()
	checks += 5
	failures += int(not _expect(viewer.current_tree != null, "New creates a tree"))
	failures += int(not _expect(viewer.current_tree_name == "new_tree", "the new tree is named new_tree"))
	failures += int(not _expect(viewer.current_tree.root_task != null, "the new tree has a root"))
	failures += int(not _expect(viewer.current_tree.root_task.friendly_name == "Root" and viewer.current_tree.root_task.category == "Root", "the new root is named Root"))
	failures += int(not _expect(viewer._has_unsaved_changes(), "the new tree stays dirty until it is saved"))

	# Choosing a folder switches the source (through the dirty check).
	viewer.set_source_directory("res://demo/data")
	checks += 2
	failures += int(not _expect(viewer._confirm_dialog.visible, "choosing a folder with unsaved changes asks for confirmation"))
	viewer._confirm_dialog.confirmed.emit()
	failures += int(not _expect(viewer.tree_source is BTFileTreeSource, "choosing a folder switches to a file source"))
	viewer.free()

# ---------------------------------------------------------------- E7: stale JSON
func _test_stale_json_guard() -> void:
	var viewer := _make_viewer()
	var tree := _tree_with_root()
	viewer.load_generic_tree(tree, "Stale")
	viewer._tab_bar.current_tab = 2
	# The Inspector stays editable while the JSON tab is open.
	tree.root_task.friendly_name = "Renamed in the Inspector"
	viewer._on_apply_json_pressed()
	checks += 2
	failures += int(not _expect(viewer._confirm_dialog.visible, "applying stale JSON asks for confirmation"))
	failures += int(not _expect(viewer.current_tree.root_task.friendly_name == "Renamed in the Inspector", "the model is untouched until the change is confirmed"))
	viewer._confirm_dialog.confirmed.emit()
	checks += 1
	failures += int(not _expect(viewer.current_tree.root_task.friendly_name != "Renamed in the Inspector", "confirming applies the JSON and drops the model change"))
	viewer.free()

# ---------------------------------------------------------------- E8: set_tree_source
func _test_set_tree_source_dirty_flow() -> void:
	var viewer := _make_viewer()
	var tree := _tree_with_root()
	viewer.load_generic_tree(tree, "Dirty")
	tree.root_task.friendly_name = "Unsaved edit"
	var provider := BTMemoryTreeSource.new()
	viewer.set_tree_source(provider)
	checks += 2
	failures += int(not _expect(viewer._confirm_dialog.visible, "switching the source with unsaved changes asks for confirmation"))
	failures += int(not _expect(viewer.tree_source != provider, "the source is not switched before the change is confirmed"))
	viewer._confirm_dialog.confirmed.emit()
	checks += 1
	failures += int(not _expect(viewer.tree_source == provider, "confirming switches the source"))
	viewer.free()

# ---------------------------------------------------------------- E9: corrupt tree
class BrokenProvider extends BTTreeSourceProvider:
	func list_trees() -> Array:
		return ["broken"]

	func load_tree(_identifier: String) -> BTTree:
		return null

func _test_corrupt_tree_status() -> void:
	var viewer := _make_viewer()
	var tree := _tree_with_root()
	viewer.load_generic_tree(tree, "Good")
	viewer.set_tree_source(BrokenProvider.new())
	checks += 3
	failures += int(not _expect(viewer.current_tree == null, "a tree that fails to load clears loaded state instead of keeping previous tree"))
	failures += int(not _expect(viewer._stats_label.text == "❌ Failed to load tree 'broken'", "the load failure is reported"))
	failures += int(not _expect(viewer.current_tree_name == "", "the previously loaded tree is not resurrected"))
	viewer.free()

# ---------------------------------------------------------------- E10: typed parameters
func _test_typed_parameters() -> void:
	var viewer := _make_viewer()
	var tree := BTTree.new()
	var repeater := BTDecorator.BTRepeater.new()
	repeater.id = 1
	repeater.friendly_name = "Repeater"
	tree.set_root(repeater)
	var leaf := BTTask.new()
	leaf.id = 2
	leaf.friendly_name = "Leaf"
	leaf.parameters["target"] = Vector2(3, 4)
	tree.connect_parent_child(repeater, leaf)
	viewer.load_generic_tree(tree, "Typed")

	# A fresh Repeater shows the rows of its parameter schema.
	viewer.select_node_by_id(1)
	checks += 5
	failures += int(not _expect(_find_row(viewer._inspector_form_container, "count:") != [], "a fresh Repeater shows the count row"))
	failures += int(not _expect(_find_row(viewer._inspector_form_container, "repeat_forever:") != [], "a fresh Repeater shows the repeat_forever row"))
	failures += int(not _expect(_find_row(viewer._inspector_form_container, "end_on_failure:") != [], "a fresh Repeater shows the end_on_failure row"))
	failures += int(not _expect(_row_has(viewer._inspector_form_container, "count:", "SpinBox"), "int schema rows use a SpinBox"))
	failures += int(not _expect(_row_has(viewer._inspector_form_container, "repeat_forever:", "CheckBox"), "bool schema rows use a CheckBox"))

	# A Vector2 parameter becomes editable.
	viewer.select_node_by_id(2)
	var edit := _find_line_edit(viewer._inspector_form_container, str(Vector2(3, 4)))
	checks += 1
	failures += int(not _expect(edit != null, "the Vector2 parameter is shown as text"))
	if edit != null:
		edit.text_changed.emit("(5, 6)")
	checks += 2
	failures += int(not _expect(typeof(leaf.parameters["target"]) == TYPE_VECTOR2, "editing a Vector2 parameter keeps its type"))
	failures += int(not _expect(leaf.parameters["target"] == Vector2(5, 6), "editing Vector2 to '(5, 6)' updates value to Vector2(5, 6)"))

	# Garbage input keeps the old value
	if edit != null:
		edit.text_changed.emit("garbage")
	checks += 1
	failures += int(not _expect(leaf.parameters["target"] == Vector2(5, 6), "garbage input keeps the old Vector2 value"))

	# "+ Add" coerces the value instead of storing a string.
	var key_edit := _find_line_edit_by_placeholder(viewer._inspector_form_container, "New param key...")
	var val_edit := _find_line_edit_by_placeholder(viewer._inspector_form_container, "Value...")
	var add_btn := _find_button(viewer._inspector_form_container, "+ Add")
	if key_edit != null and val_edit != null and add_btn != null:
		key_edit.text = "speed"
		val_edit.text = "5"
		add_btn.pressed.emit()
	checks += 2
	failures += int(not _expect(typeof(leaf.parameters.get("speed", null)) == TYPE_INT, "an added numeric parameter is stored as an int"))
	failures += int(not _expect(leaf.parameters.get("speed", null) == 5, "an added numeric parameter keeps its value"))
	viewer.free()

# ---------------------------------------------------------------- E11: attachment & orphans
func _test_add_task_attachment() -> void:
	var viewer := _make_viewer()
	var tree := _tree_with_root()
	var root_task := tree.root_task
	viewer.load_generic_tree(tree, "Attach")
	viewer.select_node_by_id(1)
	var popup: PopupMenu = viewer._add_task_menu_button.get_popup()
	var sequence_id := -1
	for i in popup.item_count:
		if popup.get_item_metadata(i) == "Sequence":
			sequence_id = popup.get_item_id(i)
	viewer._on_add_task_menu_item_pressed(sequence_id)
	var new_task: BTTask = tree.node_list[tree.node_list.size() - 1]
	checks += 4
	failures += int(not _expect(tree.node_list.size() == 2, "Add Task creates a node"))
	failures += int(not _expect(new_task.parent == root_task, "the new task is attached to the selected root"))
	failures += int(not _expect(root_task.children.has(new_task), "the new task is a child of the root"))
	failures += int(not _expect(_hierarchy_ids(viewer._hierarchy_tree).has(new_task.id), "the new task appears in the hierarchy"))

	# A node that is not reachable from the root is listed separately.
	var orphan := BTTask.new()
	orphan.id = 9
	orphan.friendly_name = "Orphan"
	tree.add_node(orphan)
	viewer.load_generic_tree(tree, "Attach")
	checks += 3
	failures += int(not _expect(_hierarchy_labels(viewer._hierarchy_tree).has("(unattached)"), "unattached nodes are grouped in the Tree tab"))
	failures += int(not _expect(_hierarchy_ids(viewer._hierarchy_tree).has(9), "the unattached node is listed in the hierarchy"))
	failures += int(not _expect(viewer._graph_nodes_by_id[9].position_offset.y > viewer._graph_nodes_by_id[1].position_offset.y, "unattached nodes are laid out below the tree"))
	viewer.free()

# ---------------------------------------------------------------- E3: connection feedback
func _test_connection_feedback() -> void:
	var viewer := _make_viewer()
	var tree := BTTree.new()
	var root_task := BTComposite.BTSequence.new()
	root_task.id = 1
	tree.set_root(root_task)
	var other := BTComposite.BTSequence.new()
	other.id = 2
	tree.connect_parent_child(root_task, other)
	var child := BTTask.new()
	child.id = 3
	tree.connect_parent_child(root_task, child)
	viewer.load_generic_tree(tree, "Connect")

	# Moving a child to another parent works through the model.
	viewer._on_graph_connection_request("Node_2", 0, "Node_3", 0)
	checks += 2
	failures += int(not _expect(child.parent == other, "moving a child to another parent changes its parent"))
	failures += int(not _expect(not root_task.children.has(child), "the old parent no longer holds the child"))

	# A decorator that already has a child refuses a second one and says why.
	var deco := BTDecorator.BTInverter.new()
	deco.id = 4
	tree.connect_parent_child(root_task, deco)
	var first_child := BTTask.new()
	first_child.id = 5
	tree.connect_parent_child(deco, first_child)
	var second_child := BTTask.new()
	second_child.id = 6
	tree.connect_parent_child(root_task, second_child)
	viewer.load_generic_tree(tree, "Connect")
	viewer._on_graph_connection_request("Node_4", 0, "Node_6", 0)
	checks += 2
	failures += int(not _expect(second_child.parent == root_task, "a decorator keeps its own child"))
	failures += int(not _expect(viewer._stats_label.text.contains("decorator already has a child"), "a refused connection explains itself"))
	viewer.free()

# ---------------------------------------------------------------- E1: node positions
func _test_node_positions() -> void:
	var viewer := _make_viewer()
	var tree := _tree_with_root()
	var child := BTTask.new()
	child.id = 2
	tree.connect_parent_child(tree.root_task, child)
	viewer.load_generic_tree(tree, "Positions")

	var gnode: GraphNode = viewer._graph_nodes_by_id[1]
	gnode.position_offset = Vector2(777, 555)
	viewer._graph_edit.end_node_move.emit()
	checks += 2
	failures += int(not _expect(viewer.current_tree.metadata.has("node_positions"), "the dragged position is stored in the tree metadata"))
	failures += int(not _expect(_saved_position(viewer.current_tree, 1) == Vector2(777, 555), "the stored position matches the drag"))

	viewer._render_current_tree()
	checks += 1
	failures += int(not _expect(viewer._graph_nodes_by_id[1].position_offset == Vector2(777, 555), "re-rendering keeps the saved position"))

	var round_trip := BTTree.from_dict(JSON.parse_string(JSON.stringify(viewer.current_tree.to_dict())), viewer.current_tree.registry)
	checks += 2
	failures += int(not _expect(_saved_position(round_trip, 1) == Vector2(777, 555), "the position survives a save and load round trip"))
	failures += int(not _expect(viewer.current_tree.to_dict().metadata.has("node_positions"), "the positions are part of the serialized tree"))
	viewer.free()

# ---------------------------------------------------------------- E2: dirty close
func _test_dirty_close_hooks() -> void:
	var plugin_script = load("res://addons/godot_bt/plugin.gd")
	var has_unsaved := false
	var has_save := false
	for m in plugin_script.get_script_method_list():
		if m.name == "_get_unsaved_status":
			has_unsaved = true
		if m.name == "_save_external_data":
			has_save = true
	checks += 2
	failures += int(not _expect(has_unsaved, "the plugin implements the _get_unsaved_status editor hook"))
	failures += int(not _expect(has_save, "the plugin implements the _save_external_data editor hook"))

	var viewer := _make_viewer()
	viewer.set_tree_source(BTMemoryTreeSource.new())
	var tree := _tree_with_root()
	viewer.load_generic_tree(tree, "Close")
	checks += 1
	failures += int(not _expect(not viewer._has_unsaved_changes(), "a freshly loaded tree is clean"))
	tree.root_task.friendly_name = "Unsaved"
	checks += 3
	failures += int(not _expect(viewer._has_unsaved_changes(), "an edited tree is dirty"))
	failures += int(not _expect(viewer.save_current_tree(), "the dirty tree can be saved"))
	failures += int(not _expect(not viewer._has_unsaved_changes(), "saving clears the dirty state"))
	viewer.free()

# ---------------------------------------------------------------- D5: inspector rebuild
func _test_inspector_rebuild() -> void:
	var viewer := _make_viewer()
	var tree := BTTree.new()
	var root_task := BTComposite.BTSequence.new()
	root_task.id = 1
	tree.set_root(root_task)
	var leaf_a := BTTask.new()
	leaf_a.id = 2
	leaf_a.friendly_name = "A"
	var leaf_b := BTTask.new()
	leaf_b.id = 3
	leaf_b.friendly_name = "B"
	tree.connect_parent_child(root_task, leaf_a)
	tree.connect_parent_child(root_task, leaf_b)
	viewer.load_generic_tree(tree, "Inspector")

	viewer.select_node_by_id(2)
	var count_a := viewer._inspector_form_container.get_child_count()
	viewer.select_node_by_id(3)
	var count_b := viewer._inspector_form_container.get_child_count()
	viewer.select_node_by_id(2)
	var count_a2 := viewer._inspector_form_container.get_child_count()
	checks += 3
	failures += int(not _expect(count_a == count_a2, "the inspector keeps a stable child count across selections"))
	failures += int(not _expect(count_a == count_b, "two nodes of the same kind produce the same inspector"))
	failures += int(not _expect(_find_line_edit(viewer._inspector_form_container, "A") != null, "the inspector shows the node that is selected"))
	viewer.free()

# ---------------------------------------------------------------- E13: misc
func _test_editor_misc() -> void:
	var viewer := _make_viewer()
	var tree := _tree_with_root()
	var child := BTTask.new()
	child.id = 2
	child.friendly_name = "Child"
	tree.connect_parent_child(tree.root_task, child)
	viewer.load_generic_tree(tree, "Misc")

	# An unknown menu entry must not silently add a Sequence.
	var before := tree.node_list.size()
	viewer._on_add_task_menu_item_pressed(987654)
	checks += 1
	failures += int(not _expect(tree.node_list.size() == before, "an unknown menu id adds no node"))

	# Filters are reset when a tree is loaded.
	viewer.set_search_filter("combat")
	viewer.set_placeholder_filter(true)
	viewer.load_generic_tree(_tree_with_root(), "Other")
	checks += 1
	failures += int(not _expect(viewer._search_filter == "" and not viewer._filter_placeholders_only, "loading a tree resets the search and placeholder filters"))

	# Renaming a node refreshes the hierarchy row.
	viewer.load_generic_tree(tree, "Misc")
	viewer.select_node_by_id(2)
	var name_edit := _find_line_edit(viewer._inspector_form_container, "Child")
	if name_edit != null:
		name_edit.text_changed.emit("Renamed child")
	checks += 1
	failures += int(not _expect(_hierarchy_row_text(viewer._hierarchy_tree, 2) == "Renamed child", "renaming refreshes the hierarchy row"))

	# Square brackets in names are escaped for the BBCode of the inspector.
	var bracket_task := BTTask.new()
	bracket_task.id = 7
	bracket_task.friendly_name = "Bracket[Name]"
	bracket_task.type_name = "Custom[Type]"
	tree.add_node(bracket_task)
	viewer.load_generic_tree(tree, "Misc")
	viewer.select_node_by_id(7)
	checks += 2
	failures += int(not _expect(viewer._inspector_content.text.contains("[lb]"), "square brackets are escaped for the inspector BBCode"))
	failures += int(not _expect(not viewer._inspector_content.text.contains("Custom[Type]"), "the raw name does not leak into the BBCode"))
	viewer.free()

# ---------------------------------------------------------------- N1: switch source clears state
func _test_n1_switch_source_clears_state() -> void:
	var viewer := _make_viewer()
	var prov_a := BTMemoryTreeSource.new()
	var tree_orig := _tree_with_root()
	tree_orig.tree_name = "Orig"
	prov_a.save_tree("Orig", tree_orig)

	viewer.set_tree_source(prov_a)
	viewer.load_tree_by_name("Orig")
	checks += 2
	failures += int(not _expect(viewer.current_tree_name == "Orig", "Orig loaded from source A"))
	failures += int(not _expect(viewer.current_tree != null, "source A has loaded tree"))

	var prov_b := BTMemoryTreeSource.new()
	viewer.set_tree_source(prov_b)
	checks += 3
	failures += int(not _expect(viewer.current_tree == null, "switching to empty source B clears current_tree"))
	failures += int(not _expect(viewer.current_tree_name == "", "switching to empty source B clears current_tree_name"))
	failures += int(not _expect(viewer.selected_node_id == -1, "switching to empty source B clears selection"))

	viewer._on_save_pressed()
	checks += 2
	failures += int(not _expect(prov_b.list_trees().is_empty(), "provider B receives nothing after save on empty source"))
	failures += int(not _expect(not viewer._stats_label.text.begins_with("✅"), "status does not claim success after save on empty source"))
	viewer.free()

# ---------------------------------------------------------------- N2: add task attachment guard
func _test_n2_add_task_attachment_guard() -> void:
	var viewer := _make_viewer()
	var tree := BTTree.new()
	var leaf_root := BTTask.new()
	leaf_root.id = 1
	leaf_root.friendly_name = "LeafRoot"
	tree.set_root(leaf_root)
	viewer.load_generic_tree(tree, "LeafRootTree")

	var popup: PopupMenu = viewer._add_task_menu_button.get_popup()
	var seq_id := -1
	for i in popup.item_count:
		if popup.get_item_metadata(i) == "Sequence":
			seq_id = popup.get_item_id(i)
			break

	var initial_size := tree.node_list.size()
	viewer._on_add_task_menu_item_pressed(seq_id)
	checks += 3
	failures += int(not _expect(tree.node_list.size() == initial_size, "leaf root -> node_list unchanged on Add Task"))
	failures += int(not _expect(tree.root_task == leaf_root, "leaf root -> root is not replaced on Add Task"))
	failures += int(not _expect(viewer._stats_label.text == "Cannot attach: root 'LeafRoot' cannot take children; select a node that can take children", "status explains why leaf root cannot attach child"))

	# Decorator root with existing child cannot take a second child
	var dec_tree := BTTree.new()
	var dec_root := BTDecorator.BTInverter.new()
	dec_root.id = 1
	dec_root.friendly_name = "InvertRoot"
	dec_tree.set_root(dec_root)
	var dec_child := BTTask.new()
	dec_child.id = 2
	dec_tree.connect_parent_child(dec_root, dec_child)
	viewer.load_generic_tree(dec_tree, "FullDecoratorTree")
	var dec_size := dec_tree.node_list.size()
	viewer._on_add_task_menu_item_pressed(seq_id)
	checks += 2
	failures += int(not _expect(dec_tree.node_list.size() == dec_size, "full decorator root -> node_list unchanged"))
	failures += int(not _expect(viewer._stats_label.text == "Cannot attach: root 'InvertRoot' cannot take children; select a node that can take children", "status explains full decorator cannot take children"))

	# No-root case promotes new task to root
	var empty_tree := BTTree.new()
	viewer.load_generic_tree(empty_tree, "NoRootTree")
	viewer._on_add_task_menu_item_pressed(seq_id)
	checks += 2
	failures += int(not _expect(empty_tree.root_task != null, "no-root case promotes new task to root"))
	failures += int(not _expect(empty_tree.node_list.size() == 1, "no-root case adds exactly one node"))
	viewer.free()

# ---------------------------------------------------------------- N4: cancel pending action
func _test_n4_cancel_pending_action() -> void:
	var viewer := _make_viewer()
	var tree := _tree_with_root()
	viewer.load_generic_tree(tree, "StaleCancel")
	viewer._tab_bar.current_tab = 2
	tree.root_task.friendly_name = "InspectorEdit"
	viewer._json_text_edit.text = JSON.stringify({"root_id": 1, "nodes": [{"id": 1, "type": "Sequence", "name": "FromJSON"}]})
	viewer._on_apply_json_pressed()

	checks += 2
	failures += int(not _expect(viewer._confirm_dialog.visible, "stale apply opens confirmation dialog"))
	failures += int(not _expect(viewer._pending_action.is_valid(), "stale apply arms _pending_action"))

	# Cancel the dialog
	viewer._confirm_dialog.canceled.emit()
	viewer._confirm_dialog.hide()
	checks += 2
	failures += int(not _expect(not viewer._pending_action.is_valid(), "canceling clears _pending_action"))
	failures += int(not _expect(viewer._confirm_dialog.dialog_text == "Discard unapplied changes?", "canceling restores dialog text"))

	# Trigger confirmation path; stale apply must not execute
	viewer._confirm_dialog.confirmed.emit()
	checks += 1
	failures += int(not _expect(viewer.current_tree.root_task.friendly_name == "InspectorEdit", "stale apply did not execute after being canceled"))
	viewer.free()

# ---------------------------------------------------------------- N6: save external data with unapplied JSON
func _test_n6_save_external_data_unapplied_json() -> void:
	var viewer = _make_viewer()
	var tree := _tree_with_root()
	viewer.set_tree_source(SnapshotProvider.new(BTTaskRegistry.new()))
	viewer.load_generic_tree(tree, "ExternalSave")

	viewer._tab_bar.current_tab = 2
	viewer._json_text_edit.text = "unapplied edit"
	viewer._tab_bar.current_tab = 0

	# Call save_current_tree (as invoked by plugin._save_external_data)
	var saved := viewer.save_current_tree()
	checks += 3
	failures += int(not _expect(not saved, "save_current_tree returns false on unapplied JSON draft"))
	failures += int(not _expect(viewer._stats_label.text == "Unapplied JSON edits; apply JSON before saving.", "save_external_data sets viewer status on unapplied JSON draft"))
	failures += int(not _expect(viewer._json_draft_modified, "draft remains marked modified without exception"))

	viewer.free()

# ---------------------------------------------------------------- N8: corrupt-first tree list
class CorruptThenValidProvider extends BTTreeSourceProvider:
	var valid_tree: BTTree
	func _init(p_valid: BTTree) -> void:
		valid_tree = p_valid

	func list_trees() -> Array:
		return ["corrupt_tree", "valid_tree"]

	func load_tree(identifier: String) -> BTTree:
		if identifier == "valid_tree":
			return valid_tree
		return null

class AllCorruptProvider extends BTTreeSourceProvider:
	func list_trees() -> Array:
		return ["bad1", "bad2"]

	func load_tree(_identifier: String) -> BTTree:
		return null

func _test_n8_refresh_tree_list_skips_corrupt_to_valid() -> void:
	var viewer := _make_viewer()
	var valid := _tree_with_root()
	valid.tree_name = "valid_tree"
	var provider := CorruptThenValidProvider.new(valid)
	viewer.set_tree_source(provider)

	checks += 3
	failures += int(not _expect(viewer.current_tree == valid, "valid tree loads even when first listed tree is corrupt"))
	failures += int(not _expect(viewer.current_tree_name == "valid_tree", "valid tree name is selected"))
	failures += int(not _expect(viewer._tree_option_button.get_item_text(viewer._tree_option_button.selected) == "valid_tree", "dropdown selects valid tree"))

	# Source where all trees are corrupt
	var bad_provider := AllCorruptProvider.new()
	viewer.set_tree_source(bad_provider)
	checks += 2
	failures += int(not _expect(viewer.current_tree == null, "when all trees corrupt, state stays empty"))
	failures += int(not _expect(viewer._stats_label.text == "❌ Failed to load tree 'bad1'", "when all trees corrupt, failure on first tree is reported"))
	viewer.free()

# ---------------------------------------------------------------- N10: vector and color parsing
func _test_n10_vector_color_parsing() -> void:
	var viewer := _make_viewer()
	# Vector2
	checks += 4
	failures += int(not _expect(viewer._coerce_param_value("(5, 6)", Vector2(1, 2), TYPE_VECTOR2) == Vector2(5, 6), "parse (5, 6) to Vector2"))
	failures += int(not _expect(viewer._coerce_param_value("Vector2(7.5, -8.2)", Vector2(1, 2), TYPE_VECTOR2) == Vector2(7.5, -8.2), "parse Vector2(7.5, -8.2)"))
	failures += int(not _expect(viewer._coerce_param_value("garbage", Vector2(1, 2), TYPE_VECTOR2) == Vector2(1, 2), "garbage keeps old Vector2"))
	failures += int(not _expect(viewer._coerce_param_value("(1, 2, 3)", Vector2(1, 2), TYPE_VECTOR2) == Vector2(1, 2), "wrong arity keeps old Vector2"))

	# Vector3
	checks += 3
	failures += int(not _expect(viewer._coerce_param_value("(1, 2, 3)", Vector3(0, 0, 0), TYPE_VECTOR3) == Vector3(1, 2, 3), "parse (1, 2, 3) to Vector3"))
	failures += int(not _expect(viewer._coerce_param_value("Vector3(4, 5, 6)", Vector3(0, 0, 0), TYPE_VECTOR3) == Vector3(4, 5, 6), "parse Vector3(4, 5, 6)"))
	failures += int(not _expect(viewer._coerce_param_value("garbage", Vector3(0, 0, 0), TYPE_VECTOR3) == Vector3(0, 0, 0), "garbage keeps old Vector3"))

	# Color
	checks += 3
	failures += int(not _expect(viewer._coerce_param_value("(1, 0, 0, 1)", Color.BLACK, TYPE_COLOR) == Color(1, 0, 0, 1), "parse (1, 0, 0, 1) to Color"))
	failures += int(not _expect(viewer._coerce_param_value("Color(0, 1, 0, 0.5)", Color.BLACK, TYPE_COLOR) == Color(0, 1, 0, 0.5), "parse Color(0, 1, 0, 0.5)"))
	failures += int(not _expect(viewer._coerce_param_value("garbage", Color.BLACK, TYPE_COLOR) == Color.BLACK, "garbage keeps old Color"))
	viewer.free()

# ---------------------------------------------------------------- N11: new tree dropdown and save sync
func _test_n11_new_tree_dropdown_and_save_sync() -> void:
	var viewer := _make_viewer()
	var provider := BTMemoryTreeSource.new()
	viewer.set_tree_source(provider)

	checks += 1
	failures += int(not _expect(viewer._tree_option_button.item_count == 0, "empty provider has 0 dropdown items initially"))

	# Press "+ New"
	viewer._on_new_tree_pressed()
	checks += 3
	failures += int(not _expect(viewer._tree_option_button.item_count == 1, "＋ New inserts an entry in the dropdown before save"))
	failures += int(not _expect(viewer._tree_option_button.get_item_text(viewer._tree_option_button.selected) == "new_tree", "＋ New selects new_tree in dropdown before save"))
	failures += int(not _expect(viewer.current_tree_name == "new_tree", "current_tree_name is new_tree"))

	# Save the tree
	var ok := viewer.save_current_tree()
	checks += 3
	failures += int(not _expect(ok, "saving new_tree succeeds"))
	failures += int(not _expect(provider.load_tree("new_tree") != null, "provider now stores new_tree"))
	failures += int(not _expect(viewer._tree_option_button.get_item_text(viewer._tree_option_button.selected) == "new_tree", "successful save refreshes dropdown and keeps new_tree selected"))
	viewer.free()

# ---------------------------------------------------------------- Helpers
func _make_viewer() -> BTViewer:
	var viewer: BTViewer = load("res://addons/godot_bt/editor/bt_viewer.gd").new()
	root.add_child(viewer)
	return viewer

func _tree_with_root() -> BTTree:
	var tree := BTTree.new()
	var root_task := BTComposite.BTSequence.new()
	root_task.id = 1
	root_task.friendly_name = "Root"
	root_task.category = "Root"
	tree.set_root(root_task)
	return tree

func _saved_position(tree: BTTree, id: int) -> Vector2:
	var saved = tree.metadata.get("node_positions", {})
	if not saved is Dictionary:
		return Vector2.ZERO
	var entry = saved.get(id, saved.get(str(id), null))
	if entry is Array and entry.size() == 2:
		return Vector2(float(entry[0]), float(entry[1]))
	return Vector2.ZERO

## The children of the row that carries the given label.
func _find_row(node: Node, label_text: String) -> Array:
	for child in node.get_children():
		if child is Label and child.text == label_text:
			return child.get_parent().get_children()
		var found := _find_row(child, label_text)
		if not found.is_empty():
			return found
	return []

func _row_has(node: Node, label_text: String, control_class: String) -> bool:
	for c in _find_row(node, label_text):
		if c.get_class() == control_class:
			return true
	return false

func _find_button(node: Node, expected: String) -> Button:
	for child in node.get_children():
		if child is Button and (child as Button).text.contains(expected):
			return child
		var found := _find_button(child, expected)
		if found != null:
			return found
	return null

func _find_line_edit_by_placeholder(node: Node, expected: String) -> LineEdit:
	for child in node.get_children():
		if child is LineEdit and (child as LineEdit).placeholder_text == expected:
			return child
		var found := _find_line_edit_by_placeholder(child, expected)
		if found != null:
			return found
	return null

func _hierarchy_ids(tree: Tree) -> Array:
	var ids: Array = []
	var root_item := tree.get_root()
	if root_item == null:
		return ids
	var item := root_item.get_first_child()
	while item != null:
		_collect_item_ids(item, ids)
		item = item.get_next()
	return ids

func _collect_item_ids(item: TreeItem, ids: Array) -> void:
	if item == null:
		return
	var meta = item.get_metadata(0)
	if meta != null:
		ids.append(int(meta))
	var child := item.get_first_child()
	while child != null:
		_collect_item_ids(child, ids)
		child = child.get_next()

func _hierarchy_labels(tree: Tree) -> Array:
	var labels: Array = []
	var root_item := tree.get_root()
	if root_item == null:
		return labels
	var item := root_item.get_first_child()
	while item != null:
		labels.append(item.get_text(0))
		item = item.get_next()
	return labels

func _hierarchy_row_text(tree: Tree, id: int) -> String:
	var root_item := tree.get_root()
	if root_item == null:
		return ""
	var item := root_item.get_first_child()
	while item != null:
		var found := _find_item_text(item, id)
		if found != "":
			return found
		item = item.get_next()
	return ""

func _find_item_text(item: TreeItem, id: int) -> String:
	if item == null:
		return ""
	var meta = item.get_metadata(0)
	if meta != null and int(meta) == id:
		return item.get_text(0)
	var child := item.get_first_child()
	while child != null:
		var found := _find_item_text(child, id)
		if found != "":
			return found
		child = child.get_next()
	return ""

func _expect(condition: bool, message: String) -> bool:
	if not condition:
		printerr("FAIL: " + message)
	return condition

func _find_line_edit(node: Node, expected: String) -> LineEdit:
	if node is LineEdit and node.text == expected:
		return node
	for child in node.get_children():
		var found := _find_line_edit(child, expected)
		if found != null:
			return found
	return null

# ---------------------------------------------------------------- Undo/Redo
func _test_undo_redo_rename() -> void:
	var viewer := _make_viewer()
	var tree := _tree_with_root()
	var child := BTComposite.BTSelector.new()
	child.id = 2
	child.friendly_name = "Child"
	tree.connect_parent_child(tree.root_task, child)
	viewer.load_generic_tree(tree, "UndoTree")
	viewer.select_node_by_id(1)
	var name_edit := _find_line_edit(viewer._inspector_form_container, "Root")
	checks += 1
	failures += int(not _expect(name_edit != null, "the inspector offers a name field"))
	if name_edit == null:
		viewer.free()
		return
	name_edit.text_changed.emit("Renamed")
	checks += 1
	failures += int(not _expect(viewer.current_tree.root_task.friendly_name == "Renamed", "rename applies to the model"))
	checks += 1
	failures += int(not _expect(viewer.has_undo(), "rename is undoable"))
	viewer.undo()
	checks += 2
	failures += int(not _expect(viewer.current_tree.root_task.friendly_name == "Root", "undo restores the previous name"))
	failures += int(not _expect(not viewer._has_unsaved_changes(), "undo back to the baseline clears the dirty flag"))
	viewer.redo()
	checks += 1
	failures += int(not _expect(viewer.current_tree.root_task.friendly_name == "Renamed", "redo re-applies the rename"))
	viewer.free()

func _test_undo_redo_add_task_and_history_cleared() -> void:
	var viewer := _make_viewer()
	viewer.load_generic_tree(_tree_with_root(), "HistoryTree")
	var popup: PopupMenu = viewer._add_task_menu_button.get_popup()
	var selector_id := -1
	for i in popup.item_count:
		if popup.get_item_metadata(i) == "Selector":
			selector_id = popup.get_item_id(i)
			break
	checks += 1
	failures += int(not _expect(selector_id >= 0, "the Add Task menu lists built-in composites"))
	if selector_id >= 0:
		popup.id_pressed.emit(selector_id)
		checks += 2
		failures += int(not _expect(viewer.current_tree.get_node_count() == 2, "Add Task adds a node"))
		failures += int(not _expect(viewer.has_undo(), "Add Task is undoable"))
		viewer.undo()
		checks += 1
		failures += int(not _expect(viewer.current_tree.get_node_count() == 1, "undo removes the added task"))
	viewer.load_generic_tree(_tree_with_root(), "HistoryTree")
	checks += 1
	failures += int(not _expect(not viewer.has_undo(), "loading a tree clears the undo history"))
	viewer.free()

func _test_undo_delete_subtree() -> void:
	var viewer := _make_viewer()
	var tree := _tree_with_root()
	var branch := BTComposite.BTSelector.new()
	branch.id = 2
	branch.friendly_name = "Branch"
	var leaf := BTDecorator.BTInverter.new()
	leaf.id = 3
	leaf.friendly_name = "Leaf"
	tree.connect_parent_child(tree.root_task, branch)
	tree.connect_parent_child(branch, leaf)
	viewer.load_generic_tree(tree, "SubtreeTree")
	viewer.select_node_by_id(2)
	checks += 1
	failures += int(not _expect(viewer._delete_task(branch), "deleting a branch succeeds"))
	checks += 2
	failures += int(not _expect(viewer.current_tree.get_node_count() == 1, "deleting a branch removes its subtree"))
	failures += int(not _expect(viewer.current_tree.get_node_by_id(3) == null, "the subtree leaf is removed with the branch"))
	viewer.undo()
	checks += 2
	failures += int(not _expect(viewer.current_tree.get_node_count() == 3, "undo restores the deleted subtree"))
	failures += int(not _expect(viewer.current_tree.get_node_by_id(2) != null and viewer.current_tree.get_node_by_id(3) != null, "undo restores the branch and its leaf"))
	viewer.redo()
	checks += 1
	failures += int(not _expect(viewer.current_tree.get_node_count() == 1, "redo re-deletes the subtree"))
	viewer.free()

func _test_filtering() -> void:
	var viewer := _make_viewer()
	var tree := _tree_with_root()
	var combat := BTTask.new()
	combat.id = 2
	combat.friendly_name = "Combat"
	var patrol := BTTask.new()
	patrol.id = 3
	patrol.friendly_name = "Patrol"
	tree.connect_parent_child(tree.root_task, combat)
	tree.connect_parent_child(tree.root_task, patrol)
	viewer.load_generic_tree(tree, "FilterTree")
	viewer.set_search_filter("combat")
	checks += 3
	failures += int(not _expect(viewer._graph_nodes_by_id[2].visible, "matching nodes stay visible in the graph"))
	failures += int(not _expect(not viewer._graph_nodes_by_id[3].visible, "non-matching nodes are hidden in the graph"))
	failures += int(not _expect(_hierarchy_ids(viewer._hierarchy_tree).has(2) and not _hierarchy_ids(viewer._hierarchy_tree).has(3), "the hierarchy lists matches but not non-matches"))
	viewer.set_search_filter("")
	checks += 2
	failures += int(not _expect(viewer._graph_nodes_by_id[3].visible, "clearing the filter restores hidden nodes"))
	failures += int(not _expect(_hierarchy_ids(viewer._hierarchy_tree).has(3), "clearing the filter restores the hierarchy"))
	viewer.free()

func _test_source_label() -> void:
	var viewer := _make_viewer()
	var provider := BTMemoryTreeSource.new()
	viewer.set_tree_source(provider)
	checks += 2
	failures += int(not _expect(viewer._source_label.visible, "the source label is visible"))
	failures += int(not _expect(viewer._source_label.text.begins_with("Source:"), "the source label names the source"))
	viewer.free()

func _test_incremental_render_identity() -> void:
	var viewer := _make_viewer()
	var tree := _tree_with_root()
	var child := BTTask.new()
	child.id = 2
	child.friendly_name = "Child"
	tree.connect_parent_child(tree.root_task, child)
	viewer.load_generic_tree(tree, "RenderTree")
	var root_gnode: GraphNode = viewer._graph_nodes_by_id[1]
	var child_gnode: GraphNode = viewer._graph_nodes_by_id[2]
	viewer.select_node_by_id(1)
	var name_edit := _find_line_edit(viewer._inspector_form_container, "Root")
	if name_edit != null:
		name_edit.text_changed.emit("Renamed Root")
	viewer._render_current_tree()
	checks += 2
	failures += int(not _expect(viewer._graph_nodes_by_id[1] == root_gnode, "re-render reuses the surviving GraphNode"))
	failures += int(not _expect(root_gnode.title.contains("Renamed Root"), "the reused node shows the new title"))
	viewer._delete_task(child)
	checks += 2
	failures += int(not _expect(not viewer._graph_nodes_by_id.has(2), "the removed node leaves the graph map"))
	failures += int(not _expect(not is_instance_valid(child_gnode), "the removed GraphNode is freed"))
	viewer.free()
