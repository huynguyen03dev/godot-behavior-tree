class_name BTPerformInterruption
extends BTGhostTaskBase

func on_update() -> int:
	var interrupt_tasks = _get_param_any(["interrupt_tasks", "interruptTasks", "errupt[]interruptTasks"], [12, 21])
	var interrupt_success = bool(_get_param_any(["interrupt_success", "interruptSuccess"], false))
	var target_status = BTStatus.SUCCESS if interrupt_success else BTStatus.FAILURE

	var tree = null
	if owner != null and "tree" in owner:
		tree = owner.tree

	if tree != null and interrupt_tasks is Array:
		for tid in interrupt_tasks:
			var node = tree.get_node_by_id(int(tid))
			if node != null and node.has_method("do_interrupt"):
				node.do_interrupt(target_status)

	return BTStatus.SUCCESS
