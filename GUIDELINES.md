# Room-Design Guidelines

These rules are binding for every room, layout and transition in this project.
Read them before you add or change a room, a doorway or a secret wall.
They apply to developers and to AI assistants alike.

The same rules are repeated in the code, at the places that enforce them:

| Rule | Where it is enforced | Where it is checked |
| --- | --- | --- |
| A | `core/game.gd` → `_landing_arrival()` | `tools/build_assets.gd` → `_check_room_rules()`, smoke test "Rule A" |
| B | `core/game.gd` → `_ejection_arrival()` | `tools/build_assets.gd` → `_check_room_rules()`, smoke test "Rule B" |
| C | `core/game.gd` → `_update_doors()`, `hit_breakable()`; `combat/combat_manager.gd` (breakable hits) | smoke test "Rule C" |

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

**Whenever a room transition leads upward, the spawn point offsets the player UP and slightly to ONE SIDE: toward a side with standable floor, or a random side if both are standable. The player must never fall straight back into the transition zone.**

- An upward transition is any exit the player jumps into. It ends at the **floor gap** of the room above (`'O'` in the bottom row, `vertical = 1`).
- At least one side of the floor gap must have **standable floor**: solid under the player's full width, with head room above (2 open tiles).
- The player appears just beside the gap edge on that side (`EJECT_MARGIN`), a little above the floor (`EJECT_LIFT`), with a small hop away from the gap (`EJECT_HOP`). They then land on that floor.
- If both sides are standable, the side is chosen at random.
- Example: in the Upper Galleries the floor gap spans columns 4–7. Columns 1–3 and 8+ are floor, so the player comes out on the left or the right at random.

**In code.** `Game._ejection_arrival()` finds the standable sides with `_floor_surface()` and picks one. If neither side is standable, it logs a warning and falls back to a strong upward boost inside the gap. That fallback is not acceptable in a finished layout.

**At build time.** `tools/build_assets.gd` reports `Rule B violated …` as an error if neither side of a floor gap is standable.

## Rule C — Secret breakable walls keep working inside arenas

**Secret breakable walls must stay fully functional and destructible inside arena rooms. When an arena fight locks the regular doors, breakable-wall exits must stay accessible, for escape or exploration.**

- A secret exit is a breakable wall that fills a gap in the outer wall, with a door behind it (`'Z'` in a layout, plus `'z'` for the upper cells of the gap).
- The generator gives these doors `secret = true`. `Game._update_doors()` locks doors during an active arena **except** secret doors.
- Hitting a breakable wall (`combat_manager.gd` → `Game.hit_breakable()`) never checks the arena state.
- Arena gates are never drawn over a secret wall, so the arena does not give the secret away.
- Leaving through a secret exit mid-fight aborts the attempt. The arena is not cleared and starts again on the next visit. The broken wall stays broken (saved in `WorldState.secrets`).

---

## Checklist for a new room or exit

1. Side exit: a 3-tile gap in the side wall, door letter in its bottom cell (`D` / `H`). Arrival keeps height and speed.
2. Exit going **down** into this room (ceiling gap): ground under the whole gap within 4 tiles (**Rule A**).
3. Exit going **up** into this room (floor gap): standable floor on at least one side of the gap (**Rule B**).
4. Secret exit: `Z` / `z` in the outer wall, never a normal door; keep it usable during arenas (**Rule C**).
5. No visual markers on exits: an exit is just a missing piece of wall.
6. Rebuild with `godot --headless --path . --script res://tools/build_assets.gd` (delete the room's `.tscn` first). Look for `Rule … violated` errors.
7. Run the smoke test: `godot --headless --path . --fixed-fps 60 res://tests/smoke_test.tscn`.
