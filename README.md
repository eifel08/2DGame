# 2DGame — Metroidvania Core (Godot 4)

The core engine for an original 2D Action-Metroidvania.
It is a native Godot 4 project written in GDScript.
It has no plugins and no add-ons.

Tested with **Godot 4.3**. Newer 4.x versions open it too; Godot may offer to upgrade the project files.

## Clone and run

1. Install Godot 4.3 or newer (the standard build, not .NET): https://godotengine.org/download
2. Clone the repository:
   ```bash
   git clone https://github.com/eifel08/2DGame.git
   ```
   Or on GitHub: **Code → Download ZIP**, then unzip.
3. Start Godot. In the Project Manager click **Import**, select `2DGame/project.godot`, then **Import & Edit**.
4. The first opening imports the assets. This takes a few seconds.
5. Press **F5** (or ▶) to play. The title screen opens: choose **Play**, then a save slot.

To pull later changes: `git pull` inside the `2DGame` folder, then reopen the project.

## Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Move / aim | Arrow keys or WASD | Left stick / D-pad |
| Look up / down (stand still, hold) | Up / Down | Left stick / D-pad |
| Jump (hold = higher) | Space / Z | A |
| Drop through a platform | Down + Jump | Down + A |
| Attack (directional) | J / X (hold Up or Down to aim; Down only in the air) | X |
| Dash | K / C / Shift | RB |
| Heal (hold, chunk by chunk) | L / V (on the ground) | LB |
| Ultimate slot 1 / 2 / 3 / 4 | 1 / 2 / 3 / 4 | Y / RT / LT / R3 |
| Ultimate slot 5 – 8 (only when the slot capacity allows) | 5 / 6 / 7 / 8 | — |
| Interact (talk, read, save) | E / F (checkpoints: also Down) | B |
| Pause menu | Esc / P | Start |
| Inventory | I / Tab | Back / Select |
| Inventory: switch tab | Left / Right on the tab row (also Q / E, PgUp / PgDn) | D-pad, LB / RB |
| Inventory: move / confirm | Arrows or WASD; Z / Enter / Space | D-pad, A |
| Inventory: cancel slot choice | Backspace / Delete | X |
| Debug overlay | F1 or ` / ~ | — |
| Debug overlay keyboard mode | F2 (pauses; arrows, Enter, Left/Right on sliders) | — |
| Reset room | R | — |

Keys can be rebound in **Settings → Controls** (title screen or pause menu). The defaults live in **Project → Project Settings → Input Map**.
Every menu (title, slot select, settings, pause, inventory) works with the mouse and with the keyboard or gamepad.
- Arrows or WASD move the focus. Enter, Space or Z confirms. A click works too.
- Only one button is highlighted at a time (gold frame). Hovering with the mouse moves that highlight.
- Up and Down wrap around, so the first and last buttons are always reachable. In Settings, Down goes all the way to **Back**.

## Systems

### Movement
Crisp acceleration and stopping, dynamic jump height, double jump, dash with i-frames, coyote time and jump buffering. Gravity defaults to 2100, a little low, to give more reaction time for pogo chains.

**Walls:** press into a wall while falling and **wall friction** slows you to a slide. Press jump to wall-jump. Wall jumps have a fixed height (a quick tap is enough). Holding toward the wall as you jump makes a "climb jump" with a smaller push, so you swing back and can **climb a single wall** with consecutive wall jumps. A wall jump or slide refreshes your double jump and air dash.

### Combat
Directional attacks (left, right, up, down) and the downward pogo bounce off enemies and spikes.
The pogo is forgiving: the downward swing has a wide hitbox (78 × 80 px, `Config.combat.pogo_hitbox`), stays active a little longer, and an attack press is buffered for 0.16 s. Hits trigger hitstop and screen shake. Enemy contact deals damage, knocks you back and starts the i-frames.

### Energy, healing and ultimates
- **One shared energy meter.** Basic attacks fill it.
- **Two ways to heal:**
  1. **Channel (risk and reward):** hold L on the ground. Healing comes in **chunks**.
     - While a chunk channels, energy drains and the health it will give appears as a **white** segment on the health bar.
     - When the chunk completes, the white segment turns **red**: that health is now yours. A short pause follows, so you can let go safely. Keep holding to start the next chunk.
     - If you let go early, jump or get hit before the chunk completes, the drained energy is **lost** and no health returns.
     - You cannot start without enough energy for a whole chunk.
     - Chunk size, energy cost, duration and pause are in `Config.vitals` (`heal_chunk_*`) and in the debug overlay.
  2. **Save at a checkpoint:** see below. Saving restores full health.
- **Heal-ready glow:** the energy bar glows green, with a light sweep, whenever it holds enough energy for one full heal chunk. A small green dot under the bar marks a chunk's cost.
- **Hotkey slots (1–4 by default).** Each slot holds one ultimate, or nothing. There is no switching.
  - The **slot capacity** sets how many slots are usable: 1 to 8, default 4 (keys 1–8). It is saved per slot file and can be changed in the debug overlay. Lowering it empties the slots past the new limit.
  - Defaults: 1 Nova Burst, 2 Spirit Volley, 3 Ascendant Form, 4 Comet Dash. All eight spells start **known** (in the inventory pool).
- **The eight spells.** Energy thresholds are defaults in `Config.ultimates` and can be tuned live in the debug overlay.

  | Spell | Type | Energy | What it does |
  | --- | --- | --- | --- |
  | Nova Burst | AoE blast | 33 | Expanding shockwave around the player. |
  | Spirit Volley | Projectiles | 50 | Fan of homing bolts. |
  | Ascendant Form | Buff | 100 | More damage, speed and reach for a while. |
  | Comet Dash | Mobility strike | 25 | Aimable invulnerable charge, then a blast. |
  | **Repulse Aegis** | Counter (parry) | 20 minimum, **consumes all energy** | No wind-up. Opens a **0.2 s** counter window. If an enemy touches you inside it (or comes within 6 px of your body), its contact damage is negated and it takes **150 %** of the energy consumed. **Enemy contact only:** projectiles are not blocked and hurt as usual. Cast too early and the energy is wasted. |
  | **Stasis Field** | Emergency escape | 80 | Near-instant (0.05 s) pulse: enemies and hostile projectiles within **90 px** freeze in place for **0.8 s**. A last-second escape, not area control. Frozen enemies cannot move or hurt you but can still be hit. Frozen projectiles hang harmless, then fly on. |
  | **Radiant Lance** | Beam | 60 | A long piercing beam forward, or straight up while holding Up. It stops at walls and hits each enemy once. |
  | **Meteor Slam** | Dive strike | 30 | Invulnerable straight-down plunge that hits enemies on the way, then a wide ground shockwave and short landing i-frames. Cast in the air, it dives at once. **Cast on the ground, you first hop up** (about 0.25 s): the hop is a **vulnerable** wind-up, and a hit during it cancels the slam. |
- **Color-coded energy bar, no numbers.** Each equipped slot puts a mark on the bar at the energy it needs. Under the bar, the hotkey strip shows the four slots from left to right, each with its icon and its **actual key** (1–4 by default; a key rebound in Settings shows its new name). A mark or slot is bright when there is enough energy.
  - The color follows the energy tier, not the spell: green (low), yellow, orange, pink (full).
  - Empty slots have no mark.
- **No exact stats for the player.** Abilities, tooltips and lore never show energy numbers. Each ability shows a small gauge filled to its requirement instead. Exact values appear only in the debug stats view.

### Checkpoints, safe ground and death
- **Spikes:** damage, then you reappear on the **last safe ground** you stood on, a few steps back. **I-frames never protect against hazards** (see *Damage sources* below). Because you are always moved out, a damage loop is impossible.
- **Death:** only when health reaches zero (from enemies or spikes) do you respawn at the checkpoint where you **last saved**.
  - A short collapse animation plays first (red flash, death sound). Then the screen fades.
  - Respawning works like a save: weak and strong enemies return. Energy starts at **0**.
  - Dead enemies stop hurting at once: their contact damage, hurtbox and body collision switch off the moment they die.
- **Trance:** after saving at a checkpoint, after a death, or when a save loads, you float in a trance at the checkpoint. You are safe there. Any **new** button press wakes you. A key you were already holding does not.
- **Checkpoints save only on purpose.** Standing near a flame does nothing. Press **E** (or **Down** on the ground) to save: the flame lights, you snap to its exact center, and your health is fully restored. No text appears. Only at the flame where you saved can you change the loadout.
- **Info tablet:** one tablet stands just before the very first checkpoint. Reading it is optional; it explains saving, death respawn and the loadout rule. Later checkpoints have no tablet.
- The debug toggle *Spikes → Safe Ground* (on by default) can send spike hits to the checkpoint instead.

Checkpoint art is modular. Replace the polygons under `Visual` in `world/objects/checkpoint.tscn`, and edit or replace its animations named `inactive`, `activate` and `active`.

### Camera
The camera follows the player and never shows anything outside the room. **Look up / down:** stand still on the ground and hold Up or Down. After a short delay (0.3 s, so quick taps for aimed attacks do nothing) the view pans up to 160 px that way, within the room bounds. Moving or letting go brings it back. Tune it in `Config.camera` or the debug overlay (*Camera*).

### Rooms and openings
> **Design rules:** read [`GUIDELINES.md`](GUIDELINES.md) before changing any room, exit or feedback. Rule A: ground right below every downward exit. Rule B: an upward exit puts you beside the gap, on floor. Rule C: secret walls stay breakable and open during arena fights. Rule D: every room and hidden pocket is closed by solid walls wherever there is no transition. Rule E: the way out of a secret room looks like an ordinary open doorway. Rule F: no celebrations anywhere.

The world map has six rooms:

```
 Hidden Vault  ⇄ (secret doorway) ⇄  Upper Galleries
                                          ⇅ (gap in the ceiling)
                                    Testing Halls  ⇄  Sentinel's Arena  ⇄  Proving Grounds  ⇄ (breakable wall) ⇄  Hidden Shrine
