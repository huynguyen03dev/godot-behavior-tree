//! Native runner: tick loop, execution budget, conditional aborts, interrupts.
//!
//! Every method takes `&self` and mutates `RunnerCore` through `RefCell`.
//! GDScript callbacks legitimately re-enter the runner (`owner.stop()`,
//! `runner.interrupt(task)`, a nested `runner.tick()`), so no method may hold a
//! `RunnerCore` borrow while calling into the engine.

use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::rc::Rc;

use godot::classes::Node;
use godot::prelude::*;

use crate::common::*;
use crate::task::{self, dispatch, lifecycle, BTTaskNative};
use crate::tree::BTTreeNative;

pub struct Budget {
    pub max_executions: i64,
    pub executions: i64,
}

pub struct RunnerCore {
    pub is_running: bool,
    pub paused: bool,
    pub ticking: bool,
    pub generation: u64,
    pub ticks: i64,
    pub task_executions: i64,
    pub time: f64,
    pub delta: f64,
    pub last_status: i64,
    pub stopped_at_placeholder: GString,
    pub tick_log: Vec<GString>,
    pub elapsed: f64,
    pub started: HashSet<i64>,
    pub last_status_map: HashMap<i64, i64>,
    pub prepared: HashSet<i64>,
    pub pending_terminal: HashMap<i64, i64>,
    pub activation_interrupts: HashMap<i64, i64>,
    pub budget: Option<Rc<RefCell<Budget>>>,
    pub subtree_stack: Vec<String>,
}

impl Default for RunnerCore {
    fn default() -> Self {
        Self {
            is_running: false,
            paused: false,
            ticking: false,
            generation: 0,
            ticks: 0,
            task_executions: 0,
            time: 0.0,
            delta: 0.0,
            last_status: INACTIVE,
            stopped_at_placeholder: GString::new(),
            tick_log: Vec::new(),
            elapsed: 0.0,
            started: HashSet::new(),
            last_status_map: HashMap::new(),
            prepared: HashSet::new(),
            pending_terminal: HashMap::new(),
            activation_interrupts: HashMap::new(),
            budget: None,
            subtree_stack: Vec::new(),
        }
    }
}

#[derive(GodotClass)]
#[class(init, base = Node)]
pub struct BTRunnerNative {
    base: Base<Node>,
    core: RefCell<RunnerCore>,

    #[var]
    pub update_interval: i64,
    #[var]
    pub update_interval_seconds: f64,
    #[var]
    pub executions_per_tick: i64,
    #[var]
    pub max_task_executions_per_tick: i64,
    #[var]
    pub auto_start: bool,
    #[var]
    pub max_ticks: i64,
    #[var]
    pub debug_log: bool,

    tree_ref: RefCell<Option<Gd<BTTreeNative>>>,
    actor_ref: RefCell<Option<Gd<Node>>>,

    #[var(rename = tree, get = get_bt_tree, set = set_bt_tree)]
    tree: PhantomVar<Variant>,
    #[var(get = get_actor, set = set_actor)]
    actor: PhantomVar<Variant>,
    #[var(get = get_is_running, no_set)]
    is_running: PhantomVar<bool>,
    #[var(get = get_last_status, set = set_last_status_prop)]
    last_status: PhantomVar<i64>,
    #[var(get = get_ticks, no_set)]
    ticks: PhantomVar<i64>,
    #[var(get = get_task_executions, set = set_task_executions)]
    task_executions: PhantomVar<i64>,
    #[var(get = get_time, no_set)]
    time: PhantomVar<f64>,
    #[var(get = get_delta, no_set)]
    delta: PhantomVar<f64>,
    #[var(get = get_tick_log, no_set)]
    tick_log: PhantomVar<VarArray>,
    #[var(get = get_stopped_at_placeholder, no_set)]
    stopped_at_placeholder: PhantomVar<GString>,
    #[var(get = get_subtree_path_stack, set = set_subtree_path_stack)]
    subtree_path_stack: PhantomVar<VarArray>,
}

