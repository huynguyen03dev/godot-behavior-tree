extends SceneTree
## Benchmark Suite for Godot Behavior Tree Rust Native Engine.
##
## Measures tick performance, JSON parsing/tree building (from_dict),
## tree serialization (to_dict), and runtime overhead breakdown across scales:
##   1. Single Leaf Tree (1 node under Repeater)
##   2. Small Sequence Tree (Sequence + 3 leaves under Repeater, 4 nodes)
##   3. RTS Commander 800 Tree (~850 nodes from JSON)
##   4. RTS Commander 2000 Tree (2000 nodes from JSON)
##   5. Overhead Controls: Native call floor, stopped early return,
##      non-completing tick vs signal emission, and from_dict throughput.
##
## Usage:
##   godot --headless --path . -s res://tests/bench_native.gd

const COMMANDER_800_PATH := "res://demo/complex/rts_data/commander_800_tree.json"
const COMMANDER_2000_PATH := "res://demo/complex/rts_data/commander_2000_tree.json"
const WARMUP_TICKS: int = 500
const MEASURE_TICKS: int = 5000

func _initialize() -> void:
	print("================================================================================")
	print(" Godot Behavior Tree Native Engine Benchmark")
	print(" Engine: %s" % Engine.get_version_info().string)
	print(" OS / Arch: %s / %s" % [OS.get_name(), Engine.get_architecture_name()])
	print(" Warmup: %d ticks | Benchmark: %d ticks per configuration" % [WARMUP_TICKS, MEASURE_TICKS])
	print("================================================================================\n")

	await _run_all_benchmarks()

	print("\n================================================================================")
	print("bench: OK")
	print("================================================================================")
	await process_frame
	quit(0)

func _run_all_benchmarks() -> void:
	var registry := _create_benchmark_registry()

	# Section 1: JSON Parse, from_dict Build, and to_dict Serialization Benchmarks
	print("--- 1. Tree Build & Serialization Benchmarks (Single Run) ---")
	var build_results: Array[Dictionary] = []
	if FileAccess.file_exists(COMMANDER_800_PATH):
		build_results.append(_bench_tree_io("Commander 800 (850 nodes)", COMMANDER_800_PATH, registry))
	else:
		print("WARNING: %s not found" % COMMANDER_800_PATH)

	if FileAccess.file_exists(COMMANDER_2000_PATH):
		build_results.append(_bench_tree_io("Commander 2000 (2000 nodes)", COMMANDER_2000_PATH, registry))
	else:
		print("WARNING: %s not found" % COMMANDER_2000_PATH)

	_print_build_table(build_results)

	# Section 2: Tick Execution Performance Benchmarks
	print("\n--- 2. Tick Execution Benchmarks (>= %d ticks) ---" % MEASURE_TICKS)
	var tick_results: Array[Dictionary] = []

	# Config 1: 1 Leaf under Repeater
	var tree_1leaf := _build_1leaf_tree()
	tick_results.append(_bench_tree_ticks("1-Leaf (Code, 1 node)", tree_1leaf))
	tree_1leaf = null

	# Config 2: Sequence + 3 leaves under Repeater
	var tree_small_seq := _build_small_seq_tree()
	tick_results.append(_bench_tree_ticks("Sequence+3Leaves (Code, 4 nodes)", tree_small_seq))
	tree_small_seq = null

	# Config 3: Commander 800 Tree (850 nodes)
	if FileAccess.file_exists(COMMANDER_800_PATH):
		var tree_800 := _load_tree_from_file(COMMANDER_800_PATH, registry)
		if tree_800 != null:
			_ensure_repeater_root(tree_800)
			tick_results.append(_bench_tree_ticks("Commander 800 (JSON, 850 nodes)", tree_800))
			tree_800 = null

	# Config 4: Commander 2000 Tree (2000 nodes)
	if FileAccess.file_exists(COMMANDER_2000_PATH):
		var tree_2000 := _load_tree_from_file(COMMANDER_2000_PATH, registry)
		if tree_2000 != null:
			_ensure_repeater_root(tree_2000)
			tick_results.append(_bench_tree_ticks("Commander 2000 (JSON, 2000 nodes)", tree_2000))
			tree_2000 = null

	_print_tick_table(tick_results)

	# Section 3: Overhead Breakdown & Control Benchmarks
	print("\n--- 3. Overhead Breakdown & Control Benchmarks ---")
	var control_results := _run_control_benchmarks(registry)

	_save_bench_artifacts(build_results, tick_results, control_results)

	registry = null

