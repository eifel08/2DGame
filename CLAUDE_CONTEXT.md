# CLAUDE_CONTEXT.md — technical briefing for AI sessions

High-level map of this repo so a new session does not have to re-read everything.
**Binding sources of truth:** `GUIDELINES.md` (design rules) and `README.md` (full behaviour spec, controls, test checklist).
When this file and the code disagree, the code wins — update this file.

- Engine: **Godot 4.3+**, pure GDScript, no plugins. Viewport 960×540 (`canvas_items` stretch), window 1440×810.
- Main scene: `scenes/title.tscn` → slot select → `scenes/game.tscn`.
- Tile size 32 px. Node origins of player/enemies are at the **feet (bottom-center)**.
- ~20.7k lines of GDScript; the biggest files are `tests/smoke_test.gd` (5.2k), `tools/build_assets.gd` (1.5k), `core/game.gd` (1.2k).

---

## 1. Repository structure

| Path | What lives there |
| --- | --- |
| `autoload/` | Singletons (see §2.1): `config.gd`, `events.gd`, `settings.gd`, `saves.gd`, `sfx.gd` (Sfx is registered as `audio/sfx.tscn`) |
| `core/` | `game.gd` (composition root + fixed-step loop), `state_machine.gd` (generic FSM), `input_state.gd` (buffered input edges), `world_state.gd` (persistence of enemies/bosses/arenas/coins/secrets/relics), `arena_director.gd` (arena waves), `camera_rig.gd`, `geom.gd` |
| `player/` | `player.gd` (CharacterBody2D, movement helpers, hit/hazard API), `player_data.gd` (currency, spells, slots, movement items, tutorials), `player_animator.gd` (rules → clip name), `player_rig.tscn` + `player_animations.tres` (placeholder art), `states/*.gd` (one class per FSM state) |
| `stats/health_energy.gd` | Health, the single shared energy meter, heal chunks, i-frames/invuln flags, max-stat bonuses |
| `combat/` | `combat_manager.gd` (melee, pogo, deflect, damage API, contact + hazard resolution, debug drawing), `projectile_system.gd` (data-driven projectiles, deflect, freeze), `grapple_hook.gd/.tscn` (hook aim/flight/latch/pull/swing), `damage.gd` (`Damage.Source` enum) |
| `ultimates/` | `ultimate_ability.gd` (spell base), `ultimate_manager.gd` (Spell+direction, loadout, casting), `ultimate_registry.gd` (list of spells), `ultimate_context.gd`, `abilities/*.gd` (Mana Discharge + 8 equippable spells) |
| `enemies/` | `enemy.gd` (shared contract: tier, health, contact damage, `blocks_hit`, freeze), `base_enemy.gd` (BaseEnemy: mini-FSM, senses, movement, shoot/strike, telegraph, poise), `enemy_rig.gd` (placeholder drawings per `look`), `dummy_enemy.gd` (+ `dummy/strong/flying` scenes), `boss_sentinel.gd` (Hollow Sentinel), `bestiary/<kind>.gd/.tscn` (13 kinds), `*_rig.tscn` + `*_animations.tres` |
| `world/` | `room.gd` (world queries), one `.tscn` per room, `objects/` (all room objects), `tiles/` (tileset + atlas png) |
| `map/` | `map_atlas.gd` (`WORLD` data: zones, room rects, exits, anomaly resolution), `map_zone.gd`, `map_room.gd`, `map_exit.gd`, `map_state.gd` (fog of war) |
| `ui/` | `hud.gd`, `spell_cross.gd`/`spell_node_view.gd`, `energy_gauge.gd`, `stat_bar.gd`, `inventory_menu.gd`, `map_view.gd`, `map_overlay.gd`, `pause_menu.gd`, `settings_panel.gd`, `title_screen.gd`, `dialogue_box.gd`, `tutorial_popup.gd`, `ability_art.gd`/`ability_icon.gd`/`ability_card.gd`, `menu_kit.gd`, `debug_overlay.gd` (F1), `background.gd` |
| `effects/` | `effects.gd` (play fx scenes by name), `feedback.gd` (Events → hitstop/shake/fx/sfx), `fx/<name>.tscn` (one `FxPlayer` scene per effect), `fx/placeholders/` |
| `audio/` | `sfx.tscn` (one AudioStreamPlayer per sound, named after it), `sfx/<name>.wav` |
| `dialogue/` | `dialogue_data.gd` (DialogueData resource) + `.tres` texts |
| `tools/build_assets.gd` | Generator (SceneTree script): input map, tileset, **room scenes from ASCII layouts**, rigs, animations, fx/sound placeholders, **build-time rule checks** |
| `tests/smoke_test.gd/.tscn` | Headless end-to-end test (~754 checks) driven by real input actions |

