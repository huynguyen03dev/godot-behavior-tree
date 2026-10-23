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

var parent_scope: BTBlackboard = null
var _variables: Dictionary = {} # name -> Variable

func set_var_local(p_name: String, p_value: Variant, p_type: String = "", p_is_shared: bool = false, p_description: String = "") -> void:
	var old_val: Variant = null
	if _variables.has(p_name):
		var existing: Variable = _variables[p_name]
		old_val = existing.value
		existing.value = p_value
		if p_type != "":
			existing.type_name = p_type
		existing.is_shared = p_is_shared
		if p_description != "":
			existing.description = p_description
		variable_changed.emit(p_name, p_value, old_val)
		return

	var type_str := p_type
	if type_str == "":
		type_str = _type_to_string(typeof(p_value))
	var v := Variable.new(p_name, p_value, type_str)
	v.is_shared = p_is_shared
	v.description = p_description
	_variables[p_name] = v
	variable_changed.emit(p_name, p_value, old_val)

func set_var(p_name: String, p_value: Variant, p_type: String = "") -> void:
	if _variables.has(p_name):
		var v: Variable = _variables[p_name]
		var old_val: Variant = v.value
		v.value = p_value
		if p_type != "":
			v.type_name = p_type
		variable_changed.emit(p_name, p_value, old_val)
		return

	# If variable exists in ancestor chain and is shared -> write to ancestor
	var ancestor := parent_scope
	while ancestor != null:
		if ancestor._variables.has(p_name):
			var v: Variable = ancestor._variables[p_name]
			if v.is_shared:
				ancestor.set_var(p_name, p_value, p_type)
				return
			break
		ancestor = ancestor.parent_scope

	# Otherwise create locally
	var old_val: Variant = null
	var type_str := p_type
	if type_str == "":
		type_str = _type_to_string(typeof(p_value))
	var v := Variable.new(p_name, p_value, type_str)
	_variables[p_name] = v
	variable_changed.emit(p_name, p_value, old_val)

func get_var(p_name: String, default_value: Variant = null) -> Variant:
	if _variables.has(p_name):
		return _variables[p_name].value
	if parent_scope != null:
		return parent_scope.get_var(p_name, default_value)
	return default_value

func has_var(p_name: String) -> bool:
	if _variables.has(p_name):
		return true
	if parent_scope != null:
		return parent_scope.has_var(p_name)
	return false

func remove_var(p_name: String) -> bool:
	if _variables.has(p_name):
		var old_val = _variables[p_name].value
		_variables.erase(p_name)
		variable_changed.emit(p_name, null, old_val)
		return true
	return false

func get_variable_obj(p_name: String) -> Variable:
	if _variables.has(p_name):
		return _variables[p_name]
	if parent_scope != null:
		return parent_scope.get_variable_obj(p_name)
	return null

func get_all_vars() -> Dictionary:
	var res := {}
	if parent_scope != null:
		res = parent_scope.get_all_vars()
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
