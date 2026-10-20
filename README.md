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
5. Press **F5** (or ▶) to play.

To pull later changes: `git pull` inside the `2DGame` folder, then reopen the project.

## Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Move / aim | Arrow keys or WASD | Left stick / D-pad |
| Jump (hold = higher) | Space / Z | A |
| Drop through a platform | Down + Jump | Down + A |
| Attack (directional) | J / X (hold Up or Down to aim; Down only in the air) | X |
| Dash | K / C / Shift | RB |
| Heal (hold, uses energy) | L / V (on the ground) | LB |
| Ultimate slot 1 / 2 / 3 / 4 | 1 / 2 / 3 / 4 | Y / RT / LT / R3 |
| Interact (talk, read, rest) | E / F | B |
| Inventory | I / Tab / Esc | Back / Select |
| Inventory: switch tab | Q / E (or PgUp / PgDn) | LB / RB |
| Inventory: move / select | Arrow keys, Enter or Space | D-pad, A |
| Inventory: clear a slot | Backspace / Delete | X |
| Debug overlay | F1 or ` / ~ | Start |
| Debug overlay keyboard mode | F2 (pauses; arrows, Enter, Left/Right on sliders) | — |
| Reset room | R | — |

Bindings live in **Project → Project Settings → Input Map**. Everything, including menus, dialogue, inventory tabs and loadout swaps, works with the keyboard alone. No mouse is needed.

## Systems

### Movement
Crisp acceleration and stopping, dynamic jump height, double jump, dash with i-frames, coyote time and jump buffering. Gravity defaults to 2100, a little low, to give more reaction time for pogo chains.

**Walls are jump-only.** There is no wall slide: you fall at full speed next to a wall. Press jump while touching a wall in mid-air to spring away from it. A wall jump refreshes your double jump and air dash, so you can climb narrow shafts wall to wall.

### Combat
Directional attacks (left, right, up, down) and the downward pogo bounce off enemies and spikes. Hits trigger hitstop and screen shake. Enemy contact deals damage, knocks you back and starts the i-frames.

### Energy, healing and ultimates
- **One shared energy meter.** Basic attacks fill it.
- **Two ways to heal:**
  1. **Channel:** hold L on the ground. Energy drains into health for as long as you hold it.
  2. **Rest:** stand at a checkpoint flame and press E. Your health is fully restored. This needs no energy.
- **Four hotkeys (1–4).** Each slot holds one ultimate, or nothing. You can equip 0 to 4 abilities. There is no switching.
  - Defaults: 1 Nova Burst, 2 Spirit Volley, 3 Ascendant Form, 4 Comet Dash.
- **Color-coded energy bar, no numbers.** Each equipped slot puts a mark on the bar at the energy it needs. Under the bar, the hotkey strip shows slots 1, 2, 3 and 4 from left to right, each with its icon. A mark or slot is bright when there is enough energy.
  - The color follows the energy tier, not the spell: green (low), yellow, orange, pink (full).
  - Empty slots have no mark.
- **No exact stats for the player.** Abilities, tooltips and lore never show energy numbers. Each ability shows a small gauge filled to its requirement instead. Exact values appear only in the debug stats view.

### Checkpoints, safe ground and death
- **Spikes:** damage, then you reappear on the **last safe ground** you stood on, a few steps back. This happens even while invulnerable (but then without damage), so a damage loop is impossible.
- **Death:** only when health reaches zero (from enemies or spikes) do you respawn at the **last lit checkpoint**.
- **Checkpoints:** touching a flame lights it. Pressing E there ("Rest") fully heals you without showing any text. While you stand at a lit flame, you can change the loadout.
- **Info tablets:** a tablet stands shortly before each later checkpoint. Reading it is optional; it explains checkpoints, resting and the loadout rule.
- The debug toggle *Spikes → Safe Ground* (on by default) can send spike hits to the checkpoint instead.

Checkpoint art is modular. Replace the polygons under `Visual` in `world/objects/checkpoint.tscn`, and edit or replace its animations named `inactive`, `activate` and `active`.

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
- **Abilities:** the top row shows hotkey slots 1–4, left to right. The bottom grid shows every unlocked ability, plus an empty card.
  - Cards show **icons and energy gauges only**. The name and description appear below only for the focused card.
  - **Keyboard flow:** use the arrows to reach a slot and press Enter, then pick an ability and press Enter. The empty card, or Backspace, clears the selected slot. If the ability already sits in another slot, the two slots swap.
  - **Changes only work at a lit checkpoint.** Elsewhere you can browse but not change anything, and `UltimateManager.equip` / `unequip` enforce this in code too.

### Text direction
The UI is always laid out left to right, even on a system set to a right-to-left language. This is set in `project.godot` (`root_node_layout_direction`) and on every panel. Dialogue text is laid out for the whole page before typing starts, so lines never shift or re-wrap while the letters appear.

### HUD
The HUD is clean by default: health and energy bars, threshold marks, the hotkey strip and the shard count. It has no numbers except the shards. Turn on **Hitboxes & Stats** in the debug overlay (or simply open it) to see exact health, energy, enemy health, damage numbers and hitboxes.

## Test checklist

| Feature | How |
| --- | --- |
| Spikes vs death | Walk into a spike pit: you reappear just before it. Let health run out (debug: *Take Damage*): you wake at the last flame. |
| Shards on spikes | Destroy the right-hand dummy near its pit so shards fly in: they vanish. |
| Empty slots | At a flame, open the inventory, select a slot, press Backspace. Its mark leaves the energy bar and its strip box turns empty. |
| Keyboard inventory | I, then Q/E for tabs, arrows to move, Enter to select and equip. No mouse. |
| Icons and details | Move focus over ability cards: the name and description appear only for the focused one. |
| Left to right | Slots read 1-2-3-4 left to right in the HUD and the inventory. Dialogue types from the left. |
| Checkpoint tablets | Read the tablet before the middle or right flame. Resting at the flame shows no text. |
| No wall slide | Fall next to a wall while holding toward it: you do not slow down. Jump to wall-jump. |
| Dialogue | Walk to the robed NPC right of the start, press E. |
| Debug, keyboard only | F1, then F2: arrows, Enter, Left/Right on sliders. F2 again resumes. |

## Project layout

```
autoload/config.gd       Config: every tunable value + energy tier colors
autoload/events.gd       Events: global signal bus
core/game.gd             composition root: fixed-step loop, checkpoints, interaction, pickups
player/
  player.gd, states/     movement state machine (normal, dash, heal, cast, ability, hurt)
  player_data.gd         currency, unlocked abilities, 4 equipped slots
  player_animator.gd     animation state machine (rules → animation name)
  player_rig.tscn        placeholder skeleton; swap art here
