# === ExploreScene.gd ===
# Real-time top-down exploration. Builds the ground, spawns the player with a
# follow camera, and populates the current zone (buildings, POIs, NPCs). The
# active zone comes from GameManager.current_zone.
class_name ExploreScene
extends Node2D

const PLAYER_SCENE: PackedScene = preload("res://scenes/explore/Player.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/ui/HUD.tscn")
const NPC_SCENE: PackedScene = preload("res://scenes/npcs/NPC.tscn")
const SHOP_SCENE: PackedScene = preload("res://scenes/ui/Shop.tscn")
const BALLOON_SCENE: PackedScene = preload("res://scenes/ui/dialogue_balloon/dialogue_balloon.tscn")
const CREDITS_SCENE: PackedScene = preload("res://scenes/main/Credits.tscn")
const PAUSE_SCENE: PackedScene = preload("res://scenes/ui/PauseMenu.tscn")
const GROUND_TILESET: TileSet = preload("res://assets/tilesets/ground.tres")
const TILE: int = 32
const MAP_W: int = 44
const MAP_H: int = 32

# Per-zone ground tiles {floor_source, path_source} into ground.tres.
const ZONE_GROUND: Dictionary = {
	"welcometon": [0, 1], "zone1": [0, 1],
	"zone2": [2, 3], "zone3": [4, 5], "zone4": [6, 7],
}

signal player_defeated()
signal zone_change_requested(zone_id: String)

const FILM_COLOR: Color = Color(0.78, 0.85, 1.0)
const FILM_ALPHA_SANITIZED: float = 0.30

var player: Player
var zone: ZoneDef
var hud: HUD
var _film: ColorRect
var _merchant: NPC = null
var _escort_dest: POI = null
var _escorting: bool = false
var _lure_active: bool = false
var _remote_root: Node2D = null
var _remote_avatars: Dictionary = {}  # player id -> Node2D

@onready var _world: Node2D = $World


func _ready() -> void:
	GameManager.encounters_paused = false  # clean state per zone (lure puzzle re-pauses)
	var zone_id: String = GameManager.current_zone
	zone = DataLoader.get_zone(zone_id)
	_build_ground()
	_spawn_player()
	_build_zone()
	_setup_filter()
	_setup_hud()
	GameManager.firewall_power_changed.connect(_on_firewall_changed)
	Quests.quest_updated.connect(_on_quest_updated)
	Audio.play_music("explore")
	if PartyManager.is_multiplayer:
		_setup_multiplayer()


# === Multiplayer presence (Layer 1) ===
func _setup_multiplayer() -> void:
	_remote_root = Node2D.new()
	_remote_root.name = "RemotePlayers"
	_remote_root.y_sort_enabled = true
	_world.add_child(_remote_root)
	PartyManager.party_changed.connect(_sync_remote_avatars)
	PartyManager.world_state_changed.connect(_on_world_synced)
	_sync_remote_avatars()


# Guests adopt the host's shared firewall power (and follow zone changes elsewhere).
func _on_world_synced() -> void:
	if not PartyManager.is_host:
		GameManager.adopt_firewall_power(int(PartyManager.game_state.get("firewall_power", GameManager.firewall_power)))


func _sync_remote_avatars() -> void:
	if _remote_root == null:
		return
	var present: Dictionary = {}
	for m: Dictionary in PartyManager.remote_players_in_zone(zone.id):
		present[m.id] = true
		var av: Node2D = _remote_avatars.get(m.id)
		if av == null:
			av = _make_remote_avatar(m)
			_remote_avatars[m.id] = av
			_remote_root.add_child(av)
		av.set_meta("target", m.pos)
	for id: String in _remote_avatars.keys():
		if not present.has(id):
			_remote_avatars[id].queue_free()
			_remote_avatars.erase(id)