#[godot_api]
impl BTRunnerNative {
    #[signal]
    pub fn tree_finished(status: i64);
    #[signal]
    pub fn task_started(task: Variant);
    #[signal]
    pub fn task_finished(task: Variant, status: i64);
    #[signal]
    pub fn task_aborted(task: Variant);

    // ------------------------------------------------------------ properties
    #[func]
    pub fn get_bt_tree(&self) -> Variant {
        match &*self.tree_ref.borrow() {
            Some(t) => t.to_variant(),
            None => Variant::nil(),
        }
    }

    #[func]
    pub fn set_bt_tree(&self, value: Variant) {
        let tree = value
            .try_to::<Gd<BTTreeNative>>()
            .ok()
            .filter(|t| is_valid(&t));
        self.set_tree(tree);
    }

    #[func]
    pub fn get_actor(&self) -> Variant {
        match &*self.actor_ref.borrow() {
            Some(a) => a.to_variant(),
            None => Variant::nil(),
        }
    }

    #[func]
    pub fn set_actor(&self, value: Variant) {
        *self.actor_ref.borrow_mut() = value
            .try_to::<Gd<Node>>()
            .ok()
            .filter(|n| is_valid(&n));
    }

    #[func]
    pub fn get_is_running(&self) -> bool {
        self.core.borrow().is_running
    }

    #[func]
    pub fn get_last_status(&self) -> i64 {
        self.core.borrow().last_status
    }

    #[func]
    pub fn set_last_status_prop(&self, value: i64) {
        self.core.borrow_mut().last_status = value;
    }

    #[func]
    pub fn get_ticks(&self) -> i64 {
        self.core.borrow().ticks
    }

    #[func]
    pub fn get_task_executions(&self) -> i64 {
        self.core.borrow().task_executions
    }

    #[func]
    pub fn set_task_executions(&self, value: i64) {
        self.core.borrow_mut().task_executions = value;
    }

    #[func]
    pub fn get_time(&self) -> f64 {
        self.core.borrow().time
    }

    #[func]
    pub fn get_delta(&self) -> f64 {
        self.core.borrow().delta
    }

    #[func]
    pub fn get_tick_log(&self) -> VarArray {
        let mut out = VarArray::new();
        for entry in &self.core.borrow().tick_log {
            out.push(&entry.clone().to_variant());
        }
        out
    }

    #[func]
    pub fn get_stopped_at_placeholder(&self) -> GString {
        self.core.borrow().stopped_at_placeholder.clone()
    }

    #[func]
    pub fn get_subtree_path_stack(&self) -> VarArray {
        let mut out = VarArray::new();
        for entry in &self.core.borrow().subtree_stack {
            out.push(entry.as_str());
        }
        out
    }

    #[func]
    pub fn set_subtree_path_stack(&self, value: VarArray) {
        let mut stack = Vec::new();
        for item in value.iter_shared() {
            stack.push(item.to::<GString>().to_string());
        }
        self.core.borrow_mut().subtree_stack = stack;
    }

    pub fn sim_time(&self) -> f64 {
        self.core.borrow().time
    }

    fn emit(&self, signal: &str, args: &[Variant]) {
        let mut me = self.to_gd();
        me.emit_signal(signal, args);
    }

    pub fn subtree_paths(&self) -> Vec<String> {
        self.core.borrow().subtree_stack.clone()
    }

    pub fn actor(&self) -> Option<Gd<Node>> {
        self.actor_ref.borrow().clone()
    }

    pub fn budget_handle(&self) -> Option<Rc<RefCell<Budget>>> {
        self.core.borrow().budget.clone()
    }

    pub fn share_budget(&self, budget: Option<Rc<RefCell<Budget>>>) {
        self.core.borrow_mut().budget = budget;
    }

    pub fn current_delta(&self) -> f64 {
        self.core.borrow().delta
    }

    pub fn set_delta(&self, delta: f64) {
        self.core.borrow_mut().delta = delta;
    }

    pub fn tree(&self) -> Option<Gd<BTTreeNative>> {
        self.tree_ref.borrow().clone()
    }

