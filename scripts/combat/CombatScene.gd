# === CombatScene.gd ===
# The battle view. Owns a CombatSystem, renders party (left) / enemies (right),
# the initiative queue, action menu, combat log, and target/skill/item choosers.
# Emits `finished(result)` so the encounter orchestrator can apply rewards.
class_name CombatScene
extends Control

signal finished(result: String)

var system: CombatSystem
var _current: Combatant = null
var _party_panels: Dictionary = {}   # Combatant -> Label
var _enemy_panels: Dictionary = {}   # Combatant -> Label

@onready var _party_box: VBoxContainer = %PartyBox
@onready var _enemy_box: VBoxContainer = %EnemyBox
@onready var _initiative_box: HBoxContainer = %InitiativeBox
@onready var _log: RichTextLabel = %Log
@onready var _action_menu: VBoxContainer = %ActionMenu
@onready var _choice_box: VBoxContainer = %ChoiceBox
@onready var _banner: Label = %Banner


## Start a battle with the given combatants. Call after the scene is in the tree.
func setup(party: Array[Combatant], enemies: Array[Combatant]) -> void:
	system = CombatSystem.new()
	add_child(system)
	system.combat_log.connect(_on_log)
	system.turn_started.connect(_on_turn_started)
	system.state_changed.connect(_refresh)
	system.awaiting_action.connect(_on_awaiting_action)
	system.combat_ended.connect(_on_combat_ended)
	_build_party_panels(party)
	_build_enemy_panels(enemies)
	_banner.visible = false
	_hide_menus()
	system.start(party, enemies)


func _build_party_panels(party: Array[Combatant]) -> void:
	for c: Combatant in party:
		var box: VBoxContainer = VBoxContainer.new()
		var portrait: TextureRect = TextureRect.new()
		portrait.custom_minimum_size = Vector2(96, 96)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture = _portrait_for(c)
		box.add_child(portrait)
		var label: Label = Label.new()
		box.add_child(label)
		_party_box.add_child(box)
		_party_panels[c] = label
	_refresh()


func _build_enemy_panels(enemies: Array[Combatant]) -> void:
	for c: Combatant in enemies:
		var box: VBoxContainer = VBoxContainer.new()
		var sprite: TextureRect = TextureRect.new()
		sprite.custom_minimum_size = Vector2(140, 130)
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if ResourceLoader.exists(c.sprite_ref):
			sprite.texture = load(c.sprite_ref)
		box.add_child(sprite)
		var label: Label = Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(label)
		_enemy_box.add_child(box)
		_enemy_panels[c] = label
	_refresh()


func _portrait_for(c: Combatant) -> Texture2D:
	if c.sprite_kind == "lpc":
		var path: String = "res://assets/chars/%s_walk.png" % c.sprite_ref
		if ResourceLoader.exists(path):
			var at: AtlasTexture = AtlasTexture.new()
			at.atlas = load(path)
			at.region = Rect2(0, 192, 64, 64)  # right-facing (row 3) standing frame
			return at
	elif ResourceLoader.exists(c.sprite_ref):
		return load(c.sprite_ref)
	return null


func _refresh() -> void:
	for c: Combatant in _party_panels:
		var status: String = _status_suffix(c)
		_party_panels[c].text = "%s\n%d/%d HP  %d/%d MP%s" % [c.display_name, c.hp, c.max_hp, c.mp, c.max_mp, status]
	for c: Combatant in _enemy_panels:
		var dead: String = "  (defeated)" if not c.is_alive() else ""
		_enemy_panels[c].text = "%s\n%d/%d HP%s%s" % [c.display_name, c.hp, c.max_hp, _status_suffix(c), dead]


func _status_suffix(c: Combatant) -> String:
	var marks: Array[String] = []
	if c.defending:
		marks.append("DEF")
	for st: Dictionary in c.statuses:
		marks.append(str(st.get("name", st.kind)))
	return "  [%s]" % ", ".join(marks) if not marks.is_empty() else ""


