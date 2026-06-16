# === SupabaseManager.gd ===
# All Supabase backend calls (multiplayer rooms, cloud saves, mod registry) behind
# one clean, await-able interface. REST/PostgREST over HTTPRequest — works in the
# web export. Realtime is done by polling (see PartyManager), which needs no
# WebSocket and survives GitHub Pages hosting. Autoload — `SupabaseManager`.
#
# Config comes from res://supabase.cfg (url + publishable/anon key; client-safe).
# Every method returns {ok: bool, code: int, data: Variant} and never throws.
extends Node

const CONFIG_PATH: String = "res://supabase.cfg"

var url: String = ""
var anon_key: String = ""
var is_configured: bool = false


func _ready() -> void:
	_load_config()


func _load_config() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		url = cfg.get_value("supabase", "url", "")
		anon_key = cfg.get_value("supabase", "anon_key", "")
	is_configured = not url.is_empty() and not anon_key.is_empty()


# === Rooms ===
func create_room(code: String, host_id: String, game_state: Dictionary) -> Dictionary:
	return await _rest(HTTPClient.METHOD_POST, "rooms", "", {
		"code": code, "host_id": host_id,
		"players": [host_id], "game_state": game_state,
	})


func get_room(code: String) -> Dictionary:
	return await _rest(HTTPClient.METHOD_GET, "rooms", "?code=eq.%s&select=*" % code)


func join_room(code: String, player_id: String) -> Dictionary:
	var room: Dictionary = await get_room(code)
	if not room.ok or not (room.data is Array) or room.data.is_empty():
		return {"ok": false, "code": room.code, "data": null}
	var players: Array = room.data[0].get("players", [])
	if player_id not in players:
		players.append(player_id)
	return await _rest(HTTPClient.METHOD_PATCH, "rooms", "?code=eq.%s" % code, {"players": players})


func update_room_state(code: String, game_state: Dictionary) -> Dictionary:
	return await _rest(HTTPClient.METHOD_PATCH, "rooms", "?code=eq.%s" % code, {"game_state": game_state})


func delete_room(code: String) -> Dictionary:
	return await _rest(HTTPClient.METHOD_DELETE, "rooms", "?code=eq.%s" % code)


# === Cloud saves (upsert by player_id) ===
func push_save(player_id: String, save_data: Dictionary) -> Dictionary:
	return await _rest(HTTPClient.METHOD_POST, "player_saves", "", {
		"player_id": player_id, "save_data": save_data,
	}, true)


func pull_save(player_id: String) -> Dictionary:
	var r: Dictionary = await _rest(HTTPClient.METHOD_GET, "player_saves", "?player_id=eq.%s&select=save_data" % player_id)
	if r.ok and r.data is Array and not r.data.is_empty():
		return {"ok": true, "code": r.code, "data": r.data[0].get("save_data", {})}
	return {"ok": false, "code": r.code, "data": {}}


# === Mods (registry; upload/sanitize lands in M7) ===
func fetch_mods() -> Dictionary:
	return await _rest(HTTPClient.METHOD_GET, "mods", "?approved=eq.true&select=*&order=rating.desc")


func upload_mod(mod: Dictionary) -> Dictionary:
	return await _rest(HTTPClient.METHOD_POST, "mods", "", mod)


# === Core REST helper ===
# `upsert` adds the merge-duplicates Prefer header (for cloud-save upserts).
func _rest(method: int, table: String, query: String = "", body: Dictionary = {}, upsert: bool = false) -> Dictionary:
	if not is_configured:
		return {"ok": false, "code": 0, "data": null}
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)
	var prefer: String = "return=representation"
	if upsert:
		prefer += ",resolution=merge-duplicates"
	var headers: PackedStringArray = [
		"apikey: " + anon_key,
		"Authorization: Bearer " + anon_key,
		"Content-Type: application/json",
		"Prefer: " + prefer,
	]
	var full: String = "%s/rest/v1/%s%s" % [url, table, query]
	var payload: String = JSON.stringify(body) if not body.is_empty() else ""
	var err: int = http.request(full, headers, method, payload)
	if err != OK:
		http.queue_free()
		return {"ok": false, "code": 0, "data": null}
	var res: Array = await http.request_completed
	http.queue_free()
	var code: int = res[1]
	var raw: String = (res[3] as PackedByteArray).get_string_from_utf8()
	var data: Variant = JSON.parse_string(raw) if not raw.is_empty() else null
	var ok: bool = code >= 200 and code < 300
	if not ok:
		push_warning("Supabase %s %s -> %d: %s" % [method, table, code, raw])
	return {"ok": ok, "code": code, "data": data}