    pub fn root_task(&self) -> Option<Gd<BTTaskNative>> {
        let tree = self.tree()?;
        let root = tree.bind().data().root.clone();
        root
    }

    pub fn tree_nodes(&self) -> Vec<Gd<BTTaskNative>> {
        match self.tree() {
            Some(tree) => tree.bind().data().nodes.clone(),
            None => Vec::new(),
        }
    }

    // ------------------------------------------------------------ lifecycle
    #[func]
    pub fn process(&self, delta: f64) {
        if !self.core.borrow().is_running {
            return;
        }
        if self.update_interval != 1 || self.update_interval_seconds <= 0.0 {
            self.tick(delta);
            return;
        }
        let elapsed = {
            let mut core = self.core.borrow_mut();
            core.elapsed += delta;
            core.elapsed
        };
        if elapsed < self.update_interval_seconds {
            return;
        }
        let step = elapsed;
        self.core.borrow_mut().elapsed -= self.update_interval_seconds;
        self.tick(step);
    }

    #[func]
    pub fn ready(&self) {
        if self.auto_start && self.tree().is_some() {
            self.start();
        }
    }

    #[func]
    pub fn set_tree(&self, p_tree: Option<Gd<BTTreeNative>>) {
        self.core.borrow_mut().generation += 1;
        let running = {
            let core = self.core.borrow();
            core.is_running || !core.started.is_empty() || core.paused
        };
        if running {
            self.stop();
        } else if let Some(previous) = self.tree() {
            let me = oid(&self.to_gd());
            for task in previous.bind().data().nodes.clone() {
                if task.bind().data().owner_ref == Some(self.to_gd().instance_id()) {
                    let _ = me;
                    task.bind().data_mut().owner_ref = None;
                }
            }
        }
        *self.tree_ref.borrow_mut() = p_tree;
        self.reset_state();
    }

    pub fn reset_state(&self) {
        let mut core = self.core.borrow_mut();
        core.started.clear();
        core.last_status_map.clear();
        core.prepared.clear();
        core.pending_terminal.clear();
        core.activation_interrupts.clear();
        core.tick_log.clear();
        core.ticks = 0;
        core.task_executions = 0;
        core.last_status = INACTIVE;
        core.stopped_at_placeholder = GString::new();
        core.elapsed = 0.0;
    }

    #[func]
    pub fn start(&self) {
        self.core.borrow_mut().generation += 1;
        let Some(root) = self.root_task() else {
            return;
        };
        let running = {
            let core = self.core.borrow();
            core.is_running || !core.started.is_empty() || core.paused
        };
        if running {
            self.stop();
        }
        self.reset_state();
        self.core.borrow_mut().is_running = true;

        if self.actor_ref.borrow().is_none() {
            let mut me = self.to_gd();
            if let Some(parent) = me.get_parent() {
                *self.actor_ref.borrow_mut() = Some(parent);
            }
        }

        let blackboard = self
            .tree()
            .and_then(|tree| tree.bind().data().blackboard.clone());
        let runner_id = self.to_gd().instance_id();
        for task in self.tree_nodes() {
            let placeholder = task.bind().data().is_placeholder;
            if !placeholder {
                let guard = task.bind();
                let mut d = guard.data_mut();
                d.owner_ref = Some(runner_id);
                d.blackboard_ref = blackboard.clone();
            }
        }

        lifecycle::reset(&root);

        let awake_generation = self.core.borrow().generation;
        let awake_tree = self.tree().map(|t| t.instance_id());
        for task in self.tree_nodes() {
            if task.bind().data().is_placeholder {
                continue;
            }
            lifecycle::awake(&task);
            if self.core.borrow().generation != awake_generation
                || self.tree().map(|t| t.instance_id()) != awake_tree
            {
                return;
            }
        }
    }