### Scenes
- `scenes/game.tscn` (root `Main`, script `core/game.gd`): `BackgroundLayer/Background`, `RoomRoot`, `Enemies`, `Pickups`, `Ultimates`, `Player` (instance), `Combat` → `Projectiles`, `Grapple` (instance), `Effects`, `Feedback`, `Camera`, `HudLayer/Hud`, `FadeLayer/Fade`, `DialogueBox`, `Inventory`, `PauseMenu`, `DebugOverlay`.
- `player/player.tscn`: `Player` (CharacterBody2D) → `CollisionShape2D`, `Flip/Rig`, `AnimationPlayer`, `HealthEnergy`, `Animator`.
- Rooms (`Game.ROOM_SCENES`, ids → files): `test_room` Testing Halls (start), `boss_room` Sentinel's Arena, `arena_room` Proving Grounds, `secret_room` Hidden Shrine, `upper_room` Upper Galleries, `hidden_vault` Hidden Vault, `lava_room` Ember Crossing, `bestiary` Bestiary. Each room: `Room` script, `Tiles` (TileMapLayer), `Objects/...` (doors, checkpoints, pickups, `Arena` with `Waves/WaveN` markers), spawn markers with meta `kind`.

World graph:
```
Hidden Vault ⇄(secret doorway)⇄ Upper Galleries ⇄ Ember Crossing (dead end; old vault doorway walled up)
                                      ⇅ ceiling/floor gap
                                Testing Halls ⇄ Sentinel's Arena ⇄ Proving Grounds ⇄(breakable wall)⇄ Hidden Shrine
                                      ⇅ plank (Down+Jump)
                                Bestiary (one chamber per enemy type)
```
Map zones: `halls` (Testing Halls, Arena, Proving Grounds, Hidden Shrine [secret], Bestiary [not on base map]) and `reaches` (Upper Galleries, Hidden Vault [secret], Ember Crossing).

---

## 2. Architecture & design patterns

### 2.1 Autoloads (`project.godot`)
| Name | File | Role |
| --- | --- | --- |
| `Config` | `autoload/config.gd` | **Every tunable value**, grouped as inner objects: `upgrades` (debug ability switches), `movement`, `combat`, `grapple`, `vitals`, `progression`, `debug`, `camera`, `map`, plus `ultimates` (Dictionary per spell id) and `ENERGY_TIERS` colors. Debug overlay sliders write here live. |
| `Events` | `autoload/events.gd` | Global **signal bus**. Gameplay emits, Feedback/HUD/tests listen. ~70 signals: hits, pogo, grapple, player life cycle, heal, energy, spells, checkpoints, rooms, boss/arena, enemy block/parry/telegraph/slam, secrets, relics/potions/scrolls, meditation, movement items, tutorials, map, `anim_event`, platform/peg crumble. |
| `Sfx` | `audio/sfx.tscn` (`autoload/sfx.gd`) | `Sfx.play("name")` → AudioStreamPlayer child of that name; SFX/Music buses. |
| `Settings` | `autoload/settings.gd` | Volumes, shake, fullscreen, key rebinding (one key + one pad button per action, swap on conflict; debug keys reserved). `user://settings.cfg`. |
| `Saves` | `autoload/saves.gd` | 5 JSON slots `user://saves/slot_N.json`; `active_slot` (-1 = not saving: tests / running game.tscn directly), `pending_data` loaded by Game at start. |

