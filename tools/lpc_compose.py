#!/usr/bin/env python3
"""
lpc_compose.py

Deterministic compositor for the Universal-LPC-Spritesheet-Character-Generator.

Takes a hash-params JSON (as produced by the AI wrapper's /api/generate) and
composites the modular LPC layers into combined per-animation spritesheets,
ready to import into Godot.

Conventions discovered in this generator:
  * Skin layers (body, head): animation PNGs live directly in the layer folder
    (walk.png, slash.png, ...). Recolor is palette-based; we use the default
    (light) skin, which is fine for our purposes.
  * Variant layers (hair, clothes, armour, legs, feet, ...): each layer folder
    contains per-animation SUBFOLDERS (walk/, slash/, ...) whose files are named
    by variant (dark_brown.png, brown.png, iron.png, ...).
  * Layers are drawn back-to-front by zPos (ascending).

We key item -> sheet-definition by `id` (manifest item id == sheet def filename),
which disambiguates duplicate display names across categories.
"""

import json
import os
import sys
import glob
import argparse

GEN_DIR = r"C:/Users/seanm/AI LPC Sprite Gen/Universal-LPC-Spritesheet-Character-Generator"
MANIFEST = r"C:/Users/seanm/AI LPC Sprite Gen/ai-wrapper/asset-manifest.json"
SHEETS = os.path.join(GEN_DIR, "spritesheets")

# animation -> (cols, rows). LPC universal sheet, 64px frames.
ANIMS = {
	"walk": (9, 4),
	"slash": (6, 4),
	"spellcast": (7, 4),
	"thrust": (8, 4),
	"hurt": (6, 1),
	"idle": (2, 4),
}

FRAME = 64


def load_defs():
	"""Map sheet-definition id (filename stem) -> parsed json."""
	defs = {}
	for f in glob.glob(os.path.join(GEN_DIR, "sheet_definitions", "**", "*.json"), recursive=True):
		stem = os.path.splitext(os.path.basename(f))[0]
		if stem.startswith("meta_"):
			continue
		try:
			defs[stem] = json.load(open(f, encoding="utf-8"))
		except Exception:
			pass
	return defs


def find_item(manifest, category, value):
	"""Given a hash value like 'Tunic_brown', return (item_dict, variant_str)."""
	items = manifest["items"].get(category, [])
	best = None
	for it in items:
		cand = it["name"].replace(" ", "_")
		if value == cand:
			if best is None or len(cand) > len(best[0]):
				best = (cand, it, "")
		elif value.startswith(cand + "_"):
			variant = value[len(cand) + 1:]
			if best is None or len(cand) > len(best[0]):
				best = (cand, it, variant)
	if best:
		return best[1], best[2]
	return None, None


def resolve_layer_file(base, anim, variant):
	"""Return an existing PNG path for this layer+anim, or None."""
	if not base:
		return None
	root = os.path.join(SHEETS, base)
	# variant filename candidates
	vcands = []
	if variant:
		vcands += [variant, variant.replace(" ", "_"), variant.replace(" ", "")]
	# 1) per-animation subfolder with variant file: base/<anim>/<variant>.png
	for v in vcands:
		p = os.path.join(root, anim, v + ".png")
		if os.path.exists(p):
			return p
	# 2) per-animation subfolder, single file: base/<anim>/<anim>.png or first png
	subdir = os.path.join(root, anim)
	if os.path.isdir(subdir):
		# prefer a file literally named after the variant already tried; else any png
		pngs = sorted([x for x in os.listdir(subdir) if x.endswith(".png")])
		if pngs:
			# if a variant was requested but not found, take first as fallback
			return os.path.join(subdir, pngs[0])
	# 3) direct animation file: base/<anim>.png (skin layers)
	p = os.path.join(root, anim + ".png")
	if os.path.exists(p):
		return p
	return None


def collect_layers(params, manifest, defs, bodytype):
	"""Return list of (zPos, id, base_path_template_per_layer, variant)."""
	layers = []  # each: (zPos, base, variant, label)
	for category, value in params.items():
		if category == "sex":
			continue
		item, variant = find_item(manifest, category, value)
		if not item:
			print(f"  [skip] {category}={value} (no manifest item)", file=sys.stderr)
			continue
		idd = item.get("id")
		d = defs.get(idd)
		if not d:
			# fallback: match by name across defs
			for k, dd in defs.items():
				if dd.get("name") == item["name"]:
					d = dd
					break
		if not d:
			print(f"  [skip] {category}={value} (no sheet def for id {idd})", file=sys.stderr)
			continue
		# iterate layer_1..layer_N
		for n in range(1, 12):
			lk = f"layer_{n}"
			if lk not in d:
				continue
			layer = d[lk]
			z = layer.get("zPos", 50 + n)
			base = (layer.get(bodytype) or layer.get("male") or layer.get("female")
					or layer.get("muscular") or layer.get("teen") or "")
			if base:
				layers.append((z, base, variant, f"{category}:{idd}:L{n}"))
	layers.sort(key=lambda x: x[0])
	return layers


def compose(params, out_dir, name):
	from PIL import Image
	os.makedirs(out_dir, exist_ok=True)
	manifest = json.load(open(MANIFEST, encoding="utf-8"))
	defs = load_defs()
	bodytype = params.get("sex", "male")
	if bodytype not in ("male", "female", "muscular", "teen", "child", "pregnant"):
		bodytype = "male"
	layers = collect_layers(params, manifest, defs, bodytype)
	print(f"[{name}] {len(layers)} layers, bodytype={bodytype}")

	meta = {"name": name, "frame": FRAME, "anims": {}}
	for anim, (cols, rows) in ANIMS.items():
		canvas = None
		used = 0
		for z, base, variant, label in layers:
			fp = resolve_layer_file(base, anim, variant)
			if not fp:
				continue
			try:
				img = Image.open(fp).convert("RGBA")
			except Exception:
				continue
			if canvas is None:
				w = max(img.width, cols * FRAME)
				h = max(img.height, rows * FRAME)
				canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
			else:
				if img.width > canvas.width or img.height > canvas.height:
					nw = max(img.width, canvas.width)
					nh = max(img.height, canvas.height)
					nc = Image.new("RGBA", (nw, nh), (0, 0, 0, 0))
					nc.alpha_composite(canvas)
					canvas = nc
			canvas.alpha_composite(img)
			used += 1
		if canvas is not None and used > 0:
			outp = os.path.join(out_dir, f"{name}_{anim}.png")
			canvas.save(outp)
			meta["anims"][anim] = {"cols": cols, "rows": rows,
									"w": canvas.width, "h": canvas.height, "layers": used}
			print(f"  {anim}: {used} layers -> {os.path.basename(outp)} {canvas.size}")
	json.dump(meta, open(os.path.join(out_dir, f"{name}_meta.json"), "w"), indent=2)
	return meta


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--params", required=True, help="JSON string or @file")
	ap.add_argument("--out", required=True)
	ap.add_argument("--name", required=True)
	args = ap.parse_args()
	if args.params.startswith("@"):
		params = json.load(open(args.params[1:], encoding="utf-8"))
	else:
		params = json.loads(args.params)
	# unwrap {"params": {...}}
	if "params" in params and isinstance(params["params"], dict):
		params = params["params"]
	compose(params, args.out, args.name)


if __name__ == "__main__":
	main()
