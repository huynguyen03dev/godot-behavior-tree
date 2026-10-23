class_name BTComposite
extends BTParentTask

enum AbortType { NONE = 0, SELF = 1, LOWER_PRIORITY = 2, BOTH = 3 }

class BTSequence extends BTComposite:
	func _init() -> void:
		_setup_kind("Sequence", "Sequence", "Composite")

class BTSelector extends BTComposite:
	func _init() -> void:
		_setup_kind("Selector", "Selector", "Composite")

class BTParallel extends BTComposite:
	func _init() -> void:
		_setup_kind("Parallel", "Parallel", "Composite")

class BTRandomSequence extends BTSequence:
	func _init() -> void:
		_setup_kind("RandomSequence", "Random Sequence", "Composite")

class BTRandomSelector extends BTSelector:
	func _init() -> void:
		_setup_kind("RandomSelector", "Random Selector", "Composite")
