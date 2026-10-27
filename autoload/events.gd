extends Node
## Global signal hub (autoload "Events").
## Systems emit and listen here instead of holding references to each other.
## Example: CombatManager emits hit_landed; energy gain, hitstop, shake and
## particles each react on their own.

# Combat
@warning_ignore("unused_signal")
signal hit_landed(info: Dictionary) ## {target, damage, position, source, grants_energy, strength}
@warning_ignore("unused_signal")
signal pogo_bounced(position: Vector2, on_hazard: bool)
@warning_ignore("unused_signal")
signal attack_swung(direction: String)
@warning_ignore("unused_signal")
signal enemy_killed(enemy: Node)
@warning_ignore("unused_signal")
signal grapple_fired(origin: Vector2, direction: Vector2)
@warning_ignore("unused_signal")
signal grapple_latched(anchor: Vector2, on_enemy: bool) ## The hook holds; the pull starts.
@warning_ignore("unused_signal")
signal grapple_released(position: Vector2) ## The hook lets go (missed, refused or pull over) and flies back.
@warning_ignore("unused_signal")
signal grapple_deflected(position: Vector2) ## The hook touched a hazard: it never latches there.
@warning_ignore("unused_signal")
signal grapple_bounced(position: Vector2) ## An enemy pull ended in the upward rebound.
@warning_ignore("unused_signal")
signal grapple_swing_ended(reason: String) ## "input", "terrain", "obstructed" or "interrupted" (damage, hazard, reset).

# Player
@warning_ignore("unused_signal")
signal player_jumped(player: Node, kind: String)
@warning_ignore("unused_signal")
signal player_landed(player: Node, fall_speed: float)
@warning_ignore("unused_signal")
signal player_dashed(player: Node, direction: int)
@warning_ignore("unused_signal")
signal player_hurt(player: Node, damage: float)
@warning_ignore("unused_signal")
signal player_died(player: Node)
@warning_ignore("unused_signal")
signal player_hazard_respawn(player: Node, from_position: Vector2, to_position: Vector2)
@warning_ignore("unused_signal")
signal player_dying(player: Node)
@warning_ignore("unused_signal")
signal player_respawned(player: Node)
@warning_ignore("unused_signal")
signal trance_broken(player: Node)
@warning_ignore("unused_signal")
signal heal_started(player: Node)
@warning_ignore("unused_signal")
signal heal_ended(player: Node)

# Vitals
@warning_ignore("unused_signal")
signal health_damaged(amount: float)
@warning_ignore("unused_signal")
signal health_healed(amount: float)
@warning_ignore("unused_signal")
signal energy_changed(value: float)

# Ultimates
@warning_ignore("unused_signal")
signal loadout_changed()
@warning_ignore("unused_signal")
signal ultimate_cast(ability: RefCounted)
@warning_ignore("unused_signal")
signal ultimate_denied(ability: RefCounted, reason: String)
@warning_ignore("unused_signal")
signal ultimate_impact(hitstop: float, shake: float)

# World, progression and UI
@warning_ignore("unused_signal")
signal checkpoint_activated(checkpoint: Node)
@warning_ignore("unused_signal")
signal player_rested(checkpoint: Node)
@warning_ignore("unused_signal")
signal currency_collected(amount: int, position: Vector2)
@warning_ignore("unused_signal")
signal dialogue_opened()
@warning_ignore("unused_signal")
signal dialogue_closed()

