class_name DialogueBalloon extends CanvasLayer
## Dialogue balloon for Firewall Quest, driven by Nathan Hoad's Dialogue Manager.
## Ported from Nightspawn (originally the RDC demo balloon): per-character font /
## size / color (regular + bold/italic) resolved from data/characters/<id>.json.
## Defaults to PANEL mode (fixed bottom banner); scenes can opt into BALLOON mode
## to float near the speaking character. The speaker is resolved against the live
## "player" group and the "npc" group (NPCs expose an `npc_name`).

## The action to use for advancing the dialogue
@export var next_action: StringName = &"interact"

## The action to use to skip typing the dialogue
@export var skip_action: StringName = &"ui_cancel_game"

## The dialogue resource
var resource: DialogueResource
## Temporary game states
var temporary_game_states: Array = []

## See if we are waiting for the player
var is_waiting_for_input: bool = false

## See if we are running a long mutation and should hide the balloon
var will_hide_balloon: bool = false

## A dictionary to store any ephemeral variables
var locals: Dictionary = {}

var _locale: String = TranslationServer.get_locale()

## The current line
var dialogue_line: DialogueLine:
	set(value):
		if value:
			dialogue_line = value
			apply_dialogue_line()
		else:
			# The dialogue has finished so close the balloon
			queue_free()
	get:
		return dialogue_line

## A cooldown timer for delaying the balloon hide when encountering a mutation.
var mutation_cooldown: Timer = Timer.new()

@onready var balloon: Control = %Balloon
@onready var character_label: RichTextLabel = %CharacterLabel
@onready var dialogue_label: DialogueLabel = %DialogueLabel
@onready var responses_menu: DialogueResponsesMenu = %ResponsesMenu

# Store references to loaded fonts to avoid reloading
var loaded_fonts: Dictionary = {}

const BALLOON_WIDTH: float = 380.0
const PANEL_WIDTH: float = 700.0          # wide bottom banner for PANEL mode
const BALLOON_MARGIN: float = 16.0
const DEFAULT_FONT := "res://assets/fonts/System/FantasticBoogaloo-GDlq.ttf"

# Presentation mode (per-scene, set by the caller). PANEL is a fixed wide banner
# pinned bottom-centre (classic-JRPG feel) — Firewall Quest's default. BALLOON
# floats near the speaker; scenes can opt into it when position carries meaning.
# In PANEL mode the speaker-anchoring + HUD scoring are skipped, but per-speaker
# font/size/color styling still applies.
enum Mode { BALLOON, PANEL }
var presentation_mode: int = Mode.PANEL

var _current_speaker: Node2D = null  # set during font application, used for positioning

func _ready() -> void:
	balloon.hide()
	DialogueManager.mutated.connect(_on_mutated)
	if responses_menu.next_action.is_empty():
		responses_menu.next_action = next_action
	if ResourceLoader.exists(DEFAULT_FONT):
		loaded_fonts["Default"] = load(DEFAULT_FONT)
	mutation_cooldown.timeout.connect(_on_mutation_cooldown_timeout)
	add_child(mutation_cooldown)

# === CHARACTER STYLING ===
func _on_dialogue_line_started(line: DialogueLine) -> void:
	var character_name := ""
	if line.character and not line.character.is_empty():
		character_name = line.character
	elif ":" in line.text:
		character_name = line.text.split(":")[0].strip_edges()
	if character_name.is_empty():
		character_name = "Default"
	apply_font_for_character(character_name)