```

- **Seamless transitions.** A room exit is simply a place where the wall is missing. There is no light, arrow, sound, fade or pause. Walk, jump or fall through the opening and you are in the next room, at the same height (or the same spot along a ceiling gap), with the same speed.
- **Ceiling gap:** in the Testing Halls, the ceiling is open above the central hanging wall. Climb the wall (or wall-jump up its side) and jump. You come up **through** a gap in the floor of the **Upper Galleries**: you rise out of the opening, then an arc throws you onto the floor to its left or right (Rule B), a side room with ordinary enemies (weak and strong dummies, flyers), shards and platforms. No boss and no arena. Drop back through the floor gap to return; you land on the wall cap, which spans the whole ceiling gap (Rule A).
- **Proving Grounds** is a dedicated arena room with its own checkpoint and three waves. Once cleared, it stays cleared.
- **Secret passage:** at the far east end of the Proving Grounds, the outer wall has a section that is really a breakable wall. It sits exactly where the solid wall would be and looks like it, apart from faint cracks. Strike it three times. This works even while the arena fight runs, and the passage is never locked by it (Rule C). It crumbles at once (debris and a crash, no jingle, flash or message), and opens the way to the **Hidden Shrine**. The shrine holds a lore tablet, shards and a **relic** that raises max health for this save. The broken wall and the relic are saved.
- **Secret walls (walk through, no attack).** There are two types; [`GUIDELINES.md`](GUIDELINES.md) ("Secret walls") is the binding description.
  - **Type 1 — Hidden Pocket** (`HiddenPocketWall`, layout letter `I`): hides a pocket of the **same** room. Everything inside (shards, enemies, doors) is covered until the first pass. Until then the wall is **one-way**: you can walk in from its entry side, but from the pocket side it is solid. The first pass reveals it **for good**: the disguise and the cover vanish, it opens both ways, and the find is **saved**. It never hides again after a room change, a death or a save load. It is silent (Rule F), and enemies never pass it.
    - **Upper Galleries, east:** the alcove under the east block, near the right edge. Walk in from the left: two shards and a training dummy.
    - **Testing Halls, far west:** the west wall at floor level, left of the first tablet. The pocket lies **beyond the room's normal left edge**. Until you break through, the camera never scrolls left of the room. Afterwards it follows you into the pocket (two shards), and keeps doing so for this save.
  - **Type 2 — Secret Doorway** (`SecretDoorway`, layout letters `X` / `x`): a normal room transition to **another** room, disguised as wall. It is never consumed: walk through it back and forth as often as you like. From the **entry** side it is drawn **semi-transparent**; from the **exit** side (inside the secret room) it is an ordinary **open doorway** with nothing drawn (Rule E).
    - **Upper Galleries, west wall ⇄ Hidden Vault** (a secret room with shards).
  - **Placeholders:** each type has its own art nodes. Type 1 has `Visual` (the disguise, 50 % opacity) and `Cover` (the pocket, solid rock), plus an optional `reveal` clip. Type 2 has `EntryVisual` (50 % opacity, entry side only), plus an optional `pass` clip; its exit side draws nothing (Rule E). Empty nodes are filled with wall tiles at runtime; put your own art in and it is used instead.
- Each room is its own scene in `world/`. They are loaded on demand by `core/game.gd` (`ROOM_SCENES`).

### Enemy tiers and respawning
Progress that outlives a room load is kept in `core/world_state.gd` and written to the save slot.

| Tier | Example | Comes back… |
| --- | --- | --- |
| Weak | training dummies | when you enter its room again, save at a checkpoint, die, or load the save |
| Strong | armored dummy (on the upper right ledge) | only when you save at a checkpoint, die, or load the save |
| Boss | Hollow Sentinel | never in this playthrough |

- Dead enemies stay dead. There is no timed respawn.
- An enemy that was damaged but survived is back at **full health** when you leave its room and return.
- Saving at a checkpoint also restores the room's enemies right away (bosses excluded).
- Placed shards you collected stay collected.

### Boss: the Hollow Sentinel
The Sentinel waits in the Boss Room. It always tracks you: it turns to face you, walks toward you, and aims each attack at where you stand when the attack starts. Every attack is announced by white eyes and a flash ring.
- **Charge:** a lunge that runs past your position. Jump over it.
- **Leap:** it jumps to land on you, then slams. The slam sends shockwaves along the floor both ways; jump them.
- **Volley:** shards aimed at you, in a spread.
- **Phase 2** (below half health): shorter warnings, faster moves, more shards.
- Its health bar appears at the top of the screen during the fight. A defeated Sentinel never returns.
- **Death:** it rears up and screams (a low roar and a shudder), then dissolves into purple particles. That is all: no freeze, no celebration effect, no fanfare and no text. Play simply goes on.

### Arena encounters
The Boss Room is an **arena**. Stepping in seals the doorway with gates, then the waves follow:
1. Weak dummies and a flyer.
2. A strong dummy.
3. The boss.

Each wave starts once the previous one is defeated. After the last wave the gates open, and the arena is **cleared for good**. Clearing an arena is strictly environmental: the gates open with a mechanical clunk, no more enemies come, and play goes on. There is no fanfare, no effect, no flash and no text (GUIDELINES.md, Rule F). If you die inside, the attempt resets and the arena starts fresh next time.

**Telegraphed spawns (arenas only):** arena wave enemies appear through a short portal. For 0.35 s they fade in, harmless and impossible to hit. No timer or text is shown. They never appear on top of you: a spawn point too close to the player moves aside. Everywhere else enemies simply appear, with no telegraph.
- Arenas are data: in a room scene, `Objects/Arena` has a trigger rect, gate rects, and `Waves/Wave1`, `Wave2`, ... with marker children (meta `kind`: `weak`, `flyer`, `strong` or `boss`).
- The logic is in `core/arena_director.gd`. Add a wave by adding a `WaveN` node with markers.

### Layout and collision
- Solid tiles light every face that borders open space, so the drawn edges are exactly the collision edges.
- The background is dim, with fading tops, so it never looks like something you can stand on. The HUD sits on its own backing panel.
- The camera, including screen shake, never shows anything outside the room.
- Every opening in a room's outer wall (sides, ceiling, floor) is an exit. The automated test checks all of this.
- With *Hitboxes & Stats* on, the debug view also outlines solid tiles, door triggers and arena areas.

### Damage sources and i-frames
Damage to the player comes from exactly three sources (`combat/damage.gd`, `Damage.Source`). Each has its own rule, decided in one place: `HealthEnergy.blocks(source)`.

| Source | Examples | I-frames / invulnerability protect? |
| --- | --- | --- |
| `ENEMY` | Touching a creature (dummies, the boss's charge) | **Yes** |
| `PROJECTILE` | Anything fired, by an enemy or by a hazard (boss shards, shockwaves, a future turret) | **Yes** |
| `HAZARD` | Touching the environment (spikes; later lava, acid) | **Never**: not post-hit i-frames, dash, casts or the Meteor Slam dive. Only the debug *God Mode* protects. |

- A projectile fired by a hazard is still a `PROJECTILE`. Only direct contact with the hazard bypasses i-frames.
- Enemy and projectile hits go through `Player.receive_hit(..., source)`; hazards go through `Player.hazard_respawn()`.
- Hit guards (such as Repulse Aegis) receive the source and only ever see enemy and projectile hits.

### Hazards
Spikes damage the player (see above). **Enemies that touch spikes die instantly**, and **shards that touch spikes disappear**.

### Currency (Shards)
Shards (◆) lie on ledges around the room, and destroyed enemies drop them. The total shows in the top-right corner and in the inventory. Placed shards return when you reset the room (R). Collected currency is kept.

### Dialogue, lore and explanations
Walk up to an NPC or a lore tablet. An "E Talk" or "E Read" prompt appears. Press E to open the dialogue. Press E, Space or J to reveal the page and then to turn it. The game pauses while dialogue is open.
- **Archivist Mira** (next to the start) explains healing, checkpoints, currency, the ultimate keys and the loadout rule.
- **Tablets** explain wall jumps (left shaft), spikes and the pogo (on the raised block), and the four ultimates (center).

Dialogue texts are `DialogueData` resources in `dialogue/`. Edit them in the Inspector, or create new ones (FileSystem → New Resource → DialogueData). Assign one to any `lore_stone.tscn` or `npc.tscn` instance.

### Inventory and loadout (I / Tab)
The game pauses while the inventory is open. It has two tabs (switch with Q / E):
- **Status:** shards (the only number), plus health and energy as bars. A bar's frame grows when its maximum increases (`max_health_bonus` / `max_energy_bonus`; the debug overlay has buttons to test this).
- **Abilities:** the top row shows hotkey slots 1–4, left to right. The bottom grid shows every unlocked ability with a normal, crisp icon. Equipped ones carry their key number.
  - Cards show **icons and energy gauges only**. The name and description appear below only for the focused card.
  - **Keyboard flow:** Left / Right on the tab row switches tabs, and Down enters the cards.
    - Confirm (Z / Enter / Space) on an **equipped** ability, in a slot or in the grid, **unequips** it.
    - Confirm on a **free** ability, then choose slot 1–4. An empty slot takes it. An occupied slot has its ability **replaced**.
    - Backspace cancels the slot choice.
  - **Changes only work at the checkpoint where you saved.** Elsewhere you can browse but not change anything, and `UltimateManager.equip` / `unequip` enforce this in code too.

### Title screen, save slots and settings
- **Title screen:** Play, Settings, Quit.
- **Play** opens the slot select. There are **5 independent slots**. A used slot shows the location, the shards and the play time. An empty slot reads **New Game**. *Delete* asks for confirmation (press it twice).
- **A slot stores:** the saved checkpoint and room, shards, unlocked and equipped abilities, health/energy growth, defeated bosses, cleared arenas, collected shards, opened secrets and relics. Respawnable enemies are not stored.
- **Saving happens** when you save at a checkpoint, clear an arena, defeat a boss, break a secret wall or take a relic.
- **Loading** puts you at the saved checkpoint, in a trance, with 0 energy and the respawnable enemies reset.
- Save files are JSON in `user://saves/slot_N.json`.
- **Settings:** master, music and effects volume, screen shake, fullscreen, and key rebinding (choose a key, then press the new one; Esc cancels). *Reset controls* restores the defaults. Settings are kept in `user://settings.cfg`.
- **Pause menu (Esc):** Resume, Settings, Quit to title. The game is paused while it is open. The inventory is not in this menu; it opens only with its own key (I / Tab).

