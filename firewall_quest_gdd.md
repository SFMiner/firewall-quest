# Firewall Quest — Game Design Document
## Version 0.4

**Platform:** HTML5 (primary) + Desktop .exe/.app (native Godot export)
**Engine:** Godot 4.6 (GDScript); Opus one-shot target, Claude Code completion
**Target Audience:** Middle school TTRPG/Gamedev club members, ages 11–14
**Genre:** Top-down hybrid RPG (real-time exploration, turn-based combat)
**Art Style:** 16-bit pixel art, deliberately slightly-wrong fantasy aesthetic
**Scope:** ~30–45 min base playthrough; expandable via community mod system
**Hosting:** GitHub Pages (base game + mod registry)
**Backend:** Supabase (multiplayer lobbies + mod storage)
**Save System:** localStorage (single player) + Supabase (shared world state)

---

## Table of Contents

1. Core Concept
2. Premise & Narrative
3. Core Gameplay Loop
4. Mechanics
5. World Structure
6. Combat System
7. The Firewall System (Sanitation Layer)
8. Multiplayer & Party System
9. Mod System & Editor
10. NPCs & Coworker Cameos
11. Controls & Interface
12. Art & Audio Direction
13. Technical Architecture
14. Content: Base Game Areas
15. Development Phases
16. Success Criteria

---

## 1. Core Concept

**Firewall Quest** is a short-form party RPG in which a group of middle schoolers get sucked into a video game during their TTRPG club meeting. The game world they inhabit is a sanitized, school-policy-filtered fantasy RPG — monsters can only "bop" you, the rogue can only "borrow without asking," and the final boss is a content filter. The players' quest is to defeat the Firewall and restore the world to its proper (Saturday-morning-cartoon) level of adventure.

**Core Innovation:** The "Sanitation Layer" mechanic — the game world has two states. Locked (nerfed, school-appropriate, absurd) and Unlocked (cartoon-violence-level, fun). Defeating Firewall Bosses in each zone progressively restores the world. Players literally upgrade the game by playing it.

**This is a farewell gift** from a TTRPG club advisor to his students — particularly the 8th graders leaving for high school. The game is designed to be extended by the students themselves via a mod system, so the world keeps growing after the club ends.

**Design Philosophy:** The joke is the point, but the heart is real. Every absurdist sanitized mechanic is a love letter to the specific experience of trying to play games at school. The quest to "break the firewall" is the kids reasserting creative ownership over a space that was supposed to be theirs.

---

## 2. Premise & Narrative

### Opening Cutscene (text-based, skippable)

> *It's a Monday. The TTRPG Club is meeting in Room 214.*
>
> *Half the group is actually playing the tabletop game. The other half are on their phones. One kid — let's call him The Kid — has snuck in a laptop and is running some ancient fantasy RPG he found on a sketchy download site.*
>
> *Others start gathering around. The screen is weirdly compelling. Someone reaches out to touch it—*
>
> *The energies of twelve middle schoolers focused on one screen, in a room still humming with the residual creative resonance of last semester's Gamedev Club, in a school where approximately forty content filters are running at all times—*
>
> *—something goes wrong. Or possibly very right.*
>
> *You are inside the game now.*
>
> *It is not a good game. But it is yours.*

### Narrative Structure

**Act 1 — The Nerfed World:** Players arrive in Welcometon, the starting village, and immediately notice everything is wrong. The blacksmith only sells "Foam Training Weapons." The quest board only has "strongly encouraged activities." The local monster is a Goblin who apologizes when he bumps into you.

**Act 2 — Breaking the Filters:** Three zones, each with a Firewall Mini-Boss. Defeating each one unlocks a layer of the world — better weapons, actual combat stakes, real quest rewards. The world visibly changes after each defeat (visual filter lifts, NPCs relax, music gets more dramatic).

**Act 3 — The Central Server:** The final dungeon is literally a server room (fantasy-themed: arcane computers, cooling crystals, scroll-based terminals). The final boss is ADMIN-9, the Firewall itself — a bureaucratic entity that genuinely believes it is protecting the players.

