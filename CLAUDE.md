# Firewall Quest — CLAUDE.md

## Project Overview
Firewall Quest is a short-form (~30–45 min) party RPG where middle schoolers get sucked into a
sanitized, school-policy-filtered fantasy game and must defeat the Firewall to restore the world to
proper Saturday-morning-cartoon adventure. It's a farewell gift from a TTRPG club advisor to his
students, built to be extended by them via a mod system. Top-down real-time exploration + turn-based
combat. The joke is the point, but the heart is real.

## Engine & Stack
- **Godot 4.6, GDScript, tabs not spaces.** Bundled binary at repo root: `Godot_v4.6-stable_win64.exe`.
- Renderer: **GL Compatibility** (web + school hardware friendly). 2D only.
- Backend: Supabase (URL + anon key in `.env` — never commit secrets). Not wired until M6.
- Hosting: GitHub Pages (web export to `/docs`).
- Desktop: native Godot export — Windows `.exe`; Mac `.app` deferred (needs signing).
  `SaveManager.gd` detects platform via `OS.get_name()` and routes saves to localStorage (web) or
  `user://` (desktop).

## How to run & validate (bundled binary)
- **Parse / import scan (primary check):**
  `./Godot_v4.6-stable_win64.exe --headless --path . --editor --quit-after 300`
  → expect no `SCRIPT ERROR` / `Parse Error` / `not found`. Registers `class_name`s, imports assets.
- **Runtime smoke test:** `./Godot_v4.6-stable_win64.exe --headless --path . --quit-after 120`
  → boots into `Main.tscn` (main menu). Grep for `SCRIPT ERROR` / `Failed loading` / `Nonexistent`.
- **Force reimport** of changed assets: `./Godot_v4.6-stable_win64.exe --headless --path . --import`.
- Gotchas: a benign `ERROR: N resources still in use at exit` can appear on headless quit — not a bug.
  Single-script `--check-only` gives false "Identifier not found" for autoloads; trust the full scan.

## Architecture Summary
- **AutoLoad singletons** (`scripts/autoload/`): `GameManager`, `SaveManager`, `SupabaseManager`,
  `PartyManager`, `ModManager`, plus Dialogue Manager's `DialogueManager`.
- `GameManager` owns the **firewall power** world-state spine (0–100). Everything keys off it
  (shop stock, NPC lines, palette, zone unlocks). `defeat_firewall_boss()` drops it 25 and emits
  `firewall_power_changed`.
- All game content is **data-driven via JSON** in `/data/` (`/data/zones/`, `/data/characters/`).
  Don't hardcode content — JSON first, engine reads it.
- Combat is fully turn-based; exploration is real-time top-down.
- Scene flow: `Main.tscn` (`scripts/main/Main.gd`) is the persistent root and swaps screens
  (menu → character creation → explore → combat) beneath itself.

## Dialogue system
- **Nathan Hoad's Dialogue Manager** (stock v3.6.3 in `addons/dialogue_manager/`) +
  **custom balloon** (`addons/dialogue_balloon.gd`, scene at `scenes/ui/dialogue_balloon/`).
- The customization is NOT a forked addon — it's the balloon. It resolves per-speaker font /
  size / color (regular + bold/italic) from `data/characters/<id>.json`.
- **Defaults to PANEL mode** (fixed wide bottom banner). Scenes can opt into `Mode.BALLOON` to float
  near the speaker. Per-speaker styling applies in both modes.
