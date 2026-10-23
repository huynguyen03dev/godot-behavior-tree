extends SceneTree
## Deep E2E QA Test Suite for Behavior Tree Editor Plugin
## Focuses on data loss, undo/redo discrepancies, save targets, deletion safety, and engine interaction.

var checks: int = 0
var failures: int = 0
var bug_reports: Array[Dictionary] = []

const TEST_BASE_DIR := "user://test_deep_e2e"

func _init() -> void:
	_run.call_deferred()

func _check(condition: bool, name: String, repro: String, expected: String, actual: String, is_blocker: bool = false) -> bool:
	checks += 1
	if not condition:
		failures += 1
		var tag := "[BLOCKER] [FAIL]" if is_blocker else "[FAIL]"
		printerr("%s: %s" % [tag, name])
		printerr("   Repro:    %s" % repro)
		printerr("   Expected: %s" % expected)
		printerr("   Actual:   %s" % actual)
		bug_reports.append({
			"name": name,
			"severity": "BLOCKER" if is_blocker else "MAJOR",
			"repro": repro,
			"expected": expected,
			"actual": actual
		})
		return false
	return true

func _make_viewer() -> BTViewer:
	var viewer: BTViewer = load("res://addons/godot_bt/editor/bt_viewer.gd").new()
	root.add_child(viewer)
	return viewer

func _tree_with_root(root_name: String = "Root") -> BTTree:
	var tree := BTTree.new()
	var root_task := BTComposite.BTSequence.new()
	root_task.id = 1
	root_task.friendly_name = root_name
	root_task.category = "Root"
	tree.set_root(root_task)
	return tree