func _make_remote_avatar(m: Dictionary) -> Node2D:
	var node: Node2D = Node2D.new()
	node.position = m.pos
	node.set_meta("target", m.pos)
	var spr: AnimatedSprite2D = AnimatedSprite2D.new()
	spr.position = Vector2(0, -18)
	var frames: SpriteFrames = LPCFrames.build(m.get("class", "fighter"))
	if frames.get_animation_names().size() > 0 and frames.has_animation("idle_down"):
		spr.sprite_frames = frames
		spr.play("idle_down")
	node.add_child(spr)
	var tag: Label = Label.new()
	tag.text = m.get("name", "Player")
	tag.position = Vector2(-70, -56)
	tag.size = Vector2(140, 18)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	tag.add_theme_constant_override("outline_size", 4)
	node.add_child(tag)
	return node


# Toast quest start/completion so quests register, and run the merchant escort.
func _on_quest_updated(quest_id: String, stage: int) -> void:
	var q: Dictionary = DataLoader.get_quest(quest_id)
	var qname: String = q.get("name", quest_id)
	if stage == 1:
		hud.toast("New quest: %s" % qname, 3.0)
	elif stage >= Quests.DONE:
		hud.toast("Quest complete: %s  (+%d XP)" % [qname, int(q.get("xp", 20))], 3.0)
	if quest_id == "apologetic_merchant":
		if stage == 1:
			_begin_escort()
		elif stage >= Quests.DONE:
			_escorting = false


# The merchant trails the player to the south gate dropoff.
func _begin_escort() -> void:
	_escorting = true
	_escort_dest = _add_poi(Vector2(704, 880), "escort_dest", "Walk the Merchant to the gate")


func _process(delta: float) -> void:
	if _escorting and is_instance_valid(_merchant) and player != null and not GameManager.ui_blocking:
		var trail: Vector2 = player.global_position + Vector2(0, 36)
		_merchant.global_position = _merchant.global_position.move_toward(trail, 95.0 * delta)
	if PartyManager.is_multiplayer and player != null:
		PartyManager.set_local_presence(player.global_position, zone.id)
		for id: String in _remote_avatars:
			var av: Node2D = _remote_avatars[id]
			av.position = av.position.move_toward(av.get_meta("target", av.position), 140.0 * delta)


func _setup_hud() -> void:
	hud = HUD_SCENE.instantiate()
	add_child(hud)
	player.interaction_target_changed.connect(_on_interaction_target_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_menu") and not GameManager.ui_blocking:
		var pause: Node = PAUSE_SCENE.instantiate()
		add_child(pause)


func _on_interaction_target_changed(label: String) -> void:
	if label.is_empty():
		hud.clear_prompt()
	else:
		hud.set_prompt("[E] %s" % label)


# Grass fill with a simple path cross through the middle of town.
func _build_ground() -> void:
	var sources: Array = ZONE_GROUND.get(zone.id if zone != null else "", [0, 1])
	var floor_src: int = sources[0]
	var path_src: int = sources[1]
	var ground: TileMapLayer = TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = GROUND_TILESET
	_world.add_child(ground)
	_world.move_child(ground, 0)
	for y: int in MAP_H:
		for x: int in MAP_W:
			ground.set_cell(Vector2i(x, y), floor_src, Vector2i(0, 0))
	var mid_y: int = MAP_H / 2
	var mid_x: int = MAP_W / 2
	for x: int in MAP_W:
		ground.set_cell(Vector2i(x, mid_y), path_src, Vector2i(0, 0))
		ground.set_cell(Vector2i(x, mid_y + 1), path_src, Vector2i(0, 0))
	for y: int in MAP_H:
		ground.set_cell(Vector2i(mid_x, y), path_src, Vector2i(0, 0))
		ground.set_cell(Vector2i(mid_x + 1, y), path_src, Vector2i(0, 0))
	_add_boundaries()


# Invisible walls around the map edge so the player can't wander off into the void.
func _add_boundaries() -> void:
	var w: float = MAP_W * TILE
	var h: float = MAP_H * TILE
	var t: float = 24.0
	var rects: Array[Rect2] = [
		Rect2(-t, -t, t, h + t * 2), Rect2(w, -t, t, h + t * 2),
		Rect2(0, -t, w, t), Rect2(0, h, w, t),
	]
	for r: Rect2 in rects:
		var body: StaticBody2D = StaticBody2D.new()
		var cs: CollisionShape2D = CollisionShape2D.new()
		var shape: RectangleShape2D = RectangleShape2D.new()
		shape.size = r.size
		cs.shape = shape
		cs.position = r.position + r.size / 2.0
		body.add_child(cs)
		_world.add_child(body)


func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate()
	player.position = Vector2(MAP_W * TILE / 2.0, MAP_H * TILE / 2.0)
	_world.add_child(player)
	var class_id: String = "fighter"
	if GameManager.player_state != null:
		class_id = GameManager.player_state.class_id
	player.set_character(class_id)


# The sanitation "filter": a pale screen-space film over sanitized zones that
# lifts (fades out) when the zone unlocks.
func _setup_filter() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 1
	_film = ColorRect.new()
	# Color-blind mode uses a neutral grey film instead of the blue wash.
	var tint: Color = Color(0.85, 0.85, 0.85) if Settings.colorblind else FILM_COLOR
	_film.color = Color(tint.r, tint.g, tint.b, 0.0)
	_film.set_anchors_preset(Control.PRESET_FULL_RECT)
	_film.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_film)
	add_child(layer)
	_apply_world_state(false)


