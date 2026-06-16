# Firewall Quest — Implementation Plan

Derived from `firewall_quest_gdd.md` v0.4. This plan turns the GDD's five development
phases into concrete, ordered, file-level engineering work. Each milestone is independently
testable and leaves the game in a runnable state.

**Engine:** Godot 4.6 (GDScript, tabs, type hints). **Targets:** HTML5 (primary), Windows .exe.
**Backend:** Supabase. **Hosting:** GitHub Pages (`/docs`).

**Current repo state:** A default Godot 4.6 project already exists (`project.godot`, GL Compatibility
renderer, `icon.svg`, `.gitignore`, `.editorconfig`, `.gitattributes`). Config still has stock values
(`config/name="New Game Project"`, no autoloads, no scenes, no export presets). Milestone 0 below
configures this existing scaffold rather than creating it from scratch.

**Dialogue:** We use **Nathan Hoad's Dialogue Manager** (Godot addon, **stock v3.6.3** — unmodified)
plus the user's **custom balloon** that adds per-speaker control over font, size, and color. The
customization is NOT a forked addon — it lives in a standalone `DialogueBalloon` (`addons/dialogue_balloon.gd`
+ a balloon scene) that resolves each speaker's regular/bold/italic fonts, color, and size offset from
`data/characters/<id>.json`. Dialogue is authored in `.dialogue` files (conditionals/mutations can read
`firewall_power` and flags directly). Ported from `nightspawn-rpg` at Milestone 0, with its
Nightspawn-specific bits reworked for Firewall Quest (see M0).

> **Port source:** `C:\Users\seanm\Nextcloud2\Gamedev\GodotGames\nightspawn-rpg`
> Files: `addons/dialogue_manager/` (stock 3.6.3), `addons/dialogue_balloon.gd`,
> `scenes/ui/dialogue_balloon/dialogue_balloon.tscn`, `panel_style_box_flat.tres` (repo root),
> referenced fonts (Bainsley family, FantasticBoogaloo), and the `data/characters/*.json` style schema.

---

## Guiding Principles

1. **Data-driven from day one.** Content lives in `/data/*.json`; engine reads it. No hardcoded
   enemies, items, dialogue, or zone layouts. This is what makes the mod system nearly free later.
2. **Firewall power is the spine.** A single global `firewall_power` (0–100) drives world state,
   shop stock, NPC lines, palette, and zone unlocks. Build it early; everything keys off it.
3. **Vertical slice before breadth.** Get one full loop (explore → combat → reward → boss → unlock)
   working in Welcometon + Zone 1 before authoring Zones 2–4.
4. **Solo-complete is the MVP.** Multiplayer and mods layer onto a finished single-player game.
   Never let networking block the core gift.
5. **Keep it runnable.** Every milestone ends with the game booting and the new feature demoable.

---

## Milestone 0 — Configure Project Skeleton & Autoloads

**Goal:** Take the existing default project to a correct, booting main-menu state. No gameplay yet.

- [ ] Edit `project.godot`: set `config/name="Firewall Quest"`; confirm GL Compatibility renderer
      (good for HTML5/school hardware); set viewport stretch (`canvas_items`, integer scale) and a
      base window size for pixel art.
