//! SubTree task: loads an external tree file and drives it with a nested runner.

use godot::classes::{FileAccess, Json, Node};
use godot::prelude::*;

use crate::blackboard::BTBlackboardNative;
use crate::common::*;
use crate::facade;
use crate::runner::BTRunnerNative;
use crate::task::BTTaskNative;
use crate::tree::{build_tree, validate_tree_data};

fn normalize(path: &str) -> String {
    if path.is_empty() {
        return String::new();
    }
    let with_scheme = if path.starts_with("res://") || path.starts_with("user://") {
        path.to_string()
    } else {
        format!("res://{}", path)
    };
    let with_ext = if with_scheme.ends_with(".json") {
        with_scheme
    } else {
        format!("{}.json", with_scheme)
    };
    let (scheme, rest) = if let Some(r) = with_ext.strip_prefix("res://") {
        ("res://", r)
    } else if let Some(r) = with_ext.strip_prefix("user://") {
        ("user://", r)
    } else {
        ("", with_ext.as_str())
    };
    let mut parts: Vec<&str> = Vec::new();
    for segment in rest.split('/') {
        match segment {
            "" | "." => continue,
            ".." => {
                parts.pop();
            }
            other => parts.push(other),
        }
    }
    format!("{}{}", scheme, parts.join("/"))
}

fn resolved_path(task: &BTTaskNative) -> String {
    let raw = task.param_string("tree_path", &GString::new());
    normalize(&raw.to_string())
}

pub fn ensure_loaded(task: &BTTaskNative) {
    let path = resolved_path(task);
    if path.is_empty() {
        return;
    }
    let (loaded, loading) = {
        let d = task.data();
        (d.sub.loaded_path.clone(), d.sub.loading)
    };
    if loading || path == loaded {
        return;
    }
    load(task, &path);
}

fn load(task: &BTTaskNative, path: &str) {
    task.data_mut().sub.loading = true;
    do_load(task, path);
    task.data_mut().sub.loading = false;
}

fn log_failure(task: &BTTaskNative, message: String) {
    let mut d = task.data_mut();
    if !d.sub.warned {
        d.sub.warned = true;
        drop(d);
        godot_error!("{}", message);
    }
}

fn do_load(task: &BTTaskNative, path: &str) {
    {
        let mut d = task.data_mut();
        if path != d.sub.loaded_path {
            d.sub.warned = false;
        }
        d.sub.loaded_path = path.to_string();
    }

    // Drop the previous subtree runner before rebuilding.
    free_runner(task);

    let owner_id = task.data().owner_ref;
    let parent_runner = owner_id
        .and_then(|id| Gd::<Node>::try_from_instance_id(id).ok())
        .and_then(|node| node.try_cast::<BTRunnerNative>().ok());
    if let Some(parent) = &parent_runner {
        let stack = parent.bind().subtree_paths();
        if stack.iter().any(|p| p == path) {
            log_failure(
                task,
                format!("BTSubTree: recursive subtree detected at '{}'", path),
            );
            return;
        }
    }

    if !FileAccess::file_exists(path) {
        log_failure(
            task,
            format!("BTSubTree: file not found at '{}'", path),
        );
        return;
    }
    let Some(mut file) = FileAccess::open(path, godot::classes::file_access::ModeFlags::READ)
    else {
        log_failure(
            task,
            format!("BTSubTree: cannot open file at '{}'", path),
        );
        return;
    };
    let text = file.get_as_text();
    file.close();

    let parsed = Json::parse_string(&text);
    let Ok(data) = parsed.try_to::<VarDictionary>() else {
        log_failure(
            task,
            format!("BTSubTree: failed to parse JSON in '{}'", path),
        );
        return;
    };

    let registry = parent_runner.as_ref().and_then(|runner| {
        runner
            .bind()
            .tree()
            .and_then(|tree| tree.bind().data().registry.clone())
    });
    let mut errors = VarArray::new();
    validate_tree_data(&data, registry.as_ref(), &mut errors);
    if !errors.is_empty() {
        let mut parts = Vec::new();
        for item in errors.iter_shared() {
            parts.push(item.to::<GString>().to_string());
        }
        log_failure(
            task,
            format!(
                "BTSubTree: invalid subtree at '{}': {}",
                path,
                parts.join("; ")
            ),
        );
        return;
    }

    let Some(sub_tree) = build_tree(&data, registry) else {
        log_failure(
            task,
            format!("BTSubTree: failed to build tree from '{}'", path),
        );
        return;
    };

    // Cache the declared variables so each start re-seeds the scoped blackboard.
    let declared = {
        let blackboard = sub_tree.bind().data().blackboard.clone();
        match blackboard {
            Some(bb) => {
                let mut out = Vec::new();
                for (name, var) in bb.bind().get_all_variables().iter_shared() {
                    if let Ok(var) = var.try_to::<Gd<crate::blackboard::BTTaskVariableNative>>() {
                        let v = var.bind();
                        out.push((
                            name.to::<GString>().to_string(),
                            v.value.clone(),
                            v.type_name.to_string(),
                            v.is_shared,
                            v.description.to_string(),
                        ));
                    }
                }
                out
            }
            None => Vec::new(),
        }
    };

    {
        let mut d = task.data_mut();
        d.sub.tree = Some(sub_tree.clone());
        d.sub.declared = declared;
        d.sub.blackboard = None;
    }

    setup_blackboard(task);

    let Some(mut runner) = facade::new_runner(Some(sub_tree)) else {
        log_failure(task, "BTSubTree: failed to create subtree runner".to_string());
        return;
    };
    if let Some(parent) = &parent_runner {
        let actor = parent.bind().actor();
        if let Some(actor) = actor {
            runner.set("actor", &actor.to_variant());
        }
        let mut stack = parent.bind().subtree_paths();
        stack.push(path.to_string());
        let mut arr = VarArray::new();
        for entry in &stack {
            arr.push(entry.as_str());
        }
        runner.set("subtree_path_stack", &arr.to_variant());
    }
    task.data_mut().sub.runner = Some(runner);
    task.data_mut().sub.warned = false;
}

