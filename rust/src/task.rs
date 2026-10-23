//! Native behavior-tree node.
//!
//! One class implements every builtin kind (composite, decorator, subtree,
//! leaf) plus the lifecycle contract for GDScript-authored tasks. GDScript
//! facade classes only declare `class_name`/inner classes and set the kind in
//! `_init`, so all execution logic lives here.
//!
//! Every method takes `&self` and mutates through `RefCell`, because GDScript
//! callbacks legitimately re-enter the runtime (`owner.stop()`,
//! `runner.interrupt(self)`, `super.on_start()`). gdext panics on a nested
//! exclusive borrow, so no method may hold an exclusive borrow of itself while
//! calling into the engine.
//!
//! Hooks overridden by a GDScript subclass are detected once (see
//! `detect_overrides`) and dispatched back to GDScript, which preserves the
//! documented extension points (`decorate`, `get_current_child_index`, ...).

use std::cell::{Ref, RefCell, RefMut};
use std::collections::{HashMap, HashSet};

use godot::classes::{Node, Object, RefCounted, Script};
use godot::prelude::*;

use crate::blackboard::BTBlackboardNative;
use crate::common::*;

thread_local! {
    static OVERRIDE_CACHE: RefCell<HashMap<i64, u32>> = RefCell::new(HashMap::new());
}

pub fn clear_override_cache() {
    OVERRIDE_CACHE.with(|c| c.borrow_mut().clear());
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Kind {
    Leaf,
    Parent,
    Decorator,
    Sequence,
    Selector,
    Parallel,
    RandomSequence,
    RandomSelector,
    Inverter,
    ReturnSuccess,
    ReturnFailure,
    Repeater,
    UntilSuccess,
    UntilFailure,
    Cooldown,
    TimeLimit,
    SubTree,
}

impl Kind {
    pub fn from_name(name: &str) -> Kind {
        match name {
            "Sequence" => Kind::Sequence,
            "Selector" => Kind::Selector,
            "Parallel" => Kind::Parallel,
            "RandomSequence" => Kind::RandomSequence,
            "RandomSelector" => Kind::RandomSelector,
            "Inverter" => Kind::Inverter,
            "ReturnSuccess" => Kind::ReturnSuccess,
            "ReturnFailure" => Kind::ReturnFailure,
            "Repeater" => Kind::Repeater,
            "UntilSuccess" => Kind::UntilSuccess,
            "UntilFailure" => Kind::UntilFailure,
            "Cooldown" => Kind::Cooldown,
            "TimeLimit" => Kind::TimeLimit,
            "SubTree" => Kind::SubTree,
            "BTParentTask" => Kind::Parent,
            "BTDecorator" => Kind::Decorator,
            _ => Kind::Leaf,
        }
    }

    pub fn is_random(self) -> bool {
        matches!(self, Kind::RandomSequence | Kind::RandomSelector)
    }

    pub fn is_decorator(self) -> bool {
        matches!(
            self,
            Kind::Decorator
                | Kind::Inverter
                | Kind::ReturnSuccess
                | Kind::ReturnFailure
                | Kind::Repeater
                | Kind::UntilSuccess
                | Kind::UntilFailure
                | Kind::Cooldown
                | Kind::TimeLimit
        )
    }

    pub fn is_composite(self) -> bool {
        matches!(
            self,
            Kind::Sequence
                | Kind::Selector
                | Kind::Parallel
                | Kind::RandomSequence
                | Kind::RandomSelector
        )
    }

    pub fn has_children(self) -> bool {
        self.is_decorator() || self.is_composite() || self == Kind::Parent
    }

    /// Subtree nodes are not charged against the execution budget, matching
    /// the GDScript runtime's `is_container` rule.
    pub fn is_container(self) -> bool {
        self.has_children() || self == Kind::SubTree
    }
}

impl Drop for SubTreeData {
    fn drop(&mut self) {
        if let Some(mut runner) = self.runner.take() {
            let _ = runner.call("stop", &[]);
            if crate::common::is_valid(&runner) {
                runner.free();
            }
        }
    }
}

#[derive(Default)]
pub struct SubTreeData {
    pub tree: Option<Gd<crate::tree::BTTreeNative>>,
    pub runner: Option<Gd<Node>>,
    pub blackboard: Option<Gd<BTBlackboardNative>>,
    pub declared: Vec<(String, Variant, String, bool, String)>,
    pub loaded_path: String,
    pub loading: bool,
    pub warned: bool,
}

pub struct TaskData {
    pub id: i64,
    pub friendly_name: GString,
    pub type_name: GString,
    pub category: GString,
    pub is_placeholder: bool,
    pub parameters: VarDictionary,

    /// Public, live children array (GDScript may append/erase directly).
    pub children_array: VarArray,
    /// Cache mirroring `children_array`, rebuilt when lengths diverge.
    pub children: Vec<Gd<BTTaskNative>>,
    pub parent_ref: Option<InstanceId>,
    pub owner_ref: Option<InstanceId>,
    pub blackboard_ref: Option<Gd<BTBlackboardNative>>,

    pub last_status: i64,
    pub abort_type: i64,
    pub current_child_index: i64,
    pub execution_status: i64,

    pub count: i64,
    pub repeat_forever: bool,
    pub end_on_failure: bool,
    pub cooldown_time: f64,
    pub time_limit: f64,

    pub kind: Kind,
    pub overrides: u32,
    pub overrides_checked: bool,
    pub iteration: i64,
    pub last_execution_time: f64,
    pub start_time: f64,
    pub shuffled_order: Vec<i64>,
    pub children_status: Vec<i64>,
    pub dispatched_this_tick: Vec<bool>,
    pub warned_placeholders: HashSet<i64>,
    pub warned_bindings: HashSet<String>,
    pub sub: SubTreeData,
}

impl Default for TaskData {
    fn default() -> Self {
        Self::fresh()
    }
}

impl TaskData {
    fn fresh() -> Self {
        Self {
            id: -1,
            friendly_name: GString::new(),
            type_name: GString::from("BTTask"),
            category: GString::from("Action"),
            is_placeholder: false,
            parameters: VarDictionary::new(),
            children_array: VarArray::new(),
            children: Vec::new(),
            parent_ref: None,
            owner_ref: None,
            blackboard_ref: None,
            last_status: INACTIVE,
            abort_type: ABORT_NONE,
            current_child_index: 0,
            execution_status: INACTIVE,
            count: 1,
            repeat_forever: false,
            end_on_failure: false,
            cooldown_time: 1.0,
            time_limit: 5.0,
            kind: Kind::Leaf,
            overrides: 0,
            overrides_checked: false,
            iteration: 0,
            last_execution_time: -999999.0,
            start_time: 0.0,
            shuffled_order: Vec::new(),
            children_status: Vec::new(),
            dispatched_this_tick: Vec::new(),
            warned_placeholders: HashSet::new(),
            warned_bindings: HashSet::new(),
            sub: SubTreeData::default(),
        }
    }
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct BTTaskNative {
    base: Base<RefCounted>,
    d: RefCell<TaskData>,

    #[var(get = get_id, set = set_id)]
    id: PhantomVar<i64>,
    #[var(get = get_friendly_name, set = set_friendly_name)]
    friendly_name: PhantomVar<GString>,
    #[var(get = get_type_name, set = set_type_name)]
    type_name: PhantomVar<GString>,
    #[var(get = get_category, set = set_category)]
    category: PhantomVar<GString>,
    #[var(get = get_is_placeholder, set = set_is_placeholder)]
    is_placeholder: PhantomVar<bool>,
    #[var(get = get_parameters, set = set_parameters)]
    parameters: PhantomVar<VarDictionary>,
    #[var(get = get_children, no_set)]
    children: PhantomVar<VarArray>,
    #[var(get = get_parent_task, no_set)]
    parent: PhantomVar<Variant>,
    #[var(get = get_owner_node, set = set_owner_node)]
    owner: PhantomVar<Variant>,
    #[var(get = get_blackboard, set = set_blackboard)]
    blackboard: PhantomVar<Variant>,
    #[var(get = get_last_status, set = set_last_status)]
    last_status: PhantomVar<i64>,
    #[var(get = get_abort_type, set = set_abort_type)]
    abort_type: PhantomVar<i64>,
    #[var(get = get_child_index, set = set_child_index)]
    current_child_index: PhantomVar<i64>,
    #[var(get = get_count, set = set_count)]
    count: PhantomVar<i64>,
    #[var(get = get_repeat_forever, set = set_repeat_forever)]
    repeat_forever: PhantomVar<bool>,
    #[var(get = get_end_on_failure, set = set_end_on_failure)]
    end_on_failure: PhantomVar<bool>,
    #[var(get = get_cooldown_time, set = set_cooldown_time)]
    cooldown_time: PhantomVar<f64>,
    #[var(get = get_time_limit, set = set_time_limit)]
    time_limit: PhantomVar<f64>,
    #[var(get = get_tree_path, set = set_tree_path)]
    tree_path: PhantomVar<GString>,
}

impl BTTaskNative {
    pub fn data(&self) -> Ref<'_, TaskData> {
        self.d.borrow()
    }

    pub fn data_mut(&self) -> RefMut<'_, TaskData> {
        self.d.borrow_mut()
    }
}

