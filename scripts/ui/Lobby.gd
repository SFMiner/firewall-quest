# === Lobby.gd ===
# Co-op waiting room. Shows the room code and connected players (polled by
# PartyManager). Host can Start; guests wait until the host starts. Emits
# `start_game` when this client should enter the shared world, or `cancelled`.
class_name Lobby
extends Control

signal start_game()
signal cancelled()

@onready var _code: Label = %CodeLabel
@onready var _players: VBoxContainer = %PlayerList
@onready var _status: Label = %StatusLabel
@onready var _start_btn: Button = %StartButton


func _ready() -> void:
	_code.text = "Room Code:  %s" % PartyManager.room_code
	_start_btn.visible = PartyManager.is_host
	_status.text = "Waiting for the host to start..." if not PartyManager.is_host else "Share the code. Start when ready."
	PartyManager.party_changed.connect(_refresh)
	PartyManager.room_started.connect(_on_started)
	PartyManager.room_closed.connect(func() -> void: cancelled.emit())
	_refresh()


func _refresh() -> void:
	for child: Node in _players.get_children():
		child.queue_free()
	for m: Dictionary in PartyManager.members:
		var label: Label = Label.new()
		var tag: String = "  (you)" if m.get("id", "") == PartyManager.local_id else ""
		var cls: ClassDef = DataLoader.get_class_def(m.get("class", ""))
		var cls_name: String = cls.sanitized_name if cls != null else m.get("class", "")
		label.text = "%s  —  %s%s" % [m.get("name", "Player"), cls_name, tag]
		_players.add_child(label)


func _on_started() -> void:
	start_game.emit()


func _on_start_pressed() -> void:
	Audio.sfx("menu")
	PartyManager.start_game()


func _on_leave_pressed() -> void:
	Audio.sfx("menu")
	await PartyManager.leave_room()
	cancelled.emit()