fn setup_blackboard(task: &BTTaskNative) {
    let (sub_tree, declared, parent_blackboard) = {
        let d = task.data();
        (
            d.sub.tree.clone(),
            d.sub.declared.clone(),
            d.blackboard_ref.clone(),
        )
    };
    let Some(sub_tree) = sub_tree else {
        return;
    };

    let child_scope = facade::new_blackboard().unwrap_or_else(BTBlackboardNative::new_gd);
    {
        let mut scope = child_scope.clone();
        scope.set("parent_scope", &parent_blackboard.to_variant());
    }

    for (name, value, type_name, shared, description) in declared {
        let key = GString::from(name.as_str());
        if shared {
            match &parent_blackboard {
                Some(parent) => {
                    let parent = parent.clone();
                    if !parent.bind().has_var(key.clone()) {
                        parent
                            .bind()
                            .set_var(key.clone(), value, GString::from(type_name.as_str()));
                        if let Some(mut var) = parent.bind().get_variable_obj(key.clone()) {
                            let mut v = var.bind_mut();
                            v.is_shared = true;
                            v.description = GString::from(description.as_str());
                        }
                    }
                }
                None => {
                    child_scope.bind().set_var_local(
                        key.clone(),
                        value,
                        GString::from(type_name.as_str()),
                        true,
                        GString::from(description.as_str()),
                    );
                }
            }
        } else {
            child_scope.bind().set_var_local(
                key,
                value,
                GString::from(type_name.as_str()),
                false,
                GString::from(description.as_str()),
            );
        }
    }

    // Point the subtree and all its nodes at the scoped blackboard.
    sub_tree.bind().set_blackboard(child_scope.to_variant());
    let nodes = sub_tree.bind().data().nodes.clone();
    for node in nodes {
        node.bind().data_mut().blackboard_ref = Some(child_scope.clone());
    }
    task.data_mut().sub.blackboard = Some(child_scope);
}

pub fn start(task: &BTTaskNative) {
    ensure_loaded(task);
    let runner = task.data().sub.runner.clone();
    let Some(runner) = runner else {
        return;
    };
    setup_blackboard(task);
    {
        let mut runner = runner.clone();
        let actor = task
            .data()
            .owner_ref
            .and_then(|id| Gd::<Node>::try_from_instance_id(id).ok())
            .and_then(|node| node.try_cast::<BTRunnerNative>().ok())
            .and_then(|r| r.bind().actor());
        if let Some(actor) = actor {
            runner.set("actor", &actor.to_variant());
        }
        let _ = runner.call("start", &[]);
    }
}

pub fn tick(task: &BTTaskNative) -> i64 {
    let (runner, sub_tree) = {
        let d = task.data();
        (d.sub.runner.clone(), d.sub.tree.clone())
    };
    let (Some(runner), Some(sub_tree)) = (runner, sub_tree) else {
        return FAILURE;
    };
    if sub_tree.bind().data().root.is_none() {
        return FAILURE;
    }
    let Ok(runner_native) = runner.clone().try_cast::<BTRunnerNative>() else {
        return FAILURE;
    };

    let owner_id = task.data().owner_ref;
    let parent_runner = owner_id
        .and_then(|id| Gd::<Node>::try_from_instance_id(id).ok())
        .and_then(|node| node.try_cast::<BTRunnerNative>().ok());

    if let Some(parent) = &parent_runner {
        let budget = parent.bind().budget_handle();
        let delta = parent.bind().current_delta();
        runner_native.bind().share_budget(budget);
        runner_native.bind().set_delta(delta);
    } else {
        runner_native.bind().share_budget(None);
    }

    let delta = runner_native.bind().current_delta();
    let mut runner_node: Gd<Node> = runner_native.clone().upcast();
    let status = runner_node
        .call("tick", &[delta.to_variant()])
        .try_to::<i64>()
        .unwrap_or(FAILURE);

    if let Some(parent) = &parent_runner {
        if let Some(budget) = parent.bind().budget_handle() {
            let executions = budget.borrow().executions;
            parent.bind().set_task_executions(executions);
        }
    }
    status
}

pub fn stop_runner(task: &BTTaskNative) {
    let runner = task.data().sub.runner.clone();
    if let Some(mut runner) = runner {
        let _ = runner.call("stop", &[]);
    }
}

pub fn free_runner(task: &BTTaskNative) {
    let runner = task.data_mut().sub.runner.take();
    if let Some(mut runner) = runner {
        let _ = runner.call("stop", &[]);
        runner.free();
    }
    task.data_mut().sub.tree = None;
}

pub fn abort_runner(task: &BTTaskNative) {
    let runner = task.data().sub.runner.clone();
    if let Some(mut runner) = runner {
        let _ = runner.call("abort_running", &[]);
    }
}
