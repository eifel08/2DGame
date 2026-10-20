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
3. Start Godot. In the Project Manager click **Import**, select the `project.godot` file inside the `2DGame` folder, then **Import & Edit**.
4. The first opening imports the assets. This takes a few seconds.
5. Press **F5** (or the ▶ button) to play.

From a terminal you can also run it without the editor:
```bash
godot --path 2DGame
```

## Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Move / aim | Arrow keys or WASD | Left stick / D-pad |
| Jump (hold = higher) | Space / Z | A |
| Drop through a platform | Down + Jump | Down + A |
| Attack (directional) | J / X (hold Up or Down to aim; Down only in the air) | X |
| Dash | K / C / Shift | RB |
| Heal (hold) | L / V (on the ground) | LB |
| Ultimate | U / Q | Y |
| Switch ultimate | Tab | Back / Select |
| Debug overlay | F1 or ` (backquote) | Start |
| Reset room | R | — |

Bindings live in **Project → Project Settings → Input Map**.

## What to test

| Mechanic | How |
| --- | --- |
| Variable jump | Tap jump, then hold it. Holding goes about 3× higher. |
| Coyote time | Run off a ledge and jump just after leaving it. |
| Jump buffer | Press jump just before landing. The jump fires on touchdown. |
| Double jump | Jump again in mid-air. |
| Wall slide / jump | Far-left shaft or the narrow right shaft. Hold toward the wall while falling, then jump. |
| Dash + i-frames | Dash through a dummy. With *Show Hitboxes* on, the player box turns blue while invulnerable. |
| Directional attacks | Attack sideways, with Up held, and with Down held in the air. |
| Pogo | Down-attack the flying dummy above the spikes, or the spikes themselves. |
| Hitstop / shake | Hit anything. Tune both in the debug overlay. |
| Contact damage + i-frames | Walk into a dummy. The player flickers for the i-frame time. |
| Energy + heal | Hit dummies to fill EN. Hold L on the ground to turn energy into HP. |
| Ultimates | Fill the meter (or *Max Energy*), press U. Tab switches. Ticks on the EN bar show each cost. |

Dummies respawn 2.5 s after being destroyed. Dying respawns the player at the start.

## The four ultimates

| Ultimate | Type | Default cost |
| --- | --- | --- |
| Nova Burst | Area-of-effect shockwave | 33 |
| Spirit Volley | Fan of homing projectiles | 50 |
| Ascendant Form | 8 s buff: damage, speed, reach | 100 |
| Comet Dash | Aimable invulnerable charge + blast | 25 |

Costs and all other numbers are in `autoload/config.gd` and can be changed live in the debug overlay.

## Project layout

```
project.godot          settings, input map, autoloads
autoload/
  config.gd            Config: every tunable value (edited live by the debug overlay)
  events.gd            Events: global signal bus
core/
  game.gd              composition root + fixed 60 Hz step order + hitstop gate
  input_state.gd       buffered input edges (no lost presses during hitstop)
  state_machine.gd     generic FSM
  camera_rig.gd        follow camera + trauma screen shake
  geom.gd
player/
  player.tscn / .gd    CharacterBody2D: body, components, movement helpers
  states/              normal, dash, heal, cast, ability, hurt
  player_animator.gd   animation state machine (ordered rules → animation name)
  player_rig.tscn      placeholder skeleton (Flip/Rig/Body, Visor, Arm/Blade)
  player_animations.tres
stats/health_energy.gd health, shared energy, healing, i-frames
combat/
  combat_manager.gd    melee, pogo, recoil, damage API, contact + hazard damage
  projectile_system.gd homing projectiles
ultimates/
  ultimate_ability.gd  base class (lifecycle hooks)
  ultimate_manager.gd  equip / cycle / cost check / cast / update
  ultimate_registry.gd list of available ultimates
  abilities/           nova_burst, spirit_volley, ascendant_form, comet_dash
enemies/               training dummy (ground + flying) scenes, rigs, animations
effects/
  feedback.gd          hitstop + shake + particles, driven by events
  effects.gd           particles, rings, damage numbers, afterimages
ui/                    HUD, debug overlay, parallax background
world/
  room.gd              world queries (solid, one-way, hazard, ground)
  test_room.tscn       the test room (TileMapLayer + spawn markers)
  tiles/               tile atlas and TileSet
scenes/main.tscn       main scene
tools/build_assets.gd  regenerates rigs, animations, TileSet, room and input map
tests/smoke_test.tscn  automated headless test of the core mechanics
```

### Design rules

- **One loop drives the game.** `core/game.gd` steps every system in a fixed order. During hitstop it simply stops stepping, and animations freeze too, because the AnimationPlayers run in manual mode.
- **Systems talk through signals.** Combat emits `Events.hit_landed`. Energy gain, hitstop, shake and particles each react on their own.
- **One config.** Every number lives in `Config`. The debug overlay writes to it, and systems read it every frame.
- **Gameplay never touches animation.** The player exposes state. `player_animator.gd` maps that state to an animation name.
- **Buffs are stat modifiers.** `player.add_modifier(id, {"speed_mul": 1.25, ...})`. Movement and combat read `player.stat("speed_mul")`.

## Extending

**Swap in real art.** Open `player/player_rig.tscn` and replace the Polygon2D parts with your Sprite2D, AnimatedSprite2D or Skeleton2D setup. Then edit the animations in the player's AnimationPlayer. Keep the animation names (`idle`, `run`, `jump`, `fall`, `dash`, `wall_slide`, `attack_side`, `attack_up`, `attack_down`, `heal`, `cast`, `hurt`). No code changes are needed.

**Add an animation state.** Add an animation to the AnimationPlayer and one rule to `player/player_animator.gd`. Rule order is priority.

**Add an ultimate.**
1. Create `ultimates/abilities/my_ult.gd` extending `UltimateAbility`. Override `_on_activate`, `_on_step`, `_on_end`, `draw_world` as needed. Call `end(ctx)` when done.
2. Add `"my_ult": {"cost": 40.0, "cast_time": 0.3, ...}` to `Config.ultimates`.
3. Add `MyUlt.new()` to `ultimates/ultimate_registry.gd`.

It then appears in the HUD, the Tab cycle and the debug overlay.

**Add a debug control.** Add one entry to `TOGGLES`, `SLIDERS` or `_actions()` in `ui/debug_overlay.gd`.

**Edit the room.** Open `world/test_room.tscn` and paint with the TileMap editor. Tiles: solid, solid (lit top), one-way plank, spikes. Move the markers under `EnemySpawns` to place dummies. To set a marker as flying, give it the metadata `flying = true`.

## Automated test

```bash
godot --headless --path . --fixed-fps 60 res://tests/smoke_test.tscn
```

It drives the game through real input actions and checks 31 behaviors: movement, jumps, dash, wall slide/jump, attacks, pogo, healing, all four ultimates, contact damage, i-frames and the debug toggles. Exit code 0 means all passed.
