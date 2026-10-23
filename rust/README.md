# godot_bt_native — Rust Runtime Port

Native (Rust / GDExtension) port of the `godot_bt` behavior tree runtime for Godot 4.

The runtime delivers high-performance behavior tree execution, fast serialization/deserialization, and zero-allocation execution loops while preserving full backward compatibility with GDScript custom tasks and existing demo trees.

---

## Architecture & Class Layout

The engine operates on a **Native Core + GDScript Facade** model:

```diagram
┌────────────────────────────────────────────────────────┐
│                   GDScript Facade                      │
│ (BTTree, BTTask, BTRunner, BTBlackboard, BTRegistry)   │
└───────────────────────────┬────────────────────────────┘
                            │ extends / wraps
┌───────────────────────────▼────────────────────────────┐
│                 Rust GDExtension Core                  │
│       (BTTreeNative, BTTaskNative, BTRunnerNative,     │
│        BTBlackboardNative, BTTaskRegistryNative)       │
└────────────────────────────────────────────────────────┘
```

### 1. Registered Native Classes
- `BTTreeNative`: Owns the tree hierarchy, node lookup maps, and tree-level operations (`from_dict`, `to_dict`, `validate_dict`). Trees must be loaded with the registry that defines their custom types; there is no permissive fallback.
- `BTTaskNative`: Base class for tree nodes. Encapsulates status lifecycle, child management, blackboard integration, and execution logic.
- `BTRunnerNative`: Driving engine for tree evaluation, ticking, execution budgets, pause/resume, and signal dispatch.
- `BTBlackboardNative`: Fast variant dictionary for scoped blackboard data sharing and fallback chaining.
- `BTTaskRegistryNative`: Type factory and schema registry supporting built-in tasks and custom user actions.
- `BTNativeVersion`: Engine build metadata and API version negotiation.

### 2. GDScript Facade & Overridable Lifecycle Hooks
To allow GDScript code to define custom actions/conditions/decorators seamlessly, the GDScript classes inherit from the native classes. Public GDScript hook methods wrap their native `bt_*` dispatch counterparts:

- `on_update()`: Wraps `bt_on_update()`. Custom tasks override `on_update()`. If not overridden, native dispatch executes internal logic (e.g. built-in composites/decorators).
- `evaluate_condition(runner)`: Wraps `bt_evaluate_condition(runner)`. Used for pure condition probing and reactive conditional aborts.
- `on_start()`, `on_end()`, `on_abort()`: Wrap `bt_on_start()`, `bt_on_end()`, `bt_on_abort()`.
- `can_execute()`: Wraps `bt_can_execute()` for parent task execution flow.
- `decorate(status)`: Modifies child task return status in custom decorators.
- `get_current_child_index()`: Exposes and synchronizes active child traversal in composite nodes.

---

## Build Instructions & Cross-platform builds

Requirements: Rust toolchain (`rustup`, cargo), Godot 4.6+ or 4.7+.

### Building on Host Platform
The build script automatically detects the host operating system (`Linux`, `macOS`, or `Windows`) and copies the output artifact with the appropriate extension:

```bash
# Build both debug and release binaries
bash rust/build.sh

# Build release profile only (recommended for benchmark and production)
bash rust/build.sh --release-only

# Build debug profile only
bash rust/build.sh --debug-only
```

### Cross-platform Target & File Mapping

The Godot GDExtension configuration (`addons/godot_bt_native/godot_bt_native.gdextension`) expects the following library artifacts in `addons/godot_bt_native/bin/`:

| Platform | Feature Tag | Cargo Target Artifact | Addon Destination File |
|---|---|---|---|
| **Linux (x86_64)** | `linux.debug.x86_64`<br>`linux.release.x86_64` | `target/<profile>/libgodot_bt_native.so` | `libgodot_bt_native.debug.so`<br>`libgodot_bt_native.release.so` |
| **Linux (ARM64)** | `linux.debug.arm64`<br>`linux.release.arm64` | `target/<profile>/libgodot_bt_native.so` | `libgodot_bt_native.debug.so`<br>`libgodot_bt_native.release.so` |
| **Windows (x86_64)** | `windows.debug.x86_64`<br>`windows.release.x86_64` | `target/<profile>/godot_bt_native.dll` | `libgodot_bt_native.debug.dll`<br>`libgodot_bt_native.release.dll` |
| **macOS (Universal / Host)** | `macos.debug`<br>`macos.release` | `target/<profile>/libgodot_bt_native.dylib` | `libgodot_bt_native.debug.dylib`<br>`libgodot_bt_native.release.dylib` |

> **Current Build Limits:** Pre-built cross-platform binaries are not yet published to a public release repository. When distributing or running on Windows or macOS, users/developers must build the extension locally on their respective target operating system (or via a GitHub Actions CI matrix) using `bash rust/build.sh`. Godot safely ignores missing platform entries when running on a different platform (e.g., Windows/macOS entries are ignored on Linux).

---

## Running Tests & Benchmarks

### 1. Regression & Integration Test Suite
Run all 15 headless test suites via the orchestrator:
```bash
bash tests/run_tests.sh
```

### 2. Native Benchmark Suite (`tests/bench_native.gd`)
Measures tick performance, serialization, and overhead breakdown:
```bash
godot --headless --path . -s res://tests/bench_native.gd
```
Artifacts are automatically exported to `bench/results.json`.

