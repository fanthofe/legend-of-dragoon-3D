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

func _ready() -> void:
	hp = max_hp

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
