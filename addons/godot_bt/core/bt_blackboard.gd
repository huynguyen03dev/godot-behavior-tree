class_name BTBlackboard
extends RefCounted
## Generic Blackboard for Behavior Trees — stores and shares variables across tasks (Shared Variables).

signal variable_changed(var_name: String, new_val: Variant, old_val: Variant)

class Variable extends RefCounted:
	var name: String = ""
	var type_name: String = "Variant"
	var value: Variant = null
	var is_shared: bool = true
	var description: String = ""

	func _init(p_name: String = "", p_val: Variant = null, p_type: String = "Variant") -> void:
		name = p_name
		value = p_val
		type_name = p_type

var _variables: Dictionary = {} # name -> Variable

func set_var(p_name: String, p_value: Variant, p_type: String = "") -> void:
	var old_val: Variant = null
	if _variables.has(p_name):
		var v: Variable = _variables[p_name]
		old_val = v.value
		v.value = p_value
		if p_type != "":
			v.type_name = p_type
	else:
		var type_str := p_type
		if type_str == "":
			type_str = _type_to_string(typeof(p_value))
		var v := Variable.new(p_name, p_value, type_str)
		_variables[p_name] = v
	variable_changed.emit(p_name, p_value, old_val)

func get_var(p_name: String, default_value: Variant = null) -> Variant:
	if _variables.has(p_name):
		return _variables[p_name].value
	return default_value

func has_var(p_name: String) -> bool:
	return _variables.has(p_name)

func remove_var(p_name: String) -> bool:
	if _variables.has(p_name):
		var old_val = _variables[p_name].value
		_variables.erase(p_name)
		variable_changed.emit(p_name, null, old_val)
		return true
	return false

func get_variable_obj(p_name: String) -> Variable:
	return _variables.get(p_name, null)

func get_all_vars() -> Dictionary:
	var res := {}
	for k in _variables.keys():
		res[k] = _variables[k].value
	return res

func get_all_variables() -> Dictionary:
	return _variables.duplicate()

func clear() -> void:
	_variables.clear()

static func _type_to_string(type_id: int) -> String:
	match type_id:
		TYPE_BOOL: return "bool"
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_STRING: return "String"
		TYPE_VECTOR2: return "Vector2"
		TYPE_VECTOR3: return "Vector3"
		TYPE_ARRAY: return "Array"
		TYPE_DICTIONARY: return "Dictionary"
		TYPE_OBJECT: return "Object"
		_: return "Variant"