func _apply_world_state(animate: bool) -> void:
	if _film == null or zone == null:
		return
	var target: float = 0.0 if zone.is_unlocked(GameManager.firewall_power) else FILM_ALPHA_SANITIZED
	if animate:
		var tween: Tween = create_tween()
		tween.tween_property(_film, "color:a", target, 1.2)
	else:
		_film.color.a = target


func _on_firewall_changed(new_value: int, _old_value: int) -> void:
	_apply_world_state(true)
	# Host shares world unlocks with the party.
	if PartyManager.is_multiplayer and PartyManager.is_host:
		PartyManager.host_set("firewall_power", new_value)


# Buildings, POIs and NPCs for the current zone.
func _build_zone() -> void:
	if zone == null:
		return
	if zone.is_hub:
		_build_welcometon()
	else:
		_build_combat_zone()


const NEXT_ZONE: Dictionary = {"zone1": "zone2", "zone2": "zone3", "zone3": "zone4"}


# A non-hub zone: return portal, encounters, boss POI, a gated portal deeper, and
# zone-specific content (quests, NPCs, puzzles).
func _build_combat_zone() -> void:
	_add_poi(Vector2(704, 980), "travel:welcometon", "Return to Welcometon")
	if not zone.enemies.is_empty():
		_spawn_encounters()
	_add_boss_poi()
	if NEXT_ZONE.has(zone.id):
		var next_id: String = NEXT_ZONE[zone.id]
		var next_zone: ZoneDef = DataLoader.get_zone(next_id)
		var next_name: String = next_zone.display_name if next_zone != null else next_id
		_add_poi(Vector2(704, 60), "next:" + next_id, "Deeper -> %s" % next_name)
	match zone.id:
		"zone1":
			_build_meadows()
		"zone2":
			_build_dungeon()
		"zone3":
			_build_castle()
		"zone4":
			_build_server()


func _build_meadows() -> void:
	_add_npc("farmer", Vector2(280, 560))
	_merchant = _add_npc("apologetic_merchant", Vector2(1100, 560))
	if Quests.quest_active("apologetic_merchant"):
		_begin_escort()  # resume if re-entering mid-escort
	_add_poi(Vector2(1180, 360), "find_turnips", "Search the turnip patch")
	_add_poi(Vector2(360, 820), "raven_grave", "A small gravestone")  # Ashvale egg


