extends SceneTree

func _init() -> void:
	print("==================================================")
	print(" Devour Clone - Preflight Environment Check")
	print("==================================================")

	# 1. Check Godot Engine Version (>= 4.6 required)
	var v := Engine.get_version_info()
	var major: int = v.get("major", 0)
	var minor: int = v.get("minor", 0)
	var version_str: String = v.get("string", "%d.%d" % [major, minor])
	var version_ok := (major > 4) or (major == 4 and minor >= 6)
	if version_ok:
		print("[OK] Godot Version: %s (>= 4.6 required)" % version_str)
	else:
		printerr("[FAIL] Godot Version %s is unsupported. Version >= 4.6 required." % version_str)

	# 2. Check GDExtension Native Classes
	var has_task := ClassDB.class_exists("BTTaskNative")
	var has_runner := ClassDB.class_exists("BTRunnerNative")
	var ext_ok := has_task and has_runner
	if ext_ok:
		print("[OK] GDExtension Classes: BTTaskNative, BTRunnerNative loaded")
	else:
		printerr("[FAIL] GDExtension not loaded. Missing classes: BTTaskNative=%s, BTRunnerNative=%s" % [has_task, has_runner])

	# 3. Check Required Game Files
	var file_bt := "res://game/bt/ghost_main.json"
	var file_scene := "res://game/scenes/main.tscn"
	var bt_ok := FileAccess.file_exists(file_bt)
	var scene_ok := FileAccess.file_exists(file_scene)
	var files_ok := bt_ok and scene_ok
	if files_ok:
		print("[OK] Required Game Files: %s, %s exist" % [file_bt, file_scene])
	else:
		printerr("[FAIL] Missing game files: %s (exists=%s), %s (exists=%s)" % [file_bt, bt_ok, file_scene, scene_ok])

	print("==================================================")

	# Exit codes:
	# quit(0) if OK, quit(2) if missing extension, quit(3) if Godot too old, quit(4) if missing files
	if not ext_ok:
		quit(2)
	elif not version_ok:
		quit(3)
	elif not files_ok:
		quit(4)
	else:
		quit(0)
