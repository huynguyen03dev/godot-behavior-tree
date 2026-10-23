//! Helpers for instantiating the GDScript facade classes from Rust.
//!
//! The public classes (`BTTree`, `BTTask`, `BTRunner`, ...) stay thin GDScript
//! facades over the native bases so the documented API (constructors with
//! arguments, inner classes, `is` checks) keeps working. Native code that must
//! create such an object (subtree sub-runners, placeholder tasks, trees built
//! from JSON) goes through here.
//!
//! Instantiation uses `ClassDB` because a GDScript's `new()` is a language
//! construct, not a callable method (`script.call("new")` fails on 4.7).

use std::cell::RefCell;
use std::collections::HashMap;

use godot::classes::{Node, Script};
use godot::prelude::*;

use crate::blackboard::BTBlackboardNative;
use crate::registry::BTTaskRegistryNative;
use crate::task::BTTaskNative;
use crate::tree::BTTreeNative;

pub const TASK_SCRIPT: &str = "res://addons/godot_bt/core/bt_task.gd";
pub const TREE_SCRIPT: &str = "res://addons/godot_bt/core/bt_tree.gd";
pub const BLACKBOARD_SCRIPT: &str = "res://addons/godot_bt/core/bt_blackboard.gd";
pub const REGISTRY_SCRIPT: &str = "res://addons/godot_bt/core/bt_task_registry.gd";
pub const RUNNER_SCRIPT: &str = "res://addons/godot_bt/core/bt_runner.gd";
pub const SUBTREE_SCRIPT: &str = "res://addons/godot_bt/core/bt_subtree.gd";

thread_local! {
    static CACHE: RefCell<HashMap<String, Option<Gd<Script>>>> = RefCell::new(HashMap::new());
}

fn script(path: &str) -> Option<Gd<Script>> {
    if let Some(hit) = CACHE.with(|c| c.borrow().get(path).cloned()) {
        return hit;
    }
    let loaded = try_load::<Script>(path).ok().filter(|s| crate::common::is_valid(s));
    CACHE.with(|c| c.borrow_mut().insert(path.to_string(), loaded.clone()));
    loaded
}

pub fn clear_cache() {
    CACHE.with(|c| c.borrow_mut().clear());
}

/// Instantiates a facade script. GDScript classes are not in `ClassDB`
/// (`class_exists("BTTree")` is false), but `new` is callable on the script.
fn instantiate(path: &str) -> Option<Variant> {
    let mut script = script(path)?;
    let value = script.call("new", &[]);
    if value.get_type() == VariantType::OBJECT {
        Some(value)
    } else {
        None
    }
}

pub fn new_task() -> Option<Gd<BTTaskNative>> {
    instantiate(TASK_SCRIPT)?.try_to::<Gd<BTTaskNative>>().ok()
}

pub fn new_tree() -> Option<Gd<BTTreeNative>> {
    instantiate(TREE_SCRIPT)?.try_to::<Gd<BTTreeNative>>().ok()
}

pub fn new_blackboard() -> Option<Gd<BTBlackboardNative>> {
    instantiate(BLACKBOARD_SCRIPT)?
        .try_to::<Gd<BTBlackboardNative>>()
        .ok()
}

pub fn new_registry() -> Option<Gd<BTTaskRegistryNative>> {
    instantiate(REGISTRY_SCRIPT)?
        .try_to::<Gd<BTTaskRegistryNative>>()
        .ok()
}

pub fn new_runner(tree: Option<Gd<BTTreeNative>>) -> Option<Gd<Node>> {
    let value = instantiate(RUNNER_SCRIPT)?;
    let mut node = value.try_to::<Gd<Node>>().ok()?;
    if let Some(tree) = tree {
        node.set("tree", &tree.to_variant());
    }
    Some(node)
}

pub fn new_subtree(path: &GString) -> Option<Gd<BTTaskNative>> {
    let value = instantiate(SUBTREE_SCRIPT)?;
    let mut task = value.try_to::<Gd<BTTaskNative>>().ok()?;
    if !path.is_empty() {
        task.set("tree_path", &path.to_variant());
    }
    Some(task)
}