    #[func]
    pub fn stop(&self) {
        self.core.borrow_mut().generation += 1;
        {
            let mut core = self.core.borrow_mut();
            core.is_running = false;
            core.paused = false;
        }
        let started: Vec<i64> = {
            let mut core = self.core.borrow_mut();
            let ids = core.started.iter().copied().collect();
            core.started.clear();
            core.prepared.clear();
            core.pending_terminal.clear();
            ids
        };
        for id in started {
            let Ok(task) = Gd::<BTTaskNative>::try_from_instance_id(InstanceId::from_i64(id))
            else {
                continue;
            };
            if task.bind().data().is_placeholder {
                continue;
            }
            lifecycle::end(&task);
            let status = task.bind().data().last_status;
            self.emit(
                "task_finished",
                &[task.to_variant(), status.to_variant()],
            );
        }
        let runner_id = self.to_gd().instance_id();
        for task in self.tree_nodes() {
            if task.bind().data().owner_ref == Some(runner_id) {
                task.bind().data_mut().owner_ref = None;
            }
        }
        self.core.borrow_mut().ticking = false;
    }

    #[func]
    pub fn abort_running(&self) {
        let empty = {
            let core = self.core.borrow();
            !core.is_running && core.started.is_empty()
        };
        if empty {
            return;
        }
        self.core.borrow_mut().generation += 1;
        if let Some(root) = self.root_task() {
            self.abort_task_branch(&root);
        }
        let remaining: Vec<i64> = self.core.borrow().started.iter().copied().collect();
        for id in remaining {
            if let Ok(task) = Gd::<BTTaskNative>::try_from_instance_id(InstanceId::from_i64(id)) {
                self.abort_task_branch(&task);
            }
        }
        {
            let mut core = self.core.borrow_mut();
            core.is_running = false;
            core.paused = false;
            core.prepared.clear();
            core.pending_terminal.clear();
            core.ticking = false;
            core.last_status = FAILURE;
        }
        let runner_id = self.to_gd().instance_id();
        for task in self.tree_nodes() {
            if task.bind().data().owner_ref == Some(runner_id) {
                task.bind().data_mut().owner_ref = None;
            }
        }
    }

    // ------------------------------------------------------------ tick
    #[func]
    pub fn tick(&self, p_delta: f64) -> i64 {
        if self.core.borrow().ticking {
            godot_warn!(
                "BTRunner.tick() was called re-entrantly from inside a running tick; the nested tick is ignored."
            );
            return self.core.borrow().last_status;
        }
        self.core.borrow_mut().ticking = true;
        let status = self.tick_internal(p_delta);
        self.core.borrow_mut().ticking = false;
        status
    }

    pub fn tick_internal(&self, p_delta: f64) -> i64 {
        let Some(root) = self.root_task() else {
            return INACTIVE;
        };
        if !self.core.borrow().is_running {
            return self.core.borrow().last_status;
        }
        let (max_ticks, ticks) = (self.max_ticks, self.core.borrow().ticks);
        if max_ticks > 0 && ticks >= max_ticks {
            self.stop();
            return self.core.borrow().last_status;
        }

        let root_budget = {
            let mut core = self.core.borrow_mut();
            core.delta = p_delta;
            core.time += p_delta;
            core.ticks += 1;
            if core.budget.is_none() {
                core.task_executions = 0;
                if self.max_task_executions_per_tick > 0 {
                    core.budget = Some(Rc::new(RefCell::new(Budget {
                        max_executions: self.max_task_executions_per_tick,
                        executions: 0,
                    })));
                    true
                } else {
                    false
                }
            } else {
                false
            }
        };

        self.core.borrow_mut().prepared.clear();
        let generation = self.core.borrow().generation;
        self.core.borrow_mut().activation_interrupts.clear();

        let mut status = self.run_task(&root, generation);

        if root_budget {
            let executions = self
                .core
                .borrow()
                .budget
                .as_ref()
                .map(|b| b.borrow().executions)
                .unwrap_or(0);
            let mut core = self.core.borrow_mut();
            core.task_executions = executions;
            core.budget = None;
        }

        if generation != self.core.borrow().generation {
            return self.core.borrow().last_status;
        }

        let interrupted = self
            .core
            .borrow()
            .activation_interrupts
            .get(&oid(&root))
            .copied();
        if let Some(interrupt_status) = interrupted {
            if !self.core.borrow().is_running {
                return self.core.borrow().last_status;
            }
            status = interrupt_status;
        }

        self.core.borrow_mut().last_status = status;
        if status != RUNNING {
            self.stop();
            self.emit("tree_finished", &[status.to_variant()]);
        }
        status
    }

