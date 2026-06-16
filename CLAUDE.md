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

**Milestone 6 — IN PROGRESS (foundation done).** Multiplayer against a **local** Supabase (see
`supabase-setup` memory). Verified by `scenes/dev/M6ConnTest.tscn` (11/11) from Godot.
- `SupabaseManager` rewritten: real PostgREST-over-HTTPRequest, `{ok,code,data}` returns, config from
  `res://supabase.cfg` (url + publishable key). Realtime = polling (no WebSocket; GH-Pages-safe).
  Methods: create/get/join/update/delete room, push/pull save, fetch/upload mod.
- Schema applied (rooms/player_saves/mods/mod_reports) + saved as a migration in the supabase project.
- **Lobby DONE** (`scenes/dev/M6LobbyTest.tscn`, 12/12 vs live backend): `PartyManager` rewritten with
  `host_room`/`join_room`/`start_game`/`leave_room` + 1s polling that mirrors the room's `game_state`
  and emits `party_changed`/`room_started`/`room_closed`. Main-menu **Host Co-op / Join Co-op** (disabled
  if Supabase unconfigured) → `CharacterCreation` → `Lobby` (4-char code, live player list, host Start) →
  shared explore. `JoinDialog` for entering codes. Concurrency note: presence writes are read-modify-write
  on `game_state.players` (last-write-wins) — fine for small lobbies; revisit if races show up.
- **Shared world (Layer 1) DONE** (`M6PresenceTest`, 7/7 vs live backend): PartyManager presence is
  read-modify-write on `game_state.players` (each poll re-reads then writes only our own slot to minimise
  clobber); each slot carries the full PlayerState dict + pos + zone + heartbeat `t`. Heartbeat older than
  DISCONNECT_TIMEOUT (6s) = offline. ExploreScene spawns/lerps **remote-player avatars** (LPC sprite +
  name) for others in the same zone, writes local presence each frame, and syncs **shared firewall power**
  (host pushes on change via `host_set`; guests adopt via `world_state_changed` → `GameManager.adopt_firewall_power`).
- TODO (Layer 2 — full shared party combat, host-authoritative): combatant `owner_id`, serialize combat
  to `game_state.combat`, host runs the loop + relays remote actions, guests view + submit, 30s timer →
  Defend → AI, disconnect → AI, boss HP scales with party size.
- **Testing co-op:** run two instances on this machine (local Supabase binds 0.0.0.0). Verifiable from one
  instance: connectivity, lobby, presence-data. Needs your 2-client playtest: live avatars + combat feel.
- **Reality:** local Supabase only reaches this machine; real co-op needs a hosted instance + rebuild.

**Milestone 8 — DONE (polish pass; multiplayer M6 + mods M7 still pending).** All regression suites
green; menu/HUD/settings/zone art confirmed by screenshot.
- **UI theme** (`assets/ui/theme.tres`, project `gui/theme/custom`): FantasticBoogaloo default font,
  styled buttons/panels. A true pixel font (Press Start 2P / m5x7) is a **drop-in**: replace the font
  in the theme. (Not shipped — no pixel `.ttf` was available locally.)
- **Per-zone ground** (`ZONE_GROUND` → `ground.tres` sources): meadow grass, dungeon stone, castle
  flagstone+carpet, server tech-grid. Procedurally generated 32×32 tiles.
- **Audio** (`Audio` autoload): looping explore/combat music + hit/success/menu/coin SFX (CC0). Wired
  in explore, combat, shop, menu. Headless-safe (dummy driver).
- **Settings** (`Settings` autoload + `SettingsPanel`): music/SFX volume, text size (S/M/L → theme
  font size), color-blind mode (neutral grey filter instead of blue). Persisted to `user://settings.cfg`.
  Reachable from main menu and the new **PauseMenu** (Esc in explore: Resume/Settings/Save/Quit to Title).
- **Export:** both presets work with the installed 4.6 templates. Web → `docs/` (single-threaded,
  `thread_support=false`, so it runs on GitHub Pages with no special headers; `docs/_headers` is for
  hosts that honor it). Windows → `export/firewall-quest.exe` (gitignored). Build:
  `./Godot_v4.6-stable_win64.exe --headless --path . --export-release "Web" docs/index.html`.
  Dev test scenes are excluded from builds (`scenes/dev/*`, `scripts/dev/*`).

