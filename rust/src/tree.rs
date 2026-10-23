//! Tree model, serialization and validation (JSON-compatible dictionaries).

use std::cell::RefCell;
use std::collections::HashMap;

use godot::classes::RefCounted;
use godot::prelude::*;

use crate::blackboard::{type_name_of, BTBlackboardNative};
use crate::common::{coerce_bool, is_valid};
use crate::facade;
use crate::registry::BTTaskRegistryNative;
use crate::task::{detect_overrides, Kind, BTTaskNative};

pub const BUILTIN_COMPOSITE_TYPES: [&str; 5] = [
    "Sequence",
    "Selector",
    "Parallel",
    "RandomSequence",
    "RandomSelector",
];

pub const BUILTIN_DECORATOR_TYPES: [&str; 8] = [
    "Inverter",
    "ReturnSuccess",
    "ReturnFailure",
    "Repeater",
    "UntilSuccess",
    "UntilFailure",
    "Cooldown",
    "TimeLimit",
];

impl BTTreeNative {
    pub fn data(&self) -> std::cell::Ref<'_, TreeData> {
        self.d.borrow()
    }

    pub fn data_mut(&self) -> std::cell::RefMut<'_, TreeData> {
        self.d.borrow_mut()
    }
}

impl Default for TreeData {
    fn default() -> Self {
        Self {
            tree_name: GString::from("Untitled Tree"),
            description: GString::new(),
            metadata: VarDictionary::new(),
            root: None,
            nodes: Vec::new(),
            blackboard: None,
            registry: None,
            next_id_hint: 1,
            by_id: std::collections::HashMap::new(),
        }
    }
}

pub struct TreeData {
    pub tree_name: GString,
    pub description: GString,
    pub metadata: VarDictionary,
    pub root: Option<Gd<BTTaskNative>>,
    pub nodes: Vec<Gd<BTTaskNative>>,
    pub blackboard: Option<Gd<BTBlackboardNative>>,
    pub registry: Option<Gd<BTTaskRegistryNative>>,
    pub next_id_hint: i64,
    pub by_id: HashMap<i64, Gd<BTTaskNative>>,
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct BTTreeNative {
    base: Base<RefCounted>,
    d: RefCell<TreeData>,

    #[var(get = get_tree_name, set = set_tree_name)]
    tree_name: PhantomVar<GString>,
    #[var(get = get_description, set = set_description)]
    description: PhantomVar<GString>,
    #[var(get = get_root_task, no_set)]
    root_task: PhantomVar<Variant>,
    #[var(get = get_node_list, no_set)]
    node_list: PhantomVar<VarArray>,
    #[var(get = get_blackboard, set = set_blackboard)]
    blackboard: PhantomVar<Variant>,
    #[var(get = get_metadata, set = set_metadata)]
    metadata: PhantomVar<VarDictionary>,
    #[var(get = get_registry, set = set_registry)]
    registry: PhantomVar<Variant>,
}

#[godot_api]
impl BTTreeNative {
    // ------------------------------------------------------------ properties
    #[func]
    pub fn get_tree_name(&self) -> GString {
        self.d.borrow().tree_name.clone()
    }
    #[func]
    pub fn set_tree_name(&self, value: GString) {
        self.d.borrow_mut().tree_name = value;
    }

    #[func]
    pub fn get_description(&self) -> GString {
        self.d.borrow().description.clone()
    }
    #[func]
    pub fn set_description(&self, value: GString) {
        self.d.borrow_mut().description = value;
    }

    #[func]
    pub fn get_root_task(&self) -> Variant {
        match &self.d.borrow().root {
            Some(task) => task.to_variant(),
            None => Variant::nil(),
        }
    }

    #[func]
    pub fn get_node_list(&self) -> VarArray {
        let mut out = VarArray::new();
        for node in &self.d.borrow().nodes {
            out.push(node);
        }
        out
    }

    #[func]
    pub fn get_blackboard(&self) -> Variant {
        match &self.d.borrow().blackboard {
            Some(bb) => bb.to_variant(),
            None => Variant::nil(),
        }
    }
    #[func]
    pub fn set_blackboard(&self, value: Variant) {
        self.d.borrow_mut().blackboard = value
            .try_to::<Gd<BTBlackboardNative>>()
            .ok()
            .filter(|b| is_valid(&b));
    }

    #[func]
    pub fn get_metadata(&self) -> VarDictionary {
        self.d.borrow().metadata.clone()
    }
    #[func]
    pub fn set_metadata(&self, value: VarDictionary) {
        self.d.borrow_mut().metadata = value;
    }

    #[func]
    pub fn get_registry(&self) -> Variant {
        match &self.d.borrow().registry {
            Some(registry) => registry.to_variant(),
            None => Variant::nil(),
        }
    }
    #[func]
    pub fn set_registry(&self, value: Variant) {
        self.d.borrow_mut().registry = value
            .try_to::<Gd<BTTaskRegistryNative>>()
            .ok()
            .filter(|r| is_valid(&r));
    }

    // ------------------------------------------------------------ builder
    #[func]
    pub fn add_node(&self, task: Variant) -> Variant {
        let Ok(task) = task.try_to::<Gd<BTTaskNative>>() else {
            return Variant::nil();
        };
        if !is_valid(&task) {
            return Variant::nil();
        }
        self.register_node(task.clone());
        task.to_variant()
    }