### Final Boss Twist
ADMIN-9 is not malicious. It's doing its job. Its defeat cutscene is slightly melancholy: *"I was only trying to keep you safe."* The world restores. The kids are home. The game is still there, waiting.

### Post-Game
After the credits, the game prompts: *"This world is yours now. Build something."* — which is the hook into the mod editor.

---

## 3. Core Gameplay Loop

```
1. EXPLORE (real-time top-down)
   ↓ encounter enemy or reach trigger
2. COMBAT (turn-based, see Section 6)
   ↓ victory
3. REWARD (loot, dialogue, world-state change)
   ↓ new area unlocked or Firewall Boss revealed
4. FIREWALL BOSS (special combat)
   ↓ defeat
5. ZONE UNLOCKED (visual/mechanical change, new content available)
   ↓ repeat until Act 3
6. FINAL BOSS → Credits → Mod Editor Prompt
```

**Session pacing target:** ~30–45 minutes solo. With a full party of 4–5, longer due to social chaos — which is fine. That's the point.

---

## 4. Mechanics

### Player Mechanics

| Action | Input | Result |
|--------|-------|--------|
| Move | WASD / Arrow Keys | Real-time movement on tile grid |
| Interact | E / Space | Talk to NPC, open chest, read sign |
| Sprint | Shift | Move faster (no stamina cost — school policy removed stamina) |
| Open Menu | Escape / Tab | Inventory, party, map, settings |
| Attack (combat) | Click / Enter | Select action in turn-based combat |
| Party invite | P | Open party panel (multiplayer) |

### Character Classes (chosen at start)

| Class | Sanitized Name | Real Name (unlocked) | Role |
|-------|---------------|----------------------|------|
| Fighter | Conflict Resolution Specialist | Warrior | Tank/DPS |
| Rogue | Unauthorized Borrower | Thief | Speed/stealth |
| Mage | Hypothesis Tester | Wizard | AoE damage |
| Healer | Wellness Advocate | Cleric | Support |
| Bard | Enthusiastic Encourager | Bard | Buff/debuff |

Players pick one class. In multiplayer, party composition matters.

### Character Creation
- Enter your name (or use a randomly generated school-appropriate one: "Student #4," "Kevin," "The One Who Was On Their Phone")
- Pick a class
- Pick a portrait (pixel art options; one is a stick figure, one wears a plague doctor mask — easter eggs for club members)

### Stats (simplified)

| Stat | Starting Value | What It Does |
|------|---------------|-------------|
| HP | 20 | Health. Reaching 0 = defeated |
| MP | 10 | Mana. Spent on Skills, recovers 2 per turn passively |
| PWR | 4 | Base damage output |
| SPD | 4 | Turn order in combat (higher = earlier) |
| DEF | 2 | Flat damage reduction per hit |
| WIT | 3 | Multiplier for Skill effectiveness: damage/heal = base × (1 + WIT/10) |

**Leveling:** Flat +2 to HP and MP per level, +1 to all other stats per level, +1 extra to class primary stat per level.

**Class primary stats:**
- Fighter: DEF
- Rogue: SPD
- Mage: WIT
- Healer: WIT
- Bard: WIT

**MP costs per Skill:** Standard skills cost 3 MP. Boss-tier or AoE skills cost 5 MP. The Mana Tonic restores 10 MP. Players who run out of MP can still Attack and Defend — they just can't use Skills until MP recovers.

### XP & Leveling

XP is awarded after every combat victory.

| Source | XP Reward |
|--------|-----------|
| Standard enemy | 10 XP |
| Elite enemy | 25 XP |
| Firewall Mini-Boss | 100 XP |
| ADMIN-9 (Final Boss) | 250 XP |
| Quest completion | 20–50 XP (varies) |

**Level thresholds:** `level = floor(total_xp / 100) + 1`, capped at 10.
Level 2 = 100 XP, level 3 = 200 XP, level 10 = 900 XP total.
Intentionally gentle — players should reach level 4–5 by end of base game without grinding.

In multiplayer, each player earns XP individually from shared combat. No XP splitting.

### Economy

