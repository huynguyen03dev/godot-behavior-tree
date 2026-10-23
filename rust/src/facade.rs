//! Helpers for instantiating the GDScript facade classes from Rust.
//!
//! The public classes (`BTTree`, `BTTask`, `BTRunner`, ...) stay thin GDScript
//! facades over the native bases so the documented API (constructors with
//! arguments, inner classes, `is` checks) keeps working. Native code that must
//! create such an object (subtree sub-runners, placeholder tasks, trees built
//! from JSON) goes through here.

use std::cell::RefCell;
use std::collections::HashMap;

use godot::classes::{Node, RefCounted, Script};
use godot::prelude::*;

use crate::blackboard::BTBlackboardNative;
use crate::common::is_valid;
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

pub fn script(path: &str) -> Option<Gd<Script>> {
    if let Some(hit) = CACHE.with(|c| c.borrow().get(path).cloned()) {
        return hit;
    }
    let loaded = try_load::<Script>(path).ok().filter(|s| is_valid(&s));
    CACHE.with(|c| c.borrow_mut().insert(path.to_string(), loaded.clone()));
    loaded
}

fn new_from(script: Gd<Script>, args: &[Variant]) -> Option<Variant> {
    let mut s = script;
    let value = s.call("new", args);
    if value.get_type() == VariantType::OBJECT {
        Some(value)
    } else {
        None
    }
}

/// Instantiates an inner class (`class Foo extends ...`) of a facade script.
pub fn inner_new(outer_path: &str, class_name: &str, args: &[Variant]) -> Option<Variant> {
    let mut outer = script(outer_path)?;
    let constants = outer
        .call("get_script_constant_map", &[])
        .try_to::<VarDictionary>()
        .ok()?;
    let inner = constants.get(class_name)?.try_to::<Gd<Script>>().ok()?;
    new_from(inner, args)
}

pub fn new_task() -> Option<Gd<BTTaskNative>> {
    new_from(script(TASK_SCRIPT)?, &[])?.try_to::<Gd<BTTaskNative>>().ok()
}

pub fn new_tree() -> Option<Gd<BTTreeNative>> {
    new_from(script(TREE_SCRIPT)?, &[])?.try_to::<Gd<BTTreeNative>>().ok()
}

pub fn new_blackboard() -> Option<Gd<BTBlackboardNative>> {
    new_from(script(BLACKBOARD_SCRIPT)?, &[])?
        .try_to::<Gd<BTBlackboardNative>>()
        .ok()
}

pub fn new_registry() -> Option<Gd<BTTaskRegistryNative>> {
    new_from(script(REGISTRY_SCRIPT)?, &[])?
        .try_to::<Gd<BTTaskRegistryNative>>()
        .ok()
}

pub fn new_runner(tree: Option<Gd<BTTreeNative>>) -> Option<Gd<Node>> {
    let args = vec![match tree {
        Some(t) => t.to_variant(),
        None => Variant::nil(),
    }];
    let obj = new_from(script(RUNNER_SCRIPT)?, &args)?;
    obj.try_to::<Gd<Node>>().ok()
}

pub fn new_unknown_task(type_name: &GString) -> Option<Gd<BTTaskNative>> {
    let obj = inner_new(REGISTRY_SCRIPT, "BTUnknownTask", &[type_name.to_variant()])?;
    obj.try_to::<Gd<BTTaskNative>>().ok()
}