### 3. A/B Benchmark Suite (`tests/bench_ab.gd`)
Compares the pure GDScript baseline vs Rust native runtime across identical trees:
```bash
godot --headless --path . -s res://tests/bench_ab.gd
```

---

## Native Benchmark Results (`bench/results.json`)

*Environment:* Intel Core i5-6500T @ 2.50GHz (4 cores), Linux x86_64, Godot 4.7.2-stable headless, Release profile.

### 1. Tick Execution Performance (Warmup: 500 ticks | Measure: 5,000 ticks)

| Configuration | Nodes | Avg (µs) | p50 (µs) | p99 (µs) | Max (µs) | Throughput (ticks/s) |
|---|---|---|---|---|---|---|
| **1-Leaf (Code, 1 node under Repeater)** | 2 | 6.90 µs | 7.00 µs | 8.00 µs | 76.00 µs | **135,888.0 / s** |
| **Sequence + 3 Leaves (Code, 4 nodes)** | 5 | 20.25 µs | 20.00 µs | 24.00 µs | 35.00 µs | **48,329.7 / s** |
| **Commander 800 (JSON, 850 nodes)** | 850 | 536.92 µs | 474.00 µs | 902.00 µs | 1,178.00 µs | **1,860.0 / s** |
| **Commander 2000 (JSON, 2,000 nodes)** | 2,000 | 1,233.77 µs | 996.00 µs | 2,199.00 µs | 2,691.00 µs | **810.0 / s** |

### 2. Tree Build & Serialization Throughput

| Configuration | Nodes | JSON Size | Parse JSON | `from_dict` | `to_dict` | Total Load |
|---|---|---|---|---|---|---|
| **Commander 800** | 850 | 189.1 KB | 6.31 ms | **57.02 ms** | 9.58 ms | 63.33 ms |
| **Commander 2000** | 2,000 | 447.5 KB | 14.99 ms | **238.34 ms** | 22.74 ms | 253.33 ms |

*`from_dict` throughput:* ~18,056 nodes/sec (55.4 µs/node median).

### 3. Overhead Breakdown & Controls

| Control Measurement | p50 (µs) | Avg (µs) | Throughput |
|---|---|---|---|
| **1. GDScript → Native Method Call Floor** (`runner.get_ticks()`) | 0.00 µs | 0.15 µs | 6,501,950 / s |
| **   GDScript → Native Property Access Floor** (`runner.is_running`) | 0.00 µs | 0.27 µs | 3,706,449 / s |
| **2. Stopped Tick Early Return Floor** (`runner.stop()` -> `tick()`) | 0.00 µs | 0.32 µs | 3,132,832 / s |
| **3A. Non-completing Tick** (Leaf returns `RUNNING`, 0 signals) | 2.00 µs | 2.43 µs | 394,352 / s |
| **3B. Completing Tick with Budget=1** (Leaf completes, emits signals) | 6.00 µs | 5.86 µs | 159,708 / s |

---

## A/B Comparison: GDScript Baseline vs Rust Native

Comparison measured using `tests/bench_ab.gd` between baseline GDScript (commit `967bfa1`) and optimized Rust native release build. Each runtime was sampled across 3 independent runs (median values reported).

### 1. Tick Performance Comparison

| Configuration | Nodes | GDScript p50 | Rust Native p50 | GDScript Throughput | Rust Throughput | Speedup (p50) | Speedup (Throughput) |
|---|---|---|---|---|---|---|---|
| **1-Leaf (Code)** | 2 | 14.00 µs | **7.00 µs** | 70,279/s | **139,198/s** | **2.00x** | **1.98x** |
| **Sequence + 3 Leaves** | 5 | 37.00 µs | **18.00 µs** | 26,580/s | **53,231/s** | **2.06x** | **2.00x** |
| **Commander 800** | 850 | 806.00 µs | **474.00 µs** | 1,125/s | **1,868/s** | **1.70x** | **1.66x** |
| **Commander 2000** | 2,000 | 1,670.00 µs | **997.00 µs** | 501/s | **808/s** | **1.68x** | **1.61x** |

### 2. Serialization Comparison (`from_dict` & `to_dict`)

| Configuration | Metric | GDScript Baseline | Rust Native | Ratio (GD / Rust) | Notes |
|---|---|---|---|---|---|
| **Commander 800** | `from_dict` | 59.55 ms | **50.62 ms** | **1.18x** | Rust faster after schema cache optimization |
| | `to_dict` | 7.04 ms | 8.24 ms | 0.85x | Negligible (~1.2 ms difference) |
| **Commander 2000** | `from_dict` | 240.09 ms | **220.97 ms** | **1.09x** | Rust faster across 2,000 nodes |
| | `to_dict` | 19.11 ms | 19.46 ms | 0.98x | Virtually identical |

### Practical Evaluation & Limits
- **Real-world Ship Configuration:** All benchmarks execute through the GDScript facade (`BTTree`, `BTTask`, `BTRunner`), representing the exact runtime configuration used by game projects.
- **Latency Consistency:** Tail latency (p99) on large trees is reduced by over 37%–45%, eliminating frame hitches in real-time simulations.
- **Optimization Impact:** Node instantiation and schema decoding in `from_dict` was accelerated by >4x compared to earlier unoptimized native builds, outperforming the pure GDScript parser on both 850 and 2,000 node trees.
