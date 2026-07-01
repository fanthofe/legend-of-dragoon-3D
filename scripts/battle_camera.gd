extends Camera3D

var _home_transform: Transform3D

func _ready() -> void:
	_home_transform = global_transform

# Zoom dramatique sur l'attaquant + sa cible
func zoom_to(attacker: Node3D, target: Node3D) -> void:
	var mid := (attacker.global_position + target.global_position) * 0.5
	var desired := mid + Vector3(2.5, 2.0, 4.0)  # léger angle
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "global_position", desired, 0.4)
	tw.parallel().tween_method(_look_at_point.bind(mid), 0.0, 1.0, 0.4)
	await tw.finished

func reset() -> void:
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "global_transform", _home_transform, 0.4)
	await tw.finished

func _look_at_point(_p, point: Vector3) -> void:
	look_at(point, Vector3.UP)