### Placeholder art, animation and sound (swap without code changes)
Gameplay code never draws art or builds sounds. It only asks for things **by name**. Everything visible or audible is a placeholder in its own node or file:

| What | Where | How to replace |
| --- | --- | --- |
| Player poses (idle, run, attack, heal, hurt, **dying**, **trance**, ...) | `player/player_rig.tscn` + `player/player_animations.tres` (AnimationPlayer) | Swap the rig for sprites or an AnimatedSprite2D; keep the clip names. |
| Enemy and boss poses (idle, move, hurt, dead, **spawn**; boss: telegraph, charge, leap, volley, **roar**, **dissolve**) | `enemies/*_rig.tscn` + `enemies/*_animations.tres` | Same: new rig, same clip names. |
| Checkpoint flame, relic, secret wall | `Visual` node + AnimationPlayer in each object scene (`world/objects/`) | Replace `Visual`; keep the clip names (wall: `idle`, `hit_1`, `hit_2`). |
| Secret walls, Type 1 hidden pocket | `Visual` (disguise, 50 % opacity) and `Cover` (hides the pocket) in `world/objects/hidden_pocket_wall.tscn`; optional AnimationPlayer clip `reveal` | Put your art (vines, darkness, fake stone) into the nodes; empty nodes get placeholder wall tiles. |
| Secret walls, Type 2 secret doorway | `EntryVisual` (50 % opacity, entry side only) in `world/objects/secret_doorway.tscn`; optional AnimationPlayer clip `pass`. The exit side stays an open doorway (Rule E). | Same: your art replaces the placeholder tiles. |
| Particle effects (hits, dust, portal, boss dissolve, arena clear, wall break, ...) | One scene per effect in `effects/fx/<name>.tscn` (root: `FxPlayer`) | Open the scene, delete the placeholder children, add your own CPUParticles2D / GPUParticles2D / AnimatedSprite2D / AnimationPlayer ("play" clip). |
| Sounds | `audio/sfx.tscn` (the `Sfx` autoload): one **AudioStreamPlayer** per sound, named after it. Files in `audio/sfx/<name>.wav` | Overwrite the `.wav` with the same name, or drop a file on the node's Stream. |

