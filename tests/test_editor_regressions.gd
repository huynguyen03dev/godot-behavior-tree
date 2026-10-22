extends SceneTree
## Focused authoring-path regressions.

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
	var checks := 0
	var failures := 0
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
	print("Editor regressions: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)

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
