# === PartyManager.gd ===
# Tracks the active party. Solo by default (a party of one); multiplayer room
# state layers on in M6. Autoload — `PartyManager`.
extends Node

## Emitted when a member joins or leaves.
signal party_changed()

## Members of the current party. Each entry is a Dictionary of character state.
## In solo play this holds exactly the local player.
var members: Array[Dictionary] = []

## True while connected to a multiplayer room (always false until M6).
var is_multiplayer: bool = false

## 4-char room code when hosting/joined; empty in solo.
var room_code: String = ""


## Start a solo party from the local player's character state.
func start_solo(player_state: Dictionary) -> void:
	is_multiplayer = false
	room_code = ""
	members = [player_state]
	party_changed.emit()


func party_size() -> int:
	return members.size()


func is_solo() -> bool:
	return not is_multiplayer
