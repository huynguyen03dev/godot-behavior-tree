# Godot Behavior Tree (`godot_bt`)

A Behavior Tree addon and visual editor for **Godot 4** (4.3+).

It provides a lightweight runtime engine for behavior trees along with a built-in bottom panel editor featuring visual graph editing, node inspector property configuration, and direct JSON view.

## Features

- **Visual Editor**: Bottom panel editor using Godot's GraphEdit to create, connect, and arrange nodes.
- **Dual Editing**: Configure nodes via the Inspector panel or edit the underlying JSON representation directly with two-way sync.
- **Blackboard**: Key-value blackboard with change signals for sharing state across tasks.
- **Core Nodes**:
  - **Composites**: Sequence, Selector, Parallel, RandomSelector, RandomSequence. Conditional aborts support Self on Sequence and Lower Priority on Selector; Both combines those supported checks. This is not full external-sibling observer or Behavior Designer abort parity. Runtime abort checks reevaluate the guard prefix; conditions can provide a pure `evaluate_condition(runner)` probe (recommended), while legacy `Condition` tasks using `on_update()` remain supported.
  - **Decorators**: Inverter, Repeater, ReturnSuccess, ReturnFailure, UntilSuccess, UntilFailure, TimeLimit, Cooldown — with typed Inspector controls for their configuration.
  - **SubTree**: Modular tree embedding (`BTSubTree`) to reuse sub-behaviors with a shared blackboard; the parsed subtree is cached across runner restarts and reloaded only when `tree_path` changes.
  - **Leaves**: Extend `BTTask` in GDScript; tasks identify their category as Action or Condition.
- **Dynamic Parameters & Blackboard**: Dual-mode parameters supporting literal values or dynamic blackboard variable bindings (`@var_name` / `$var_name`). An unresolvable binding returns the parameter default, and `@@` / `$$` escape a literal leading `@` / `$`.
- **Task Lifecycle**: Hooks include `on_awake`, `on_reset`, `on_start`, `on_update`, `on_end`, `on_abort`, `on_pause`, and `on_event`. Signals: `tree_finished`, `task_started`, `task_finished`, and `task_aborted` (fires when a running task ends because its branch was aborted).
- **Pluggable Storage**: Load and save trees using JSON files on disk (`BTFileTreeSource`) or in-memory dictionaries (`BTMemoryTreeSource`). Saving validates the tree first and refuses invalid data.
- **Decoupled**: Pure GDScript runtime with no external dependencies.

The runner update budget bounds dispatched leaf task updates per tick only: set `max_task_executions_per_tick` (0 = unlimited; the legacy `ExecutionsPerTick` enum is deprecated and ignored). Condition reevaluation/probes (including legacy condition `on_update()` checks) are additional work outside `task_executions` and are not bounded by this budget; keep condition evaluation cheap and side-effect-free, preferably via `evaluate_condition(runner)`. When the budget is exhausted, traversal yields and resumes on a later tick. Task update hooks can use the runner's `actor`, `delta`, and monotonic `time` (advanced by each tick's delta). `TimeLimit` and `Cooldown` run on this simulated time, so pausing the runner, manual ticking, or `Engine.time_scale` behaves predictably.

## Installation

1. Copy the `addons/godot_bt` folder into your project's `addons/` directory.
2. In Godot, go to **Project -> Project Settings -> Plugins**.
3. Enable **Godot Behavior Tree**.
4. The **Behavior Tree** tab will appear in the bottom panel of the editor.

## Getting Started

### 1. Creating Custom Tasks

Extend `BTTask` and implement `on_update()`, returning a `BTStatus` value. The runner sets `task.owner` to itself (not the actor) and provides the actor separately on `BTRunner.actor`; the runner also assigns the tree blackboard. Use `get_param()` to read literal or blackboard-bound parameters.

```gdscript
# action_attack.gd
class_name ActionAttack
extends BTTask

func _init() -> void:
    type_name = "ActionAttack"
    category = "Action"

func on_update() -> int:
    var target = get_blackboard_var("target", null)
    if not is_instance_valid(target):
        return BTStatus.FAILURE
    if owner == null or not is_instance_valid(owner.actor):
        return BTStatus.FAILURE
    owner.actor.play_attack()
    target.take_damage(float(get_param("damage", 10.0)))
    return BTStatus.SUCCESS
```