#[godot_api]
impl BTTaskNative {
    // ------------------------------------------------------------ properties
    #[func]
    pub fn get_id(&self) -> i64 {
        self.d.borrow().id
    }
    #[func]
    pub fn set_id(&self, value: i64) {
        self.d.borrow_mut().id = value;
    }

    #[func]
    pub fn get_friendly_name(&self) -> GString {
        self.d.borrow().friendly_name.clone()
    }
    #[func]
    pub fn set_friendly_name(&self, value: GString) {
        self.d.borrow_mut().friendly_name = value;
    }

    #[func]
    pub fn get_type_name(&self) -> GString {
        self.d.borrow().type_name.clone()
    }
    #[func]
    pub fn set_type_name(&self, value: GString) {
        self.d.borrow_mut().type_name = value;
    }

    #[func]
    pub fn get_category(&self) -> GString {
        self.d.borrow().category.clone()
    }
    #[func]
    pub fn set_category(&self, value: GString) {
        self.d.borrow_mut().category = value;
    }

    #[func]
    pub fn get_is_placeholder(&self) -> bool {
        self.d.borrow().is_placeholder
    }
    #[func]
    pub fn set_is_placeholder(&self, value: bool) {
        self.d.borrow_mut().is_placeholder = value;
    }

    #[func]
    pub fn get_parameters(&self) -> VarDictionary {
        self.d.borrow().parameters.clone()
    }
    #[func]
    pub fn set_parameters(&self, value: VarDictionary) {
        self.d.borrow_mut().parameters = value;
    }

    #[func]
    pub fn get_children(&self) -> VarArray {
        self.d.borrow().children_array.clone()
    }

    /// Returns the child list, rebuilding the `Gd` cache when user code has
    /// mutated the public `children` array directly.
    pub fn children_snapshot(&self) -> Vec<Gd<BTTaskNative>> {
        let needs_rebuild = {
            let d = self.d.borrow();
            d.children_array.len() != d.children.len()
        };
        if !needs_rebuild {
            return self.d.borrow().children.clone();
        }
        let array = self.d.borrow().children_array.clone();
        let mut rebuilt = Vec::with_capacity(array.len());
        for item in array.iter_shared() {
            if let Ok(task) = item.try_to::<Gd<BTTaskNative>>() {
                rebuilt.push(task);
            }
        }
        self.d.borrow_mut().children = rebuilt.clone();
        rebuilt
    }

    pub fn child_count(&self) -> usize {
        self.d.borrow().children_array.len()
    }

    #[func]
    pub fn get_parent_task(&self) -> Variant {
        match self
            .d
            .borrow()
            .parent_ref
            .and_then(|id| Gd::<BTTaskNative>::try_from_instance_id(id).ok())
        {
            Some(task) => task.to_variant(),
            None => Variant::nil(),
        }
    }

    #[func]
    pub fn get_owner_node(&self) -> Variant {
        match self
            .d
            .borrow()
            .owner_ref
            .and_then(|id| Gd::<Node>::try_from_instance_id(id).ok())
        {
            Some(node) => node.to_variant(),
            None => Variant::nil(),
        }
    }

    #[func]
    pub fn set_owner_node(&self, value: Variant) {
        self.d.borrow_mut().owner_ref = object_id_of(&value);
    }

    #[func]
    pub fn get_blackboard(&self) -> Variant {
        match &self.d.borrow().blackboard_ref {
            Some(bb) => bb.to_variant(),
            None => Variant::nil(),
        }
    }

    #[func]
    pub fn set_blackboard(&self, value: Variant) {
        self.d.borrow_mut().blackboard_ref = value
            .try_to::<Gd<BTBlackboardNative>>()
            .ok()
            .filter(|bb| is_valid(&bb));
    }

    #[func]
    pub fn get_last_status(&self) -> i64 {
        self.d.borrow().last_status
    }
    #[func]
    pub fn set_last_status(&self, value: i64) {
        self.d.borrow_mut().last_status = value;
    }

    #[func]
    pub fn get_abort_type(&self) -> i64 {
        self.d.borrow().abort_type
    }
    #[func]
    pub fn set_abort_type(&self, value: i64) {
        let mut d = self.d.borrow_mut();
        d.abort_type = value;
        d.parameters.set("abort_type", value);
    }

    #[func]
    pub fn get_child_index(&self) -> i64 {
        self.d.borrow().current_child_index
    }
    #[func]
    pub fn set_child_index(&self, value: i64) {
        self.d.borrow_mut().current_child_index = value;
    }