func _build_dungeon() -> void:
	_add_poi(Vector2(1180, 360), "find_usb", "Examine the ancient pedestal")
	_add_poi(Vector2(300, 760), "birdman_poster", "Read the wanted poster")  # Ashvale egg
	_add_poi(Vector2(900, 760), "plague_mask", "Open the dusty chest")  # Ashvale egg


func _build_castle() -> void:
	_add_poi(Vector2(300, 360), "bronze_lantern", "The fire-damaged wing")  # Ashvale egg


func _build_server() -> void:
	pass


# Hall Monitor Prime: a chase puzzle. Lead the monitor across all three patrol
# checkpoints to loop its policy and free it.
func _spawn_hall_monitor() -> void:
	_lure_active = true
	GameManager.encounters_paused = true  # no random fights mid-puzzle
	var markers: Array[Node2D] = []
	for pos: Vector2 in [Vector2(300, 300), Vector2(1100, 320), Vector2(700, 820)]:
		var m: Node2D = Node2D.new()
		m.position = pos
		var glyph: Polygon2D = Polygon2D.new()
		glyph.polygon = PackedVector2Array([Vector2(0, -26), Vector2(22, 0), Vector2(0, 26), Vector2(-22, 0)])
		glyph.color = Color(1, 1, 0.35, 0.85)
		m.add_child(glyph)
		var cap: Label = Label.new()
		cap.text = "CHECKPOINT"
		cap.position = Vector2(-70, -56)
		cap.size = Vector2(140, 18)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.add_theme_font_size_override("font_size", 12)
		cap.add_theme_color_override("font_outline_color", Color.BLACK)
		cap.add_theme_constant_override("outline_size", 4)
		m.add_child(cap)
		_world.add_child(m)
		markers.append(m)
	var monitor: HallMonitor = HallMonitor.new()
	monitor.position = Vector2(700, 220)
	_world.add_child(monitor)
	monitor.setup(player, markers)
	monitor.progress.connect(func(lit: int, total: int) -> void:
		hud.toast("Checkpoint %d / %d looped!" % [lit, total]))
	monitor.caught.connect(_on_lure_complete.bind(monitor, markers))
	hud.toast("HALL_MONITOR_PRIME can't leave its patrol. Lead it over the 3 glowing CHECKPOINTS to loop it!", 4.0)


func _on_lure_complete(monitor: Node, markers: Array) -> void:
	_lure_active = false
	GameManager.encounters_paused = false
	for m: Node in markers:
		m.queue_free()
	monitor.queue_free()
	Combat.resolve_boss("hall_monitor_prime")
	_on_encounter_resolved("victory")
	_on_boss_freed("hall_monitor_prime")


func _show_credits() -> void:
	var credits: Node = CREDITS_SCENE.instantiate()
	get_tree().root.add_child(credits)


# A boss confrontation POI for the current zone (uses zone.boss).
func _add_boss_poi() -> void:
	if zone.boss.is_empty():
		return
	var beaten: bool = zone.boss in GameManager.bosses_defeated
	var ed: EnemyDef = DataLoader.get_enemy(zone.boss)
	var boss_name: String = ed.stats_for(GameManager.firewall_power).get("name", zone.boss) if ed != null else zone.boss
	var label: String = "This place feels free now" if beaten else "Confront %s" % boss_name
	_add_poi(Vector2(704, 150), "boss", label)


# Convention: each zone's dialogue file holds "<boss_id>" (intro) and
# "<boss_id>_defeated" (freed/grateful) titles.
func _zone_dialogue_path() -> String:
	return "res://dialogue/%s.dialogue" % zone.id