### 2.2 Composition root & simulation loop (`core/game.gd`)
- Game owns plain-object systems: `InputState`, `PlayerData`, `WorldState`, `ArenaDirector`, `MapAtlas`, `MapState`, plus node systems from the scene.
- **One fixed 60 Hz `_physics_process`, strict order.** Nothing else steps itself:
  `input.poll()` → tutorial gate → meta input → pause checks (pause menu / transition / dialogue / inventory / debug nav) → playtime, camera shake → **hitstop** (`feedback.step_hitstop`, returns early but keeps input edges) → `_update_secret_walls` → `_update_movers` → `player.step` → each `enemy.step` → `combat.step` → `ultimates.step` → `arena_director.step` → `_update_doors` → `_update_checkpoints` → `_update_pickups` → `_update_interaction` → `feedback.step` → `effects.step` → `camera.follow` → deferred room load (`_pending_door`) → death→respawn fade → `input.end_step()`.
- Room loading: `load_room(id, arrival_door, offset, velocity)` → `_load_room_scene` collects typed arrays (`doors`, `checkpoints`, `coins`, `breakables`, `hidden_pockets`, `secret_doorways`, `relics`, `scrolls`, `altars`, `ability_pickups`, `map_pickups`, `platforms`, `grapple_pegs`, `interactables`), spawns enemies not dead in `WorldState`, applies map anomalies, sets camera bounds. Transitions are **seamless** (same height/speed), except upward (Rule B ejection) and downward (Rule A landing).
- Progress hooks on Game: `collect_relic/scroll/ability/map`, `meditate_at`, `hit_breakable`, `drop_currency`, `save_at_checkpoint`, `respawn_at_checkpoint`, `make_save_data`/`apply_save_data`/`write_save`, `grant_full_kit` (debug/tests), `show_tutorial`, `seal_door`.

### 2.3 Input
- `InputState` buffers `just_pressed`/`just_released` edges per physics frame so no press is lost during hitstop; `consume(action)` to swallow; `end_step()` clears. Actions: `move_*`, `jump`, `attack`, `dash`, `heal`, `grapple`, `spell`, `interact`, `inventory`, `map`, `pause`, `toggle_debug`, `debug_navigate`, `reset_room`.
- Defaults generated into `project.godot` by `tools/build_assets.gd`; rebinding via `Settings`. No hidden alternate keys (WASD etc. unbound).

### 2.4 Player state machine
- `StateMachine` (RefCounted): states are objects with `enter(params)`, `step(delta)`, `exit()`; `change(name, params)`; a state calling `change()` inside `step()` must return right after.
- `PlayerState` base holds `p: Player`. States registered in `Player._ready()`: `normal` (ground/air/wall-slide), `dash` (invulnerable), `heal` (chunk channel), `cast` (spell wind-up, frozen, invulnerable), `ability` (spell takes over movement: `begin_ability_control`), `hurt`, `trance` (after save/death/load; broken by a *new* press), `dying`, `eject` (Rule B), `grapple`, `meditate`, `map_read` (hold Tab; not paused, a hit closes it).
- Player API used by others: `receive_hit(damage, source_x, ..., attacker, source)` for ENEMY/PROJECTILE, `hazard_respawn(damage)` for HAZARD, `add_hit_guard(id, callable)`, `add_modifier(id, mods)` / `stat(key)`, `can_use(ability_id)` (movement item owned AND `Config.upgrades` switch), `pogo`, `jump`, `wall_jump`, `begin_ejection`, `begin_meditation`, `enter_trance`, `safe_point`.
- `PlayerAnimator` maps state → clip name; art lives only in `player_rig.tscn` + `player_animations.tres` (clips: idle, run, attack, heal, hurt, dying, trance, meditate, grapple, map_read, …).

