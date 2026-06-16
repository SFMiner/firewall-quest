# === NPC.gd ===
# A data-driven non-player character. Reads its definition from npcs.json, shows
# an idle LPC sprite, and opens a dialogue balloon on interaction. Joins the
# "npc" group and exposes `npc_name` so the dialogue balloon can resolve it.
class_name NPC
extends Area2D

const BALLOON_SCENE: PackedScene = preload("res://scenes/ui/dialogue_balloon/dialogue_balloon.tscn")

## Which npcs.json entry this is.
@export var npc_id: String = ""

var npc_name: String = ""
var _data: Dictionary = {}

@onready var _sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	add_to_group("npc")
	add_to_group("interactable")
	_data = DataLoader.get_npc(npc_id)
	npc_name = _data.get("name", npc_id)
	var sprite_name: String = _data.get("sprite", npc_id)
	var frames: SpriteFrames = LPCFrames.build(sprite_name)
	if frames.get_animation_names().size() > 0:
		_sprite.sprite_frames = frames
		if frames.has_animation("idle_down"):
			_sprite.play("idle_down")


## Prompt shown by the HUD when the player is in range.
func interact_prompt() -> String:
	return "Talk to %s" % npc_name


## Called by the player's interaction probe.
func interact() -> void:
	if GameManager.ui_blocking:
		return
	var res_path: String = _data.get("dialogue_resource", "")
	if res_path.is_empty() or not ResourceLoader.exists(res_path):
		return
	var resource: DialogueResource = load(res_path)
	var title: String = _data.get("dialogue_title", npc_id)
	_open_dialogue(resource, title)


func _open_dialogue(resource: DialogueResource, title: String) -> void:
	GameManager.ui_blocking = true
	var balloon: Node = BALLOON_SCENE.instantiate()
	get_tree().current_scene.add_child(balloon)
	balloon.tree_exited.connect(_on_dialogue_closed)
	# Pass GameManager so .dialogue conditionals can read `firewall_power`, flags, etc.
	balloon.start(resource, title, [GameManager])


func _on_dialogue_closed() -> void:
	GameManager.ui_blocking = false
