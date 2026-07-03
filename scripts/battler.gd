class_name Battler
extends Node3D

signal died(battler)
signal hp_changed(battler)
signal sp_changed(battler)

@export var display_name: String = "Héros"
@export var is_player: bool = true

# --- Stats de base ---
@export var max_hp: int = 200
@export var attack: int = 40
@export var defense: int = 20
@export var magic_attack: int = 35
@export var magic_defense: int = 20
@export var speed: int = 50          # pilote l'ordre des tours
@export var element: String = "none" # "fire", "water", "wind"...

# --- État courant ---
var hp: int
var sp: int = 0
const SP_PER_LEVEL := 100
const MAX_SP := 500
var is_defending: bool = false
var is_dragoon: bool = false
var dragoon_turns_left: int = 0

# --- Contenu (rempli côté configuration) ---
var additions: Array = []      # liste d'AdditionData (voir addition_data.gd)
var dragoon_magic: Array = []  # sorts dispo en mode Dragoon

# --- Animation (placeholders par tween, à remplacer par les anims Meshy) ---
var _home_pos: Vector3
var _home_basis: Basis
var _anim_base: Vector3
var _strike_tween: Tween
var _react_base: Vector3
var _react_tween: Tween
var _meshes: Array[MeshInstance3D] = []
var _flash_mat: StandardMaterial3D

func _ready() -> void:
	hp = max_hp
	for mi in find_children("*", "MeshInstance3D"):
		_meshes.append(mi as MeshInstance3D)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.albedo_color = Color(1, 0.2, 0.2, 0.0)

func is_alive() -> bool:
	return hp > 0

func sp_levels() -> int:
	@warning_ignore("integer_division")
	return sp / SP_PER_LEVEL   # nombre de paliers pleins (division entière voulue)

func gain_sp(amount: int) -> void:
	sp = clampi(sp + amount, 0, MAX_SP)
	sp_changed.emit(self)

func take_damage(amount: int) -> void:
	amount = maxi(1, amount)
	hp = clampi(hp - amount, 0, max_hp)
	hp_changed.emit(self)
	if hp == 0:
		died.emit(self)

func heal(amount: int) -> void:
	hp = clampi(hp + amount, 0, max_hp)
	hp_changed.emit(self)

# --- Animations de combat ---
# Placeholders par tween sur le nœud racine : quand les modèles Meshy seront
# importés, il suffira de déclencher leurs AnimationPlayer au même endroit.

func face_point(p: Vector3) -> void:
	var flat := Vector3(p.x, global_position.y, p.z)
	if global_position.distance_squared_to(flat) > 0.001:
		look_at(flat, Vector3.UP)

## Court jusqu'à portée de mêlée de la cible.
func play_lunge(target: Node3D) -> void:
	_home_pos = global_position
	_home_basis = global_basis
	face_point(target.global_position)
	var dir := (target.global_position - global_position).normalized()
	var stop := target.global_position - dir * 1.25
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "global_position", stop, 0.3)
	await tw.finished
	_anim_base = global_position

## Coup sec vers l'avant (non bloquant, appelé à chaque hit de l'addition).
func play_strike() -> void:
	if _strike_tween and _strike_tween.is_valid():
		_strike_tween.kill()
		global_position = _anim_base
	_anim_base = global_position
	var fwd := -global_basis.z
	_strike_tween = create_tween()
	_strike_tween.tween_property(self, "global_position", _anim_base + fwd * 0.4, 0.06)
	_strike_tween.tween_property(self, "global_position", _anim_base, 0.14)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## Retourne à sa place et reprend son orientation d'origine.
func play_return() -> void:
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "global_position", _home_pos, 0.35)
	await tw.finished
	global_basis = _home_basis

## Flash coloré + recul quand le combattant encaisse (non bloquant).
func play_hit_react(from_dir := Vector3.ZERO) -> void:
	flash(Color(1, 0.25, 0.25, 0.65))
	if _react_tween and _react_tween.is_valid():
		_react_tween.kill()
		global_position = _react_base
	_react_base = global_position
	var push := from_dir
	if push == Vector3.ZERO:
		push = global_basis.z
	push = Vector3(push.x, 0, push.z).normalized() * 0.3
	_react_tween = create_tween()
	_react_tween.tween_property(self, "global_position", _react_base + push, 0.07)
	_react_tween.tween_property(self, "global_position", _react_base, 0.18)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## Teinte brièvement tous les meshes du modèle (marche avec n'importe quel modèle).
func flash(color: Color) -> void:
	_flash_mat.albedo_color = color
	for mi in _meshes:
		mi.material_overlay = _flash_mat
	var tw := create_tween()
	tw.tween_property(_flash_mat, "albedo_color:a", 0.0, 0.25)
	tw.tween_callback(func() -> void:
		for mi in _meshes:
			mi.material_overlay = null)

## Chute puis disparition dans le sol.
func play_death() -> void:
	flash(Color(1, 1, 1, 0.8))
	var model: Node3D = get_node_or_null("Model")
	if model == null:
		visible = false
		return
	var tw := create_tween()
	tw.tween_property(model, "rotation_degrees", Vector3(-80, 0, 0), 0.5)\
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.4)
	tw.tween_property(model, "position:y", -1.6, 0.8)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: visible = false)
	await tw.finished

## Nombre flottant au-dessus du combattant (dégâts ou soin).
func show_damage(amount: int, color := Color(1, 0.95, 0.7)) -> void:
	var lbl := Label3D.new()
	lbl.text = str(amount)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.font_size = 120
	lbl.outline_size = 24
	lbl.pixel_size = 0.006
	lbl.modulate = color
	get_parent().add_child(lbl)
	lbl.global_position = global_position + Vector3.UP * 2.2 \
		+ Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.1, 0.1))
	var tw := lbl.create_tween().set_parallel()
	tw.tween_property(lbl, "global_position:y", lbl.global_position.y + 0.9, 0.7)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.7).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(lbl.queue_free)
