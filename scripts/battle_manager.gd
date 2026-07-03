extends Node3D

@onready var party_positions := $PartyPositions
@onready var enemy_positions := $EnemyPositions
@onready var camera := $BattleCamera
@onready var ui := $UI

@export var battler_scene: PackedScene  # Battler.tscn

var party: Array[Battler] = []
var enemies: Array[Battler] = []
var all_battlers: Array[Battler] = []

# Jauge d'initiative (ATB simplifié) : clé = battler, valeur = accumulateur
var initiative := {}
const TURN_THRESHOLD := 1000.0

const DRAGOON_COST_LEVELS := 1
const DRAGOON_DURATION := 3
const ITEM_HEAL_AMOUNT := 50

var _fled := false

func _ready() -> void:
	_spawn_battlers()
	_start_battle()

# --- Instanciation ---
func _spawn_battlers() -> void:
	_make_party()
	_make_enemies()

	all_battlers = party + enemies
	for b in all_battlers:
		initiative[b] = randf() * TURN_THRESHOLD * 0.3  # petit décalage de départ
		b.died.connect(_on_battler_died)

	# Chaque camp fait face à l'autre (utile dès que les modèles Meshy arrivent)
	for b in party:
		b.face_point(b.global_position + Vector3.RIGHT)
	for b in enemies:
		b.face_point(b.global_position + Vector3.LEFT)

	ui.setup_party_status(party, enemies)

func _make_battler(battler_name: String, is_player: bool, parent: Node3D) -> Battler:
	var b: Battler = battler_scene.instantiate()
	b.display_name = battler_name
	b.is_player = is_player
	parent.add_child(b)
	return b

func _make_party() -> void:
	var slots := party_positions.get_children()
	var hero := _make_battler("Héros", true, self)
	hero.global_position = slots[0].global_position

	var double := AdditionData.new()
	double.name = "Double Frappe"
	double.hits = 2
	hero.additions = [double]

	party.append(hero)

func _make_enemies() -> void:
	var slots := enemy_positions.get_children()
	var e := _make_battler("Golem", false, self)
	e.max_hp = 400
	e.hp = 400
	e.speed = 35
	e.global_position = slots[0].global_position
	enemies.append(e)

# --- Boucle principale ---
func _start_battle() -> void:
	await ui.show_message("Un ennemi surgit !")
	_battle_loop()

func _battle_loop() -> void:
	while not _battle_is_over():
		var actor := await _get_next_actor()   # avance les jauges d'initiative
		if not actor.is_alive():
			continue

		_tick_dragoon(actor)  # décompte des tours Dragoon
		actor.is_defending = false

		if actor.is_player:
			await _player_turn(actor)
		else:
			await _enemy_turn(actor)

		await get_tree().create_timer(0.25).timeout

	_end_battle()

# Avance les jauges jusqu'à ce qu'un combattant vivant soit "prêt"
func _get_next_actor() -> Battler:
	while true:
		var ready_battler: Battler = null
		for b in all_battlers:
			if not b.is_alive():
				continue
			initiative[b] += b.speed
			if initiative[b] >= TURN_THRESHOLD:
				if ready_battler == null or initiative[b] > initiative[ready_battler]:
					ready_battler = b
		if ready_battler != null:
			initiative[ready_battler] -= TURN_THRESHOLD
			return ready_battler
		await get_tree().process_frame  # évite de bloquer si personne prêt
	return null

func _battle_is_over() -> bool:
	return _fled or _all_dead(party) or _all_dead(enemies)

func _all_dead(group: Array[Battler]) -> bool:
	for b in group:
		if b.is_alive():
			return false
	return true

func _end_battle() -> void:
	if _fled:
		await ui.show_message("Vous avez fui le combat.")
	elif _all_dead(enemies):
		await ui.show_message("Victoire !")
	else:
		await ui.show_message("Défaite...")
	# transition de scène, écran de résultats, XP, etc.

