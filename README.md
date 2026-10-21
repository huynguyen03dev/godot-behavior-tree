# Godot Behavior Tree (`godot_bt`)

A modular, production-grade Behavior Tree framework and visual node editor for **Godot 4.3+** (supporting 4.3 through 4.7+).

Designed for complex game AI, robotics, and decision systems. Features a visual graph editor, real-time Inspector editing, direct JSON code view, blackboard memory, and a decoupled runtime engine.

---

## Highlights

- **Visual Graph Editor**: Node-based graph with intuitive connection routing, auto-layout, zoom/pan controls, minimap, copy/paste, and undo/redo support.
- **Dual-Mode Authoring**:
  - **Visual & Inspector**: Click nodes to edit parameters, descriptions, and blackboard bindings in the dedicated Inspector panel.
  - **Direct JSON Code View**: Inspect or edit the underlying JSON hierarchy directly in-editor with instant validation and two-way sync.
- **Decoupled Architecture**: Engine core has zero hard dependencies on specific game logic or node hierarchies.
- **Pluggable Tree Providers**: Load behavior trees from disk (`.json`), in-memory dictionaries, or implement custom adapters for remote endpoints or database storage.
- **Blackboard System**: Built-in blackboard for sharing state between tasks, with value observer signals and runtime debugging.
- **Comprehensive Task Library**:
  - **Composites**: `Sequence`, `Selector`, `Parallel`, `RandomSelector`, `RandomSequence`, `UtilitySelector`.
  - **Decorators**: `Inverter`, `Repeater`, `Succeeder`, `Failer`, `TimeLimit`, `Cooldown`.
  - **Leaves**: Extensible `BTAction` and `BTCondition`.
- **Runtime Debugging**: Visualizes active running nodes, successes, and failures in real-time.

---

## Installation

### Method 1: Copy Addon
1. Copy the `addons/godot_bt` folder into your Godot project's `addons/` directory.
2. In Godot, go to **Project -> Project Settings -> Plugins**.
3. Enable **Godot Behavior Tree**.
4. The **Behavior Tree** editor tab will appear in the bottom panel.

### Method 2: Git Submodule
```bash
git submodule add https://github.com/huynguyen03dev/godot-behavior-tree.git addons/godot_bt
```

---

## Quickstart

### 1. Creating Custom Actions and Conditions

Inherit from `BTAction` or `BTCondition` in GDScript:

```gdscript
# custom_actions/action_attack.gd
class_name ActionAttack
extends BTAction

@export var damage: float = 10.0

func _tick(actor: Node, blackboard: BTBlackboard) -> int:
    var target = blackboard.get_var("target", null)
    if not is_instance_valid(target):
        return BTStatus.FAILURE
    
    actor.play_attack_animation()
    target.take_damage(damage)
    return BTStatus.SUCCESS
```

```gdscript
# custom_conditions/condition_has_target.gd
class_name ConditionHasTarget
extends BTCondition

func _tick(actor: Node, blackboard: BTBlackboard) -> int:
    var target = blackboard.get_var("target", null)
    if is_instance_valid(target) and target.is_alive():
        return BTStatus.SUCCESS
    return BTStatus.FAILURE
```

### 2. Running a Tree via Code

```gdscript
extends CharacterBody2D

var bt_runner: BTRunner
var blackboard: BTBlackboard

func _ready() -> void:
    blackboard = BTBlackboard.new()
    blackboard.set_var("speed", 250.0)
    
    # Load tree using the File Tree Source adapter
    var tree_source = BTFileTreeSource.new("res://ai/trees/")
    var tree: BTTree = tree_source.load_tree("patrol_ai")
    
    # Initialize runner
    bt_runner = BTRunner.new(self, tree, blackboard)

func _physics_process(delta: float) -> void:
    # Tick the tree every physics frame
    var status: int = bt_runner.tick(delta)
```

---

## Visual Editor & Dual-Mode Authoring

Open the **Behavior Tree** panel at the bottom of the Godot editor:

1. **Graph Canvas**: Drag, connect, and arrange composite, decorator, and action nodes.
2. **Inspector Panel (Right)**: Select any node to configure its parameters, blackboard variable keys, and runtime options with immediate feedback.
3. **JSON Code View**: Switch to the **Code View** tab at any time to review or modify the raw JSON specification. Changes synchronize directly back into the visual graph upon applying.
4. **Validation & Testing**: Run built-in tree consistency checks to verify missing children, circular links, or unset required properties before running your game.

---

## Architecture

```
godot_bt/
├── core/                  # Core Behavior Tree logic
│   ├── bt_node.gd         # Base tree node & status enums (SUCCESS, FAILURE, RUNNING)
│   ├── bt_composite.gd    # Sequence, Selector, Parallel, Random
│   ├── bt_decorator.gd    # Inverter, Repeater, Cooldown, TimeLimit
│   ├── bt_action.gd       # Base Action leaf task
│   ├── bt_condition.gd    # Base Condition leaf task
│   ├── bt_blackboard.gd   # Key-value blackboard with observers
│   ├── bt_tree.gd         # Tree data container and serialization
│   └── bt_runner.gd       # Runtime evaluation executor
├── adapters/              # Modular Tree Storage Providers
│   ├── bt_tree_source_provider.gd # Base interface
│   ├── bt_file_tree_source.gd     # Filesystem JSON tree loader/saver
│   └── bt_memory_tree_source.gd   # In-memory tree provider (for testing/procedural AI)
├── editor/                # Editor Bottom Panel & Visual Graph
│   ├── bt_viewer.gd       # GraphEdit canvas, node layout, Inspector, and JSON code view
│   ├── bt_graph_node.gd   # Custom GraphNode visual representation
│   └── bt_node_palette.gd # Searchable palette of available tasks & composites
└── plugin.gd              # Godot EditorPlugin registration
```

---

## Automated Test Suite

The repository includes a headless unit test suite verifying composites, decorators, memory sources, and serialization:

```bash
godot --headless --path . -s res://tests/test_runner.gd
```

All 22 core engine and serialization tests run in milliseconds without requiring an active display server.

---

## License

This project is open-source software licensed under the [MIT License](LICENSE).
Feel free to use it in commercial or open-source projects.
