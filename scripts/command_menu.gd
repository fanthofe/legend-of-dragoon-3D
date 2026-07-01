extends Control

signal action_selected(result: Dictionary)

@onready var main_buttons: VBoxContainer = $MainButtons
@onready var target_buttons: VBoxContainer = $TargetButtons

var _actor: Battler
var _party: Array = []
var _enemies: Array = []
var _pending_action: String = ""

func _ready() -> void:
	visible = false
	target_buttons.visible = false
	$MainButtons/AttackButton.pressed.connect(_on_action_pressed.bind("attack"))
	$MainButtons/MagicButton.pressed.connect(_on_action_pressed.bind("magic"))
	$MainButtons/DefendButton.pressed.connect(_on_defend_pressed)
	$MainButtons/TransformButton.pressed.connect(_on_transform_pressed)
	$MainButtons/ItemButton.pressed.connect(_on_action_pressed.bind("item"))
	$MainButtons/FleeButton.pressed.connect(_on_flee_pressed)

func open(actor: Battler, party: Array, enemies: Array) -> void:
	_actor = actor
	_party = party
	_enemies = enemies
	visible = true
	main_buttons.visible = true
	target_buttons.visible = false
	$MainButtons/MagicButton.disabled = not actor.is_dragoon
	$MainButtons/AttackButton.grab_focus()

func close() -> void:
	visible = false

func _unhandled_input(_event: InputEvent) -> void:
	if visible and target_buttons.visible and Input.is_action_just_pressed("menu_cancel"):
		_on_target_back()

func _on_action_pressed(action: String) -> void:
	_pending_action = action
	var targets: Array = _party if action == "item" else _enemies
	_open_target_menu(targets)

func _on_defend_pressed() -> void:
	action_selected.emit({"action": "defend"})

func _on_transform_pressed() -> void:
	action_selected.emit({"action": "transform"})

func _on_flee_pressed() -> void:
	action_selected.emit({"action": "flee"})

func _open_target_menu(targets: Array) -> void:
	for child in target_buttons.get_children():
		child.queue_free()

	for t in targets:
		if not t.is_alive():
			continue
		var b := Button.new()
		b.text = t.display_name
		b.pressed.connect(_on_target_chosen.bind(t))
		target_buttons.add_child(b)

	var back := Button.new()
	back.text = "Retour"
	back.pressed.connect(_on_target_back)
	target_buttons.add_child(back)

	main_buttons.visible = false
	target_buttons.visible = true
	if target_buttons.get_child_count() > 0:
		target_buttons.get_child(0).grab_focus()

func _on_target_chosen(target: Battler) -> void:
	action_selected.emit({"action": _pending_action, "target": target})

func _on_target_back() -> void:
	target_buttons.visible = false
	main_buttons.visible = true
	$MainButtons/AttackButton.grab_focus()