func _on_log(text: String) -> void:
	_log.append_text(text + "\n")


func _on_turn_started(c: Combatant) -> void:
	_current = c
	var names: Array[String] = []
	for combatant: Combatant in system._initiative():
		var marker: String = "> " if combatant == c else ""
		names.append(marker + combatant.display_name)
	for child: Node in _initiative_box.get_children():
		child.queue_free()
	var lbl: Label = Label.new()
	lbl.text = "Turn: " + "   ".join(names)
	_initiative_box.add_child(lbl)


func _on_awaiting_action(c: Combatant) -> void:
	_current = c
	_action_menu.visible = true
	_choice_box.visible = false


func _hide_menus() -> void:
	_action_menu.visible = false
	_choice_box.visible = false


# === Action buttons (wired in the scene) ===
func _on_attack_pressed() -> void:
	_choose_enemy_target("attack")


func _on_skill_pressed() -> void:
	_populate_choices()
	var class_def: ClassDef = DataLoader.get_class_def(_current.player_state.class_id)
	var skill_ids: Array[String] = [class_def.sanitized_skill]
	if GameManager.firewall_power <= 0:
		skill_ids.append_array(class_def.unlocked_skills)
	for sid: String in skill_ids:
		var skill: SkillDef = DataLoader.get_skill(sid)
		if skill == null:
			continue
		var btn: Button = Button.new()
		btn.text = "%s (%d MP)" % [skill.name, skill.mp_cost]
		btn.disabled = _current.mp < skill.mp_cost
		btn.pressed.connect(_on_skill_chosen.bind(sid))
		_choice_box.add_child(btn)
	_add_back_button()


func _on_skill_chosen(skill_id: String) -> void:
	var skill: SkillDef = DataLoader.get_skill(skill_id)
	if skill.target == "enemy":
		_choose_enemy_target("skill", skill_id)
	else:
		_submit("skill", null, skill_id)


func _on_item_pressed() -> void:
	_populate_choices()
	var ps: PlayerState = _current.player_state
	var seen: Dictionary = {}
	for item_id: String in ps.inventory:
		if seen.has(item_id):
			continue
		seen[item_id] = true
		var item: ItemDef = DataLoader.get_item(item_id)
		if item == null or item.is_equipment():
			continue
		var count: int = ps.inventory.count(item_id)
		var btn: Button = Button.new()
		btn.text = "%s x%d" % [item.name, count]
		btn.pressed.connect(_submit.bind("item", null, "", item_id))
		_choice_box.add_child(btn)
	_add_back_button()


func _on_defend_pressed() -> void:
	_submit("defend")


func _on_flee_pressed() -> void:
	_submit("flee")


func _choose_enemy_target(action: String, skill_id: String = "") -> void:
	var living: Array[Combatant] = system._living(system.enemies)
	if living.size() == 1:
		_submit(action, living[0], skill_id)
		return
	_populate_choices()
	for enemy: Combatant in living:
		var btn: Button = Button.new()
		btn.text = enemy.display_name
		btn.pressed.connect(_submit.bind(action, enemy, skill_id, ""))
		_choice_box.add_child(btn)
	_add_back_button()


func _populate_choices() -> void:
	_action_menu.visible = false
	_choice_box.visible = true
	for child: Node in _choice_box.get_children():
		child.queue_free()


func _add_back_button() -> void:
	var back: Button = Button.new()
	back.text = "Back"
	back.pressed.connect(_on_awaiting_action.bind(_current))
	_choice_box.add_child(back)


func _submit(action: String, target: Combatant = null, skill_id: String = "", item_id: String = "") -> void:
	_hide_menus()
	system.submit_action(action, target, skill_id, item_id)


func _on_combat_ended(result: String) -> void:
	_hide_menus()
	_refresh()
	var text: String = {"victory": "VICTORY!", "defeat": "DEFEATED...", "fled": "Got away!"}.get(result, result)
	_banner.text = text
	_banner.visible = true
	await get_tree().create_timer(1.5).timeout
	finished.emit(result)
