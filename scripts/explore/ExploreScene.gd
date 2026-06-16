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
const GROUND_TILESET: TileSet = preload("res://assets/tilesets/ground.tres")
const SOURCE_GRASS: int = 0
const SOURCE_PATH: int = 1
const TILE: int = 32
const MAP_W: int = 44
const MAP_H: int = 32

signal player_defeated()

var player: Player
var zone: ZoneDef
var hud: HUD

@onready var _world: Node2D = $World


func _ready() -> void:
	var zone_id: String = GameManager.current_zone
	zone = DataLoader.get_zone(zone_id)
	_build_ground()
	_spawn_player()
	_build_zone()
	_setup_hud()


func _setup_hud() -> void:
	hud = HUD_SCENE.instantiate()
	add_child(hud)
	player.interaction_target_changed.connect(_on_interaction_target_changed)


func _on_interaction_target_changed(label: String) -> void:
	if label.is_empty():
		hud.clear_prompt()
	else:
		hud.set_prompt("[E] %s" % label)


# Grass fill with a simple path cross through the middle of town.
func _build_ground() -> void:
	var ground: TileMapLayer = TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = GROUND_TILESET
	_world.add_child(ground)
	_world.move_child(ground, 0)
	for y: int in MAP_H:
		for x: int in MAP_W:
			ground.set_cell(Vector2i(x, y), SOURCE_GRASS, Vector2i(0, 0))
	var mid_y: int = MAP_H / 2
	var mid_x: int = MAP_W / 2
	for x: int in MAP_W:
		ground.set_cell(Vector2i(x, mid_y), SOURCE_PATH, Vector2i(0, 0))
		ground.set_cell(Vector2i(x, mid_y + 1), SOURCE_PATH, Vector2i(0, 0))
	for y: int in MAP_H:
		ground.set_cell(Vector2i(mid_x, y), SOURCE_PATH, Vector2i(0, 0))
		ground.set_cell(Vector2i(mid_x + 1, y), SOURCE_PATH, Vector2i(0, 0))


func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate()
	player.position = Vector2(MAP_W * TILE / 2.0, MAP_H * TILE / 2.0)
	_world.add_child(player)
	var class_id: String = "fighter"
	if GameManager.player_state != null:
		class_id = GameManager.player_state.class_id
	player.set_character(class_id)


# Buildings, POIs and NPCs for the current zone. Filled per-zone (Welcometon: M2).
func _build_zone() -> void:
	if zone == null:
		return
	if zone.is_hub:
		_build_welcometon()
	elif not zone.enemies.is_empty():
		_spawn_encounters()


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
	if result == "victory":
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


func _add_poi(pos: Vector2, poi_id: String, label: String) -> void:
	var poi: POI = POI.new()
	poi.position = pos
	poi.poi_id = poi_id
	poi.label = label
	var cs: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 28.0
	cs.shape = circle
	poi.add_child(cs)
	poi.triggered.connect(_on_poi_triggered)
	_world.add_child(poi)


func _add_npc(npc_id: String, pos: Vector2) -> void:
	var npc: NPC = NPC_SCENE.instantiate()
	npc.npc_id = npc_id
	npc.position = pos
	_world.add_child(npc)


func _on_poi_triggered(poi_id: String) -> void:
	match poi_id:
		"inn":
			_rest_at_inn()
		"shop":
			_open_shop()
		"quest_board":
			hud.toast("Quest Board: Defeat the Firewall. (Real quests await in Zone 1.)")
		"library":
			hud.toast("The Library hums with tutorials nobody reads.")
		"bulletin_board":
			hud.toast("Bulletin Board: community mods will appear here after the game ends.")
		"portal_alley":
			hud.toast("Portal Alley is sealed until the Firewall falls.")


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