# ---------------------------------------------------------------- Registry Setup

func _create_benchmark_registry() -> BTTaskRegistry:
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

# ---------------------------------------------------------------- Code Trees

func _build_1leaf_tree() -> BTTree:
	var tree := BTTree.new()
	tree.tree_name = "1LeafTree"

	var rep := BTDecorator.BTRepeater.new()
	rep.id = 1
	rep.repeat_forever = true
	tree.set_root(rep)

	var leaf := BTTask.new()
	leaf.id = 2
	leaf.friendly_name = "FastLeaf"
	tree.connect_parent_child(rep, leaf)
	return tree

func _build_small_seq_tree() -> BTTree:
	var tree := BTTree.new()
	tree.tree_name = "SmallSeqTree"

	var rep := BTDecorator.BTRepeater.new()
	rep.id = 1
	rep.repeat_forever = true
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

# ---------------------------------------------------------------- Tree I/O & Bench

func _load_tree_from_file(path: String, registry: BTTaskRegistry) -> BTTree:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Failed to open %s" % path)
		return null
	var text := f.get_as_text()
	f.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("Failed to parse JSON from %s" % path)
		return null

	var data: Dictionary = json.data
	return BTTree.from_dict(data, registry)

func _ensure_repeater_root(tree: BTTree) -> void:
	var root_task = tree.get_root_task()
	if root_task != null:
		if root_task is BTDecorator.BTRepeater:
			root_task.repeat_forever = true
		elif root_task is BTTaskNative and root_task.type_name == "Repeater":
			root_task.set_repeat_forever(true)

func _bench_tree_io(name: String, path: String, registry: BTTaskRegistry) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()

	# 1. JSON string -> Dictionary
	var t0 := Time.get_ticks_usec()
	var json := JSON.new()
	var err := json.parse(text)
	var json_parse_us := Time.get_ticks_usec() - t0
	if err != OK:
		push_error("JSON parse failed for %s" % path)
		return {}

	var data: Dictionary = json.data

	# 2. Dictionary -> BTTree (from_dict)
	t0 = Time.get_ticks_usec()
	var tree: BTTree = BTTree.from_dict(data, registry)
	var from_dict_us := Time.get_ticks_usec() - t0

	var node_count := tree.get_node_count() if tree != null else 0

	# 3. BTTree -> Dictionary (to_dict)
	t0 = Time.get_ticks_usec()
	var serialized: Dictionary = tree.to_dict() if tree != null else {}
	var to_dict_us := Time.get_ticks_usec() - t0

	return {
		"name": name,
		"nodes": node_count,
		"json_bytes": text.length(),
		"json_parse_ms": json_parse_us / 1000.0,
		"from_dict_ms": from_dict_us / 1000.0,
		"to_dict_ms": to_dict_us / 1000.0,
		"total_load_ms": (json_parse_us + from_dict_us) / 1000.0,
	}

# ---------------------------------------------------------------- Tick Benchmarking

func _bench_tree_ticks(name: String, tree: BTTree) -> Dictionary:
	var runner := BTRunner.new(tree)
	runner.start()

	# Warm-up phase
	for i in range(WARMUP_TICKS):
		if not runner.is_running:
			runner.start()
		runner.tick(0.016)

	# Measurement phase
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

	# Compute statistics
	var sorted := Array(samples_us)
	sorted.sort()

	var p50_idx := int(floor(MEASURE_TICKS * 0.50))
	var p99_idx := mini(MEASURE_TICKS - 1, int(floor(MEASURE_TICKS * 0.99)))

	var p50_us: float = sorted[p50_idx]
	var p99_us: float = sorted[p99_idx]
	var min_us: float = sorted[0]
	var max_us: float = sorted[MEASURE_TICKS - 1]

	var sum_us: float = 0.0
	for val in samples_us:
		sum_us += val
	var avg_us: float = sum_us / float(MEASURE_TICKS)

	var total_seconds: float = float(total_elapsed_usec) / 1_000_000.0
	var ticks_per_sec: float = float(MEASURE_TICKS) / total_seconds if total_seconds > 0.0 else 0.0

	return {
		"name": name,
		"nodes": tree.get_node_count(),
		"ticks": MEASURE_TICKS,
		"avg_us": avg_us,
		"p50_us": p50_us,
		"p99_us": p99_us,
		"min_us": min_us,
		"max_us": max_us,
		"ticks_per_sec": ticks_per_sec,
	}

