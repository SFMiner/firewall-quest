# === POI.gd ===
# A point of interest the player can interact with (Inn, Shop, Quest Board, ...).
# Emits `triggered` with its id; ExploreScene dispatches the behavior.
class_name POI
extends Area2D

signal triggered(poi_id: String)

var poi_id: String = ""
var label: String = ""


func _ready() -> void:
	add_to_group("interactable")


func interact_prompt() -> String:
	return label


func interact() -> void:
	triggered.emit(poi_id)
