# === HUD.gd ===
# Exploration HUD: party HP (top-left), zone name + Firewall Power gauge
# (top-right), interaction prompt (bottom). Reacts to firewall-power changes.
class_name HUD
extends CanvasLayer

@onready var _party_list: VBoxContainer = %PartyList
@onready var _zone_name: Label = %ZoneName
@onready var _firewall_gauge: ProgressBar = %FirewallGauge
@onready var _firewall_label: Label = %FirewallLabel
@onready var _prompt: Label = %Prompt
@onready var _toast: Label = %Toast


func _ready() -> void:
	GameManager.firewall_power_changed.connect(_on_firewall_changed)
	_style_overlay(_toast)
	_style_overlay(_prompt)
	clear_prompt()
	_toast.text = ""
	refresh()


# Dark rounded backing + outline so overlay text reads on any background.
func _style_overlay(label: Label) -> void:
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.66)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	label.add_theme_stylebox_override("normal", sb)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## Show a transient message (e.g. "Game saved", "Equipped Foam Sword").
func toast(text: String, seconds: float = 2.0) -> void:
	_toast.text = text
	var timer: SceneTreeTimer = get_tree().create_timer(seconds)
	timer.timeout.connect(func() -> void:
		if _toast.text == text:
			_toast.text = "")


func refresh() -> void:
	var zone: ZoneDef = DataLoader.get_zone(GameManager.current_zone)
	_zone_name.text = zone.display_name if zone != null else GameManager.current_zone
	_update_gauge(GameManager.firewall_power)
	_refresh_party()


func _update_gauge(power: int) -> void:
	_firewall_gauge.value = power
	_firewall_label.text = "Firewall: %d%%" % power


func _refresh_party() -> void:
	for child: Node in _party_list.get_children():
		child.queue_free()
	var ps: PlayerState = GameManager.player_state
	if ps != null:
		_party_list.add_child(_make_hp_row(ps.player_name, ps.hp, ps.max_hp()))


func _make_hp_row(name: String, hp: int, max_hp: int) -> Label:
	var row: Label = Label.new()
	row.text = "%s  %d/%d HP" % [name, hp, max_hp]
	return row


func set_prompt(text: String) -> void:
	_prompt.text = text
	_prompt.visible = not text.is_empty()


func clear_prompt() -> void:
	set_prompt("")


func _on_firewall_changed(new_value: int, _old_value: int) -> void:
	_update_gauge(new_value)
	refresh()
