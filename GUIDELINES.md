# Design Guidelines

These rules are binding for every room, layout, transition and piece of feedback in this project.
Read them before you add or change a room, a doorway, a secret wall or any win/discovery feedback.
They apply to developers and to AI assistants alike.

The same rules are repeated in the code, at the places that enforce them:

| Rule | Where it is enforced | Where it is checked |
| --- | --- | --- |
| A | `core/game.gd` → `_landing_arrival()` | `tools/build_assets.gd` → `_check_room_rules()`, smoke test "Rule A" |
| B | `core/game.gd` → `_ejection_arrival()` | `tools/build_assets.gd` → `_check_room_rules()`, smoke test "Rule B" |
| C | `core/game.gd` → `_update_doors()`, `hit_breakable()`; `combat/combat_manager.gd` (breakable hits) | smoke test "Rule C" |
| D | `effects/feedback.gd` (boss, arena, secret, relic handlers); `tools/build_assets.gd` (`FX`, `SOUNDS`) | smoke test "no celebration …" |

`world/objects/door.gd` and the room section of `tools/build_assets.gd` carry a short summary of all three rules.

---

## Rule A — Downward transitions: ground right after the boundary

**Whenever a room transition leads downward, solid ground must be placed immediately after the boundary, so the player lands safely.**

- A downward transition is any exit the player falls into. It ends at the **ceiling gap** of the room below (`'O'` in row 0, `vertical = -1`).
- Directly below that gap, across its **whole width**, there must be ground: a solid tile (`#`) or a one-way platform (`=`), at most 4 tiles down.
- The player must never fall through open space, into spikes or into another exit right after arriving.
- Example: in the Testing Halls the ceiling gap spans columns 30–33. The cap of the central hanging wall spans the same four columns, so every drop lands on it.

**In code.** `Game._landing_arrival()` keeps the arrival point when ground lies below it. Otherwise it moves the point along the gap to the nearest spot with ground below. It logs a warning if there is none. That warning means a layout is wrong; fix the layout, not the code.

**At build time.** `tools/build_assets.gd` reports `Rule A violated …` as an error if any gap column has no ground below it.

## Rule B — Upward transitions: out and to one side

**Whenever a room transition leads upward, the player physically emerges through the floor gap and is ejected UP and to ONE SIDE: toward a side with standable floor, or a random side if both are standable. The player must never fall straight back into the transition zone, and is never simply placed on the floor.**

- An upward transition is any exit the player jumps into. It ends at the **floor gap** of the room above (`'O'` in the bottom row, `vertical = 1`).
- At least one side of the floor gap must have **standable floor**: solid under the player's full width, with head room above (2 open tiles).
- The player appears at the **threshold** of the opening: inside the gap, just above its trigger. The `eject` state (`player/states/eject_state.gd`) then moves them through real space:
  1. **Rise:** straight up out of the gap until the feet clear the floor surface. There is no sideways motion yet, so the gap's edges are never clipped.
  2. **Arc:** a ballistic launch (real gravity and collisions) that peaks above the floor and lands just beside the gap edge on the chosen side (`EJECT_MARGIN`).
- Input is ignored until the landing, so the arc never drifts back over the gap. The player is not invulnerable while ejected.
- If both sides are standable, the side is chosen at random.
- Example: in the Upper Galleries the floor gap spans columns 4–7. Columns 1–3 and 8+ are floor, so the player comes out on the left or the right at random.

**In code.** `Game._ejection_arrival()` finds the standable sides with `_floor_surface()` and picks one; `Player.begin_ejection()` starts the climb and arc. If neither side is standable, it logs a warning and falls back to a strong upward boost inside the gap. That fallback is not acceptable in a finished layout.

**At build time.** `tools/build_assets.gd` reports `Rule B violated …` as an error if neither side of a floor gap is standable.

## Rule C — Secret breakable walls keep working inside arenas

**Secret breakable walls must stay fully functional and destructible inside arena rooms. When an arena fight locks the regular doors, breakable-wall exits must stay accessible, for escape or exploration.**

- A secret exit is a breakable wall that fills a gap in the outer wall, with a door behind it (`'Z'` in a layout, plus `'z'` for the upper cells of the gap).
- The generator gives these doors `secret = true`. `Game._update_doors()` locks doors during an active arena **except** secret doors.
- Hitting a breakable wall (`combat_manager.gd` → `Game.hit_breakable()`) never checks the arena state.
- Arena gates are never drawn over a secret wall, so the arena does not give the secret away.
- Leaving through a secret exit mid-fight aborts the attempt. The arena is not cleared and starts again on the next visit. The broken wall stays broken (saved in `WorldState.secrets`).

## Rule D — No celebrations, anywhere

**Defeating a boss, clearing an arena, breaking a secret wall or taking a relic never triggers a celebration.** No victory music, fanfare or jingle. No text pop-up or banner. No victory effects, flashes, flares or rings. No freeze.

Feedback stays strictly environmental, and play continues at once:

| Event | Allowed feedback |
| --- | --- |
| Boss defeated | Its own roar, a shudder, the dissolve clip and particles. A light camera shake. |
| Arena cleared | The gates open with a mechanical clunk (`gate`). No more enemies come. |
| Secret wall broken | A crash (`break`), falling debris (`wall_break`, particles only), a light shake. |
| Relic taken | A soft pickup sound (`pickup`) and a small puff (`relic_pickup`). The relic is gone. |

- Do not add sounds such as `victory`, `fanfare`, `secret` or `jingle`, nor effects such as `arena_clear` or `boss_death`. The smoke test fails if they exist.
- The HUD has no banner or pop-up text system. Do not add one for these events.

---

## Checklist for a new room or exit

1. Side exit: a 3-tile gap in the side wall, door letter in its bottom cell (`D` / `H`). Arrival keeps height and speed.
2. Exit going **down** into this room (ceiling gap): ground under the whole gap within 4 tiles (**Rule A**).
3. Exit going **up** into this room (floor gap): standable floor on at least one side of the gap (**Rule B**).
4. Secret exit: `Z` / `z` in the outer wall, never a normal door; keep it usable during arenas (**Rule C**).
5. No visual markers on exits: an exit is just a missing piece of wall.
6. No celebration when anything in the room is won or found (**Rule D**).
7. Rebuild with `godot --headless --path . --script res://tools/build_assets.gd` (delete the room's `.tscn` first). Look for `Rule … violated` errors.
8. Run the smoke test: `godot --headless --path . --fixed-fps 60 res://tests/smoke_test.tscn`.