    pub fn run_task(&self, task: &Gd<BTTaskNative>, tick_generation: u64) -> i64 {
        if !is_valid(&task) {
            return INACTIVE;
        }
        let tid = oid(task);

        if let Some(pending) = self.core.borrow_mut().pending_terminal.remove(&tid) {
            task.bind().data_mut().last_status = pending;
            self.core.borrow_mut().last_status_map.insert(tid, pending);
            return pending;
        }

        let (kind, is_placeholder) = {
            let guard = task.bind();
            let d = guard.data();
            (d.kind, d.is_placeholder)
        };
        let is_container = kind.is_container();
        let (max_exec, cur_exec) = self.budget_state();
        if max_exec > 0 && cur_exec >= max_exec && !is_container {
            return RUNNING;
        }
        if !is_container {
            self.bump_executions();
        }

        if is_placeholder {
            {
                let mut core = self.core.borrow_mut();
                if core.stopped_at_placeholder.is_empty() {
                    core.stopped_at_placeholder = task.bind().data().type_name.clone();
                }
            }
            let label = self.core.borrow().stopped_at_placeholder.clone();
            self.log_tick(format!("<placeholder:{}>", label));
            return INACTIVE;
        }

        if !self.core.borrow().started.contains(&tid) {
            self.core.borrow_mut().started.insert(tid);
            let activation_generation = self.core.borrow().generation;
            lifecycle::start(task);
            if activation_generation != self.core.borrow().generation
                || !self.core.borrow().started.contains(&tid)
            {
                return self.activation_status(tid, INACTIVE);
            }
            self.emit("task_started", &[task.to_variant()]);
            if activation_generation != self.core.borrow().generation
                || !self.core.borrow().started.contains(&tid)
            {
                return self.activation_status(tid, INACTIVE);
            }
        }

        let label = {
            let guard = task.bind();
            let d = guard.data();
            if d.friendly_name.is_empty() {
                d.type_name.to_string()
            } else {
                d.friendly_name.to_string()
            }
        };
        self.log_tick(label);

        let mut result = INACTIVE;

        if kind.has_children() {
            if !self.core.borrow().prepared.contains(&tid) {
                let hook_generation = self.core.borrow().generation;
                dispatch::on_tick_start(task);
                if hook_generation != self.core.borrow().generation
                    || self.core.borrow().activation_interrupts.contains_key(&tid)
                {
                    return self.activation_status(tid, INACTIVE);
                }
                self.core.borrow_mut().prepared.insert(tid);
            }

            let (abort_type, child_cursor) = {
                let guard = task.bind();
            let d = guard.data();
                (d.abort_type, d.current_child_index)
            };
            if kind.is_composite() && abort_type != ABORT_NONE && child_cursor > 0 {
                let abort_generation = self.core.borrow().generation;
                self.check_conditional_abort(task);
                if abort_generation != self.core.borrow().generation
                    || self.core.borrow().activation_interrupts.contains_key(&tid)
                {
                    return self.activation_status(tid, INACTIVE);
                }
            }

            let mut executed_child = false;
            let mut last_child_index = -1i64;
            loop {
                if !dispatch::can_execute(task) {
                    break;
                }
                let child_idx = dispatch::current_child_index(task);
                if child_idx == last_child_index {
                    break;
                }
                last_child_index = child_idx;
                let mut child_status = INACTIVE;
                let children = task.bind().data().children.clone();
                if child_idx >= 0 && (child_idx as usize) < children.len() {
                    let child_hook_generation = self.core.borrow().generation;
                    dispatch::on_child_started(task, child_idx);
                    if child_hook_generation != self.core.borrow().generation
                        || self.core.borrow().activation_interrupts.contains_key(&tid)
                    {
                        return self.activation_status(tid, INACTIVE);
                    }
                    child_status = self.run_task(&children[child_idx as usize], tick_generation);
                    if self.core.borrow().generation != tick_generation
                        || self.core.borrow().activation_interrupts.contains_key(&tid)
                    {
                        let fallback = self.last_status_of(tid);
                        return self.activation_status(tid, fallback);
                    }
                    let hook_generation = self.core.borrow().generation;
                    dispatch::on_child_executed(task, child_idx, child_status);
                    if hook_generation != self.core.borrow().generation
                        || self.core.borrow().activation_interrupts.contains_key(&tid)
                    {
                        let fallback = self.last_status_of(tid);
                        return self.activation_status(tid, fallback);
                    }
                }
                executed_child = true;
                result = child_status;
                if child_status == RUNNING && !dispatch::can_run_parallel(task) {
                    break;
                }
                let (max_exec, cur_exec) = self.budget_state();
                if max_exec > 0 && cur_exec >= max_exec {
                    break;
                }
            }
            if !executed_child {
                result = self.last_status_of(tid);
            }
        } else {
            let activation_generation = self.core.borrow().generation;
            result = dispatch::on_update(task);
            if activation_generation != self.core.borrow().generation
                || self.core.borrow().activation_interrupts.contains_key(&tid)
            {
                return self.activation_status(tid, INACTIVE);
            }
        }

        if kind.has_children() {
            let decorate_generation = self.core.borrow().generation;
            result = dispatch::decorate(task, result);
            if decorate_generation != self.core.borrow().generation
                || self.core.borrow().activation_interrupts.contains_key(&tid)
            {
                return self.activation_status(tid, INACTIVE);
            }
            result = dispatch::override_status(task, result);
            if decorate_generation != self.core.borrow().generation
                || self.core.borrow().activation_interrupts.contains_key(&tid)
            {
                return self.activation_status(tid, INACTIVE);
            }
        }

        self.core.borrow_mut().last_status_map.insert(tid, result);
        task.bind().data_mut().last_status = result;

        if result != RUNNING {
            self.core.borrow_mut().started.remove(&tid);
            if kind.has_children() {
                for child in task.bind().data().children.clone() {
                    self.abort_task_branch(&child);
                }
            }
            lifecycle::end(task);
            if self.core.borrow().generation != tick_generation {
                return result;
            }
            self.emit("task_finished", &[task.to_variant(), result.to_variant()]);
            if self.core.borrow().generation != tick_generation {
                return result;
            }
        }

        result
    }