func apply_font_for_character(character_name: String) -> void:
	if not dialogue_label:
		return
	var character_id := character_name.to_lower().replace(" ", "_")
	_current_speaker = _resolve_speaker_node(character_id)

	# Defaults
	var font_to_use: Font = loaded_fonts.get("Default")
	var font_bold_to_use: Font = null
	var font_italic_to_use: Font = null
	var font_bold_italic_to_use: Font = null
	var color_to_use := Color(1, 1, 1, 1)
	var font_size := 22

	# Styling comes from data/characters/<id>.json (font_path, font_*_path,
	# font_color hex, font_size offset added to the base size).
	var data_path := "res://data/characters/%s.json" % character_id
	if ResourceLoader.exists(data_path):
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(data_path)) == OK:
			var data: Dictionary = json.get_data()
			var fp: String = data.get("font_path", "")
			var fbp: String = data.get("font_bold_path", "")
			var fip: String = data.get("font_italic_path", "")
			var fbip: String = data.get("font_bold_italic_path", "")
			var fc: String = data.get("font_color", "")
			var fs: int = int(data.get("font_size", 0))
			if fp != "" and ResourceLoader.exists(fp): font_to_use = load(fp)
			if fbp != "" and ResourceLoader.exists(fbp): font_bold_to_use = load(fbp)
			if fip != "" and ResourceLoader.exists(fip): font_italic_to_use = load(fip)
			if fbip != "" and ResourceLoader.exists(fbip): font_bold_italic_to_use = load(fbip)
			if fc != "": color_to_use = Color(fc)
			if fs != 0: font_size = 22 + fs

	# Fall back to the normal font for any variant not provided
	if font_bold_to_use == null: font_bold_to_use = font_to_use
	if font_italic_to_use == null: font_italic_to_use = font_to_use
	if font_bold_italic_to_use == null: font_bold_italic_to_use = font_to_use

	if font_to_use:
		dialogue_label.add_theme_font_override("normal_font", font_to_use)
		dialogue_label.add_theme_font_override("bold_font", font_bold_to_use)
		dialogue_label.add_theme_font_override("italics_font", font_italic_to_use)
		dialogue_label.add_theme_font_override("bold_italics_font", font_bold_italic_to_use)
	dialogue_label.add_theme_color_override("default_color", color_to_use)
	for k in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]:
		dialogue_label.add_theme_font_size_override(k, font_size)

# Map a character id to a live world node for balloon positioning.
func _resolve_speaker_node(character_id: String) -> Node2D:
	if character_id in ["you", "player"]:
		var ps := get_tree().get_nodes_in_group("player")
		return ps[0] if ps.size() > 0 else null
	for npc in get_tree().get_nodes_in_group("npc"):
		if "npc_name" in npc and String(npc.npc_name).to_lower().replace(" ", "_") == character_id:
			return npc
	return null