- Sounds play on the **SFX** bus; a **Music** bus is ready for music (`default_bus_layout.tres`).
- The placeholders are made by `tools/build_assets.gd`. It never overwrites a file that exists, so your replacements are safe. Delete a file to get its placeholder back.

### Text direction
The UI is always laid out left to right, even on a system set to a right-to-left language. This is set in `project.godot` (`root_node_layout_direction`) and on every panel. Dialogue text is laid out for the whole page before typing starts, so lines never shift or re-wrap while the letters appear.

### HUD
The HUD is clean by default: health and energy bars, threshold marks, the hotkey strip and the shard count. It has no numbers except the shards. Turn on **Hitboxes & Stats** in the debug overlay (or simply open it) to see exact health, energy, enemy health, damage numbers and hitboxes.

## Test checklist

| Feature | How |
| --- | --- |
| Title and slots | Start the game: Play → choose a slot. Try both the mouse and the arrows + Enter. |
| Save slots | Save at a flame, quit to title (Esc → Quit to title), pick the same slot: you wake at that flame with 0 energy. Other slots are untouched. |
| Death and trance | Let health run out: a short collapse plays, then you float at your flame. Press any button to wake. Dummies are back. |
| Secret passage | Proving Grounds, far east: strike the cracked wall three times, walk through, take the red relic. |
| Hidden pocket (Type 1) | Upper Galleries, under the east block: what looks like solid rock with a faint column on its left. Walk right into the column: the cover vanishes and you are in an alcove with shards and a dummy (no attack). It stays open both ways, also after leaving the room or reloading the save. |
| Hidden pocket beyond the room edge | Testing Halls, at the start: walk left past the first tablet into the faint wall at floor level. Before that, the camera never shows anything left of the room. Once through, it scrolls into the pocket. |
| Secret doorway (Type 2) | Upper Galleries, west wall at floor level: a faint, semi-transparent section. Walk into it: you are in the Hidden Vault. Its east side has an ordinary open doorway (Rule E): walk through it to go back. Repeat as often as you like. |
| Solid boundaries (Rule D) | After breaking into the Testing Halls' west pocket, keep walking left: you stop at a solid wall, and that wall is on screen. |
| Spawn portal | Debug overlay → spawn an enemy, or enter an arena: enemies fade in through a portal and cannot hurt you yet. |
| Seamless exit | Run to the far east end of the Test Room: you keep running into the Boss Room, with no fade. Run back left to return. |
| Ceiling gap | Climb the central hanging wall, jump from its top: you rise out of the floor gap of the Upper Galleries and arc onto the floor beside it. Fall back through the floor gap to return. |
| Look up / down | Stand still at the start and hold Up: the view pans up. Climb the central hanging wall and hold Down: it pans down. Walk: it snaps back. |
| Arena and boss | In the Boss Room, step forward: gates close, waves come, then the Hollow Sentinel. Clear it, leave and return: nothing repeats. |
| Boss targeting | Move around the Sentinel: it turns, follows you, and aims charges, leaps and shards at you. |
| Respawn rules | Defeat a dummy and wait: it stays down. Go to the Boss Room and back: weak dummies return. The strong dummy (upper right) returns only after you save at a flame. |
| Survivors heal | Damage a dummy, leave the room, return: it is at full health. |
| Heal glow | Hit dummies until the energy bar glows green: a heal chunk is ready. |
| Wall friction | Fall next to a wall while holding toward it: you slide slowly. |
| Single-wall climb | Central hanging wall: hold toward it and tap jump each time you touch it. You climb to the top. |
| Chunk healing | Hold L with enough energy: the white segment grows, then turns red. Let go halfway: the energy is gone and no health returns. |
| Explicit saving | Walk to the middle flame: nothing happens. Press E or Down: you snap to the flame and are fully healed. |
| Spikes vs death | Walk into a spike pit: you reappear just before it. Let health run out (debug: *Take Damage*): you wake at the flame where you saved. |
| Shards on spikes | Destroy the right-hand dummy near its pit so shards fly in: they vanish. |
| Loadout | At your saved flame: I, Right (Abilities), Down. Confirm on an equipped ability to remove it. Confirm on a free one, then pick a slot (an occupied slot is replaced). |
| Icons and details | Move focus over ability cards: the name and description appear only for the focused one. |
| Left to right | Slots read 1-2-3-4 left to right in the HUD and the inventory. Dialogue types from the left. |
| Hotkeys on slots | Settings → rebind Ultimate 1: the first HUD slot shows the new key. |
| Checkpoint tablet | The only tablet stands just before the first flame. Saving at any flame shows no text and starts the trance. |
| Dialogue | Walk to the robed NPC right of the start, press E. |
| Debug, keyboard only | F1, then F2: arrows, Enter, Left/Right on sliders. F2 again resumes. |
| Repulse Aegis | F1 → *Max Energy*. Put the Aegis on a key (F1 → *Auto-Equip Known* with capacity 8, or the inventory at a flame). Walk toward a dummy and cast it **just before** you touch it: a gold hexagon flashes and shrinks, you take no damage, and the dummy takes 150 damage (100 energy × 1.5). Cast it early: the hexagon vanishes, the energy is gone, and the touch hurts. In the Boss Room, a shard still hurts during the window. |
| Stasis Field | Let a dummy walk right up to you, then cast: a small blue ring snaps open, the dummy stops and turns blue for under a second. An enemy a few steps away is not affected. In the Boss Room, cast it as a shard is about to hit you: it hangs in the air. |
| Hazards ignore i-frames | F1 → *Take Damage*, then at once walk into the spike pit: you still lose health. Cast Meteor Slam above a spike pit: the dive does not protect you. A dummy touching you during i-frames still does nothing. |
| Radiant Lance | Face a dummy and cast: a pink beam hits it. Hold Up while casting: the beam fires straight up. |
| Meteor Slam | Jump above a dummy and cast: you plunge down (invulnerable), land with a green shockwave and the dummy is hit. Cast it on the ground: you hop up first. Get touched by a dummy during the hop: you are hurt and no slam follows. |
| Known spells | F1 → *Spells*: untick a spell. It leaves the inventory pool and its slot. Tick it again to relearn it. |
| Slot capacity | F1 → *Spells → Equip Slots*: drag to 2. The HUD and inventory show two slots, and key 3 does nothing. Drag to 8: keys 1–8 work. |