### 2.5 Combat
- `CombatManager` owns **every damage interaction** and reports outcomes only via `Events` (`hit_landed`, `pogo_bounced`, …). Melee: directional hitboxes (`get_attack_hitbox`), forgiving pogo (`Config.combat.pogo_hitbox` 78×80, 0.16 s attack buffer), `swing_box()`, `deflect_box()` (swing box +8 px, live from swing start until 0.06 s after damage frames, +12 px around shot). Generic API for spells: `apply_damage(target, opts)`, `damage_in_circle`, `damage_in_rect`. Also resolves enemy contact damage, player hazards (spikes/lava), enemy hazards (enemies die on spikes/lava).
- Pogo works on enemies and **spikes only** — never lava (`Room.find_hazard(rect, false)`).
- `ProjectileSystem`: dictionaries spawned with opts; deflectable (gold, white edge) vs non-deflectable (crimson/violet, spiky); `deflect_in_rect` sends shots along the strike direction and turns them friendly (spearman spear: `on_deflect = "destroy"`); `freeze_in_circle` (Stasis Field).
- Only melee deflects/parries; spells never do.
- `GrappleHook` (child `Combat/Grapple`): range 256 px, three-ray terrain cast on layers 1+3, enemies via combat system (never layer 4), pull vs swing mode by aim rules, enemy pull → stop 18 px short → rebound → standard attack damage; pegs on layer 7; deflected by hazards; undiscovered Type 1 walls stop it like rock.

### 2.6 Enemies
- `Enemy` contract: `tier` (`weak`/`strong`/`boss`), `max_health`, `currency_drop`, `contact_damage_mul`, `knockback_mul`, `keeps_wounds`; `hitbox_active()` is the single switch for being hit and dealing contact damage (off while spawning and from the instant of death). `blocks_hit(direction, source)`, `pogo_on_block()`, `freeze(duration)`, `surface_normal()`.
- `BaseEnemy` (extends Enemy): override `_think(delta)`; helpers `enter(state)`, `cooldown`, `sees_target` (LOS), `target_in_leash`, `move_ground`, `move_fly`, `ground_ahead`, `wander()`, `shoot`, `strike`, `telegraph()`, `poise_states`, `is_alerted()` (red eyes ≈1 s).
- Roster (`Game.ENEMY_SCENES` keys): `weak`, `flyer`, `strong` (dummies), `boss` (Hollow Sentinel), and BaseEnemy kinds `swooper`, `charger`*, `thrower`, `brute`*, `ambusher`, `shellback`, `urchin`, `turret`*, `orb_sentry`, `hopper`, `crawler`, `phalanx`*, `spearman` (* = elite: `tier="strong"`, `keeps_wounds`).
- Adding a type: `enemies/bestiary/<kind>.gd` + `.tscn` (CharacterBody2D + CollisionShape2D + `Flip/Rig` EnemyRig + AnimationPlayer) → register in `Game.ENEMY_SCENES` → place with `!` + `"spawns"` in a layout → add a Bestiary chamber (`BESTIARY_LAYOUT`) → map/test checks.
- Boss: always tracks the player; Charge / Leap+shockwaves / Volley; phase 2 below 50 %; dies with roar + dissolve only.
- Arenas: data in room scene `Objects/Arena` (trigger rect, gate rects, `Waves/WaveN` markers with meta `kind`); `ArenaDirector` starts/advances/clears/aborts; arena spawns use a 0.35 s harmless portal telegraph and are pushed away from the player (`SPAWN_CLEARANCE` 110).

### 2.7 Feedback, effects, placeholders
- `Feedback` listens to `Events` and answers with hitstop, shake, `effects.play(name, pos)` and `Sfx.play(name)`. Gameplay never calls fx/sfx directly.
- `Effects.play("<name>")` instantiates `effects/fx/<name>.tscn` (root `FxPlayer`, frees itself).