# === FLOATING POSITIONING ===
func _to_screen(world_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos

func _get_character_screen_rect(character: Node2D) -> Rect2:
	# Nightspawn player/NPCs carry a CircleShape2D CollisionShape2D child.
	var col: Node = character.get_node_or_null("CollisionShape2D")
	if col == null:
		for c in character.get_children():
			if c is CollisionShape2D:
				col = c
				break
	if col and col is CollisionShape2D and col.shape is CircleShape2D:
		var center_world: Vector2 = character.to_global(col.position)
		var center_s: Vector2 = _to_screen(center_world)
		var edge_s: Vector2 = _to_screen(center_world + Vector2((col.shape as CircleShape2D).radius, 0))
		var r: float = (edge_s - center_s).length()
		return Rect2(center_s - Vector2(r, r + 40.0), Vector2(r * 2.0, r * 2.0 + 40.0))
	var s: Vector2 = _to_screen(character.global_position)
	return Rect2(s - Vector2(24, 56), Vector2(48, 64))

func _position_balloon() -> void:
	var panel: Panel = balloon.get_node("Panel")
	var bw: float = PANEL_WIDTH if presentation_mode == Mode.PANEL else BALLOON_WIDTH
	panel.custom_minimum_size = Vector2(bw, 0)
	panel.size = Vector2(bw, panel.size.y)
	await get_tree().process_frame
	await get_tree().process_frame

	var vw: float = get_viewport().get_visible_rect().size.x
	var vh: float = get_viewport().get_visible_rect().size.y

	# Size the height to the wrapped text. The DialogueLabel sits in a ScrollContainer
	# with a capped custom_minimum_size, so measuring the container under-reports tall
	# lines — the box stays short and the last line clips. We drive the scroll region's
	# min height from the label's real wrapped content height. But the label is still
	# hidden here (shown only after positioning), and a hidden RichTextLabel doesn't lay
	# out — so it would wrap at ~0 width and over-report. Show it for the measure with
	# nothing revealed yet (visible_ratio 0) so it lays out at the true width without
	# flashing the full text before type_out animates it in.
	var scroll: Control = balloon.get_node("Panel/Dialogue/VBoxContainer/ScrollContainer") as Control
	dialogue_label.show()
	dialogue_label.visible_ratio = 0.0
	await get_tree().process_frame
	var max_text_h: float = vh * 0.45
	var text_h: float = dialogue_label.get_content_height()
	if scroll:
		scroll.custom_minimum_size.y = clampf(text_h, 40.0, max_text_h)
		await get_tree().process_frame
	var content: Control = balloon.get_node("Panel/Dialogue") as Control
	var measured: float = content.get_combined_minimum_size().y if content else 0.0
	const PADDING: float = 20.0
	var bh: float = clampf(measured + PADDING, 84.0, vh * 0.6)
	panel.size = Vector2(bw, bh)

	# PANEL mode: a fixed wide banner pinned bottom-centre. Position carries no meaning
	# here (group scene, shared focus), so skip the speaker-anchoring + HUD scoring.
	if presentation_mode == Mode.PANEL:
		panel.position = Vector2((vw - bw) / 2.0, vh - bh - 44.0)
		return

	# BALLOON mode: float near the speaker, avoiding HUD-reserved zones (weighted
	# heavily) and the other characters it should try not to cover (weighted lightly).
	var hud_rects: Array[Rect2] = _hud_safe_rects(vw, vh)
	var char_rects: Array[Rect2] = []
	for npc in get_tree().get_nodes_in_group("npc"):
		if npc != _current_speaker and is_instance_valid(npc):
			char_rects.append(_get_character_screen_rect(npc))
	for pl in get_tree().get_nodes_in_group("player"):
		if pl != _current_speaker and is_instance_valid(pl):
			char_rects.append(_get_character_screen_rect(pl))

	if not is_instance_valid(_current_speaker):
		# Narrator / player lines with no resolved node: bottom-centre, clear of the
		# bottom controls hint.
		panel.position = Vector2((vw - bw) / 2.0, vh - bh - 44.0)
		return

	var speaker_rect: Rect2 = _get_character_screen_rect(_current_speaker)
	var char_center_s: Vector2 = speaker_rect.get_center()
	var candidates: Array[Vector2] = [
		Vector2(char_center_s.x - bw * 0.5, speaker_rect.position.y - bh - BALLOON_MARGIN),
		Vector2(speaker_rect.position.x - bw - BALLOON_MARGIN, char_center_s.y - bh * 0.5),
		Vector2(speaker_rect.position.x + speaker_rect.size.x + BALLOON_MARGIN, char_center_s.y - bh * 0.5),
		Vector2(char_center_s.x - bw * 0.5, speaker_rect.position.y + speaker_rect.size.y + BALLOON_MARGIN),
	]
	var best_pos: Vector2 = Vector2(
		clamp(candidates[0].x, BALLOON_MARGIN, vw - bw - BALLOON_MARGIN),
		clamp(candidates[0].y, BALLOON_MARGIN, vh - bh - BALLOON_MARGIN))
	var best_score: int = 1 << 30
	for candidate in candidates:
		var bx: float = clamp(candidate.x, BALLOON_MARGIN, vw - bw - BALLOON_MARGIN)
		var by: float = clamp(candidate.y, BALLOON_MARGIN, vh - bh - BALLOON_MARGIN)
		var brect := Rect2(bx, by, bw, bh)
		if brect.intersects(speaker_rect):
			continue
		# HUD overlap is the worst offence; covering another character is minor.
		var score: int = 0
		for r in hud_rects:
			if brect.intersects(r):
				score += 10
		for r in char_rects:
			if brect.intersects(r):
				score += 1
		if score < best_score:
			best_score = score
			best_pos = Vector2(bx, by)
			if score == 0:
				break
	panel.position = best_pos

# Screen rectangles the HUD occupies (top-left stats, top-right quest tracker,
# bottom controls hint). Kept in sync with hud.gd's layout. The balloon avoids them.
func _hud_safe_rects(vw: float, vh: float) -> Array[Rect2]:
	return [
		Rect2(0, 0, 300, 190),            # top-left: resource bars + Dread + level/marks/form
		Rect2(vw - 332, 0, 332, 148),     # top-right: quest tracker panel
		Rect2(0, vh - 40, vw, 40),        # bottom: controls hint
	]

func _unhandled_input(_event: InputEvent) -> void:
	# Only the balloon is allowed to handle input while it's showing
	get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _locale != TranslationServer.get_locale() and is_instance_valid(dialogue_label):
		_locale = TranslationServer.get_locale()
		var visible_ratio = dialogue_label.visible_ratio
		self.dialogue_line = await resource.get_next_dialogue_line(dialogue_line.id)
		if visible_ratio < 1:
			dialogue_label.skip_typing()

## Start some dialogue
func start(dialogue_resource: DialogueResource, title: String, extra_game_states: Array = []) -> void:
	resource = dialogue_resource
	temporary_game_states = [self] + extra_game_states
	self.dialogue_line = await resource.get_next_dialogue_line(title, temporary_game_states)
	if self.dialogue_line:
		_on_dialogue_line_started(self.dialogue_line)

## Apply any changes to the balloon given a new [DialogueLine].
func apply_dialogue_line() -> void:
	if dialogue_line and dialogue_line.text:
		_on_dialogue_line_started(dialogue_line)
	mutation_cooldown.stop()
	is_waiting_for_input = false
	balloon.focus_mode = Control.FOCUS_ALL
	balloon.grab_focus()

	character_label.visible = not dialogue_line.character.is_empty()
	character_label.text = tr(dialogue_line.character, "dialogue")

	dialogue_label.hide()
	dialogue_label.dialogue_line = dialogue_line

	responses_menu.hide()
	responses_menu.responses = dialogue_line.responses

	balloon.show()
	will_hide_balloon = false
	await _position_balloon()

	dialogue_label.show()
	if not dialogue_line.text.is_empty():
		dialogue_label.type_out()
		await dialogue_label.finished_typing

	if dialogue_line.responses.size() > 0:
		balloon.focus_mode = Control.FOCUS_NONE
		responses_menu.show()
	elif dialogue_line.time != "":
		var time = dialogue_line.text.length() * 0.02 if dialogue_line.time == "auto" else dialogue_line.time.to_float()
		await get_tree().create_timer(time).timeout
		next(dialogue_line.next_id)
	else:
		is_waiting_for_input = true
		balloon.focus_mode = Control.FOCUS_ALL
		balloon.grab_focus()

## Go to the next line
func next(next_id: String) -> void:
	self.dialogue_line = await resource.get_next_dialogue_line(next_id, temporary_game_states)
	if self.dialogue_line:
		_on_dialogue_line_started(self.dialogue_line)

#region Signals

func _on_mutation_cooldown_timeout() -> void:
	if will_hide_balloon:
		will_hide_balloon = false
		balloon.hide()

# Nightspawn has no cutscene system; mutations are plain Game method calls handled
# by the Dialogue Manager directly. Hook kept for parity / future use.
func _on_mutated(_mutation: Dictionary) -> void:
	pass

func _on_balloon_gui_input(event: InputEvent) -> void:
	if dialogue_label.is_typing:
		var mouse_was_clicked: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed()
		var skip_button_was_pressed: bool = event.is_action_pressed(skip_action)
		if mouse_was_clicked or skip_button_was_pressed:
			get_viewport().set_input_as_handled()
			dialogue_label.skip_typing()
			return

	if not is_waiting_for_input: return
	if dialogue_line.responses.size() > 0: return

	get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
		is_waiting_for_input = false
		next(dialogue_line.next_id)
	elif event.is_action_pressed(next_action) and get_viewport().gui_get_focus_owner() == balloon:
		is_waiting_for_input = false
		next(dialogue_line.next_id)

func _on_responses_menu_response_selected(response: DialogueResponse) -> void:
	next(response.next_id)

#endregion
