extends Node
var _f := 0
var _c := 0
func _ready() -> void:
	await _run()
	print("=== M6 PRESENCE: %d/%d ===" % [_c - _f, _c])
	print("M6 PRESENCE RESULT: %s" % ("PASS" if _f == 0 else "FAIL(%d)" % _f))
	get_tree().quit(_f)
func _run() -> void:
	if not SupabaseManager.is_configured:
		_check("backend configured", false); return
	var ps: PlayerState = PlayerState.create("Host", "fighter")
	var code: String = await PartyManager.host_room(ps.to_dict())
	PartyManager.set_process(false)
	PartyManager.set_local_presence(Vector2(100, 200), "zone1")
	_check("host created room", code.length() == 4)
	# Simulate a guest in zone1 with a fresh heartbeat
	var room: Dictionary = await SupabaseManager.get_room(code)
	var gs: Dictionary = room.data[0].get("game_state", {})
	gs["players"]["guest_a"] = {"player_name": "Mara", "class": "mage", "pos": [300, 400], "zone": "zone1", "t": Time.get_unix_time_from_system()}
	await SupabaseManager.update_room_state(code, gs)
	await PartyManager._poll(); PartyManager.set_process(false)
	_check("poll sees 2 members", PartyManager.members.size() == 2)
	var in_zone: Array = PartyManager.remote_players_in_zone("zone1")
	_check("guest visible in zone1", in_zone.size() == 1 and in_zone[0].name == "Mara")
	_check("guest pos parsed", in_zone[0].pos == Vector2(300, 400))
	_check("local player not in remote list", PartyManager.remote_players_in_zone("zone1").all(func(m): return m.id != PartyManager.local_id))
	# Disconnect: stale heartbeat -> dropped from in-zone list
	room = await SupabaseManager.get_room(code)
	gs = room.data[0].get("game_state", {})
	gs["players"]["guest_a"]["t"] = Time.get_unix_time_from_system() - 30.0
	await SupabaseManager.update_room_state(code, gs)
	await PartyManager._poll(); PartyManager.set_process(false)
	_check("stale guest marked offline (excluded)", PartyManager.remote_players_in_zone("zone1").is_empty())
	# Host shares firewall power
	var synced: Array[bool] = [false]
	PartyManager.world_state_changed.connect(func() -> void: synced[0] = true)
	await PartyManager.host_set("firewall_power", 75)
	var r2: Dictionary = await SupabaseManager.get_room(code)
	_check("host_set wrote firewall=75", int((r2.data[0].get("game_state", {}) as Dictionary).get("firewall_power", 0)) == 75)
	await PartyManager.leave_room()
func _check(label: String, ok: bool) -> void:
	_c += 1
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok: _f += 1