func _start_boss_fight() -> void:
	if zone.boss in GameManager.bosses_defeated:
		hud.toast("The firmware is off. They're free now.")
		return
	if _lure_active:
		hud.toast("It's already chasing you — lead it over the 3 glowing checkpoints!")
		return
	var ed: EnemyDef = DataLoader.get_enemy(zone.boss)
	GameManager.ui_blocking = true
	match (ed.defeat_mechanic if ed != null else ""):
		"answer_questions":
			_play_dialogue(zone.boss, _after_dialogue_boss)
		"lure_into_loop":
			_play_dialogue(zone.boss, _after_lure_intro)
		_:
			_play_dialogue(zone.boss, _after_combat_intro)


func _play_dialogue(title: String, on_done: Callable) -> void:
	var path: String = _zone_dialogue_path()
	if not ResourceLoader.exists(path):
		if on_done.is_valid():
			on_done.call()
		return
	var balloon: Node = BALLOON_SCENE.instantiate()
	add_child(balloon)
	if on_done.is_valid():
		balloon.tree_exited.connect(on_done, CONNECT_ONE_SHOT)
	balloon.start(load(path), title, [GameManager, Quests])


# Standard combat bosses (VICE_PRINCIPAL, ADMIN-9).
func _after_combat_intro() -> void:
	GameManager.ui_blocking = false
	var boss_id: String = zone.boss
	var result: String = await Combat.run_encounter([boss_id])
	_on_encounter_resolved(result)
	if result == "victory":
		_on_boss_freed(boss_id)


# Dialogue-battle boss (Wellness Counselor): the intro IS the multiple-choice
# survey; it sets boss_resolved_<id> when out-absurded.
func _after_dialogue_boss() -> void:
	GameManager.ui_blocking = false
	if GameManager.get_flag("boss_resolved_" + zone.boss):
		Combat.resolve_boss(zone.boss)
		_on_encounter_resolved("victory")
		_on_boss_freed(zone.boss)


# Lure-into-loop boss (Hall Monitor Prime): spawn the patrol puzzle.
func _after_lure_intro() -> void:
	GameManager.ui_blocking = false
	_spawn_hall_monitor()


# Possessed-by-policy: on defeat the staffer is freed and thanks you. The final
# boss (ADMIN-9) rolls into the melancholy cutscene + credits.
func _on_boss_freed(boss_id: String) -> void:
	var ed: EnemyDef = DataLoader.get_enemy(boss_id)
	if ed != null and ed.recruitable:
		GameManager.set_flag("ally_" + boss_id, true)
	GameManager.ui_blocking = true
	var is_final: bool = ed != null and ed.final_boss
	_play_dialogue(boss_id + "_defeated", func() -> void:
		GameManager.ui_blocking = false
		if is_final:
			_show_credits())


# Place a few enemy encounters for a combat zone (used by Zone 1+ in M4).
func _spawn_encounters() -> void:
	var positions: Array[Vector2] = [
		Vector2(360, 300), Vector2(960, 320), Vector2(520, 760), Vector2(1040, 700),
	]
	for i: int in positions.size():
		var enemy_id: String = zone.enemies[i % zone.enemies.size()]
		var ed: EnemyDef = DataLoader.get_enemy(enemy_id)
		if ed == null:
			continue
		var enc: EnemyEncounter = EnemyEncounter.new()
		enc.position = positions[i]
		enc.enemy_ids = [enemy_id]
		var sprite_id: String = ed.stats_for(GameManager.firewall_power).get("sprite", enemy_id)
		var tex_path: String = "res://assets/enemies/%s.png" % sprite_id
		if ResourceLoader.exists(tex_path):
			var spr: Sprite2D = Sprite2D.new()
			spr.texture = load(tex_path)
			spr.scale = Vector2(0.4, 0.4)
			spr.position = Vector2(0, -24)
			enc.add_child(spr)
		var cs: CollisionShape2D = CollisionShape2D.new()
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = 26.0
		cs.shape = circle
		enc.add_child(cs)
		enc.resolved.connect(_on_encounter_resolved)
		_world.add_child(enc)