---

## 3. Key systems — quick reference

### Energy & healing (`stats/health_energy.gd`, `Config.vitals`)
- One shared energy meter; **only basic melee hits fill it** (`gain_energy_from_hit`); the hook does not.
- Start: max health 50, max energy 50 (`STARTING_MAX_*`); growth via `max_health_bonus`/`max_energy_bonus` (Health Potion +15 & full heal, Mana Potion +15, relics).
- Heal = hold heal on ground, **chunk by chunk** (`heal_chunk_*`): energy drains, white segment previews; complete → red (kept) + short pause; let go / jump / hit before completion → energy lost, no health. Needs energy for a full chunk to start. Energy bar glows green when a chunk is affordable.
- Checkpoint save = full heal. Respawn/load = energy 0.
- No numbers in the player-facing UI except shards; exact stats only in the debug view.

### Spells (`ultimates/`)
- One Spell button + direction: none → **Mana Discharge** (fixed, never equipped/removed; drains ALL energy; ≥20 → wave radius = `radius_per_energy` × max energy, 4 damage; <20 → fizzle). Up → Up slot; Left/Right → Side slot (turns player); Down → Down slot. Up > Down > sides. Empty or locked slot casts nothing (no fallback).
- New game: no equippable spell known, all 3 slots locked. **Spell Scrolls** teach (`UltimateManager.learn`), **Meditation Altars** open slots (`open_slot`). Loadout changes only at the checkpoint where you saved (`can_change_loadout`, enforced in `equip`/`unequip`).
- Equippable (cost defaults in `Config.ultimates`): Nova Burst 33, Spirit Volley 50, Ascendant Form 100, Comet Dash 25 (horizontal, invulnerable), Repulse Aegis ≥20 consumes all (0.2 s contact-only parry, 150 % of energy back; projectiles not blocked), Stasis Field 80 (90 px, 0.8 s freeze), Radiant Lance 60 (horizontal beam), Meteor Slam 30 (invulnerable dive; ground cast hops first = vulnerable). `Game.DEFAULT_LOADOUT` = radiant_lance / comet_dash / meteor_slam.
- New spell: extend `UltimateAbility` (`_on_activate/_on_step/_on_end`, optional `pay_cost`, `draw_world`), add `Config.ultimates` block, register in `UltimateRegistry.create_default()`, add icon case in `ui/ability_icon.gd`, place a scroll (`?` + `"scrolls"`).

### Movement & items
- Coyote time, jump buffer, variable jump, gravity 2100. Wall slide/jump/climb-jump, double jump, dash (i-frames), grapple are **items** (`PlayerData.MOVEMENT`: `double_jump`, `dash`, `wall_climb`, `grapple`), placed once each (`j`,`d`,`c`,`g`). Old saves keep all movement.
- First pickup of each item/potion/scroll/altar → full-screen `TutorialPopup` (pauses game, any key closes, closing key ignored, once per save via `seen_tutorials`).

### Hazards & i-frames (`combat/damage.gd`, `HealthEnergy.blocks(source)`)
| Source | Examples | Blocked by i-frames / invulnerability? |
| --- | --- | --- |
| `ENEMY` | body contact | Yes |
| `PROJECTILE` | anything fired (incl. by a hazard) | Yes |
| `HAZARD` | spikes, lava | **Never** (not dash, cast, dive, post-hit). Only debug God Mode. |
- Hazard hit → damage + teleport to `player.safe_point` (last safe ground; ground within 1.5 tiles of lava is not safe) → no damage loops. Death (health 0) → collapse → fade → last saved checkpoint, in trance.
- Hit guards (Aegis) only see ENEMY/PROJECTILE. Enemies touching spikes/lava die; shards touching spikes vanish.
- Spikes: `^` floor, `V` ceiling, `<`/`>` wall (transform flags; `Room.hazard_rect_for_cell`). Lava `L`: **floor only**, never pogoed.