Register custom task types with a `BTTaskRegistry` before parsing/loading a tree that refers to them:

```gdscript
var registry := BTTaskRegistry.new()
registry.register_task("ActionAttack", ActionAttack, "Action")
var source := BTFileTreeSource.new("res://ai/trees", registry)
var tree := source.load_tree("patrol_ai")
```

The file provider scans `.json` files in the specified directory. Pass the registry to the provider so custom task names can be instantiated; unregistered types become inactive placeholders.

### 2. Running a Tree in Code

Attach a runner to any node:

```gdscript
extends CharacterBody2D

var bt_runner: BTRunner
var blackboard: BTBlackboard

func _ready() -> void:
    var registry := BTTaskRegistry.new()
    registry.register_task("ActionAttack", ActionAttack, "Action")
    var tree_source := BTFileTreeSource.new("res://ai/trees/", registry)
    var tree: BTTree = tree_source.load_tree("patrol_ai")
    if tree == null:
        push_error("Could not load patrol_ai")
        return

    # Each independently running agent needs its own mutable tree instance.
    blackboard = tree.blackboard
    blackboard.set_var("speed", 200.0)
    bt_runner = BTRunner.new(tree)
    bt_runner.actor = self
    add_child(bt_runner) # Node lifecycle (_exit_tree stops it) requires tree membership.
    bt_runner.set_process(false) # Disable automatic _process ticks; manual physics ticks below are used.
    bt_runner.start()

func _physics_process(delta: float) -> void:
    # Manual physics ticking: don't also enable auto ticking or call tick from _process.
    if is_instance_valid(bt_runner):
        bt_runner.tick(delta)
```

`BTRunner` can instead tick automatically in `_process` while running; choose one ticking mode to avoid double ticks. `start()` resets task state and invokes awake hooks, `stop()` ends active tasks, and starting again resets the run. Ensure `actor` is a valid `Node` for tasks that need it. Parameter values are stored on tasks; a parameter can bind dynamically to a blackboard key using `@key` or `set_param(name, key, true)`. When exporting, ensure JSON tree files are included by your export preset (for example, use an include filter for `*.json`) so runtime loading can find them.

## Editor Usage

Open the **Behavior Tree** tab at the bottom of the editor. With no custom provider configured it scans `res://` for `.json` trees; use **📁 Source…** to pick another folder, or set the project setting `behavior_tree/custom_source_provider` to a script path extending `BTTreeSourceProvider`. **＋ New** starts an unsaved `new_tree` with a Sequence root.

- **Canvas**: Drag and connect nodes — dragging a child to another parent reparents it, and refused connections are explained in the status bar. Node positions persist in the tree's `metadata["node_positions"]` and survive reloads. The root cannot be deleted; select another node and press **⭐ Set as Root** first. Deleting a node removes its whole subtree.
- **Undo/Redo**: Every editing action (add/delete/connect/rename/parameters/blackboard edits, Apply JSON) is undoable with **Ctrl+Z** and redoable with **Ctrl+Shift+Z** / **Ctrl+Y** while the panel has focus; loading or creating a tree clears the history.
- **Inspector**: Click any node to inspect and edit its name, abort type, and parameters. Built-in decorators expose typed controls for their configuration (Repeater `count` / `repeat_forever` / `end_on_failure`, Cooldown `cooldown_time`, TimeLimit `time_limit`), editing never changes a parameter's type, and `Vector2` / `Vector3` / `Color` values accept `(x, y[, z[, w]])`.
- **Code View**: Switch to the Code View tab to view or edit the raw JSON tree directly. Click **⚡ Apply JSON to Tree** to update the graph; it validates first and warns when the model changed since the JSON was captured.
- **Filter**: The search box and the "Placeholders Only" checkbox hide non-matching nodes in the graph and list only matches (plus their ancestors) in the Tree tab.