# ---------------------------------------------------------------- Control Benchmarks

func _run_control_benchmarks(registry: BTTaskRegistry) -> Dictionary:
	var results: Dictionary = {}

	# Control 1: GDScript -> Native call overhead floor
	var runner := BTRunner.new()
	runner.stop()

	# Warmup
	for i in range(WARMUP_TICKS):
		var _x = runner.is_running
		var _y = runner.get_ticks()

	var samples_prop := PackedFloat64Array()
	samples_prop.resize(MEASURE_TICKS)
	var t0 := Time.get_ticks_usec()
	for i in range(MEASURE_TICKS):
		var ts := Time.get_ticks_usec()
		var _x = runner.is_running
		samples_prop[i] = float(Time.get_ticks_usec() - ts)
	var elapsed_prop := Time.get_ticks_usec() - t0

	var samples_method := PackedFloat64Array()
	samples_method.resize(MEASURE_TICKS)
	t0 = Time.get_ticks_usec()
	for i in range(MEASURE_TICKS):
		var ts := Time.get_ticks_usec()
		var _y = runner.get_ticks()
		samples_method[i] = float(Time.get_ticks_usec() - ts)
	var elapsed_method := Time.get_ticks_usec() - t0

	var stat_prop := _calc_stats(samples_prop, elapsed_prop)
	var stat_method := _calc_stats(samples_method, elapsed_method)

	results["c1_call_floor"] = {
		"is_running_prop_p50_us": stat_prop.p50_us,
		"is_running_prop_avg_us": stat_prop.avg_us,
		"get_ticks_method_p50_us": stat_method.p50_us,
		"get_ticks_method_avg_us": stat_method.avg_us,
	}

	# Control 2: Stopped tick early-return
	for i in range(WARMUP_TICKS):
		runner.tick(0.0)

	var samples_stopped := PackedFloat64Array()
	samples_stopped.resize(MEASURE_TICKS)
	t0 = Time.get_ticks_usec()
	for i in range(MEASURE_TICKS):
		var ts := Time.get_ticks_usec()
		runner.tick(0.0)
		samples_stopped[i] = float(Time.get_ticks_usec() - ts)
	var elapsed_stopped := Time.get_ticks_usec() - t0
	var stat_stopped := _calc_stats(samples_stopped, elapsed_stopped)

	results["c2_stopped_tick"] = {
		"p50_us": stat_stopped.p50_us,
		"avg_us": stat_stopped.avg_us,
		"p99_us": stat_stopped.p99_us,
	}

	runner.free()
	runner = null

	# Control 3: 1-leaf tick non-completing vs completing
	# 3A: Leaf returning RUNNING (0 task_finished / tree_finished signals emitted)
	var running_script := GDScript.new()
	running_script.source_code = """
extends BTTask
func on_update() -> int:
	return BTStatus.RUNNING
"""
	running_script.reload()
	var leaf_running = running_script.new()
	leaf_running.id = 1
	var tree_running := BTTree.new()
	tree_running.set_root(leaf_running)
	var runner_running := BTRunner.new(tree_running)
	runner_running.start()

	for i in range(WARMUP_TICKS):
		runner_running.tick(0.016)

	var samples_running := PackedFloat64Array()
	samples_running.resize(MEASURE_TICKS)
	t0 = Time.get_ticks_usec()
	for i in range(MEASURE_TICKS):
		var ts := Time.get_ticks_usec()
		runner_running.tick(0.016)
		samples_running[i] = float(Time.get_ticks_usec() - ts)
	var elapsed_running := Time.get_ticks_usec() - t0
	var stat_running := _calc_stats(samples_running, elapsed_running)

	results["c3_non_completing_tick"] = {
		"description": "1-leaf persistent action (returns RUNNING, 0 signals)",
		"p50_us": stat_running.p50_us,
		"avg_us": stat_running.avg_us,
		"p99_us": stat_running.p99_us,
		"ticks_per_sec": stat_running.ticks_per_sec,
	}

	runner_running.stop()
	runner_running.free()
	tree_running = null

	# 3B: 1-leaf under Repeater with max_task_executions_per_tick = 1
	var tree_rep := _build_1leaf_tree()
	var runner_budget := BTRunner.new(tree_rep)
	runner_budget.max_task_executions_per_tick = 1
	runner_budget.start()

	for i in range(WARMUP_TICKS):
		if not runner_budget.is_running:
			runner_budget.start()
		runner_budget.tick(0.016)

	var samples_budget := PackedFloat64Array()
	samples_budget.resize(MEASURE_TICKS)
	t0 = Time.get_ticks_usec()
	for i in range(MEASURE_TICKS):
		if not runner_budget.is_running:
			runner_budget.start()
		var ts := Time.get_ticks_usec()
		runner_budget.tick(0.016)
		samples_budget[i] = float(Time.get_ticks_usec() - ts)
	var elapsed_budget := Time.get_ticks_usec() - t0
	var stat_budget := _calc_stats(samples_budget, elapsed_budget)

	results["c3_budget_1_tick"] = {
		"description": "1-leaf under Repeater with budget=1 (leaf completes)",
		"p50_us": stat_budget.p50_us,
		"avg_us": stat_budget.avg_us,
		"p99_us": stat_budget.p99_us,
		"ticks_per_sec": stat_budget.ticks_per_sec,
	}

	runner_budget.stop()
	runner_budget.free()
	tree_rep = null

	# Control 4: 850-node from_dict throughput (5 runs for stable median)
	if FileAccess.file_exists(COMMANDER_800_PATH):
		var f := FileAccess.open(COMMANDER_800_PATH, FileAccess.READ)
		var text := f.get_as_text()
		f.close()
		var json := JSON.new()
		json.parse(text)
		var data: Dictionary = json.data

		var runs_ms: Array[float] = []
		for r in range(5):
			t0 = Time.get_ticks_usec()
			var tree_800 = BTTree.from_dict(data, registry)
			var elapsed_us = Time.get_ticks_usec() - t0
			runs_ms.append(float(elapsed_us) / 1000.0)
			tree_800 = null

		runs_ms.sort()
		var median_from_dict_ms: float = runs_ms[2]
		var nodes: int = 850
		var ms_per_node := median_from_dict_ms / float(nodes)
		var us_per_node := ms_per_node * 1000.0
		var nodes_per_sec := float(nodes) / (median_from_dict_ms / 1000.0)

		results["c4_from_dict_throughput"] = {
			"tree": "Commander 800",
			"nodes": nodes,
			"median_ms": median_from_dict_ms,
			"ms_per_node": ms_per_node,
			"us_per_node": us_per_node,
			"nodes_per_sec": nodes_per_sec,
			"runs_ms": runs_ms,
		}

	_print_control_table(results)
	return results