func _clean_dir(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			dir.remove(file_name)
		else:
			_clean_dir(dir_path.path_join(file_name))
			dir.remove(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(dir_path)

func _are_tree_dicts_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.get("tree_name", "") != b.get("tree_name", ""):
		return false
	if int(a.get("root_id", -1)) != int(b.get("root_id", -1)):
		return false
	if a.get("blackboard", {}) != b.get("blackboard", {}):
		return false
	var a_nodes: Array = a.get("nodes", [])
	var b_nodes: Array = b.get("nodes", [])
	if a_nodes.size() != b_nodes.size():
		return false
	for i in a_nodes.size():
		var an: Dictionary = a_nodes[i]
		var bn: Dictionary = b_nodes[i]
		if int(an.get("id", -1)) != int(bn.get("id", -1)):
			return false
		if an.get("name", "") != bn.get("name", ""):
			return false
		if an.get("friendly_name", "") != bn.get("friendly_name", ""):
			return false
		if an.get("parameters", {}) != bn.get("parameters", {}):
			return false
		if an.get("children", []) != bn.get("children", []):
			return false
	return true

func _are_positions_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a.keys():
		if not b.has(k):
			return false
		var va = a[k]
		var vb = b[k]
		if not (va is Array) or not (vb is Array) or va.size() < 2 or vb.size() < 2:
			return false
		if not is_equal_approx(float(va[0]), float(vb[0])) or not is_equal_approx(float(va[1]), float(vb[1])):
			return false
	return true

func _find_line_edit(node: Node, expected: String) -> LineEdit:
	if node is LineEdit and node.text == expected:
		return node
	for child in node.get_children():
		var found := _find_line_edit(child, expected)
		if found != null:
			return found
	return null

func _find_button(node: Node, expected: String) -> Button:
	for child in node.get_children():
		if child is Button and (child as Button).text.contains(expected):
			return child
		var found := _find_button(child, expected)
		if found != null:
			return found
	return null

# ==============================================================================
# GROUP 1: Naming & Save As
# ==============================================================================
func _test_group1_naming_and_save_as() -> void:
	var group_dir := TEST_BASE_DIR.path_join("group1")
	DirAccess.make_dir_recursive_absolute(group_dir)
	var source := BTFileTreeSource.new(group_dir)
	var viewer := _make_viewer()
	viewer.set_tree_source(source)

	# 1.1 Tạo tree mới khi đã có tree đang mở (không được ghi đè file cũ)
	var tree_a := _tree_with_root("TreeA_Root")
	tree_a.tree_name = "TreeA"
	source.save_tree("TreeA", tree_a)
	viewer.load_tree_by_name("TreeA")

	viewer._on_new_tree_pressed()
	if viewer._new_tree_dialog != null and viewer._new_tree_dialog.visible:
		viewer._new_tree_line_edit.text = "TreeB"
		viewer._new_tree_dialog.confirmed.emit()

	var tree_a_on_disk := source.load_tree("TreeA")
	_check(
		tree_a_on_disk != null and tree_a_on_disk.root_task.friendly_name == "TreeA_Root",
		"Group 1.1: Creating new tree does not overwrite currently opened tree file on disk",
		"1. Load TreeA. 2. Click New Tree button, confirm name TreeB. 3. Inspect TreeA.json on disk.",
		"TreeA.json on disk must remain intact with its original content.",
		"TreeA.json exists: %s, root name: %s" % [tree_a_on_disk != null, tree_a_on_disk.root_task.friendly_name if tree_a_on_disk else "null"],
		true
	)
	_check(
		viewer.current_tree_name == "TreeB",
		"Group 1.1: Current tree name updated to new tree name",
		"Confirm new tree dialog with name TreeB.",
		"viewer.current_tree_name == 'TreeB'",
		"viewer.current_tree_name == '%s'" % viewer.current_tree_name
	)

	# Save TreeB to disk
	viewer.save_current_tree()
	tree_a_on_disk = source.load_tree("TreeA")
	var tree_b_on_disk := source.load_tree("TreeB")
	_check(
		tree_a_on_disk != null and tree_b_on_disk != null and tree_a_on_disk.root_task.friendly_name == "TreeA_Root",
		"Group 1.1: Saving new tree writes to TreeB and leaves TreeA untouched",
		"1. After creating TreeB, call viewer.save_current_tree(). 2. Inspect TreeA and TreeB on disk.",
		"TreeA untouched; TreeB written to disk.",
		"TreeA: %s, TreeB: %s" % [tree_a_on_disk.root_task.friendly_name if tree_a_on_disk else "null", tree_b_on_disk != null]
	)

	# 1.2 Save As sang tên mới
	viewer.load_tree_by_name("TreeA")
	viewer.current_tree.root_task.friendly_name = "TreeA_Modified"
	var tree_c_path := group_dir.path_join("TreeC.json")
	var save_as_ok := viewer.save_tree_as(tree_c_path)
	var tree_c_on_disk := source.load_tree("TreeC")
	tree_a_on_disk = source.load_tree("TreeA")
	_check(
		save_as_ok and tree_c_on_disk != null and tree_c_on_disk.root_task.friendly_name == "TreeA_Modified" and tree_a_on_disk.root_task.friendly_name == "TreeA_Root",
		"Group 1.2: Save As creates new file and preserves original file",
		"1. Load TreeA. 2. Modify node in RAM. 3. Save As TreeC.json. 4. Inspect TreeA.json and TreeC.json.",
		"TreeC has modified content; TreeA has original content.",
		"save_as_ok: %s, TreeC root: %s, TreeA root: %s" % [save_as_ok, tree_c_on_disk.root_task.friendly_name if tree_c_on_disk else "null", tree_a_on_disk.root_task.friendly_name if tree_a_on_disk else "null"],
		true
	)

	# 1.3 Save As đè file đã tồn tại (prompt confirm)
	viewer.load_tree_by_name("TreeC")
	viewer.current_tree.root_task.friendly_name = "TreeC_Overwriting_B"
	var target_b_path := group_dir.path_join("TreeB.json")
	viewer._on_save_as_file_selected(target_b_path)
	var prompt_shown := viewer._save_as_confirm_dialog != null and viewer._save_as_confirm_dialog.visible
	_check(
		prompt_shown,
		"Group 1.3: Save As over existing file prompts confirmation dialog",
		"1. Select existing file path in Save As. 2. Check if _save_as_confirm_dialog is shown.",
		"_save_as_confirm_dialog.visible == true",
		"prompt_shown == %s" % prompt_shown
	)
	# Hide without confirming: file TreeB on disk must NOT be modified
	if viewer._save_as_confirm_dialog != null:
		viewer._save_as_confirm_dialog.hide()
	var tree_b_unconfirmed := source.load_tree("TreeB")
	_check(
		tree_b_unconfirmed != null and tree_b_unconfirmed.root_task.friendly_name != "TreeC_Overwriting_B",
		"Group 1.3: Cancelling Save As overwrite does not overwrite target file",
		"1. Save As selecting TreeB.json. 2. Hide/cancel confirmation dialog. 3. Check TreeB on disk.",
		"TreeB on disk is not overwritten.",
		"TreeB root: %s" % [tree_b_unconfirmed.root_task.friendly_name if tree_b_unconfirmed else "null"],
		true
	)
	# Now confirm overwrite
	viewer._on_save_as_file_selected(target_b_path)
	if viewer._save_as_confirm_dialog != null:
		viewer._save_as_confirm_dialog.confirmed.emit()
	var tree_b_confirmed := source.load_tree("TreeB")
	_check(
		tree_b_confirmed != null and tree_b_confirmed.root_task.friendly_name == "TreeC_Overwriting_B",
		"Group 1.3: Confirming Save As overwrite updates target file and current_tree_name",
		"1. Emit confirmed on _save_as_confirm_dialog. 2. Inspect TreeB on disk.",
		"TreeB on disk updated with new content; viewer.current_tree_name == 'TreeB'",
		"TreeB root: %s, viewer.current_tree_name: %s" % [tree_b_confirmed.root_task.friendly_name if tree_b_confirmed else "null", viewer.current_tree_name]
	)

	# 1.4 Tên có khoảng trắng / ký tự lạ / unicode
	var unicode_name := "Cây hành vi 🌲"
	var space_name := "Tree With Space"
	var special_name := "Tree_!@#$"
	var tree_uni := _tree_with_root("UniRoot")
	tree_uni.tree_name = unicode_name
	var ok_uni := source.save_tree(unicode_name, tree_uni)
	var loaded_uni := source.load_tree(unicode_name)
	_check(
		ok_uni and loaded_uni != null and loaded_uni.tree_name == unicode_name,
		"Group 1.4: Tree with Unicode name saves and loads correctly",
		"source.save_tree('Cây hành vi 🌲', tree) then source.load_tree('Cây hành vi 🌲')",
		"Saved and loaded successfully with matching tree_name",
		"ok_uni: %s, loaded: %s" % [ok_uni, loaded_uni != null]
	)
	var tree_space := _tree_with_root("SpaceRoot")
	tree_space.tree_name = space_name
	var ok_space := source.save_tree(space_name, tree_space)
	var loaded_space := source.load_tree(space_name)
	_check(
		ok_space and loaded_space != null and loaded_space.tree_name == space_name,
		"Group 1.4: Tree with spaces in name saves and loads correctly",
		"source.save_tree('Tree With Space', tree) then load_tree('Tree With Space')",
		"Saved and loaded successfully with matching tree_name",
		"ok_space: %s, loaded: %s" % [ok_space, loaded_space != null]
	)

	# 1.5 Tên rỗng
	var ok_empty_save := viewer.save_tree_as("")
	_check(
		not ok_empty_save,
		"Group 1.5: save_tree_as with empty path is rejected safely",
		"viewer.save_tree_as('')",
		"Returns false without crashing or creating blank file",
		"Returns %s" % ok_empty_save
	)
	viewer._on_new_tree_pressed()
	if viewer._new_tree_line_edit != null:
		viewer._new_tree_line_edit.text = "   "
		viewer._on_new_tree_dialog_confirmed()
	_check(
		viewer.current_tree_name != "" and viewer.current_tree_name != "   ",
		"Group 1.5: New tree dialog with empty/whitespace input falls back to valid unused name",
		"Enter whitespace '   ' in new tree dialog and confirm.",
		"viewer.current_tree_name is assigned an automatic non-empty name like new_tree_X",
		"viewer.current_tree_name == '%s'" % viewer.current_tree_name
	)

	# 1.6 Đổi tên tree rồi Save (ngữ nghĩa Save-As khi đổi tên)
	# Khi người dùng mở file TreeOrig.json, sửa tree_name = "TreeRenamed" trong JSON tab rồi ấn Save:
	# File mới TreeRenamed.json được tạo, can_auto_save() vẫn true, autosave ghi đúng file mới, file cũ không bị sửa.
	var orig_tree := _tree_with_root("OrigRoot")
	orig_tree.tree_name = "TreeOrig"
	source.save_tree("TreeOrig", orig_tree)
	viewer.load_tree_by_name("TreeOrig")

	viewer._tab_bar.current_tab = 2
	var json_dict: Dictionary = viewer.current_tree.to_dict()
	json_dict["tree_name"] = "TreeRenamed"
	json_dict["nodes"][0]["friendly_name"] = "OrigRoot_Renamed"
	viewer._json_text_edit.text = JSON.stringify(json_dict, "\t")
	viewer._json_text_edit.text_changed.emit()
	viewer._on_apply_json_pressed()
	viewer.save_current_tree()

	var files_after := DirAccess.get_files_at(group_dir)
	var orig_file_content := source.load_tree("TreeOrig")
	var renamed_file_content := source.load_tree("TreeRenamed")
	var auto_save_still_valid := viewer.can_auto_save()

	# Test autosave writes to the new file and keeps old file intact
	viewer.current_tree.root_task.friendly_name = "OrigRoot_Autosaved"
	var auto_saved := viewer.auto_save_external_data()
	var renamed_after_autosave := source.load_tree("TreeRenamed")
	var orig_after_autosave := source.load_tree("TreeOrig")
	var autosave_targets_new_file: bool = auto_saved and \
		renamed_after_autosave != null and renamed_after_autosave.root_task.friendly_name == "OrigRoot_Autosaved" and \
		orig_after_autosave != null and orig_after_autosave.root_task.friendly_name == "OrigRoot"

	_check(
		auto_save_still_valid and \
		renamed_file_content != null and renamed_file_content.root_task.friendly_name == "OrigRoot_Renamed" and \
		orig_file_content != null and orig_file_content.root_task.friendly_name == "OrigRoot" and \
		autosave_targets_new_file,
		"Group 1.6: Renaming tree and saving follows Save-As semantics (new file created, autosave tracks new file, original file unchanged)",
		"1. Load TreeOrig.json. 2. Edit tree_name to TreeRenamed in JSON tab & apply. 3. Click Save.",
		"New file is created with new name, original file remains unchanged, can_auto_save() remains true, and autosave targets the new file.",
		"can_auto_save(): %s, files: %s, TreeOrig root: %s, TreeRenamed root: %s, autosave_ok: %s" % [
			auto_save_still_valid,
			str(files_after),
			orig_file_content.root_task.friendly_name if orig_file_content else "null",
			renamed_file_content.root_task.friendly_name if renamed_file_content else "null",
			autosave_targets_new_file
		],
		true
	)

	viewer.free()

# ==============================================================================
# GROUP 2: Autosave / Ctrl+S
# ==============================================================================
func _test_group2_autosave_and_ctrl_s() -> void:
	var group_dir := TEST_BASE_DIR.path_join("group2")
	DirAccess.make_dir_recursive_absolute(group_dir)
	var source := BTFileTreeSource.new(group_dir)
	var viewer := _make_viewer()
	viewer.set_tree_source(source)

	# 2.1 Sau khi sửa node rồi Ctrl+S, file trên đĩa phải khớp model
	var tree_auto := _tree_with_root("InitialAutoRoot")
	tree_auto.tree_name = "AutoSaveTest"
	source.save_tree("AutoSaveTest", tree_auto)
	viewer.load_tree_by_name("AutoSaveTest")

	# Sửa node qua inspector (submitted)
	viewer.select_node_by_id(1)
	viewer.current_tree.root_task.friendly_name = "EditedAutoRoot"
	viewer._record_mutation("Rename Root", func():
		viewer._render_current_tree()
	)
	var auto_saved := viewer.auto_save_external_data()
	var on_disk := source.load_tree("AutoSaveTest")
	_check(
		auto_saved and on_disk != null and on_disk.root_task.friendly_name == "EditedAutoRoot",
		"Group 2.1: Model mutation followed by auto_save_external_data updates file on disk to match model",
		"1. Edit node friendly_name. 2. Call auto_save_external_data(). 3. Read file from disk.",
		"File on disk matches in-memory model (EditedAutoRoot).",
		"auto_saved: %s, on_disk root: %s" % [auto_saved, on_disk.root_task.friendly_name if on_disk else "null"]
	)

	# 2.2 Sửa text trong Inspector nhưng chưa nhấn Enter / blur, rồi Save/Ctrl+S (DATA LOSS CHECK)
	# Khi user đang gõ tên trong LineEdit và bấm Ctrl+S / Save, dữ liệu trong LineEdit phải được commit và lưu
	viewer.select_node_by_id(1)
	var name_edit := _find_line_edit(viewer._inspector_form_container, "EditedAutoRoot")
	if name_edit != null:
		name_edit.text = "InFlightEditedName"
		name_edit.text_changed.emit("InFlightEditedName")
		# Người dùng KHÔNG ấn Enter và focus chưa thoát, nhưng thực hiện Save / Ctrl+S
		viewer.save_current_tree()
		var on_disk_inflight := source.load_tree("AutoSaveTest")
		_check(
			on_disk_inflight != null and on_disk_inflight.root_task.friendly_name == "InFlightEditedName",
			"Group 2.2: In-flight inspector LineEdit edit is committed on save (Data loss prevention)",
			"1. Type new name in LineEdit without pressing Enter. 2. Trigger save_current_tree(). 3. Inspect file on disk.",
			"File on disk saves the active LineEdit text 'InFlightEditedName'.",
			"File on disk has '%s'" % [on_disk_inflight.root_task.friendly_name if on_disk_inflight else "null"],
			true
		)

		# 2.2b: Test in-flight LineEdit text is committed on Ctrl+S shortcut
		name_edit.text = "InFlightViaCtrlS"
		name_edit.text_changed.emit("InFlightViaCtrlS")
		var ctrl_s_ev := InputEventKey.new()
		ctrl_s_ev.pressed = true
		ctrl_s_ev.keycode = KEY_S
		ctrl_s_ev.ctrl_pressed = true
		viewer._shortcut_input(ctrl_s_ev)
		var on_disk_ctrl_s := source.load_tree("AutoSaveTest")
		_check(
			on_disk_ctrl_s != null and on_disk_ctrl_s.root_task.friendly_name == "InFlightViaCtrlS",
			"Group 2.2b: In-flight inspector edit is committed on Ctrl+S shortcut",
			"1. Type new name in LineEdit. 2. Press Ctrl+S without Enter or blur. 3. Inspect file on disk.",
			"File on disk saves 'InFlightViaCtrlS'.",
			"File on disk has '%s'" % [on_disk_ctrl_s.root_task.friendly_name if on_disk_ctrl_s else "null"],
			true
		)

		# 2.2c: Test in-flight SpinBox edit is committed on save
		viewer.current_tree.root_task.parameters["speed"] = 10
		viewer.save_current_tree()
		viewer._update_inspector()
		var le_spin := _find_line_edit(viewer._inspector_form_container, "10")
		if le_spin != null:
			le_spin.text = "77"
			le_spin.text_changed.emit("77")
			viewer.save_current_tree()
			var on_disk_spin := source.load_tree("AutoSaveTest")
			var saved_speed = on_disk_spin.root_task.parameters.get("speed") if on_disk_spin else null
			_check(
				int(saved_speed) == 77,
				"Group 2.2c: In-flight inspector SpinBox edit is committed on save",
				"1. Change SpinBox LineEdit text to 77 without Enter. 2. Trigger save_current_tree(). 3. Inspect file on disk.",
				"File on disk saves parameter 'speed' = 77.",
				"File on disk has speed: %s" % str(saved_speed),
				true
			)

	# 2.3 Autosave không được ghi khi tree chưa từng được lưu
	viewer._create_new_tree("ScratchNeverSaved")
	viewer.current_tree.root_task.friendly_name = "ScratchModified"
	_check(
		not viewer.can_auto_save(),
		"Group 2.3: can_auto_save() returns false for scratch tree never saved to disk",
		"Create new tree, check viewer.can_auto_save().",
		"can_auto_save() == false",
		"can_auto_save() == %s" % viewer.can_auto_save()
	)
	var scratch_saved := viewer.auto_save_external_data()
	var scratch_on_disk := source.load_tree("ScratchNeverSaved")
	_check(
		not scratch_saved and scratch_on_disk == null and viewer._stats_label.text.contains("Skipped autosave"),
		"Group 2.3: auto_save_external_data rejects scratch tree and logs status",
		"Call auto_save_external_data() on unsaved scratch tree.",
		"Returns false, no file created, stats label explains skipped autosave.",
		"scratch_saved: %s, file exists: %s, stats: '%s'" % [scratch_saved, scratch_on_disk != null, viewer._stats_label.text]
	)

	# 2.4 Autosave khi đang kéo node
	# Khi node đang di chuyển trong graph, autosave không được làm hỏng trạng thái undo hoặc corrupt model
	viewer.load_tree_by_name("AutoSaveTest")
	var gn1: GraphNode = viewer._graph_nodes_by_id[1]
	gn1.position_offset = Vector2(888, 999)
	viewer._on_node_position_changed()
	var auto_during_drag := viewer.auto_save_external_data()
	var disk_tree_drag := source.load_tree("AutoSaveTest")
	var saved_pos: Dictionary = disk_tree_drag.metadata.get("node_positions", {}) if disk_tree_drag else {}
	_check(
		auto_during_drag and saved_pos.has("1") and is_equal_approx(float(saved_pos["1"][0]), 888.0),
		"Group 2.4: Autosave during node drag persists valid node positions to disk",
		"1. Move GraphNode offset. 2. _on_node_position_changed(). 3. auto_save_external_data().",
		"Positions written safely to disk metadata without corruption.",
		"auto_during_drag: %s, saved_pos: %s" % [auto_during_drag, str(saved_pos)]
	)

	viewer.free()

# ==============================================================================
# GROUP 3: Undo / Redo
# ==============================================================================
func _test_group3_undo_redo() -> void:
	var viewer := _make_viewer()
	var tree := _tree_with_root("RootTask")
	viewer.load_generic_tree(tree, "UndoRedoTree")

	# 3.1 Mỗi edit là 1 bước undo (không phải mỗi keystroke)
	viewer.select_node_by_id(1)
	var name_edit := _find_line_edit(viewer._inspector_form_container, "RootTask")
	if name_edit != null:
		name_edit.text = "R"
		name_edit.text_changed.emit("R")
		name_edit.text = "Ro"
		name_edit.text_changed.emit("Ro")
		name_edit.text = "Roo"
		name_edit.text_changed.emit("Roo")
		name_edit.text = "RootCommitted"
		name_edit.text_submitted.emit("RootCommitted")

	_check(
		viewer.current_tree.root_task.friendly_name == "RootCommitted" and viewer.has_undo(),
		"Group 3.1: Keystrokes accumulate, single commit creates single undo action",
		"Emit text_changed multiple times, then single text_submitted.",
		"Model updated to RootCommitted, exactly 1 action in undo stack.",
		"Root name: '%s', has_undo: %s" % [viewer.current_tree.root_task.friendly_name, viewer.has_undo()]
	)
	viewer.undo()
	_check(
		viewer.current_tree.root_task.friendly_name == "RootTask" and not viewer.has_undo(),
		"Group 3.1: Single undo restores original name, undo stack empty",
		"viewer.undo() once after multiple keystrokes.",
		"Restores 'RootTask' and has_undo() is false.",
		"Root name: '%s', has_undo: %s" % [viewer.current_tree.root_task.friendly_name, viewer.has_undo()]
	)
	viewer.redo()
	_check(
		viewer.current_tree.root_task.friendly_name == "RootCommitted",
		"Group 3.1: Redo re-applies committed edit",
		"viewer.redo()",
		"Root name is 'RootCommitted'",
		"Root name: '%s'" % viewer.current_tree.root_task.friendly_name
	)

	# 3.2 Undo/redo: thêm node
	viewer.clear_undo_history()
	var popup: PopupMenu = viewer._add_task_menu_button.get_popup()
	var seq_id := -1
	for i in popup.item_count:
		if str(popup.get_item_metadata(i)).contains("Sequence") or popup.get_item_text(i).contains("Sequence"):
			seq_id = popup.get_item_id(i)
			break
	if seq_id == -1 and popup.item_count > 0:
		seq_id = popup.get_item_id(0)

	popup.id_pressed.emit(seq_id)
	var added_id := viewer.selected_node_id
	var nodes_after_add := viewer.current_tree.get_node_count()
	_check(
		added_id > 1 and nodes_after_add == 2,
		"Group 3.2: Adding node adds node and selects it",
		"Trigger add task from popup menu.",
		"Added node id > 1, total nodes == 2",
		"added_id: %d, total nodes: %d" % [added_id, nodes_after_add]
	)
	viewer.undo()
	_check(
		viewer.current_tree.get_node_by_id(added_id) == null and viewer.current_tree.get_node_count() == 1,
		"Group 3.2: Undo Add Task removes added node from model",
		"viewer.undo()",
		"Added node is null, total nodes == 1",
		"node exists: %s, total nodes: %d" % [viewer.current_tree.get_node_by_id(added_id) != null, viewer.current_tree.get_node_count()]
	)
	viewer.redo()
	_check(
		viewer.current_tree.get_node_by_id(added_id) != null and viewer.current_tree.get_node_count() == 2,
		"Group 3.2: Redo Add Task restores added node",
		"viewer.redo()",
		"Node restored in model",
		"node exists: %s, total nodes: %d" % [viewer.current_tree.get_node_by_id(added_id) != null, viewer.current_tree.get_node_count()]
	)

	# 3.3 Undo/redo: xoá node
	var task_to_delete: BTTask = viewer.current_tree.get_node_by_id(added_id)
	viewer._delete_task(task_to_delete)
	_check(
		viewer.current_tree.get_node_by_id(added_id) == null,
		"Group 3.3: Delete task removes node",
		"viewer._delete_task(added_task)",
		"Node removed from model",
		"Node exists: %s" % (viewer.current_tree.get_node_by_id(added_id) != null)
	)
	viewer.undo()
	_check(
		viewer.current_tree.get_node_by_id(added_id) != null,
		"Group 3.3: Undo delete task restores node in model",
		"viewer.undo()",
		"Node restored in model",
		"Node exists: %s" % (viewer.current_tree.get_node_by_id(added_id) != null)
	)
	viewer.redo()
	_check(
		viewer.current_tree.get_node_by_id(added_id) == null,
		"Group 3.3: Redo delete task re-deletes node",
		"viewer.redo()",
		"Node deleted again",
		"Node exists: %s" % (viewer.current_tree.get_node_by_id(added_id) != null)
	)

	# 3.4 Undo/redo: nối cạnh & ngắt cạnh
	# Chuẩn bị 2 node độc lập
	viewer.undo() # Khôi phục node added_id
	var root_id: int = viewer.current_tree.root_task.id
	var child_task_init: BTTask = viewer.current_tree.get_node_by_id(added_id)
	viewer.current_tree.disconnect_parent_child(viewer.current_tree.root_task, child_task_init)
	viewer.clear_undo_history()

	# Nối cạnh
	viewer._on_graph_connection_request(
		StringName("Node_%d" % root_id), 0,
		StringName("Node_%d" % added_id), 0
	)
	var child_connected: BTTask = viewer.current_tree.get_node_by_id(added_id)
	_check(
		child_connected != null and child_connected.parent == viewer.current_tree.root_task,
		"Group 3.4: Connection request connects parent and child",
		"viewer._on_graph_connection_request(from, 0, to, 0)",
		"child.parent == root_task",
		"child.parent: %s" % [child_connected.parent if child_connected else "null"]
	)
	viewer.undo()
	var child_undone: BTTask = viewer.current_tree.get_node_by_id(added_id)
	_check(
		child_undone != null and child_undone.parent == null,
		"Group 3.4: Undo connection disconnects parent and child",
		"viewer.undo()",
		"child.parent == null",
		"child.parent: %s" % [child_undone.parent if child_undone else "null"]
	)
	viewer.redo()
	var child_redone: BTTask = viewer.current_tree.get_node_by_id(added_id)
	_check(
		child_redone != null and child_redone.parent == viewer.current_tree.root_task,
		"Group 3.4: Redo connection restores parent-child link",
		"viewer.redo()",
		"child.parent == root_task",
		"child.parent: %s" % [child_redone.parent if child_redone else "null"]
	)

	# Ngắt cạnh
	viewer._on_graph_disconnection_request(
		StringName("Node_%d" % root_id), 0,
		StringName("Node_%d" % added_id), 0
	)
	var child_disc: BTTask = viewer.current_tree.get_node_by_id(added_id)
	_check(
		child_disc != null and child_disc.parent == null,
		"Group 3.4: Disconnection request disconnects parent and child",
		"viewer._on_graph_disconnection_request(from, 0, to, 0)",
		"child.parent == null",
		"child.parent: %s" % [child_disc.parent if child_disc else "null"]
	)
	viewer.undo()
	var child_disc_undone: BTTask = viewer.current_tree.get_node_by_id(added_id)
	_check(
		child_disc_undone != null and child_disc_undone.parent == viewer.current_tree.root_task,
		"Group 3.4: Undo disconnection restores link",
		"viewer.undo()",
		"child.parent == root_task",
		"child.parent: %s" % [child_disc_undone.parent if child_disc_undone else "null"]
	)

	# 3.5 Undo/redo: đổi parameter qua inspector
	viewer.select_node_by_id(added_id)
	viewer._record_mutation("Add Parameter", func():
		var t: BTTask = viewer.current_tree.get_node_by_id(added_id)
		if t != null:
			t.parameters["target_speed"] = 42
		viewer._update_inspector()
	)
	var t_param: BTTask = viewer.current_tree.get_node_by_id(added_id)
	_check(
		t_param != null and int(t_param.parameters.get("target_speed", 0)) == 42,
		"Group 3.5: Parameter set to 42",
		"Add parameter target_speed = 42",
		"parameters['target_speed'] == 42",
		"param: %s" % [t_param.parameters.get("target_speed") if t_param else "null"]
	)
	viewer.undo()
	var t_param_undone: BTTask = viewer.current_tree.get_node_by_id(added_id)
	_check(
		t_param_undone != null and not t_param_undone.parameters.has("target_speed"),
		"Group 3.5: Undo parameter edit restores previous parameters",
		"viewer.undo()",
		"parameter removed",
		"has target_speed: %s" % (t_param_undone.parameters.has("target_speed") if t_param_undone else "null")
	)

	# 3.6 Undo sau khi kéo node (với luồng thật GraphNode di chuyển)
	# BUG CHECK: Trong runtime thật, GraphNode emit position_offset_changed -> _on_node_position_changed -> _on_graph_end_node_move
	var gnode_child: GraphNode = viewer._graph_nodes_by_id.get(added_id, null)
	if gnode_child != null:
		var orig_pos := gnode_child.position_offset
		var orig_metadata_pos: Variant = viewer.current_tree.metadata.get("node_positions", {}).get(str(added_id), null)
		var target_pos := Vector2(orig_pos.x + 200, orig_pos.y + 150)
		viewer._on_graph_begin_node_move()
		gnode_child.position_offset = target_pos
		# Trigger sự kiện thay đổi offset như khi user kéo node
		viewer._on_node_position_changed()
		viewer._on_graph_end_node_move()
		var move_has_undo := viewer.has_undo() and viewer.undo_redo.get_current_action_name() == "Move Nodes"
		_check(
			move_has_undo,
			"Group 3.6: Dragging node records Move Nodes undo action when position_offset_changed was emitted",
			"1. Move GraphNode offset. 2. _on_node_position_changed(). 3. _on_graph_end_node_move(). 4. Check has_undo.",
			"Undo action 'Move Nodes' is recorded.",
			"has_undo: %s, action: '%s'" % [viewer.has_undo(), viewer.undo_redo.get_current_action_name() if viewer.has_undo() else "none"],
			true
		)

		# 3.6b: Undo restores exact original node positions
		viewer.undo()
		var meta_pos_after_undo: Variant = viewer.current_tree.metadata.get("node_positions", {}).get(str(added_id), null)
		var gn_offset_after_undo := gnode_child.position_offset
		var meta_matched: bool = (orig_metadata_pos == null and meta_pos_after_undo == null) or (
			orig_metadata_pos is Array and meta_pos_after_undo is Array and \
			is_equal_approx(float(meta_pos_after_undo[0]), float(orig_metadata_pos[0])) and \
			is_equal_approx(float(meta_pos_after_undo[1]), float(orig_metadata_pos[1]))
		)
		var offset_matched: bool = is_equal_approx(gn_offset_after_undo.x, orig_pos.x) and \
			is_equal_approx(gn_offset_after_undo.y, orig_pos.y)
		var undo_restored_pos: bool = meta_matched and offset_matched
		_check(
			undo_restored_pos,
			"Group 3.6b: Undo restores exact original node position in metadata and GraphNode",
			"1. Drag node to new position. 2. Call viewer.undo(). 3. Verify positions match orig_pos.",
			"Position matches original: %s" % str(orig_pos),
			"Meta pos: %s, GraphNode offset: %s" % [str(meta_pos_after_undo), str(gn_offset_after_undo)],
			true
		)

		# 3.6c: Redo re-applies new dragged node positions
		viewer.redo()
		var meta_pos_after_redo: Array = viewer.current_tree.metadata.get("node_positions", {}).get(str(added_id), [])
		var gn_offset_after_redo := gnode_child.position_offset
		var redo_restored_pos: bool = meta_pos_after_redo.size() >= 2 and \
			is_equal_approx(float(meta_pos_after_redo[0]), target_pos.x) and \
			is_equal_approx(float(meta_pos_after_redo[1]), target_pos.y) and \
			is_equal_approx(gn_offset_after_redo.x, target_pos.x) and \
			is_equal_approx(gn_offset_after_redo.y, target_pos.y)
		_check(
			redo_restored_pos,
			"Group 3.6c: Redo re-applies new dragged node position",
			"1. Call viewer.redo() after undoing node move. 2. Verify positions match target_pos.",
			"Position matches target: %s" % str(target_pos),
			"Meta pos: %s, GraphNode offset: %s" % [str(meta_pos_after_redo), str(gn_offset_after_redo)],
			true
		)

		# 3.6d: Zero-delta drag does not create an undo action
		viewer.clear_undo_history()
		viewer._on_graph_begin_node_move()
		viewer._on_node_position_changed()
		viewer._on_graph_end_node_move()
		_check(
			not viewer.has_undo(),
			"Group 3.6d: Dragging node with zero position change does not create undo action",
			"1. Begin move without position offset change. 2. End move. 3. Check viewer.has_undo().",
			"viewer.has_undo() == false",
			"has_undo: %s" % viewer.has_undo()
		)

		# 3.6e: Dragging multiple nodes records exactly 1 Move Nodes action and undo restores all of them
		viewer.clear_undo_history()
		var root_gn: GraphNode = viewer._graph_nodes_by_id.get(1, null)
		if root_gn != null:
			var root_orig_pos := root_gn.position_offset
			var child_orig_pos := gnode_child.position_offset
			viewer._on_graph_begin_node_move()
			root_gn.position_offset = Vector2(root_orig_pos.x + 50, root_orig_pos.y + 50)
			gnode_child.position_offset = Vector2(child_orig_pos.x + 80, child_orig_pos.y + 80)
			viewer._on_node_position_changed()
			viewer._on_graph_end_node_move()

			var multi_move_has_undo := viewer.has_undo() and viewer.undo_redo.get_current_action_name() == "Move Nodes"
			viewer.undo()
			var multi_undone: bool = is_equal_approx(root_gn.position_offset.x, root_orig_pos.x) and \
				is_equal_approx(root_gn.position_offset.y, root_orig_pos.y) and \
				is_equal_approx(gnode_child.position_offset.x, child_orig_pos.x) and \
				is_equal_approx(gnode_child.position_offset.y, child_orig_pos.y)
			viewer.redo()
			var multi_redone: bool = is_equal_approx(root_gn.position_offset.x, root_orig_pos.x + 50) and \
				is_equal_approx(root_gn.position_offset.y, root_orig_pos.y + 50) and \
				is_equal_approx(gnode_child.position_offset.x, child_orig_pos.x + 80) and \
				is_equal_approx(gnode_child.position_offset.y, child_orig_pos.y + 80)
			_check(
				multi_move_has_undo and multi_undone and multi_redone,
				"Group 3.6e: Multi-node drag creates single Move Nodes action and undo/redo restores all nodes",
				"1. Move two nodes in one drag. 2. End drag. 3. Undo and Redo.",
				"Single Move Nodes action, both nodes restored on undo, both reapplied on redo.",
				"has_undo: %s, multi_undone: %s, multi_redone: %s" % [multi_move_has_undo, multi_undone, multi_redone],
				true
			)

	# 3.7 Undo khi đang có selection
	viewer.select_node_by_id(added_id)
	viewer._record_mutation("Rename Child", func():
		var t_sel: BTTask = viewer.current_tree.get_node_by_id(added_id)
		if t_sel != null:
			t_sel.friendly_name = "SelectedChild_NewName"
	)
	viewer.undo()
	var t_reverted: BTTask = viewer.current_tree.get_node_by_id(added_id)
	_check(
		viewer.selected_node_id == added_id and t_reverted != null and t_reverted.friendly_name != "SelectedChild_NewName",
		"Group 3.7: Undo while selection is active retains selected_node_id and restores model",
		"1. Select node. 2. Mutate node name. 3. viewer.undo().",
		"selected_node_id is preserved and node name is reverted.",
		"selected_node_id: %d, name: '%s'" % [viewer.selected_node_id, t_reverted.friendly_name if t_reverted else "null"]
	)

	# 3.8 Undo/Redo 20 bước liên tiếp không lệch model
	viewer.clear_undo_history()
	var step_snapshots: Array[String] = []
	step_snapshots.append(JSON.stringify(viewer.current_tree.to_dict()))

	for step in range(1, 21):
		var step_num := step
		viewer._record_mutation("Step_%d" % step_num, func():
			var t := BTTask.new()
			t.id = 100 + step_num
			t.friendly_name = "Task_Step_%d" % step_num
			t.parameters["step_val"] = step_num * 10
			viewer.current_tree.add_node(t)
			viewer.current_tree.connect_parent_child(viewer.current_tree.root_task, t)
		)
		step_snapshots.append(JSON.stringify(viewer.current_tree.to_dict()))

	var undo_ok := true
	var undo_fail_step := -1
	for step in range(20, 0, -1):
		viewer.undo()
		var cur_d: Dictionary = viewer.current_tree.to_dict()
		var exp_d: Dictionary = JSON.parse_string(step_snapshots[step - 1])
		# So sánh theo cấu trúc dict (tránh lệch thứ tự key khi JSON.stringify)
		if not _are_tree_dicts_equal(cur_d, exp_d):
			undo_ok = false
			undo_fail_step = step
			print("DEBUG: Structural mismatch at step %d" % step)
			break

	_check(
		undo_ok,
		"Group 3.8: 20 consecutive undo steps restore exact previous snapshots without drift",
		"Perform 20 mutations, undo 20 times comparing serialized dictionary at each step.",
		"All 20 undo states match exactly.",
		"Failed at step: %d" % undo_fail_step
	)

	var redo_ok := true
	var redo_fail_step := -1
	for step in range(1, 21):
		viewer.redo()
		var cur_d: Dictionary = viewer.current_tree.to_dict()
		var exp_d: Dictionary = JSON.parse_string(step_snapshots[step])
		if not _are_tree_dicts_equal(cur_d, exp_d):
			redo_ok = false
			redo_fail_step = step
			print("DEBUG: Redo structural mismatch at step %d" % step)
			break

	_check(
		redo_ok,
		"Group 3.8: 20 consecutive redo steps restore exact forward snapshots without drift",
		"Redo 20 times comparing serialized dictionary at each step.",
		"All 20 redo states match exactly.",
		"Failed at step: %d" % redo_fail_step
	)

	viewer.free()

# ==============================================================================
# GROUP 4: JSON view
# ==============================================================================
func _test_group4_json_view() -> void:
	var viewer := _make_viewer()
	var tree := _tree_with_root("JsonRoot")
	var child := BTTask.new()
	child.id = 2
	child.friendly_name = "JsonChild"
	tree.connect_parent_child(tree.root_task, child)
	viewer.load_generic_tree(tree, "JsonTestTree")

	# 4.1 Sửa JSON hợp lệ → apply → model đúng
	viewer._tab_bar.current_tab = 2
	var valid_dict: Dictionary = tree.to_dict()
	valid_dict["nodes"][1]["friendly_name"] = "JsonChild_Applied"
	viewer._json_text_edit.text = JSON.stringify(valid_dict, "\t")
	viewer._json_text_edit.text_changed.emit()
	viewer._on_apply_json_pressed()

	_check(
		viewer.current_tree.get_node_by_id(2) != null and viewer.current_tree.get_node_by_id(2).friendly_name == "JsonChild_Applied",
		"Group 4.1: Valid JSON edit applies and updates in-memory model",
		"1. Edit JSON text. 2. _on_apply_json_pressed(). 3. Check current_tree node 2 friendly_name.",
		"Node 2 friendly_name is 'JsonChild_Applied'",
		"Node 2 friendly_name is '%s'" % [viewer.current_tree.get_node_by_id(2).friendly_name if viewer.current_tree.get_node_by_id(2) else "null"]
	)

	# 4.2 JSON sai cú pháp → báo lỗi, không phá model hiện tại
	var model_before_bad_syntax := JSON.stringify(viewer.current_tree.to_dict())
	viewer._json_text_edit.text = "{\"nodes\": [ unclosed syntax error..."
	viewer._json_text_edit.text_changed.emit()
	viewer._on_apply_json_pressed()

	var model_after_bad_syntax := JSON.stringify(viewer.current_tree.to_dict())
	_check(
		viewer._json_status_label.text.begins_with("❌") and model_after_bad_syntax == model_before_bad_syntax,
		"Group 4.2: Malformed JSON syntax is rejected and model in RAM remains unchanged",
		"1. Insert invalid JSON string. 2. _on_apply_json_pressed().",
		"Error reported in status label and model unchanged.",
		"Status: '%s', model unchanged: %s" % [viewer._json_status_label.text, model_after_bad_syntax == model_before_bad_syntax]
	)

	# 4.3 JSON hợp lệ nhưng sai schema: leaf có con
	var leaf_with_children: Dictionary = JSON.parse_string(model_before_bad_syntax)
	# Node 2 là BTTask (leaf) nhưng gán children_ids: [3]
	var bogus_leaf := {"id": 3, "type_name": "BTTask", "friendly_name": "Bogus", "children_ids": []}
	leaf_with_children["nodes"].append(bogus_leaf)
	leaf_with_children["nodes"][1]["children_ids"] = [3]
	viewer._json_text_edit.text = JSON.stringify(leaf_with_children, "\t")
	viewer._json_text_edit.text_changed.emit()
	viewer._on_apply_json_pressed()

	_check(
		viewer._json_status_label.text.begins_with("❌") and viewer.current_tree.get_node_by_id(3) == null,
		"Group 4.3: Schema violation (leaf with children) rejected without replacing model",
		"Set children_ids on leaf BTTask and apply JSON.",
		"Rejected with error, bogus node 3 not added.",
		"Status: '%s', node 3 exists: %s" % [viewer._json_status_label.text, viewer.current_tree.get_node_by_id(3) != null]
	)

	# 4.4 JSON hợp lệ nhưng sai schema: decorator có 2 con
	var dec_with_2_children: Dictionary = JSON.parse_string(model_before_bad_syntax)
	var dec_node := {"id": 4, "type_name": "BTInverter", "friendly_name": "Inverter", "children_ids": [2, 5]}
	var leaf_5 := {"id": 5, "type_name": "BTTask", "friendly_name": "Leaf5", "children_ids": []}
	dec_with_2_children["nodes"].append(dec_node)
	dec_with_2_children["nodes"].append(leaf_5)
	# Root trỏ vào decorator 4
	dec_with_2_children["nodes"][0]["children_ids"] = [4]
	viewer._json_text_edit.text = JSON.stringify(dec_with_2_children, "\t")
	viewer._json_text_edit.text_changed.emit()
	viewer._on_apply_json_pressed()

	_check(
		viewer._json_status_label.text.begins_with("❌") and viewer.current_tree.get_node_by_id(4) == null,
		"Group 4.4: Schema violation (decorator with 2 children) rejected without replacing model",
		"Set children_ids with 2 elements on BTInverter and apply JSON.",
		"Rejected with error, decorator node 4 not added.",
		"Status: '%s', node 4 exists: %s" % [viewer._json_status_label.text, viewer.current_tree.get_node_by_id(4) != null]
	)

	# 4.5 JSON hợp lệ nhưng sai schema: ID trùng
	var duplicate_ids: Dictionary = JSON.parse_string(model_before_bad_syntax)
	var dup_node := {"id": 2, "type_name": "BTTask", "friendly_name": "DuplicateNode2", "children_ids": []}
	duplicate_ids["nodes"].append(dup_node)
	viewer._json_text_edit.text = JSON.stringify(duplicate_ids, "\t")
	viewer._json_text_edit.text_changed.emit()
	viewer._on_apply_json_pressed()

	_check(
		viewer._json_status_label.text.begins_with("❌"),
		"Group 4.5: Schema violation (duplicate node IDs) rejected without replacing model",
		"Add second node with id == 2 and apply JSON.",
		"Rejected with error.",
		"Status: '%s'" % viewer._json_status_label.text
	)

	# 4.6 Revert JSON draft về model
	viewer._json_text_edit.text = "{\"unapplied_draft\": true}"
	viewer._json_text_edit.text_changed.emit()
	_check(
		viewer._json_draft_modified,
		"Group 4.6: Modifying draft marks _json_draft_modified",
		"Type draft in JSON edit.",
		"_json_draft_modified == true",
		"_json_draft_modified == %s" % viewer._json_draft_modified
	)
	viewer.revert_json_draft()
	_check(
		not viewer._json_draft_modified and viewer._json_text_edit.text.contains("JsonChild_Applied"),
		"Group 4.6: Revert JSON draft restores serialized model and resets modified flag",
		"viewer.revert_json_draft()",
		"_json_draft_modified is false and text matches model.",
		"_json_draft_modified: %s, text contains JsonChild_Applied: %s" % [viewer._json_draft_modified, viewer._json_text_edit.text.contains("JsonChild_Applied")]
	)

	viewer.free()

# ==============================================================================
# GROUP 5: Xoá
# ==============================================================================
func _test_group5_deletion() -> void:
	var viewer := _make_viewer()
	var tree := _tree_with_root("RootSeq")
	var comp := BTComposite.BTSelector.new()
	comp.id = 2
	comp.friendly_name = "ParentSel"
	var leaf1 := BTTask.new()
	leaf1.id = 3
	leaf1.friendly_name = "Leaf1"
	var leaf2 := BTTask.new()
	leaf2.id = 4
	leaf2.friendly_name = "Leaf2"

	tree.connect_parent_child(tree.root_task, comp)
	tree.connect_parent_child(comp, leaf1)
	tree.connect_parent_child(comp, leaf2)
	viewer.load_generic_tree(tree, "DeleteTree")

	# 5.1 Xoá node đang chọn
	viewer.select_node_by_id(4)
	viewer._delete_task(leaf2)
	_check(
		viewer.current_tree.get_node_by_id(4) == null and viewer.selected_node_id == -1,
		"Group 5.1: Deleting selected node removes it and resets selected_node_id to -1",
		"Select node 4, call _delete_task(leaf2).",
		"Node 4 is removed, selected_node_id == -1",
		"Node 4 exists: %s, selected_node_id: %d" % [viewer.current_tree.get_node_by_id(4) != null, viewer.selected_node_id]
	)

	# 5.2 Xoá root (tree rỗng) - phải bị từ chối
	var root_before: BTTask = viewer.current_tree.root_task
	var del_root_res := viewer._delete_task(root_before)
	_check(
		not del_root_res and viewer.current_tree.root_task == root_before and viewer._stats_label.text.contains("Cannot delete the root"),
		"Group 5.2: Deleting root node is rejected to prevent corrupt/rootless tree",
		"Call _delete_task(root_task).",
		"Returns false, root kept, status explains refusal.",
		"result: %s, root intact: %s, stats: '%s'" % [del_root_res, viewer.current_tree.root_task == root_before, viewer._stats_label.text]
	)

	# 5.3 Xoá node cha có con: khi con visible thì không hỏi dialog mà xoá trực tiếp (vì đã qua mutation có thể Undo phục hồi)
	var comp_node: BTTask = viewer.current_tree.get_node_by_id(2)
	_check(
		comp_node != null and comp_node.children.size() > 0,
		"Group 5.3: Pre-condition: Node 2 has children",
		"Inspect Node 2 children count.",
		"children.size() > 0",
		"children count: %d" % [comp_node.children.size() if comp_node else 0]
	)
	var child_ids_before: Array = []
	for ch in comp_node.children:
		child_ids_before.append(ch.id)
	var positions_before: Dictionary = viewer.current_tree.metadata.get("node_positions", {}).duplicate(true)

	viewer._delete_task(comp_node)
	var confirm_shown_for_parent := viewer._delete_confirm_dialog != null and viewer._delete_confirm_dialog.visible
	var deleted_from_tree := viewer.current_tree.get_node_by_id(2) == null
	for cid in child_ids_before:
		if viewer.current_tree.get_node_by_id(cid) != null:
			deleted_from_tree = false
	_check(
		not confirm_shown_for_parent and deleted_from_tree,
		"Group 5.3: Deleting parent node with visible children deletes directly without dialog",
		"1. Select parent node with visible children. 2. Call _delete_task(parent). 3. Check dialog and tree.",
		"No dialog shown (action is undoable), parent and children deleted from model.",
		"Dialog visible: %s, deleted: %s" % [confirm_shown_for_parent, deleted_from_tree],
		true
	)

	# 5.3b Undo phục hồi nguyên cây con + vị trí
	viewer.undo()
	var restored_parent: BTTask = viewer.current_tree.get_node_by_id(2)
	var subtree_restored := restored_parent != null and restored_parent.children.size() == child_ids_before.size()
	if subtree_restored:
		for cid in child_ids_before:
			if viewer.current_tree.get_node_by_id(cid) == null:
				subtree_restored = false
	var positions_after_undo: Dictionary = viewer.current_tree.metadata.get("node_positions", {})
	var positions_restored := _are_positions_equal(positions_before, positions_after_undo)
	_check(
		subtree_restored and positions_restored,
		"Group 5.3b: Undo restores deleted parent and full subtree with node positions",
		"1. Call viewer.undo() after deleting parent node. 2. Check parent, children, and positions metadata.",
		"Subtree and positions completely restored.",
		"subtree_restored: %s, positions_restored: %s" % [subtree_restored, positions_restored],
		true
	)

	# 5.4 Xoá node cha khi node con đang được select
	# Setup lại tree
	var tree_sel := _tree_with_root("Root")
	var p := BTComposite.BTSequence.new()
	p.id = 10
	var c := BTTask.new()
	c.id = 11
	tree_sel.connect_parent_child(tree_sel.root_task, p)
	tree_sel.connect_parent_child(p, c)
	viewer.load_generic_tree(tree_sel, "TargetSelTree")

	viewer.select_node_by_id(11) # select con
	# Xoá cha
	viewer._delete_task_with_descendants(p)
	_check(
		viewer.selected_node_id == -1 and viewer.current_tree.get_node_by_id(11) == null,
		"Group 5.4: Deleting parent safely resets selection when child was selected",
		"Select child node 11, delete parent node 10. Check selected_node_id.",
		"selected_node_id is reset to -1 without dangling pointer.",
		"selected_node_id == %d" % viewer.selected_node_id
	)

	# 5.5 Xoá rồi undo
	viewer.clear_undo_history()
	var tree_undo := _tree_with_root("Root")
	var sub_p := BTComposite.BTSequence.new()
	sub_p.id = 20
	sub_p.friendly_name = "SubParent"
	var sub_c1 := BTTask.new()
	sub_c1.id = 21
	sub_c1.friendly_name = "SubChild1"
	var sub_c2 := BTTask.new()
	sub_c2.id = 22
	sub_c2.friendly_name = "SubChild2"
	tree_undo.connect_parent_child(tree_undo.root_task, sub_p)
	tree_undo.connect_parent_child(sub_p, sub_c1)
	tree_undo.connect_parent_child(sub_p, sub_c2)
	viewer.load_generic_tree(tree_undo, "UndoDeleteSubtree")

	var nodes_before_del := viewer.current_tree.get_node_count()
	viewer._delete_task(sub_p)
	var nodes_after_del := viewer.current_tree.get_node_count()
	viewer.undo()
	var nodes_after_undo := viewer.current_tree.get_node_count()
	var restored_p: BTTask = viewer.current_tree.get_node_by_id(20)
	var restored_c1: BTTask = viewer.current_tree.get_node_by_id(21)
	var restored_c2: BTTask = viewer.current_tree.get_node_by_id(22)
	_check(
		nodes_after_undo == nodes_before_del and restored_p != null and restored_c1 != null and restored_c2 != null and restored_c1.parent == restored_p and restored_c2.parent == restored_p,
		"Group 5.5: Undo after deleting subtree restores parent, all children, and hierarchy connections",
		"1. Delete parent node with 2 children. 2. viewer.undo(). 3. Verify nodes and parent links.",
		"All 3 nodes restored with parent connections intact.",
		"before: %d, after del: %d, after undo: %d, links intact: %s" % [
			nodes_before_del, nodes_after_del, nodes_after_undo,
			restored_c1 != null and restored_c1.parent == restored_p
		]
	)

	viewer.free()

# ==============================================================================
# GROUP 6: Load/Save qua source
# ==============================================================================
func _test_group6_load_save_source() -> void:
	var group_dir := TEST_BASE_DIR.path_join("group6")
	DirAccess.make_dir_recursive_absolute(group_dir)
	var source := BTFileTreeSource.new(group_dir)

	# 6.1 Load tree từ file, sửa, save, load lại → khớp
	var tree := _tree_with_root("SourceRoot")
	tree.tree_name = "RoundTripTree"
	tree.blackboard.set_var("health", 100, "int")
	var child := BTTask.new()
	child.id = 2
	child.friendly_name = "ActionChild"
	child.parameters["power"] = 50
	tree.connect_parent_child(tree.root_task, child)
	source.save_tree("RoundTripTree", tree)

	var loaded1 := source.load_tree("RoundTripTree")
	_check(loaded1 != null, "Group 6.1: Initial tree loaded from source", "source.load_tree('RoundTripTree')", "Loaded != null", "Loaded: %s" % (loaded1 != null))
	if loaded1 != null:
		loaded1.root_task.friendly_name = "SourceRoot_Edited"
		loaded1.blackboard.set_var("health", 75, "int")
		loaded1.get_node_by_id(2).parameters["power"] = 99
		source.save_tree("RoundTripTree", loaded1)

		var fresh_source := BTFileTreeSource.new(group_dir)
		var loaded2 := fresh_source.load_tree("RoundTripTree")
		_check(
			loaded2 != null and loaded2.root_task.friendly_name == "SourceRoot_Edited" and loaded2.blackboard.get_var("health") == 75 and loaded2.get_node_by_id(2).parameters.get("power") == 99,
			"Group 6.1: Load tree from file, edit, save, and reload in fresh source matches exactly",
			"Load tree, edit friendly_name, blackboard, parameter. Save, reload via new source.",
			"All edits persisted and restored accurately.",
			"Loaded: %s, root name: %s, health: %s, power: %s" % [
				loaded2 != null,
				loaded2.root_task.friendly_name if loaded2 else "null",
				loaded2.blackboard.get_var("health") if loaded2 else "null",
				loaded2.get_node_by_id(2).parameters.get("power") if (loaded2 and loaded2.get_node_by_id(2)) else "null"
			]
		)

	# 6.2 Load file không tồn tại → last_error, không crash
	var null_tree := source.load_tree("non_existent_file_xyz_999")
	_check(
		null_tree == null and source.last_error.contains("file not found"),
		"Group 6.2: Loading nonexistent file sets last_error and returns null without crashing",
		"source.load_tree('non_existent_file_xyz_999')",
		"Returns null and last_error contains 'file not found'.",
		"null_tree: %s, last_error: '%s'" % [null_tree, source.last_error]
	)

	var viewer := _make_viewer()
	viewer.set_tree_source(source)
	var load_file_res := viewer.load_tree_file("res://non_existent_path_xyz.json")
	_check(
		not load_file_res,
		"Group 6.2: viewer.load_tree_file on nonexistent path returns false without crashing",
		"viewer.load_tree_file('res://non_existent_path_xyz.json')",
		"Returns false gracefully.",
		"Returns: %s" % load_file_res
	)
	viewer.free()

	# 6.3 Save vào thư mục chưa tồn tại → tự tạo
	var nested_path := group_dir.path_join("new_sub_dir/deep/nested_tree.json")
	var nested_tree := _tree_with_root("NestedRoot")
	nested_tree.tree_name = "nested_tree"
	var save_nested_ok := source.save_tree(nested_path, nested_tree)
	var nested_file_exists := FileAccess.file_exists(nested_path)
	_check(
		save_nested_ok and nested_file_exists,
		"Group 6.3: Saving to nonexistent nested directory automatically creates directory tree",
		"source.save_tree(nested_path, tree)",
		"Returns true and file exists on disk.",
		"save_nested_ok: %s, exists: %s, last_error: '%s'" % [save_nested_ok, nested_file_exists, source.last_error]
	)

	# 6.4 Load file hỏng cú pháp JSON → last_error, không crash
	var corrupt_file := group_dir.path_join("corrupted.json")
	var fa := FileAccess.open(corrupt_file, FileAccess.WRITE)
	fa.store_string("{ \"broken_json\": [ 1, 2,")
	fa.close()
	var corrupt_load := source.load_tree(corrupt_file)
	_check(
		corrupt_load == null and source.last_error.contains("failed to parse JSON"),
		"Group 6.4: Loading corrupt JSON file sets last_error and returns null",
		"source.load_tree('corrupted.json')",
		"Returns null, last_error reports JSON parse failure.",
		"corrupt_load: %s, last_error: '%s'" % [corrupt_load, source.last_error]
	)

# ==============================================================================
# GROUP 7: Tương tác với engine
# ==============================================================================
func _test_group7_engine_interaction() -> void:
	var commander_path := "res://demo/complex/rts_data/commander_800_tree.json"
	_check(
		FileAccess.file_exists(commander_path),
		"Group 7.1: Pre-condition: commander_800_tree.json exists in project",
		"Check FileAccess.file_exists('%s')" % commander_path,
		"File exists",
		"File exists: %s" % FileAccess.file_exists(commander_path)
	)

	var viewer := _make_viewer()
	var file_source := BTFileTreeSource.new("res://demo/complex/rts_data")
	viewer.set_tree_source(file_source)

	# 7.1 Viewer load cây lớn không treo (< vài giây)
	var t0 := Time.get_ticks_msec()
	var loaded := viewer.load_tree_file(commander_path)
	var elapsed_ms := Time.get_ticks_msec() - t0
	_check(
		loaded and elapsed_ms < 5000,
		"Group 7.1: Viewer loads commander_800_tree.json without freezing (< 5 seconds)",
		"viewer.load_tree_file('commander_800_tree.json') and measure elapsed milliseconds.",
		"Loaded successfully in < 5000 ms.",
		"Loaded: %s, elapsed: %d ms" % [loaded, elapsed_ms]
	)

	# 7.2 Node count hiển thị đúng
	var model_node_count := viewer.current_tree.get_node_count()
	var stats_node_count: int = int(viewer._stats.total)
	_check(
		model_node_count == 850 and stats_node_count == 850,
		"Group 7.2: Node count in viewer stats matches model node count (850 nodes)",
		"Check viewer.current_tree.get_node_count() vs viewer._stats.total",
		"Both equal 850",
		"model count: %d, stats count: %d" % [model_node_count, stats_node_count]
	)

	# 7.3 Refresh sau khi model đổi
	var new_task := BTTask.new()
	new_task.id = 9999
	new_task.friendly_name = "AddedCommanderTask"
	viewer.current_tree.add_node(new_task)
	viewer.current_tree.connect_parent_child(viewer.current_tree.root_task, new_task)
	viewer._stats = viewer.current_tree.get_stats()
	viewer._update_stats_label()
	viewer._render_current_tree()

	_check(
		viewer._graph_nodes_by_id.has(9999) and viewer._stats.total == 851,
		"Group 7.3: Viewer graph and stats refresh accurately when model expands",
		"Add task to large tree, re-render, verify graph node created and stats updated.",
		"Graph node 9999 exists and total nodes == 851",
		"graph has 9999: %s, total: %d" % [viewer._graph_nodes_by_id.has(9999), viewer._stats.total]
	)

	# 7.4 Chọn node rồi xem inspector không lỗi
	viewer.select_node_by_id(1)
	var root_title := viewer._inspector_title.text
	viewer.select_node_by_id(9999)
	var leaf_title := viewer._inspector_title.text
	_check(
		root_title.contains("1") and leaf_title.contains("9999"),
		"Group 7.4: Selecting nodes in large tree populates inspector without error",
		"Select root node (1) and added node (9999), verify inspector title.",
		"Inspector title updates with node ID and details without crashing.",
		"root_title: '%s', leaf_title: '%s'" % [root_title, leaf_title]
	)

	viewer.free()

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================
func _run() -> void:
	await process_frame
	print("Starting Editor Deep E2E QA Test Suite...")

	# Ensure base test dir is clean
	_clean_dir(TEST_BASE_DIR)
	DirAccess.make_dir_recursive_absolute(TEST_BASE_DIR)

	_test_group1_naming_and_save_as()
	_test_group2_autosave_and_ctrl_s()
	_test_group3_undo_redo()
	_test_group4_json_view()
	_test_group5_deletion()
	_test_group6_load_save_source()
	_test_group7_engine_interaction()

	# Cleanup test dir
	_clean_dir(TEST_BASE_DIR)

	print("\n=======================================================")
	print("Editor deep E2E: %d checks, %d failures" % [checks, failures])
	print("=======================================================")

	if failures > 0:
		print("\nSummary of detected bugs (%d total):" % failures)
		for i in bug_reports.size():
			var b: Dictionary = bug_reports[i]
			print("[%d] [%s] %s" % [i + 1, b["severity"], b["name"]])
			print("    Repro:    %s" % b["repro"])
			print("    Expected: %s" % b["expected"])
			print("    Actual:   %s" % b["actual"])

	quit(1 if failures > 0 else 0)