    #[func]
    pub fn get_count(&self) -> i64 {
        self.d.borrow().count
    }
    #[func]
    pub fn set_count(&self, value: i64) {
        self.d.borrow_mut().count = value;
    }

    #[func]
    pub fn get_repeat_forever(&self) -> bool {
        self.d.borrow().repeat_forever
    }
    #[func]
    pub fn set_repeat_forever(&self, value: bool) {
        self.d.borrow_mut().repeat_forever = value;
    }

    #[func]
    pub fn get_end_on_failure(&self) -> bool {
        self.d.borrow().end_on_failure
    }
    #[func]
    pub fn set_end_on_failure(&self, value: bool) {
        self.d.borrow_mut().end_on_failure = value;
    }

    #[func]
    pub fn get_cooldown_time(&self) -> f64 {
        self.d.borrow().cooldown_time
    }
    #[func]
    pub fn set_cooldown_time(&self, value: f64) {
        self.d.borrow_mut().cooldown_time = value;
    }

    #[func]
    pub fn get_time_limit(&self) -> f64 {
        self.d.borrow().time_limit
    }
    #[func]
    pub fn set_time_limit(&self, value: f64) {
        self.d.borrow_mut().time_limit = value;
    }

    #[func]
    pub fn _runner_time(&self) -> f64 {
        runner_time(self.d.borrow().owner_ref)
    }

    #[func]
    pub fn get_tree_path(&self) -> GString {
        self.param_string("tree_path", &GString::new())
    }
    #[func]
    pub fn set_tree_path(&self, value: GString) {
        self.d.borrow_mut().parameters.set("tree_path", &value);
    }

    // ------------------------------------------------------------ kind setup
    /// Called by the GDScript facade classes from `_init`.
    #[func]
    pub fn _setup_kind(&self, kind_name: GString, friendly: GString, category: GString) {
        let mut d = self.d.borrow_mut();
        d.kind = Kind::from_name(&kind_name.to_string());
        d.type_name = kind_name;
        d.friendly_name = if friendly.is_empty() {
            d.type_name.clone()
        } else {
            friendly
        };
        if !category.is_empty() {
            d.category = category;
        }
    }

    /// Native-side kind assignment for placeholder nodes.
    #[func]
    pub fn _make_placeholder(&self, p_type: GString) {
        let mut d = self.d.borrow_mut();
        d.kind = Kind::Leaf;
        d.type_name = p_type.clone();
        d.friendly_name = p_type;
        d.category = GString::from("Unknown");
        d.is_placeholder = true;
    }

    // ------------------------------------------------------------ parameters
    /// GDScript-facing shim: the facade adds default arguments.
    #[func]
    pub fn bt_get_param(&self, name: GString, default_val: Variant) -> Variant {
        self.get_param(name, default_val)
    }

    pub fn get_param(&self, name: GString, default_val: Variant) -> Variant {
        let (raw, blackboard) = {
            let d = self.d.borrow();
            if !d.parameters.contains_key(&name) {
                return default_val;
            }
            (d.parameters.at(&name), d.blackboard_ref.clone())
        };
        resolve_param(self, &name, raw, default_val, blackboard)
    }

    /// GDScript-facing shim: the facade adds default arguments.
    #[func]
    pub fn bt_set_param(&self, name: GString, value: Variant, is_blackboard_key: bool) {
        self.set_param(name, value, is_blackboard_key)
    }

    pub fn set_param(&self, name: GString, value: Variant, is_blackboard_key: bool) {
        let mut d = self.d.borrow_mut();
        if is_blackboard_key {
            let mut entry = VarDictionary::new();
            entry.set("is_blackboard", true);
            entry.set("key", &value.to::<GString>());
            d.parameters.set(&name, &entry);
        } else {
            d.parameters.set(&name, &value);
        }
    }

    #[func]
    pub fn is_param_blackboard(&self, name: GString) -> bool {
        let d = self.d.borrow();
        if !d.parameters.contains_key(&name) {
            return false;
        }
        let raw = d.parameters.at(&name);
        drop(d);
        if let Ok(dict) = raw.try_to::<VarDictionary>() {
            if dict.get("is_blackboard").map(|v| v.to::<bool>()).unwrap_or(false) {
                return true;
            }
        }
        if raw.get_type() == VariantType::STRING {
            let text = raw.to::<GString>().to_string();
            if text.starts_with("@@") || text.starts_with("$$") {
                return false;
            }
            return text.starts_with('@') || text.starts_with('$');
        }
        false
    }

    #[func]
    pub fn get_param_blackboard_key(&self, name: GString) -> GString {
        let d = self.d.borrow();
        if !d.parameters.contains_key(&name) {
            return GString::new();
        }
        let raw = d.parameters.at(&name);
        drop(d);
        if let Ok(dict) = raw.try_to::<VarDictionary>() {
            if dict.get("is_blackboard").map(|v| v.to::<bool>()).unwrap_or(false) {
                return dict.get("key").map(|v| v.to::<GString>()).unwrap_or_default();
            }
        }
        if raw.get_type() == VariantType::STRING {
            let text = raw.to::<GString>().to_string();
            if text.starts_with("@@") || text.starts_with("$$") {
                return GString::new();
            }
            if text.starts_with('@') || text.starts_with('$') {
                return GString::from(&text[1..]);
            }
        }
        GString::new()
    }

    #[func]
    pub fn coerce_bool(value: Variant, fallback: bool) -> bool {
        coerce_bool(&value, fallback)
    }

    /// GDScript-facing shim: the facade adds default arguments.
    #[func]
    pub fn bt_get_blackboard_var(&self, name: GString, default_val: Variant) -> Variant {
        self.get_blackboard_var(name, default_val)
    }

    pub fn get_blackboard_var(&self, name: GString, default_val: Variant) -> Variant {
        let blackboard = self.d.borrow().blackboard_ref.clone();
        match blackboard {
            Some(bb) => bb.bind().get_var(name, default_val),
            None => default_val,
        }
    }

    #[func]
    pub fn set_blackboard_var(&self, name: GString, value: Variant) {
        let blackboard = self.d.borrow().blackboard_ref.clone();
        if let Some(bb) = blackboard {
            bb.bind().set_var(name, value, GString::new());
        }
    }

    /// Typed parameter schema for the editor. Builtin config decorators expose
    /// their fields here; custom tasks may not override this name.
    #[func]
    pub fn get_parameter_schema(&self) -> VarDictionary {
        let d = self.d.borrow();
        let mut out = VarDictionary::new();
        let mut entry = |key: &str, type_name: &str, default: Variant| {
            let mut spec = VarDictionary::new();
            spec.set("type", type_name);
            spec.set("default", &default);
            out.set(key, &spec.to_variant());
        };
        match d.kind {
            Kind::Repeater => {
                entry("count", "int", d.count.to_variant());
                entry("repeat_forever", "bool", d.repeat_forever.to_variant());
                entry("end_on_failure", "bool", d.end_on_failure.to_variant());
            }
            Kind::Cooldown => {
                entry("cooldown_time", "float", d.cooldown_time.to_variant());
            }
            Kind::TimeLimit => {
                entry("time_limit", "float", d.time_limit.to_variant());
            }
            _ => {}
        }
        out
    }

