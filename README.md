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
| Debug overlay | F1 or ` / ~ | Start |
| Reset room | R | — |

Bindings live in **Project → Project Settings → Input Map**.

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
- **Four hotkeys (1–4).** Each slot holds one ultimate. There is no switching.
  - Defaults: 1 Nova Burst (33), 2 Spirit Volley (50), 3 Ascendant Form (100), 4 Comet Dash (25).
- **Color-coded energy bar.** Each equipped slot has a mark on the bar at its cost, with the slot number under it. A mark is bright when you can afford it.
  - The color follows the cost tier, not the spell. Green is up to 25, yellow up to 50, orange up to 75, and pink above that.
  - So when you swap abilities later, the colors still show the minimum energy each slot needs.

### Checkpoints
Touching a checkpoint lights it. After a death **or a spike hit** you return to the last lit checkpoint. Resting (E) heals you fully. The game starts at the first checkpoint. The debug toggle *Spikes → Safe Ground* switches spike hits back to the "last safe ground" behavior.

Checkpoint art is modular. Replace the polygons under `Visual` in `world/objects/checkpoint.tscn`, and edit or replace its animations named `inactive`, `activate` and `active`. No code changes are needed.

### Hazards
Spikes damage the player and send them to the last checkpoint. They teleport you even when you are invulnerable (but then deal no damage), so a damage loop is impossible. **Enemies that touch spikes die instantly.** Knock a dummy into a pit to see it.

### Currency (Shards)
Shards (◆) lie on ledges around the room, and destroyed enemies drop them. The total shows in the top-right corner and in the inventory. Placed shards return when you reset the room (R). Collected currency is kept.

### Dialogue, lore and explanations
Walk up to an NPC or a lore tablet. An "E Talk" or "E Read" prompt appears. Press E to open the dialogue. Press E, Space or J to reveal the page and then to turn it. The game pauses while dialogue is open.
- **Archivist Mira** (next to the start) explains healing, checkpoints, currency, the ultimate keys and the loadout rule.
- **Tablets** explain wall jumps (left shaft), spikes and the pogo (on the raised block), and the four ultimates (center).

Dialogue texts are `DialogueData` resources in `dialogue/`. Edit them in the Inspector, or create new ones (FileSystem → New Resource → DialogueData). Assign one to any `lore_stone.tscn` or `npc.tscn` instance.

### Inventory and loadout (I / Tab)
The game pauses while the inventory is open. It has two tabs:
- **Status:** shards, current/max health and current/max energy. Max values support growth through `max_health_bonus` and `max_energy_bonus`. The debug overlay has buttons to test this.
- **Abilities:** the top row shows the 4 equipped slots. The bottom grid shows every unlocked ability, starting with the 4 basic ones.
  - To swap, select a slot, then click an ability. If that ability already sits in another slot, the two slots swap.
  - **Swapping only works while you stand at a checkpoint.** Elsewhere the buttons are disabled, and the rule is enforced in code too (`UltimateManager.equip`).

### HUD
The HUD is clean by default: health and energy bars, threshold marks and the shard count. There are no cost or switching texts. Turn on **Hitboxes & Stats** in the debug overlay (or simply open it) to see exact health, energy, enemy health, damage numbers and hitboxes.

## Test checklist

| Feature | How |
| --- | --- |
| No wall slide | Fall next to a wall while holding toward it: you do not slow down. Jump to wall-jump. |
| Dialogue | Walk to the robed NPC right of the start, press E. Read the tablets too. |
| Rest-heal | Take damage on a dummy, walk to a flame, press E. |
| Checkpoints | Walk to the flame in the middle (it lights up). Then touch spikes: you reappear there. |
| Currency | Collect the ◆ shards on the platforms. Destroy a dummy and collect its drops. |
| Ultimate keys | Fill energy (debug: *Max Energy*), press 1, 2, 3, 4. Watch the colored marks. |
| Loadout | Press I away from a checkpoint (swapping is locked), then at a checkpoint (select a slot, then an ability). |
| Enemy on spikes | Knock the right-side dummy into the right pit, or use *Spawn Dummy* above a pit. |
| Stats | Debug overlay (F1) → *Hitboxes & Stats*. |

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
tests/smoke_test.tscn    automated headless test (64 checks)
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

It plays the game through real input actions and checks 64 behaviors. These include movement, the no-wall-slide rule, combat, healing (channel and rest), the 4 hotkeys, energy tiers, dialogue, currency, checkpoints, the loadout restriction, the inventory, hazards for the player and for enemies, and the debug toggles. Exit code 0 means everything passed.