    pub fn register_node(&self, task: Gd<BTTaskNative>) {
        if self
            .d
            .borrow()
            .nodes
            .iter()
            .any(|n| n.instance_id() == task.instance_id())
        {
            return;
        }
        let blackboard = self.d.borrow().blackboard.clone();
        let id_guard = task.bind();
        let existing_id = id_guard.data().id;
        drop(id_guard);
        let taken = existing_id >= 0 && self.d.borrow().by_id.contains_key(&existing_id);
        let id = if existing_id >= 0 && !taken {
            existing_id
        } else {
            let mut candidate = self.d.borrow().next_id_hint;
            while self.d.borrow().by_id.contains_key(&candidate) {
                candidate += 1;
            }
            candidate
        };
        {
            let guard = task.bind();
            let mut td = guard.data_mut();
            td.id = id;
            td.blackboard_ref = blackboard;
        }
        {
            let mut d = self.d.borrow_mut();
            if id >= d.next_id_hint {
                d.next_id_hint = id + 1;
            }
            d.by_id.insert(id, task.clone());
            d.nodes.push(task);
        }
    }

    #[func]
    pub fn set_root(&self, task: Variant) {
        let Ok(task) = task.try_to::<Gd<BTTaskNative>>() else {
            return;
        };
        if !is_valid(&task) {
            return;
        }
        self.register_node(task.clone());
        {
            let __g_td = task.bind();
        let mut td = __g_td.data_mut();
            if td.category.is_empty()
                || td.category.to_string() == "Task"
                || td.category.to_string() == "Action"
            {
                td.category = GString::from("Root");
            }
        }
        self.d.borrow_mut().root = Some(task);
    }

    #[func]
    pub fn connect_parent_child(&self, parent_task: Variant, child_task: Variant) {
        let (Ok(parent_task), Ok(child_task)) = (
            parent_task.try_to::<Gd<BTTaskNative>>(),
            child_task.try_to::<Gd<BTTaskNative>>(),
        ) else {
            return;
        };
        if !is_valid(&parent_task) || !is_valid(&child_task) {
            return;
        }
        if parent_task.instance_id() == child_task.instance_id() {
            return;
        }
        let is_root = {
            let d = self.d.borrow();
            d.root
                .as_ref()
                .map(|r| r.instance_id() == child_task.instance_id())
                .unwrap_or(false)
        };
        if is_root {
            return;
        }
        // Reject cycles.
        let mut cursor = Some(parent_task.instance_id());
        while let Some(id) = cursor {
            if id == child_task.instance_id() {
                return;
            }
            cursor = Gd::<BTTaskNative>::try_from_instance_id(id)
                .ok()
                .and_then(|t| t.bind().data().parent_ref);
        }
        self.register_node(parent_task.clone());
        self.register_node(child_task.clone());
        parent_task.bind().add_child_task(child_task.to_variant());
    }

    #[func]
    pub fn disconnect_parent_child(&self, parent_task: Variant, child_task: Variant) {
        let (Ok(parent_task), Ok(child_task)) = (
            parent_task.try_to::<Gd<BTTaskNative>>(),
            child_task.try_to::<Gd<BTTaskNative>>(),
        ) else {
            return;
        };
        if !is_valid(&parent_task) || !is_valid(&child_task) {
            return;
        }
        parent_task.bind().remove_child_task(child_task.to_variant());
    }

    #[func]
    pub fn remove_node(&self, task: Variant) {
        let Ok(task) = task.try_to::<Gd<BTTaskNative>>() else {
            return;
        };
        if !is_valid(&task) {
            return;
        }
        let parent_ref = task.bind().data().parent_ref;
        if let Some(parent) =
            parent_ref.and_then(|id| Gd::<BTTaskNative>::try_from_instance_id(id).ok())
        {
            parent.bind().remove_child_task(task.to_variant());
        }
        let children = task.bind().data().children.clone();
        for child in children {
            task.bind().remove_child_task(child.to_variant());
        }
        let mut d = self.d.borrow_mut();
        if d
            .root
            .as_ref()
            .map(|r| r.instance_id() == task.instance_id())
            .unwrap_or(false)
        {
            d.root = None;
        }
        let id = task.bind().data().id;
        d.by_id.remove(&id);
        d.nodes
            .retain(|n| n.instance_id() != task.instance_id());
    }

    #[func]
    pub fn get_node_by_id(&self, id: i64) -> Option<Gd<BTTaskNative>> {
        self.d.borrow().by_id.get(&id).cloned()
    }

    #[func]
    pub fn get_node_count(&self) -> i64 {
        self.d.borrow().nodes.len() as i64
    }

    #[func]
    pub fn get_stats(&self) -> VarDictionary {
        let d = self.d.borrow();
        let mut roots = 0i64;
        let mut composites = 0i64;
        let mut decorators = 0i64;
        let mut leaves = 0i64;
        let mut placeholders = 0i64;
        let root_id = d.root.as_ref().map(|r| r.instance_id());

        for task in &d.nodes {
            let __g_td = task.bind();
        let td = __g_td.data();
            if td.is_placeholder {
                placeholders += 1;
            }
            let is_root = root_id == Some(task.instance_id()) || td.category.to_string() == "Root";
            if is_root {
                roots += 1;
            }
            if td.kind.is_decorator() || td.category.to_string() == "Decorator" {
                decorators += 1;
            } else if td.kind.is_composite()
                || td.category.to_string() == "Composite"
                || (td.kind.has_children() && !td.kind.is_decorator())
            {
                composites += 1;
            } else if !is_root {
                leaves += 1;
            } else if !td.kind.has_children() {
                leaves += 1;
            }
        }

        let mut out = VarDictionary::new();
        out.set("total", d.nodes.len() as i64);
        out.set("root", roots);
        out.set("composite", composites);
        out.set("decorator", decorators);
        out.set("leaf", leaves);
        out.set("placeholder", placeholders);
        out
    }

