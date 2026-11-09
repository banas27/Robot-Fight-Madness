extends "res://scripts/combat/riptide_tracked_flank.gd"
## Diagnostic control: candidate attacks with the original escape controller.
func _choose_escape(forward: Vector3, toward: Vector3, radius: Vector2) -> void:
	last_approach_side = lane_side
	_baseline_escape_route(forward, toward, radius)

func _exit_order(delta: float, radius: Vector2, forward: Vector3, toward: Vector3, distance: float) -> Vector2:
	return _recover_order(delta, radius, forward, toward, distance)

func _finish_saw_recovery(_radius: Vector2, separated: bool) -> void:
	# Resume the candidate's own approach on the next tick.
	_enter(Maneuver.LINE_UP, "clear of opponent" if separated else "recovery time limit")
