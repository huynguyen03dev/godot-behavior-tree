class_name BTStatus
extends RefCounted
## Standard execution status for Behavior Trees (aligned with Unity Behavior Designer / NodeCanvas).

enum Type {
	INACTIVE = 0,
	FAILURE = 1,
	SUCCESS = 2,
	RUNNING = 3
}

const INACTIVE := Type.INACTIVE
const FAILURE := Type.FAILURE
const SUCCESS := Type.SUCCESS
const RUNNING := Type.RUNNING