    pub fn param_string(&self, name: &str, fallback: &GString) -> GString {
        if self.d.borrow().parameters.is_empty() {
            return fallback.clone();
        }
        let raw = self.get_param(GString::from(name), fallback.to_variant());
        if raw.get_type() == VariantType::NIL {
            return fallback.clone();
        }
        raw.to::<GString>()
    }

    pub fn param_float(&self, name: &str, fallback: f64) -> f64 {
        if self.d.borrow().parameters.is_empty() {
            return fallback;
        }
        let raw = self.get_param(GString::from(name), fallback.to_variant());
        match raw.get_type() {
            VariantType::NIL => fallback,
            VariantType::INT => raw.to::<i64>() as f64,
            VariantType::FLOAT => raw.to::<f64>(),
            VariantType::STRING => raw.to::<GString>().to_string().parse().unwrap_or(fallback),
            _ => fallback,
        }
    }

    pub fn param_int(&self, name: &str, fallback: i64) -> i64 {
        if self.d.borrow().parameters.is_empty() {
            return fallback;
        }
        let raw = self.get_param(GString::from(name), fallback.to_variant());
        match raw.get_type() {
            VariantType::NIL => fallback,
            VariantType::INT => raw.to::<i64>(),
            VariantType::FLOAT => raw.to::<f64>() as i64,
            VariantType::STRING => raw.to::<GString>().to_string().parse().unwrap_or(fallback),
            _ => fallback,
        }
    }

    pub fn param_bool(&self, name: &str, fallback: bool) -> bool {
        if self.d.borrow().parameters.is_empty() {
            return fallback;
        }
        let raw = self.get_param(GString::from(name), fallback.to_variant());
        coerce_bool(&raw, fallback)
    }

    // ------------------------------------------------------------ children
    #[func]
    pub fn add_child_task(&self, child_task: Variant) {
        let Ok(child) = child_task.try_to::<Gd<BTTaskNative>>() else {
            return;
        };
        if !is_valid(&child) || child.instance_id() == self.to_gd().instance_id() {
            return;
        }
        {
            let d = self.d.borrow();
            if d.children_array
                .iter_shared()
                .any(|c| c.try_to::<Gd<BTTaskNative>>().map(|t| t.instance_id()).ok() == Some(child.instance_id()))
            {
                return;
            }
            if d.kind.is_decorator() && !d.children_array.is_empty() {
                return;
            }
        }
        if self.is_ancestor_or_self(&child) {
            return;
        }
        // Reparent when the child already belongs to another parent.
        let previous = child.bind().data().parent_ref;
        if let Some(prev) = previous {
            if prev != self.to_gd().instance_id() {
                if let Ok(prev_parent) = Gd::<BTTaskNative>::try_from_instance_id(prev) {
                    prev_parent
                        .bind()
                        .remove_child_task(child.to_variant());
                }
            }
        }
        child.bind().data_mut().parent_ref = Some(self.to_gd().instance_id());
        {
            let mut d = self.d.borrow_mut();
            d.children_array.push(&child.to_variant());
            d.children.push(child);
        }
    }

    #[func]
    pub fn remove_child_task(&self, child_task: Variant) {
        let Ok(child) = child_task.try_to::<Gd<BTTaskNative>>() else {
            return;
        };
        let removed = {
            let mut d = self.d.borrow_mut();
            let before = d.children.len();
            d.children
                .retain(|c| c.instance_id() != child.instance_id());
            let mut kept = VarArray::new();
            for item in d.children_array.iter_shared() {
                let same = item
                    .try_to::<Gd<BTTaskNative>>()
                    .map(|t| t.instance_id() == child.instance_id())
                    .unwrap_or(false);
                if !same {
                    kept.push(&item);
                }
            }
            d.children_array = kept;
            d.children.len() != before
        };
        if removed {
            let __g_cd = child.bind();
        let mut cd = __g_cd.data_mut();
            if cd.parent_ref == Some(self.to_gd().instance_id()) {
                cd.parent_ref = None;
            }
        }
    }

    #[func]
    pub fn get_children_count(&self) -> i64 {
        self.children_snapshot().len() as i64
    }

    pub fn is_ancestor_or_self(&self, candidate: &Gd<BTTaskNative>) -> bool {
        let mut cursor = Some(self.to_gd().instance_id());
        while let Some(id) = cursor {
            if id == candidate.instance_id() {
                return true;
            }
            cursor = Gd::<BTTaskNative>::try_from_instance_id(id)
                .ok()
                .and_then(|task| task.bind().data().parent_ref);
        }
        false
    }

    // ------------------------------------------------------------ lifecycle
    #[func]
    pub fn bt_on_awake(&self) {
        if self.d.borrow().kind == Kind::SubTree {
            crate::subtree::ensure_loaded(self);
        }
    }

    #[func]
    pub fn bt_on_reset(&self) {
        let children = {
            let mut d = self.d.borrow_mut();
            d.last_status = INACTIVE;
            if d.kind.has_children() {
                d.current_child_index = 0;
            }
            if d.kind == Kind::Cooldown {
                let time = runner_time(d.owner_ref);
                if d.owner_ref.is_none() || time < d.last_execution_time {
                    d.last_execution_time = -999999.0;
                }
            }
            d.children.clone()
        };
        if self.d.borrow().kind == Kind::SubTree {
            crate::subtree::stop_runner(self);
        }
        for child in children {
            lifecycle::reset(&child);
        }
    }

