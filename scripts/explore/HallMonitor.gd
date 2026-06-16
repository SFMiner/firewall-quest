# === HallMonitor.gd ===
# Zone 3 boss puzzle. Chases the player (a touch slower, so it's lurable). When
# led across all three patrol checkpoints, its policy loop closes and it's caught.
class_name HallMonitor
extends CharacterBody2D

signal caught()

@export var speed: float = 78.0

var _player: Node2D = null
var _markers: Array[Node2D] = []
var _lit: Dictionary = {}
var _done: bool = false


func setup(player: Node2D, markers: Array[Node2D]) -> void:
	_player = player
	_markers = markers
	var sprite: Sprite2D = Sprite2D.new()
	var tex_path: String = "res://assets/enemies/hall_monitor.png"
	if ResourceLoader.exists(tex_path):
		sprite.texture = load(tex_path)
		sprite.scale = Vector2(0.45, 0.45)
		sprite.position = Vector2(0, -24)
	add_child(sprite)
	var cs: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 14.0
	cs.shape = circle
	add_child(cs)


func _physics_process(_delta: float) -> void:
	if _done or _player == null or GameManager.ui_blocking:
		return
	var dir: Vector2 = (_player.global_position - global_position).normalized()
	velocity = dir * speed
	move_and_slide()
	for m: Node2D in _markers:
		if not _lit.get(m, false) and global_position.distance_to(m.global_position) < 34.0:
			_lit[m] = true
			m.color = Color(0.4, 1.0, 0.4, 0.85)
			if _lit.size() >= _markers.size():
				_done = true
				caught.emit()
				return