# Rooms, bosses and arenas
@warning_ignore("unused_signal")
signal room_entered(room_id: String)
@warning_ignore("unused_signal")
signal boss_telegraph(boss: Node, attack: String)
@warning_ignore("unused_signal")
signal boss_phase_changed(boss: Node, phase: int)
@warning_ignore("unused_signal")
signal boss_defeated(boss: Node)
@warning_ignore("unused_signal")
signal arena_started(arena_id: String)
@warning_ignore("unused_signal")
signal arena_wave_started(arena_id: String, wave: int)
@warning_ignore("unused_signal")
signal arena_cleared(arena_id: String)
@warning_ignore("unused_signal")
signal enemy_spawning(enemy: Node)
@warning_ignore("unused_signal")
signal enemy_blocked(enemy: Node, direction: Vector2) ## A hit bounced off a shield (Enemy.blocks_hit).
@warning_ignore("unused_signal")
signal enemy_telegraph(enemy: Node, attack: String) ## A BaseEnemy is about to attack (wind-up starts).
@warning_ignore("unused_signal")
signal enemy_slam(enemy: Node, position: Vector2, strength: float) ## A heavy blow hit the ground (screen shake).
@warning_ignore("unused_signal")
signal enemy_parried(enemy: Node, position: Vector2) ## A melee swing stopped a deflectable enemy strike.
@warning_ignore("unused_signal")
signal projectile_deflected(position: Vector2) ## A melee swing swatted a deflectable projectile back.
@warning_ignore("unused_signal")
signal secret_found(secret_id: String, position: Vector2)
@warning_ignore("unused_signal")
signal hidden_pocket_found(secret_id: String) ## A Type 1 hidden pocket was walked into (no feedback: Rule F).
@warning_ignore("unused_signal")
signal relic_collected(relic_id: String, position: Vector2)

# Progression: potions, spell scrolls, meditation altars
@warning_ignore("unused_signal")
signal potion_collected(potion_id: String, stat: String, position: Vector2) ## A Health / Mana Potion raised a maximum.
@warning_ignore("unused_signal")
signal scroll_collected(spell_id: String, position: Vector2) ## A Spell Scroll was picked up.
@warning_ignore("unused_signal")
signal spell_learned(spell_id: String) ## An equippable spell joined the known pool.
@warning_ignore("unused_signal")
signal meditation_started(altar: Node)
@warning_ignore("unused_signal")
signal meditation_finished(altar: Node, slot: int) ## slot: PlayerData.SLOT_*, or -1 if interrupted.
@warning_ignore("unused_signal")
signal spell_slot_opened(slot: int) ## A directional slot (PlayerData.SLOT_*) was unlocked for good.
@warning_ignore("unused_signal")
signal movement_learned(ability_id: String, position: Vector2) ## An AbilityPickup was collected.
@warning_ignore("unused_signal")
signal tutorial_opened(tutorial_id: String)
@warning_ignore("unused_signal")
signal tutorial_closed(tutorial_id: String)

# Map (map/map_state.gd, the quick view)
@warning_ignore("unused_signal")
signal map_acquired(zone_id: String) ## A zone's base map was taken: its rooms are outlined.
@warning_ignore("unused_signal")
signal map_collected(zone_id: String, position: Vector2) ## A MapPickup was touched (feedback).
@warning_ignore("unused_signal")
signal map_room_revealed(room_id: String, reveal: int) ## MapState.Reveal: OUTLINED or FILLED.
@warning_ignore("unused_signal")
signal map_opened() ## The quick view opened (the Map key is held).
@warning_ignore("unused_signal")
signal map_denied() ## The Map key was pressed in a zone whose map is not owned ("No Map").
@warning_ignore("unused_signal")
signal map_closed(reason: String) ## "released", "damage" or "interrupted".

# Animation (frame events from method tracks, e.g. "footstep", "swing")
@warning_ignore("unused_signal")
signal anim_event(owner: Node, event_name: String)
signal gear_changed() ## Pouches or tools were equipped, slotted or removed (GearManager).
signal tool_shockwave(position: Vector2, direction: Vector2) ## A tool's full-energy shockwave left a swing.
signal platform_crumbled(position: Vector2) ## A breakable platform gave way (it comes back later).
signal peg_crumbled(position: Vector2) ## A breakable grapple peg gave way (it comes back later).
