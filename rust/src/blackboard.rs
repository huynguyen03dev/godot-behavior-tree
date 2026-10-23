//! Native blackboard with parent-scope chaining and shared-variable semantics.

use std::cell::RefCell;

use godot::classes::RefCounted;
use crate::common::is_valid;
use godot::prelude::*;

/// One blackboard entry. Exposed to GDScript as `BTBlackboard.Variable`
/// (the GDScript facade declares an inner class extending this native class).
#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct BTTaskVariableNative {
    base: Base<RefCounted>,
    #[var]
    pub name: GString,
    #[var]
    pub type_name: GString,
    #[var]
    pub value: Variant,
    #[var]
    pub is_shared: bool,
    #[var]
    pub description: GString,
}

#[godot_api]
impl BTTaskVariableNative {
    #[func]
    pub fn make(name: GString, value: Variant, type_name: GString) -> Gd<BTTaskVariableNative> {
        let mut v = BTTaskVariableNative::new_gd();
        {
            let mut b = v.bind_mut();
            b.name = name;
            b.value = value;
            b.type_name = type_name;
            b.is_shared = true;
        }
        v
    }
}

/// Scoped blackboard. `set_var` writes into the nearest ancestor that owns a
/// shared variable of that name; otherwise the value is created locally.
#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct BTBlackboardNative {
    base: Base<RefCounted>,

    #[var(rename = parent_scope, get = get_parent_scope, set = set_parent_scope)]
    parent_scope_prop: PhantomVar<Variant>,
    parent: RefCell<Option<Gd<BTBlackboardNative>>>,

    // Insertion-ordered entries: (name, variable object).
    vars: RefCell<Vec<(String, Gd<BTTaskVariableNative>)>>,
}

#[godot_api]
impl BTBlackboardNative {
    #[signal]
    pub fn variable_changed(var_name: GString, new_val: Variant, old_val: Variant);

    #[func]
    pub fn get_parent_scope(&self) -> Variant {
        match &*self.parent.borrow() {
            Some(p) => p.to_variant(),
            None => Variant::nil(),
        }
    }

    #[func]
    pub fn set_parent_scope(&self, value: Variant) {
        *self.parent.borrow_mut() = value
            .try_to::<Gd<BTBlackboardNative>>()
            .ok()
            .filter(|p| is_valid(p));
    }

    pub fn find(&self, name: &str) -> Option<Gd<BTTaskVariableNative>> {
        self.vars
            .borrow()
            .iter()
            .find(|(k, _)| k == name)
            .map(|(_, v)| v.clone())
    }

    pub fn store(&self, name: &str, var: Gd<BTTaskVariableNative>) {
        let mut vars = self.vars.borrow_mut();
        if let Some(slot) = vars.iter_mut().find(|(k, _)| k == name) {
            slot.1 = var;
        } else {
            vars.push((name.to_string(), var));
        }
    }

    pub fn emit_changed(&self, name: &GString, new_val: &Variant, old_val: &Variant) {
        let mut me = self.to_gd();
        me.emit_signal(
            "variable_changed",
            &[name.to_variant(), new_val.clone(), old_val.clone()],
        );
    }

    /// Writes a variable in this scope only, never consulting ancestors.
    #[func]
    pub fn bt_set_var_local(
        &self,
        p_name: GString,
        p_value: Variant,
        p_type: GString,
        p_is_shared: bool,
        p_description: GString,
    ) {
        self.set_var_local(p_name, p_value, p_type, p_is_shared, p_description);
    }

    pub fn set_var_local(
        &self,
        p_name: GString,
        p_value: Variant,
        p_type: GString,
        p_is_shared: bool,
        p_description: GString,
    ) {
        let key = p_name.to_string();
        if let Some(existing) = self.find(&key) {
            let mut e = existing.clone();
            let old_val;
            {
                let mut v = e.bind_mut();
                old_val = v.value.clone();
                v.value = p_value.clone();
                if !p_type.is_empty() {
                    v.type_name = p_type;
                }
                v.is_shared = p_is_shared;
                if !p_description.is_empty() {
                    v.description = p_description;
                }
            }
            self.emit_changed(&p_name, &p_value, &old_val);
            return;
        }

        let type_str = if p_type.is_empty() {
            GString::from(type_name_of(&p_value))
        } else {
            p_type
        };
        let var = self.make_variable(&p_name, &p_value, &type_str, p_is_shared, &p_description);
        self.store(&key, var);
        self.emit_changed(&p_name, &p_value, &Variant::nil());
    }

    /// Writes a variable honouring shared ancestor scopes.
    /// GDScript-facing shim: the facade adds default arguments.
    #[func]
    pub fn bt_set_var(&self, p_name: GString, p_value: Variant, p_type: GString) {
        self.set_var(p_name, p_value, p_type)
    }

