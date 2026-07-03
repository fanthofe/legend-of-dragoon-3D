class_name BattleCamera
extends Camera3D

## Caméra de combat cinématique façon Legend of Dragoon :
## - plans d'attaque variés (épaule, profil, contre-plongée) choisis au hasard
## - lente poussée avant (dolly-in) pendant l'enchaînement
## - cut sec sur la cible au moment de l'impact
## - secousses à l'impact (système de "trauma") + coup de FOV
## - léger flottement "caméra épaule" au repos
##
## La position (cam_pos) et le point regardé (look_target) sont pilotés par
## des tweens ; le transform réel est recomposé chaque frame dans _process
## pour pouvoir superposer proprement le sway et les secousses.

var cam_pos: Vector3
var look_target: Vector3

var _home_pos: Vector3
var _home_look: Vector3
var _home_fov: float

var _idle := true
var _idle_time := 0.0

var _trauma := 0.0
var _noise := FastNoiseLite.new()
var _noise_t := 0.0

var _move_tween: Tween
var _push_tween: Tween
var _fov_tween: Tween

const TRAUMA_DECAY := 2.4        # vitesse d'amortissement des secousses
const SHAKE_MAX_OFFSET := 0.25   # déplacement max (m) à trauma plein
const SHAKE_MAX_ROLL_DEG := 2.5  # roulis max (°) à trauma plein
const EYE := Vector3.UP * 1.2    # hauteur "poitrine" des combattants

func _ready() -> void:
	cam_pos = global_position
	look_target = global_position - global_transform.basis.z * 8.0
	_home_pos = cam_pos
	_home_look = look_target
	_home_fov = fov
	_noise.frequency = 0.9

func _process(delta: float) -> void:
	_noise_t += delta * 60.0
	var pos := cam_pos
	if _idle:
		_idle_time += delta
		pos += Vector3(
			sin(_idle_time * 0.33) * 0.18,
			sin(_idle_time * 0.21) * 0.09,
			cos(_idle_time * 0.27) * 0.12)

	var dir := look_target - pos
	if dir.length_squared() < 0.001 or absf(dir.normalized().dot(Vector3.UP)) > 0.99:
		dir = -global_transform.basis.z
	var xf := Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), pos)

	_trauma = maxf(_trauma - TRAUMA_DECAY * delta, 0.0)
	if _trauma > 0.0:
		var amt := _trauma * _trauma
		var off := Vector3(
			_noise.get_noise_2d(_noise_t, 0.0),
			_noise.get_noise_2d(0.0, _noise_t),
			0.0) * SHAKE_MAX_OFFSET * amt
		xf.origin += xf.basis * off
		var roll := _noise.get_noise_2d(_noise_t, 99.0) * SHAKE_MAX_ROLL_DEG * amt
		xf.basis = xf.basis.rotated(xf.basis.z, deg_to_rad(roll))

	global_transform = xf

# --- Plans d'attaque ---

## Amène la caméra sur un plan d'attaque tiré au hasard, puis lance un
## lent dolly-in qui continue pendant l'addition.
func play_attack_intro(attacker: Node3D, target: Node3D) -> void:
	_idle = false
	var a := attacker.global_position + EYE
	var t := target.global_position + EYE
	var dir := (t - a).normalized()
	var side := dir.cross(Vector3.UP).normalized()
	if randf() < 0.5:
		side = -side  # varie le côté d'un plan à l'autre

	var shot_pos: Vector3
	var shot_look: Vector3
	match randi() % 3:
		0:  # par-dessus l'épaule de l'attaquant, cible en ligne de mire
			shot_pos = a - dir * 2.3 + side * 1.1 + Vector3.UP * 0.8
			shot_look = t
		1:  # profil, les deux combattants dans le cadre
			var mid := (a + t) * 0.5
			shot_pos = mid + side * 3.4 + Vector3.UP * 0.5
			shot_look = mid
		_:  # contre-plongée dramatique entre les deux combattants
			shot_pos = a + dir * 1.6 + side * 1.9 - Vector3.UP * 0.55
			shot_pos.y = maxf(shot_pos.y, 0.35)
			shot_look = (a + t) * 0.5 + Vector3.UP * 0.2

	await _move_to(shot_pos, shot_look, 0.45)
	_start_push_in()

## Cut sec côté cible au moment de l'impact (l'attaquant en arrière-plan).
func cut_to_impact(target: Node3D, attacker: Node3D) -> void:
	_kill_tweens()
	var t := target.global_position + EYE
	var a := attacker.global_position + EYE
	var dir := (t - a).normalized()
	var side := dir.cross(Vector3.UP).normalized() * (1.0 if randf() < 0.5 else -1.0)
	cam_pos = t + dir * 2.6 + side * 1.2 + Vector3.UP * 0.6
	look_target = t
	_start_push_in()

## Plan rapproché qui orbite lentement autour du lanceur pendant la charge.
func play_magic_shot(caster: Node3D) -> void:
	_idle = false
	var c := caster.global_position + EYE
	await _move_to(c + Vector3(2.6, 0.4, 2.6), c, 0.4)
	_kill_push()
	var around := c + (cam_pos - c).rotated(Vector3.UP, TAU * 0.18)
	_push_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_push_tween.tween_property(self, "cam_pos", around, 2.4)

## Impact : secousse + punch de FOV. strength dans [0..1].
func on_hit(strength := 0.5) -> void:
	_trauma = minf(_trauma + 0.35 + strength * 0.45, 1.0)
	if _fov_tween:
		_fov_tween.kill()
	fov = _home_fov - 4.0 - strength * 6.0
	_fov_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_fov_tween.tween_property(self, "fov", _home_fov, 0.35)

## Retour fluide au plan large d'origine.
func reset() -> void:
	await _move_to(_home_pos, _home_look, 0.55)
	_idle = true

# --- Interne ---

func _move_to(pos: Vector3, look: Vector3, duration: float) -> void:
	_kill_tweens()
	_move_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_parallel()
	_move_tween.tween_property(self, "cam_pos", pos, duration)
	_move_tween.tween_property(self, "look_target", look, duration)
	await _move_tween.finished

## Lente poussée vers le point regardé, non bloquante (dolly-in).
func _start_push_in() -> void:
	_kill_push()
	var goal := cam_pos + (look_target - cam_pos) * 0.14
	_push_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_push_tween.tween_property(self, "cam_pos", goal, 3.5)

func _kill_push() -> void:
	if _push_tween:
		_push_tween.kill()

func _kill_tweens() -> void:
	if _move_tween:
		_move_tween.kill()
	_kill_push()