func _calc_stats(samples: PackedFloat64Array, total_elapsed_usec: int) -> Dictionary:
	var sorted := Array(samples)
	sorted.sort()
	var n := samples.size()
	var p50_idx := int(floor(n * 0.50))
	var p99_idx := mini(n - 1, int(floor(n * 0.99)))

	var sum_us: float = 0.0
	for val in samples:
		sum_us += val
	var avg_us := sum_us / float(n) if n > 0 else 0.0
	var total_sec := float(total_elapsed_usec) / 1_000_000.0
	var tps := float(n) / total_sec if total_sec > 0.0 else 0.0

	return {
		"p50_us": sorted[p50_idx],
		"p99_us": sorted[p99_idx],
		"avg_us": avg_us,
		"ticks_per_sec": tps,
	}

# ---------------------------------------------------------------- Output Formatting

func _print_build_table(rows: Array[Dictionary]) -> void:
	print("+----------------------------------+-------+------------+---------------+--------------+------------+---------------+")
	print("| Configuration                    | Nodes | JSON Size  | JSON Parse ms | from_dict ms | to_dict ms | Total Load ms |")
	print("+----------------------------------+-------+------------+---------------+--------------+------------+---------------+")
	for r in rows:
		if r.is_empty():
			continue
		print("| %-32s | %5d | %8d B | %11.2f ms | %10.2f ms | %8.2f ms | %11.2f ms |" % [
			r.name, r.nodes, r.json_bytes, r.json_parse_ms, r.from_dict_ms, r.to_dict_ms, r.total_load_ms
		])
	print("+----------------------------------+-------+------------+---------------+--------------+------------+---------------+");

