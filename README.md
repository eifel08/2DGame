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
| Jump (hold = higher) | Space / Z | A |
| Drop through a platform | Down + Jump | Down + A |
| Attack (directional) | J / X (hold Up or Down to aim; Down only in the air) | X |
| Dash | K / C / Shift | RB |
| Heal (hold, chunk by chunk) | L / V (on the ground) | LB |
| Ultimate slot 1 / 2 / 3 / 4 | 1 / 2 / 3 / 4 | Y / RT / LT / R3 |
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
- **Four hotkeys (1–4).** Each slot holds one ultimate, or nothing. You can equip 0 to 4 abilities. There is no switching.
  - Defaults: 1 Nova Burst, 2 Spirit Volley, 3 Ascendant Form, 4 Comet Dash.
- **Color-coded energy bar, no numbers.** Each equipped slot puts a mark on the bar at the energy it needs. Under the bar, the hotkey strip shows the four slots from left to right, each with its icon and its **actual key** (1–4 by default; a key rebound in Settings shows its new name). A mark or slot is bright when there is enough energy.
  - The color follows the energy tier, not the spell: green (low), yellow, orange, pink (full).
  - Empty slots have no mark.
- **No exact stats for the player.** Abilities, tooltips and lore never show energy numbers. Each ability shows a small gauge filled to its requirement instead. Exact values appear only in the debug stats view.

### Checkpoints, safe ground and death
- **Spikes:** damage, then you reappear on the **last safe ground** you stood on, a few steps back. This happens even while invulnerable (but then without damage), so a damage loop is impossible.
- **Death:** only when health reaches zero (from enemies or spikes) do you respawn at the checkpoint where you **last saved**.
  - A short collapse animation plays first (red flash, death sound). Then the screen fades.
  - Respawning works like a save: weak and strong enemies return. Energy starts at **0**.
  - Dead enemies stop hurting at once: their contact damage, hurtbox and body collision switch off the moment they die.
- **Trance:** after saving at a checkpoint, after a death, or when a save loads, you float in a trance at the checkpoint. You are safe there. Any **new** button press wakes you. A key you were already holding does not.
- **Checkpoints save only on purpose.** Standing near a flame does nothing. Press **E** (or **Down** on the ground) to save: the flame lights, you snap to its exact center, and your health is fully restored. No text appears. Only at the flame where you saved can you change the loadout.
- **Info tablet:** one tablet stands just before the very first checkpoint. Reading it is optional; it explains saving, death respawn and the loadout rule. Later checkpoints have no tablet.
- The debug toggle *Spikes → Safe Ground* (on by default) can send spike hits to the checkpoint instead.

Checkpoint art is modular. Replace the polygons under `Visual` in `world/objects/checkpoint.tscn`, and edit or replace its animations named `inactive`, `activate` and `active`.

### Rooms and doors
The world map has four rooms:

```
Testing Halls  ⇄  Sentinel's Arena  ⇄  Proving Grounds  ⇄ (hidden wall) ⇄  Hidden Shrine
```

- Walk into a lit doorway to move through it. The switch is instant: no fade and no wait, and you keep running.
- **Proving Grounds** is a dedicated arena room with its own checkpoint and three waves. Once cleared, it stays cleared.
- **Secret passage:** at the far east end of the Proving Grounds, one wall section is cracked. Strike it three times. It crumbles at once, with no message, and opens the way to the **Hidden Shrine**. The shrine holds a lore tablet, shards and a **relic** that raises max health for this save. The broken wall and the relic are saved.
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
- **Death:** it rears up and screams (a low roar, a heavy shake, a flash), then dissolves into purple particles. There is no text pop-up.

### Arena encounters
The Boss Room is an **arena**. Stepping in seals the doorway with gates, then the waves follow:
1. Weak dummies and a flyer.
2. A strong dummy.
3. The boss.

Each wave starts once the previous one is defeated. After the last wave the gates open, and the arena is **cleared for good**. A clear plays a victory fanfare with golden rings and sparks. There is no text pop-up. If you die inside, the attempt resets and the arena starts fresh next time.

**Telegraphed spawns (arenas only):** arena wave enemies appear through a short portal. For 0.35 s they fade in, harmless and impossible to hit. No timer or text is shown. They never appear on top of you: a spawn point too close to the player moves aside. Everywhere else enemies simply appear, with no telegraph.
- Arenas are data: in a room scene, `Objects/Arena` has a trigger rect, gate rects, and `Waves/Wave1`, `Wave2`, ... with marker children (meta `kind`: `weak`, `flyer`, `strong` or `boss`).
- The logic is in `core/arena_director.gd`. Add a wave by adding a `WaveN` node with markers.