**Milestone 5 — DONE (base game complete; MVP = Phases 0+1).** Zones 2–4 + bosses, validated by
`scenes/dev/M5Test.tscn` (13/13); Counselor survey / ADMIN-9 fight / Hall Monitor puzzle confirmed by
screenshot. Full firewall 100→0 chain works.
- **Boss framing (see memory):** mini-bosses are school staff *possessed by District policy*, freed and
  grateful on defeat; true antagonist is the off-screen **Office of the Chancellor** (unnamed; rotates
  with the mayor) that ADMIN-9 (final boss) serves. Affectionate satire aimed up at policy.
- Generalized, data-driven boss flow (`zone.boss` + per-zone `<boss>` / `<boss>_defeated` dialogue);
  gated `next:<zone>` progression portals; `EnemyDef.recruitable`.
- **Bespoke boss mechanics:** VICE_PRINCIPAL `out_of_forms` (combat); WELLNESS_COUNSELOR
  `answer_questions` — a multiple-choice "feelings survey" **dialogue-battle** (balloon responses; sets
  `boss_resolved_<id>`; `Combat.resolve_boss()` applies rewards without combat) → recruitable ally;
  HALL_MONITOR_PRIME `lure_into_loop` — overworld chase puzzle (`HallMonitor` chases player across 3
  markers); ADMIN-9 3-phase (`Combatant.is_final` + `CombatSystem._maybe_phase` at 66%/33%) + Office of
  the Chancellor reveal in combat log + melancholy `admin_9_defeated` → `Credits` scene → "build
  something" prompt → title.
- **Zone-4 enemy gimmicks:** Error 404 evades (40%), Stack Overflow grows + overflows (party wipe) at
  turn 5. (Corrupted Data "split" left as a normal enemy — simplification, noted.)
- **Ashvale easter eggs** (POIs): raven gravestone (Z1), Birdman wanted poster + plague-doctor mask
  chest → `plague_mask` cosmetic (Z2), Bronze Lantern fire-damaged wing note (Z3). Cerys's past hinted
  in Welcometon dialogue.
- Maps for Zones 2–4 reuse the grass/path ground (dungeon/castle/server art is a later polish pass).
  Recruited ally is a flag + acknowledgment, not yet a second combat party member (future).

**Milestone 4 — DONE (Phase 0 vertical slice complete).** Zone 1 + first Firewall Boss, validated by
`scenes/dev/M4Test.tscn` (15/15); sanitized vs unlocked rendering confirmed by screenshot.
- Zone travel via `travel:<id>` POIs; `ExploreScene.zone_change_requested` → Main reloads explore.
  Welcometon has a "Leave Town → The Meadows" portal; zones have a return portal.
- **Sanitation filter**: a pale screen-space `ColorRect` film over sanitized zones (CanvasLayer 1;
  HUD bumped to layer 2) that tweens out when the zone unlocks (`GameManager.firewall_power_changed`).
- `Quests` autoload (`QuestManager`): flag-based stages in `GameManager.flags` ("q_<id>"); methods
  named for `.dialogue` use (`start_quest`/`complete_quest`/`quest_stage`/`quest_active`/`quest_done`),
  passed to balloons as a game state alongside GameManager. Turnips quest is fully wired
  (farmer → search patch → return); quest board shows status.
- **VICE_PRINCIPAL.exe**: boss POI with Form-7B pre-fight dialogue, then `Combat.run_encounter`.
  Defeat mechanic `out_of_forms` (`Combatant.special.forms`, behavior `assign_detention` in
  CombatSystem): files a detention each turn (minor damage) and powers down when forms hit 0 — survive
  to win (or beat it down). Drops `administrative_override`. Boss kill → firewall 100→75 → Iron Sword
  stock, Gerald's new bark, filter lifts.
- Zone-1 NPCs: `farmer`, `apologetic_merchant` (LPC sprites). Fixed M2 bug: Definitely-Not-Kevin's
  npcs.json sprite was "student" (nonexistent) → now "definitely_not_kevin".

**Milestone 3 — DONE.** Turn-based combat, validated by `scenes/dev/M3Test.tscn` (14/14); rendering
confirmed by screenshot.
- `Combatant` (`scripts/combat/Combatant.gd`): pure state/logic, built from PlayerState or
  EnemyDef.stats_for(firewall); statuses (stun/sleep/poison/buff/debuff), `eff()` stat modifiers.
- `CombatSystem`: async round/turn loop — SPD initiative, Attack/Skill/Item/Defend/Flee (60%, blocked
  vs boss), damage = PWR−DEF min 1 (Defend halves), MP 3/5 + 2 regen/turn, skill effects
  (damage/heal/stun/buff/debuff/steal), enemy AI (attack lowest HP; unlocked goblin flees low).
  Players act via `submit_action` (UI); enemies via AI. Emits log/turn/state/ended signals.