## Project layout

```
autoload/config.gd       Config: every tunable value + energy tier colors
autoload/events.gd       Events: global signal bus
autoload/sfx.gd          Sfx: placeholder sounds, audio buses
autoload/settings.gd     Settings: volumes, screen shake, fullscreen, key bindings
autoload/saves.gd        Saves: 5 JSON save slots
scenes/title.tscn        title screen (main scene): Play → slots, Settings
scenes/game.tscn         the game: rooms, player, HUD, menus
core/game.gd             composition root: fixed-step loop, checkpoints, interaction, pickups
player/
  player.gd, states/     movement state machine (normal, dash, heal, cast, ability, hurt, dying, trance, eject)
  player_data.gd         currency, unlocked abilities, 4 equipped slots
  player_animator.gd     animation state machine (rules → animation name)
  player_rig.tscn        placeholder skeleton; swap art here
stats/health_energy.gd   health, shared energy, healing, i-frames, growth bonuses
combat/                  melee, pogo, damage API, contact/hazard damage, projectiles;
  damage.gd              the three damage sources (enemy, projectile, hazard) and their i-frame rules
ultimates/               ability base class, slot manager (keys 1-8, capacity), the 8 abilities
enemies/
  enemy.gd               shared enemy base (tiers, health, contact damage)
  dummy_enemy.gd         weak / strong training dummies (ground + flying)
  boss_sentinel.gd       the intro boss and its attack patterns
world/
  room.gd                world queries (solid, hazard, ground, safe ground, doors, arena)
  test_room.tscn         test room: platforms, walls, 2 spike pits, objects, east exit, ceiling gap
  upper_room.tscn        Upper Galleries: side room above the test room, standard enemies
  boss_room.tscn         boss room: arena with waves and the Hollow Sentinel
  arena_room.tscn        Proving Grounds: arena room with a cracked wall
  secret_room.tscn       Hidden Shrine: relic, tablet, shards
  objects/               interactable base, checkpoint, lore stone, NPC, coin, door, breakable wall, relic,
                         secret walls: secret_wall (base), hidden_pocket_wall (Type 1), secret_doorway (Type 2)
dialogue/                DialogueData resources (NPC + lore texts)
ui/                      HUD, dialogue box, inventory, debug overlay, title, pause and settings menus
tools/build_assets.gd    regenerates rigs, animations, TileSet, room and input map
core/world_state.gd      dead enemies, bosses, arenas, collected shards
core/arena_director.gd   arena waves: start, next wave, clear, abort
effects/fx/               one scene per visual effect (placeholders), FxPlayer
audio/sfx.tscn, sfx/     the Sfx autoload: one AudioStreamPlayer per sound + .wav placeholders
GUIDELINES.md            binding design rules A-D (transitions, secret walls, no celebrations)
tests/smoke_test.tscn    automated headless test (342 checks)
```