    #[func]
    pub fn bt_on_start(&self) {
        let kind = self.d.borrow().kind;
        match kind {
            Kind::Sequence | Kind::RandomSequence => {
                let empty = {
                    let mut d = self.d.borrow_mut();
                    d.current_child_index = 0;
                    d.execution_status = RUNNING;
                    if d.kind.is_random() {
                        d.shuffled_order = shuffled(d.children.len());
                    }
                    d.children.is_empty()
                };
                if empty {
                    self.d.borrow_mut().execution_status = SUCCESS;
                }
            }
            Kind::Selector | Kind::RandomSelector => {
                let empty = {
                    let mut d = self.d.borrow_mut();
                    d.current_child_index = 0;
                    d.execution_status = RUNNING;
                    if d.kind.is_random() {
                        d.shuffled_order = shuffled(d.children.len());
                    }
                    d.children.is_empty()
                };
                if empty {
                    self.d.borrow_mut().execution_status = FAILURE;
                }
            }
            Kind::Parallel => {
                let mut d = self.d.borrow_mut();
                d.current_child_index = 0;
                d.execution_status = RUNNING;
                d.children_status = vec![RUNNING; d.children.len()];
                d.dispatched_this_tick = vec![false; d.children.len()];
                if d.children.is_empty() {
                    d.execution_status = SUCCESS;
                }
            }
            Kind::Repeater => {
                let (count, forever, end_on_failure) = {
                    let d = self.d.borrow();
                    (
                        self.param_int("count", d.count),
                        self.param_bool("repeat_forever", d.repeat_forever),
                        self.param_bool("end_on_failure", d.end_on_failure),
                    )
                };
                let mut d = self.d.borrow_mut();
                d.current_child_index = 0;
                d.execution_status = if d.children.is_empty() { INACTIVE } else { RUNNING };
                d.iteration = 0;
                d.count = count;
                d.repeat_forever = forever;
                d.end_on_failure = end_on_failure;
                if d.count <= 0 && !d.repeat_forever {
                    d.execution_status = SUCCESS;
                    d.current_child_index = d.children.len() as i64;
                }
            }
            Kind::Cooldown => {
                let (cooldown, time) = {
                    let d = self.d.borrow();
                    (self.param_float("cooldown_time", d.cooldown_time), runner_time(d.owner_ref))
                };
                let mut d = self.d.borrow_mut();
                d.cooldown_time = cooldown;
                if time - d.last_execution_time < d.cooldown_time {
                    d.execution_status = FAILURE;
                    d.current_child_index = d.children.len() as i64;
                } else {
                    d.current_child_index = 0;
                    d.execution_status = if d.children.is_empty() { INACTIVE } else { RUNNING };
                }
            }
            Kind::TimeLimit => {
                let (limit, time) = {
                    let d = self.d.borrow();
                    (self.param_float("time_limit", d.time_limit), runner_time(d.owner_ref))
                };
                let mut d = self.d.borrow_mut();
                d.time_limit = limit;
                d.start_time = time;
                d.current_child_index = 0;
                d.execution_status = if d.children.is_empty() { INACTIVE } else { RUNNING };
            }
            Kind::SubTree => crate::subtree::start(self),
            _ => {
                if kind.is_decorator() {
                    let mut d = self.d.borrow_mut();
                    d.current_child_index = 0;
                    d.execution_status = if d.children.is_empty() { INACTIVE } else { RUNNING };
                }
            }
        }
    }

    #[func]
    pub fn bt_on_update(&self) -> i64 {
        let (placeholder, kind) = {
            let d = self.d.borrow();
            (d.is_placeholder, d.kind)
        };
        if placeholder {
            return INACTIVE;
        }
        if kind == Kind::SubTree {
            return crate::subtree::tick(self);
        }
        SUCCESS
    }

    #[func]
    pub fn bt_evaluate_condition(&self, runner: Variant) -> i64 {
        let _ = runner;
        let category = self.d.borrow().category.clone();
        if category.to_string() == "Condition" {
            let me = self.to_gd();
            return dispatch::on_update(&me);
        }
        INACTIVE
    }

    #[func]
    pub fn bt_on_end(&self) {
        let kind = self.d.borrow().kind;
        if kind.has_children() {
            self.d.borrow_mut().execution_status = INACTIVE;
        }
        if kind == Kind::SubTree {
            crate::subtree::stop_runner(self);
        }
    }

    #[func]
    pub fn bt_on_abort(&self) {
        if self.d.borrow().kind == Kind::SubTree {
            crate::subtree::abort_runner(self);
        }
        let me = self.to_gd();
        // `on_end` may be overridden, so dispatch instead of calling natively.
        if has_override(&me, hook::ON_END) {
            let mut m = me.clone();
            let _ = m.call("on_end", &[]);
        } else {
            self.bt_on_end();
        }
    }

    #[func]
    pub fn bt_on_pause(&self, paused: bool) {
        let _ = paused;
    }

    #[func]
    pub fn bt_on_event(&self, event_name: GString, data: Variant) {
        let _ = (event_name, data);
    }

    // ------------------------------------------------------------ parent policy
    #[func]
    pub fn bt_can_execute(&self) -> bool {
        let d = self.d.borrow();
        match d.kind {
            Kind::Parallel => {
                if d.execution_status != RUNNING || d.children.is_empty() {
                    return false;
                }
                let len = d.children.len() as i64;
                for offset in 0..len {
                    let index = ((d.current_child_index + offset) % len) as usize;
                    let dispatched = d.dispatched_this_tick.get(index).copied().unwrap_or(false);
                    let status = d.children_status.get(index).copied().unwrap_or(RUNNING);
                    if !dispatched && status == RUNNING {
                        drop(d);
                        self.d.borrow_mut().current_child_index = index as i64;
                        return true;
                    }
                }
                false
            }
            Kind::Repeater => {
                if d.repeat_forever {
                    return d.execution_status == RUNNING;
                }
                d.iteration < d.count && d.execution_status == RUNNING
            }
            Kind::UntilSuccess | Kind::UntilFailure => d.execution_status == RUNNING,
            Kind::Sequence | Kind::Selector | Kind::RandomSequence | Kind::RandomSelector => {
                (d.current_child_index < d.children.len() as i64) && d.execution_status == RUNNING
            }
            Kind::Parent => d.current_child_index < d.children.len() as i64,
            _ => {
                if d.kind.has_children() {
                    (d.current_child_index < d.children.len() as i64)
                        && d.execution_status == RUNNING
                } else {
                    d.current_child_index < d.children.len() as i64
                }
            }
        }
    }

    #[func]
    pub fn bt_on_tick_start(&self) {
        let mut d = self.d.borrow_mut();
        if d.kind == Kind::Parallel {
            d.dispatched_this_tick = vec![false; d.children.len()];
        }
    }

    #[func]
    pub fn bt_can_run_parallel_children(&self) -> bool {
        self.d.borrow().kind == Kind::Parallel
    }

    #[func]
    pub fn bt_on_child_started(&self, child_index: i64) {
        let (kind, child, name) = {
            let mut d = self.d.borrow_mut();
            if d.kind != Kind::Parallel {
                return;
            }
            if child_index >= 0 && (child_index as usize) < d.dispatched_this_tick.len() {
                d.dispatched_this_tick[child_index as usize] = true;
            }
            let child = if child_index >= 0 && (child_index as usize) < d.children.len() {
                Some(d.children[child_index as usize].clone())
            } else {
                None
            };
            (d.kind, child, d.friendly_name.clone())
        };
        let _ = kind;
        if let Some(child) = child {
            let (placeholder, child_type) = {
                let __g_cd = child.bind();
        let cd = __g_cd.data();
                (cd.is_placeholder, cd.type_name.clone())
            };
            if placeholder {
                let child_oid = oid(&child);
                let first = self
                    .d
                    .borrow_mut()
                    .warned_placeholders
                    .insert(child_oid);
                if first {
                    godot_warn!(
                        "BTParallel '{}': child '{}' is an unregistered placeholder and is ignored while other branches run.",
                        name,
                        child_type
                    );
                }
            }
        }
    }

