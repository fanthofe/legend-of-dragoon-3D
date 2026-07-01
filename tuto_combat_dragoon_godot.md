# Créer une boucle de combat type *Legend of Dragoon* en 3D dans Godot 4

Tuto détaillé pour reconstruire le système de combat au tour par tour de *Legend of Dragoon* (LoD) — avec son mini-jeu de timing (**Additions**), la jauge de **SP**, et la **transformation Dragoon** — rendu en 3D dans Godot 4.x.

> ⚠️ On recrée des **mécaniques de gameplay** (non protégeables), pas le jeu. Utilise tes propres personnages, noms, sprites, musiques et modèles 3D (par ex. générés via Meshy). Ne copie ni les assets ni les personnages originaux.

---

## Partie 0 — Comprendre le combat de Legend of Dragoon

Pour bien coder, il faut cerner ce qui rend ce combat unique :

1. **Tour par tour, ordre par la vitesse.** Chaque combattant agit à son tour, l'ordre dépend de sa vitesse (on utilisera une jauge d'initiative type ATB simplifiée).
2. **Les Additions** = la signature. Quand un perso attaque, une petite boîte se rétracte vers une boîte cible. Tu dois **appuyer pile au bon moment** : réussi → le coup passe et l'enchaînement continue (de plus en plus rapide), raté → l'enchaînement s'arrête. Plus tu enchaînes de coups, plus tu fais de dégâts et plus tu gagnes de **SP**.
3. **SP (Spirit Points).** Se remplit en réussissant des Additions. Par paliers (disons 100 par niveau, jusqu'à 500).
4. **Transformation Dragoon.** Quand tu as assez de SP, tu peux dépenser un ou plusieurs paliers pour te transformer en Dragoon pendant quelques tours : magie élémentaire puissante + attaques Dragoon (autre mini-jeu de timing).
5. **Commandes classiques** : Attaque (Addition), Magie/Objet Dragoon, Objet, Défense, Fuite.

On construit tout ça autour d'une **machine à états** pilotant la boucle.

---

## Partie 1 — Mise en place du projet

### 1.1 Créer le projet et les actions d'entrée
Nouveau projet Godot 4 (renderer **Forward+** ou **Mobile** selon ta cible — tu es sur RTX 3050 Ti donc Forward+ passe).

Dans **Projet → Paramètres du projet → Contrôles (Input Map)**, ajoute ces actions :

| Action           | Touche(s) suggérées      | Rôle                                  |
|------------------|--------------------------|---------------------------------------|
| `addition_hit`   | Espace, Entrée, manette A | Valider le timing d'une Addition      |
| `menu_up`        | Flèche haut              | Naviguer le menu                      |
| `menu_down`      | Flèche bas               | Naviguer le menu                      |
| `menu_confirm`   | Entrée / A               | Confirmer un choix                    |
| `menu_cancel`    | Échap / B                | Annuler                               |

### 1.2 Arborescence de la scène de combat
Crée une scène `Battle.tscn` (racine `Node3D` nommée `Battle`) :

```
Battle (Node3D)  ── script: battle_manager.gd
├── Arena (Node3D)              # le décor 3D (sol, props…)
├── PartyPositions (Node3D)     # 3 Marker3D : PlayerSlot0/1/2
├── EnemyPositions (Node3D)     # N Marker3D : EnemySlot0/1/…
├── BattleCamera (Camera3D)     # script: battle_camera.gd
├── DirectionalLight3D
├── WorldEnvironment            # sinon la scène est noire (cf. tuto import Meshy)
└── UI (CanvasLayer)            # script: battle_ui.gd
    ├── CommandMenu (Control)
    ├── PartyStatus (Control)   # barres HP / SP
    ├── AdditionOverlay (Control) # script: addition_minigame.gd
    └── MessageLabel (Label)
```

Les `Marker3D` servent d'ancrages : on instancie les combattants dessus. Place la party à gauche, les ennemis à droite, la caméra en léger surplomb qui regarde le centre.

---

## Partie 2 — Le combattant (`Battler`)

C'est la brique de base : données de stats **+** représentation 3D. Fais-en une scène `Battler.tscn` :

```
Battler (Node3D)  ── script: battler.gd
└── Model (Node3D)   # ici tu instancies ton .glb Meshy (ou un placeholder MeshInstance3D)
```

`battler.gd` :

```gdscript
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
var additions: Array = []   # liste d'AdditionData (voir Partie 4)
var dragoon_magic: Array = [] # sorts dispo en mode Dragoon

func _ready() -> void:
	hp = max_hp

func is_alive() -> bool:
	return hp > 0

func sp_levels() -> int:
	return sp / SP_PER_LEVEL   # nombre de paliers pleins

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
```

> **Astuce 3D** : dans `Model`, glisse ton `.glb` importé (ou une scène héritée). Pour un placeholder, un simple `MeshInstance3D` + capsule fait l'affaire le temps de coder la logique.

---

## Partie 3 — La boucle de combat (machine à états)

Le cœur du tuto. On profite des **coroutines `await`** de Godot 4 pour écrire la boucle de façon linéaire et lisible, au lieu d'une énorme `match` fragmentée.

`battle_manager.gd` (sur le nœud racine `Battle`) :

```gdscript
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

func _ready() -> void:
	_spawn_battlers()
	_start_battle()

# --- Instanciation ---
func _spawn_battlers() -> void:
	# Exemple : configure ces données ailleurs (ressources, autoload...).
	# Ici on suppose que party/enemies sont remplis via _make_battler().
	_make_party()
	_make_enemies()

	all_battlers = party + enemies
	for b in all_battlers:
		initiative[b] = randf() * TURN_THRESHOLD * 0.3  # petit décalage de départ
		b.died.connect(_on_battler_died)

func _make_battler(name: String, is_player: bool, parent: Node3D) -> Battler:
	var b: Battler = battler_scene.instantiate()
	b.display_name = name
	b.is_player = is_player
	parent.add_child(b)
	return b

func _make_party() -> void:
	var slots := party_positions.get_children()
	var hero := _make_battler("Héros", true, self)
	hero.global_position = slots[0].global_position
	# hero.additions = [ ... ]  # voir Partie 4
	party.append(hero)
	# ... ajoute d'autres membres sur slots[1], slots[2]

func _make_enemies() -> void:
	var slots := enemy_positions.get_children()
	var e := _make_battler("Golem", false, self)
	e.is_player = false
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

func _battle_is_over() -> bool:
	return _all_dead(party) or _all_dead(enemies)

func _all_dead(group: Array[Battler]) -> bool:
	for b in group:
		if b.is_alive():
			return false
	return true

func _end_battle() -> void:
	if _all_dead(enemies):
		await ui.show_message("Victoire !")
	else:
		await ui.show_message("Défaite...")
	# transition de scène, écran de résultats, XP, etc.

func _on_battler_died(b: Battler) -> void:
	# anim de mort, retrait visuel...
	await ui.show_message("%s est vaincu !" % b.display_name)

func _tick_dragoon(actor: Battler) -> void:
	if actor.is_dragoon:
		actor.dragoon_turns_left -= 1
		if actor.dragoon_turns_left <= 0:
			actor.is_dragoon = false
			ui.refresh_status(actor)
```

Les deux fonctions `_player_turn` et `_enemy_turn` sont détaillées Parties 4 à 6.

---

## Partie 4 — Le mini-jeu d'Additions (le timing)

C'est LA feature LoD. Concept : une **boîte entrante** rétrécit vers une **boîte cible** fixe. Tu appuies quand elles se superposent. Chaque Addition est une **séquence de coups** ; chaque coup réussi rend le suivant un peu plus rapide.

### 4.1 Données d'une Addition
Crée une ressource simple `addition_data.gd` :

```gdscript
class_name AdditionData
extends Resource

@export var name: String = "Double Frappe"
@export var hits: int = 2                 # nb de coups dans la séquence
@export var base_speed: float = 1.0       # durée du 1er coup (s)
@export var speed_step: float = 0.12      # accélération par coup réussi
@export var window: float = 0.14          # fenêtre de réussite (part de la durée)
@export var damage_per_hit: float = 0.55  # % de l'attaque par coup
@export var sp_per_hit: int = 25          # SP gagné par coup réussi
```

Exemple de config (dans `_make_party`) :

```gdscript
var double := AdditionData.new()
double.name = "Double Frappe"; double.hits = 2
hero.additions = [double]
```

### 4.2 L'overlay du mini-jeu
Sur `UI/AdditionOverlay` (un `Control` plein écran, caché par défaut), place :

```
AdditionOverlay (Control)  ── script: addition_minigame.gd
├── TargetBox (Panel)   # boîte cible, taille fixe, au centre
└── IncomingBox (Panel) # boîte entrante, grande au départ
```

`addition_minigame.gd` :

```gdscript
extends Control

signal finished(hits_landed, addition)

@onready var target_box := $TargetBox
@onready var incoming_box := $IncomingBox

var _active := false
var _in_window := false
var _pressed_this_hit := false

const TARGET_SIZE := Vector2(120, 120)
const START_SIZE := Vector2(360, 360)

# Joue l'addition complète et renvoie le nombre de coups réussis (via await).
func play(addition: AdditionData) -> int:
	visible = true
	_active = true
	var hits_landed := 0
	var duration := addition.base_speed

	target_box.size = TARGET_SIZE
	_center(target_box)

	for i in range(addition.hits):
		var landed := await _play_single_hit(duration, addition.window)
		if not landed:
			break                      # timing raté : la chaîne s'arrête
		hits_landed += 1
		duration = maxf(0.3, duration - addition.speed_step)  # ça accélère !

	visible = false
	_active = false
	finished.emit(hits_landed, addition)
	return hits_landed

# Un seul coup : la boîte entrante rétrécit ; réussite si "appuyé" dans la fenêtre.
func _play_single_hit(duration: float, window: float) -> bool:
	_pressed_this_hit = false
	_in_window = false

	incoming_box.size = START_SIZE
	_center(incoming_box)

	var t := 0.0
	var window_start := duration * (1.0 - window)

	while t < duration:
		var dt := get_process_delta_time()
		t += dt
		var progress := clampf(t / duration, 0.0, 1.0)
		# interpolation de la taille : grande -> cible
		var s := START_SIZE.lerp(TARGET_SIZE, progress)
		incoming_box.size = s
		_center(incoming_box)

		_in_window = t >= window_start
		# feedback visuel : la boîte devient verte dans la fenêtre
		incoming_box.modulate = Color(0.4, 1, 0.4) if _in_window else Color(1, 1, 1)

		if Input.is_action_just_pressed("addition_hit"):
			if _in_window:
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
	# petit tween d'impact
	var tw := create_tween()
	tw.tween_property(incoming_box, "modulate", Color(1,1,1,0), 0.15)
```

> **Extension « Counter »** : dans LoD, certaines Additions demandent une seconde pression rapide (contre-timing). Tu peux l'ajouter en insérant, sur un coup donné, une deuxième fenêtre très courte juste après la première. Garde ça pour une v2.

### 4.3 Utiliser l'Addition dans le tour du joueur
Extrait de `_player_turn` (le menu de commandes est Partie 7) :

```gdscript
func _player_turn(actor: Battler) -> void:
	ui.refresh_status(actor)
	var choice = await ui.request_command(actor)  # "attack", "magic", "defend"...

	match choice.action:
		"attack":
			var target: Battler = choice.target
			var addition: AdditionData = actor.additions[0]  # ou choix du joueur
			await _do_camera_zoom(actor, target)
			var hits: int = await ui.addition_overlay.play(addition)
			_resolve_addition(actor, target, addition, hits)
			await _do_camera_reset()
		"magic":
			await _do_dragoon_magic(actor, choice)
		"transform":
			_transform_to_dragoon(actor)
		"defend":
			actor.is_defending = true
		"item":
			await _use_item(actor, choice)
		"flee":
			await _try_flee()
```

---

## Partie 5 — Dégâts, SP et transformation Dragoon

### 5.1 Résolution d'une Addition
```gdscript
func _resolve_addition(actor: Battler, target: Battler, add: AdditionData, hits: int) -> void:
	if hits == 0:
		await ui.show_message("%s rate son enchaînement !" % actor.display_name)
		return

	# Dégâts = attaque * (dégâts par coup) * nb de coups, moins la défense
	var raw := int(actor.attack * add.damage_per_hit * hits)
	var dmg := _compute_damage(raw, target)
	target.take_damage(dmg)

	# SP gagné proportionnel aux coups réussis (bonus si chaîne complète)
	var sp := add.sp_per_hit * hits
	if hits == add.hits:
		sp = int(sp * 1.5)   # bonus "Addition parfaite"
	actor.gain_sp(sp)

	ui.refresh_status(actor)
	await ui.show_message("%s inflige %d dégâts (%d coups) !" % [actor.display_name, dmg, hits])

func _compute_damage(raw: int, target: Battler) -> int:
	var def := target.defense
	if target.is_defending:
		def = int(def * 2.0)   # défense = dégâts réduits ce tour
	return maxi(1, raw - def)
```

> Pense à remettre `is_defending = false` en début du tour suivant du combattant.

### 5.2 Transformation Dragoon
```gdscript
const DRAGOON_COST_LEVELS := 1   # coûte 1 palier de SP
const DRAGOON_DURATION := 3      # tours

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
```

### 5.3 Magie Dragoon (autre mini-jeu de timing)
La magie Dragoon de LoD a son propre timing (appui répété qui « charge » la puissance). Version simple : un compteur d'appuis pendant une fenêtre.

```gdscript
func _do_dragoon_magic(actor: Battler, choice) -> void:
	if not actor.is_dragoon:
		await ui.show_message("Transformation requise.")
		return
	var power := await ui.dragoon_charge_minigame()  # renvoie 1.0..2.0 selon les appuis
	var target: Battler = choice.target
	var raw := int(actor.magic_attack * 1.6 * power)
	# bonus/malus élémentaire
	if _element_advantage(choice.element, target.element):
		raw = int(raw * 1.5)
	var dmg := maxi(1, raw - target.magic_defense)
	target.take_damage(dmg)
	await ui.show_message("Magie Dragoon : %d dégâts !" % dmg)

func _element_advantage(atk_el: String, def_el: String) -> bool:
	var chart := {"fire":"wind", "wind":"earth", "earth":"water", "water":"fire"}
	return chart.get(atk_el, "") == def_el
```

Le `dragoon_charge_minigame()` est un petit `Control` qui compte les `addition_hit` pendant ~2 s et mappe le total sur un multiplicateur.

---

## Partie 6 — IA ennemie

Simple et lisible : l'ennemi cible un membre vivant et attaque (ou lance un sort si HP bas côté joueur, etc.).

```gdscript
func _enemy_turn(actor: Battler) -> void:
	var targets := party.filter(func(b): return b.is_alive())
	if targets.is_empty():
		return
	var target: Battler = targets[randi() % targets.size()]

	await _do_camera_zoom(actor, target)
	# pas de mini-jeu pour l'IA : dégâts directs avec variance
	var raw := int(actor.attack * randf_range(0.9, 1.15))
	var dmg := _compute_damage(raw, target)
	target.take_damage(dmg)
	await ui.show_message("%s attaque %s : %d dégâts." % [actor.display_name, target.display_name, dmg])
	await _do_camera_reset()
```

Pour une IA plus fine : pondère les actions (70 % attaque, 20 % sort de zone, 10 % soin si un allié est bas) via un `randf()` et des seuils.

---

## Partie 7 — L'interface (menu + barres)

`battle_ui.gd` sur `UI (CanvasLayer)`. Il expose des méthodes que le manager `await`.

```gdscript
extends CanvasLayer

@onready var command_menu := $CommandMenu
@onready var message_label := $MessageLabel
@onready var addition_overlay := $AdditionOverlay
@onready var party_status := $PartyStatus

signal command_chosen(result)

func show_message(text: String) -> void:
	message_label.text = text
	message_label.visible = true
	await get_tree().create_timer(1.0).timeout
	message_label.visible = false

# Renvoie un Dictionary { action, target, element } via await
func request_command(actor: Battler):
	command_menu.open(actor)   # affiche Attaque / Magie / Défense / Transform / Objet / Fuite
	var result = await command_chosen
	command_menu.close()
	return result

func refresh_status(actor: Battler = null) -> void:
	# met à jour les barres HP/SP de chaque membre
	party_status.update_all()

func dragoon_charge_minigame() -> float:
	# affiche une jauge, compte les appuis pendant 2s
	var count := 0
	var t := 0.0
	while t < 2.0:
		t += get_process_delta_time()
		if Input.is_action_just_pressed("addition_hit"):
			count += 1
		await get_tree().process_frame
	return clampf(1.0 + count * 0.08, 1.0, 2.0)
```

Le `CommandMenu` : un `VBoxContainer` de boutons. À la sélection d'« Attaque » ou « Magie », tu ouvres un sous-menu de ciblage (surligne l'ennemi visé avec `menu_up/down`), puis tu émets `command_chosen` avec `{ "action": "attack", "target": enemy }`.

