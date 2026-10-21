# Godot Behavior Tree (`godot_bt`)

A Behavior Tree addon and visual editor for **Godot 4** (4.3+).

It provides a lightweight runtime engine for behavior trees along with a built-in bottom panel editor featuring visual graph editing, node inspector property configuration, and direct JSON view.

## Features

- **Visual Editor**: Bottom panel editor using Godot's GraphEdit to create, connect, and arrange nodes.
- **Dual Editing**: Configure nodes via the Inspector panel or edit the underlying JSON representation directly with two-way sync.
- **Blackboard**: Key-value blackboard with change signals for sharing state across tasks.
- **Core Nodes**:
  - **Composites**: Sequence, Selector, Parallel, RandomSelector, RandomSequence (with **Conditional Aborts**: None, Self, Lower Priority, Both).
  - **Decorators**: Inverter, Repeater, ReturnSuccess, ReturnFailure, UntilSuccess, UntilFailure, TimeLimit, Cooldown.
  - **SubTree**: Modular tree embedding (`BTSubTree`) to reuse sub-behaviors with shared or scoped blackboards.
  - **Leaves**: Extendable `BTTask` (or `BTAction` / `BTCondition`) base classes in GDScript.
- **Dynamic Parameters & Blackboard**: Dual-mode parameters supporting literal values or dynamic blackboard variable bindings (`@var_name`).
- **Task Lifecycle**: Clean hooks for `on_awake`, `on_start`, `on_update`, `on_end`, `on_abort`, `on_pause`, and `on_event`.
- **Pluggable Storage**: Load and save trees using JSON files on disk (`BTFileTreeSource`) or in-memory dictionaries (`BTMemoryTreeSource`).
- **Decoupled**: Pure GDScript runtime with no external dependencies.

## Installation

1. Copy the `addons/godot_bt` folder into your project's `addons/` directory.
2. In Godot, go to **Project -> Project Settings -> Plugins**.
3. Enable **Godot Behavior Tree**.
4. The **Behavior Tree** tab will appear in the bottom panel of the editor.

## Getting Started

### 1. Creating Custom Actions and Conditions

Create custom tasks by extending `BTAction` or `BTCondition`:

```gdscript
# action_attack.gd
class_name ActionAttack
extends BTAction

@export var damage: float = 10.0

func _tick(actor: Node, blackboard: BTBlackboard) -> int:
    var target = blackboard.get_var("target", null)
    if not is_instance_valid(target):
        return BTStatus.FAILURE
    
    actor.play_attack()
    target.take_damage(damage)
    return BTStatus.SUCCESS
```

```gdscript
# condition_has_target.gd
class_name ConditionHasTarget
extends BTCondition

func _tick(actor: Node, blackboard: BTBlackboard) -> int:
    var target = blackboard.get_var("target", null)
    if is_instance_valid(target) and target.is_alive():
        return BTStatus.SUCCESS
    return BTStatus.FAILURE
```

### 2. Running a Tree in Code

Attach a runner to any node:

```gdscript
extends CharacterBody2D

var bt_runner: BTRunner
var blackboard: BTBlackboard

func _ready() -> void:
    blackboard = BTBlackboard.new()
    blackboard.set_var("speed", 200.0)
    
    # Load tree from json
    var tree_source = BTFileTreeSource.new("res://ai/trees/")
    var tree: BTTree = tree_source.load_tree("patrol_ai")
    
    # Create the runner
    bt_runner = BTRunner.new(self, tree, blackboard)

func _physics_process(delta: float) -> void:
    bt_runner.tick(delta)
```

## Editor Usage

Open the **Behavior Tree** tab at the bottom of the editor:

- **Canvas**: Drag and connect nodes. Supports zoom, pan, minimap, auto-layout, and multi-selection.
- **Inspector**: Click any node to inspect and edit its properties, parameters, or comments.
- **Code View**: Switch to the Code View tab to view or edit the raw JSON tree directly. Click **Apply Changes** to update the graph canvas.

## Running Tests & Demo

An interactive demo scene is included under `demo/demo.tscn`.

You can also run the headless test suite from the command line:

```bash
godot --headless --path . -s res://tests/test_runner.gd
```

## License

MIT License. See [LICENSE](LICENSE) for details.