    pub fn budget_state(&self) -> (i64, i64) {
        let core = self.core.borrow();
        match &core.budget {
            Some(budget) => {
                let b = budget.borrow();
                (b.max_executions, b.executions)
            }
            None => (self.max_task_executions_per_tick, core.task_executions),
        }
    }

    pub fn bump_executions(&self) {
        let mut core = self.core.borrow_mut();
        if let Some(budget) = core.budget.clone() {
            budget.borrow_mut().executions += 1;
            core.task_executions = budget.borrow().executions;
        } else {
            core.task_executions += 1;
        }
    }

    pub fn last_status_of(&self, tid: i64) -> i64 {
        self.core
            .borrow()
            .last_status_map
            .get(&tid)
            .copied()
            .unwrap_or(INACTIVE)
    }

    pub fn activation_status(&self, tid: i64, fallback: i64) -> i64 {
        self.core
            .borrow()
            .activation_interrupts
            .get(&tid)
            .copied()
            .unwrap_or(fallback)
    }

    pub fn log_tick(&self, entry: String) {
        if !self.debug_log {
            return;
        }
        let mut core = self.core.borrow_mut();
        core.tick_log.push(GString::from(entry.as_str()));
        while core.tick_log.len() > 512 {
            core.tick_log.remove(0);
        }
    }

