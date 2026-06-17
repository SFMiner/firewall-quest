# === PartyManager.gd ===
# The active party. Solo by default; multiplayer rooms layer on via Supabase.
# Realtime is poll-based: every POLL_INTERVAL we read the room, write our own
# presence slot back (read-modify-write, so we never clobber others with stale
# data), and mirror the shared game_state. The host is authoritative for world
# state and for running combat. Autoload — `PartyManager`.
extends Node

signal party_changed()             # members list changed
signal room_started()              # host pressed Start; everyone enters the game
signal room_closed()               # room vanished / we left
signal world_state_changed()       # shared firewall/zone changed (for guests)
signal combat_state_changed()      # shared combat blob changed (drives MP combat)

const POLL_INTERVAL: float = 1.0
const DISCONNECT_TIMEOUT: float = 6.0  # no heartbeat for this long = disconnected
const CODE_CHARS: String = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

var is_multiplayer: bool = false
var is_host: bool = false
var room_code: String = ""
var local_id: String = ""

## Solo: [local player's full state dict]. Multiplayer: one {id,name,class,pos,online}
## entry per player (from the room's game_state.players).
var members: Array[Dictionary] = []
## Mirror of the room's shared game_state (firewall_power, zone, started, players, combat).
var game_state: Dictionary = {}

var _poll_accum: float = 0.0
var _started: bool = false
var _busy: bool = false                 # guard against overlapping polls
var _local_data: Dictionary = {}        # our full PlayerState dict (for combat reconstruction)
var _local_pos: Vector2 = Vector2.ZERO
var _local_zone: String = "welcometon"


func _ready() -> void:
	set_process(false)


func start_solo(player_state: Dictionary) -> void:
	_reset()
	is_multiplayer = false
	members = [player_state]
	party_changed.emit()


func host_room(player_state: Dictionary) -> String:
	_reset()
	is_host = true
	is_multiplayer = true
	local_id = _gen_id()
	room_code = _gen_code()
	_local_data = player_state
	game_state = {
		"started": false, "firewall_power": 100, "zone": "welcometon",
		"players": {local_id: _presence_slot()}, "combat": {},
	}
	var r: Dictionary = await SupabaseManager.create_room(room_code, local_id, game_state)
	if not r.ok:
		_reset()
		return ""
	_refresh_members()
	set_process(true)
	party_changed.emit()
	return room_code


func join_room(code: String, player_state: Dictionary) -> bool:
	_reset()
	is_host = false
	is_multiplayer = true
	local_id = _gen_id()
	room_code = code.strip_edges().to_upper()
	_local_data = player_state
	var room: Dictionary = await SupabaseManager.get_room(room_code)
	if not room.ok or not (room.data is Array) or room.data.is_empty():
		_reset()
		return false
	game_state = room.data[0].get("game_state", {})
	if not game_state.has("players"):
		game_state["players"] = {}
	game_state["players"][local_id] = _presence_slot()
	await SupabaseManager.join_room(room_code, local_id)
	await SupabaseManager.update_room_state(room_code, game_state)
	_refresh_members()
	set_process(true)
	party_changed.emit()
	return true


func start_game() -> void:
	if not is_host:
		return
	_started = true
	game_state["started"] = true
	await SupabaseManager.update_room_state(room_code, game_state)
	room_started.emit()


func leave_room() -> void:
	if is_multiplayer and is_host and not room_code.is_empty():
		await SupabaseManager.delete_room(room_code)
	_reset()
	room_closed.emit()


# === Presence (called by the explore scene) ===
func set_local_presence(pos: Vector2, zone: String) -> void:
	_local_pos = pos
	_local_zone = zone