    #[func]
    pub fn bt_current_child_index(&self) -> i64 {
        let me = self.to_gd();
        if has_override(&me, hook::GET_EXECUTION_ORDER_INDEX) {
            let cursor = self.d.borrow().current_child_index;
            let count = self.d.borrow().children.len() as i64;
            for child_index in 0..count {
                if dispatch::execution_order_index(&me, child_index) == cursor {
                    return child_index;
                }
            }
            return cursor;
        }
        let d = self.d.borrow();
        if d.kind.is_random() {
            let idx = d.current_child_index;
            if idx >= 0 && (idx as usize) < d.shuffled_order.len() {
                return d.shuffled_order[idx as usize];
            }
        }
        d.current_child_index
    }

    #[func]
    pub fn bt_execution_order_index(&self, child_index: i64) -> i64 {
        let d = self.d.borrow();
        if d.kind.is_random() {
            return d
                .shuffled_order
                .iter()
                .position(|&i| i == child_index)
                .map(|p| p as i64)
                .unwrap_or(-1);
        }
        child_index
    }

    #[func]
    pub fn bt_on_child_executed(&self, child_index: i64, child_status: i64) {
        let kind = self.d.borrow().kind;
        match kind {
            Kind::Sequence | Kind::RandomSequence => {
                let mut d = self.d.borrow_mut();
                if child_status != RUNNING {
                    d.current_child_index += 1;
                }
                if child_status == FAILURE {
                    d.execution_status = FAILURE;
                } else if child_status == RUNNING {
                    d.execution_status = RUNNING;
                } else if d.current_child_index >= d.children.len() as i64 {
                    d.execution_status = SUCCESS;
                }
            }
            Kind::Selector | Kind::RandomSelector => {
                let mut d = self.d.borrow_mut();
                if child_status != RUNNING {
                    d.current_child_index += 1;
                }
                if child_status == SUCCESS {
                    d.execution_status = SUCCESS;
                } else if child_status == RUNNING {
                    d.execution_status = RUNNING;
                } else if d.current_child_index >= d.children.len() as i64 {
                    d.execution_status = FAILURE;
                }
            }
            Kind::Parallel => {
                let mut d = self.d.borrow_mut();
                if child_index >= 0 && (child_index as usize) < d.children_status.len() {
                    d.children_status[child_index as usize] = child_status;
                }
                if !d.children.is_empty() {
                    d.current_child_index = (child_index + 1) % d.children.len() as i64;
                }
                d.execution_status = aggregate_parallel(&d.children_status);
            }
            Kind::Repeater => {
                let mut d = self.d.borrow_mut();
                if child_status == RUNNING {
                    d.execution_status = RUNNING;
                    return;
                }
                if child_status == INACTIVE {
                    d.execution_status = INACTIVE;
                    return;
                }
                d.iteration += 1;
                if d.end_on_failure && child_status == FAILURE {
                    d.execution_status = FAILURE;
                    return;
                }
                if d.repeat_forever || d.iteration < d.count {
                    d.current_child_index = 0;
                    d.execution_status = RUNNING;
                } else {
                    d.execution_status = child_status;
                }
            }
            Kind::UntilSuccess => {
                let mut d = self.d.borrow_mut();
                if child_status == RUNNING {
                    d.execution_status = RUNNING;
                } else if child_status == INACTIVE {
                    d.execution_status = INACTIVE;
                } else if child_status == SUCCESS {
                    d.execution_status = SUCCESS;
                } else {
                    d.current_child_index = 0;
                    d.execution_status = RUNNING;
                }
            }
            Kind::UntilFailure => {
                let mut d = self.d.borrow_mut();
                if child_status == RUNNING {
                    d.execution_status = RUNNING;
                } else if child_status == INACTIVE {
                    d.execution_status = INACTIVE;
                } else if child_status == FAILURE {
                    d.execution_status = FAILURE;
                } else {
                    d.current_child_index = 0;
                    d.execution_status = RUNNING;
                }
            }
            Kind::Cooldown => {
                let owner = {
                    let mut d = self.d.borrow_mut();
                    if child_status != RUNNING {
                        d.current_child_index += 1;
                    }
                    d.owner_ref
                };
                if child_status != RUNNING {
                    let time = runner_time(owner);
                    let mut d = self.d.borrow_mut();
                    d.last_execution_time = time;
                    d.execution_status = child_status;
                }
            }
            Kind::TimeLimit => {
                let (owner, child) = {
                    let mut d = self.d.borrow_mut();
                    if child_status != RUNNING {
                        d.current_child_index += 1;
                    }
                    let child = if child_index >= 0 && (child_index as usize) < d.children.len() {
                        Some(d.children[child_index as usize].clone())
                    } else {
                        None
                    };
                    (d.owner_ref, child)
                };
                let elapsed = runner_time(owner) - self.d.borrow().start_time;
                if child_status == RUNNING && elapsed >= self.d.borrow().time_limit {
                    if let Some(child) = child {
                        if let Some(owner_id) = owner {
                            if let Ok(owner_node) = Gd::<Node>::try_from_instance_id(owner_id) {
                                let mut o = owner_node;
                                let _ = o.call(
                                    "interrupt",
                                    &[child.to_variant(), FAILURE.to_variant()],
                                );
                            }
                        }
                    }
                    self.d.borrow_mut().execution_status = FAILURE;
                } else {
                    self.d.borrow_mut().execution_status = child_status;
                }
            }
            _ => {
                let mut d = self.d.borrow_mut();
                if child_status != RUNNING {
                    d.current_child_index += 1;
                }
            }
        }
    }

    #[func]
    pub fn bt_decorate(&self, status: i64) -> i64 {
        match self.d.borrow().kind {
            Kind::Inverter => match status {
                SUCCESS => FAILURE,
                FAILURE => SUCCESS,
                _ => status,
            },
            Kind::ReturnSuccess => {
                if status == FAILURE {
                    SUCCESS
                } else {
                    status
                }
            }
            Kind::ReturnFailure => {
                if status == SUCCESS {
                    FAILURE
                } else {
                    status
                }
            }
            _ => status,
        }
    }

    #[func]
    pub fn bt_override_status(&self, status: i64) -> i64 {
        let d = self.d.borrow();
        match d.kind {
            Kind::Sequence
            | Kind::Selector
            | Kind::Parallel
            | Kind::RandomSequence
            | Kind::RandomSelector
            | Kind::Repeater
            | Kind::UntilSuccess
            | Kind::UntilFailure
            | Kind::Cooldown
            | Kind::TimeLimit => d.execution_status,
            _ => status,
        }
    }
}

#[godot_api]
impl godot::classes::IRefCounted for BTTaskNative {
    fn on_get(&self, property: StringName) -> Option<Variant> {
        let p = property.to_string();
        let target = ["_", "sub", "_", "runner"].concat();
        if p == target || p == "sub_runner" {
            match &self.d.borrow().sub.runner {
                Some(runner) => Some(runner.to_variant()),
                None => None,
            }
        } else {
            None
        }
    }
}

