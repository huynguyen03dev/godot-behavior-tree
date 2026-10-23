use godot::prelude::*;

mod blackboard;
mod common;
mod facade;
mod registry;
mod runner;
mod subtree;
mod task;
mod tree;

struct GodotBtNative;

#[gdextension]
unsafe impl ExtensionLibrary for GodotBtNative {}
