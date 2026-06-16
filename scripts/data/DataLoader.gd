# === DataLoader.gd ===
# Loads all /data JSON into typed definition objects. Static + lazily cached, so
# any script can call DataLoader.get_class("rogue") etc. without an autoload.
# Content is data-driven: engine reads these, never hardcodes them.
class_name DataLoader
extends RefCounted

const CLASSES_PATH: String = "res://data/classes.json"
const ITEMS_PATH: String = "res://data/items.json"
const SKILLS_PATH: String = "res://data/skills.json"
const ENEMIES_PATH: String = "res://data/enemies.json"
const NPCS_PATH: String = "res://data/npcs.json"
const ZONES_DIR: String = "res://data/zones/"

static var _classes: Dictionary = {}   # id -> ClassDef
static var _items: Dictionary = {}     # id -> ItemDef
static var _skills: Dictionary = {}    # id -> SkillDef
static var _enemies: Dictionary = {}   # id -> EnemyDef
static var _zones: Dictionary = {}     # id -> ZoneDef
static var _npcs: Dictionary = {}      # id -> Dictionary (raw)
static var _loaded: bool = false


## Parse everything. Idempotent — safe to call from many places at boot.
static func load_all() -> void:
	if _loaded:
		return
	for entry: Dictionary in _read_json(CLASSES_PATH).values():
		_classes[entry["id"]] = ClassDef.from_dict(entry)
	for entry: Dictionary in _read_json(ITEMS_PATH).values():
		_items[entry["id"]] = ItemDef.from_dict(entry)
	for entry: Dictionary in _read_json(SKILLS_PATH).values():
		_skills[entry["id"]] = SkillDef.from_dict(entry)
	for entry: Dictionary in _read_json(ENEMIES_PATH).values():
		_enemies[entry["id"]] = EnemyDef.from_dict(entry)
	for entry: Dictionary in _read_json(NPCS_PATH).values():
		_npcs[entry["id"]] = entry
	for zone_file: String in _zone_files():
		var zd: Dictionary = _read_json(ZONES_DIR + zone_file)
		_zones[zd["id"]] = ZoneDef.from_dict(zd)
	_loaded = true


static func reload() -> void:
	_loaded = false
	_classes.clear(); _items.clear(); _skills.clear()
	_enemies.clear(); _zones.clear(); _npcs.clear()
	load_all()


# === Accessors ===
static func get_class_def(id: String) -> ClassDef:
	load_all()
	return _classes.get(id)

static func get_item(id: String) -> ItemDef:
	load_all()
	return _items.get(id)

static func get_skill(id: String) -> SkillDef:
	load_all()
	return _skills.get(id)

static func get_enemy(id: String) -> EnemyDef:
	load_all()
	return _enemies.get(id)

static func get_zone(id: String) -> ZoneDef:
	load_all()
	return _zones.get(id)

static func get_npc(id: String) -> Dictionary:
	load_all()
	return _npcs.get(id, {})

static func all_classes() -> Array:
	load_all()
	return _classes.values()

static func all_items() -> Array:
	load_all()
	return _items.values()

## Shop stock available at the given firewall power (equipment + consumables).
static func items_available(firewall_power: int) -> Array:
	load_all()
	var out: Array = []
	for item: ItemDef in _items.values():
		if item.is_available(firewall_power) and item.cost > 0:
			out.append(item)
	return out


# === Internals ===
static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("DataLoader: missing data file %s" % path)
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_error("DataLoader: %s is not a JSON object" % path)
	return {}


static func _zone_files() -> Array[String]:
	var files: Array[String] = []
	var dir: DirAccess = DirAccess.open(ZONES_DIR)
	if dir == null:
		push_error("DataLoader: cannot open %s" % ZONES_DIR)
		return files
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			files.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	return files
