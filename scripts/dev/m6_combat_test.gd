extends Node
var _f := 0
var _c := 0
func _ready() -> void:
	await _run()
	print("=== M6 COMBAT: %d/%d ===" % [_c - _f, _c])
	print("M6 COMBAT RESULT: %s" % ("PASS" if _f == 0 else "FAIL(%d)" % _f))
	get_tree().quit(_f)


func _run() -> void:
	_test_snapshot_roundtrip()

	if not SupabaseManager.is_configured:
		_check("backend configured", false)
		return

	var host_ps: PlayerState = PlayerState.create("Host", "fighter")
	var code: String = await PartyManager.host_room(host_ps.to_dict())
	PartyManager.set_process(false)
	_check("host created room", code.length() == 4)

	# Replace the party with a single simulated guest (mage) so the host's
	# relay handles 100% of the encounter's player turns — the real point of
	# this test (the live two-window feel still needs a manual playtest).
	var guest_ps: PlayerState = PlayerState.create("Mara", "mage")
	var room: Dictionary = await SupabaseManager.get_room(code)
	var gs: Dictionary = room.data[0].get("game_state", {})
	var guest_slot: Dictionary = guest_ps.to_dict()
	guest_slot["pos"] = [0, 0]
	guest_slot["zone"] = "zone1"
	guest_slot["t"] = Time.get_unix_time_from_system()
	gs["players"] = {"guest_a": guest_slot}
	await SupabaseManager.update_room_state(code, gs)
	# Update the local mirror directly rather than via _poll() — a poll would
	# also rewrite our own presence slot back into "players", reintroducing the
	# host as a second party member when we want a clean guest-only party.
	PartyManager.game_state = gs
	PartyManager._refresh_members()
	_check("party is guest-only", PartyManager.members.size() == 1 and PartyManager.members[0].id == "guest_a")

	_test_mp_party_and_scaling()
	await _test_action_relay_writes(code)
	_test_viewer_zone_gating()
	await _test_live_relay(code)

	await PartyManager.leave_room()


# === Pure logic: Combatant <-> snapshot dict round-trip ===
func _test_snapshot_roundtrip() -> void:
	var ps: PlayerState = PlayerState.create("Mara", "mage")
	var c: Combatant = Combatant.from_player(ps, "p_guest")
	c.hp = 7
	c.add_status({"kind": "buff", "stat": "pwr", "amount": 2, "turns": 2, "name": "Focus"})
	var snap: Dictionary = c.to_snapshot()
	_check("snapshot owner set", snap.get("owner", "") == "p_guest")
	var ghost: Combatant = Combatant.from_snapshot(snap)
	_check("ghost owner round-trips", ghost.owner_id == "p_guest")
	_check("ghost hp round-trips", ghost.hp == 7)
	_check("ghost is_player true for non-empty owner", ghost.is_player)
	_check("ghost statuses round-trip", ghost.statuses.size() == 1 and ghost.statuses[0].get("name", "") == "Focus")
	var enemy_ghost: Combatant = Combatant.from_snapshot({"owner": "", "name": "Goblin", "hp": 5, "max_hp": 8})
	_check("enemy ghost is_player false for empty owner", not enemy_ghost.is_player)


# === Pure logic: MP party building + zone filtering + boss HP scaling ===
func _test_mp_party_and_scaling() -> void:
	var party: Array[Combatant] = Combat._build_mp_party("zone1")
	_check("mp party has the simulated guest", party.size() == 1 and party[0].owner_id == "guest_a")
	_check("mp party combatant is a player", party[0].is_player)

	# Add a second simulated member standing in a different zone — they should
	# never be pulled into a zone1 fight (and only they should be pulled into one).
	PartyManager.game_state["players"]["guest_b"] = {
		"player_name": "Bram", "class": "fighter", "pos": [0, 0], "zone": "zone2",
		"t": Time.get_unix_time_from_system(),
	}
	PartyManager._refresh_members()
	var zone1_party: Array[Combatant] = Combat._build_mp_party("zone1")
	_check("cross-zone member excluded from zone1 fight", zone1_party.size() == 1 and zone1_party[0].owner_id == "guest_a")
	var zone2_party: Array[Combatant] = Combat._build_mp_party("zone2")
	_check("only the zone2 member joins a zone2 fight", zone2_party.size() == 1 and zone2_party[0].owner_id == "guest_b")
	PartyManager.game_state["players"].erase("guest_b")
	PartyManager._refresh_members()

	var boss_def: EnemyDef = DataLoader.get_enemy("vice_principal")
	var base_hp: int = Combatant.from_enemy(boss_def, GameManager.firewall_power).max_hp
	var solo_enemies: Array[Combatant] = Combat._build_mp_enemies(["vice_principal"], 1)
	_check("boss HP unscaled for party of 1", solo_enemies[0].max_hp == base_hp)
	var scaled_enemies: Array[Combatant] = Combat._build_mp_enemies(["vice_principal"], 3)
	var expected: int = int(round(base_hp * (1.0 + 0.6 * 2.0)))
	_check("boss HP scales with party size", scaled_enemies[0].max_hp == expected)
	var non_boss: Array[Combatant] = Combat._build_mp_enemies(["goblin"], 3)
	var goblin_base: int = Combatant.from_enemy(DataLoader.get_enemy("goblin"), GameManager.firewall_power).max_hp
	_check("non-boss HP unaffected by party size", non_boss[0].max_hp == goblin_base)