func _on_encounter_resolved(result: String) -> void:
	Audio.play_music("explore")
	if result == "victory":
		Audio.sfx("success")
		var r: Dictionary = Combat.last_rewards
		var extra: String = "  Level up!" if r.get("leveled", false) else ""
		hud.toast("Victory! +%d XP, +%d Bytes%s" % [r.get("xp", 0), r.get("bytes", 0), extra])
		hud.refresh()
	elif result == "defeat":
		player_defeated.emit()


func _build_welcometon() -> void:
	# Buildings (sprite + solid collision).
	_add_building(Vector2(320, 360), "res://assets/sprites/buildings/inn.png")
	_add_building(Vector2(1088, 360), "res://assets/sprites/buildings/shop.png")
	_add_building(Vector2(320, 820), "res://assets/sprites/buildings/library.png")

	# POIs (interaction triggers).
	_add_poi(Vector2(320, 470), "inn", "Rest at the Inn")
	_add_poi(Vector2(1088, 470), "shop", "Browse the Shop")
	_add_poi(Vector2(320, 900), "library", "Visit the Library")
	_add_poi(Vector2(640, 360), "quest_board", "Read the Quest Board")
	_add_poi(Vector2(800, 360), "bulletin_board", "Check the Bulletin Board")
	_add_poi(Vector2(1088, 900), "portal_alley", "Portal Alley (locked)")
	_add_poi(Vector2(704, 120), "travel:zone1", "Leave Town -> The Meadows")

	# NPCs.
	_add_npc("cerys", Vector2(420, 470))
	_add_npc("gerald", Vector2(980, 470))
	_add_npc("chronicler", Vector2(440, 900))
	_add_npc("definitely_not_kevin", Vector2(1000, 900))


# A building: sprite anchored at its base (for y-sort) plus a solid footprint.
func _add_building(base: Vector2, tex_path: String) -> void:
	if not ResourceLoader.exists(tex_path):
		return
	var tex: Texture2D = load(tex_path)
	var node: Node2D = Node2D.new()
	node.position = base
	var spr: Sprite2D = Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.offset = Vector2(-tex.get_width() / 2.0, -tex.get_height())
	node.add_child(spr)
	var body: StaticBody2D = StaticBody2D.new()
	var cs: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(minf(tex.get_width() - 40.0, 200.0), 70.0)
	cs.shape = rect
	cs.position = Vector2(0, -40)
	body.add_child(cs)
	node.add_child(body)
	_world.add_child(node)


func _add_poi(pos: Vector2, poi_id: String, label: String) -> POI:
	var poi: POI = POI.new()
	poi.position = pos
	poi.poi_id = poi_id
	poi.label = label
	var cs: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 30.0
	cs.shape = circle
	poi.add_child(cs)
	# Visible marker so the player can SEE there's something here. Portals get a
	# bigger blue glyph; other POIs a yellow diamond. Both carry a floating label.
	var is_portal: bool = poi_id.begins_with("travel:") or poi_id.begins_with("next:")
	var marker: Polygon2D = Polygon2D.new()
	var s: float = 22.0 if is_portal else 14.0
	marker.polygon = PackedVector2Array([Vector2(0, -s), Vector2(s * 0.8, 0), Vector2(0, s), Vector2(-s * 0.8, 0)])
	marker.color = Color(0.4, 0.7, 1.0, 0.95) if is_portal else Color(1.0, 0.85, 0.3, 0.9)
	marker.position = Vector2(0, -8)
	poi.add_child(marker)
	var lbl: Label = Label.new()
	lbl.text = label
	lbl.position = Vector2(-110, -52)
	lbl.size = Vector2(220, 20)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 4)
	poi.add_child(lbl)
	poi.triggered.connect(_on_poi_triggered)
	_world.add_child(poi)
	return poi


func _add_npc(npc_id: String, pos: Vector2) -> NPC:
	var npc: NPC = NPC_SCENE.instantiate()
	npc.npc_id = npc_id
	npc.position = pos
	npc.service_requested.connect(_on_npc_service)
	_world.add_child(npc)
	return npc