## Extending

- **New ultimate:** extend `UltimateAbility` in `ultimates/abilities/`, add a config block to `Config.ultimates`, and register it in `ultimate_registry.gd`. Every registered ability starts known; `UltimateManager.set_known(id, false)` removes one. It then appears in the inventory pool, in the debug overlay's *Spells* list and cost sliders, and can be slotted at a checkpoint. Give it an icon by adding a `match` case in `ui/ability_icon.gd`.
  - Optional hooks, no engine changes needed:
    - `pay_cost(health)`: a special energy rule (Repulse Aegis consumes the whole meter).
    - `Player.add_hit_guard(id, callable)`: intercept incoming enemy and projectile hits (counters, shields). The callable gets `(damage, attacker, source)`; check `source` (`Damage.Source`).
    - `Player.begin_ability_control(self)`: take over movement (Comet Dash, Meteor Slam). Set `invulnerable` for i-frames.
    - `Enemy.freeze(duration)` and `ProjectileSystem.freeze_in_circle(...)`: crowd control.
- **New lore or NPC:** create a `DialogueData` resource and assign it to an instance of `world/objects/lore_stone.tscn` or `npc.tscn` under `TestRoom/Objects`.
- **New interactable:** extend `Interactable` and override `interact(game)`. Put the node under `Objects`.
- **Real sprites, effects and sounds:** see *Placeholder art, animation and sound* above.
- **Edit the room:** paint in `world/test_room.tscn`, or edit `ROOM_LAYOUT` in `tools/build_assets.gd`. Delete `world/test_room.tscn`, then run:
  ```bash
  godot --headless --path . --script res://tools/build_assets.gd
  ```

