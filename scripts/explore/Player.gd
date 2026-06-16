# === Player.gd ===
# Top-down explorer. Real-time movement over the tile world, 4-direction LPC
# animation, sprint, and an interaction probe that talks to nearby NPCs. Joins
# the "player" group so the dialogue balloon can resolve it as a speaker.
class_name Player
extends CharacterBody2D

## Emitted when the NPC the player could talk to changes (empty name = none).
signal interaction_target_changed(npc_name: String)

@export var speed: float = 110.0
@export var sprint_multiplier: float = 1.7

var _char_name: String = "fighter"
var _facing: String = "down"
var _target_name: String = ""

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _interact_zone: Area2D = $InteractZone


func _ready() -> void:
	add_to_group("player")
	set_character(_char_name)


## Rebuild the sprite from an LPC character sheet (e.g. the chosen class id).
func set_character(char_name: String) -> void:
	_char_name = char_name
	var frames: SpriteFrames = LPCFrames.build(char_name)
	if frames.get_animation_names().size() > 0:
		_sprite.sprite_frames = frames
	_play("idle")


func _physics_process(_delta: float) -> void:
	if GameManager.ui_blocking:
		velocity = Vector2.ZERO
		_play("idle")
		return
	var input: Vector2 = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	).limit_length(1.0)
	var sp: float = speed * (sprint_multiplier if Input.is_action_pressed("sprint") else 1.0)
	velocity = input * sp
	move_and_slide()
	if input != Vector2.ZERO:
		_facing = LPCFrames.dir_name(input)
		_play("walk")
	else:
		_play("idle")
	_update_interaction_target()


func _unhandled_input(event: InputEvent) -> void:
	if GameManager.ui_blocking:
		return
	if event.is_action_pressed("interact"):
		_try_interact()


func _play(state: String) -> void:
	if _sprite.sprite_frames == null:
		return
	var anim: String = "%s_%s" % [state, _facing]
	if _sprite.sprite_frames.has_animation(anim) and _sprite.animation != anim:
		_sprite.play(anim)


# Talk to the nearest NPC overlapping the interaction zone.
func _try_interact() -> void:
	var nearest: Node = _nearest_npc()
	if nearest != null and nearest.has_method("interact"):
		nearest.interact()


# The closest interactable (NPC or POI) inside the interaction zone, or null.
func _nearest_npc() -> Node:
	var nearest: Node = null
	var nearest_dist: float = INF
	for area: Area2D in _interact_zone.get_overlapping_areas():
		if not area.is_in_group("interactable"):
			continue
		var d: float = global_position.distance_to(area.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = area
	return nearest


# Emit a prompt change when the reachable interactable changes.
func _update_interaction_target() -> void:
	var nearest: Node = _nearest_npc()
	var label: String = ""
	if nearest != null and nearest.has_method("interact_prompt"):
		label = nearest.interact_prompt()
	if label != _target_name:
		_target_name = label
		interaction_target_changed.emit(label)