stats/health_energy.gd   health, shared energy, healing, i-frames, growth bonuses
combat/                  melee, pogo, damage API, contact/hazard damage, projectiles
ultimates/               ability base class, slot manager (keys 1-4), the 4 abilities
enemies/                 training dummies (ground + flying)
world/
  room.gd                world queries (solid, hazard, ground, safe ground, objects)
  test_room.tscn         test room: platforms, walls, 2 spike pits, objects
  objects/               interactable base, checkpoint, lore stone, NPC, coin
dialogue/                DialogueData resources (NPC + lore texts)
ui/                      HUD, dialogue box, inventory, debug overlay, background
tools/build_assets.gd    regenerates rigs, animations, TileSet, room and input map
tests/smoke_test.tscn    automated headless test (86 checks)
```

## Extending

- **New ultimate:** extend `UltimateAbility` in `ultimates/abilities/`, add a config block to `Config.ultimates`, and register it in `ultimate_registry.gd`. Unlock it with `game.player_data.unlock("id")`. It then appears in the inventory pool and can be slotted at a checkpoint.
- **New lore or NPC:** create a `DialogueData` resource and assign it to an instance of `world/objects/lore_stone.tscn` or `npc.tscn` under `TestRoom/Objects`.
- **New interactable:** extend `Interactable` and override `interact(game)`. Put the node under `Objects`.
- **Real sprites:** replace `player/player_rig.tscn` (keep the animation names), the enemy rigs, or the `Visual` nodes of the world objects.
- **Edit the room:** paint in `world/test_room.tscn`, or edit `ROOM_LAYOUT` in `tools/build_assets.gd`. Delete `world/test_room.tscn`, then run:
  ```bash
  godot --headless --path . --script res://tools/build_assets.gd
  ```

## Automated test

```bash
godot --headless --path . --fixed-fps 60 res://tests/smoke_test.tscn
```

It plays the game through real input actions and checks 86 behaviors. These include movement and combat, healing, safe-ground versus checkpoint respawn, shards and enemies on spikes, empty slots, number-free ability UI, keyboard-only inventory and debug use, left-to-right layout and text, dialogue, currency and checkpoints. Exit code 0 means everything passed.