func _print_tick_table(rows: Array[Dictionary]) -> void:
	print("+----------------------------------+-------+-------+------------+------------+------------+------------+----------------+")
	print("| Configuration                    | Nodes | Ticks |  Avg µs    |   p50 µs   |   p99 µs   |   Max µs   |    Ticks/sec   |")
	print("+----------------------------------+-------+-------+------------+------------+------------+------------+----------------+")
	for r in rows:
		if r.is_empty():
			continue
		print("| %-32s | %5d | %5d | %8.2f µs | %8.2f µs | %8.2f µs | %8.2f µs | %12.1f/s |" % [
			r.name, r.nodes, r.ticks, r.avg_us, r.p50_us, r.p99_us, r.max_us, r.ticks_per_sec
		])
	print("+----------------------------------+-------+-------+------------+------------+------------+------------+----------------+")

func _print_control_table(controls: Dictionary) -> void:
	print("+---------------------------------------------------------------+------------+------------+----------------+")
	print("| Control Measurement                                           |   p50 µs   |   Avg µs   |  Throughput    |")
	print("+---------------------------------------------------------------+------------+------------+----------------+")
	if controls.has("c1_call_floor"):
		var c1 = controls["c1_call_floor"]
		print("| 1. GDScript->Native method floor (runner.get_ticks)           | %8.2f µs | %8.2f µs | %12.1f/s |" % [
			c1.get_ticks_method_p50_us, c1.get_ticks_method_avg_us, 1_000_000.0 / maxf(0.001, c1.get_ticks_method_avg_us)
		])
		print("|    GDScript->Native property floor (runner.is_running)        | %8.2f µs | %8.2f µs | %12.1f/s |" % [
			c1.is_running_prop_p50_us, c1.is_running_prop_avg_us, 1_000_000.0 / maxf(0.001, c1.is_running_prop_avg_us)
		])
	if controls.has("c2_stopped_tick"):
		var c2 = controls["c2_stopped_tick"]
		print("| 2. Stopped tick early return (runner.stop -> tick)            | %8.2f µs | %8.2f µs | %12.1f/s |" % [
			c2.p50_us, c2.avg_us, 1_000_000.0 / maxf(0.001, c2.avg_us)
		])
	if controls.has("c3_non_completing_tick"):
		var c3a = controls["c3_non_completing_tick"]
		print("| 3A. Non-completing tick (leaf returns RUNNING, 0 signals)     | %8.2f µs | %8.2f µs | %12.1f/s |" % [
			c3a.p50_us, c3a.avg_us, c3a.ticks_per_sec
		])
	if controls.has("c3_budget_1_tick"):
		var c3b = controls["c3_budget_1_tick"]
		print("| 3B. Completing tick with budget=1 (emits task signals)        | %8.2f µs | %8.2f µs | %12.1f/s |" % [
			c3b.p50_us, c3b.avg_us, c3b.ticks_per_sec
		])
	print("+---------------------------------------------------------------+------------+------------+----------------+")

	if controls.has("c4_from_dict_throughput"):
		var c4 = controls["c4_from_dict_throughput"]
		print("\n--- 4. from_dict Throughput Breakdown (%s, %d nodes) ---" % [c4.tree, c4.nodes])
		print("  Median from_dict: %.2f ms (runs: %s ms)" % [c4.median_ms, str(c4.runs_ms)])
		print("  Time per node:    %.4f ms/node (%.1f µs/node)" % [c4.ms_per_node, c4.us_per_node])
		print("  Throughput:       %.1f nodes/sec" % c4.nodes_per_sec)

func _save_bench_artifacts(build_results: Array[Dictionary], tick_results: Array[Dictionary], control_results: Dictionary = {}) -> void:
	var dir_path := "res://bench"
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var artifact := {
		"engine": Engine.get_version_info().string,
		"os": OS.get_name(),
		"arch": Engine.get_architecture_name(),
		"warmup_ticks": WARMUP_TICKS,
		"measure_ticks": MEASURE_TICKS,
		"build_benchmarks": build_results,
		"tick_benchmarks": tick_results,
		"control_benchmarks": control_results,
	}

	var json_str := JSON.stringify(artifact, "\t")
	var f := FileAccess.open("res://bench/results.json", FileAccess.WRITE)
	if f != null:
		f.store_string(json_str)
		f.close()
		print("Benchmark artifact saved to res://bench/results.json")
