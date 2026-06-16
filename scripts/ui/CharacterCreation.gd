# === CharacterCreation.gd ===
# Pick a name (or roll a school-appropriate one), a class, and a portrait. Emits
# `confirmed` with the choices; Main.gd turns that into a PlayerState and starts
# the game.
class_name CharacterCreation
extends Control

signal confirmed(player_name: String, class_id: String, portrait: String)

const RANDOM_NAMES: Array[String] = [
	"Student #4", "Kevin", "The One Who Was On Their Phone",
	"Hall Pass", "Substitute", "Definitely Not Kevin",
]
# "default" plus two club easter eggs.
const PORTRAITS: Array[String] = ["default", "stick_figure", "plague_doctor"]
const PORTRAIT_LABELS: Array[String] = ["Default", "Stick Figure", "Plague Doctor Mask"]

var _class_ids: Array[String] = []

@onready var _name_edit: LineEdit = %NameEdit
@onready var _class_option: OptionButton = %ClassOption
@onready var _portrait_option: OptionButton = %PortraitOption
@onready var _role_label: Label = %RoleLabel
@onready var _preview: TextureRect = %Preview


func _ready() -> void:
	for class_def: ClassDef in DataLoader.all_classes():
		_class_ids.append(class_def.id)
		_class_option.add_item(class_def.sanitized_name)
	for label: String in PORTRAIT_LABELS:
		_portrait_option.add_item(label)
	_class_option.item_selected.connect(_on_class_selected)
	_on_class_selected(0)


func _on_random_pressed() -> void:
	_name_edit.text = RANDOM_NAMES.pick_random()


func _on_class_selected(index: int) -> void:
	var class_def: ClassDef = DataLoader.get_class_def(_class_ids[index])
	if class_def == null:
		return
	_role_label.text = "%s  —  %s" % [class_def.unlocked_name, class_def.role]
	_update_preview(class_def.id)


func _update_preview(class_id: String) -> void:
	var path: String = "res://assets/chars/%s_walk.png" % class_id
	if not ResourceLoader.exists(path):
		_preview.texture = null
		return
	var at: AtlasTexture = AtlasTexture.new()
	at.atlas = load(path)
	at.region = Rect2(0, 128, 64, 64)  # down-facing standing frame (row 2, col 0)
	_preview.texture = at


func _on_confirm_pressed() -> void:
	var player_name: String = _name_edit.text.strip_edges()
	if player_name.is_empty():
		player_name = RANDOM_NAMES.pick_random()
	var class_id: String = _class_ids[_class_option.selected]
	var portrait: String = PORTRAITS[_portrait_option.selected]
	confirmed.emit(player_name, class_id, portrait)
