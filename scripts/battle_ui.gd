extends CanvasLayer

@onready var command_menu := $CommandMenu
@onready var message_label := $MessageLabel
@onready var addition_overlay := $AdditionOverlay
@onready var party_status := $PartyStatus

func setup_party_status(party: Array, enemies: Array) -> void:
	party_status.setup(party + enemies)

func show_message(text: String) -> void:
	message_label.text = text
	message_label.visible = true
	await get_tree().create_timer(1.0).timeout
	message_label.visible = false

# Renvoie un Dictionary { action, target } via await
func request_command(actor: Battler, party: Array, enemies: Array) -> Dictionary:
	command_menu.open(actor, party, enemies)
	var result: Dictionary = await command_menu.action_selected
	command_menu.close()
	return result

func refresh_status(_actor: Battler = null) -> void:
	party_status.update_all()

func dragoon_charge_minigame() -> float:
	var count := 0
	var t := 0.0
	while t < 2.0:
		t += get_process_delta_time()
		if Input.is_action_just_pressed("addition_hit"):
			count += 1
		await get_tree().process_frame
	return clampf(1.0 + count * 0.08, 1.0, 2.0)
