class_name SaveSlots
extends Control
## The 4 save slots (scenes/ui/save_slots.tscn), used in two ways:
##   LOAD mode (main menu): "Cargar" a slot, start a "Nueva" game in it (replacing what it had)
##                          or "Borrar" it.
##   SAVE mode (pause menu): "Guardar aquí" saves the current game in a new slot or replaces one.
## Replacing or deleting a slot asks for confirmation. Slots whose file was modified are shown as
## "modificado" and can not be loaded. Every row is a node: Slots/Slot1..Slot4.

signal save_requested(slot: int)
signal closed

enum Mode { LOAD, SAVE }

@export var mode: Mode = Mode.LOAD

@onready var title_label: Label = $Panel/VBox/Title
@onready var rows: Array = [$Panel/VBox/Slots/Slot1, $Panel/VBox/Slots/Slot2, $Panel/VBox/Slots/Slot3, $Panel/VBox/Slots/Slot4]
@onready var confirm_box: Control = $Panel/VBox/Confirm
@onready var confirm_label: Label = $Panel/VBox/Confirm/Label
@onready var status_label: Label = $Panel/VBox/Status
@onready var back_button: Button = $Panel/VBox/BackButton

var _pending_action := Callable()


func _ready() -> void:
	for i in rows.size():
		var row: Node = rows[i]
		var slot := i + 1
		row.get_node("HBox/MainButton").pressed.connect(_on_main_pressed.bind(slot))
		row.get_node("HBox/NewButton").pressed.connect(_on_new_pressed.bind(slot))
		row.get_node("HBox/DeleteButton").pressed.connect(_on_delete_pressed.bind(slot))


func open(new_mode: Mode) -> void:
	mode = new_mode
	visible = true
	confirm_box.visible = false
	status_label.text = ""
	refresh()
	back_button.grab_focus()


func refresh() -> void:
	title_label.text = "Elige una partida" if mode == Mode.LOAD else "Guardar partida"
	var slots := SaveManager.list_slots()
	for i in rows.size():
		var info: Dictionary = slots[i]
		var row: Node = rows[i]
		var label: Label = row.get_node("HBox/Info")
		var main: Button = row.get_node("HBox/MainButton")
		var new_button: Button = row.get_node("HBox/NewButton")
		var delete_button: Button = row.get_node("HBox/DeleteButton")
		label.text = "Partida %d  ·  %s" % [i + 1, describe(info)]
		main.text = "Cargar" if mode == Mode.LOAD else "Guardar aquí"
		new_button.visible = mode == Mode.LOAD
		delete_button.disabled = info.status == SaveManager.SlotStatus.EMPTY
		if mode == Mode.LOAD:
			main.disabled = info.status != SaveManager.SlotStatus.VALID or bool(info.data.completed)
		else:
			main.disabled = false


## Text of a slot: what was done, play time and date.
static func describe(info: Dictionary) -> String:
	match info.status:
		SaveManager.SlotStatus.EMPTY:
			return "Vacía"
		SaveManager.SlotStatus.TAMPERED:
			return "¡Guardado modificado o dañado! No se puede cargar"
	var d: Dictionary = info.data
	var t := int(d.play_time)
	var dt := Time.get_datetime_dict_from_unix_time(int(d.saved_at) + int(Time.get_time_zone_from_system().bias) * 60)
	var date := "%02d/%02d/%d %02d:%02d" % [dt.day, dt.month, dt.year, dt.hour, dt.minute]
	if d.completed:
		return "¡Misión cumplida!  ·  %d:%02d  ·  %s" % [t / 60, t % 60, date]
	return "Carne %d/%d  ·  Buggy: %s  ·  %d:%02d  ·  %s" % [d.meat.size(), SaveManager.MEAT_COUNT, "derrotado" if d.boss_defeated else "en pie", t / 60, t % 60, date]


func _ask(text: String, action: Callable) -> void:
	confirm_label.text = text
	confirm_box.visible = true
	_pending_action = action
	$Panel/VBox/Confirm/Buttons/YesButton.grab_focus()


func _on_main_pressed(slot: int) -> void:
	var info := SaveManager.read_slot(slot)
	if mode == Mode.LOAD:
		if SaveManager.load_game(slot):
			get_tree().paused = false
			get_tree().change_scene_to_file("res://scenes/game.tscn")
		else:
			status_label.text = "Esa partida no se puede cargar."
	elif info.status == SaveManager.SlotStatus.EMPTY:
		save_requested.emit(slot)
	else:
		_ask("¿Reemplazar la Partida %d con el progreso actual?" % slot, save_requested.emit.bind(slot))


func _on_new_pressed(slot: int) -> void:
	var start := func() -> void:
		SaveManager.start_new_game(slot)
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/game.tscn")
	if SaveManager.read_slot(slot).status == SaveManager.SlotStatus.EMPTY:
		start.call()
	else:
		_ask("¿Empezar una partida nueva en la Partida %d? Se perderá lo que tenía." % slot, start)


func _on_delete_pressed(slot: int) -> void:
	_ask("¿Borrar la Partida %d?" % slot, func() -> void:
		SaveManager.delete_slot(slot)
		status_label.text = "Partida %d borrada." % slot
		refresh())


func _on_yes_button_pressed() -> void:
	confirm_box.visible = false
	var action := _pending_action
	_pending_action = Callable()
	if action.is_valid():
		action.call()


func _on_no_button_pressed() -> void:
	confirm_box.visible = false
	_pending_action = Callable()


func _on_back_button_pressed() -> void:
	visible = false
	closed.emit()


## Called by the pause menu after saving.
func show_saved(slot: int, ok: bool) -> void:
	status_label.text = ("Partida %d guardada." % slot) if ok else "No se pudo guardar."
	refresh()