### Persistence & saves
- `WorldState` (in memory, session): `dead_enemies` (room → spawn → tier), `defeated_bosses`, `cleared_arenas`, `collected_coins`, `secrets` (broken walls + found Type 1 pockets), `relics` (incl. potions), `wounds` (elites, not saved).
- Respawn hierarchy: **weak** revive on room re-entry or checkpoint rest; **strong/elite** only on checkpoint rest (save, death, load); **boss** never. Survivors return at full health unless `keeps_wounds`. No timed respawn.
- Save slot (`Game.make_save_data`) = checkpoint + room, currency, movement, tutorials, known/equipped spells, open slots, stat bonuses, `WorldState.to_dict()` (bosses, arenas, coins, secrets, relics), map state, playtime. Respawnable enemy deaths are deliberately **not** saved.
- Saved on: checkpoint save, arena clear, boss defeat, secret broken, relic/potion, scroll, movement item, meditation. Loading → saved checkpoint, trance, 0 energy, enemies reset.
- Old-save compatibility paths exist (all slots open, full movement, default loadout); keep them when changing the schema.
- Placed coins are saved **by node name** — don't rename them (pocket coins use `*` → `PocketCoinN` for that reason).

### Map & fog of war (`map/`)
- `MapAtlas.WORLD` is data: zones (`world_origin`, `color`), rooms (rect in map cells, `base`, `hidden`), exits (one per door: `door_id`, target room/door, `secret`). `MapState`: owned maps, outlined/filled/pending rooms. Without a zone's map nothing of that zone is shown ("No Map").
- Spatial anomaly rule: remove the doorway from both layouts; `MapAtlas.resolve_anomalies()` + `Game.seal_door()` are only a safety net; the smoke test fails on unresolved anomalies.

### Rooms & build pipeline
- Rooms are generated from ASCII layouts in `tools/build_assets.gd` (`ROOM_LAYOUT`, `BOSS_LAYOUT`, `ARENA_LAYOUT`, `SECRET_LAYOUT`, `UPPER_LAYOUT`, `VAULT_LAYOUT`, `LAVA_LAYOUT`, `BESTIARY_LAYOUT`, metadata in `ROOMS`: doors, spawns, scrolls, altars, maps, movers, `origin_x`, `secret_doorway`…). Legend at the top of the file (`#` solid, `=` one-way, `O` ceiling/floor gap, `D`/`H` door, `Z`/`z` breakable secret exit, `I` Type 1 pocket wall, `X`/`x` Type 2 doorway, `*` pocket shard, `$` shard, `S`/`C` checkpoints, `+ m b` pegs, `_ ~ %` platforms, `L` lava, `h e ? A` progression, `j d c g` items, `M` map, `!` BaseEnemy spawn, `E F G` dummies, `N W K U T` NPC/tablets).
- Rebuild: delete the room `.tscn`, then `godot --headless --path . --script res://tools/build_assets.gd` (`-- --force` to overwrite). The tool **never overwrites existing files** without `--force` (art replacements are safe). Watch for `Rule … violated` errors.
- Physics layers: 1 world, 2 player, 3 one_way, 4 enemies, 5 hidden_wall_player, 6 hidden_wall_enemy, 7 grapple_peg. Hazards have no collision (tile custom data `hazard`; also `one_way`).
- `Room` answers world queries (solid, hazard, ground, safe ground, `free_spot`, `open_direction`, bounds / `main_rect`).

### Tests
```bash
godot --headless --path . --fixed-fps 60 res://tests/smoke_test.tscn
```
Exit code 0 = all pass. Writes only to `user://test_saves`. Older checks run with `Game.grant_full_kit()` and `tutorials_enabled = false`. Every new feature gets smoke-test checks; the README's "Automated test" paragraph is a running changelog of what's covered.

---

## 4. Development guidelines check (from `GUIDELINES.md` — binding)