    // ------------------------------------------------------------ serialization
    #[func]
    pub fn to_dict(&self) -> VarDictionary {
        let d = self.d.borrow();
        let mut nodes_data = VarArray::new();

        for task in &d.nodes {
            let __g_td = task.bind();
        let td = __g_td.data();
            let mut child_ids = VarArray::new();
            for child in &td.children {
                child_ids.push(child.bind().data().id);
            }
            let mut params = td.parameters.clone();

            let mut handle = task.clone();
            if handle.has_method("get_parameter_schema") {
                if let Ok(schema) = handle
                    .call("get_parameter_schema", &[])
                    .try_to::<VarDictionary>()
                {
                    for (key, entry) in schema.iter_shared() {
                        if !params.contains_key(&key) {
                            if let Ok(entry) = entry.try_to::<VarDictionary>() {
                                if let Some(default) = entry.get("default") {
                                    params.set(&key, &default);
                                }
                            }
                        }
                    }
                }
            }
            if td.kind.is_composite()
                && !params.contains_key("abort_type")
                && td.abort_type != 0
            {
                params.set("abort_type", td.abort_type);
            }

            let parent_id = td
                .parent_ref
                .and_then(|id| Gd::<BTTaskNative>::try_from_instance_id(id).ok())
                .map(|p| p.bind().data().id)
                .unwrap_or(-1);

            let mut entry = VarDictionary::new();
            entry.set("id", td.id);
            entry.set("friendly_name", &td.friendly_name.clone().to_variant());
            entry.set("type_name", &td.type_name.clone().to_variant());
            entry.set("category", &td.category.clone().to_variant());
            entry.set("is_placeholder", td.is_placeholder);
            entry.set("parent_id", parent_id);
            entry.set("children_ids", &child_ids.to_variant());
            entry.set("parameters", &encode_value(&params.to_variant()));
            nodes_data.push(&entry.to_variant());
        }

        let mut bb_data = VarDictionary::new();
        if let Some(bb) = &d.blackboard {
            let all = bb.bind().get_all_variables();
            for (name, var) in all.iter_shared() {
                let v = var.try_to::<Gd<crate::blackboard::BTTaskVariableNative>>();
                if let Ok(var_obj) = v {
                    let vd = var_obj.bind();
                    let mut entry = VarDictionary::new();
                    entry.set("value", &encode_value(&vd.value));
                    entry.set("type_name", &vd.type_name.clone().to_variant());
                    entry.set("is_shared", vd.is_shared);
                    entry.set("description", &vd.description.clone().to_variant());
                    bb_data.set(&name, &entry.to_variant());
                }
            }
        }

        let mut out = VarDictionary::new();
        out.set("tree_name", &d.tree_name.clone().to_variant());
        out.set("description", &d.description.clone().to_variant());
        out.set("root_id", d.root.as_ref().map(|r| r.bind().data().id).unwrap_or(-1));
        out.set("nodes", &nodes_data.to_variant());
        out.set("blackboard", &bb_data.to_variant());
        out.set("metadata", &d.metadata.clone().to_variant());
        out
    }

    #[func]
    pub fn validate_dict(data: VarDictionary, registry: Variant) -> PackedStringArray {
        let registry = registry
            .try_to::<Gd<BTTaskRegistryNative>>()
            .ok()
            .filter(|r| is_valid(&r));
        let mut errors = VarArray::new();
        validate_tree_data(&data, registry.as_ref(), &mut errors);
        let mut out = PackedStringArray::new();
        for item in errors.iter_shared() {
            out.push(&item.to::<GString>());
        }
        out
    }

