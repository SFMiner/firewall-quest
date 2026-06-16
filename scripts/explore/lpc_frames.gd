# === lpc_frames.gd ===
# Builds a SpriteFrames resource at runtime from the AI-generated LPC combined
# spritesheets (assets/chars/<name>_<anim>.png). Each sheet is a 64px grid laid
# out as rows = direction (up/left/down/right), cols = animation frames.
# This is what turns the natural-language sprite output into in-engine animation.
class_name LPCFrames
extends RefCounted

const DIRS := ["up", "left", "down", "right"]

# anim_state -> {file, cols, rows, fps, loop}
const ANIMS := {
	"idle":  {"file": "idle", "cols": 2, "rows": 4, "fps": 4.0, "loop": true},
	"walk":  {"file": "walk", "cols": 9, "rows": 4, "fps": 13.0, "loop": true},
	"slash": {"file": "slash", "cols": 6, "rows": 4, "fps": 16.0, "loop": false},
	"cast":  {"file": "spellcast", "cols": 7, "rows": 4, "fps": 14.0, "loop": false},
	"hurt":  {"file": "hurt", "cols": 6, "rows": 1, "fps": 10.0, "loop": false},
}

static func build(char_name: String) -> SpriteFrames:
	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")
	for state in ANIMS:
		var info: Dictionary = ANIMS[state]
		var path := "res://assets/chars/%s_%s.png" % [char_name, info.file]
		if not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = load(path)
		var rows: int = info.rows
		for d in range(4):
			var anim_name := "%s_%s" % [state, DIRS[d]]
			sf.add_animation(anim_name)
			sf.set_animation_speed(anim_name, info.fps)
			sf.set_animation_loop(anim_name, info.loop)
			var row: int = d if rows > 1 else 0
			for c in range(info.cols):
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(c * 64, row * 64, 64, 64)
				sf.add_frame(anim_name, at)
	# guarantee a usable default
	if sf.get_animation_names().size() > 0 and not sf.has_animation("idle_down"):
		pass
	return sf

# Map a movement/aim vector to one of the four LPC directions.
static func dir_name(v: Vector2) -> String:
	if v == Vector2.ZERO:
		return "down"
	if abs(v.x) > abs(v.y):
		return "right" if v.x > 0 else "left"
	return "down" if v.y > 0 else "up"