func _on_battler_died(b: Battler) -> void:
	b.play_death()
	await ui.show_message("%s est vaincu !" % b.display_name)

func _tick_dragoon(actor: Battler) -> void:
	if actor.is_dragoon:
		actor.dragoon_turns_left -= 1
		if actor.dragoon_turns_left <= 0:
			actor.is_dragoon = false
			ui.refresh_status(actor)

# --- Tour du joueur ---
func _player_turn(actor: Battler) -> void:
	ui.refresh_status(actor)
	var choice: Dictionary = await ui.request_command(actor, party, enemies)

	match choice.action:
		"attack":
			await _do_attack(actor, choice.target)
		"magic":
			await _do_dragoon_magic(actor, choice)
		"transform":
			await _transform_to_dragoon(actor)
		"defend":
			actor.is_defending = true
			await ui.show_message("%s se met en garde." % actor.display_name)
		"item":
			await _use_item(actor, choice)
		"flee":
			await _try_flee()

# --- Séquence d'attaque cinématique (joueur) ---
func _do_attack(actor: Battler, target: Battler) -> void:
	var addition: AdditionData = actor.additions[0]

	# Plan d'attaque tiré au hasard, puis l'attaquant court au contact
	await camera.play_attack_intro(actor, target)
	await actor.play_lunge(target)

	# Chaque coup réussi du mini-jeu déclenche frappe + réaction + secousse
	var dir := (target.global_position - actor.global_position).normalized()
	var on_hit := func(_i: int) -> void:
		actor.play_strike()
		target.play_hit_react(dir)
		camera.on_hit(0.4)
	ui.addition_overlay.hit_landed.connect(on_hit)
	var hits: int = await ui.addition_overlay.play(addition)
	ui.addition_overlay.hit_landed.disconnect(on_hit)

	await _resolve_addition(actor, target, addition, hits)
	await actor.play_return()
	await _do_camera_reset()

# --- IA ennemie ---
func _enemy_turn(actor: Battler) -> void:
	var targets := party.filter(func(b): return b.is_alive())
	if targets.is_empty():
		return
	var target: Battler = targets[randi() % targets.size()]

	await camera.play_attack_intro(actor, target)
	await actor.play_lunge(target)
	actor.play_strike()
	await get_tree().create_timer(0.07).timeout  # l'impact tombe au bout du coup

	# Cut sur la victime au moment où le coup touche
	camera.cut_to_impact(target, actor)
	camera.on_hit(0.6)
	var dir := (target.global_position - actor.global_position).normalized()
	target.play_hit_react(dir)

	var raw := int(actor.attack * randf_range(0.9, 1.15))
	var dmg := _compute_damage(raw, target)
	target.take_damage(dmg)
	target.show_damage(dmg, Color(1, 0.4, 0.35))
	if not target.is_alive():
		await _slow_motion(0.25, 0.5)
	ui.refresh_status(target)
	await ui.show_message("%s attaque %s : %d dégâts." % [actor.display_name, target.display_name, dmg])
	await actor.play_return()
	await _do_camera_reset()

# --- Dégâts, SP ---
func _resolve_addition(actor: Battler, target: Battler, add: AdditionData, hits: int) -> void:
	if hits == 0:
		await ui.show_message("%s rate son enchaînement !" % actor.display_name)
		return

	# Dégâts = attaque * (dégâts par coup) * nb de coups, moins la défense
	var raw := int(actor.attack * add.damage_per_hit * hits)
	var dmg := _compute_damage(raw, target)
	var perfect := hits == add.hits

	if perfect:
		camera.on_hit(0.9)
		target.flash(Color(1, 0.9, 0.3, 0.7))
	target.take_damage(dmg)
	target.show_damage(dmg)
	if not target.is_alive():
		await _slow_motion(0.25, 0.5)  # coup fatal au ralenti

	# SP gagné proportionnel aux coups réussis (bonus si chaîne complète)
	var sp := add.sp_per_hit * hits
	if perfect:
		sp = int(sp * 1.5)   # bonus "Addition parfaite"
	actor.gain_sp(sp)

	ui.refresh_status(actor)
	ui.refresh_status(target)
	if perfect:
		await ui.show_message("Addition parfaite ! %s inflige %d dégâts !" % [actor.display_name, dmg])
	else:
		await ui.show_message("%s inflige %d dégâts (%d coups) !" % [actor.display_name, dmg, hits])

