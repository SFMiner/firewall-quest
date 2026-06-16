extends Node
var _f := 0
var _c := 0
func _ready() -> void:
	await _run()
	print("=== M6 CONN: %d/%d ===" % [_c - _f, _c])
	print("M6 CONN RESULT: %s" % ("PASS" if _f == 0 else "FAIL(%d)" % _f))
	get_tree().quit(_f)
func _run() -> void:
	_check("client configured", SupabaseManager.is_configured)
	if not SupabaseManager.is_configured:
		return
	var code := "Z%d" % (randi() % 90000 + 10000)
	var r: Dictionary = await SupabaseManager.create_room(code, "host1", {"firewall_power": 100, "zone": "welcometon"})
	_check("create_room ok", r.ok)
	var g: Dictionary = await SupabaseManager.get_room(code)
	_check("get_room returns one", g.ok and g.data is Array and g.data.size() == 1)
	_check("host_id matches", g.data[0].get("host_id") == "host1")
	var j: Dictionary = await SupabaseManager.join_room(code, "guest2")
	_check("join_room ok", j.ok)
	var g2: Dictionary = await SupabaseManager.get_room(code)
	_check("two players after join", (g2.data[0].get("players") as Array).size() == 2)
	var u: Dictionary = await SupabaseManager.update_room_state(code, {"firewall_power": 75})
	_check("update_room_state ok", u.ok)
	var g3: Dictionary = await SupabaseManager.get_room(code)
	_check("state synced to 75", int((g3.data[0].get("game_state") as Dictionary).get("firewall_power", 0)) == 75)
	var ps: Dictionary = await SupabaseManager.push_save("playerX", {"level": 3, "bytes": 42})
	_check("push_save ok", ps.ok)
	var pl: Dictionary = await SupabaseManager.pull_save("playerX")
	_check("pull_save bytes==42", pl.ok and int((pl.data as Dictionary).get("bytes", 0)) == 42)
	var d: Dictionary = await SupabaseManager.delete_room(code)
	_check("delete_room ok", d.ok)
func _check(label: String, ok: bool) -> void:
	_c += 1
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok: _f += 1