Pour les **barres HP/SP** : dans `PartyStatus`, un `ProgressBar` par membre. Connecte-toi aux signaux du battler :

```gdscript
battler.hp_changed.connect(func(b): hp_bar.value = float(b.hp) / b.max_hp * 100.0)
battler.sp_changed.connect(func(b): sp_bar.value = float(b.sp) / b.MAX_SP * 100.0)
```

---

## Partie 8 — Rendre ça « 3D » et cinématique

LoD utilisait des décors et une caméra dynamique qui swoope pendant les attaques. En 3D pur, on recrée ce punch avec des mouvements de caméra tweenés.

`battle_camera.gd` :

```gdscript
extends Camera3D

var _home_transform: Transform3D

func _ready() -> void:
	_home_transform = global_transform

# Zoom dramatique sur l'attaquant + sa cible
func zoom_to(attacker: Node3D, target: Node3D) -> void:
	var mid := (attacker.global_position + target.global_position) * 0.5
	var desired := global_position
	desired = mid + Vector3(2.5, 2.0, 4.0)  # léger angle
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
```

Et dans le manager, les helpers utilisés plus haut :

```gdscript
func _do_camera_zoom(attacker: Battler, target: Battler) -> void:
	await camera.zoom_to(attacker, target)

func _do_camera_reset() -> void:
	await camera.reset()
```