## Automated test

```bash
godot --headless --path . --fixed-fps 60 res://tests/smoke_test.tscn
```

It plays the game through real input actions and checks 342 behaviors. New in this version: the two secret wall types. Type 1 hidden pockets: covered contents (shards and an enemy), one-way until found, found by walking through, permanently un-hidden, saved, and kept through room changes and save loads. The far-west pocket of the Testing Halls lies outside the normal room: the camera stays clamped until the player breaks through, then scrolls in, never past the tiles. Type 2 secret doorways: semi-transparent entry, an exit that matches the wall tile, no collision, back and forth twice, never consumed or saved. Also: GUIDELINES.md documents both types, and every room's camera limits stay within its tiles. Before that: illusion walls. Before that: the Stasis Field's doubled cost; the Meteor Slam ground hop (it rises first, is vulnerable during the hop, a hit cancels the slam, then the invulnerable dive slams); camera look up / down (a tap does nothing, a hold pans, moving snaps back, never outside the room); and the physical upward transition (the player emerges at the threshold inside the floor gap, climbs out, arcs over the floor without drifting back, lands beside the gap, either side at random, not invulnerable). Before that: the three damage sources (spikes hurt through post-hit i-frames, dash invulnerability and the Meteor Slam dive; i-frames still block enemy contact and projectiles; God Mode still blocks hazards), the Repulse Aegis parry (no wind-up, a short window, a mistimed cast does not protect, only an enemy at the player's skin triggers it, projectiles are never blocked) and the Stasis Field as a short-range, short emergency freeze. Before that: the four new spells (Repulse Aegis consumes all energy, negates a contact or projectile hit and strikes back ×1.5; Stasis Field freezes enemies and projectiles in range, harmless while frozen, and wears off; Radiant Lance fires forward or up and damages; Meteor Slam dives with i-frames, lands, grants landing i-frames and damages), the slot capacity (fewer slots, more slots up to 8, keys past the limit do nothing, saved per slot) and the debug overlay's spell controls (known checkboxes, capacity slider). Before that: no celebrations anywhere (no victory/secret/relic sounds or celebration effects exist; an arena clear only plays the gate clunk). Before that: the room-design rules from GUIDELINES.md (A: landing ground at every point of a downward exit; B: upward exits place you beside the gap, either side at random; C: the secret wall breaks and its exit opens during an active arena). Before that: seamless exits (no fade, sound or marker; speed kept), the ceiling gap to the Upper Galleries and back, its standard enemies, the secret wall sitting in the outer wall and blocking until broken, and a quiet boss defeat (no fanfare, effect or freeze). Earlier: menu focus wrap-around (first and last buttons reachable), "New Game" slot text, no Inventory in the pause menu, the trance after saving, sounds as AudioStreamPlayer nodes, effects as scenes that free themselves, enemy spawn/roar/dissolve clips, the HUD showing bound hotkeys, arena-only short spawn telegraphs, a single checkpoint tablet, no text pop-ups and instant door transitions. From the previous version: the death animation and trance, respawn reviving weak and strong enemies with 0 energy, dead and spawning enemies being harmless, spawns kept away from the player, the off-centre pogo, the boss roar and dissolve, the arena victory feedback, the Proving Grounds arena, the secret wall and relic, all 5 save slots (write, read, load), the pause menu, settings, and the title screen with both keyboard and mouse. The test writes to `user://test_saves` only. Also covered: sealed room borders and camera limits, the heal-ready glow, both door transitions, the weak/strong/boss respawn rules, survivors healing on re-entry, boss tracking and aiming (facing, charge, leap, volley, phase 2), a full arena run that stays cleared, arena reset on death, chunk healing, explicit saving, the keyboard loadout flow and the earlier movement and combat rules. Exit code 0 means everything passed.