- [ ] Set pixel-art import defaults (texture filter = Nearest, mipmaps off) project-wide.
- [ ] Add HTML5 + Windows export presets (`export_presets.cfg`); HTML5 export targets `/docs`.
- [ ] Create folder structure per GDD §13 (`scenes/`, `scripts/`, `assets/`, `data/`).
- [ ] **Port Dialogue Manager + custom balloon from `nightspawn-rpg`** (see Port source above):
  - Copy `addons/dialogue_manager/` (stock 3.6.3), enable the plugin, register the `DialogueManager`
    autoload. Copy `addons/dialogue_balloon.gd`, the balloon scene, `panel_style_box_flat.tres`, and
    the referenced fonts. Fix any `res://` paths that move.
  - Ensure input actions `interact` and `ui_cancel_game` exist in `project.godot` (the balloon's
    `next_action` / `skip_action` defaults).
  - **Rework the Nightspawn-specific code in `dialogue_balloon.gd` for Firewall Quest:**
    - `_resolve_speaker_node()` — keep the `"player"` group + NPC `npc_name` lookup; replace the
      `"kestrel"` player alias with FQ's player id(s).
    - `_get_character_screen_rect()` — it assumes a `CircleShape2D`; adapt to FQ's tile-grid player/NPC
      collision (or rely on the generic fallback rect).
    - `_hud_safe_rects()` — currently hardcoded to Nightspawn's HUD (Dread bar, quest tracker). Re-tune
      to FQ's HUD (§11: top-left party HP, top-right zone + firewall gauge, bottom interaction prompt).
      Keep this in sync with `HUD.tscn` when M2 lands.
    - `DEFAULT_FONT` — point at a font we actually ship (bring FantasticBoogaloo or pick a pixel font).
    - **Default `presentation_mode` to `Mode.PANEL`** (fixed wide bottom banner, classic-JRPG feel) —
      change the `presentation_mode` initializer from `Mode.BALLOON`. Individual scenes can opt into
      `Mode.BALLOON` (float near speaker) when it suits them; expose it so the launcher/caller can set
      it per dialogue. In PANEL mode the per-speaker font/size/color styling still applies; only the
      speaker-anchored positioning + HUD scoring are skipped, so the M2 HUD re-tune (open question #6)
      only matters for scenes that opt into BALLOON.
  - Establish `data/characters/<id>.json` as the per-speaker style source (schema: `font_path`,
    `font_bold_path`, `font_italic_path`, `font_bold_italic_path`, `font_color` hex, `font_size` offset);
    seed a `default.json`.
  - Create `dialogue/` for `.dialogue` files; add a smoke-test `.dialogue` and confirm a line renders
    in the balloon with a non-default speaker font/color.
- [ ] Create the five autoload singletons as stubs with typed public APIs and register them:
  - `GameManager.gd` — `firewall_power: int = 100`, current zone, signals
    (`firewall_power_changed`, `zone_unlocked`); owns the run's party/player state in SP.
  - `SaveManager.gd` — `save()` / `load()` branching on `OS.get_name()` (web → JavaScriptBridge
    localStorage; desktop → `user://`). Stub returns dummy data.
  - `SupabaseManager.gd` — empty wrapper, `await`-able methods returning mock data.
  - `PartyManager.gd` — local-only stub (solo party of one).
  - `ModManager.gd` — stub `load_mods()` returning `[]`.
- [ ] `Main.tscn` + `MainMenu.tscn`: New Game / Continue / Join Code (disabled) / Quit; set as main scene.
- [ ] **Port the LPC sprite tooling** (see Asset Pipeline section): copy `tools/lpc_compose.py` and the
      `scripts/lpc_frames.gd` frame-slicer from `Temu_skyrim`; confirm `GEN_DIR` in `lpc_compose.py`
      points at `C:/Users/seanm/AI LPC Sprite Gen/Universal-LPC-Spritesheet-Character-Generator`.
      Smoke-test by composing one humanoid (e.g. a villager recipe) into `assets/chars/`.
- [ ] Add `CLAUDE.md` at root per GDD §15 spec (Overview, stack, conventions: tabs, type hints,
      signals over refs, data-first). Mark status: "Phase 0 in progress."
- [ ] `git init` + initial commit; verify `.gitignore` already covers `.godot/` (it does) and add
      `export/` and `.env`.

**Exit test:** Project opens in Godot 4.6, runs, shows the main menu, no errors in output. Window
title reads "Firewall Quest".

---

## Milestone 1 — Data Layer & Core Models  *(Phase 0)*

**Goal:** Define the JSON schemas and the GDScript loaders that read them.

- [ ] Author seed data: `data/classes.json`, `data/items.json`, `data/enemies.json`,
      `data/npcs.json`, and `data/zones/{welcometon,zone1,zone2,zone3,zone4}.json`.
  - `classes.json`: 5 classes, base stats (HP20/MP10/PWR4/SPD4/DEF2/WIT3), primary stat,
    sanitized + unlocked names, sanitized + unlocked skill ids.
  - `items.json`: potions, tonics, weapons (with `unlock_zone` gating), effects.
  - `enemies.json`: per-enemy sanitized/unlocked stats, damage, XP, byte drops, abilities.
  - `data/characters/<id>.json`: per-speaker dialogue styling (consumed by the ported balloon) — one
    per named speaker (Gerald, Cerys, Chronicler, bosses, player, `default`).
- [ ] GDScript data models (`RefCounted`/`Resource`): `ClassDef`, `ItemDef`, `EnemyDef`, `Skill`,
      `ZoneDef`. A `DataLoader` (autoload or static) parses JSON → typed objects.
- [ ] Stat/leveling math in one place (`scripts/combat/Stats.gd`): level = `floor(xp/100)+1` cap 10;
      per-level growth (+2 HP/MP, +1 all, +1 extra primary); WIT skill multiplier `base*(1+WIT/10)`.
- [ ] Define the **save schema** (GDD §13) and wire `SaveManager` to round-trip a real `PlayerState`.

**Exit test:** A test scene loads all JSON, builds a level-3 rogue with stats matching the GDD example,
saves and reloads identically.

---

## Milestone 2 — Exploration & World State  *(Phase 0)*

**Goal:** Walk around Welcometon, talk to NPCs, see the firewall gauge.

- [ ] `Player.tscn` / `Player.gd`: 4-direction tile movement, sprint (Shift), interact raycast. Add
      player to the `"player"` group (the balloon resolves the speaker node from it).
- [ ] `ExploreScene.tscn`: TileMap map, camera follow, NPC/trigger/portal nodes.
- [ ] `NPC.gd`: each NPC references a `.dialogue` title; interaction instantiates the ported
      `DialogueBalloon` and calls `start(resource, title)`. NPCs join the `"npc"` group and expose an
      `npc_name` property (the balloon matches the speaker against `npc_name` for per-character fonts +
      floating position). Firewall-state branching (Gerald's 4 lines, §7) lives **inside** the
      `.dialogue` file as conditionals on `GameManager.firewall_power` (expose GameManager/flags to
      Dialogue Manager's state-access list).
- [ ] Author `dialogue/welcometon.dialogue` (Gerald, Cerys, Chronicler, "Definitely Not Kevin") using
      the shared themed balloon; assign per-speaker fonts/colors via the modified fork.
- [ ] `HUD.tscn`: party HP (top-left), zone name + **Firewall Power gauge** (top-right),
      interaction prompt (bottom).
- [ ] Build **Welcometon** from `welcometon.json`: Inn (save+heal), Shop, Quest Board, Library,
      Portal Alley (locked), Bulletin Board. NPCs: Cerys, Gerald, Chronicler, "Definitely Not Kevin."
- [ ] **Generate humanoid sprites via the LPC pipeline** (Asset Pipeline section): hand-author
      `tools/<name>.json` recipes for the Welcometon NPCs (Gerald, Cerys, Chronicler, Definitely-Not-Kevin)
      and the 5 player classes, compose to `assets/chars/`, slice with `lpc_frames.gd` (4-dir walk + idle).
- [ ] Character creation: name (or random school-appropriate), class pick, portrait pick
      (include stick-figure + plague-doctor easter eggs).
- [ ] Shop UI reading `items.json` with `firewall_power` stock gating + Gerald's reactive barks.

**Exit test:** New Game → create character → explore Welcometon → buy a Foam Sword → save at Inn →
Continue restores state. Gauge reads 100.

---

## Milestone 3 — Turn-Based Combat  *(Phase 0)*

**Goal:** The combat half of the core loop, solo.

- [ ] `CombatScene.tscn`: party left, enemies right, initiative queue (top), action menu (bottom),
      enemy info panel (right).
- [ ] `Combatant.gd`: HP/MP/stats, status effects (stun, poison, buffs/debuffs), sanitized vs
      unlocked sprite + name based on zone state. Humanoid bosses (VICE_PRINCIPAL, Wellness Counselor,
      Hall Monitor) use LPC sprites; non-humanoid enemies (slime, goblin, golem, dragon, Error 404)
      use the monster-art path (Asset Pipeline section).
- [ ] `CombatSystem.gd`: SPD-ordered initiative; Attack / Skill / Item / Defend / Flee (60%, fails vs
      boss); damage = `PWR - DEF` floored at 1, Defend halves; MP costs (3 standard, 5 boss/AoE),
      +2 MP/turn regen; enemy AI (attack lowest HP, flee at low HP for unlocked goblin).
- [ ] Implement the 5 sanitized skills + unlocked counterparts as data-referenced effects.
- [ ] Encounter trigger from exploration → transition → return on victory.
- [ ] Reward resolution: XP (10/25/100/250), Bytes, level-up chime + stat application.
- [ ] Death/defeat: dark screen → respawn at last save, no item loss, no permadeath.

**Exit test:** Trigger a Sorry Goblin fight, win with Attack + a skill, gain XP/Bytes, level up at
100 XP, lose a fight and respawn at the Inn.

---

## Milestone 4 — Zone 1 + First Firewall Boss  *(Phase 0, completes the vertical slice)*

**Goal:** Full loop end-to-end; defeating a boss visibly changes the world.

- [ ] Build **Zone 1 — Meadows of Mild Inconvenience** from `zone1.json`: tilemap, 3 enemy types,
      3 mini-quests (turnips / apologetic merchant escort / "difficult time" animals).
- [ ] Quest-flag system (talk-to-X / give-Y / return-to-Z) driven by `GameManager.flags`.
- [ ] **VICE_PRINCIPAL.exe** boss: Form-7B pre-fight; win = survive until it runs out of forms
      (turn/resource gimmick); drops "Administrative Override" item.
- [ ] On defeat: `firewall_power -= 25` → fire `firewall_power_changed` → **filter-lift transition**,
      palette shift (pastel → saturated), music swap, Gerald restocks (Iron Sword), NPC barks update,
      zone marked unlocked.
- [ ] Verify the firewall-power → world-state table (§7) is fully wired (75% state).

**Exit test:** Clear a Zone 1 mini-quest, beat VICE_PRINCIPAL, watch the filter lift, return to
Welcometon and find Iron Sword + Gerald's new line. **This is the Phase 0 playable prototype.**

---

## Milestone 5 — Zones 2–4, Remaining Bosses, Easter Eggs  *(Phase 1)*

**Goal:** Complete the solo base game (the minimum gift).

- [ ] **Zone 2 — Dungeon of Strongly Discouraged Behavior**: enemies (Old Bones/Skeleton, Flying
      Mouse/Bat, Surprise Box/Mimic), 3 mini-quests, **THE_WELLNESS_COUNSELOR** (multiple-choice
      defeat; buffs enemies with "Processed Feelings"; becomes recruitable ally).
- [ ] **Zone 3 — Castle of Appropriate Conflict Resolution**: enemies (Conflict Mediator/Guard,
      Strongly Opinionated Peer/Knight, Large Reptilian Roommate/Dragon), abstract enemies
      (Bureaucratic Delay, Pending Approval, Under Review), **HALL_MONITOR_PRIME** (fixed-patrol
      lure-into-loop defeat).
- [ ] **Zone 4 — Central Server** (always real): Error 404 (vanish-on-look), Corrupted Data (splits),
      Stack Overflow (grows; must die by turn 5). **ADMIN-9** 3-phase fight (Protocol → Escalation →
      Override) + melancholy defeat cutscene + credits.
- [ ] Post-credits prompt: *"This world is yours now. Build something."* (hook to mod editor).
- [ ] **Ashvale easter eggs**: Birdman wanted poster, Cerys backstory hints, fire-damaged castle wing
      + "Bronze Lantern" note, plague-doctor mask chest, raven gravestone.
- [ ] Full save/load coverage across all zones and `bosses_defeated`.
- [ ] Update `CLAUDE.md` → "Phase 1 complete — solo game shippable."

**Exit test:** Complete a 30–45 min solo run to credits; firewall_power reaches 0; all bosses recorded;
easter eggs present.

---

## Milestone 6 — Multiplayer & Party  *(Phase 2)*

**Goal:** 2–5 player co-op on shared world state, layered onto the finished SP game.

- [ ] Flesh out `SupabaseManager.gd`: HTTPRequest/JavaScriptBridge wrappers, async + explicit error
      handling, `.env` for URL/anon key (never committed).
- [ ] Create Supabase tables: `rooms`, `player_saves`, `mods`, `mod_reports` (GDD §13 schema).
- [ ] `PartyManager.gd`: host creates room → 4-char code; join via code; real-time presence so players
      see each other on the same map instance.
- [ ] Shared combat: all party + enemies in one initiative queue; per-player turn control; **30s turn
      timer** → auto-Defend, "⏳ AFK" indicator, AI takeover after 3 AFK turns (attack lowest-HP enemy,
      self-heal <30%).
- [ ] Disconnect handling: character → AI NPC until return/session end.
- [ ] Shared `firewall_power`, **instanced loot per player**, individual XP (no split).
- [ ] Post-session sync: solo vs party — more-bosses-defeated wins.
- [ ] Update `CLAUDE.md` (Supabase schema, WebSocket-via-JavaScriptBridge gotchas).

**Exit test:** Two browsers join one room via code, fight a shared combat, one disconnects and is
AI-controlled, both saves sync correctly.

---

## Milestone 7 — Mod System & Editor  *(Phase 3)*

**Goal:** Community-extensible. The second gift.

- [ ] `ModManager.gd`: load mod JSON → spawn areas; treat **all mod text as plain strings**, never
      HTML/eval. Client-side validation + escaping on render.
- [ ] **XSS prevention** (non-negotiable, §9): Supabase edge function strips HTML tags and rejects
      `<script`, `javascript:`, `on[event]=` on upload; server-side sanitize before storage.
- [ ] `ModEditor.tscn`: tile placement (palette drag-drop), NPC placement + dialogue editor, enemy
      placement + stat editor, simple quest flags (talk/give/return), portal name + description.
  - **Mod dialogue is plain lines only, not full `.dialogue` scripts.** Mod NPC text is stored as data
    and rendered through the balloon as inert strings — never compiled via
    `DialogueManager.create_resource_from_text()`, because `.dialogue` mutations/conditionals can call
    game code. If runtime compilation is ever used, strip all `do`/`set`/conditional/`if` syntax and
    treat input as speaker+line pairs only. This is part of the §9 XSS guarantee.
- [ ] Publishing flow: "Upload to World" → GitHub OAuth → store in `mods` → appears in **Portal Alley**
      → other players visit + thumbs-up rate (no downvotes).
- [ ] Moderation: report → flag threshold; admin (Sean) removal path.
- [ ] Unlock Portal Alley + mod editor on post-game completion.
- [ ] Update `CLAUDE.md` (mod schema, XSS notes pointing at sanitization logic).

**Exit test:** Build a small mod area in-editor, upload it, see it in Portal Alley from a second
account, visit and rate it; verify a `<script>`-laced field is rejected server-side.

---

## Milestone 8 — Polish & Ship  *(Phase 4)*

**Goal:** Shippable gift.

- [ ] Audio pass (CC0/royalty-free): sanitized vs unlocked zone music, boss theme, ADMIN-9 piano,
      victory fanfare, SFX (footsteps, menu, hits, level-up).
- [ ] Visual transitions polish (filter-lift animation, palette swaps per firewall state).
- [ ] Accessibility: text size S/M/L, color-blind palette swap, pauseable timers.
- [ ] Performance: <5s load on school wifi, web export tuning.
- [ ] **Native desktop export** (Windows .exe; Mac .app deferred — needs signing).
- [ ] GitHub Pages deploy from `/docs` with CORS headers (`/docs/_headers`).
- [ ] Final `CLAUDE.md` update; verify all §16 success-criteria checkboxes.

**Exit test:** Public GitHub Pages URL loads <5s; full solo run + a co-op session + a mod visit all
work; Windows .exe runs standalone.

---

## Cross-Cutting Concerns (track throughout)

- **CLAUDE.md hygiene:** updated at the end of every phase (status, known issues, schema).
- **Save versioning:** `version` field in save data; write migration shims when schema changes.
- **Sanitized/Unlocked duality:** every enemy, NPC, item, palette, and music cue needs both states
  keyed off `firewall_power` — bake this into the data schema, not into per-entity code.
- **No secrets in repo:** Supabase keys in `.env`; verify `.gitignore` before first backend commit.
- **Security:** mod-text sanitization is load-bearing (§9) — server-side strip + client escape, tested.
  Mod dialogue never runs as a compiled `.dialogue` resource (mutations = code execution).
- **Dialogue:** core/base-game dialogue is authored as `.dialogue` files (Dialogue Manager). The
  modified fork's per-speaker font/size/color is the project's custom delta — re-verify it after any
  addon update. Mod dialogue is the exception (inert strings, see M7).

---

## Asset Pipeline — Sprites

Two sources by role (proven workflow from `Temu_skyrim`): **humans/humanoids = LPC**, **non-humanoid
monsters = battler/hand art**.

**LPC humanoids (NPCs, player classes, bureaucrat bosses):**
- Generator + manifest live at `C:\Users\seanm\AI LPC Sprite Gen\`. It has an AI wrapper, but **skip the
  API** — hand-author a params recipe `tools/<name>.json` using real item ids from
  `ai-wrapper/asset-manifest.json` (no API cost, deterministic, free).
- Compose: `python tools/lpc_compose.py --params @tools/<name>.json --out assets/chars --name <name>`
  → produces per-animation sheets (`<name>_walk.png`, `<name>_idle.png`, …).
- `scripts/lpc_frames.gd` slices `assets/chars/<name>_<anim>.png` into runtime frames at load; the
  NPC/Combatant `char_name` = `<name>`.
- **Known gotchas to carry over (documented in Temu_skyrim):**
  - Color-variant clothing layers ship **no idle** anim → rebuild `<name>_idle.png` from the walk
    sheet's standing frame (column 0 of each of the 4 direction rows) with PIL.
  - Plain `Longsleeve`/`Longsleeve 2` are fixed cream (`variants: null`); a `_color` suffix no-ops —
    use color-variant tops for recoloring.
  - No male floor-length robe; fake with `Longsleeve laced` + `Plain skirt` in a shared color
    (see `tools/mage.json`).
  - **Import gotcha:** some hand-edited PNGs are valid to PIL but Godot's importer rejects them
    (`valid=false`). Re-save via PIL as clean RGBA, delete the stale `.import` + cached
    `.godot/imported/<name>.png-*`, re-import. Art is unchanged.

**Non-humanoid monsters (slime, goblin, Trophy Golem, dragon, skeleton, Error 404, etc.):**
- Not expressible in LPC. Use battler/pixel art (Temu_skyrim pulled from `rpgbattlers` packs) or
  hand-authored sprites, animated as simple frame loops with tint/scale. Source TBD (open question #8).

**Sanitized vs Unlocked:** many enemies/NPCs need two looks keyed off `firewall_power`. For LPC this is
often a recipe swap (e.g. foam vs real weapon layer, washed vs saturated palette); for monsters it may
be a palette tint or a second sprite. Bake the two-state reference into the enemy/NPC data, not code.

## Suggested Build Order & Dependencies

```
M0 ─→ M1 ─→ M2 ─┐
                ├─→ M3 ─→ M4  (Phase 0: playable prototype / vertical slice)
                       └─→ M5 (Phase 1: solo game complete = MVP gift)
                              ├─→ M6 (Phase 2: multiplayer)
                              ├─→ M7 (Phase 3: mods)  ← can parallelize with M6
                              └─→ M8 (Phase 4: polish + ship) — gated on M5; pulls M6/M7 if done
```

**Recommended first PR target:** Milestones 0–4 (the Opus one-shot "Phase 0" deliverable). Everything
after is incremental and independently shippable, with M5 (solo-complete) as the true minimum gift.

---

## Open Questions / Decisions to Confirm Before Coding

1. **Renderer:** the project ships with GL Compatibility — correct for HTML5 + school hardware. Confirm
   we keep it (no Forward+/Vulkan-only features). Jolt 3D physics is irrelevant for a 2D top-down game.
2. **Boss defeat mechanics** (forms-run-out, multiple-choice, patrol-loop) are gimmicks, not raw DPS —
   confirm each should be a bespoke `BossController` rather than data-only, so budget time accordingly.
3. **Multiplayer authority:** GDD says "host authoritative." Confirm host-relay vs Supabase-relay for
   real-time state (affects `PartyManager` design).
4. **Portrait/sprite art source:** commission, CC0 packs, or AI-generated? Blocks M2 character-creation
   visuals (placeholders fine until then).
5. **Mac .app:** explicitly deferred (signing). Confirm Windows-only desktop for the gift timeline.
6. **Dialogue balloon HUD tuning:** dialogue defaults to **PANEL mode** (fixed bottom banner), which
   skips speaker-anchoring and HUD scoring — so `_hud_safe_rects()` only needs re-tuning to FQ's HUD
   *if/when* a specific scene opts into BALLOON (float-near-speaker) mode. Defer until that comes up.
   *(Port source resolved: `nightspawn-rpg`, stock Dialogue Manager 3.6.3 + custom `dialogue_balloon.gd`.)*
7. **`.dialogue` vs JSON for base content:** the GDD says "content lives in JSON," but base-game
   dialogue will live in `.dialogue` files. Confirm this split is fine (data = JSON, spoken lines =
   `.dialogue`); firewall/flag conditionals live in the `.dialogue` files reading GameManager state.
8. **Monster art source:** non-humanoid enemies can't use LPC. Temu_skyrim used `rpgbattlers` battler
   packs. Confirm we have a CC0/licensed monster set for slime/goblin/golem/dragon/skeleton/abstract
   enemies, or whether to hand-pixel them. Blocks M3/M5 enemy visuals (placeholders fine until then).
9. **Sprite frame size:** GDD §12 specifies 16x24 px character sprites, but LPC sprites are 64x64
   per frame (much larger, top-down). Recommend adopting LPC's native size for humanoids (the tooling
   is proven and free) and updating the GDD's 16x24 note — confirm, since it affects tile scale,
   camera zoom, and the overall pixel look.
```
