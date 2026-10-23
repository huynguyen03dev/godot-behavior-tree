extends SceneTree
## Portable A/B Benchmark Suite for Godot Behavior Tree.
##
## Compares GDScript baseline (pure GDScript) vs Rust GDExtension native runtime.
## Strictly adheres to the portable public API supported by both implementations:
##   BTTree, BTTree.from_dict, BTTree.validate_dict, BTTask,
##   BTComposite.BTSequence, BTDecorator.BTRepeater, BTRunner,
##   BTTaskRegistry, BTBlackboard, BTStatus.
## No *Native classes, no bt_* internal methods, no _setup_kind calls.

const COMMANDER_800_PATH := "res://demo/complex/rts_data/commander_800_tree.json"
const COMMANDER_2000_PATH := "res://demo/complex/rts_data/commander_2000_tree.json"
const WARMUP_TICKS: int = 500
const MEASURE_TICKS: int = 5000
const IO_ITERATIONS: int = 5

func _initialize() -> void:
	print("================================================================================")
	print(" Godot Behavior Tree A/B Benchmark")
	print(" Engine: %s" % Engine.get_version_info().string)
	print(" OS / Arch: %s / %s" % [OS.get_name(), Engine.get_architecture_name()])
	print(" Warmup: %d ticks | Benchmark: %d ticks" % [WARMUP_TICKS, MEASURE_TICKS])
	print("================================================================================\n")

	_run_suite()

	print("\n================================================================================")
	print("ab: OK")
	print("================================================================================")
	quit(0)

func _run_suite() -> void:
	var registry := _create_registry()

	# ---------------------------------------------------------------- (e) from_dict & to_dict IO
	print("--- Tree Serialization (from_dict & to_dict, %d iterations, median) ---" % IO_ITERATIONS)
	if FileAccess.file_exists(COMMANDER_800_PATH):
		_bench_tree_io("commander800", COMMANDER_800_PATH, registry)
	else:
		push_warning("File not found: %s" % COMMANDER_800_PATH)

	if FileAccess.file_exists(COMMANDER_2000_PATH):
		_bench_tree_io("commander2000", COMMANDER_2000_PATH, registry)
	else:
		push_warning("File not found: %s" % COMMANDER_2000_PATH)

	# ---------------------------------------------------------------- (a) - (d) Tick Execution
	print("\n--- Tree Tick Benchmarks (warmup=%d, measure=%d) ---" % [WARMUP_TICKS, MEASURE_TICKS])

	# (a) 1 leaf under Repeater (repeat_forever)
	var tree_leaf1 := _build_1leaf_tree()
	_bench_tree_ticks("leaf1", "1-Leaf (Code, 1 node under Repeater)", tree_leaf1)
	tree_leaf1 = null

	# (b) Sequence + 3 leaves under Repeater
	var tree_seq3 := _build_seq3_tree()
	_bench_tree_ticks("seq3", "Sequence + 3 Leaves (Code, 4 nodes under Repeater)", tree_seq3)
	tree_seq3 = null

	# (c) Commander 800 (~850 nodes)
	if FileAccess.file_exists(COMMANDER_800_PATH):
		var tree_800 := _load_tree_from_file(COMMANDER_800_PATH, registry)
		if tree_800 != null:
			_ensure_repeater_root(tree_800)
			_bench_tree_ticks("commander800", "Commander 800 (JSON, ~850 nodes)", tree_800)
			tree_800 = null

	# (d) Commander 2000 (2000 nodes)
	if FileAccess.file_exists(COMMANDER_2000_PATH):
		var tree_2000 := _load_tree_from_file(COMMANDER_2000_PATH, registry)
		if tree_2000 != null:
			_ensure_repeater_root(tree_2000)
			_bench_tree_ticks("commander2000", "Commander 2000 (JSON, 2000 nodes)", tree_2000)
			tree_2000 = null

# ---------------------------------------------------------------- Registry Setup

func _create_registry() -> BTTaskRegistry:
	var reg := BTTaskRegistry.new()
	var custom_action_types := [
		"ActionExecuteStrategicOrder",
		"ActionProduceUnit",
		"ActionTechUpgrade",
		"CondResourceCheck",
		"CondStrategicStance",
	]
	for t in custom_action_types:
		var cat := "Condition" if t.begins_with("Cond") else "Action"
		reg.register_task(t, func(): return BTTask.new(), cat)
	return reg

# ---------------------------------------------------------------- Tree Builders

func _build_1leaf_tree() -> BTTree:
	var tree := BTTree.new()
	tree.tree_name = "1LeafTree"

	var rep := BTDecorator.BTRepeater.new()
	rep.id = 1
	rep.repeat_forever = true
	rep.set_param("repeat_forever", true, false)
	tree.set_root(rep)

	var leaf := BTTask.new()
	leaf.id = 2
	leaf.friendly_name = "FastLeaf"
	tree.connect_parent_child(rep, leaf)
	return tree

