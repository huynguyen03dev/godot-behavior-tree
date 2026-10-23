use godot::init::InitStage;
use godot::prelude::*;

mod blackboard;
mod common;
pub mod facade;
mod registry;
mod runner;
mod subtree;
pub mod task;
mod tree;

struct GodotBtNative;

#[gdextension]
unsafe impl ExtensionLibrary for GodotBtNative {
    fn on_stage_deinit(stage: InitStage) {
        if stage == InitStage::Scene {
            facade::clear_cache();
            task::clear_override_cache();
        }
    }
}
