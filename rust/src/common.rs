//! Shared primitives for the native behavior-tree runtime.

use godot::prelude::*;

pub const INACTIVE: i64 = 0;
pub const FAILURE: i64 = 1;
pub const SUCCESS: i64 = 2;
pub const RUNNING: i64 = 3;

pub const ABORT_NONE: i64 = 0;
pub const ABORT_SELF: i64 = 1;
pub const ABORT_LOWER_PRIORITY: i64 = 2;
pub const ABORT_BOTH: i64 = 3;

/// Overridable hooks. A node whose GDScript declares one of these methods is
/// routed through GDScript for that hook instead of the native implementation,
/// which preserves subclass extension points (e.g. a RandomSequence subclass
/// overriding `get_current_child_index`).
pub mod hook {
    pub const ON_AWAKE: u32 = 1 << 0;
    pub const ON_RESET: u32 = 1 << 1;
    pub const ON_START: u32 = 1 << 2;
    pub const ON_UPDATE: u32 = 1 << 3;
    pub const EVALUATE_CONDITION: u32 = 1 << 4;
    pub const ON_END: u32 = 1 << 5;
    pub const ON_ABORT: u32 = 1 << 6;
    pub const ON_PAUSE: u32 = 1 << 7;
    pub const ON_EVENT: u32 = 1 << 8;
    pub const CAN_EXECUTE: u32 = 1 << 9;
    pub const ON_TICK_START: u32 = 1 << 10;
    pub const CAN_RUN_PARALLEL: u32 = 1 << 11;
    pub const ON_CHILD_STARTED: u32 = 1 << 12;
    pub const ON_CHILD_EXECUTED: u32 = 1 << 13;
    pub const GET_CURRENT_CHILD_INDEX: u32 = 1 << 14;
    pub const GET_EXECUTION_ORDER_INDEX: u32 = 1 << 15;
    pub const DECORATE: u32 = 1 << 16;
    pub const OVERRIDE_STATUS: u32 = 1 << 17;
    pub const GET_PARAMETER_SCHEMA: u32 = 1 << 18;

    pub const NAMES: &[(&str, u32)] = &[
        ("on_awake", ON_AWAKE),
        ("on_reset", ON_RESET),
        ("on_start", ON_START),
        ("on_update", ON_UPDATE),
        ("evaluate_condition", EVALUATE_CONDITION),
        ("on_end", ON_END),
        ("on_abort", ON_ABORT),
        ("on_pause", ON_PAUSE),
        ("on_event", ON_EVENT),
        ("can_execute", CAN_EXECUTE),
        ("on_tick_start", ON_TICK_START),
        ("can_run_parallel_children", CAN_RUN_PARALLEL),
        ("on_child_started", ON_CHILD_STARTED),
        ("on_child_executed", ON_CHILD_EXECUTED),
        ("get_current_child_index", GET_CURRENT_CHILD_INDEX),
        ("get_execution_order_index", GET_EXECUTION_ORDER_INDEX),
        ("decorate", DECORATE),
        ("override_status", OVERRIDE_STATUS),
        ("get_parameter_schema", GET_PARAMETER_SCHEMA),
    ];
}

/// True when the handle points at a live object (gdext has no `Gd::is_null`).
pub fn is_valid<T: GodotClass>(g: &Gd<T>) -> bool {
    g.instance_id().to_i64() != 0
}

/// Stable handle for a Godot object, usable as a map key.
pub fn oid<T: GodotClass>(obj: &Gd<T>) -> i64 {
    obj.instance_id().to_i64()
}

/// Coerces a Variant to bool with the same rules as `BTTask.coerce_bool`:
/// bool as-is, numbers by non-zero, "true"/"1"/"false"/"0" (trimmed, any case)
/// by literal, everything else falls back.
pub fn coerce_bool(value: &Variant, fallback: bool) -> bool {
    match value.get_type() {
        VariantType::BOOL => value.to::<bool>(),
        VariantType::INT => value.to::<i64>() != 0,
        VariantType::FLOAT => value.to::<f64>() != 0.0,
        VariantType::STRING | VariantType::STRING_NAME => {
            let s = value.to::<GString>().to_string();
            match s.trim().to_lowercase().as_str() {
                "true" | "1" => true,
                "false" | "0" => false,
                _ => fallback,
            }
        }
        _ => fallback,
    }
}