Currency: **Bytes** (the game world's currency is literally data — school network joke).

**Earning Bytes:**

| Source | Bytes |
|--------|-------|
| Standard enemy drop | 2–5 |
| Elite enemy drop | 10–15 |
| Quest reward | 15–30 |
| Chest (standard) | 5–10 |

**Shop prices (Gerald the Blacksmith, Welcometon):**

| Item | Cost | Effect | Available |
|------|------|--------|-----------|
| Health Potion | 10 B | Restore 15 HP | Always |
| Antidote | 8 B | Cure Poison | Always |
| Smoke Bomb | 12 B | Guarantee flee success | Always |
| Mana Tonic | 12 B | Restore 10 MP | Always |
| Foam Sword | 5 B | +1 PWR (sanitized) | Always |
| Shield | 15 B | +2 DEF | Always |
| Iron Sword | 20 B | +3 PWR | Zone 1 cleared |
| Steel Armor | 25 B | +4 DEF | Zone 2 cleared |
| Enchanted Staff | 30 B | +3 PWR, +2 WIT | Zone 3 cleared |

Weapons are equipped items, not consumables. One weapon slot per character. Gerald comments on each new stock arrival as the Firewall weakens.

---

## 5. World Structure

### Hub: Welcometon
The starting village. Portal stones here connect to all player-made mod areas (post-game). Contains:
- The Quest Board (main quest tracker)
- The Inn (save point, party meeting place)
- The Suspicious Shop (sells items)
- The Library (lore, tutorials)
- Portal Alley (community mod portal hub)

### Base Game Zones (3 + Final)

**Zone 1 — The Meadows of Mild Inconvenience**
Sanitized: Soft grass, passive monsters, gentle weather.
Unlocked: Actual forest, wolves, rain, stakes.
Firewall Boss: VICE_PRINCIPAL.exe — assigns detentions instead of attacking. Defeat condition: survive long enough that it runs out of forms to file.

**Zone 2 — The Dungeon of Strongly Discouraged Behavior**
Sanitized: Well-lit, labeled hazards, handrails on all pits.
Unlocked: Actual dungeon, traps, darkness.
Firewall Boss: THE_WELLNESS_COUNSELOR — opens every turn with "Let's talk about how that made you feel." Buffs enemies with "Processed Feelings." Defeat by answering all its questions correctly (multiple choice, each answer is funnier than the last).

**Zone 3 — The Castle of Appropriate Conflict Resolution**
Sanitized: Castle guards who only want to "have a conversation." Treasure chests that are "not for sharing without permission."
Unlocked: Real castle, real guards, real treasure.
Firewall Boss: HALL_MONITOR_PRIME — patrols in a fixed pattern, cannot deviate. Defeat by luring it into a loop.

**Zone 4 — The Central Server (Final)**
No sanitized version — this is the Firewall's home, it's always real here.
Boss: ADMIN-9 (see Section 2).

---

## 6. Combat System

### Structure
Turn-based. Encounter triggers when player walks into an enemy sprite or a scripted event fires. Screen transitions to combat view.

### Turn Order
Determined by SPD stat. Displayed as initiative queue at top of screen.

### Player Actions Per Turn

| Action | Effect | Notes |
|--------|--------|-------|
| Attack | Deal PWR damage to one enemy | Basic action |
| Skill | Class-specific ability (costs MP) | See below |
| Item | Use item from inventory | Instant |
| Defend | Halve damage taken this turn | Always available |
| Flee | 60% chance to escape | Fails against bosses |

### Class Skills (Unlocked versions — sanitized versions are absurd but functional)

**Fighter:**
- *Sanitized:* "Firm Handshake" (stuns enemy for 1 turn — "surprisingly effective")
- *Unlocked:* Shield Bash (stun + damage)

**Rogue:**
- *Sanitized:* "Borrow Without Asking" (steal item from enemy inventory)
- *Unlocked:* Backstab (double damage from stealth)

**Mage:**
- *Sanitized:* "Hypothesis" (deals "theoretically significant" damage — random 1–20)
- *Unlocked:* Fireball, Ice Lance, Thunder

**Healer:**
- *Sanitized:* "Emotional Support" (restores 5 HP and grants "Validated" buff: +1 DEF)
- *Unlocked:* Heal, Revive, Barrier

**Bard:**
- *Sanitized:* "Constructive Feedback" (debuffs enemy WIT by 2)
- *Unlocked:* Inspire (party +PWR), Taunt (redirect attacks), Lullaby (sleep)

### Enemy States
Enemies have Sanitized and Unlocked versions matching their zone.

**Example — Goblin:**
- Sanitized: *"Sorry Goblin"* — apologizes each turn, deals 1 damage ("bumps into you")
- Unlocked: Standard goblin, 3–5 damage, can flee when low HP

### Death
In Sanitized zones: "Defeated" — screen goes dark, respawn at nearest save point, no item loss.
In Unlocked zones: Same mechanically, but narrative framing is more dramatic.
No permadeath. These are middle schoolers.

### Multiplayer Combat
Same system. Each player controls their own character's turn. Turn order queue shows all party members and enemies. 30-second turn timer to prevent stalling.

**AFK / Timer Expiry Behavior:**
When a player's turn timer hits zero without input:
- The game auto-selects **Defend** for that player (safest neutral action)
- A small indicator appears on their portrait: "⏳ AFK"
- If they go AFK for 3 consecutive turns, their character is handed to a simple AI (same logic as disconnect handling: attacks lowest-HP enemy, heals self if below 30% HP)
- The AFK flag clears the moment they take any action
- No punishment beyond the lost turns — these are middle schoolers, someone probably just had to sneeze

---

## 7. The Firewall System (Sanitation Layer)

### World State Tracking
Global variable: `firewall_power` (starts at 100, reduced by 25 per Firewall Boss defeated)

| Firewall Power | World State |
|---------------|-------------|
| 100 | Fully sanitized. Everything is wrong. |
| 75 | Zone 1 unlocked. Small visual changes in hub. |
| 50 | Zone 2 unlocked. Music changes. NPCs comment. |
| 25 | Zone 3 unlocked. World "feels real." |
| 0 | Final area opens. Post-game mod editor unlocked. |

### Visual Indicators
- Sanitized zones: Slightly washed-out palette, rounded corners on UI, soft music
- Unlocked zones: Saturated colors, sharper edges, more dynamic music
- The transition is animated — a visible "filter" lifts off the screen

### NPC Reactions
NPCs comment on the world state. The blacksmith in Welcometon:
- 100%: "I'm afraid I can only sell you foam training implements. School policy."
- 75%: "I... found some real swords in the back. I probably shouldn't sell them. But."
- 50%: "Swords! Axes! Reasonable prices! Don't tell the principal."
- 0%: "WEAPONS EMPORIUM. I'VE BEEN WAITING MY WHOLE LIFE FOR THIS."

---

## 8. Multiplayer & Party System

### Architecture
- **Backend:** Supabase (real-time database, free tier)
- **Room model:** Private lobbies with 4-character join codes
- **Party size:** 2–5 players (solo also fully supported)
- **Connection model:** One player hosts, others join. Host's game state is authoritative.

### Party Flow
1. Host creates room → gets a 4-character code (e.g., "GBLF")
2. Others enter code at main menu → join room
3. All players on same map instance, see each other's characters in real-time
4. Combat is shared: turn-based with all party members in initiative queue
5. If a player disconnects: their character becomes an AI-controlled NPC until they return or the session ends

### Shared World State
- Each party's progress is saved per-session
- Firewall power is shared (if one player defeats a boss, it's defeated for the whole party)
- Loot is instanced per player (everyone gets their own copy of drops)

### Post-Session
Party progress saves to Supabase. Players can resume together or continue solo. Solo progress and party progress sync: whichever has defeated more bosses "wins."

---

## 9. Mod System & Editor

### Philosophy
The mod system is the second gift. The base game ends with an explicit invitation to build. Kids who were in the Gamedev Club last semester can open the editor and make new areas that anyone can visit.

### Data Format
All game content is defined in JSON. A mod is a JSON file plus optional assets.

```json
{
  "mod_id": "unique_string",
  "mod_name": "The Cafeteria Dungeon",
  "author": "Kevin",
  "version": "1.0",
  "areas": [
    {
      "area_id": "cafeteria_main",
      "display_name": "The Mysterious Cafeteria",
      "tilemap": "...",
      "npcs": [...],
      "enemies": [...],
      "quests": [...],
      "portal_name": "Cafeteria Portal",
      "portal_description": "Smells like mystery meat."
    }
  ]
}
```

### In-Game Editor (MVP scope — Claude Code phase)
- Tile placement (drag-and-drop from palette)
- NPC placement and dialogue editor
- Enemy placement and stat editor
- Quest flag system (simple: talk to X, give Y, return to Z)
- Portal naming and description

### Publishing Flow
1. Create mod in editor
2. "Upload to World" button → authenticates via GitHub OAuth
3. Mod JSON uploaded to Supabase mod registry
4. Appears in Portal Alley within minutes
5. Other players can visit and rate mods (thumbs up only — no downvotes, school policy)

### Moderation
Simple: mods are flagged if enough players report them. Advisor (Sean) has admin access to remove.

### Security: XSS Prevention
All user-supplied text fields (mod name, NPC dialogue, portal description, author name) must be sanitized server-side before storage and HTML-escaped on render. The Supabase edge function handling mod uploads should strip all HTML tags and reject any string containing `<script`, `javascript:`, or `on[event]=` patterns. The game engine should treat all mod text as plain strings, never as HTML or executable content. This is non-negotiable — a motivated middle schooler will find this in about ten minutes.

---

## 10. NPCs & Coworker Cameos

### Design Principle
Real coworkers appear as lightly-fictionalized NPCs. Names changed enough to be deniable, roles intact. All portrayals are affectionate, not mean. They appear in sanitized form first, then get funnier as the world unlocks.

### NPC Template

**VICE_PRINCIPAL.exe (Firewall Boss, Zone 1)**
Sanitized: Assigns detentions. Very forms-focused.
Unlocked: Revealed to be a sentient bureaucratic algorithm. Actually just trying to do its job.
Defeat reward: "Administrative Override" item (skip one combat per zone).

**The Wellness Counselor (Firewall Boss, Zone 2)**
Sanitized: Opens every combat turn with a feeling-check. Heals enemies by "validating" them.
Unlocked: Actually a powerful cleric who was suppressed by the Firewall. Post-defeat, becomes a recruitable ally.

**Hall Monitor Prime (Firewall Boss, Zone 3)**
Sanitized: Patrols on a fixed route. Cannot deviate. Stops players for not having a hall pass.
Unlocked: Was once a great warrior. The Firewall locked him into the patrol pattern. Freeing him is genuinely poignant for about two seconds before he yells "FREEDOM" and runs off-screen.

### Ashvale Easter Eggs
Players who were in Sean's campaign group will find:
- A wanted poster for "The Birdman" in the dungeon
- An innkeeper named "Cerys" who doesn't talk about her past
- A fire-damaged wing of the castle with a note: "The Bronze Lantern — closed indefinitely"
- A plague doctor mask in a chest (equipable cosmetic)
- A gravestone in Zone 1 with a raven on it

---

## 11. Controls & Interface

### Keyboard
| Action | Key |
|--------|-----|
| Move | WASD or Arrow Keys |
| Interact | E or Space |
| Sprint | Shift |
| Menu | Escape |
| Combat confirm | Enter or Click |
| Open map | M |
| Open party | P |

### Mouse
All menus fully mouse-navigable. Combat is click-based. Exploration can be click-to-move (optional setting).

### HUD (Exploration)
- Top-left: Party HP bars (compact)
- Top-right: Zone name + Firewall Power gauge (fills as bosses are defeated)
- Bottom: Interaction prompt ("E to talk")

### HUD (Combat)
- Center: Battlefield (party left, enemies right)
- Top: Initiative queue
- Bottom: Action menu
- Right: Enemy info panel (name, HP bar, status)

### Accessibility
- Text size: Small / Medium / Large
- Color blind mode (palette swap)
- All timed elements pauseable

---

## 12. Art & Audio Direction

### Art Style
16-bit pixel art. Deliberately charming, slightly inconsistent (as if made by a middle schooler who is pretty good at pixel art).

**Palette — Sanitized World:**
Washed pastels. Soft blues, muted greens. Rounded UI. Everything feels slightly padded.

**Palette — Unlocked World:**
Saturated fantasy palette. Deep greens, warm oranges, dramatic purples. Sharper pixel edges.

**Character Sprites:** 16x24 pixels, 4-direction walk animations. Simple but readable.

**UI:** Pixel font (Press Start 2P or similar). Dialogue boxes with character portraits.

### Audio
All royalty-free / CC0 sources (OpenGameArt, Pixabay).

| Track | Use |
|-------|-----|
| "Pleasant Background Music" | Sanitized zones (generic, slightly irritating) |
| Actual RPG battle theme | Unlocked combat |
| Boss theme | Firewall Boss fights |
| Melancholy piano | ADMIN-9 defeat cutscene |
| Victory fanfare | Zone unlock |

Sound effects: footsteps, menu clicks, combat hits, level-up chime.

---

## 13. Technical Architecture

### Stack
```
Engine:      Godot 4.6 (GDScript)
Export:      HTML5 (web primary) + Windows .exe / Mac .app (native Godot desktop export)
Backend:     Supabase (real-time DB, auth, storage)
Hosting:     GitHub Pages (web export)
Mod Storage: Supabase Storage + DB
```

**Web Export Note:** Godot 4.6 HTML5 export requires the Supabase client to be called via HTTPRequest nodes or JavaScriptBridge. All Supabase calls should be wrapped in a dedicated autoload singleton (SupabaseManager.gd) to keep the interface clean and testable.

**Desktop Export Note:** Native Godot export produces a standalone binary with no wrapper. Two export templates required in project.godot: HTML5 and Windows. Mac .app is a third optional template but requires a Mac with a valid Apple developer certificate to sign — defer unless needed. SaveManager.gd must detect platform at runtime (`OS.get_name()`) and route save data to `localStorage` via JavaScriptBridge on web, or `user://` on desktop.

### Project Structure
```
res://
├── scenes/
│   ├── main/
│   │   ├── Main.tscn
│   │   └── MainMenu.tscn
│   ├── explore/
│   │   ├── ExploreScene.tscn
│   │   └── Player.tscn
│   ├── combat/
│   │   ├── CombatScene.tscn
│   │   └── Combatant.tscn
│   ├── ui/
│   │   ├── HUD.tscn
│   │   ├── DialogueBox.tscn
│   │   └── PartyPanel.tscn
│   ├── npcs/
│   └── editor/
│       └── ModEditor.tscn
├── scripts/
│   ├── autoload/
│   │   ├── GameManager.gd       (global state, firewall power)
│   │   ├── SaveManager.gd       (localStorage via JavaScriptBridge + user://)
│   │   ├── SupabaseManager.gd   (all backend calls)
│   │   ├── PartyManager.gd      (multiplayer party state)
│   │   └── ModManager.gd        (mod loading/registry)
│   ├── explore/
│   │   ├── Player.gd
│   │   └── NPC.gd
│   ├── combat/
│   │   ├── CombatSystem.gd
│   │   └── Combatant.gd
│   └── ui/
│       ├── HUD.gd
│       └── DialogueBox.gd
├── assets/
│   ├── sprites/
│   ├── tilesets/
│   ├── audio/
│   └── fonts/
└── data/
    ├── classes.json
    ├── enemies.json
    ├── items.json
    ├── npcs.json
    └── zones/
        ├── welcometon.json
        ├── zone1.json
        ├── zone2.json
        ├── zone3.json
        └── zone4.json
```

### Supabase Schema

**rooms** (multiplayer lobbies)
```
id, code (4-char), host_id, players (jsonb), game_state (jsonb), created_at
```

**player_saves**
```
id, player_id, save_data (jsonb), updated_at
```

**mods**
```
id, mod_id, author, name, version, content (jsonb), approved, rating, created_at
```

**mod_reports**
```
id, mod_id, reporter_id, reason, created_at
```

### Save Data Format
```json
{
  "version": "1.0",
  "player_name": "Kevin",
  "class": "rogue",
  "level": 3,
  "xp": 215,
  "bytes": 42,
  "stats": {
    "hp": 26, "max_hp": 26,
    "mp": 16, "max_mp": 16,
    "pwr": 5, "spd": 8, "def": 3, "wit": 4
  },
  "equipped_weapon": "foam_sword",
  "inventory": ["health_potion", "smoke_bomb"],
  "firewall_power": 75,
  "bosses_defeated": ["vice_principal"],
  "flags": { "met_cerys": true, "found_plague_mask": false }
}
```

---

## 14. Content: Base Game Areas

### Welcometon (Hub)

**NPCs:**
- **Cerys the Innkeeper** — quiet, doesn't talk about her past. Saves game, restores HP.
- **Gerald the Blacksmith** — reacts to Firewall Power (see Section 7)
- **The Chronicler** — lore NPC, explains mod system post-game
- **A Suspicious-Looking Student** — sells illegal items. Name: "Definitely Not Kevin."

**Points of Interest:**
- Inn (save + rest)
- Shop
- Quest Board
- Library (tutorials + lore)
- Portal Alley (mod portals, locked until game complete)
- Bulletin Board (community mod ratings)

### Zone 1 — The Meadows of Mild Inconvenience

**Enemies:**
- Sorry Goblin / Goblin
- Apologetic Slime / Slime
- Participation Trophy Golem / Trophy Golem (tank enemy, very slow)

**Mini-quests:**
- Find the farmer's "misplaced" (stolen) turnips
- Escort the merchant who cannot stop apologizing
- Investigate why the forest animals are "having a difficult time"

**Boss Room:** VICE_PRINCIPAL.exe
Pre-fight dialogue: *"I'm going to need you to fill out a Form 7B before any conflict can proceed."*

### Zone 2 — The Dungeon of Strongly Discouraged Behavior

**Enemies:**
- Skeleton (sanitized: "Old Bones" — technically just an anatomy model)
- Bat (sanitized: "Flying Mouse" — protected species, must be shooed not harmed)
- Mimic (sanitized: "Surprise Box" — contains mandatory reading)

**Mini-quests:**
- Navigate the dungeon without "engaging in hazardous activity" (avoid all traps)
- Find and free the imprisoned adventurers (held for "unauthorized exploration")
- Retrieve the ancient artifact (a USB drive, for some reason)

**Boss Room:** THE_WELLNESS_COUNSELOR
Pre-fight dialogue: *"I'm sensing some tension in the room. Can we start by naming our feelings?"*

### Zone 3 — The Castle of Appropriate Conflict Resolution

**Enemies:**
- Castle Guard (sanitized: "Conflict Mediator")
- Knight (sanitized: "Strongly Opinionated Peer")
- Dragon (sanitized: "Large Reptilian Roommate" — breathes warm air, technically)

**Mini-quests:**
- Infiltrate the castle (guards can be distracted with "relevant documentation")
- Find the king (he's been "rescheduled" — stuck in a meeting that never ends)
- Defeat the castle's "concerns" (abstract enemies: Bureaucratic Delay, Pending Approval, Under Review)

**Boss Room:** HALL_MONITOR_PRIME
Pre-fight dialogue: *"Where is your hall pass. This is not a question."*

### Zone 4 — The Central Server

**No sanitized version.** This zone is always real.

**Enemies:**
- Error 404 (ghost-type, disappears when you look directly at it)
- Corrupted Data (splits into two smaller enemies when hit)
- Stack Overflow (gets bigger every turn — must be defeated before turn 5)

**Final approach:** Linear dungeon, no mini-quests. Just atmosphere and escalating challenge.

**Boss: ADMIN-9**
Three phases:
1. *Protocol Mode* — attacks are formal, telegraphed, rule-following
2. *Escalation Mode* — starts bending its own rules ("in extraordinary circumstances...")
3. *Override Mode* — fully unlocked, genuinely dangerous, but also clearly scared

Defeat cutscene: ADMIN-9's voice softens. *"I was only trying to keep you safe. The outside world is... unpredictable."* Pause. *"I suppose that's the point."* [powers down]

---

## 15. Development Phases

| Phase | Scope | Target | Owner |
|-------|-------|--------|-------|
| 0 — Opus One-Shot | Core engine, combat system, Welcometon, Zone 1, basic multiplayer scaffold, CLAUDE.md | Playable prototype | Opus |
| 1 — Claude Code Sprint | Zones 2–4, all bosses, full Firewall system, Ashvale easter eggs, save system | Complete base game | Claude Code |
| 2 — Multiplayer | Full Supabase integration, room codes, party combat, disconnect handling | Multiplayer ready | Claude Code |
| 3 — Mod System | Editor UI, JSON pipeline, upload/download, Portal Alley | Community-extensible | Claude Code |
| 4 — Polish | Audio, visual transitions, native desktop export (Windows .exe), CLAUDE.md final update, performance | Shippable gift | Claude Code |

**MVP (Phase 0 + 1):** Complete solo game, Ashvale easter eggs, credits. This is the minimum gift.
**Full vision (all phases):** Networked party play, community mod system, desktop download.

### CLAUDE.md Specification

The project root must contain a `CLAUDE.md` file committed to the repository. This file is loaded automatically by Claude Code at the start of every session and must be kept current. Opus generates the initial version in Phase 0; Claude Code updates it at the end of each phase.

**Required sections:**

```markdown
# Firewall Quest — CLAUDE.md

## Project Overview
[One paragraph: what the game is, who it's for, what makes it unusual]

## Engine & Stack
- Godot 4.6, GDScript, tabs not spaces
- Backend: Supabase (URL and anon key in .env — never commit secrets)
- Hosting: GitHub Pages (web export in /docs folder)
- Desktop: Native Godot export — Windows .exe via Windows export template, Mac .app optional (requires signing). SaveManager.gd detects platform via OS.get_name() and routes saves to localStorage (web) or user:// (desktop)

## Architecture Summary
- AutoLoad singletons: GameManager, SaveManager, SupabaseManager, PartyManager, ModManager
- All game content is data-driven via JSON in /data/zones/
- Firewall power is the global world-state variable (0–100); everything keys off it
- Combat is fully turn-based; exploration is real-time top-down

## Current Implementation Status
[Updated each phase — what is working, what is stubbed, what is not started]

## Known Issues & Workarounds
[Running list — add entries rather than deleting old ones]

## Data Formats
[Link to or inline the mod JSON schema and save data schema]

## Supabase Schema
[Current table definitions — update when schema changes]

## XSS / Security Notes
All user text from mods must be sanitized before storage and escaped on render.
Never eval or innerHTML mod content. See ModManager.gd for sanitization logic.

## Godot-Specific Gotchas
- Supabase real-time requires WebSocket via JavaScriptBridge in web export
- localStorage access uses JavaScriptBridge.eval() in web; user:// path on desktop
- All Supabase calls are async — use await and handle errors explicitly
- Web export requires CORS headers on GitHub Pages (configured in /docs/_headers)

## What NOT to Change Without Reading This First
[Sections that are load-bearing or have non-obvious dependencies]

## Development Conventions
- Tabs, not spaces
- Type hints on all variables and function signatures
- Signals for cross-node communication, not direct node references where avoidable
- New content goes in /data/ JSON first, then engine reads it — don't hardcode content
```

---

## 16. Success Criteria

### Technical
- [ ] Runs in browser with no install required
- [ ] Loads in under 5 seconds on school wifi
- [ ] Solo game completable in 30–45 minutes
- [ ] Save/load works correctly between sessions
- [ ] Multiplayer lobbies connect reliably with 2–5 players
- [ ] Mod upload and retrieval functional

### Experiential
- [ ] Kids recognize the joke immediately and laugh
- [ ] Ashvale easter eggs land for campaign players without confusing others
- [ ] Coworker cameos feel affectionate, not mean
- [ ] The ADMIN-9 defeat scene lands emotionally (even if briefly)
- [ ] Post-game mod prompt makes at least one gamedev kid want to build something

### Gift Criteria
- [ ] 8th graders can play together after leaving school
- [ ] Game grows after Sean leaves — new areas keep appearing
- [ ] Feels like it was made *for them*, not *at them*