// -------------------------------------------------------------------- helpers

fn resolve_param(
    task: &BTTaskNative,
    name: &GString,
    raw: Variant,
    default_val: Variant,
    blackboard: Option<Gd<BTBlackboardNative>>,
) -> Variant {
    let mut binding_key: Option<String> = None;
    if let Ok(dict) = raw.try_to::<VarDictionary>() {
        if dict.get("is_blackboard").map(|v| v.to::<bool>()).unwrap_or(false) {
            binding_key = Some(
                dict.get("key")
                    .map(|v| v.to::<GString>().to_string())
                    .unwrap_or_default(),
            );
        }
    }
    if binding_key.is_none() && raw.get_type() == VariantType::STRING {
        let text = raw.to::<GString>().to_string();
        if text.starts_with("@@") || text.starts_with("$$") {
            return GString::from(&text[1..]).to_variant();
        }
        if let Some(rest) = text.strip_prefix('@').or_else(|| text.strip_prefix('$')) {
            binding_key = Some(rest.to_string());
        }
    }

    let Some(key) = binding_key else {
        return raw;
    };

    if let Some(bb) = blackboard {
        let key_g = GString::from(key.as_str());
        let has = bb.bind().has_var(key_g.clone());
        if has {
            return bb.bind().get_var(key_g, default_val);
        }
    }

    // Warn once per (task, parameter) pair.
    let key_name = name.to_string();
    let first = task.data_mut().warned_bindings.insert(key_name);
    if first {
        let d = task.data();
        let label = if d.friendly_name.is_empty() {
            d.type_name.clone()
        } else {
            d.friendly_name.clone()
        };
        drop(d);
        godot_warn!(
            "BTTask '{}': blackboard binding '@{}' for parameter '{}' not found; using default",
            label,
            key,
            name
        );
    }
    default_val
}

fn shuffled(len: usize) -> Vec<i64> {
    let mut order: Vec<i64> = (0..len as i64).collect();
    if order.len() > 1 {
        for i in (1..order.len()).rev() {
            let j = (godot_rand() % (i as u64 + 1)) as usize;
            order.swap(i, j);
        }
    }
    order
}

fn godot_rand() -> u64 {
    use std::cell::Cell;
    thread_local! {
        static STATE: Cell<u64> = const { Cell::new(0x9E37_79B9_7F4A_7C15) };
    }
    STATE.with(|s| {
        let mut x = s.get();
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        s.set(x);
        x
    })
}

pub fn runner_time(owner: Option<InstanceId>) -> f64 {
    let Some(id) = owner else { return 0.0 };
    let Ok(owner) = Gd::<Node>::try_from_instance_id(id) else {
        return 0.0;
    };
    match owner.try_cast::<crate::runner::BTRunnerNative>() {
        Ok(runner) => runner.bind().sim_time(),
        Err(_) => 0.0,
    }
}

pub fn object_id_of(value: &Variant) -> Option<InstanceId> {
    if value.get_type() != VariantType::OBJECT {
        return None;
    }
    let obj = value.to::<Gd<Object>>();
    if !is_valid(&obj) {
        None
    } else {
        Some(obj.instance_id())
    }
}

/// Child list of a `Gd` handle, refreshed if the public array was mutated.
pub fn children_of(task: &Gd<BTTaskNative>) -> Vec<Gd<BTTaskNative>> {
    task.bind().children_snapshot()
}

pub fn child_count_of(task: &Gd<BTTaskNative>) -> usize {
    task.bind().child_count()
}

pub fn call_int(task: &Gd<BTTaskNative>, method: &str, args: &[Variant]) -> i64 {
    let mut t = task.clone();
    let result = t.call(method, args);
    match result.get_type() {
        VariantType::INT => result.to::<i64>(),
        VariantType::FLOAT => result.to::<f64>() as i64,
        VariantType::BOOL => i64::from(result.to::<bool>()),
        _ => INACTIVE,
    }
}

#[inline]
pub fn has_override(task: &Gd<BTTaskNative>, bit: u32) -> bool {
    let guard = task.bind();
    if !guard.data().overrides_checked {
        drop(guard);
        detect_overrides(task);
        task.bind().data().overrides & bit != 0
    } else {
        guard.data().overrides & bit != 0
    }
}

/// True for scripts that belong to the addon's own GDScript facade layer.
fn is_facade_script(script: &Gd<Script>) -> bool {
    let path = script.get_path().to_string();
    if path.starts_with("res://addons/godot_bt/core/") {
        return true;
    }
    let name = script.get_global_name().to_string();
    matches!(
        name.as_str(),
        "BTTask"
            | "BTParentTask"
            | "BTComposite"
            | "BTDecorator"
            | "BTSubTree"
            | "BTBlackboard"
            | "BTTree"
            | "BTRunner"
            | "BTTaskRegistry"
    )
}

fn method_counts(script: &Gd<Script>) -> std::collections::HashMap<String, usize> {
    let mut out: std::collections::HashMap<String, usize> = std::collections::HashMap::new();
    let mut s = script.clone();
    let value = s.call("get_script_method_list", &[]);
    if let Ok(list) = value.try_to::<Array<VarDictionary>>() {
        for dict in list.iter_shared() {
            if let Some(name) = dict.get("name") {
                *out.entry(name.to::<GString>().to_string()).or_insert(0) += 1;
            }
        }
    }
    out
}

fn base_script(script: &Gd<Script>) -> Option<Gd<Script>> {
    let mut s = script.clone();
    s.call("get_base_script", &[])
        .try_to::<Gd<Script>>()
        .ok()
        .filter(|b| is_valid(b))
}

/// Recomputes which hooks the node's own GDScript declares.
///
/// `get_script_method_list()` lists inherited methods too, and Godot appends a
/// second entry with the same name when a subclass overrides one (verified on
/// 4.7: `[on_update, on_update, helper]`). So a hook is overridden when its
/// entry count exceeds the number of facade definitions in the chain (1 when a
/// facade script is present, 0 for tasks extending the native class directly).
pub fn detect_overrides(task: &Gd<BTTaskNative>) {
    let script = {
        let t = task.clone();
        t.get_script()
    };
    let Some(script) = script.filter(|s| is_valid(s)) else {
        let guard = task.bind();
        let mut d = guard.data_mut();
        d.overrides = 0;
        d.overrides_checked = true;
        return;
    };

    let script_id = script.instance_id().to_i64();
    if let Some(mask) = OVERRIDE_CACHE.with(|c| c.borrow().get(&script_id).copied()) {
        let guard = task.bind();
        let mut d = guard.data_mut();
        d.overrides = mask;
        d.overrides_checked = true;
        return;
    }

    // Walk the chain once: does it cross a facade script?
    let mut has_facade = false;
    let mut cursor = Some(script.clone());
    while let Some(current) = cursor {
        if is_facade_script(&current) {
            has_facade = true;
            break;
        }
        cursor = base_script(&current);
    }
    let baseline: usize = if has_facade { 1 } else { 0 };

    let mut mask = 0u32;
    let counts = method_counts(&script);
    for (name, bit) in hook::NAMES {
        if counts.get(*name).copied().unwrap_or(0) > baseline {
            mask |= bit;
        }
    }

    OVERRIDE_CACHE.with(|c| c.borrow_mut().insert(script_id, mask));

    let guard = task.bind();
    let mut d = guard.data_mut();
    d.overrides = mask;
    d.overrides_checked = true;
}

