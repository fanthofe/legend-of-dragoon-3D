extends VBoxContainer

var _rows: Dictionary = {}

func setup(battlers: Array) -> void:
	for child in get_children():
		child.queue_free()
	_rows.clear()

	for b in battlers:
		_add_row(b)

func _add_row(b: Battler) -> void:
	var row := VBoxContainer.new()

	var name_label := Label.new()
	name_label.text = b.display_name
	row.add_child(name_label)

	var hp_bar := ProgressBar.new()
	hp_bar.max_value = 100
	hp_bar.value = 100
	hp_bar.show_percentage = false
	row.add_child(hp_bar)

	var sp_bar := ProgressBar.new()
	sp_bar.max_value = 100
	sp_bar.value = 0
	sp_bar.show_percentage = false
	row.add_child(sp_bar)

	add_child(row)
	_rows[b] = {"hp": hp_bar, "sp": sp_bar}

	b.hp_changed.connect(_on_hp_changed)
	b.sp_changed.connect(_on_sp_changed)

func _on_hp_changed(b: Battler) -> void:
	if _rows.has(b):
		_rows[b].hp.value = float(b.hp) / b.max_hp * 100.0

func _on_sp_changed(b: Battler) -> void:
	if _rows.has(b):
		_rows[b].sp.value = float(b.sp) / Battler.MAX_SP * 100.0

func update_all() -> void:
	for b in _rows.keys():
		_on_hp_changed(b)
		_on_sp_changed(b)
