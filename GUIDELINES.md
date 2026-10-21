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
| D | `tools/build_assets.gd` → `_check_room_rules()` (outer edge), `_pocket_rect()` (pockets); `HiddenPocketWall.camera_rect()` | build-time `Rule D violated …` errors, smoke test "Rule D" |
| E | `world/objects/secret_doorway.gd` (the exit side draws nothing) | smoke test "Rule E" |
| F | `effects/feedback.gd` (boss, arena, secret, relic handlers); `tools/build_assets.gd` (`FX`, `SOUNDS`) | smoke test "no celebration …" |
| Secret walls (Type 1 / Type 2) | `world/objects/hidden_pocket_wall.gd`, `secret_doorway.gd` (base `secret_wall.gd`); `core/game.gd` → `_update_secret_walls()`, `_refresh_camera_bounds()` | `tools/build_assets.gd` → `_pocket_rect()` (pocket must be closed), smoke test "Type 1" / "secret doorway" |

`world/objects/door.gd` and the room section of `tools/build_assets.gd` carry a short summary of the rules. The secret wall scripts each start with the rules of their type.

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

## Rule D — Boundaries require solid walls

**Every room and every hidden alcove or pocket MUST be closed by solid, physical walls on all its outer edges wherever no transition exists. Open, unbounded void edges are strictly forbidden.**

- A room's outer edge (every border cell of its layout) is wall (`#`) or part of a transition: a side door gap (`D`/`H`, `Z`/`z`, `X`/`x`) or a ceiling / floor gap (`O`). Nothing else.
- A Type 1 hidden pocket is closed by wall on every side except its hidden pocket wall. It must not reach the layout's edge; the rock around it belongs to the room.
- The wall must also be **seen**: once a pocket outside the normal room area is found, the camera limits include one tile of the wall around it (`HiddenPocketWall.camera_rect()`). The player never stands at a screen edge that looks like open void.
- Example: the Testing Halls' far-west pocket ends at a solid wall two tiles thick (the layout's first two columns). Walking left inside it stops at that wall, and the wall is on screen.

**At build time.** `tools/build_assets.gd` reports `Rule D violated …` as an error for any open cell on a layout's outer edge that is not part of a transition, and for a hidden pocket that reaches the layout edge.

## Rule E — Secret room exits look open

**When returning from a secret or hidden room to a standard room, the transition doorway MUST look fully open and natural, exactly like a standard room opening. It may never appear blocked or solid from the inside.**