- `CombatScene`: party left / enemies right, initiative queue, action menu, target+skill+item
  choosers, log, banner. Sanitized names show at firewall 100.
- `Combat` autoload (`CombatManager`): `run_encounter(ids)` overlays the scene, awaits result, awards
  XP (10/25/100/250) + Bytes + level-up, reduces firewall on boss kills, respawns at hub on defeat
  (full heal, no permadeath). `EnemyEncounter` (Area2D) triggers it on touch; ExploreScene spawns
  them in non-hub zones (used by Zone 1 in M4) and toasts rewards; Main reloads explore on defeat.

**Milestone 2 — DONE.** Exploration + Welcometon, validated by `scenes/dev/M2Test.tscn` (19/19) and
`M2DialogueTest.tscn`; rendering confirmed by screenshot.
- `Player` (`scripts/explore/Player.gd`): real-time 4-dir LPC movement, sprint, interaction probe;
  in `"player"` group; pauses on `GameManager.ui_blocking`.
- `ExploreScene` builds ground (code-filled grass/path TileMapLayer), spawns player + follow camera,
  and `_build_welcometon()` places 3 buildings (sprite + solid collision), 6 POIs, and 4 NPCs.
- `NPC` (data-driven from npcs.json, `"npc"`+`"interactable"` groups) opens the **ported PANEL balloon**
  with per-speaker fonts — confirmed working (Gerald's lines render in his gold Bainsley style).
- `HUD`: party HP (top-left), zone + Firewall gauge (top-right, reacts to changes), interaction
  prompt, toast.
- `CharacterCreation`: name/random, class pick w/ live sprite preview, portrait (incl. stick-figure +
  plague-doctor easter eggs). `Main.gd` wires New Game → creation → explore, and Continue → load → explore.
- `Shop`: firewall-gated stock from items.json, Bytes spend, equip/stock, Gerald barks. Inn POI
  heals + saves.
- Assets: Cute RPG Village 32×32 tileset, procedural grass/path tiles, 3 cropped buildings, 9 LPC
  64×64 characters (5 classes + 4 NPCs) in `assets/chars/` with recipes in `tools/`.

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
Not started: multiplayer (M6), mod editor (M7). **Phases 0+1+polish are complete — the solo game is
playable start to credits, themed, scored, settings-equipped, and exports to web + Windows.** Remaining:
networked party play (M6, needs a live Supabase project + 2-client test) and the in-game mod editor +
registry (M7). A true pixel font is a drop-in when you have one; richer per-zone decoration (props,
painted walls beyond the floor) is optional future art.

## Known Issues (polish-era)
- Balloon stylebox emits a benign UID warning on cold boot (`uid://bsihak25pctp0`); it falls back to the
  text path and works — clears after a full `--import`.
- `docs/` web build (incl. ~37 MB `index.wasm`) is committed for GitHub Pages per the plan; consider a
  CI deploy later if git history size matters.
- Recruited ally (Wellness Counselor) is a flag, not yet a second combatant. Corrupted Data "split" is a
  normal enemy. Zone maps are floor-tile + sprites (no painted walls yet).
M2 deferred polish: UI still uses the default Godot font (Press Start 2P pixel font in M8); the
Welcometon building layout is spread out and minimal (art pass later).

## Known Issues & Workarounds
- **`DataLoader.get_class_def()`**, not `get_class()` — `get_class` is a built-in `Object` method and
  shadowing it as a static causes a parse error ("Could not resolve external class member get_class").
- **GDD leveling discrepancy:** §4's growth formula and §13's sample save contradict each other (a
  level-3 rogue is HP24/MP14/PWR6/SPD8/DEF4/WIT5 by the formula; the §13 sample says
  HP26/MP16/PWR5/SPD8/DEF3/WIT4). The **§4 formula is authoritative** (implemented in `Stats.gd`);
  the §13 stat block is illustrative only.
- Save schema extends §13 with `equipped_armor` (Shield/Steel Armor need an armor slot; §13 only
  showed `equipped_weapon`).
- GDScript 4.6: returning a bare array literal where `Array[Combatant]` is expected is a runtime
  error ("Trying to return an array of type Array"). Build a typed local and `append()` instead of
  `return [x]` (bit `CombatSystem._resolve_targets`).
- Driving `CombatSystem` from a test: connect `awaiting_action` and submit via
  `submit_action.call_deferred(...)` — a synchronous submit races ahead of the loop's `await`.

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
