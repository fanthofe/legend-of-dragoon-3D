class_name AdditionData
extends Resource

@export var name: String = "Double Frappe"
@export var hits: int = 2                 # nb de coups dans la séquence
@export var base_speed: float = 1.0       # durée du 1er coup (s)
@export var speed_step: float = 0.12      # accélération par coup réussi
@export var window: float = 0.14          # fenêtre de réussite (part de la durée)
@export var damage_per_hit: float = 0.55  # % de l'attaque par coup
@export var sp_per_hit: int = 25          # SP gagné par coup réussi