- Speaker resolution: balloon matches against the `"player"` group and `"npc"` group (NPCs expose
  `npc_name`). `_hud_safe_rects()` is still tuned to Nightspawn's HUD — only matters in BALLOON mode;
  re-tune when a scene opts in (it's hardcoded; keep in sync with `HUD.tscn`).
- Base-game dialogue lives in `.dialogue` files (`/dialogue/`); firewall/flag conditionals go inside
  them reading `GameManager` state. **Mod dialogue is the exception** — inert strings only (see below).

## Sprite pipeline
Humans/humanoids = **LPC**; non-humanoid monsters = battler/hand art.
- LPC generator + manifest live at `C:\Users\seanm\AI LPC Sprite Gen\`. **Skip its AI wrapper/API** —
  hand-author `tools/<name>.json` from real ids in `ai-wrapper/asset-manifest.json` (free, deterministic).
- Compose: `python tools/lpc_compose.py --params @tools/<name>.json --out assets/chars --name <name>`.
- `scripts/explore/lpc_frames.gd` (`class_name LPCFrames`) slices `assets/chars/<name>_<anim>.png`
  into a `SpriteFrames` at load (64×64 grid; rows = direction, cols = frames).
- Gotchas (from Temu_skyrim): color-variant tops ship **no idle** → rebuild `_idle.png` from walk
  column 0 with PIL; plain `Longsleeve` is fixed cream (no recolor); no male floor-length robe;
  some hand-edited PNGs import as `valid=false` → re-save clean RGBA via PIL, delete stale `.import`
  + `.godot/imported/<name>.png-*`, re-import.
- **Frame size:** LPC is **64×64**, not the GDD's stated 16×24. Open decision — current direction is
  to adopt LPC native size for humanoids.

## Current Implementation Status
**Milestone 0 — DONE.** Project skeleton boots to a main menu with no errors (config, input map,
five autoload stubs, Dialogue Manager + PANEL balloon, LPC tooling, Main/MainMenu).

**Milestone 1 — DONE.** Data layer + core models, validated by `scenes/dev/M1Test.tscn` (34/34
checks pass headless).
- Seed JSON in `/data/`: `classes`, `skills`, `items`, `enemies`, `npcs`, `zones/*` (Welcometon +
  zones 1–4; 2–4 are skeletons).
- Typed models in `scripts/data/`: `ClassDef`, `ItemDef`, `SkillDef`, `EnemyDef`, `ZoneDef`, plus
  `DataLoader` (static, lazy-cached; **`get_class_def`** not `get_class` — see Known Issues).
- `scripts/combat/Stats.gd` — leveling + WIT math (formula authoritative; see Known Issues).
- `scripts/PlayerState.gd` — class/level/xp/bytes/current+derived stats/equipment/inventory, with
  `to_dict`/`from_dict`. `GameManager.player_state` holds it; `SaveManager` serializes the flat
  section-13 schema (player fields + world state). Equipment re-applies on load.
Not started: exploration/Welcometon (M2), combat (M3), zones/bosses (M4–5), multiplayer (M6),
mods (M7), polish/export (M8).

## Known Issues & Workarounds
- **`DataLoader.get_class_def()`**, not `get_class()` — `get_class` is a built-in `Object` method and
  shadowing it as a static causes a parse error ("Could not resolve external class member get_class").
- **GDD leveling discrepancy:** §4's growth formula and §13's sample save contradict each other (a
  level-3 rogue is HP24/MP14/PWR6/SPD8/DEF4/WIT5 by the formula; the §13 sample says
  HP26/MP16/PWR5/SPD8/DEF3/WIT4). The **§4 formula is authoritative** (implemented in `Stats.gd`);
  the §13 stat block is illustrative only.
- Save schema extends §13 with `equipped_armor` (Shield/Steel Armor need an armor slot; §13 only
  showed `equipped_weapon`).

## Data Formats
- **Character style** `data/characters/<id>.json`: `font_path`, `font_bold_path`, `font_italic_path`,
  `font_bold_italic_path`, `font_color` (hex), `font_size` (offset added to base 22).
- **Class** `data/classes.json`: base_stats, primary_stat, sanitized/unlocked names, skill refs.
- **Item** `data/items.json`: `type` (consumable/equipment), `slot`, `cost`, `unlock_firewall_max`
  (purchasable while `firewall_power <= this`), `stat_mods`, `effect`.
- **Enemy** `data/enemies.json`: sanitized + unlocked stat blocks, tier, xp, bytes range, boss meta.
- **Zone** `data/zones/<id>.json`: unlock threshold, palette/music per state, enemies, boss, quests.
- Save schema: flat — `PlayerState.to_dict()` fields + `firewall_power`/`current_zone`/
  `bosses_defeated`/`flags`. See `firewall_quest_gdd.md` §13 and the discrepancy note above.

## Supabase Schema
Not provisioned yet (M6). Planned tables: `rooms`, `player_saves`, `mods`, `mod_reports`
(see GDD §13).

## XSS / Security Notes
All user text from mods must be sanitized before storage and escaped on render. Never eval or
innerHTML mod content. **Mod dialogue is never compiled as a `.dialogue` resource** — `.dialogue`
mutations execute game code. Treat mod text as inert strings. See `ModManager.sanitize_text()`
(stub; server-side edge-function sanitization in M7).

## Godot-Specific Gotchas
- GDScript 4.6 strict mode: annotate `var path: String = a + b` on string concatenation, and
  `for x: String in [...]` loop vars, or you get "cannot infer type" errors.
- Supabase realtime needs WebSocket via JavaScriptBridge in web export (M6).
- localStorage uses `JavaScriptBridge` on web; `user://` on desktop (`SaveManager`).
- Web export needs CORS headers on GitHub Pages (`/docs/_headers`, set in M8).
- Verify asset filenames exactly — typos fail silently at runtime (`Failed loading resource`).

## What NOT to Change Without Reading This First
- `GameManager.firewall_power` and its signals — load-bearing world-state spine.
- The Dialogue Manager addon (`addons/dialogue_manager/`) is **stock**; customization lives only in
  `addons/dialogue_balloon.gd`. Don't fork the addon.
- Autoload order in `project.godot` (DialogueManager must remain registered for `.dialogue`).

## Development Conventions
- Tabs, not spaces. Type hints on all vars and function signatures.
- `class_name` for reusable types. `# === SECTION ===` header comment style.
- Signals for cross-node communication over direct node references where avoidable.
- New content goes in `/data/` JSON first, then the engine reads it — don't hardcode content.
- Commit only when asked.