**Room transition rules**
- **A — Downward:** ground (`#` or `=`) under the **whole width** of a ceiling gap within 4 tiles. Enforced `Game._landing_arrival()`; checked at build + smoke test. Fix the layout, never the code.
- **B — Upward:** player emerges through the floor gap, rises, then a ballistic arc to ONE standable side (random if both). Never placed on the floor, never falls back in; not invulnerable; input ignored until landing. `Game._ejection_arrival()`, `eject_state.gd`.
- **C — Secret breakable walls work in arenas:** `Z`/`z` exits get `secret = true` doors that arena locks skip; `hit_breakable` never checks arena state; no gates drawn over them; leaving mid-fight aborts the arena.
- **D — Solid boundaries:** every outer edge cell is `#` or part of a transition; Type 1 pockets closed on all other sides and not touching the layout edge; camera shows one tile of wall around a found pocket (`HiddenPocketWall.camera_rect()`).
- **E — Secret room exits look open:** Type 2 exit side draws nothing; any way out of a secret room is an ordinary opening.

**F — No celebrations, anywhere (no-fanfare policy)**
- Boss kill, arena clear, secret, relic, potion, scroll, map, meditation → only environmental feedback (own roar/dissolve + light shake; gate clunk; crash + debris; soft `pickup` + small puff; one low `save` tone). No victory music/jingle, banners, text pop-ups, flashes, rings, freezes.
- Never add sounds like `victory`/`fanfare`/`secret`/`jingle` or fx like `arena_clear`/`boss_death` — the smoke test fails if they exist. The HUD has no banner system; don't add one. Tutorial popups are explanations, not praise.

**Secret walls — two types, never mixed**
- Type 1 `HiddenPocketWall` (`I`): same room, one-way until found, revealed once and saved, cover hides contents, silent, blocks the hook until found.
- Type 2 `SecretDoorway` (`X`/`x` + `Door`): another room, reusable, never saved, entry side semi-transparent, exit side invisible.

**Other binding rules**
- Lava floor-only on solid `#`, never pogoed, ≥4-tile ledges at doorways.
- Enemies: visible telegraph for every attack, no "!" (red eyes only), sight ≈420 px (ranged 480) with LOS, elites = strong + keeps_wounds, deflectable vs non-deflectable looks never mixed, deflect window never tighter than the swing, only melee deflects, every new enemy gets a Bestiary chamber.
- Map: every room on exactly one zone map with one exit per door; secret rooms `hidden`.
- Progression objects on standable floor; one scroll per spell and one item per movement ability in the world, reachable in order.
- Exits have no visual markers (only Type 2 entry disguise).

**Modular placeholder policy**
- Gameplay code never draws art or builds sounds; it asks **by name**. Art lives in `Visual`/`Rig` nodes + AnimationPlayer clips with fixed names; effects in `effects/fx/<name>.tscn`; sounds as named nodes in `audio/sfx.tscn` + `audio/sfx/<name>.wav`. Swap assets without code changes; keep node and clip names. Empty secret-wall art nodes are filled with wall tiles at runtime.
- Tunables go in `Config`, not literals in gameplay code. Gameplay → `Events` → `Feedback` for game feel.
- UI is always LTR; no numbers except shards in player-facing UI.

**Workflow checklist for changes**
1. Read `GUIDELINES.md` before touching rooms, exits, secrets or feedback.
2. Edit layouts in `tools/build_assets.gd`, delete the `.tscn`, rebuild, check for rule errors.
3. Update `map/map_atlas.gd` for any room/door change.
4. Add smoke-test checks and run the smoke test.
5. Update `README.md` (and this file if architecture changes).

## Known small gaps noticed during mapping
- `Saves.ROOM_NAMES` lacks `hidden_vault` and `lava_room`, so slot summaries for saves in those rooms show `?`.
- `README.md` project layout says GUIDELINES covers "rules A-D"; it actually defines A–F.