- A Type 2 secret doorway is disguised only on its **entry** side (the room it is discovered from). On its **exit** side (inside the secret room, `side = "exit"`) nothing is drawn: the gap in the wall is an ordinary opening, like any side door.
- Do not add exit-side art that makes the doorway look closed. Framing art (an arch, vines at the sides) is fine as long as the opening stays clearly open.
- The same holds for any other way out of a secret room (the Hidden Shrine's west door is a plain open doorway).

## Rule F — No celebrations, anywhere

**Defeating a boss, clearing an arena, breaking a secret wall or taking a relic never triggers a celebration.** No victory music, fanfare or jingle. No text pop-up or banner. No victory effects, flashes, flares or rings. No freeze.

Feedback stays strictly environmental, and play continues at once:

| Event | Allowed feedback |
| --- | --- |
| Boss defeated | Its own roar, a shudder, the dissolve clip and particles. A light camera shake. |
| Arena cleared | The gates open with a mechanical clunk (`gate`). No more enemies come. |
| Secret wall broken | A crash (`break`), falling debris (`wall_break`, particles only), a light shake. |
| Relic taken | A soft pickup sound (`pickup`) and a small puff (`relic_pickup`). The relic is gone. |
| Hidden pocket found (Type 1) | Nothing at all. The disguise and the cover simply are no longer there. |
| Secret doorway used (Type 2) | Nothing beyond an ordinary room transition. |

- Do not add sounds such as `victory`, `fanfare`, `secret` or `jingle`, nor effects such as `arena_clear` or `boss_death`. The smoke test fails if they exist.
- The HUD has no banner or pop-up text system. Do not add one for these events.

---

## Secret walls — two types, never mixed

A secret wall is a piece of "wall" the player can walk through **without attacking it**. (A wall you strike until it crumbles is a breakable wall: `Z`, Rule C.) There are exactly two types. They differ in purpose, lifetime and look, so each has its own script, scene and art nodes. Both extend `SecretWall` (`world/objects/secret_wall.gd`).

| | Type 1 — Hidden Pocket | Type 2 — Secret Doorway |
| --- | --- | --- |
| Leads to | A pocket or alcove of the **same** room | A **different** room (a room transition) |
| Script / scene | `HiddenPocketWall` — `world/objects/hidden_pocket_wall.gd` / `.tscn` | `SecretDoorway` — `world/objects/secret_doorway.gd` / `.tscn` (plus an ordinary `Door`) |
| Layout letter | `I` (one wall per vertical run) | `X` bottom cell, `x` upper cells of the 3-tall gap |
| Lifetime | Revealed **once and for good** by the first pass. Saved (`WorldState.secrets`). | **Never consumed.** Usable back and forth, as often as you like. Not saved. |
| Before / after | Disguised, then gone: wall and cover disappear | Always the same |
| Collision | One-way until found (entry side only), then open both ways. Enemies never pass. | None. The `Door` behind it does the transition. |
| Look | Disguise drawn semi-transparent (placeholder, 50 %). The pocket's contents are covered. | Entry side: **semi-transparent**. Exit side (inside the secret room): **an ordinary open doorway**, nothing drawn (**Rule E**). |
| Boundaries | The pocket is closed by solid wall on every other side (**Rule D**). | An ordinary 3-tall side-door gap in a closed wall (**Rule D**). |
| Art nodes | `Visual` (the disguise), `Cover` (hides the pocket), optional `AnimationPlayer` clip `reveal` | `EntryVisual` (entry side only), optional `AnimationPlayer` clip `pass`. No exit visual (**Rule E**). |

### Type 1 — Hidden Pocket (alcove inside the room)

**A hidden pocket wall hides a small pocket of the current room. The pocket and everything in it stay completely hidden until the player first passes through the wall; from then on the pocket is permanently revealed.**

- **Hidden until found.** The `Cover` node lies over the whole pocket (`pocket_rect`, found by flood fill at build time). Items, shards, enemies and doors inside cannot be seen. The cover is drawn above pickups and enemies, below the player.
- **One-way until found.** From the entry side (`pass_dir`) the player walks straight in. From the pocket side the wall is solid. The pocket must be closed on every other side; the generator reports an error if it leaks into the room.
- **Found by passing through.** The first full pass reveals it **for good**: the disguise and the cover disappear, the wall is open both ways, and `WorldState.secrets` stores its `secret_id`. A room change, a death or a save load never hides it again. Finding it is silent (Rule F).
- **Camera.** A pocket outside the room's normal area (`Room.main_rect`, set by `origin_x` in a layout) is kept off-screen: the camera limits stop at the normal room edge until the pocket is found. `Game._refresh_camera_bounds()` then adds the pocket, and the camera may scroll into it. A pocket inside the normal area changes nothing.
- **Shards inside** use `*` (named `PocketCoinN`), so adding a pocket never renames the room's other shards (saves refer to them by name).
- Current instances:
  - **Upper Galleries, east:** the alcove under the east block, near the room's right edge, entered from the left. It holds two shards and a training dummy.
  - **Testing Halls, far west:** the west wall at floor level hides a pocket **beyond the room's normal left edge** (the layout's `origin_x = -7` columns). Before it is found, the camera never scrolls left of the room. It holds two shards.

### Type 2 — Secret Doorway (hidden room transition)

**A secret doorway is a standard side door to another room, disguised as wall. It works like any room transition and never disappears.**

- It sits in an ordinary 3-tall side-door gap with a `Door` node; walking into the "wall" moves the player to the other room. No attack, no key.
- **Reusable:** back and forth, as often as you like. Nothing is saved and nothing changes after use.
- **Visual asymmetry:** the room you discover it from has the **entry** side (`side = "entry"`): drawn **semi-transparent**, so an attentive player can spot it. The secret room has the **exit** side (`side = "exit"`): **nothing is drawn**, so the way back looks like a standard open doorway (**Rule E**).
- A secret doorway's entry side is the one exception to "no visual markers on exits": its disguise is drawn on purpose.
- Current instance: **Upper Galleries, west wall (entry) ⇄ Hidden Vault, east wall (exit).**

---

## Checklist for a new room or exit

1. Side exit: a 3-tile gap in the side wall, door letter in its bottom cell (`D` / `H`). Arrival keeps height and speed.
2. Exit going **down** into this room (ceiling gap): ground under the whole gap within 4 tiles (**Rule A**).
3. Exit going **up** into this room (floor gap): standable floor on at least one side of the gap (**Rule B**).
4. Secret exit: `Z` / `z` in the outer wall, never a normal door; keep it usable during arenas (**Rule C**).
5. No visual markers on exits: an exit is just a missing piece of wall. (Only a Type 2 secret doorway's entry side is drawn, as a disguise.)
6. Every outer edge is solid wall unless it is part of a transition; every hidden pocket is closed by wall (**Rule D**).
7. A way back out of a secret room looks like an ordinary open doorway (**Rule E**).
8. No celebration when anything in the room is won or found (**Rule F**).
9. Secret wall? Decide the type first. A pocket of this room: Type 1 (`I`, pocket closed on all other sides, shards as `*`). A way to another room: Type 2 (`X`/`x` in both rooms, `"secret_doorway": "entry"` on the discovery side, `"exit"` in the secret room).
10. Rebuild with `godot --headless --path . --script res://tools/build_assets.gd` (delete the room's `.tscn` first). Look for `Rule … violated` errors.
11. Run the smoke test: `godot --headless --path . --fixed-fps 60 res://tests/smoke_test.tscn`.
