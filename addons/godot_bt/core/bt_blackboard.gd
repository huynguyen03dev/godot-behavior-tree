class_name BTBlackboard
extends BTBlackboardNative

class Variable extends BTTaskVariableNative:
	func _init(p_name := "", p_val = null, p_type := "Variant") -> void:
		name = p_name
		value = p_val
		type_name = p_type

func set_var_local(p_name: String, p_value, p_type: String = "", p_is_shared: bool = false, p_description: String = "") -> void:
	bt_set_var_local(p_name, p_value, p_type, p_is_shared, p_description)

func set_var(p_name: String, p_value, p_type: String = "") -> void:
	bt_set_var(p_name, p_value, p_type)

func get_var(p_name: String, default_value = null):
	return bt_get_var(p_name, default_value)

func _make_variable(p_name: String, p_value, p_type: String) -> Variable:
	return Variable.new(p_name, p_value, p_type)
