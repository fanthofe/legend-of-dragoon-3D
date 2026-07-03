extends Control

signal finished(hits_landed: int, addition: AdditionData)
signal hit_landed(hit_index: int)  # émis à chaque coup réussi (pour caméra/anims)

@onready var target_box: Panel = $TargetBox
@onready var incoming_box: Panel = $IncomingBox

const TARGET_SIZE := Vector2(120, 120)
const START_SIZE := Vector2(360, 360)

func _ready() -> void:
	visible = false

# Joue l'addition complète et renvoie le nombre de coups réussis (via await).
func play(addition: AdditionData) -> int:
	visible = true
	var hits_landed := 0
	var duration := addition.base_speed

	target_box.size = TARGET_SIZE
	_center(target_box)

	for i in range(addition.hits):
		var landed := await _play_single_hit(duration, addition.window)
		if not landed:
			break                      # timing raté : la chaîne s'arrête
		hits_landed += 1
		hit_landed.emit(i)
		duration = maxf(0.3, duration - addition.speed_step)  # ça accélère !

	visible = false
	finished.emit(hits_landed, addition)
	return hits_landed

# Un seul coup : la boîte entrante rétrécit ; réussite si "appuyé" dans la fenêtre.
func _play_single_hit(duration: float, window: float) -> bool:
	incoming_box.size = START_SIZE
	_center(incoming_box)

	var t := 0.0
	var in_window := false
	var window_start := duration * (1.0 - window)

	while t < duration:
		var dt := get_process_delta_time()
		t += dt
		var progress := clampf(t / duration, 0.0, 1.0)
		var s: Vector2 = START_SIZE.lerp(TARGET_SIZE, progress)
		incoming_box.size = s
		_center(incoming_box)

		in_window = t >= window_start
		incoming_box.modulate = Color(0.4, 1, 0.4) if in_window else Color(1, 1, 1)

		if Input.is_action_just_pressed("addition_hit"):
			if in_window:
				_flash(Color(0.3, 1, 0.3))
				return true          # réussi
			else:
				_flash(Color(1, 0.3, 0.3))
				return false         # trop tôt : raté
		await get_tree().process_frame

	# temps écoulé sans appui = raté
	_flash(Color(1, 0.3, 0.3))
	return false

func _center(node: Control) -> void:
	node.position = (size - node.size) * 0.5

func _flash(c: Color) -> void:
	incoming_box.modulate = c
	var tw := create_tween()
	tw.tween_property(incoming_box, "modulate", Color(1, 1, 1, 1), 0.15)