    // ------------------------------------------------------------ conditional abort
    pub fn check_conditional_abort(&self, composite: &Gd<BTTaskNative>) -> bool {
        let (children, cursor, abort_type, kind) = {
            let __g_d = composite.bind();
        let d = __g_d.data();
            (d.children.clone(), d.current_child_index, d.abort_type, d.kind)
        };
        if children.is_empty() {
            return false;
        }
        if cursor <= 0 || cursor >= children.len() as i64 {
            return false;
        }
        let current_index = self.child_at_execution_order(composite, cursor);

        if kind == task::Kind::Selector
            && (abort_type == ABORT_LOWER_PRIORITY || abort_type == ABORT_BOTH)
        {
            for order_index in 0..cursor {
                let index = self.child_at_execution_order(composite, order_index);
                if index < 0 || (index as usize) >= children.len() {
                    continue;
                }
                let child = children[index as usize].clone();
                if self.reevaluate_branch(&child) == SUCCESS {
                    if current_index >= 0 && (current_index as usize) < children.len() {
                        self.abort_task_branch(&children[current_index as usize]);
                    }
                    let new_cursor = dispatch::execution_order_index(composite, index);
                    let __g_d = composite.bind();
        let mut d = __g_d.data_mut();
                    d.current_child_index = new_cursor;
                    d.execution_status = RUNNING;
                    return true;
                }
            }
        }

        if kind == task::Kind::Sequence && (abort_type == ABORT_SELF || abort_type == ABORT_BOTH) {
            for order_index in 0..cursor {
                let index = self.child_at_execution_order(composite, order_index);
                if index < 0 || (index as usize) >= children.len() {
                    continue;
                }
                let child = children[index as usize].clone();
                if self.reevaluate_branch(&child) == FAILURE {
                    if current_index >= 0 && (current_index as usize) < children.len() {
                        self.abort_task_branch(&children[current_index as usize]);
                    }
                    let __g_d = composite.bind();
        let mut d = __g_d.data_mut();
                    d.execution_status = FAILURE;
                    d.current_child_index = children.len() as i64;
                    return true;
                }
            }
        }

        false
    }

    pub fn reevaluate_branch(&self, task: &Gd<BTTaskNative>) -> i64 {
        if !is_valid(&task) || task.bind().data().is_placeholder {
            return INACTIVE;
        }
        let kind = task.bind().data().kind;
        match kind {
            task::Kind::Sequence | task::Kind::RandomSequence => {
                let children = task.bind().data().children.clone();
                let mut previous = SUCCESS;
                let mut saw_guard = false;
                for order_index in 0..children.len() as i64 {
                    let index = self.child_at_execution_order(task, order_index);
                    if index < 0 || (index as usize) >= children.len() {
                        continue;
                    }
                    let child = children[index as usize].clone();
                    let is_guard = {
                        let __g_d = child.bind();
        let d = __g_d.data();
                        d.category.to_string() == "Condition" || is_condition_wrapper(d.kind)
                    };
                    if !is_guard {
                        return if saw_guard { previous } else { INACTIVE };
                    }
                    let status = self.reevaluate_branch(&child);
                    if status != SUCCESS {
                        return status;
                    }
                    previous = status;
                    saw_guard = true;
                }
                if saw_guard {
                    SUCCESS
                } else {
                    INACTIVE
                }
            }
            task::Kind::Selector | task::Kind::RandomSelector => {
                let children = task.bind().data().children.clone();
                for order_index in 0..children.len() as i64 {
                    let index = self.child_at_execution_order(task, order_index);
                    if index < 0 || (index as usize) >= children.len() {
                        continue;
                    }
                    let status = self.reevaluate_branch(&children[index as usize]);
                    if status == SUCCESS {
                        return SUCCESS;
                    }
                    if status != FAILURE {
                        return status;
                    }
                }
                FAILURE
            }
            task::Kind::Inverter => {
                let children = task.bind().data().children.clone();
                if let Some(child) = children.first() {
                    let status = self.reevaluate_branch(child);
                    return match status {
                        SUCCESS => FAILURE,
                        FAILURE => SUCCESS,
                        _ => status,
                    };
                }
                INACTIVE
            }
            task::Kind::ReturnSuccess | task::Kind::ReturnFailure => {
                let children = task.bind().data().children.clone();
                if let Some(child) = children.first() {
                    let status = self.reevaluate_branch(child);
                    return dispatch::decorate(task, status);
                }
                INACTIVE
            }
            _ => {
                if task.bind().data().category.to_string() == "Condition" {
                    let me = self.to_gd();
                    let node: Gd<Node> = me.upcast();
                    return dispatch::evaluate_condition(task, &node);
                }
                INACTIVE
            }
        }
    }