    pub fn set_var(&self, p_name: GString, p_value: Variant, p_type: GString) {
        let key = p_name.to_string();

        if let Some(existing) = self.find(&key) {
            let mut e = existing.clone();
            let old_val;
            {
                let mut v = e.bind_mut();
                old_val = v.value.clone();
                v.value = p_value.clone();
                if !p_type.is_empty() {
                    v.type_name = p_type.clone();
                }
            }
            self.emit_changed(&p_name, &p_value, &old_val);
            return;
        }

        // If an ancestor owns this name, either write through (shared) or stop
        // looking (private variable shadows the ancestor).
        let mut ancestor = self.parent.borrow().clone();
        while let Some(scope) = ancestor {
            if let Some(found) = scope.bind().find(&key) {
                let shared = found.bind().is_shared;
                if shared {
                    scope.bind().set_var(p_name, p_value, p_type);
                    return;
                }
                // A private ancestor variable does not receive the write; the
                // value is created locally so the caller sees their assignment.
                break;
            }
            let next = scope.bind().parent.borrow().clone();
            ancestor = next;
        }

        let type_str = if p_type.is_empty() {
            GString::from(type_name_of(&p_value))
        } else {
            p_type
        };
        let var = self.make_variable(&p_name, &p_value, &type_str, true, &GString::new());
        self.store(&key, var);
        self.emit_changed(&p_name, &p_value, &Variant::nil());
    }

    /// GDScript-facing shim: the facade adds default arguments.
    #[func]
    pub fn bt_get_var(&self, p_name: GString, default_value: Variant) -> Variant {
        self.get_var(p_name, default_value)
    }

    pub fn get_var(&self, p_name: GString, default_value: Variant) -> Variant {
        if let Some(v) = self.find(&p_name.to_string()) {
            return v.bind().value.clone();
        }
        let parent = self.parent.borrow().clone();
        if let Some(p) = parent {
            return p.bind().get_var(p_name, default_value);
        }
        default_value
    }

    #[func]
    pub fn has_var(&self, p_name: GString) -> bool {
        if self.find(&p_name.to_string()).is_some() {
            return true;
        }
        let parent = self.parent.borrow().clone();
        match parent {
            Some(p) => p.bind().has_var(p_name),
            None => false,
        }
    }

    #[func]
    pub fn remove_var(&self, p_name: GString) -> bool {
        let key = p_name.to_string();
        let removed = {
            let mut vars = self.vars.borrow_mut();
            match vars.iter().position(|(k, _)| *k == key) {
                Some(idx) => {
                    let (_, v) = vars.remove(idx);
                    Some(v)
                }
                None => None,
            }
        };
        match removed {
            Some(v) => {
                let old = v.bind().value.clone();
                self.emit_changed(&p_name, &Variant::nil(), &old);
                true
            }
            None => false,
        }
    }

    #[func]
    pub fn get_variable_obj(&self, p_name: GString) -> Option<Gd<BTTaskVariableNative>> {
        if let Some(v) = self.find(&p_name.to_string()) {
            return Some(v);
        }
        let parent = self.parent.borrow().clone();
        match parent {
            Some(p) => p.bind().get_variable_obj(p_name),
            None => None,
        }
    }

    /// Flattened name -> value view (parent scopes first, local values win).
    #[func]
    pub fn get_all_vars(&self) -> VarDictionary {
        let mut out = VarDictionary::new();
        let parent = self.parent.borrow().clone();
        if let Some(p) = parent {
            let inherited = p.bind().get_all_vars();
            for (k, v) in inherited.iter_shared() {
                out.set(&k, &v);
            }
        }
        for (k, v) in self.vars.borrow().iter() {
            out.set(k.as_str(), &v.bind().value.clone());
        }
        out
    }

    /// This scope's own variable objects, name -> Variable.
    #[func]
    pub fn get_all_variables(&self) -> VarDictionary {
        let mut out = VarDictionary::new();
        for (k, v) in self.vars.borrow().iter() {
            out.set(k.as_str(), &v.to_variant());
        }
        out
    }

    #[func]
    pub fn clear(&self) {
        self.vars.borrow_mut().clear();
    }
}

impl BTBlackboardNative {
    /// Builds a variable through the facade so GDScript keeps its
    /// `BTBlackboard.Variable` type (typed annotations and `is` checks).
    fn make_variable(
        &self,
        name: &GString,
        value: &Variant,
        type_name: &GString,
        is_shared: bool,
        description: &GString,
    ) -> Gd<BTTaskVariableNative> {
        let mut me = self.to_gd();
        let built = me.call(
            "_make_variable",
            &[name.to_variant(), value.clone(), type_name.to_variant()],
        );
        let mut var = match built.try_to::<Gd<BTTaskVariableNative>>() {
            Ok(var) if is_valid(&var) => var,
            _ => new_variable(name, value, type_name, is_shared, description),
        };
        {
            let mut v = var.bind_mut();
            v.is_shared = is_shared;
            v.description = description.clone();
        }
        var
    }
}

fn new_variable(
    name: &GString,
    value: &Variant,
    type_name: &GString,
    is_shared: bool,
    description: &GString,
) -> Gd<BTTaskVariableNative> {
    let mut var = BTTaskVariableNative::new_gd();
    {
        let mut v = var.bind_mut();
        v.name = name.clone();
        v.value = value.clone();
        v.type_name = type_name.clone();
        v.is_shared = is_shared;
        v.description = description.clone();
    }
    var
}

/// Type label used when a variable is created without an explicit type.
pub fn type_name_of(value: &Variant) -> &'static str {
    match value.get_type() {
        VariantType::BOOL => "bool",
        VariantType::INT => "int",
        VariantType::FLOAT => "float",
        VariantType::STRING => "String",
        VariantType::VECTOR2 => "Vector2",
        VariantType::VECTOR3 => "Vector3",
        VariantType::ARRAY => "Array",
        VariantType::DICTIONARY => "Dictionary",
        VariantType::OBJECT => "Object",
        _ => "Variant",
    }
}
