# === Shop.gd ===
# Gerald's shop. Lists items available at the current firewall power (data-driven
# from items.json), spends Bytes, and equips/stocks purchases. Blocks exploration
# input while open.
class_name Shop
extends CanvasLayer

signal closed()

@onready var _bark: Label = %Bark
@onready var _bytes_label: Label = %BytesLabel
@onready var _item_list: VBoxContainer = %ItemList
@onready var _feedback: Label = %Feedback


func open() -> void:
	GameManager.ui_blocking = true
	_refresh()


func _refresh() -> void:
	_bark.text = _gerald_bark(GameManager.firewall_power)
	_bytes_label.text = "Bytes: %d" % _player().bytes
	_feedback.text = ""
	for child: Node in _item_list.get_children():
		child.queue_free()
	for item: ItemDef in DataLoader.items_available(GameManager.firewall_power):
		_item_list.add_child(_make_row(item))


func _make_row(item: ItemDef) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var info: Label = Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.clip_text = true  # never push the Buy button off the panel
	info.tooltip_text = item.description
	info.text = "%s  —  %d B" % [item.name, item.cost]
	row.add_child(info)
	var buy: Button = Button.new()
	var affordable: bool = _player() != null and _player().bytes >= item.cost
	buy.text = "Buy" if affordable else "%d B" % item.cost
	buy.disabled = not affordable
	buy.custom_minimum_size = Vector2(90, 0)
	buy.pressed.connect(_on_buy.bind(item.id))
	row.add_child(buy)
	return row


func _on_buy(item_id: String) -> void:
	var item: ItemDef = DataLoader.get_item(item_id)
	var ps: PlayerState = _player()
	if item == null or ps == null:
		return
	if ps.bytes < item.cost:
		_feedback.text = "Not enough Bytes."
		return
	ps.bytes -= item.cost
	Audio.sfx("coin")
	if item.is_equipment():
		ps.equip(item_id)
		_feedback.text = "Equipped %s." % item.name
	else:
		ps.inventory.append(item_id)
		_feedback.text = "Bought %s." % item.name
	_refresh()


func _on_close_pressed() -> void:
	GameManager.ui_blocking = false
	closed.emit()
	queue_free()


func _player() -> PlayerState:
	return GameManager.player_state


func _gerald_bark(power: int) -> String:
	if power >= 100:
		return "I can only sell you foam training implements. School policy."
	elif power >= 75:
		return "I... found some real swords in the back. I probably shouldn't. But."
	elif power >= 50:
		return "Swords! Axes! Reasonable prices! Don't tell the principal."
	return "WEAPONS EMPORIUM. I'VE BEEN WAITING MY WHOLE LIFE FOR THIS."
