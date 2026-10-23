//! Task registry: maps type names to GDScript factories (Callable or Script).

use std::cell::RefCell;

use godot::classes::{RefCounted, Script};
use godot::prelude::*;

use crate::common::is_valid;
use crate::facade;
use crate::task::{detect_overrides, BTTaskNative};

#[derive(Default)]
struct Entry {
    type_name: String,
    factory: Variant,
    category: GString,
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct BTTaskRegistryNative {
    base: Base<RefCounted>,
    entries: RefCell<Vec<Entry>>,
}

#[godot_api]
impl BTTaskRegistryNative {
    /// GDScript-facing shim: the facade adds default arguments.
    #[func]
    pub fn bt_register_task(&self, p_type: GString, factory: Variant, category: GString) {
        self.register_task(p_type, factory, category)
    }

    pub fn register_task(&self, p_type: GString, factory: Variant, category: GString) {
        let key = p_type.to_string();
        let mut entries = self.entries.borrow_mut();
        if let Some(slot) = entries.iter_mut().find(|e| e.type_name == key) {
            slot.factory = factory;
            slot.category = category;
        } else {
            entries.push(Entry {
                type_name: key,
                factory,
                category,
            });
        }
    }

    #[func]
    pub fn unregister_task(&self, p_type: GString) {
        let key = p_type.to_string();
        self.entries.borrow_mut().retain(|e| e.type_name != key);
    }

    #[func]
    pub fn has_task(&self, p_type: GString) -> bool {
        let key = p_type.to_string();
        self.entries.borrow().iter().any(|e| e.type_name == key)
    }

    #[func]
    pub fn get_category(&self, p_type: GString) -> GString {
        let key = p_type.to_string();
        self.entries
            .borrow()
            .iter()
            .find(|e| e.type_name == key)
            .map(|e| e.category.clone())
            .unwrap_or_else(|| GString::from("Unknown"))
    }

    #[func]
    pub fn create_task(&self, p_type: GString) -> Gd<BTTaskNative> {
        let key = p_type.to_string();
        let found = self
            .entries
            .borrow()
            .iter()
            .find(|e| e.type_name == key)
            .map(|e| (e.factory.clone(), e.category.clone()));

        if let Some((factory, category)) = found {
            let mut instance: Option<Gd<BTTaskNative>> = None;
            match factory.get_type() {
                VariantType::CALLABLE => {
                    let mut callable = factory.to::<Callable>();
                    let value = callable.callv(&VarArray::new());
                    instance = value.try_to::<Gd<BTTaskNative>>().ok();
                }
                VariantType::OBJECT => {
                    if let Ok(mut script) = factory.try_to::<Gd<Script>>() {
                        let value = script.call("new", &[]);
                        instance = value.try_to::<Gd<BTTaskNative>>().ok();
                    }
                }
                _ => {}
            }
            if let Some(task) = instance {
                if is_valid(&task) {
                    {
                        let guard = task.bind();
                        let mut d = guard.data_mut();
                        d.type_name = p_type.clone();
                        d.category = category;
                    }
                    detect_overrides(&task);
                    return task;
                }
            }
        }

        // Unknown type: placeholder node that never executes. The facade
        // registry knows how to build its inner `BTUnknownTask` class.
        let mut me = self.to_gd();
        let from_facade = me.call("_make_unknown", &[p_type.to_variant()]);
        let placeholder = from_facade
            .try_to::<Gd<BTTaskNative>>()
            .ok()
            .filter(|t| is_valid(t))
            .unwrap_or_else(|| {
                let mut task = BTTaskNative::new_gd();
                task.bind()._make_placeholder(p_type.clone());
                task
            });
        detect_overrides(&placeholder);
        placeholder
    }

    #[func]
    pub fn get_registered_types(&self) -> VarArray {
        let mut out = VarArray::new();
        for entry in self.entries.borrow().iter() {
            out.push(entry.type_name.as_str());
        }
        out
    }
}