func _on_npc_service(service: String) -> void:
	if service == "shop" or service == "shop_illegal":
		_open_shop()


func _on_poi_triggered(poi_id: String) -> void:
	if poi_id.begins_with("travel:"):
		zone_change_requested.emit(poi_id.substr(7))
		return
	if poi_id.begins_with("next:"):
		if zone.boss.is_empty() or zone.boss in GameManager.bosses_defeated:
			zone_change_requested.emit(poi_id.substr(5))
		else:
			hud.toast("The way deeper is sealed until the firewall here weakens.")
		return
	match poi_id:
		"inn":
			_rest_at_inn()
		"shop":
			_open_shop()
		"find_turnips":
			_search_turnips()
		"escort_dest":
			_dropoff_merchant()
		"find_usb":
			_search_usb()
		"birdman_poster":
			hud.toast("WANTED: 'The Birdman'. Crimes: unspecified. Reward: a knowing nod.", 3.0)
		"plague_mask":
			_open_plague_chest()
		"bronze_lantern":
			hud.toast("A scorched note in the rubble: 'The Bronze Lantern — closed indefinitely.'", 3.0)
		"raven_grave":
			hud.toast("A weathered gravestone. A raven watches from atop it, unbothered.", 3.0)
		"boss":
			_start_boss_fight()
		"quest_board":
			var lines: Array[String] = Quests.zone_quest_status("zone1")
			hud.toast("Quest Board — The Meadows:\n" + "\n".join(lines), 4.0)
		"library":
			hud.toast("The Library hums with tutorials nobody reads.")
		"bulletin_board":
			hud.toast("Bulletin Board: community mods will appear here after the game ends.")
		"portal_alley":
			hud.toast("Portal Alley is sealed until the Firewall falls.")


func _search_turnips() -> void:
	if Quests.quest_stage("turnips") == 1:
		Quests.set_quest_stage("turnips", 2)
		hud.toast("You found Farmer Bramble's turnips! Return them to him.")
	elif Quests.quest_done("turnips"):
		hud.toast("Just an empty turnip patch now.")
	else:
		hud.toast("A disturbed patch of turnips. Someone should ask the farmer.")


func _dropoff_merchant() -> void:
	if not Quests.quest_active("apologetic_merchant"):
		hud.toast("The town gate. Nothing to do here right now.")
		return
	Quests.complete_quest("apologetic_merchant")  # toast comes from _on_quest_updated
	if is_instance_valid(_escort_dest):
		_escort_dest.queue_free()


func _search_usb() -> void:
	if not Quests.quest_done("ancient_artifact"):
		Quests.start_quest("ancient_artifact")
		Quests.complete_quest("ancient_artifact")
		hud.toast("You retrieved the Ancient Artifact — a USB drive. For some reason.")
	else:
		hud.toast("An empty pedestal with a single USB port, humming faintly.")


func _open_plague_chest() -> void:
	if GameManager.get_flag("found_plague_mask"):
		hud.toast("An empty chest.")
		return
	GameManager.set_flag("found_plague_mask", true)
	if GameManager.player_state != null:
		GameManager.player_state.inventory.append("plague_mask")
	hud.toast("Inside: a Plague Doctor Mask. (A cosmetic. Some of you know exactly why.)", 3.0)


func _rest_at_inn() -> void:
	var ps: PlayerState = GameManager.player_state
	if ps != null:
		ps.hp = ps.max_hp()
		ps.mp = ps.max_mp()
	SaveManager.save()
	hud.refresh()
	hud.toast("Rested. HP/MP restored. Game saved.")


func _open_shop() -> void:
	var shop: Shop = SHOP_SCENE.instantiate()
	add_child(shop)
	shop.closed.connect(func() -> void: hud.refresh())
	shop.open()