    pub fn child_at_execution_order(&self, parent: &Gd<BTTaskNative>, order_index: i64) -> i64 {
        let count = parent.bind().data().children.len() as i64;
        for child_index in 0..count {
            if dispatch::execution_order_index(parent, child_index) == order_index {
                return child_index;
            }
        }
        order_index
    }

    pub fn abort_task_branch(&self, task: &Gd<BTTaskNative>) {
        if !is_valid(&task) {
            return;
        }
        let tid = oid(task);
        self.core.borrow_mut().pending_terminal.remove(&tid);
        let kind = task.bind().data().kind;
        if kind.has_children() {
            for child in task.bind().data().children.clone() {
                self.abort_task_branch(&child);
            }
        }
        if self.core.borrow_mut().started.remove(&tid) {
            self.core.borrow_mut().last_status_map.insert(tid, FAILURE);
            task.bind().data_mut().last_status = FAILURE;
            lifecycle::abort(task);
            self.emit("task_aborted", &[task.to_variant()]);
            self.emit("task_finished", &[task.to_variant(), FAILURE.to_variant()]);
        }
    }

    // ------------------------------------------------------------ public API
    #[func]
    pub fn send_event(&self, event_name: GString, data: Variant) {
        for task in self.tree_nodes() {
            if !task.bind().data().is_placeholder {
                lifecycle::event(&task, &event_name, &data);
            }
        }
    }

    #[func]
    pub fn pause(&self, paused: bool) {
        if paused {
            if !self.core.borrow().is_running {
                return;
            }
            self.core.borrow_mut().paused = true;
        } else {
            let blocked = {
                let core = self.core.borrow();
                !core.paused || self.root_task().is_none()
            };
            if blocked {
                return;
            }
            self.core.borrow_mut().paused = false;
        }
        self.core.borrow_mut().is_running = !paused;

        let started: Vec<i64> = self.core.borrow().started.iter().copied().collect();
        for id in started {
            if let Ok(task) = Gd::<BTTaskNative>::try_from_instance_id(InstanceId::from_i64(id)) {
                if !task.bind().data().is_placeholder {
                    lifecycle::pause(&task, paused);
                }
            }
        }
    }

    #[func]
    pub fn interrupt(&self, task: Variant, status: i64) {
        let Ok(task) = task.try_to::<Gd<BTTaskNative>>() else {
            return;
        };
        if !is_valid(&task) || self.tree().is_none() {
            return;
        }
        let tid = oid(&task);
        let root_id = self.root_task().map(|r| oid(&r));
        if root_id != Some(tid) && !self.core.borrow().started.contains(&tid) {
            return;
        }
        self.core
            .borrow_mut()
            .activation_interrupts
            .insert(tid, status);
        self.core.borrow_mut().last_status_map.insert(tid, status);
        task.bind().data_mut().last_status = status;
        self.abort_task_branch(&task);
        if self.core.borrow().activation_interrupts.get(&tid).copied() != Some(status) {
            return;
        }
        if root_id == Some(tid) {
            let mut core = self.core.borrow_mut();
            core.last_status = status;
            core.is_running = false;
            core.paused = false;
            core.pending_terminal.remove(&tid);
            drop(core);
            self.emit("tree_finished", &[status.to_variant()]);
        } else {
            let has_parent = task.bind().data().parent_ref.is_some();
            if has_parent {
                self.core.borrow_mut().pending_terminal.insert(tid, status);
            }
        }
    }
}

fn is_condition_wrapper(kind: task::Kind) -> bool {
    matches!(
        kind,
        task::Kind::Inverter | task::Kind::ReturnSuccess | task::Kind::ReturnFailure
    )
}