Pour les **animations d'attaque** : si ton `.glb` Meshy est riggé/animé, joue l'anim via l'`AnimationPlayer` importé, synchronisée avec chaque coup réussi de l'Addition (connecte le signal `finished` ou déclenche l'anim dans la boucle `_play_single_hit`). Sinon, un simple tween d'avancée/recul (`tween_property(model, "position", ...)`) donne déjà un bon feeling « je fonce, je frappe, je reviens ».

---

## Partie 9 — Ordre de construction conseillé

Ne code pas tout d'un coup. Suis cet ordre pour toujours avoir un truc testable :

1. **Battler + stats + barres HP** (Parties 2 et 7 minimales).
2. **Boucle + ordre par vitesse** avec attaques à dégâts directs, sans mini-jeu (Partie 3). Vérifie qu'un combat se termine (victoire/défaite).
3. **Menu de commandes** basique (Attaque / Défense) (Partie 7).
4. **Mini-jeu d'Additions** en isolé (Partie 4), testé seul, puis branché sur l'attaque.
5. **SP + transformation Dragoon + magie** (Partie 5).
6. **IA ennemie** un peu plus maligne (Partie 6).
7. **Caméra cinématique + animations 3D** (Partie 8) — le polish en dernier.

### Idées d'amélioration ensuite
- Additions à plus de coups qui « montent en niveau » avec l'usage (comme dans LoD).
- Fenêtre de contre-timing (Counter).
- Table élémentaire complète + résistances/faiblesses affichées.
- File d'attente d'actions visible (ordre des tours à l'écran).
- Effets de particules sur coup réussi/critique (`GPUParticles3D`).

---

## Notes de portée

- Les scripts ci-dessus sont **cohérents entre eux** mais destinés à être assemblés et ajustés dans ton projet (chemins de nœuds, valeurs d'équilibrage, connexions de signaux dans l'éditeur). Ils ne forment pas un projet clé-en-main : construis dans l'ordre de la Partie 9 en testant à chaque étape.
- Tout le contenu (persos, noms, stats précises, art, musique) doit être **le tien**. On réimplémente un *système*, on ne copie pas *Legend of Dragoon*.
