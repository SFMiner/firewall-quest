extends Node
var _f := 0
var _c := 0
func _ready() -> void:
	await _run()
	print("=== M6 LOBBY: %d/%d ===" % [_c - _f, _c])
	print("M6 LOBBY RESULT: %s" % ("PASS" if _f == 0 else "FAIL(%d)" % _f))
	get_tree().quit(_f)
func _run() -> void:
	_check("backend configured", SupabaseManager.is_configured)
	if not SupabaseManager.is_configured:
		return
	# --- HOST ---
	var host_ps: PlayerState = PlayerState.create("Host", "fighter")
	var code: String = await PartyManager.host_room(host_ps.to_dict())
	PartyManager.set_process(false)  # stop auto-poll; drive it manually
	_check("host got a 4-char code", code.length() == 4)
	_check("is_multiplayer + is_host", PartyManager.is_multiplayer and PartyManager.is_host)
	_check("host sees itself (1 member)", PartyManager.members.size() == 1)
	var room: Dictionary = await SupabaseManager.get_room(code)
	_check("room exists in backend", room.ok and room.data is Array and room.data.size() == 1)
	# --- simulate a guest joining (second client) by editing the room directly ---
	var gs: Dictionary = room.data[0].get("game_state", {})
	gs["players"]["guest_x"] = {"name": "Guest", "class": "mage"}
	await SupabaseManager.update_room_state(code, gs)
	await PartyManager._poll()
	PartyManager.set_process(false)
	_check("host poll now sees 2 members", PartyManager.members.size() == 2)
	# --- START ---
	var started: Array[bool] = [false]
	PartyManager.room_started.connect(func() -> void: started[0] = true)
	await PartyManager.start_game()
	_check("start_game emits room_started", started[0])
	var r2: Dictionary = await SupabaseManager.get_room(code)
	_check("room flagged started", (r2.data[0].get("game_state", {}) as Dictionary).get("started", false))
	# --- LEAVE (host deletes the room) ---
	await PartyManager.leave_room()
	var r3: Dictionary = await SupabaseManager.get_room(code)
	_check("room deleted on host leave", r3.ok and r3.data is Array and r3.data.is_empty())

	# --- JOIN flow (fresh room made directly, then PartyManager joins it) ---
	var jcode: String = "JNTST"
	await SupabaseManager.delete_room(jcode)
	await SupabaseManager.create_room(jcode, "host_owner", {"started": false, "firewall_power": 100, "zone": "welcometon", "players": {"host_owner": {"name": "Owner", "class": "bard"}}})
	var guest_ps: PlayerState = PlayerState.create("Joiner", "rogue")
	var ok: bool = await PartyManager.join_room(jcode, guest_ps.to_dict())
	PartyManager.set_process(false)
	_check("join_room succeeded", ok)
	_check("joiner sees 2 members (owner + self)", PartyManager.members.size() == 2)
	_check("not host as guest", not PartyManager.is_host)
	await SupabaseManager.delete_room(jcode)
func _check(label: String, ok: bool) -> void:
	_c += 1
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok: _f += 1