### Layout and collision
- Solid tiles light every face that borders open space, so the drawn edges are exactly the collision edges.
- The background is dim, with fading tops, so it never looks like something you can stand on. The HUD sits on its own backing panel.
- The camera, including screen shake, never shows anything outside the room.
- Every opening in a room's outer wall is a doorway. The automated test checks all of this.
- With *Hitboxes & Stats* on, the debug view also outlines solid tiles, door triggers and arena areas.

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
| Spawn portal | Debug overlay → spawn an enemy, or enter an arena: enemies fade in through a portal and cannot hurt you yet. |
| Doorway | Walk to the far east end of the Test Room: you move to the Boss Room. Walk back left to return. |
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
  player.gd, states/     movement state machine (normal, dash, heal, cast, ability, hurt, dying, trance)
  player_data.gd         currency, unlocked abilities, 4 equipped slots
  player_animator.gd     animation state machine (rules → animation name)
  player_rig.tscn        placeholder skeleton; swap art here
stats/health_energy.gd   health, shared energy, healing, i-frames, growth bonuses
combat/                  melee, pogo, damage API, contact/hazard damage, projectiles
ultimates/               ability base class, slot manager (keys 1-4), the 4 abilities
enemies/
  enemy.gd               shared enemy base (tiers, health, contact damage)
  dummy_enemy.gd         weak / strong training dummies (ground + flying)
  boss_sentinel.gd       the intro boss and its attack patterns
world/
  room.gd                world queries (solid, hazard, ground, safe ground, doors, arena)
  test_room.tscn         test room: platforms, walls, 2 spike pits, objects, east doorway
  boss_room.tscn         boss room: arena with waves and the Hollow Sentinel
  arena_room.tscn        Proving Grounds: arena room with a cracked wall
  secret_room.tscn       Hidden Shrine: relic, tablet, shards
  objects/               interactable base, checkpoint, lore stone, NPC, coin, door, breakable wall, relic
dialogue/                DialogueData resources (NPC + lore texts)
ui/                      HUD, dialogue box, inventory, debug overlay, title, pause and settings menus
tools/build_assets.gd    regenerates rigs, animations, TileSet, room and input map
core/world_state.gd      dead enemies, bosses, arenas, collected shards
core/arena_director.gd   arena waves: start, next wave, clear, abort
effects/fx/               one scene per visual effect (placeholders), FxPlayer
audio/sfx.tscn, sfx/     the Sfx autoload: one AudioStreamPlayer per sound + .wav placeholders
tests/smoke_test.tscn    automated headless test (207 checks)
```

## Extending

- **New ultimate:** extend `UltimateAbility` in `ultimates/abilities/`, add a config block to `Config.ultimates`, and register it in `ultimate_registry.gd`. Unlock it with `game.player_data.unlock("id")`. It then appears in the inventory pool and can be slotted at a checkpoint.
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

It plays the game through real input actions and checks 207 behaviors. New in this version: menu focus wrap-around (first and last buttons reachable), "New Game" slot text, no Inventory in the pause menu, the trance after saving, sounds as AudioStreamPlayer nodes, effects as scenes that free themselves, enemy spawn/roar/dissolve clips, the HUD showing bound hotkeys, arena-only short spawn telegraphs, a single checkpoint tablet, no text pop-ups and instant door transitions. From the previous version: the death animation and trance, respawn reviving weak and strong enemies with 0 energy, dead and spawning enemies being harmless, spawns kept away from the player, the off-centre pogo, the boss roar and dissolve, the arena victory feedback, the Proving Grounds arena, the secret wall and relic, all 5 save slots (write, read, load), the pause menu, settings, and the title screen with both keyboard and mouse. The test writes to `user://test_saves` only. Also covered: sealed room borders and camera limits, the heal-ready glow, both door transitions, the weak/strong/boss respawn rules, survivors healing on re-entry, boss tracking and aiming (facing, charge, leap, volley, phase 2), a full arena run that stays cleared, arena reset on death, chunk healing, explicit saving, the keyboard loadout flow and the earlier movement and combat rules. Exit code 0 means everything passed.