## Other players currently in the given zone (excludes self & disconnected).
func remote_players_in_zone(zone: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m: Dictionary in members:
		if m.get("id", "") != local_id and m.get("online", true) and m.get("zone", "") == zone:
			out.append(m)
	return out


# === Host-authoritative shared world helpers ===
## Host: write a shared world value (firewall_power / zone / combat) to the room.
func host_set(key: String, value: Variant) -> void:
	if not is_host:
		return
	game_state[key] = value
	await SupabaseManager.update_room_state(room_code, game_state)


## Guest: write our submitted action into the shared combat blob for the host
## to consume (read-modify-write, like presence). {action, target_index, skill_id, item_id}.
func submit_combat_action(action: Dictionary) -> void:
	if is_host or not is_multiplayer:
		return
	var room: Dictionary = await SupabaseManager.get_room(room_code)
	if not room.ok or not (room.data is Array) or room.data.is_empty():
		return
	game_state = room.data[0].get("game_state", {})
	if not game_state.has("combat"):
		game_state["combat"] = {}
	if not game_state["combat"].has("actions"):
		game_state["combat"]["actions"] = {}
	game_state["combat"]["actions"][local_id] = action
	await SupabaseManager.update_room_state(room_code, game_state)


## Guest: ask the host to start a shared encounter (walked into an EnemyEncounter).
## The host's CombatManager picks this up on its next poll and clears it. `zone_id`
## lets the host zone-gate the fight to players actually standing there.
func request_encounter(enemy_ids: Array, zone_id: String) -> void:
	if is_host or not is_multiplayer:
		return
	var room: Dictionary = await SupabaseManager.get_room(room_code)
	if not room.ok or not (room.data is Array) or room.data.is_empty():
		return
	game_state = room.data[0].get("game_state", {})
	if not game_state.has("combat"):
		game_state["combat"] = {}
	game_state["combat"]["requested"] = {"enemy_ids": enemy_ids, "by": local_id, "zone": zone_id, "t": Time.get_unix_time_from_system()}
	await SupabaseManager.update_room_state(room_code, game_state)


func party_size() -> int:
	return members.size()


func is_solo() -> bool:
	return not is_multiplayer


# === Polling ===
func _process(delta: float) -> void:
	if not is_multiplayer or _busy:
		return
	_poll_accum += delta
	if _poll_accum >= POLL_INTERVAL:
		_poll_accum = 0.0
		_poll()


func _poll() -> void:
	_busy = true
	var room: Dictionary = await SupabaseManager.get_room(room_code)
	if not room.ok or not (room.data is Array) or room.data.is_empty():
		_busy = false
		set_process(false)
		room_closed.emit()
		return
	var prev_world: String = "%s/%s" % [game_state.get("firewall_power", -1), game_state.get("zone", "")]
	var prev_combat: String = JSON.stringify(game_state.get("combat", {}))
	game_state = room.data[0].get("game_state", {})
	# Write our own presence slot back on freshly-read state (minimise clobber).
	if game_state.has("players"):
		game_state["players"][local_id] = _presence_slot()
		await SupabaseManager.update_room_state(room_code, game_state)
	_refresh_members()
	party_changed.emit()
	if prev_world != "%s/%s" % [game_state.get("firewall_power", -1), game_state.get("zone", "")]:
		world_state_changed.emit()
	if prev_combat != JSON.stringify(game_state.get("combat", {})):
		combat_state_changed.emit()
	if not is_host and not _started and game_state.get("started", false):
		_started = true
		room_started.emit()
	_busy = false


# === Helpers ===
func _presence_slot() -> Dictionary:
	# Full player data (so the host can build accurate combatants) + live presence.
	var slot: Dictionary = _local_data.duplicate(true)
	slot["pos"] = [_local_pos.x, _local_pos.y]
	slot["zone"] = _local_zone
	slot["t"] = Time.get_unix_time_from_system()
	return slot


func _refresh_members() -> void:
	members.clear()
	var players: Dictionary = game_state.get("players", {})
	var now: float = Time.get_unix_time_from_system()
	for id: String in players:
		var p: Dictionary = players[id]
		var pos_arr: Array = p.get("pos", [0, 0])
		members.append({
			"id": id,
			"name": p.get("player_name", "Player"),
			"class": p.get("class", "fighter"),
			"pos": Vector2(pos_arr[0], pos_arr[1]),
			"zone": p.get("zone", ""),
			"online": id == local_id or (now - float(p.get("t", now))) < DISCONNECT_TIMEOUT,
			"data": p,
		})


func _gen_code() -> String:
	var code: String = ""
	for i: int in 4:
		code += CODE_CHARS[randi() % CODE_CHARS.length()]
	return code


func _gen_id() -> String:
	return "p_%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000]


func _reset() -> void:
	set_process(false)
	is_multiplayer = false
	is_host = false
	room_code = ""
	local_id = ""
	members = []
	game_state = {}
	_local_data = {}
	_started = false
	_busy = false
	_poll_accum = 0.0