func _build_seq3_tree() -> BTTree:
	var tree := BTTree.new()
	tree.tree_name = "Seq3Tree"

	var rep := BTDecorator.BTRepeater.new()
	rep.id = 1
	rep.repeat_forever = true
	rep.set_param("repeat_forever", true, false)
	tree.set_root(rep)

	var seq := BTComposite.BTSequence.new()
	seq.id = 2
	seq.friendly_name = "MainSeq"
	tree.connect_parent_child(rep, seq)

	for i in range(3):
		var leaf := BTTask.new()
		leaf.id = 3 + i
		leaf.friendly_name = "Leaf_%d" % i
		tree.connect_parent_child(seq, leaf)

	return tree

func _load_tree_from_file(path: String, registry: BTTaskRegistry) -> BTTree:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open %s" % path)
		return null
	var text := f.get_as_text()
	f.close()

	var data = JSON.parse_string(text)
	if not (data is Dictionary):
		push_error("Failed to parse JSON dictionary from %s" % path)
		return null

	return BTTree.from_dict(data, registry)

func _ensure_repeater_root(tree: BTTree) -> void:
	var root_task = tree.get_root_task() if tree.has_method("get_root_task") else tree.root_task
	if root_task != null:
		if "repeat_forever" in root_task:
			root_task.repeat_forever = true
		if root_task.has_method("set_param"):
			root_task.set_param("repeat_forever", true, false)

# ---------------------------------------------------------------- Benchmarking

func _bench_tree_io(cfg: String, path: String, registry: BTTaskRegistry) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()

	var data: Dictionary = JSON.parse_string(text)

	var from_dict_samples: Array[float] = []
	var to_dict_samples: Array[float] = []

	for i in range(IO_ITERATIONS):
		var t0 := Time.get_ticks_usec()
		var tree := BTTree.from_dict(data, registry)
		var dt_from := (Time.get_ticks_usec() - t0) / 1000.0
		from_dict_samples.append(dt_from)

		t0 = Time.get_ticks_usec()
		var _dict: Dictionary = tree.to_dict() if tree != null else {}
		var dt_to := (Time.get_ticks_usec() - t0) / 1000.0
		to_dict_samples.append(dt_to)

	from_dict_samples.sort()
	to_dict_samples.sort()
	var mid := int(IO_ITERATIONS / 2)
	var med_from: float = from_dict_samples[mid]
	var med_to: float = to_dict_samples[mid]

	print("[%s] from_dict: %.2f ms | to_dict: %.2f ms" % [cfg, med_from, med_to])
	print("ABRESULT cfg=%s metric=from_dict_ms value=%.2f" % [cfg, med_from])
	print("ABRESULT cfg=%s metric=to_dict_ms value=%.2f" % [cfg, med_to])

func _bench_tree_ticks(cfg: String, desc: String, tree: BTTree) -> void:
	var runner := BTRunner.new(tree)
	runner.start()

	# Warmup
	for i in range(WARMUP_TICKS):
		if not runner.is_running:
			runner.start()
		runner.tick(0.016)

	# Measurement
	var samples_us := PackedFloat64Array()
	samples_us.resize(MEASURE_TICKS)

	var t_start := Time.get_ticks_usec()
	for i in range(MEASURE_TICKS):
		if not runner.is_running:
			runner.start()
		var t0 := Time.get_ticks_usec()
		runner.tick(0.016)
		samples_us[i] = float(Time.get_ticks_usec() - t0)
	var total_elapsed_usec := Time.get_ticks_usec() - t_start

	runner.stop()
	runner.free()

	var sorted := Array(samples_us)
	sorted.sort()

	var p50_idx := int(floor(MEASURE_TICKS * 0.50))
	var p90_idx := int(floor(MEASURE_TICKS * 0.90))
	var p99_idx := mini(MEASURE_TICKS - 1, int(floor(MEASURE_TICKS * 0.99)))

	var p50_us: float = sorted[p50_idx]
	var p90_us: float = sorted[p90_idx]
	var p99_us: float = sorted[p99_idx]

	var total_seconds: float = float(total_elapsed_usec) / 1_000_000.0
	var ticks_per_sec: float = float(MEASURE_TICKS) / total_seconds if total_seconds > 0.0 else 0.0

	print("[%s: %s] p50: %.2f us | p90: %.2f us | p99: %.2f us | ticks/s: %.1f" % [
		cfg, desc, p50_us, p90_us, p99_us, ticks_per_sec
	])
	print("ABRESULT cfg=%s metric=p50_us value=%.2f" % [cfg, p50_us])
	print("ABRESULT cfg=%s metric=p90_us value=%.2f" % [cfg, p90_us])
	print("ABRESULT cfg=%s metric=p99_us value=%.2f" % [cfg, p99_us])
	print("ABRESULT cfg=%s metric=ticks_s value=%.1f" % [cfg, ticks_per_sec])
