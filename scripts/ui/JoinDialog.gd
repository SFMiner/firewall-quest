# === JoinDialog.gd ===
# Prompt for a 4-character room code. Emits `code_entered` (uppercased) or `cancelled`.
class_name JoinDialog
extends Control

signal code_entered(code: String)
signal cancelled()

@onready var _edit: LineEdit = %CodeEdit
@onready var _error: Label = %ErrorLabel


func _ready() -> void:
	_edit.max_length = 4
	_edit.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())
	_edit.grab_focus()


func show_error(message: String) -> void:
	_error.text = message


func _on_join_pressed() -> void:
	var code: String = _edit.text.strip_edges().to_upper()
	if code.length() < 3:
		_error.text = "Enter the room code."
		return
	Audio.sfx("menu")
	code_entered.emit(code)


func _on_cancel_pressed() -> void:
	Audio.sfx("menu")
	cancelled.emit()
