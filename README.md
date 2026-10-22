# Godot Behavior Tree (`godot_bt`)

A Behavior Tree addon and visual editor for **Godot 4** (4.3+).

It provides a lightweight runtime engine for behavior trees along with a built-in bottom panel editor featuring visual graph editing, node inspector property configuration, and direct JSON view.

## Features

- **Visual Editor**: Bottom panel editor using Godot's GraphEdit to create, connect, and arrange nodes.
- **Dual Editing**: Configure nodes via the Inspector panel or edit the underlying JSON representation directly with two-way sync.
- **Blackboard**: Key-value blackboard with change signals for sharing state across tasks.
- **Core Nodes**:
  - **Composites**: Sequence, Selector, Parallel, RandomSelector, RandomSequence. Conditional aborts support Self on Sequence and Lower Priority on Selector; Both combines those supported checks. This is not full external-sibling observer or Behavior Designer abort parity. Runtime abort checks reevaluate the guard prefix; conditions can provide a pure `evaluate_condition(runner)` probe (recommended), while legacy `Condition` tasks using `on_update()` remain supported.
  - **Decorators**: Inverter, Repeater, ReturnSuccess, ReturnFailure, UntilSuccess, UntilFailure, TimeLimit, Cooldown.
  - **SubTree**: Modular tree embedding (`BTSubTree`) to reuse sub-behaviors with a shared blackboard.
  - **Leaves**: Extend `BTTask` in GDScript; tasks identify their category as Action or Condition.
- **Dynamic Parameters & Blackboard**: Dual-mode parameters supporting literal values or dynamic blackboard variable bindings (`@var_name`).
- **Task Lifecycle**: Hooks include `on_awake`, `on_reset`, `on_start`, `on_update`, `on_end`, `on_abort`, `on_pause`, and `on_event`.
- **Pluggable Storage**: Load and save trees using JSON files on disk (`BTFileTreeSource`) or in-memory dictionaries (`BTMemoryTreeSource`).
- **Decoupled**: Pure GDScript runtime with no external dependencies.

The runner update budget bounds dispatched leaf task updates per tick only. Condition reevaluation/probes (including legacy condition `on_update()` checks) are additional work outside `task_executions` and are not bounded by this budget; keep condition evaluation cheap and side-effect-free, preferably via `evaluate_condition(runner)`. A budget of zero or less is unlimited; when a positive budget is exhausted, traversal yields and resumes on a later tick. Task update hooks can use the runner's actor and current tick delta.

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

Open the **Behavior Tree** tab at the bottom of the editor:

- **Canvas**: Drag and connect nodes. Supports zoom, pan, minimap, auto-layout, and multi-selection.
- **Inspector**: Click any node to inspect and edit its properties, parameters, or comments.
- **Code View**: Switch to the Code View tab to view or edit the raw JSON tree directly. Click **Apply Changes** to update the graph canvas.

## Running Tests & Demo

### Night Courier minigame

Launch at the demo's intended viewport size with `godot --path . --resolution 1152x720 res://demo/minigame/night_courier.tscn`. The title screen shows the controls: Enter/click starts; WASD or arrow keys move; Space dashes; P/Escape pauses/resumes; R restarts after a result. Collect all three parcels at **(175,185)**, **(570,545)**, and **(970,180)**, then reach the green exit at **(1000,565)**. Start at **(100,595)**. Two guards patrol horizontally: (330,175)↔(510,175) and (690,430)↔(900,430), initially near (370,175) and (780,430). Their 225 px detection radius triggers the behavior tree's prioritized chase (Lower Priority abort), last-seen search (move to last position, look for about one second), then patrol. Patrol speed is 90 px/s; chase speed is 1.35× patrol. Each guard has its own actor and runner; the demo drives runners manually and disables their automatic processing to prevent double ticks.

Optional playtest telemetry: append `-- --playtest-state=/absolute/path.json` after the scene. It prints JSON-line snapshots and overwrites the given file every 0.2 seconds with phase, player position/health/parcels, guard positions/behavior/search state/runner ticks, lifecycle counters, round, live runner count, elapsed time, dash cooldown/time, and invulnerability. Telemetry is observational only.

An interactive demo scene is included under `demo/demo.tscn`.

Run the headless suites from the project root. Godot 4.3+ is the target; these suites were verified with Godot 4.7.2.

```bash
godot --headless --path . -s res://tests/test_runner.gd
godot --headless --path . -s res://tests/test_runtime_regressions.gd
godot --headless --path . -s res://tests/test_model_regressions.gd
godot --headless --path . -s res://tests/test_editor_regressions.gd
```

Roadmap items not yet implemented include Undo/Redo, New/Open workflows, and scoped blackboards for subtrees.

## License

MIT License. See [LICENSE](LICENSE) for details.