**Save** validates the tree before writing and reports the first validation error. Unsaved changes prompt before switching or reloading trees, and the Godot editor warns about unsaved behavior trees on close (the plugin's save hooks write the open tree).

## Running Tests & Demo

### Night Courier minigame

Launch at the demo's intended viewport size with `godot --path . --resolution 1152x720 res://demo/minigame/night_courier.tscn`. The title screen shows the controls: Enter/click starts; WASD or arrow keys move; Space dashes; P/Escape pauses/resumes; R restarts after a result. Collect all three parcels at **(175,185)**, **(570,545)**, and **(970,180)**, then reach the green exit at **(1000,565)**. Start at **(100,595)**. Two guards patrol horizontally: (330,175)↔(510,175) and (690,430)↔(900,430), initially near (370,175) and (780,430). Their 225 px detection radius triggers the behavior tree's prioritized chase (Lower Priority abort), last-seen search (move to last position, look for about one second), then patrol. Patrol speed is 90 px/s; chase speed is 1.35× patrol. Each guard has its own actor and runner; the demo drives runners manually and disables their automatic processing to prevent double ticks.

Optional playtest telemetry: append `-- --playtest-state=/absolute/path.json` after the scene. It prints JSON-line snapshots and overwrites the given file every 0.2 seconds with phase, player position/health/parcels, guard positions/behavior/search state/runner ticks, lifecycle counters, round, live runner count, elapsed time, dash cooldown/time, and invulnerability. Telemetry is observational only.

An interactive demo scene is included under `demo/demo.tscn`. **Step BT Tick** executes exactly one tick and reports the result: demo actions report RUNNING on their first tick in an activation and complete on the second, and a finished runner restarts on the next press so every press runs a real tick. The demo registers its own Condition/Action leaf tasks and re-binds the runner automatically when you apply JSON in the embedded viewer.

Run the headless suites from the project root. Godot 4.3+ is the target; these suites were verified with Godot 4.7.2.

```bash
godot --headless --path . -s res://tests/test_runner.gd
godot --headless --path . -s res://tests/test_runtime_regressions.gd
godot --headless --path . -s res://tests/test_model_regressions.gd
godot --headless --path . -s res://tests/test_editor_regressions.gd
godot --headless --path . -s res://tests/test_minigame_regressions.gd
godot --headless --path . -s res://tests/test_demo_regressions.gd
```

Roadmap items no longer open: Undo/Redo, New/Open workflows, and real filtering shipped. Still open: incremental rendering is partially in (surviving nodes are reused; structural edits still rebuild connections), scoped blackboards for subtrees, and a recursive file-source listing.

## Behavior notes

- An unregistered task type loads as an inactive placeholder: Sequence/Selector stop the tree with INACTIVE (`stopped_at_placeholder` records the type), while Parallel ignores inactive branches as long as another sibling is active.
- A decorator with no child returns INACTIVE and stops the tree.
- Repeater/UntilSuccess/UntilFailure run at most one child iteration per tick, so `count = 100` needs at least 100 ticks.
- Conditional-abort re-evaluation only probes guard conditions; if a higher-priority branch's guard passes but its action fails, the lower-priority branch is re-preempted on the next tick.
- `task_finished` reports FAILURE when a running task is aborted (preemption, sibling failure, or `interrupt`); connect `task_aborted` to distinguish aborts from real failures. `stop()` also closes every started task with `task_finished`, whose status is the task's last status (RUNNING for a mid-run stop).
- The `@@` / `$$` escape is part of the saved format: a literal stored before the escape existed (e.g. `@@x` meant as data) now reads back as `@x`.
- `BTRunner.time` is monotonic for the runner's lifetime and is not reset by `set_tree()`, so a Cooldown window survives swapping to a different tree on the same runner.
- A second `interrupt()` on a task that is no longer running is ignored (the first one wins).
- Saving writes a built-in decorator's effective configuration (count, repeat_forever, end_on_failure, cooldown_time, time_limit) and a composite's `abort_type` (when not NONE) even when those were assigned from code instead of via parameters.
- The file source lists the `.json` files directly inside its folder (no recursion), works in exported PCK builds, reports save failures through `last_error`, and `refresh()` drops in-folder files that were deleted on disk.

## License

MIT License. See [LICENSE](LICENSE) for details.
