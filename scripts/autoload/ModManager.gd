# === ModManager.gd ===
# Loads and registers community mods (JSON areas) for Portal Alley. Autoload — `ModManager`.
# SECURITY: all mod-supplied text is treated as plain strings — never compiled as
# .dialogue, never eval'd, never rendered as HTML. Real loading/sanitization in M7.
extends Node

## Emitted after the mod list (re)loads.
signal mods_loaded(count: int)

## Currently loaded mods, each a parsed mod JSON Dictionary.
var mods: Array[Dictionary] = []


## Load available mods. STUB returns nothing until M7 wires Supabase + local cache.
func load_mods() -> Array[Dictionary]:
	mods = []
	mods_loaded.emit(mods.size())
	return mods


## Strip anything that could execute when mod text is displayed. Mod strings are
## inert: no HTML, no dialogue-script syntax. Expanded + tested in M7.
func sanitize_text(text: String) -> String:
	var clean: String = text
	for needle: String in ["<script", "javascript:", "</", "<"]:
		clean = clean.replace(needle, "")
	return clean