# === PartyManager write helpers (exercised from the guest's-eye view) ===
func _test_action_relay_writes(code: String) -> void:
	var was_host: bool = PartyManager.is_host
	PartyManager.is_host = false  # pretend to be a guest just to exercise the write path
	await PartyManager.submit_combat_action({"action": "attack", "target_index": 0})
	await PartyManager.request_encounter(["goblin"], "zone1")
	PartyManager.is_host = was_host
	var room: Dictionary = await SupabaseManager.get_room(code)
	var gs: Dictionary = room.data[0].get("game_state", {})
	var combat: Dictionary = gs.get("combat", {})
	_check("submit_combat_action wrote an action", combat.get("actions", {}).has(PartyManager.local_id))
	_check("request_encounter wrote a request", combat.get("requested", {}).get("enemy_ids", []) == ["goblin"])
	_check("request_encounter wrote the zone", combat.get("requested", {}).get("zone", "") == "zone1")
	# Clear both so they don't leak into the live relay test below. Update the
	# local mirror directly rather than via _poll() — a poll would also rewrite
	# our own presence slot back into "players", reintroducing the host as a
	# second party member before run_shared_encounter snapshots the (intended
	# guest-only) party below.
	combat.erase("actions")
	combat.erase("requested")
	gs["combat"] = combat
	await SupabaseManager.update_room_state(code, gs)
	PartyManager.game_state = gs


# === Guest viewer only opens for a fight in the guest's own zone ===
func _test_viewer_zone_gating() -> void:
	var was_host: bool = PartyManager.is_host
	var was_zone: String = GameManager.current_zone
	PartyManager.is_host = false  # pretend to be a guest so _on_remote_combat_changed considers opening a viewer
	PartyManager.game_state["combat"] = {"active": true, "zone": "zone2"}

	GameManager.current_zone = "zone1"
	Combat._on_remote_combat_changed()
	_check("viewer stays closed for a fight in another zone", not Combat._viewer_open)

	GameManager.current_zone = "zone2"
	Combat._on_remote_combat_changed()
	_check("viewer opens for a fight in the guest's own zone", Combat._viewer_open)
	if Combat._viewer_open:
		Combat._close_viewer("fled")

	PartyManager.is_host = was_host
	GameManager.current_zone = was_zone
	PartyManager.game_state["combat"] = {}


# === Live relay: run a real shared encounter; respond to guest_a's turns by
# writing actions straight to the room (as a second client would), and let
# PartyManager's normal polling surface them to the host's relay. ===
func _test_live_relay(code: String) -> void:
	var finished: Array[bool] = [false]
	var result: Array[String] = [""]
	Combat.encounter_finished.connect(_on_test_encounter_finished.bind(finished, result), CONNECT_ONE_SHOT)
	PartyManager.set_process(true)
	GameManager.current_zone = "zone1"  # host stands with guest_a so the visible CombatScene path runs too
	Combat.run_shared_encounter(["goblin"], "zone1")

	var elapsed: float = 0.0
	var attacks_sent: int = 0
	while not finished[0] and elapsed < 25.0:
		await get_tree().create_timer(0.5).timeout
		elapsed += 0.5
		var combat: Dictionary = PartyManager.game_state.get("combat", {})
		if combat.get("turn_owner", "") == "guest_a" and not combat.get("actions", {}).has("guest_a"):
			await _write_guest_action(code, "guest_a", {"action": "attack", "target_index": 0})
			attacks_sent += 1

	PartyManager.set_process(false)
	_check("live relay reached victory", result[0] == "victory")
	_check("relay never timed out (no AI takeover)", int(Combat._remote_timeouts.get("guest_a", 0)) == 0)
	_check("attacks were relayed", attacks_sent > 0)
	var room: Dictionary = await SupabaseManager.get_room(code)
	var gs: Dictionary = room.data[0].get("game_state", {})
	_check("rewards pushed to room", int((gs.get("combat", {}) as Dictionary).get("rewards", {}).get("xp", 0)) > 0)


func _on_test_encounter_finished(r: String, finished: Array, result: Array) -> void:
	finished[0] = true
	result[0] = r


func _write_guest_action(code: String, owner_id: String, action: Dictionary) -> void:
	var room: Dictionary = await SupabaseManager.get_room(code)
	var gs: Dictionary = room.data[0].get("game_state", {})
	if not gs.has("combat"):
		gs["combat"] = {}
	if not gs["combat"].has("actions"):
		gs["combat"]["actions"] = {}
	gs["combat"]["actions"][owner_id] = action
	await SupabaseManager.update_room_state(code, gs)


func _check(label: String, ok: bool) -> void:
	_c += 1
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		_f += 1