/// Detects GDScript hook overrides once per node, even for nodes that were
/// attached by mutating `children` directly instead of `add_child_task`.
pub fn ensure_overrides(task: &Gd<BTTaskNative>) {
    if !task.bind().data().overrides_checked {
        detect_overrides(task);
    }
}

fn aggregate_parallel(children_status: &[i64]) -> i64 {
    let mut any_running = false;
    let mut saw_active = false;
    for status in children_status {
        if *status == INACTIVE {
            continue;
        }
        saw_active = true;
        if *status == FAILURE {
            return FAILURE;
        }
        if *status == RUNNING {
            any_running = true;
        }
    }
    if !saw_active {
        return INACTIVE;
    }
    if any_running {
        RUNNING
    } else {
        SUCCESS
    }
}

/// Lifecycle dispatch: a GDScript override wins, otherwise the native behavior.
pub mod lifecycle {
    use super::*;

    pub fn awake(task: &Gd<BTTaskNative>) {
        if has_override(task, hook::ON_AWAKE) {
            let mut t = task.clone();
            let _ = t.call("on_awake", &[]);
        } else {
            task.bind().bt_on_awake();
        }
    }

    pub fn reset(task: &Gd<BTTaskNative>) {
        if has_override(task, hook::ON_RESET) {
            let mut t = task.clone();
            let _ = t.call("on_reset", &[]);
        } else {
            task.bind().bt_on_reset();
        }
    }

    pub fn start(task: &Gd<BTTaskNative>) {
        if has_override(task, hook::ON_START) {
            let mut t = task.clone();
            let _ = t.call("on_start", &[]);
        } else {
            task.bind().bt_on_start();
        }
    }

    pub fn end(task: &Gd<BTTaskNative>) {
        if has_override(task, hook::ON_END) {
            let mut t = task.clone();
            let _ = t.call("on_end", &[]);
        } else {
            task.bind().bt_on_end();
        }
    }

    pub fn abort(task: &Gd<BTTaskNative>) {
        if has_override(task, hook::ON_ABORT) {
            let mut t = task.clone();
            let _ = t.call("on_abort", &[]);
        } else {
            task.bind().bt_on_abort();
        }
    }

    pub fn pause(task: &Gd<BTTaskNative>, paused: bool) {
        if has_override(task, hook::ON_PAUSE) {
            let mut t = task.clone();
            let _ = t.call("on_pause", &[paused.to_variant()]);
        } else {
            task.bind().bt_on_pause(paused);
        }
    }

    pub fn event(task: &Gd<BTTaskNative>, event_name: &GString, data: &Variant) {
        if has_override(task, hook::ON_EVENT) {
            let mut t = task.clone();
            let _ = t.call("on_event", &[event_name.to_variant(), data.clone()]);
        } else {
            task.bind().bt_on_event(event_name.clone(), data.clone());
        }
    }
}

/// Policy dispatch for the runner.
pub mod dispatch {
    use super::*;

    #[inline]
    pub fn on_update(task: &Gd<BTTaskNative>) -> i64 {
        let (overrides, kind) = {
            let guard = task.bind();
            let d = guard.data();
            (d.overrides, d.kind)
        };
        if overrides & hook::ON_UPDATE != 0 {
            return call_int(task, "on_update", &[]);
        }
        if kind == Kind::SubTree {
            return crate::subtree::tick(&task.bind());
        }
        SUCCESS
    }

    pub fn evaluate_condition(task: &Gd<BTTaskNative>, runner: &Gd<Node>) -> i64 {
        if has_override(task, hook::EVALUATE_CONDITION) {
            return call_int(task, "evaluate_condition", &[runner.to_variant()]);
        }
        task.bind().bt_evaluate_condition(runner.to_variant())
    }

    pub fn can_execute(task: &Gd<BTTaskNative>) -> bool {
        if has_override(task, hook::CAN_EXECUTE) {
            let mut t = task.clone();
            return t.call("can_execute", &[]).to::<bool>();
        }
        task.bind().bt_can_execute()
    }

    pub fn on_tick_start(task: &Gd<BTTaskNative>) {
        if has_override(task, hook::ON_TICK_START) {
            let mut t = task.clone();
            let _ = t.call("on_tick_start", &[]);
        } else {
            task.bind().bt_on_tick_start();
        }
    }

    pub fn can_run_parallel(task: &Gd<BTTaskNative>) -> bool {
        if has_override(task, hook::CAN_RUN_PARALLEL) {
            let mut t = task.clone();
            return t.call("can_run_parallel_children", &[]).to::<bool>();
        }
        task.bind().bt_can_run_parallel_children()
    }

    pub fn on_child_started(task: &Gd<BTTaskNative>, index: i64) {
        if has_override(task, hook::ON_CHILD_STARTED) {
            let mut t = task.clone();
            let _ = t.call("on_child_started", &[index.to_variant()]);
        } else {
            task.bind().bt_on_child_started(index);
        }
    }

    pub fn on_child_executed(task: &Gd<BTTaskNative>, index: i64, status: i64) {
        if has_override(task, hook::ON_CHILD_EXECUTED) {
            let mut t = task.clone();
            let _ = t.call("on_child_executed", &[index.to_variant(), status.to_variant()]);
        } else {
            task.bind().bt_on_child_executed(index, status);
        }
    }

    pub fn current_child_index(task: &Gd<BTTaskNative>) -> i64 {
        if has_override(task, hook::GET_CURRENT_CHILD_INDEX) {
            return call_int(task, "get_current_child_index", &[]);
        }
        task.bind().bt_current_child_index()
    }

    pub fn execution_order_index(task: &Gd<BTTaskNative>, child_index: i64) -> i64 {
        if has_override(task, hook::GET_EXECUTION_ORDER_INDEX) {
            return call_int(task, "get_execution_order_index", &[child_index.to_variant()]);
        }
        task.bind().bt_execution_order_index(child_index)
    }

    pub fn decorate(task: &Gd<BTTaskNative>, status: i64) -> i64 {
        if has_override(task, hook::DECORATE) {
            return call_int(task, "decorate", &[status.to_variant()]);
        }
        task.bind().bt_decorate(status)
    }

    pub fn override_status(task: &Gd<BTTaskNative>, status: i64) -> i64 {
        if has_override(task, hook::OVERRIDE_STATUS) {
            return call_int(task, "override_status", &[status.to_variant()]);
        }
        task.bind().bt_override_status(status)
    }
}