    #[func]
    pub fn from_dict(data: VarDictionary, registry: Variant) -> Variant {
        let registry = registry
            .try_to::<Gd<BTTaskRegistryNative>>()
            .ok()
            .filter(|r| is_valid(&r));
        match build_tree(&data, registry) {
            Some(tree) => tree.to_variant(),
            None => Variant::nil(),
        }
    }
}

// -------------------------------------------------------------------- build

pub fn build_tree(
    data: &VarDictionary,
    registry: Option<Gd<BTTaskRegistryNative>>,
) -> Option<Gd<BTTreeNative>> {
    let validation_registry = registry.clone().or_else(facade::new_registry);
    let mut errors = VarArray::new();
    validate_tree_data(data, validation_registry.as_ref(), &mut errors);
    if !errors.is_empty() {
        let joined = join_errors(&errors);
        godot_error!("Invalid behavior tree data: {}", joined);
        return None;
    }

    let mut tree = facade::new_tree().unwrap_or_else(|| {
        let t = BTTreeNative::new_gd();
        t
    });

    {
        let tree_guard = tree.bind();
        let mut d = tree_guard.d.borrow_mut();
        d.tree_name = data
            .get("tree_name")
            .map(|v| v.to::<GString>())
            .unwrap_or_else(|| GString::from("Untitled Tree"));
        d.description = data
            .get("description")
            .map(|v| v.to::<GString>())
            .unwrap_or_default();
        d.metadata = data
            .get("metadata")
            .and_then(|v| v.try_to::<VarDictionary>().ok())
            .unwrap_or_default();
    }

    let registry = registry
        .or_else(|| tree.bind().d.borrow().registry.clone())
        .or_else(facade::new_registry);
    if let Some(reg) = &registry {
        tree.bind().d.borrow_mut().registry = Some(reg.clone());
    }

    let nodes_data = data
        .get("nodes")
        .and_then(|v| v.try_to::<VarArray>().ok())
        .unwrap_or_default();

    let mut id_to_task: HashMap<i64, Gd<BTTaskNative>> = HashMap::new();
    let mut children_map: HashMap<i64, Vec<i64>> = HashMap::new();

    // 1. Create tasks.
    for entry in nodes_data.iter_shared() {
        let Ok(node) = entry.try_to::<VarDictionary>() else {
            continue;
        };
        let nid = node.get("id").map(|v| to_int(&v)).unwrap_or(0);
        let type_name = node
            .get("type_name")
            .map(|v| v.to::<GString>())
            .unwrap_or_else(|| GString::from("BTTask"));
        let mut task = match &registry {
            Some(reg) => reg.bind().create_task(type_name.clone()),
            None => facade::new_task().unwrap_or_else(BTTaskNative::new_gd),
        };
        if !is_valid(&task) {
            task = BTTaskNative::new_gd();
            task.bind()._make_placeholder(type_name.clone());
        }

        let known = registry
            .as_ref()
            .map(|r| r.bind().has_task(type_name.clone()))
            .unwrap_or(false);
        {
            let __g_td = task.bind();
        let mut td = __g_td.data_mut();
            td.id = nid;
            td.friendly_name = node
                .get("friendly_name")
                .map(|v| v.to::<GString>())
                .unwrap_or_else(|| type_name.clone());
            if !known {
                if let Some(cat) = node.get("category") {
                    td.category = cat.to::<GString>();
                }
            }
            td.parameters = VarDictionary::new();
            if let Some(params) = node.get("parameters").and_then(|v| v.try_to::<VarDictionary>().ok()) {
                for (key, value) in params.iter_shared() {
                    let decoded = decode_value(&value);
                    td.parameters.set(&key, &decoded);
                }
            }
        }

        // Typed parameter schema: coerce values to the declared type.
        {
            let mut handle = task.clone();
            if handle.has_method("get_parameter_schema") {
                if let Ok(schema) = handle.call("get_parameter_schema", &[]).try_to::<VarDictionary>() {
                    for (key, entry) in schema.iter_shared() {
                        let Ok(entry) = entry.try_to::<VarDictionary>() else {
                            continue;
                        };
                        let has_value = task.bind().data().parameters.contains_key(&key);
                        if !has_value {
                            continue;
                        }
                        let raw = task.bind().data().parameters.at(&key);
                        let declared = entry
                            .get("type")
                            .map(|v| v.to::<GString>().to_string())
                            .unwrap_or_default();
                        let coerced = match declared.as_str() {
                            "int" => to_int(&raw).to_variant(),
                            "float" => to_float(&raw).to_variant(),
                            "bool" => {
                                let fallback = entry
                                    .get("default")
                                    .map(|v| v.to::<bool>())
                                    .unwrap_or(false);
                                coerce_bool(&raw, fallback).to_variant()
                            }
                            _ => continue,
                        };
                        let mut handle = task.clone();
                        handle.set(&StringName::from(&key.to::<GString>()), &coerced);
                    }
                }
            }
        }

        if task.bind().data().kind.is_composite() {
            let abort = task.bind().data().parameters.get("abort_type");
            if let Some(abort) = abort {
                let value = to_int(&abort);
                task.bind().set_abort_type(value);
            }
        }

        children_map.insert(
            nid,
            node.get("children_ids")
                .and_then(|v| v.try_to::<VarArray>().ok())
                .map(|arr| arr.iter_shared().map(|v| to_int(&v)).collect())
                .unwrap_or_default(),
        );

        tree.bind().register_node(task.clone());
        id_to_task.insert(nid, task);
    }

    // 2. Connect parent-child.
    let mut ordered: Vec<(i64, Vec<i64>)> = children_map.into_iter().collect();
    ordered.sort_by_key(|(id, _)| *id);
    for (nid, child_ids) in ordered {
        let Some(parent) = id_to_task.get(&nid).cloned() else {
            continue;
        };
        if !parent.bind().data().kind.has_children() && !child_ids.is_empty() {
            godot_error!("Invalid behavior tree data: leaf node {} has children", nid);
            return None;
        }
        if parent.bind().data().kind.is_decorator() && child_ids.len() > 1 {
            godot_error!("Invalid behavior tree data: decorator {} has multiple children", nid);
            return None;
        }
        for cid in child_ids {
            if let Some(child) = id_to_task.get(&cid).cloned() {
                tree.bind()
                    .connect_parent_child(parent.to_variant(), child.to_variant());
            }
        }
    }

    // 3. Root.
    let root_id = data.get("root_id").map(|v| to_int(&v)).unwrap_or(-1);
    if let Some(root) = id_to_task.get(&root_id).cloned() {
        tree.bind().set_root(root.to_variant());
    } else if let Some(first) = tree.bind().d.borrow().nodes.first().cloned() {
        tree.bind().set_root(first.to_variant());
    }

    // 4. Blackboard.
    if let Some(bb_data) = data.get("blackboard").and_then(|v| v.try_to::<VarDictionary>().ok()) {
        let blackboard = tree.bind().d.borrow().blackboard.clone();
        if let Some(bb) = blackboard {
            for (key, serialized) in bb_data.iter_shared() {
                if let Ok(entry) = serialized.try_to::<VarDictionary>() {
                    if entry.contains_key("value") {
                        let value = decode_value(&entry.get("value").unwrap());
                        let type_name = entry
                            .get("type_name")
                            .map(|v| v.to::<GString>())
                            .unwrap_or_else(|| GString::from(type_name_of(&value)));
                        bb.bind().set_var(key.to::<GString>(), value, type_name);
                        if let Some(mut var) = bb.bind().get_variable_obj(key.to::<GString>()) {
                            let mut v = var.bind_mut();
                            v.is_shared = entry
                                .get("is_shared")
                                .map(|v| v.to::<bool>())
                                .unwrap_or(true);
                            v.description = entry
                                .get("description")
                                .map(|v| v.to::<GString>())
                                .unwrap_or_default();
                        }
                        continue;
                    }
                }
                bb.bind().set_var(key.to::<GString>(), serialized, GString::new());
            }
        }
    }

    Some(tree)
}

// -------------------------------------------------------------------- validation

pub fn validate_tree_data(
    data: &VarDictionary,
    registry: Option<&Gd<BTTaskRegistryNative>>,
    errors: &mut VarArray,
) {
    let Some(nodes) = data.get("nodes").and_then(|v| v.try_to::<VarArray>().ok()) else {
        errors.push("nodes must be an array");
        return;
    };
    if let Some(meta) = data.get("metadata") {
        if meta.try_to::<VarDictionary>().is_err() {
            errors.push("metadata must be a dictionary");
        }
    }
    if let Some(bb) = data.get("blackboard") {
        match bb.try_to::<VarDictionary>() {
            Err(_) => errors.push("blackboard must be a dictionary"),
            Ok(bb) => {
                for (key, entry) in bb.iter_shared() {
                    let encoded = entry
                        .try_to::<VarDictionary>()
                        .ok()
                        .and_then(|d| d.get("value"))
                        .unwrap_or(entry.clone());
                    if !valid_encoded(&encoded) {
                        errors.push(
                            format!(
                                "blackboard variable {} contains malformed encoded value",
                                key
                            )
                            .as_str(),
                        );
                    }
                }
            }
        }
    }

    let mut by_id: HashMap<i64, VarDictionary> = HashMap::new();
    for (index, node) in nodes.iter_shared().enumerate() {
        let Ok(node) = node.try_to::<VarDictionary>() else {
            errors.push(format!("node {} must have an integer id", index).as_str());
            continue;
        };
        let Some(id_value) = node.get("id") else {
            errors.push(format!("node {} must have an integer id", index).as_str());
            continue;
        };
        if !is_integer(&id_value) {
            errors.push(format!("node {} must have an integer id", index).as_str());
            continue;
        }
        let id = to_int(&id_value);
        if id < 0 || by_id.contains_key(&id) {
            errors.push(format!("invalid or duplicate node id {}", id).as_str());
        }
        if let Some(params) = node.get("parameters") {
            if params.try_to::<VarDictionary>().is_err() {
                errors.push(format!("node {} parameters must be a dictionary", id).as_str());
            }
        }
        if let Some(children) = node.get("children_ids") {
            if children.try_to::<VarArray>().is_err() {
                errors.push(format!("node {} children_ids must be an array", id).as_str());
            }
        }
        let parameters = node
            .get("parameters")
            .and_then(|v| v.try_to::<VarDictionary>().ok())
            .unwrap_or_default();
        for (_, value) in parameters.iter_shared() {
            if !valid_encoded(&value) {
                errors.push(format!("node {} contains malformed encoded value", id).as_str());
                break;
            }
        }
        let type_name = node
            .get("type_name")
            .map(|v| v.to::<GString>().to_string())
            .unwrap_or_default();
        if BUILTIN_COMPOSITE_TYPES.contains(&type_name.as_str())
            && parameters.contains_key("abort_type")
        {
            let abort = parameters.at("abort_type");
            if !is_integer(&abort) || to_int(&abort) < 0 || to_int(&abort) > 3 {
                errors.push(
                    format!("node {} abort_type must be an integer from 0 to 3", id).as_str(),
                );
            }
        }
        by_id.insert(id, node);
    }

    let root_id = data
        .get("root_id")
        .filter(|v| is_integer(v))
        .map(|v| to_int(&v))
        .unwrap_or(-1);
    if root_id < 0 || !by_id.contains_key(&root_id) {
        errors.push("root_id must identify an existing node");
    }
    if by_id.is_empty() {
        errors.push("tree must contain nodes");
    }

    let mut parents: HashMap<i64, i64> = HashMap::new();
    let mut edges: HashMap<i64, Vec<i64>> = HashMap::new();
    for id in by_id.keys() {
        parents.insert(*id, 0);
        edges.insert(*id, Vec::new());
    }

    let mut shape_cache: HashMap<String, (bool, bool)> = HashMap::new();
    let ids: Vec<i64> = by_id.keys().copied().collect();
    for id in ids {
        let node = by_id.get(&id).cloned().unwrap_or_default();
        let child_ids = node
            .get("children_ids")
            .and_then(|v| v.try_to::<VarArray>().ok())
            .unwrap_or_default();
        if !child_ids.is_empty() {
            let type_name = node
                .get("type_name")
                .map(|v| v.to::<GString>().to_string())
                .unwrap_or_default();
            let (can_have_children, is_decorator) = match shape_cache.get(&type_name) {
                Some(shape) => *shape,
                None => {
                    let shape = node_parent_shape(&type_name, registry);
                    shape_cache.insert(type_name.clone(), shape);
                    shape
                }
            };
            if !can_have_children {
                errors.push(
                    format!(
                        "node {} of type '{}' has children but cannot hold them",
                        id, type_name
                    )
                    .as_str(),
                );
            } else if is_decorator && child_ids.len() > 1 {
                errors.push(format!("decorator {} has multiple children", id).as_str());
            }
        }
        for child_value in child_ids.iter_shared() {
            let child = if is_integer(&child_value) {
                to_int(&child_value)
            } else {
                -1
            };
            if child < 0 || !by_id.contains_key(&child) {
                errors.push(format!("node {} references missing child {}", id, child).as_str());
                continue;
            }
            *parents.entry(child).or_insert(0) += 1;
            edges.entry(id).or_default().push(child);
        }
    }

    for (id, count) in &parents {
        if *count > 1 {
            errors.push(format!("node {} has multiple parents", id).as_str());
        }
    }
    if by_id.contains_key(&root_id) && parents.get(&root_id).copied().unwrap_or(0) > 0 {
        errors.push("root node cannot have a parent");
    }

    let mut colors: HashMap<i64, i32> = HashMap::new();
    for id in by_id.keys() {
        colors.insert(*id, 0);
    }
    for id in by_id.keys() {
        if colors.get(id).copied().unwrap_or(0) == 0 && has_cycle(*id, &edges, &mut colors) {
            errors.push("hierarchy contains a cycle");
            break;
        }
    }
}

fn node_parent_shape(
    type_name: &str,
    registry: Option<&Gd<BTTaskRegistryNative>>,
) -> (bool, bool) {
    if let Some(registry) = registry {
        let task = registry.bind().create_task(GString::from(type_name));
        let __g_td = task.bind();
        let td = __g_td.data();
        let is_decorator = td.kind.is_decorator()
            || registry
                .bind()
                .get_category(GString::from(type_name))
                .to_string()
                == "Decorator";
        return (td.kind.has_children(), is_decorator);
    }
    if BUILTIN_DECORATOR_TYPES.contains(&type_name) {
        return (true, true);
    }
    if BUILTIN_COMPOSITE_TYPES.contains(&type_name) {
        return (true, false);
    }
    (true, false)
}

fn has_cycle(id: i64, edges: &HashMap<i64, Vec<i64>>, colors: &mut HashMap<i64, i32>) -> bool {
    colors.insert(id, 1);
    if let Some(children) = edges.get(&id) {
        for child in children {
            let color = colors.get(child).copied().unwrap_or(0);
            if color == 1 || (color == 0 && has_cycle(*child, edges, colors)) {
                return true;
            }
        }
    }
    colors.insert(id, 2);
    false
}

// -------------------------------------------------------------------- value codec

fn tagged(type_name: &str, components: Vec<f64>) -> Variant {
    let mut dict = VarDictionary::new();
    dict.set("__bt_type", type_name);
    let mut arr = VarArray::new();
    for c in components {
        arr.push(c);
    }
    dict.set("value", &arr.to_variant());
    dict.to_variant()
}

pub fn encode_value(value: &Variant) -> Variant {
    match value.get_type() {
        VariantType::FLOAT => {
            let f = value.to::<f64>();
            if !f.is_finite() {
                let mut dict = VarDictionary::new();
                dict.set("__bt_type", "float");
                dict.set(
                    "value",
                    if f.is_nan() {
                        "nan"
                    } else if f > 0.0 {
                        "inf"
                    } else {
                        "-inf"
                    },
                );
                return dict.to_variant();
            }
            value.clone()
        }
        VariantType::VECTOR2 => {
            let v = value.to::<Vector2>();
            tagged("Vector2", vec![v.x as f64, v.y as f64])
        }
        VariantType::VECTOR2I => {
            let v = value.to::<Vector2i>();
            tagged("Vector2i", vec![v.x as f64, v.y as f64])
        }
        VariantType::VECTOR3 => {
            let v = value.to::<Vector3>();
            tagged("Vector3", vec![v.x as f64, v.y as f64, v.z as f64])
        }
        VariantType::VECTOR3I => {
            let v = value.to::<Vector3i>();
            tagged("Vector3i", vec![v.x as f64, v.y as f64, v.z as f64])
        }
        VariantType::VECTOR4 => {
            let v = value.to::<Vector4>();
            tagged("Vector4", vec![v.x as f64, v.y as f64, v.z as f64, v.w as f64])
        }
        VariantType::VECTOR4I => {
            let v = value.to::<Vector4i>();
            tagged("Vector4i", vec![v.x as f64, v.y as f64, v.z as f64, v.w as f64])
        }
        VariantType::COLOR => {
            let v = value.to::<Color>();
            tagged("Color", vec![v.r as f64, v.g as f64, v.b as f64, v.a as f64])
        }
        VariantType::RECT2 => {
            let v = value.to::<Rect2>();
            tagged(
                "Rect2",
                vec![
                    v.position.x as f64,
                    v.position.y as f64,
                    v.size.x as f64,
                    v.size.y as f64,
                ],
            )
        }
        VariantType::RECT2I => {
            let v = value.to::<Rect2i>();
            tagged(
                "Rect2i",
                vec![
                    v.position.x as f64,
                    v.position.y as f64,
                    v.size.x as f64,
                    v.size.y as f64,
                ],
            )
        }
        VariantType::QUATERNION => {
            let v = value.to::<Quaternion>();
            tagged("Quaternion", vec![v.x as f64, v.y as f64, v.z as f64, v.w as f64])
        }
        VariantType::PLANE => {
            let v = value.to::<Plane>();
            tagged(
                "Plane",
                vec![v.normal.x as f64, v.normal.y as f64, v.normal.z as f64, v.d as f64],
            )
        }
        VariantType::AABB => {
            let v = value.to::<Aabb>();
            tagged(
                "AABB",
                vec![
                    v.position.x as f64,
                    v.position.y as f64,
                    v.position.z as f64,
                    v.size.x as f64,
                    v.size.y as f64,
                    v.size.z as f64,
                ],
            )
        }
        VariantType::TRANSFORM2D => {
            let v = value.to::<Transform2D>();
            tagged(
                "Transform2D",
                vec![
                    v.a.x as f64,
                    v.a.y as f64,
                    v.b.x as f64,
                    v.b.y as f64,
                    v.origin.x as f64,
                    v.origin.y as f64,
                ],
            )
        }
        VariantType::BASIS => {
            let v = value.to::<Basis>();
            tagged(
                "Basis",
                vec![
                    v.rows[0].x as f64,
                    v.rows[0].y as f64,
                    v.rows[0].z as f64,
                    v.rows[1].x as f64,
                    v.rows[1].y as f64,
                    v.rows[1].z as f64,
                    v.rows[2].x as f64,
                    v.rows[2].y as f64,
                    v.rows[2].z as f64,
                ],
            )
        }
        VariantType::TRANSFORM3D => {
            let v = value.to::<Transform3D>();
            let b = v.basis;
            tagged(
                "Transform3D",
                vec![
                    b.rows[0].x as f64,
                    b.rows[0].y as f64,
                    b.rows[0].z as f64,
                    b.rows[1].x as f64,
                    b.rows[1].y as f64,
                    b.rows[1].z as f64,
                    b.rows[2].x as f64,
                    b.rows[2].y as f64,
                    b.rows[2].z as f64,
                    v.origin.x as f64,
                    v.origin.y as f64,
                    v.origin.z as f64,
                ],
            )
        }
        VariantType::PROJECTION => {
            let v = value.to::<Projection>();
            let mut components = Vec::with_capacity(16);
            for row in 0..4 {
                components.push(v.cols[row].x as f64);
                components.push(v.cols[row].y as f64);
                components.push(v.cols[row].z as f64);
                components.push(v.cols[row].w as f64);
            }
            tagged("Projection", components)
        }
        VariantType::ARRAY => {
            let arr = value.to::<VarArray>();
            let mut out = VarArray::new();
            for item in arr.iter_shared() {
                out.push(&encode_value(&item));
            }
            out.to_variant()
        }
        VariantType::DICTIONARY => {
            let dict = value.to::<VarDictionary>();
            let mut out = VarDictionary::new();
            for (key, item) in dict.iter_shared() {
                out.set(&key, &encode_value(&item));
            }
            out.to_variant()
        }
        _ => value.clone(),
    }
}

pub fn decode_value(value: &Variant) -> Variant {
    if let Ok(dict) = value.try_to::<VarDictionary>() {
        if dict.len() == 2 && dict.contains_key("__bt_type") && dict.contains_key("value") {
            let tag = dict.get("__bt_type").unwrap().to::<GString>().to_string();
            let payload = dict.get("value").unwrap();
            if tag == "float" {
                return match payload.to::<GString>().to_string().as_str() {
                    "inf" => f64::INFINITY.to_variant(),
                    "-inf" => f64::NEG_INFINITY.to_variant(),
                    _ => f64::NAN.to_variant(),
                };
            }
            if let Ok(arr) = payload.try_to::<VarArray>() {
                let c: Vec<f64> = arr.iter_shared().map(|v| to_float(&v)).collect();
                let f = |i: usize| *c.get(i).unwrap_or(&0.0);
                let i = |i: usize| *c.get(i).unwrap_or(&0.0) as i32;
                return match tag.as_str() {
                    "Vector2" => Vector2::new(f(0) as f32, f(1) as f32).to_variant(),
                    "Vector2i" => Vector2i::new(i(0), i(1)).to_variant(),
                    "Vector3" => Vector3::new(f(0) as f32, f(1) as f32, f(2) as f32).to_variant(),
                    "Vector3i" => Vector3i::new(i(0), i(1), i(2)).to_variant(),
                    "Vector4" => {
                        Vector4::new(f(0) as f32, f(1) as f32, f(2) as f32, f(3) as f32).to_variant()
                    }
                    "Vector4i" => Vector4i::new(i(0), i(1), i(2), i(3)).to_variant(),
                    "Color" => Color::from_rgba(f(0) as f32, f(1) as f32, f(2) as f32, f(3) as f32)
                        .to_variant(),
                    "Rect2" => Rect2::new(
                        Vector2::new(f(0) as f32, f(1) as f32),
                        Vector2::new(f(2) as f32, f(3) as f32),
                    )
                    .to_variant(),
                    "Rect2i" => Rect2i::new(Vector2i::new(i(0), i(1)), Vector2i::new(i(2), i(3)))
                        .to_variant(),
                    "Quaternion" => {
                        Quaternion::new(f(0) as f32, f(1) as f32, f(2) as f32, f(3) as f32)
                            .to_variant()
                    }
                    "Plane" => Plane::new(
                        Vector3::new(f(0) as f32, f(1) as f32, f(2) as f32),
                        f(3) as f32,
                    )
                    .to_variant(),
                    "AABB" => Aabb::new(
                        Vector3::new(f(0) as f32, f(1) as f32, f(2) as f32),
                        Vector3::new(f(3) as f32, f(4) as f32, f(5) as f32),
                    )
                    .to_variant(),
                    "Transform2D" => Transform2D::from_cols(
                        Vector2::new(f(0) as f32, f(1) as f32),
                        Vector2::new(f(2) as f32, f(3) as f32),
                        Vector2::new(f(4) as f32, f(5) as f32),
                    )
                    .to_variant(),
                    "Basis" => Basis::from_rows(
                            Vector3::new(f(0) as f32, f(1) as f32, f(2) as f32),
                            Vector3::new(f(3) as f32, f(4) as f32, f(5) as f32),
                            Vector3::new(f(6) as f32, f(7) as f32, f(8) as f32),
                        )
                    .to_variant(),
                    "Transform3D" => Transform3D::new(
                        Basis::from_rows(
                            Vector3::new(f(0) as f32, f(1) as f32, f(2) as f32),
                            Vector3::new(f(3) as f32, f(4) as f32, f(5) as f32),
                            Vector3::new(f(6) as f32, f(7) as f32, f(8) as f32),
                        ),
                        Vector3::new(f(9) as f32, f(10) as f32, f(11) as f32),
                    )
                    .to_variant(),
                    "Projection" => Projection::from_cols(
                        Vector4::new(f(0) as f32, f(1) as f32, f(2) as f32, f(3) as f32),
                        Vector4::new(f(4) as f32, f(5) as f32, f(6) as f32, f(7) as f32),
                        Vector4::new(f(8) as f32, f(9) as f32, f(10) as f32, f(11) as f32),
                        Vector4::new(f(12) as f32, f(13) as f32, f(14) as f32, f(15) as f32),
                    )
                    .to_variant(),
                    _ => Variant::nil(),
                };
            }
        }
    }
    if let Ok(arr) = value.try_to::<VarArray>() {
        let mut out = VarArray::new();
        for item in arr.iter_shared() {
            out.push(&decode_value(&item));
        }
        return out.to_variant();
    }
    if let Ok(dict) = value.try_to::<VarDictionary>() {
        let mut out = VarDictionary::new();
        for (key, item) in dict.iter_shared() {
            out.set(&key, &decode_value(&item));
        }
        return out.to_variant();
    }
    value.clone()
}

fn valid_encoded(value: &Variant) -> bool {
    match value.get_type() {
        VariantType::NIL | VariantType::BOOL | VariantType::INT | VariantType::STRING => true,
        VariantType::FLOAT => value.to::<f64>().is_finite(),
        VariantType::ARRAY => {
            let arr = value.to::<VarArray>();
            arr.iter_shared().all(|v| valid_encoded(&v))
        }
        VariantType::DICTIONARY => {
            let dict = value.to::<VarDictionary>();
            if dict.contains_key("__bt_type") {
                if dict.len() != 2 || !dict.contains_key("value") {
                    return false;
                }
                let tag = dict.get("__bt_type").unwrap().to::<GString>().to_string();
                let payload = dict.get("value").unwrap();
                if tag == "float" {
                    if payload.get_type() != VariantType::STRING {
                        return false;
                    }
                    return matches!(payload.to::<GString>().to_string().as_str(), "inf" | "-inf" | "nan");
                }
                let sizes: &[(&str, usize, bool)] = &[
                    ("Vector2", 2, false),
                    ("Vector2i", 2, true),
                    ("Vector3", 3, false),
                    ("Vector3i", 3, true),
                    ("Vector4", 4, false),
                    ("Vector4i", 4, true),
                    ("Color", 4, false),
                    ("Rect2", 4, false),
                    ("Rect2i", 4, true),
                    ("Quaternion", 4, false),
                    ("Plane", 4, false),
                    ("AABB", 6, false),
                    ("Transform2D", 6, false),
                    ("Basis", 9, false),
                    ("Transform3D", 12, false),
                    ("Projection", 16, false),
                ];
                let Some((_, size, ints)) = sizes.iter().find(|(name, _, _)| *name == tag) else {
                    return false;
                };
                let Ok(arr) = payload.try_to::<VarArray>() else {
                    return false;
                };
                if arr.len() != *size {
                    return false;
                }
                for component in arr.iter_shared() {
                    if *ints {
                        if !is_integer(&component) {
                            return false;
                        }
                    } else {
                        match component.get_type() {
                            VariantType::INT => {}
                            VariantType::FLOAT => {
                                if !component.to::<f64>().is_finite() {
                                    return false;
                                }
                            }
                            _ => return false,
                        }
                    }
                }
                return true;
            }
            dict.iter_shared().all(|(_, v)| valid_encoded(&v))
        }
        _ => false,
    }
}

pub fn is_integer(value: &Variant) -> bool {
    match value.get_type() {
        VariantType::INT => true,
        VariantType::FLOAT => {
            let f = value.to::<f64>();
            f.is_finite() && f.floor() == f
        }
        _ => false,
    }
}

pub fn to_int(value: &Variant) -> i64 {
    match value.get_type() {
        VariantType::INT => value.to::<i64>(),
        VariantType::FLOAT => value.to::<f64>() as i64,
        VariantType::BOOL => i64::from(value.to::<bool>()),
        VariantType::STRING => value.to::<GString>().to_string().parse().unwrap_or(0),
        _ => 0,
    }
}

pub fn to_float(value: &Variant) -> f64 {
    match value.get_type() {
        VariantType::FLOAT => value.to::<f64>(),
        VariantType::INT => value.to::<i64>() as f64,
        VariantType::BOOL => {
            if value.to::<bool>() {
                1.0
            } else {
                0.0
            }
        }
        VariantType::STRING => value.to::<GString>().to_string().parse().unwrap_or(0.0),
        _ => 0.0,
    }
}

fn join_errors(errors: &VarArray) -> String {
    let mut parts = Vec::new();
    for item in errors.iter_shared() {
        parts.push(item.to::<GString>().to_string());
    }
    parts.join("; ")
}