func _compute_damage(raw: int, target: Battler) -> int:
	var def := target.defense
	if target.is_defending:
		def = int(def * 2.0)   # défense = dégâts réduits ce tour
	return maxi(1, raw - def)

# --- Transformation et magie Dragoon ---
func _transform_to_dragoon(actor: Battler) -> void:
	if actor.sp_levels() < DRAGOON_COST_LEVELS:
		await ui.show_message("SP insuffisant.")
		return
	actor.gain_sp(-DRAGOON_COST_LEVELS * actor.SP_PER_LEVEL)
	actor.is_dragoon = true
	actor.dragoon_turns_left = DRAGOON_DURATION
	# bonus de stats + swap de modèle 3D si tu as une forme Dragoon
	await ui.show_message("%s se transforme en Dragoon !" % actor.display_name)
	ui.refresh_status(actor)

func _do_dragoon_magic(actor: Battler, choice: Dictionary) -> void:
	if not actor.is_dragoon:
		await ui.show_message("Transformation requise.")
		return
	var target: Battler = choice.target

	# La caméra orbite lentement autour du lanceur pendant la charge
	await camera.play_magic_shot(actor)
	actor.flash(Color(0.5, 0.7, 1, 0.5))
	var power: float = await ui.dragoon_charge_minigame()  # renvoie 1.0..2.0 selon les appuis

	var raw := int(actor.magic_attack * 1.6 * power)
	if _element_advantage(actor.element, target.element):
		raw = int(raw * 1.5)
	var dmg := maxi(1, raw - target.magic_defense)

	# Cut sur la cible pour l'explosion du sort
	camera.cut_to_impact(target, actor)
	camera.on_hit(0.9)
	var dir := (target.global_position - actor.global_position).normalized()
	target.play_hit_react(dir)
	target.take_damage(dmg)
	target.show_damage(dmg, Color(0.6, 0.8, 1))
	if not target.is_alive():
		await _slow_motion(0.25, 0.5)
	ui.refresh_status(target)
	await ui.show_message("Magie Dragoon : %d dégâts !" % dmg)
	await _do_camera_reset()

func _element_advantage(atk_el: String, def_el: String) -> bool:
	var chart := {"fire": "wind", "wind": "earth", "earth": "water", "water": "fire"}
	return chart.get(atk_el, "") == def_el

# --- Objet et fuite ---
func _use_item(actor: Battler, choice: Dictionary) -> void:
	var target: Battler = choice.get("target", actor)
	target.heal(ITEM_HEAL_AMOUNT)
	target.flash(Color(0.4, 1, 0.5, 0.5))
	target.show_damage(ITEM_HEAL_AMOUNT, Color(0.5, 1, 0.55))
	ui.refresh_status(target)
	await ui.show_message("%s utilise une Potion sur %s (+%d PV)." % [actor.display_name, target.display_name, ITEM_HEAL_AMOUNT])

func _try_flee() -> void:
	if randf() < 0.5:
		_fled = true
		await ui.show_message("Fuite réussie !")
	else:
		await ui.show_message("Impossible de fuir !")

# --- Caméra cinématique ---
func _do_camera_reset() -> void:
	await camera.reset()

# Ralenti bref (coup fatal). real_duration est en temps réel, hors time_scale.
func _slow_motion(time_scale: float, real_duration: float) -> void:
	Engine.time_scale = time_scale
	await get_tree().create_timer(real_duration, true, false, true).timeout
	Engine.time_scale = 1.0
