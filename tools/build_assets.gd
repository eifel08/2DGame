extends SceneTree
## Generates the placeholder content of the project with Godot's own API, so
## every scene and resource is guaranteed valid:
##   - Input Map actions (keyboard + gamepad) in project.godot
##   - Tile atlas texture, TileSet (collision, one-way, hazard data)
##   - Room scenes (test room + boss room, from the ASCII layouts below)
##   - Player and enemy placeholder rigs ("skeletons") and their AnimationLibraries
##
## The generated files are already committed. You only need this tool to
## rebuild them, e.g. after editing a room layout (delete the room .tscn first):
##   godot --headless --path . --script res://tools/build_assets.gd -- --force
## The first run on a fresh checkout creates tiles.png; run
##   godot --headless --path . --import
## (or open the editor once), then run this tool again.
## Without --force, existing files are left untouched.

const TS := 32

## '#' solid  '=' one-way  '^' floor spikes  'V' ceiling spikes (pointing down)
## '<' / '>' wall spikes pointing left / right (the wall is on the other side)
## 'E' weak ground dummy  'F' weak flying dummy
## 'G' strong dummy  'D' door (doorway to another room, see ROOMS)
## 'S' start checkpoint (+ player spawn)  'C' checkpoint  '$' shard (currency)
## 'N' guide NPC  'W' / 'K' / 'U' lore tablets  'T' checkpoint info tablet (see LORE)
## '+' grapple peg (GrapplePeg, centered in its cell; only the hook touches it)
## 'm' moving grapple peg  'b' breakable grapple peg (see the room's "movers")
## '_' platform  '~' moving platform  '%' breakable platform (Platform objects:
##     one node per horizontal run, one-way like '=')
## 'L' lava (Lava, one node per run): floor only, it must sit on a solid cell
## Progression (see core/game.gd): 'h' Health Potion, 'e' Mana Potion (+max
## health / +max energy, saved by id like relics), '?' Spell Scroll (the room's
## "scrolls" entry gives its spell id), 'A' Meditation Altar (the room's
## "altars" entry gives its slot: "up", "side" or "down"). Both entries are
## keyed by the "col,row" of the cell.
## Movement items (AbilityPickup): 'j' Double Jump, 'd' Dash, 'c' Wall Climb,
## 'g' Grappling Hook. A new game has none of them.
## Two spike pits (rows 21-22): touching them deals damage and respawns the
## player on the last safe ground. Wall spikes ('<', right part of the room,
## rows 10-12) and ceiling spikes ('V', under the block in row 13) are there to
## check that the grappling hook never latches on a hazard. The flying dummy above the right pit is for pogo chains.
## Two grapple pegs over the right pit: a low one level with the block left of
## the pit (throw right from its top and hang there: static hold), and one 45
## degrees up-right of it to swing on (Down + hook in the air).
## The first 7 columns lie LEFT of the normal room (origin_x = -7): solid rock
## around a hidden pocket (Type 1) behind the west wall. The camera only goes
## there once the pocket is found.
const ROOM_LAYOUT := [
	"#####################################O...##############################",
	"########..............................................................#",
	"########..............................................................#",
	"########..............................................................#",
	"########..$..........................####.............................#",
	"########=====..................#####.##......................e$.G.....#",
	"########.....##......................##....................########...#",
	"########.....##......................##..........................##...#",
	"########.....##.....$.h..............##..............$...........##...#",
	"########.....##...======.............##............======........##...#",
	"########.....##..................F...##.........................<##...#",
	"########.....##................$.....##.........................<##...#",
	"########.....##..............=====...##.....$...................<##...#",
	"########.....##......................##...####...................##...#",
	"########.....##..........$.?.........##...VVVV............+......##...#",
	"########.....##........=====.........##..........................##...#",
	"########.....##......................##..........................##...#",
	"########.....##....$.................##.................F........##...#",
	"########.....##..=====..........................?K....+..........##...#",
	"##.....#.....##................................####....................",
	"##.....I.......................................####....................",
	"##.*.*.I..W.c.T..S..?.N........A..U..$$.E..j..C####..........E..d..C..D",
	"#########################^^^^######==################^^^^^^^###########",
	"###################################Y.##################################",
]

## Boss room: a sealed arena. Letters are arena wave markers:
##   'w' weak dummy (wave 1)  'v' flying dummy (wave 1)  's' strong dummy (wave 2)  'B' boss (final wave)
const BOSS_LAYOUT := [
	"########################################",
	"#......................................#",
	"#......................................#",
	"#......................................#",
	"#......................................#",
	"#......................................#",
	"#......................................#",
	"#......................................#",
	"#...............========...............#",
	"#......................................#",
	"#...................v..................#",
	"#......................................#",
	"#.....======................======.....#",
	"........................................",
	"........................................",
	"D.............w.......s...w...B........H",
	"########################################",
	"########################################",
]

## Proving Grounds: a wave arena without a boss. Its east wall hides a
## breakable wall ('Z') filling the east wall gap that leads to the Hidden Shrine.
## Arena letters: 'w' weak (wave 1), 'v' flyer / 'u' weak (wave 2), 's' strong (wave 3).
const ARENA_LAYOUT := [
	"####################################",
	"#..................................#",
	"#..................................#",
	"#..................................#",
	"#..................................#",
	"#..................................#",
	"#..................................#",
	"#................?.................#",
	"#..............=======.............#",
	"#..................................#",
	"#...............v........v.........#",
	"#...........e......................#",
	"#.........=====.......=====........#",
	"...................................z",
	"...................................z",
	"D....C........w..s..w..u...w.s.....Z",
	"####################################",
	"####################################",
]

## Hidden Shrine (secret room): a relic ('R') on an altar, shards and a tablet ('Q').
const SECRET_LAYOUT := [
	"################################",
	"#..............................#",
	"#..............................#",
	"#..............................#",
	"#..............................#",
	"#..............................#",
	"#..............................#",
	"#..............................#",
	"#..............................#",
	"#.....h.$...............$?.....#",
	"#.....=====...........=====....#",
	"#..............................#",
	"#..............................#",
	"...............................#",
	"................R..............#",
	"D....A....Q...#####..$.$.$.$...#",
	"################################",
	"################################",
]

## Upper Galleries: a side room above the Test Room, entered through the
## ceiling gap ('O' = floor gap here, 4 cells wide). Standard enemies only.
## West wall: a secret doorway (Type 2, 'X'/'x') to the Hidden Vault.
## East: a hidden pocket (Type 1, 'I') under the block, with shards and a dummy.
## East wall, on top of the block: the doorway to the Ember Crossing ('H').
const UPPER_LAYOUT := [
	"########################################",
	"#......................................#",
	"#......................................#",
	"#..............F...........F...........#",
	"#......................................#",
	"#..........$.h.........$.........$.?...#",
	"#.........=====......=====......=====..#",
	"#......................................#",
	"#.......................................",
	"#.....................F.................",
	"#..................................$...H",
	"#..............======...........########",
	"#...............................########",
	"x...............................I......#",
	"x...............................I......#",
	"X..$.......AE..........G..g...E.I..*E*.#",
	"####....################################",
	"####O...################################",
]

## Hidden Vault: a secret room behind the Upper Galleries' west wall (at
## least one screen in size, like every room, so the camera stays inside).
## Its east doorway is the exit side of the secret doorway: it looks like wall.
## Its west doorway ('D') is the goal exit of the Ember Crossing.
const VAULT_LAYOUT := [
	"################################",
	"#..............................#",
	"#..............................#",
	"#..............................#",
	"#..............................#",
	"#..............................#",
	"#.............?$$..............#",
	"#............======............#",
	"#..............................#",
	"#..............................#",
	"#.......e.$..........$.........#",
	"#.......=====......=====.......#",
	"#..............................#",
	"...............................x",
	"...............................x",
	"D....$......$.....$......$.....X",
	"################################",
	"################################",
]

## Ember Crossing: a lava gauntlet between the Upper Galleries (west) and the
## Hidden Vault (east). The whole floor is lava ('L') except the two ledges at
## the doorways. High ceiling. The way across, left to right:
##   A standard platform -> B moving platform (ride it right) -> throw at peg P1
##   (hold) -> jump to standard platform C -> throw at moving peg P2 when it is
##   low (hold, it lifts you) -> jump to breakable platform D (it crumbles 1 s
##   after you land) -> throw at breakable peg P3 (it crumbles 1 s after the
##   hook latches) -> jump right: moving platform E or the east ledge.
## Goal: the east ledge holds a relic and shards; its doorway leads on to the
## Hidden Vault. A checkpoint sits on the west ledge.
const LAVA_LAYOUT := [
	"################################################################",
	"#..............................................................#",
	"#..............................................................#",
	"#..............................................................#",
	"#..............................................................#",
	"#..............................................................#",
	"#..............................................................#",
	"#..............................................................#",
	"#..............................................................#",
	"#..............................................................#",
	"#..................................................b...........#",
	"#........................................%%%%..................#",
	"#..............................................................#",
	"#..............................................................#",
	"#.......................+.............m..............~~~.......#",
	"............~~~.............____................................",
	".......___......................................................",
	"D.C........................................................?$R$H",
	"#####LLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLL#####",
	"################################################################",
]

## Bestiary (a testing mega-hall): below the Testing Halls, entered by
## the floor gap ('Y' there) right of the tablet past the
## altar. A one-way plank covers that gap: walk over it, or Down + Jump to drop. An entrance
## hall (platforms back up to the gap, a checkpoint), then one chamber per
## enemy type, left to right. Dividers hang from the ceiling and end in a
## low curb, so walkers stay in their chamber and the player hops through.
## '!' an enemy (kind from the room's "spawns"), 'k' a chamber sign ("signs").
## Generated by a script: one chamber per enemy type, 22 tiles wide. The
## Ambushers' chamber holds 3 of them. The Hoppers' section is 64 tiles long
## and holds 20: cramped on purpose (a low ceiling, hanging stubs, low walls,
## ceiling notches and shelves, repeated every 16 tiles).
const BESTIARY_LAYOUT := [
	"########O.###################################################################################################################################################################################################################################################################################################################################################################################################################################",
	"#.................#......................#......................#......................#......................#......................#......................#......................#......................#......................#......................#......................#......................##################################################################......................#......................#......................#",
	"#.................#......................#......................#......................#......................#......................#......................#......................#......................#......................#......................#......................#......................##################################################################......................#......................#......................#",
	"#.....======......#......................#......................#......................#......................#......................#......................#......................#......................#......................#......................#......................#......................##################################################################......................#......................#......................#",
	"#.................#......................#......................#......................#......................#......................#......................#......................#......................#......................#......................#......................#......................##################################################################......................#......................#......................#",
	"#..........====...#......................#......................#......................#......................#......................#......................#......................#......................#......................#......................#......................#......................##################################################################..........!...........#......................#......................#",
	"#.................#......................#......................#......................#......................#......................#......................#......................#......................#......................#......................#......................#......................##################################################################.........####.........#......................#......................#",
	"#.................#......................#......................#......................#......................#......................#......................#......................#......................#......................#......................#......................#......................##################################################################.........####.........#......................#......................#",
	"#....====.........#......................#......................#......................#......................#......................#......................#......................#......................#......................#......................#......................#...........!..........##################################################################.........####.........#......................#......................#",
	"#.................#......................#......................#...........!..........#......................#......................#......................#......................#......................#......................#......................#......................#......................#......#...#...........#...#...........#...#...........#...#.....#......................#......................#...............!......#",
	"#.....................................................................................................!......................................................................................................................................................................................................#...............#...............#...............#..............................................................................#",
	"#.........====.................................................................................................................................................................................................................................................................................................===.............===.............===.............===..........................................................................#",
	"#....................................................................................................................................................................................................................................................................................................................#...............#...............#...............#......................................................................#",
	"#..............C..#..k..........!........#..k..........!........#..k...................#..k...................#..k...............!...#..k..............!....#..k..........!........#..k....!.....!....!...#..k..........!........#..k..........!........#..k................!..#..k...................#..k.#!.!..!.!.#!.!..!.!..!.!..#..!.!..!.!..!.!#.!.!..!.!......#.#..k...................#..k..........!........#..k...................#",
	"#############################################################################################################################################################################################################################################################################################################################################################################################################################################",
	"#############################################################################################################################################################################################################################################################################################################################################################################################################################################",
]

## Rooms: layout, output scene, doors (per letter) and optional arena.
##
## ROOM-DESIGN RULES (read GUIDELINES.md before editing any layout; the
## generator checks A and B and reports violations as errors):
##   Rule A - Downward transitions: wherever an exit leads DOWN into a room
##            (that room's ceiling gap), solid ground must lie directly below
##            the whole gap, within 4 tiles, so the player lands safely.
##            (Testing Halls: the cap of the central wall spans the full gap.)
##   Rule B - Upward transitions: wherever an exit leads UP into a room (that
##            room's floor gap), at least one side of the gap needs standable
##            floor. The player emerges through the gap and is ejected in an arc
##            onto that side (random side if both are standable), never back
##            over the gap.
##   Rule C - Secret breakable walls in arenas stay breakable and their door
##            stays open while the arena locks every other door ('Z' doors
##            get `secret = true`; no gate is drawn over them).
##   Rule D - Boundaries require solid walls: every cell on a layout's outer
##            edge is wall ('#') or part of a transition; a hidden pocket must
##            be closed by wall and may not reach the layout edge. Checked by
##            _check_room_rules() and _pocket_rect() (errors at build time).
##   Rule E - Secret room exits look open: an "exit" secret doorway draws no
##            disguise, so the way back looks like a standard opening.
##
## Door letters: 'D' / 'H' side doorway (bottom cell of a 3-tall wall gap),
## 'O' ceiling or floor gap ("width" cells from the letter to the right),
## 'Z' side doorway hidden behind a breakable wall that fills the gap ('z'
## marks the upper cells of that gap; they count as solid for tile edges).
## Secret walls (GUIDELINES.md, "Secret walls"):
## 'I' Type 1 hidden pocket wall (HiddenPocketWall): no tile, one object per
##     vertical run; the room's "hidden_pocket" entry gives its secret_id and
##     entry side. The pocket behind it is found by flood fill and covered.
## 'X' Type 2 secret doorway: a side door (bottom cell, like 'D') disguised by
##     a SecretDoorway; 'x' marks the upper cells of its gap. The door's
##     "secret_doorway" key is "entry" (semi-transparent disguise) or "exit"
##     (no disguise: an ordinary open doorway, Rule E).
## "origin_x" (optional, negative): the layout starts that many columns left
## of x = 0; the room's normal area (camera limits) starts at x = 0.
## '*' a shard inside a hidden pocket (named PocketCoinN, so adding a pocket
##     never renames the room's other shards, which saves refer to by name).
## World map:  Test Room <-> Boss Room <-> Proving Grounds <-(breakable wall)-> Hidden Shrine
##             Test Room <-(ceiling gap)-> Upper Galleries <-(secret doorway)-> Hidden Vault
##             Upper Galleries <-> Ember Crossing (lava) <-> Hidden Vault
const ROOMS := {
	"test_room": {
		"name": "TestRoom", "layout": ROOM_LAYOUT, "path": "res://world/test_room.tscn", "origin_x": -7,
		"doors": {
			"D": {"door_id": "east", "target_room": "boss_room", "target_door": "west", "inward": -1},
			"O": {"door_id": "ceiling", "target_room": "upper_room", "target_door": "floor", "vertical": -1, "width": 4},
			"Y": {"door_id": "floor", "target_room": "bestiary", "target_door": "ceiling", "vertical": 1, "width": 2},
		},
		# Type 1: the west wall hides a pocket beyond the room's normal area.
		"hidden_pocket": {"secret_id": "halls_west_alcove", "pass_dir": -1},
		# Right after the start: a scroll and the altar of the Up slot.
		"scrolls": {"20,21": "nova_burst", "27,14": "radiant_lance", "48,18": "meteor_slam"},
		"altars": {"31,21": "up"},
	},
	"boss_room": {
		"name": "BossRoom", "layout": BOSS_LAYOUT, "path": "res://world/boss_room.tscn",
		"doors": {
			"D": {"door_id": "west", "target_room": "test_room", "target_door": "east", "inward": 1},
			"H": {"door_id": "east", "target_room": "arena_room", "target_door": "west", "inward": -1},
		},
		"arena": {"arena_id": "sentinel_arena", "trigger_cols": [5, 34], "waves": [["w", "v"], ["s"], ["B"]]},
	},
	"arena_room": {
		"name": "ArenaRoom", "layout": ARENA_LAYOUT, "path": "res://world/arena_room.tscn",
		"doors": {
			"D": {"door_id": "west", "target_room": "boss_room", "target_door": "east", "inward": 1},
			"Z": {"door_id": "east", "target_room": "secret_room", "target_door": "west", "inward": -1},
		},
		"arena": {"arena_id": "proving_grounds", "trigger_cols": [9, 32], "waves": [["w"], ["v", "u"], ["s"]]},
		"secret_id": "proving_grounds_wall",
		"scrolls": {"17,7": "ascendant_form"},
	},
	"secret_room": {
		"name": "SecretRoom", "layout": SECRET_LAYOUT, "path": "res://world/secret_room.tscn",
		"doors": {"D": {"door_id": "west", "target_room": "arena_room", "target_door": "east", "inward": 1}},
		"relic": {"relic_id": "shrine_heart", "stat": "max_health", "amount": 25.0},
		"scrolls": {"25,9": "stasis_field"},
		"altars": {"5,15": "down"},
	},
	"upper_room": {
		"name": "UpperRoom", "layout": UPPER_LAYOUT, "path": "res://world/upper_room.tscn",
		"doors": {
			"O": {"door_id": "floor", "target_room": "test_room", "target_door": "ceiling", "vertical": 1, "width": 4},
			"X": {"door_id": "west", "target_room": "hidden_vault", "target_door": "east", "inward": 1, "secret_doorway": "entry"},
			"H": {"door_id": "east", "target_room": "lava_room", "target_door": "west", "inward": -1},
		},
		# Type 1: the alcove under the east block, entered from the left.
		"hidden_pocket": {"secret_id": "galleries_alcove", "pass_dir": 1},
		"scrolls": {"35,5": "spirit_volley"},
		"altars": {"11,15": "side"},
	},
	"hidden_vault": {
		"name": "HiddenVault", "layout": VAULT_LAYOUT, "path": "res://world/hidden_vault.tscn",
		"doors": {
			"X": {"door_id": "east", "target_room": "upper_room", "target_door": "west", "inward": -1, "secret_doorway": "exit"},
			"D": {"door_id": "west", "target_room": "lava_room", "target_door": "east", "inward": 1},
		},
		"scrolls": {"14,6": "repulse_aegis"},
	},
	"lava_room": {
		"name": "LavaRoom", "layout": LAVA_LAYOUT, "path": "res://world/lava_room.tscn",
		"doors": {
			"D": {"door_id": "west", "target_room": "upper_room", "target_door": "east", "inward": 1},
			"H": {"door_id": "east", "target_room": "hidden_vault", "target_door": "west", "inward": -1},
		},
		"relic": {"relic_id": "ember_heart", "stat": "max_energy", "amount": 20.0},
		"scrolls": {"59,17": "comet_dash"},
		# Moving platforms ('~') and pegs ('m'), keyed by "col,row" of their
		# first cell: travel (offset of the far end), period (s), phase (0..1).
		"movers": {
			"12,15": {"travel": Vector2(128, 0), "period": 4.0},
			"38,14": {"travel": Vector2(0, -128), "period": 4.0},
			"53,14": {"travel": Vector2(96, 0), "period": 3.0, "phase": 0.5},
		},
	},
}
const BESTIARY_ROOM := {
	"name": "Bestiary", "layout": BESTIARY_LAYOUT, "path": "res://world/bestiary.tscn",
	"doors": {
		"O": {"door_id": "ceiling", "target_room": "test_room", "target_door": "floor", "vertical": -1, "width": 2},
	},
	"spawns": {
			"32,13": "weak",
			"55,13": "strong",
			"76,9": "flyer",
			"102,10": "swooper",
			"129,13": "charger",
			"151,13": "thrower",
			"170,13": "brute",
			"187,13": "ambusher",
			"193,13": "ambusher",
			"198,13": "ambusher",
			"216,13": "shellback",
			"239,13": "urchin",
			"268,13": "turret",
			"283,8": "orb_sentry",
			"300,13": "hopper",
			"302,13": "hopper",
			"305,13": "hopper",
			"307,13": "hopper",
			"310,13": "hopper",
			"312,13": "hopper",
			"315,13": "hopper",
			"317,13": "hopper",
			"320,13": "hopper",
			"322,13": "hopper",
			"328,13": "hopper",
			"330,13": "hopper",
			"333,13": "hopper",
			"335,13": "hopper",
			"338,13": "hopper",
			"340,13": "hopper",
			"343,13": "hopper",
			"345,13": "hopper",
			"348,13": "hopper",
			"350,13": "hopper",
			"370,5": "crawler",
			"396,13": "phalanx",
			"421,9": "spearman",
	},
	"signs": {
			"21,13": "Training Dummy",
			"44,13": "Armored Dummy",
			"67,13": "Flying Dummy",
			"90,13": "Swooper",
			"113,13": "Charger",
			"136,13": "Thrower",
			"159,13": "Club Brute",
			"182,13": "Ambushers (3)",
			"205,13": "Shellback",
			"228,13": "Spike Urchin",
			"251,13": "Turret",
			"274,13": "Orb Sentry",
			"297,13": "Hoppers (20)",
			"362,13": "Wall Crawler",
			"385,13": "Shield Phalanx",
			"408,13": "Flying Spearman",
	},
}
const ARENA_KINDS := {"w": "weak", "u": "weak", "v": "flyer", "s": "strong", "B": "boss"}

## Dialogue per object letter.
const LORE := {
	"N": "res://dialogue/guide.tres",
	"W": "res://dialogue/lore_wall_jump.tres",
	"K": "res://dialogue/lore_spikes.tres",
	"U": "res://dialogue/lore_ultimates.tres",
	"T": "res://dialogue/lore_checkpoint.tres",
	"Q": "res://dialogue/lore_secret.tres",
}
const CHECKPOINT_SCENE := "res://world/objects/checkpoint.tscn"
const LORE_SCENE := "res://world/objects/lore_stone.tscn"
const NPC_SCENE := "res://world/objects/npc.tscn"
const COIN_SCENE := "res://world/objects/coin.tscn"
const DOOR_SCENE := "res://world/objects/door.tscn"
const BREAKABLE_SCENE := "res://world/objects/breakable_wall.tscn"
const RELIC_SCENE := "res://world/objects/relic.tscn"
const HIDDEN_POCKET_SCENE := "res://world/objects/hidden_pocket_wall.tscn"
const SECRET_DOORWAY_SCENE := "res://world/objects/secret_doorway.tscn"
const GRAPPLE_PEG_SCENE := "res://world/objects/grapple_peg.tscn"
const PEG_SCENES := {
	"+": GRAPPLE_PEG_SCENE,
	"m": "res://world/objects/grapple_peg_moving.tscn",
	"b": "res://world/objects/grapple_peg_breakable.tscn",
}
const PLATFORM_SCENES := {
	"_": "res://world/objects/platform.tscn",
	"~": "res://world/objects/platform_moving.tscn",
	"%": "res://world/objects/platform_breakable.tscn",
}
const LAVA_SCENE := "res://world/objects/lava.tscn"
const POTION_SCENES := {
	"h": "res://world/objects/health_potion.tscn",
	"e": "res://world/objects/mana_potion.tscn",
}
const SCROLL_SCENE := "res://world/objects/spell_scroll.tscn"
const ALTAR_SCENE := "res://world/objects/meditation_altar.tscn"
const ABILITY_PICKUP_SCENE := "res://world/objects/ability_pickup.tscn"
const ABILITY_LETTERS := {"j": "double_jump", "d": "dash", "c": "wall_climb", "g": "grapple"}
const SIGN_SCENE := "res://world/objects/chamber_sign.tscn"
## Ceiling / floor gap letters. 'O' is the usual one; 'Y' is a second gap in
## the same room (each letter has its own door entry).
const GAP_LETTERS := ["O", "Y"]
## Enemy kinds that fly (their spawn markers get meta "flying").
const FLYING_KINDS := ["flyer", "swooper", "orb_sentry", "spearman"]

const TILES_PNG := "res://world/tiles/tiles.png"
const TILESET := "res://world/tiles/tileset.tres"

# Atlas: columns 0-15 are solid tiles, one per exposed-edge mask
# (top = 1, right = 2, bottom = 4, left = 8), so every face that borders open
# space is lit and the collision outline is always visible.
const EDGE_TOP := 1
const EDGE_RIGHT := 2
const EDGE_BOTTOM := 4
const EDGE_LEFT := 8
const ONE_WAY := Vector2i(16, 0)
const SPIKES := Vector2i(17, 0)
const ATLAS_COLUMNS := 18
## Ceiling and wall spikes reuse the floor spike tile with transform flags.
const SPIKE_TURNS := {
	"V": TileSetAtlasSource.TRANSFORM_FLIP_V,
	"<": TileSetAtlasSource.TRANSFORM_TRANSPOSE,
	">": TileSetAtlasSource.TRANSFORM_TRANSPOSE | TileSetAtlasSource.TRANSFORM_FLIP_H,
}

## Player clips: frames/fps give the length; sx/sy squash, bob, lean (skew),
## body color, and an optional arm sweep [from, to] for attacks.
const PLAYER_ANIMS := {
	"idle": {"frames": 4, "fps": 5, "loop": true, "color": "#7fd1ff", "sx": 1.0, "sy": 1.0, "bob": 1.5},
	"run": {"frames": 8, "fps": 14, "loop": true, "color": "#7fd1ff", "sx": 1.02, "sy": 0.98, "bob": 3.0, "lean": 0.12, "events": {2: "footstep", 6: "footstep"}},
	"jump": {"frames": 2, "fps": 10, "loop": false, "color": "#9fe0ff", "sx": 0.82, "sy": 1.14},
	"fall": {"frames": 2, "fps": 8, "loop": true, "color": "#9fe0ff", "sx": 0.92, "sy": 1.06, "bob": 1.0},
	"wall_slide": {"frames": 2, "fps": 6, "loop": true, "color": "#6fb8e0", "sx": 0.9, "sy": 1.04, "lean": -0.1},
	"dash": {"frames": 3, "fps": 20, "loop": false, "color": "#ffffff", "sx": 1.45, "sy": 0.72, "lean": 0.25},
	"grapple": {"frames": 2, "fps": 10, "loop": true, "color": "#e8dcb8", "sx": 0.9, "sy": 1.1, "lean": 0.15, "arm": [-1.2, -1.4]},
	"attack_side": {"frames": 4, "fps": 18, "loop": false, "color": "#ffe08a", "sx": 1.12, "sy": 0.94, "lean": 0.18, "arm": [-1.6, 0.9], "events": {1: "swing"}},
	"attack_up": {"frames": 4, "fps": 18, "loop": false, "color": "#ffe08a", "sx": 0.88, "sy": 1.12, "arm": [-0.3, -2.8], "events": {1: "swing"}},
	"attack_down": {"frames": 4, "fps": 18, "loop": false, "color": "#ffe08a", "sx": 1.08, "sy": 0.9, "arm": [0.3, 2.8], "events": {1: "swing"}},
	"heal": {"frames": 4, "fps": 8, "loop": true, "color": "#8dffb0", "sx": 1.06, "sy": 0.9, "bob": 2.0},
	"cast": {"frames": 5, "fps": 12, "loop": false, "color": "#d6a8ff", "sx": 0.9, "sy": 1.15, "bob": 2.0},
	"hurt": {"frames": 2, "fps": 12, "loop": false, "color": "#ff6b6b", "sx": 1.1, "sy": 0.9, "lean": -0.2},
	"dying": {"frames": 6, "fps": 8, "loop": false, "color": "#ff4d5e", "sx": 1.35, "sy": 0.3, "lean": -0.35},
	"trance": {"frames": 6, "fps": 4, "loop": true, "color": "#c9f2ff", "sx": 0.95, "sy": 1.02, "bob": 2.0, "float": 14.0},
	# Meditation at an altar: kneel low (squashed), weapon away, a slow breath.
	"meditate": {"frames": 8, "fps": 5, "loop": true, "color": "#b9a8ff", "sx": 1.12, "sy": 0.78, "bob": 2.5},
	# Map quick view: standing, head bowed over the map held up in front.
	"map_read": {"frames": 6, "fps": 4, "loop": true, "color": "#e6d6a6", "sx": 1.02, "sy": 0.94, "bob": 1.0, "lean": 0.08, "arm": [-0.35, -0.5]},
}

const DUMMY_ANIMS := {
	"idle": {"frames": 2, "fps": 3, "loop": true, "color": "#c96b4a", "sx": 1.0, "sy": 1.0, "bob": 1.0},
	"move": {"frames": 4, "fps": 6, "loop": true, "color": "#c96b4a", "sx": 1.03, "sy": 0.97, "bob": 2.0},
	"hurt": {"frames": 2, "fps": 16, "loop": false, "color": "#ffffff", "sx": 1.15, "sy": 0.85},
	"dead": {"frames": 1, "fps": 1, "loop": false, "color": "#4a2f28", "sx": 1.3, "sy": 0.25},
	"spawn": {"frames": 7, "fps": 20, "loop": false, "color": "#ff9ae6", "sx": 0.7, "sy": 1.2, "fade": [0.1, 0.9]},
}

const FLYER_ANIMS := {
	"idle": {"frames": 4, "fps": 8, "loop": true, "color": "#b85c9e", "sx": 1.0, "sy": 1.0, "bob": 2.0},
	"move": {"frames": 4, "fps": 10, "loop": true, "color": "#b85c9e", "sx": 1.05, "sy": 0.95, "bob": 2.0},
	"hurt": {"frames": 2, "fps": 16, "loop": false, "color": "#ffffff", "sx": 1.2, "sy": 0.8},
	"dead": {"frames": 1, "fps": 1, "loop": false, "color": "#3d2336", "sx": 0.6, "sy": 0.6},
	"spawn": {"frames": 7, "fps": 20, "loop": false, "color": "#ff9ae6", "sx": 0.7, "sy": 1.2, "fade": [0.1, 0.9]},
}

const STRONG_ANIMS := {
	"idle": {"frames": 2, "fps": 3, "loop": true, "color": "#7d8aa6", "sx": 1.0, "sy": 1.0, "bob": 1.0},
	"move": {"frames": 4, "fps": 6, "loop": true, "color": "#7d8aa6", "sx": 1.03, "sy": 0.97, "bob": 2.0},
	"hurt": {"frames": 2, "fps": 16, "loop": false, "color": "#ffffff", "sx": 1.08, "sy": 0.92},
	"dead": {"frames": 1, "fps": 1, "loop": false, "color": "#2e3446", "sx": 1.3, "sy": 0.25},
	"spawn": {"frames": 7, "fps": 20, "loop": false, "color": "#ff9ae6", "sx": 0.7, "sy": 1.2, "fade": [0.1, 0.9]},
}

## Boss clips also animate the glowing eyes (telegraphs read clearly).
const BOSS_ANIMS := {
	"idle": {"frames": 4, "fps": 4, "loop": true, "color": "#4b4f78", "eyes": "#ff6b6b", "sx": 1.0, "sy": 1.0, "bob": 2.0},
	"walk": {"frames": 4, "fps": 8, "loop": true, "color": "#4b4f78", "eyes": "#ff6b6b", "sx": 1.02, "sy": 0.98, "bob": 3.0, "lean": 0.08},
	"telegraph": {"frames": 2, "fps": 8, "loop": true, "color": "#7a6fd1", "eyes": "#ffffff", "sx": 1.12, "sy": 0.88, "bob": 2.0},
	"charge": {"frames": 2, "fps": 12, "loop": true, "color": "#5b5f96", "eyes": "#ffd36b", "sx": 1.2, "sy": 0.86, "lean": 0.3},
	"leap": {"frames": 2, "fps": 8, "loop": false, "color": "#5b5f96", "eyes": "#ffd36b", "sx": 0.86, "sy": 1.16},
	"volley": {"frames": 3, "fps": 10, "loop": true, "color": "#5b5f96", "eyes": "#7cf3ff", "sx": 0.94, "sy": 1.08},
	"recover": {"frames": 2, "fps": 4, "loop": true, "color": "#3c3f60", "eyes": "#7a3f4a", "sx": 1.06, "sy": 0.92},
	"roar": {"frames": 7, "fps": 10, "loop": false, "color": "#8a4fd1", "eyes": "#ffffff", "sx": 1.15, "sy": 1.08, "bob": 3.0, "shake": 4.0},
	"dissolve": {"frames": 15, "fps": 10, "loop": false, "color": "#8a4fd1", "eyes": "#ffd36b", "sx": 1.1, "sy": 0.9, "fade": [1.0, 0.0]},
	"spawn": {"frames": 7, "fps": 20, "loop": false, "color": "#ff9ae6", "eyes": "#ffffff", "sx": 0.8, "sy": 1.1, "fade": [0.1, 0.9]},
	"hurt": {"frames": 2, "fps": 16, "loop": false, "color": "#ffffff", "eyes": "#ffffff", "sx": 1.05, "sy": 0.95},
	"dead": {"frames": 1, "fps": 1, "loop": false, "color": "#22243a", "eyes": "#22243a", "sx": 1.3, "sy": 0.3, "fade": [0.0, 0.0]},
}

## Visual effects: one scene per effect in effects/fx/ (see fx_player.gd).
## Placeholder parts: particle bursts ("amount" ...), rings ("ring": radius)
## and the spawn portal ("portal"). Angles in degrees (0 = right, 90 = down);
## spread is the half-angle (180 = all directions). White parts take the
## caller's tint (ultimates pass their energy-tier color).
const FX := {
	"hit_spark": [{"amount": 14, "color": "#fff3c4", "speed": 320.0, "life": 0.3}],
	"pogo_spark": [{"amount": 8, "color": "#bff6ff", "speed": 200.0, "angle": 90.0, "spread": 80.0, "gravity": 300.0}],
	"pogo_spike": [{"amount": 8, "color": "#ff9a9a", "speed": 200.0, "angle": 90.0, "spread": 80.0, "gravity": 300.0}],
	"player_hurt": [{"amount": 16, "color": "#ff6b6b", "speed": 300.0, "size": 5.0}],
	"hazard_poof": [{"amount": 18, "color": "#ff6b6b", "speed": 280.0, "size": 5.0}],
	"safe_return": [{"ring": 40.0, "color": "#bff6ff", "width": 4.0, "life": 0.4}],
	"jump_dust": [{"amount": 5, "color": "#9aa7c7", "speed": 90.0, "gravity": 100.0, "life": 0.25, "size": 3.0}],
	"double_jump": [{"ring": 26.0, "color": "#bff6ff", "width": 3.0, "life": 0.25}],
	"land_dust": [{"amount": 8, "color": "#9aa7c7", "speed": 140.0, "angle": -90.0, "spread": 90.0, "gravity": 400.0, "life": 0.3, "size": 3.0}],
	"dash_burst": [{"amount": 10, "color": "#d9f6ff", "speed": 200.0, "angle": 180.0, "spread": 23.0, "gravity": 0.0, "life": 0.25, "size": 3.0}],
	"dash_trail": [{"amount": 3, "color": "#a1e6ff", "speed": 10.0, "gravity": 0.0, "life": 0.18, "size": 6.0, "box": [11.0, 20.0]}],
	"heal_sparkle": [{"amount": 1, "color": "#8dffb0", "speed": 60.0, "angle": -90.0, "spread": 17.0, "gravity": -200.0, "life": 0.5, "size": 3.0}],
	"enemy_death": [{"amount": 24, "color": "#ffb36b", "speed": 380.0, "size": 5.0, "life": 0.5}],
	"coin_pickup": [{"amount": 6, "color": "#ffd36b", "speed": 140.0, "gravity": 200.0, "life": 0.3, "size": 3.0}],
	"coin_fizzle": [{"amount": 6, "color": "#9aa7c7", "speed": 90.0, "gravity": -60.0, "life": 0.35, "size": 3.0}],
	"checkpoint_light": [{"ring": 50.0, "color": "#ffb347", "width": 4.0, "life": 0.45}],
	"save_glow": [{"amount": 20, "color": "#8dffb0", "speed": 120.0, "angle": -90.0, "spread": 40.0, "gravity": -150.0, "life": 0.7, "size": 3.0}],
	"potion_pickup": [{"amount": 8, "color": "#ffffff", "speed": 80.0, "angle": -90.0, "spread": 60.0, "gravity": -80.0, "life": 0.35, "size": 3.0}], # Small puff, tinted per potion.
	"scroll_pickup": [{"amount": 8, "color": "#e9d9a6", "speed": 80.0, "angle": -90.0, "spread": 60.0, "gravity": -80.0, "life": 0.35, "size": 3.0}],
	"meditate_glow": [{"amount": 1, "color": "#b9a8ff", "speed": 40.0, "angle": -90.0, "spread": 40.0, "gravity": -120.0, "life": 0.6, "size": 3.0}],
	"trance_break": [{"ring": 34.0, "color": "#c9f2ff", "width": 3.0, "life": 0.3}],
	"player_death": [{"amount": 40, "color": "#ff6b6b", "speed": 400.0, "size": 5.0, "life": 0.45}],
	"spawn_portal": [{"portal": 34.0, "color": "#ff4dd2", "life": 0.35}],
	"boss_telegraph": [{"ring": 46.0, "color": "#ffffff", "width": 3.0, "life": 0.3}],
	"boss_phase": [{"ring": 140.0, "color": "#b06cff", "width": 8.0, "life": 0.6}],
	"boss_dissolve": [{"amount": 40, "color": "#b06cff", "speed": 80.0, "angle": -90.0, "spread": 35.0, "gravity": -260.0,
		"life": 0.7, "size": 4.0, "box": [30.0, 36.0], "continuous": 1.5}],
	"wall_hit": [{"amount": 8, "color": "#56649a", "speed": 220.0, "size": 4.0, "life": 0.4}],
	"wall_break": [{"amount": 40, "color": "#3a4370", "speed": 320.0, "size": 6.0, "life": 0.7}], # Debris only (no flash).
	"relic_pickup": [{"amount": 8, "color": "#ff9aae", "speed": 90.0, "gravity": 0.0, "life": 0.3, "size": 3.0}], # A small puff (no flare).
	"nova_burst": [{"amount": 40, "color": "#ffffff", "speed": 520.0, "size": 5.0, "gravity": 0.0, "life": 0.45}],
	"volley_muzzle": [{"amount": 3, "color": "#ffffff", "speed": 120.0, "gravity": 0.0, "life": 0.2, "size": 3.0}],
	"ascendant_ring": [{"ring": 120.0, "color": "#ffffff", "width": 8.0, "life": 0.5}],
	"ascendant_spark": [{"amount": 1, "color": "#ffffff", "speed": 90.0, "angle": -90.0, "spread": 15.0, "gravity": -250.0, "life": 0.45, "size": 3.0}],
	"grapple_latch": [{"amount": 6, "color": "#e8dcb8", "speed": 160.0, "gravity": 300.0, "life": 0.25, "size": 3.0}],
	"comet_impact": [{"ring": 100.0, "color": "#ffffff", "width": 6.0, "life": 0.3},
		{"amount": 22, "color": "#ffffff", "speed": 360.0, "gravity": 200.0, "life": 0.35, "size": 4.0}],
}

## No celebration sounds (GUIDELINES.md, Rule F): no fanfares or jingles.
## Placeholder sounds, written as .wav files to audio/sfx/<name>.wav and
## wired into audio/sfx.tscn (one AudioStreamPlayer per sound). Replace a
## sound by overwriting its .wav (same name) or by setting the node's Stream.
## Tone: [f0, f1, seconds, wave, volume, noise]; a list of tones plays in order.
const SOUNDS := {
	"hit": [[420, 180, 0.08, "square", 0.3, 0.3]],
	"pogo": [[300, 640, 0.09, "sine", 0.4, 0.0]],
	"hurt": [[220, 90, 0.18, "square", 0.35, 0.4]],
	"death": [[330, 55, 0.8, "saw", 0.4, 0.25]],
	"save": [[523, 523, 0.1, "sine", 0.35, 0.0], [784, 784, 0.22, "sine", 0.35, 0.0]],
	"spawn": [[180, 520, 0.3, "sine", 0.3, 0.2]],
	"break": [[180, 60, 0.35, "square", 0.45, 0.8]],
	"pickup": [[520, 640, 0.08, "sine", 0.25, 0.0]],
	"gate": [[90, 60, 0.22, "square", 0.3, 0.6]], # Mechanical clunk (arena gates).
	"boss_roar": [[170, 42, 1.5, "saw", 0.6, 0.55]],
	"ui_move": [[880, 880, 0.03, "sine", 0.12, 0.0]],
	"ui_confirm": [[660, 990, 0.07, "sine", 0.22, 0.0]],
	"grapple_fire": [[700, 1400, 0.06, "saw", 0.18, 0.2]], # Placeholder: a quick zip.
	"grapple_latch": [[260, 200, 0.07, "square", 0.25, 0.5]], # Placeholder: a dull clank.
}
const SFX_SCENE := "res://audio/sfx.tscn"
const SFX_DIR := "res://audio/sfx/"
const MIX_RATE := 22050

var force := false


func _initialize() -> void:
	force = "--force" in OS.get_cmdline_user_args()
	_build_input_map()
	_build_rig("res://player/player_rig.tscn", Vector2(22, 40), true)
	_build_rig("res://enemies/dummy_rig.tscn", Vector2(34, 44), false)
	_build_rig("res://enemies/flyer_rig.tscn", Vector2(36, 30), false)
	_build_rig("res://enemies/strong_rig.tscn", Vector2(40, 54), false)
	_build_boss_rig("res://enemies/boss_rig.tscn")
	_save_library("res://player/player_animations.tres", PLAYER_ANIMS, 40.0, true)
	_save_library("res://enemies/dummy_animations.tres", DUMMY_ANIMS, 44.0, false)
	_save_library("res://enemies/flyer_animations.tres", FLYER_ANIMS, 30.0, false)
	_save_library("res://enemies/strong_animations.tres", STRONG_ANIMS, 54.0, false)
	_save_library("res://enemies/boss_animations.tres", BOSS_ANIMS, 72.0, false)
	_save_checkpoint_library("res://world/objects/checkpoint_animations.tres")
	for fx_name in FX:
		_build_fx(fx_name, FX[fx_name])
	_build_sounds()

	if not FileAccess.file_exists(TILES_PNG) or force:
		_build_tile_png()
	var texture := load(TILES_PNG) as Texture2D
	if texture == null:
		print("tiles.png is not imported yet. Run: godot --headless --path . --import  then run this tool again.")
		quit(1)
		return
	_build_tileset(texture)
	var rooms := ROOMS.duplicate()
	rooms["bestiary"] = BESTIARY_ROOM # Defined below ROOMS (it is long).
	for room_id in rooms:
		_check_room_rules(room_id, rooms[room_id])
		_build_room(room_id, rooms[room_id])
	print("build_assets: done")
	quit()


# ---------- Visual effects (placeholders) ----------

func _build_fx(fx_name: String, parts: Array) -> void:
	var path := "res://effects/fx/%s.tscn" % fx_name
	if not _should_write(path):
		return
	var root := Node2D.new()
	root.name = fx_name.to_pascal_case()
	root.set_script(load("res://effects/fx/fx_player.gd"))
	var lifetime := 0.1
	var emit_time := 0.0
	var i := 0
	for part in parts:
		i += 1
		var node: Node2D
		var color := Color(part.color)
		if part.has("ring"):
			node = Node2D.new()
			node.set_script(load("res://effects/fx/placeholders/ring_placeholder.gd"))
			node.set("radius", part.ring)
			node.set("color", color)
			node.set("width", part.get("width", 4.0))
			node.set("life", part.get("life", 0.35))
			node.name = "Ring%d" % i
			lifetime = maxf(lifetime, part.get("life", 0.35) + 0.05)
		elif part.has("portal"):
			node = Node2D.new()
			node.set_script(load("res://effects/fx/placeholders/portal_placeholder.gd"))
			node.set("radius", part.portal)
			node.set("color", color)
			node.set("life", part.life)
			node.name = "Portal"
			lifetime = maxf(lifetime, part.life)
		else:
			var p := CPUParticles2D.new()
			p.name = "Particles%d" % i
			var life: float = part.get("life", 0.4)
			var continuous: float = part.get("continuous", 0.0)
			p.emitting = false
			p.amount = part.amount
			p.lifetime = life
			p.one_shot = continuous <= 0.0
			p.explosiveness = 1.0 if continuous <= 0.0 else 0.0
			p.local_coords = false
			p.direction = Vector2.from_angle(deg_to_rad(part.get("angle", 0.0)))
			p.spread = part.get("spread", 180.0)
			p.gravity = Vector2(0, part.get("gravity", 600.0))
			p.initial_velocity_min = part.get("speed", 220.0) * 0.35
			p.initial_velocity_max = part.get("speed", 220.0)
			var size: float = part.get("size", 4.0)
			p.scale_amount_min = size * 0.6
			p.scale_amount_max = size * 1.2
			p.color = color
			var ramp := Gradient.new()
			ramp.set_color(0, Color.WHITE)
			ramp.set_color(1, Color(1, 1, 1, 0))
			p.color_ramp = ramp
			if part.has("box"):
				p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
				p.emission_rect_extents = Vector2(part.box[0], part.box[1])
			node = p
			if continuous > 0.0:
				emit_time = continuous
			lifetime = maxf(lifetime, continuous + life + 0.05)
		if part.has("at"):
			node.position = Vector2(part.at[0], part.at[1])
		root.add_child(node)
		node.owner = root
	root.set("lifetime", lifetime)
	root.set("emit_time", emit_time)
	_save_scene(root, path)


# ---------- Sounds (placeholders) ----------

func _build_sounds() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SFX_DIR))
	for sound in SOUNDS:
		var path: String = SFX_DIR + sound + ".wav"
		if _should_write(path):
			var samples := PackedFloat32Array()
			for tone in SOUNDS[sound]:
				samples.append_array(_tone(tone[0], tone[1], tone[2], tone[3], tone[4], tone[5]))
			_check(_wav(samples).save_to_wav(path), path)
	if not _should_write(SFX_SCENE):
		return
	# Written as text so it does not need the .wav files imported first.
	var lines := ["[gd_scene load_steps=%d format=3]" % (SOUNDS.size() + 2), "",
		'[ext_resource type="Script" path="res://autoload/sfx.gd" id="script"]']
	var i := 0
	for sound in SOUNDS:
		i += 1
		lines.append('[ext_resource type="AudioStream" path="%s%s.wav" id="s%d"]' % [SFX_DIR, sound, i])
	lines.append_array(["", '[node name="Sfx" type="Node"]', 'script = ExtResource("script")'])
	i = 0
	for sound in SOUNDS:
		i += 1
		lines.append_array(["", '[node name="%s" type="AudioStreamPlayer" parent="."]' % sound,
			'stream = ExtResource("s%d")' % i, "max_polyphony = 4", 'bus = &"SFX"'])
	var file := FileAccess.open(SFX_SCENE, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	print("build_assets: wrote ", SFX_SCENE)


## One tone sliding from f0 to f1 Hz. wave: sine / square / saw; noise mixes
## in white noise (0..1). Short attack, smooth decay.
func _tone(f0: float, f1: float, duration: float, wave: String, volume: float, noise: float) -> PackedFloat32Array:
	var n := int(duration * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		phase += TAU * lerpf(f0, f1, t) / MIX_RATE
		var v := sin(phase)
		if wave == "square":
			v = signf(v)
		elif wave == "saw":
			v = fmod(phase / TAU, 1.0) * 2.0 - 1.0
		v = lerpf(v, randf_range(-1.0, 1.0), noise)
		var env := minf(1.0, float(i) / (0.008 * MIX_RATE)) * pow(1.0 - t, 1.6)
		out[i] = v * env * volume
	return out


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


func _should_write(path: String) -> bool:
	return force or not FileAccess.file_exists(path)


# ---------- Input map ----------

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _joy_button(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e


func _joy_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e


func _build_input_map() -> void:
	var actions := {
		# Rebindable actions (Settings.REBINDABLE): exactly one key and one
		# gamepad button each, no duplicates. No WASD or other hidden extra
		# keys: a key only triggers what the settings list shows for it.
		"move_left": [_key(KEY_LEFT), _joy_button(JOY_BUTTON_DPAD_LEFT), _joy_axis(JOY_AXIS_LEFT_X, -1.0)],
		"move_right": [_key(KEY_RIGHT), _joy_button(JOY_BUTTON_DPAD_RIGHT), _joy_axis(JOY_AXIS_LEFT_X, 1.0)],
		"move_up": [_key(KEY_UP), _joy_button(JOY_BUTTON_DPAD_UP), _joy_axis(JOY_AXIS_LEFT_Y, -1.0)],
		"move_down": [_key(KEY_DOWN), _joy_button(JOY_BUTTON_DPAD_DOWN), _joy_axis(JOY_AXIS_LEFT_Y, 1.0)],
		"jump": [_key(KEY_SPACE), _joy_button(JOY_BUTTON_A)],
		"attack": [_key(KEY_J), _joy_button(JOY_BUTTON_X)],
		"dash": [_key(KEY_K), _joy_button(JOY_BUTTON_RIGHT_SHOULDER)],
		"heal": [_key(KEY_L), _joy_button(JOY_BUTTON_LEFT_SHOULDER)],
		"grapple": [_key(KEY_H), _joy_button(JOY_BUTTON_LEFT_STICK)],
		# One Spell button; the held direction picks the spell (UltimateManager).
		"spell": [_key(KEY_U), _joy_button(JOY_BUTTON_Y)],
		"interact": [_key(KEY_E), _joy_button(JOY_BUTTON_B)],
		"inventory": [_key(KEY_I), _joy_button(JOY_BUTTON_BACK)],
		# Hold to read the map (quick view, MapReadState).
		"map": [_key(KEY_TAB), _joy_button(JOY_BUTTON_RIGHT_STICK)],
		"pause": [_key(KEY_ESCAPE), _joy_button(JOY_BUTTON_START)],
		# Fixed debug actions (Settings.RESERVED: their keys cannot be rebound to).
		"toggle_debug": [_key(KEY_F1), _key(KEY_QUOTELEFT)],
		"reset_room": [_key(KEY_R)],
		"debug_navigate": [_key(KEY_F2)],
		# Menu-only actions (inventory). Arrows/Enter/Space use Godot's ui_* actions.
		"menu_prev_tab": [_key(KEY_Q), _key(KEY_PAGEUP), _joy_button(JOY_BUTTON_LEFT_SHOULDER)],
		"menu_next_tab": [_key(KEY_E), _key(KEY_PAGEDOWN), _joy_button(JOY_BUTTON_RIGHT_SHOULDER)],
		"menu_clear": [_key(KEY_BACKSPACE), _key(KEY_DELETE), _joy_button(JOY_BUTTON_X)],
		# Built-in UI actions (menus only): arrows, Enter / Space, D-pad, stick.
		"ui_accept": [_key(KEY_ENTER), _key(KEY_KP_ENTER), _key(KEY_SPACE), _joy_button(JOY_BUTTON_A)],
		"ui_left": [_key(KEY_LEFT), _joy_button(JOY_BUTTON_DPAD_LEFT), _joy_axis(JOY_AXIS_LEFT_X, -1.0)],
		"ui_right": [_key(KEY_RIGHT), _joy_button(JOY_BUTTON_DPAD_RIGHT), _joy_axis(JOY_AXIS_LEFT_X, 1.0)],
		"ui_up": [_key(KEY_UP), _joy_button(JOY_BUTTON_DPAD_UP), _joy_axis(JOY_AXIS_LEFT_Y, -1.0)],
		"ui_down": [_key(KEY_DOWN), _joy_button(JOY_BUTTON_DPAD_DOWN), _joy_axis(JOY_AXIS_LEFT_Y, 1.0)],
	}
	for obsolete in ["ultimate", "cycle_ultimate", "ult_1", "ult_2", "ult_3", "ult_4", "ult_5", "ult_6", "ult_7", "ult_8"]:
		if ProjectSettings.has_setting("input/" + obsolete):
			ProjectSettings.set_setting("input/" + obsolete, null)
	for action in actions:
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.5, "events": actions[action]})
	ProjectSettings.save()


# ---------- Rigs (placeholder skeletons) ----------

## Rig hierarchy (animated by path from the character root):
##   Flip/Rig            squash/stretch (scale) and lean (skew)
##   Flip/Rig/Body       Polygon2D, color per state
##   Flip/Rig/Visor      facing indicator
##   Flip/Rig/Arm        pivot that swings for attacks (player only)
##   Flip/Rig/Arm/Blade
## Replace the polygons with Sprite2D / Skeleton2D art later and keep the node
## names, and the generated animations keep working.
func _build_rig(path: String, size: Vector2, with_arm: bool) -> void:
	if not _should_write(path):
		return
	var rig := Node2D.new()
	rig.name = "Rig"
	var body := Polygon2D.new()
	body.name = "Body"
	body.polygon = _rounded_rect(Rect2(-size.x / 2.0, -size.y, size.x, size.y), minf(8.0, size.x / 3.0))
	body.color = Color.WHITE
	_add(rig, body)
	var visor := Polygon2D.new()
	visor.name = "Visor"
	visor.polygon = _rect_poly(Rect2(size.x * 0.05, -size.y * 0.85, size.x * 0.4, size.y * 0.13))
	visor.color = Color(0.04, 0.05, 0.12, 0.9)
	_add(rig, visor)
	if with_arm:
		var arm := Node2D.new()
		arm.name = "Arm"
		arm.position = Vector2(0, -size.y * 0.55)
		_add(rig, arm)
		var blade := Polygon2D.new()
		blade.name = "Blade"
		blade.polygon = PackedVector2Array([Vector2(6, -2), Vector2(26, -3), Vector2(32, 0), Vector2(26, 3), Vector2(6, 2)])
		blade.color = Color("#e8f6ff")
		_add(rig, blade, arm)
	_save_scene(rig, path)


## Boss rig: broad body, crest, two arms and glowing eyes (all Polygon2D).
func _build_boss_rig(path: String) -> void:
	if not _should_write(path):
		return
	var rig := Node2D.new()
	rig.name = "Rig"
	var parts := [
		["ArmBack", PackedVector2Array([Vector2(-40, -56), Vector2(-28, -60), Vector2(-24, -14), Vector2(-38, -10)]), Color("#2c2f4d")],
		["Body", PackedVector2Array([Vector2(-30, 0), Vector2(30, 0), Vector2(34, -48), Vector2(22, -68), Vector2(-22, -68), Vector2(-34, -48)]), Color.WHITE],
		["Crest", PackedVector2Array([Vector2(-14, -66), Vector2(0, -88), Vector2(14, -66)]), Color("#2c2f4d")],
		["ArmFront", PackedVector2Array([Vector2(26, -58), Vector2(40, -54), Vector2(44, -12), Vector2(30, -10)]), Color("#363a5e")],
		["Mask", PackedVector2Array([Vector2(-4, -60), Vector2(26, -60), Vector2(26, -44), Vector2(-4, -44)]), Color(0.05, 0.05, 0.1, 0.95)],
		["Eyes", PackedVector2Array([Vector2(4, -56), Vector2(10, -56), Vector2(10, -50), Vector2(4, -50), Vector2(4, -53), Vector2(16, -53), Vector2(16, -56), Vector2(22, -56), Vector2(22, -50), Vector2(16, -50), Vector2(16, -53), Vector2(4, -53)]), Color("#ff6b6b")],
	]
	for part in parts:
		var poly := Polygon2D.new()
		poly.name = part[0]
		poly.polygon = part[1]
		poly.color = part[2]
		_add(rig, poly)
	_save_scene(rig, path)


func _add(owner_node: Node, child: Node, parent: Node = null) -> void:
	(parent if parent else owner_node).add_child(child)
	child.owner = owner_node


func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


func _rounded_rect(r: Rect2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(r.end.x - radius, r.position.y + radius), -PI / 2.0],
		[Vector2(r.end.x - radius, r.end.y - radius), 0.0],
		[Vector2(r.position.x + radius, r.end.y - radius), PI / 2.0],
		[Vector2(r.position.x + radius, r.position.y + radius), PI],
	]
	for c in corners:
		for i in 5:
			var a: float = c[1] + (PI / 2.0) * i / 4.0
			pts.append(c[0] + Vector2(cos(a), sin(a)) * radius)
	return pts


# ---------- Animation libraries ----------

func _save_library(path: String, defs: Dictionary, height: float, with_arm: bool) -> void:
	if not _should_write(path):
		return
	var lib := AnimationLibrary.new()
	for anim_name in defs:
		lib.add_animation(anim_name, _make_animation(defs[anim_name], height, with_arm))
	_check(ResourceSaver.save(lib, path), path)


func _value_track(anim: Animation, path: String, discrete := false) -> int:
	var t := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(t, path)
	if discrete:
		anim.value_track_set_update_mode(t, Animation.UPDATE_DISCRETE)
	return t


func _make_animation(def: Dictionary, height: float, with_arm: bool) -> Animation:
	var anim := Animation.new()
	var length := float(def.frames) / float(def.fps)
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR if def.loop else Animation.LOOP_NONE

	# Squash & stretch with optional bob.
	var base := Vector2(def.sx, def.sy)
	var t := _value_track(anim, "Flip/Rig:scale")
	anim.track_insert_key(t, 0.0, base)
	var bob: float = def.get("bob", 0.0)
	if bob > 0.0:
		var b := bob / height
		anim.track_insert_key(t, length * 0.5, base + Vector2(-b * 0.5, b))
		anim.track_insert_key(t, length, base)

	# Optional hover (e.g. the trance): the rig floats above the feet and bobs.
	t = _value_track(anim, "Flip/Rig:position")
	var lift: float = def.get("float", 0.0)
	var shake: float = def.get("shake", 0.0)
	anim.track_insert_key(t, 0.0, Vector2(0, -lift))
	if shake > 0.0: # Violent shudder (e.g. the boss scream).
		var steps := int(length * 30.0)
		for i in range(1, steps):
			var dx := shake if i % 2 == 0 else -shake
			anim.track_insert_key(t, length * i / steps, Vector2(dx, -lift + (shake * 0.5 if i % 3 == 0 else 0.0)))
		anim.track_insert_key(t, length, Vector2(0, -lift))
	elif lift > 0.0:
		anim.track_insert_key(t, length * 0.5, Vector2(0, -lift - 5.0))
		anim.track_insert_key(t, length, Vector2(0, -lift))

	# Rig opacity: spawn fade-in, dissolve fade-out (default fully opaque).
	t = _value_track(anim, "Flip/Rig:modulate")
	var fade: Array = def.get("fade", [1.0, 1.0])
	anim.track_insert_key(t, 0.0, Color(1, 1, 1, fade[0]))
	if fade[0] != fade[1]:
		anim.track_insert_key(t, length, Color(1, 1, 1, fade[1]))

	t = _value_track(anim, "Flip/Rig:skew")
	anim.track_insert_key(t, 0.0, -float(def.get("lean", 0.0)))

	t = _value_track(anim, "Flip/Rig/Body:color", true)
	anim.track_insert_key(t, 0.0, Color(def.color))
	if def.has("eyes"):
		t = _value_track(anim, "Flip/Rig/Eyes:color", true)
		anim.track_insert_key(t, 0.0, Color(def.eyes))

	if with_arm:
		var arm: Array = def.get("arm", [])
		t = _value_track(anim, "Flip/Rig/Arm:visible", true)
		anim.track_insert_key(t, 0.0, not arm.is_empty())
		t = _value_track(anim, "Flip/Rig/Arm:rotation")
		if arm.is_empty():
			anim.track_insert_key(t, 0.0, 0.6)
		else:
			anim.track_insert_key(t, 0.0, arm[0])
			anim.track_insert_key(t, length * 0.55, arm[1])

	# Frame events -> root node's _on_anim_event(name).
	var events: Dictionary = def.get("events", {})
	if not events.is_empty():
		t = anim.add_track(Animation.TYPE_METHOD)
		anim.track_set_path(t, ".")
		for frame in events:
			anim.track_insert_key(t, float(frame) / float(def.fps), {"method": "_on_anim_event", "args": [events[frame]]})
	return anim


## Checkpoint flame: "inactive" (dim ember), "activate" (flare), "active" (flicker loop).
func _save_checkpoint_library(path: String) -> void:
	if not _should_write(path):
		return
	var lib := AnimationLibrary.new()
	var specs := {
		"inactive": {"length": 0.1, "loop": false, "keys": [[0.0, Vector2(0.6, 0.5), Color("#737f99")]]},
		"activate": {"length": 0.45, "loop": false, "keys": [[0.0, Vector2(0.6, 0.5), Color.WHITE], [0.15, Vector2(1.8, 1.9), Color("#fff3c4")], [0.45, Vector2(1, 1), Color("#ffb347")]]},
		"active": {"length": 0.6, "loop": true, "keys": [[0.0, Vector2(1, 1), Color("#ffb347")], [0.3, Vector2(0.88, 1.18), Color("#ffd36b")], [0.6, Vector2(1, 1), Color("#ffb347")]]},
	}
	for anim_name in specs:
		var spec: Dictionary = specs[anim_name]
		var anim := Animation.new()
		anim.length = spec.length
		anim.loop_mode = Animation.LOOP_LINEAR if spec.loop else Animation.LOOP_NONE
		var scale_track := _value_track(anim, "Visual/Flame:scale")
		var color_track := _value_track(anim, "Visual/Flame:color")
		for key in spec.keys:
			anim.track_insert_key(scale_track, key[0], key[1])
			anim.track_insert_key(color_track, key[0], key[2])
		lib.add_animation(anim_name, anim)
	_check(ResourceSaver.save(lib, path), path)


# ---------- Tiles ----------

func _build_tile_png() -> void:
	var img := Image.create(TS * ATLAS_COLUMNS, TS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for mask in 16: # Solid variants: lit faces wherever the tile borders open space.
		var ox := mask * TS
		img.fill_rect(Rect2i(ox, 0, TS, TS), Color("#2a3150"))
		img.fill_rect(Rect2i(ox + 2, 2, TS - 4, TS - 4), Color("#323a5e"))
		if mask & EDGE_TOP:
			img.fill_rect(Rect2i(ox, 0, TS, 3), Color("#7f8fcc"))
		if mask & EDGE_BOTTOM:
			img.fill_rect(Rect2i(ox, TS - 2, TS, 2), Color("#56649a"))
		if mask & EDGE_LEFT:
			img.fill_rect(Rect2i(ox, 0, 2, TS), Color("#5d6ca6"))
		if mask & EDGE_RIGHT:
			img.fill_rect(Rect2i(ox + TS - 2, 0, 2, TS), Color("#5d6ca6"))
	# One-way plank.
	var px := ONE_WAY.x * TS
	img.fill_rect(Rect2i(px, 0, TS, 6), Color("#8a6a4a"))
	img.fill_rect(Rect2i(px, 0, TS, 2), Color("#c49a6c"))
	img.fill_rect(Rect2i(px + 4, 6, 3, 8), Color(0.54, 0.42, 0.29, 0.5))
	img.fill_rect(Rect2i(px + TS - 7, 6, 3, 8), Color(0.54, 0.42, 0.29, 0.5))
	# Spikes: four triangles in the lower 60% of the tile.
	var sx := SPIKES.x * TS
	var top := int(TS * 0.4)
	for s in 4:
		var x0 := sx + s * (TS / 4)
		var w := TS / 4
		for y in range(top, TS):
			var half := int(float(y - top) / float(TS - top) * w / 2.0)
			for x in range(x0 + w / 2 - half, x0 + w / 2 + half + 1):
				img.set_pixel(x, y, Color("#d0d6e8"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://world/tiles"))
	_check(img.save_png(TILES_PNG), TILES_PNG)


func _build_tileset(texture: Texture2D) -> void:
	if not _should_write(TILESET):
		return
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TS, TS)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1) # world
	ts.set_physics_layer_collision_mask(0, 0)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(1, 4) # one_way (layer 3)
	ts.set_physics_layer_collision_mask(1, 0)
	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(0, "one_way")
	ts.set_custom_data_layer_type(0, TYPE_BOOL)
	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(1, "hazard")
	ts.set_custom_data_layer_type(1, TYPE_BOOL)

	var src := TileSetAtlasSource.new()
	src.texture = texture
	src.texture_region_size = Vector2i(TS, TS)
	ts.add_source(src, 0)
	for column in ATLAS_COLUMNS:
		src.create_tile(Vector2i(column, 0))

	var h := TS / 2.0
	var full := PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
	for mask in 16:
		var d := src.get_tile_data(Vector2i(mask, 0), 0)
		d.add_collision_polygon(0)
		d.set_collision_polygon_points(0, 0, full)
	var plank := src.get_tile_data(ONE_WAY, 0)
	plank.add_collision_polygon(1)
	plank.set_collision_polygon_points(1, 0, PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, -h + 8), Vector2(-h, -h + 8)]))
	plank.set_collision_polygon_one_way(1, 0, true)
	plank.set_custom_data("one_way", true)
	src.get_tile_data(SPIKES, 0).set_custom_data("hazard", true)
	_check(ResourceSaver.save(ts, TILESET), TILESET)


func _build_room(room_id: String, def: Dictionary) -> void:
	var path: String = def.path
	if not _should_write(path):
		return
	var layout: Array = def.layout
	var root := Node2D.new()
	root.name = def.name
	root.set_script(load("res://world/room.gd"))
	root.set("room_id", room_id)

	var tiles := TileMapLayer.new()
	tiles.name = "Tiles"
	tiles.tile_set = load(TILESET)
	_add(root, tiles)

	var spawns := Node2D.new()
	spawns.name = "EnemySpawns"
	_add(root, spawns)

	var objects := Node2D.new()
	objects.name = "Objects"
	_add(root, objects)
	var counts := {}

	var ox: int = def.get("origin_x", 0) # Layout column 0 is at cell ox.
	if ox != 0:
		root.set("main_rect", Rect2(0.0, 0.0, ((layout[0] as String).length() + ox) * TS, layout.size() * TS))

	var arena_def: Dictionary = def.get("arena", {})
	var arena: Node2D = null
	var wave_nodes := []
	if not arena_def.is_empty():
		arena = _build_arena(root, objects, layout, arena_def, wave_nodes)

	var enemy_count := 0
	for y in layout.size():
		var row: String = layout[y]
		for x in row.length():
			var ch := row[x]
			var cell := Vector2i(x + ox, y)
			var feet := Vector2((x + ox) * TS + TS / 2.0, (y + 1) * TS)
			match ch:
				"#":
					tiles.set_cell(cell, 0, Vector2i(_edge_mask(layout, x, y), 0))
				"=":
					tiles.set_cell(cell, 0, ONE_WAY)
				"^":
					tiles.set_cell(cell, 0, SPIKES)
				"V", "<", ">": # The same spike tile, turned (Room.hazard_rect_for_cell reads the flags).
					tiles.set_cell(cell, 0, SPIKES, SPIKE_TURNS[ch])
				"P", "S":
					var marker := Marker2D.new()
					marker.name = "PlayerSpawn"
					marker.position = feet
					_add(root, marker)
					if ch == "S":
						_add_object(root, objects, counts, CHECKPOINT_SCENE, "Checkpoint", feet, {"is_start": true})
				"C":
					_add_object(root, objects, counts, CHECKPOINT_SCENE, "Checkpoint", feet, {})
				"$":
					_add_object(root, objects, counts, COIN_SCENE, "Coin", feet, {})
				"*": # A shard inside a hidden pocket: own names, so other shards keep theirs.
					_add_object(root, objects, counts, COIN_SCENE, "PocketCoin", feet, {})
				"+", "m", "b":
					var peg_props: Dictionary = def.get("movers", {}).get("%d,%d" % [x, y], {}) if ch == "m" else {}
					_add_object(root, objects, counts, PEG_SCENES[ch], "GrapplePeg", feet - Vector2(0, TS / 2.0), peg_props)
				"_", "~", "%": # One Platform per horizontal run; origin at its top-center.
					if x > 0 and row[x - 1] == ch:
						continue
					var run := 1
					while x + run < row.length() and row[x + run] == ch:
						run += 1
					var plat_props: Dictionary = def.get("movers", {}).get("%d,%d" % [x, y], {}).duplicate() if ch == "~" else {}
					plat_props["size"] = Vector2(run * TS, 12)
					_add_object(root, objects, counts, PLATFORM_SCENES[ch], "Platform",
						Vector2((x + ox) * TS + run * TS / 2.0, y * TS), plat_props)
				"L": # One Lava node per horizontal run; origin at its top-left.
					if x > 0 and row[x - 1] == "L":
						continue
					var lava_run := 1
					while x + lava_run < row.length() and row[x + lava_run] == "L":
						lava_run += 1
					_add_object(root, objects, counts, LAVA_SCENE, "Lava", Vector2((x + ox) * TS, y * TS),
						{"size": Vector2(lava_run * TS, TS)})
				"N":
					_add_object(root, objects, counts, NPC_SCENE, "Npc", feet, {"dialogue": load(LORE[ch])})
				"W", "K", "U", "T", "Q":
					_add_object(root, objects, counts, LORE_SCENE, "Lore", feet, {"dialogue": load(LORE[ch])})
				"D", "H":
					_add_object(root, objects, counts, DOOR_SCENE, "Door", feet, def.doors[ch])
				"O", "Y":
					var door_def: Dictionary = def.doors[ch].duplicate()
					var w: float = door_def.get("width", 1) * TS
					door_def.erase("width")
					door_def["trigger_size"] = Vector2(w, 24.0 if door_def.vertical == -1 else 40.0)
					var origin := Vector2((x + ox) * TS + w / 2.0, y * TS if door_def.vertical == -1 else (y + 1) * TS)
					_add_object(root, objects, counts, DOOR_SCENE, "Door", origin, door_def)
				"Z": # Rule C: a secret door is never locked by the arena.
					var secret_def: Dictionary = def.doors[ch].duplicate()
					secret_def["secret"] = true
					_add_object(root, objects, counts, DOOR_SCENE, "Door", feet, secret_def)
					_add_object(root, objects, counts, BREAKABLE_SCENE, "BreakableWall", feet, {"secret_id": def.secret_id})
				"R":
					_add_object(root, objects, counts, RELIC_SCENE, "Relic", feet, def.relic)
				"h", "e": # Potions: saved by id (WorldState.relics), so it names the room and cell.
					var kind := "health_potion" if ch == "h" else "mana_potion"
					_add_object(root, objects, counts, POTION_SCENES[ch], kind.to_pascal_case(), feet,
						{"relic_id": "%s_%s_%d_%d" % [room_id, kind, x, y]})
				"?":
					_add_object(root, objects, counts, SCROLL_SCENE, "SpellScroll", feet,
						{"spell_id": def.scrolls["%d,%d" % [x, y]]})
				"j", "d", "c", "g":
					_add_object(root, objects, counts, ABILITY_PICKUP_SCENE, "AbilityPickup", feet,
						{"ability": ABILITY_LETTERS[ch]})
				"A":
					_add_object(root, objects, counts, ALTAR_SCENE, "MeditationAltar", feet,
						{"slot_name": def.altars["%d,%d" % [x, y]]})
				"I": # Type 1: one HiddenPocketWall per vertical run, at its bottom cell.
					if y + 1 < layout.size() and x < (layout[y + 1] as String).length() and layout[y + 1][x] == "I":
						continue
					var run := 1
					while y - run >= 0 and layout[y - run][x] == "I":
						run += 1
					var hp: Dictionary = def.hidden_pocket.duplicate()
					hp["size"] = Vector2(TS, run * TS)
					hp["pocket_rect"] = _pocket_rect(layout, x, y - run + 1, y, hp.pass_dir, ox)
					_add_object(root, objects, counts, HIDDEN_POCKET_SCENE, "HiddenPocketWall", feet, hp)
				"X": # Type 2: an ordinary side door, disguised by a SecretDoorway.
					var sd_def: Dictionary = def.doors[ch].duplicate()
					var sd_side: String = sd_def.secret_doorway
					sd_def.erase("secret_doorway")
					_add_object(root, objects, counts, DOOR_SCENE, "Door", feet, sd_def)
					_add_object(root, objects, counts, SECRET_DOORWAY_SCENE, "SecretDoorway", feet,
						{"side": sd_side, "inward": sd_def.inward, "size": Vector2(TS, 3 * TS)})
				"!": # Any enemy kind, from the room's "spawns" entry (Bestiary).
					enemy_count += 1
					var any_kind: String = def.spawns["%d,%d" % [x, y]]
					var am := Marker2D.new()
					am.name = "%s%d" % [any_kind.to_pascal_case(), enemy_count]
					am.position = feet
					am.set_meta("kind", any_kind)
					am.set_meta("flying", any_kind in FLYING_KINDS)
					_add(root, am, spawns)
				"k":
					_add_object(root, objects, counts, SIGN_SCENE, "ChamberSign", feet, {"title": def.signs["%d,%d" % [x, y]]})
				"E", "F", "G":
					enemy_count += 1
					var kind: String = {"E": "weak", "F": "flyer", "G": "strong"}[ch]
					var m := Marker2D.new()
					m.name = "%s%d" % [kind.capitalize(), enemy_count]
					m.position = feet
					m.set_meta("kind", kind)
					m.set_meta("flying", ch == "F")
					_add(root, m, spawns)
				"w", "u", "v", "s", "B":
					if arena == null:
						continue
					for i in arena_def.waves.size():
						if (arena_def.waves[i] as Array).has(ch):
							var am := Marker2D.new()
							am.name = "%s%d" % [ARENA_KINDS[ch].capitalize(), wave_nodes[i].get_child_count() + 1]
							am.position = feet - arena.position
							am.set_meta("kind", ARENA_KINDS[ch])
							_add(root, am, wave_nodes[i])
	_save_scene(root, path)


## Checks Rules A and B on a layout (see GUIDELINES.md). A violation is an
## error, so a broken layout is noticed at build time, not in play.
func _check_room_rules(room_id: String, def: Dictionary) -> void:
	var layout: Array = def.layout
	# Lava is a floor hazard only: every 'L' cell sits on solid wall.
	for y in layout.size():
		var row: String = layout[y]
		for x in row.length():
			if row[x] == "L" and (y + 1 >= layout.size() or (layout[y + 1] as String)[x] != "#"):
				push_error("Lava rule violated in %s: 'L' at (%d, %d) is not on a solid floor" % [room_id, x, y])
	# Rule D: the outer edge is wall, or part of a transition (doors, gaps,
	# secret doorways, breakable-wall doorways). Never open void.
	for y in layout.size():
		var row: String = layout[y]
		for x in row.length():
			var edge := y == 0 or y == layout.size() - 1 or x == 0 or x == row.length() - 1
			if not edge:
				continue
			if not (row[x] in ["#", "O", "Y", ".", "D", "H", "Z", "z", "X", "x"]):
				push_error("Rule D violated in %s: '%s' on the outer edge at (%d, %d)" % [room_id, row[x], x, y])
			elif row[x] == "." and not _is_doorway_cell(layout, def, x, y):
				push_error("Rule D violated in %s: open edge cell at (%d, %d) is not part of a transition" % [room_id, x, y])
	for y in layout.size():
		var row: String = layout[y]
		for x in row.length():
			if not row[x] in GAP_LETTERS:
				continue
			var door: Dictionary = def.doors[row[x]]
			var width: int = door.get("width", 1)
			if door.vertical == -1: # Rule A: ground under every gap column, within 4 rows.
				for gx in range(x, x + width):
					var ground := false
					for gy in range(y + 1, mini(y + 6, layout.size())):
						if (layout[gy] as String)[gx] in ["#", "="]:
							ground = true
							break
					if not ground:
						push_error("Rule A violated in %s: no ground below ceiling gap column %d" % [room_id, gx])
			else: # Rule B: standable floor beside the floor gap on at least one side.
				var standable := false
				for side_x in [x - 1, x + width]:
					if side_x <= 0 or side_x >= row.length() - 1:
						continue
					var floor_ok := (layout[y - 1] as String)[side_x] == "#"
					var top := y - 1
					while top > 0 and (layout[top - 1] as String)[side_x] == "#":
						top -= 1
					var head_ok := top >= 2 and (layout[top - 1] as String)[side_x] != "#" and (layout[top - 2] as String)[side_x] != "#"
					standable = standable or (floor_ok and head_ok)
				if not standable:
					push_error("Rule B violated in %s: no standable floor beside the floor gap at column %d" % [room_id, x])


## Rule D helper: an open '.' cell on the outer edge is allowed only inside
## a transition gap - above a side door letter (3-tall gap) or beside a
## ceiling / floor gap letter 'O' (its "width" cells).
func _is_doorway_cell(layout: Array, def: Dictionary, x: int, y: int) -> bool:
	for dy in [1, 2]:
		if y + dy < layout.size() and (layout[y + dy] as String)[x] in ["D", "H", "Z", "X"]:
			return true
	var row: String = layout[y]
	var doors: Dictionary = def.get("doors", {})
	for letter in GAP_LETTERS:
		var o: Dictionary = doors.get(letter, {})
		for dx in range(1, int(o.get("width", 1))):
			if x - dx >= 0 and row[x - dx] == letter:
				return true
	return false


## Exposed-edge mask for a solid cell: an edge is exposed when the neighbour
## is open space. Cells outside the layout count as solid.
func _edge_mask(layout: Array, x: int, y: int) -> int:
	var mask := 0
	if not _is_solid_char(layout, x, y - 1):
		mask |= EDGE_TOP
	if not _is_solid_char(layout, x + 1, y):
		mask |= EDGE_RIGHT
	if not _is_solid_char(layout, x, y + 1):
		mask |= EDGE_BOTTOM
	if not _is_solid_char(layout, x - 1, y):
		mask |= EDGE_LEFT
	return mask


func _is_solid_char(layout: Array, x: int, y: int) -> bool:
	if y < 0 or y >= layout.size() or x < 0 or x >= (layout[y] as String).length():
		return true
	return layout[y][x] in ["#", "Z", "z", "I", "X", "x"] # Secret walls show no edge.


## Type 1 hidden pocket: the open cells reachable from the far side of the
## wall in column `wx` (rows top..bottom), as a global rect. Its contents are
## covered until the pocket is found.
func _pocket_rect(layout: Array, wx: int, top: int, bottom: int, pass_dir: int, ox: int) -> Rect2:
	var open := func(cx: int, cy: int) -> bool:
		return cy >= 0 and cy < layout.size() and cx >= 0 and cx < (layout[cy] as String).length() \
			and not (layout[cy][cx] in ["#", "I", "X", "x", "Z", "z", "^", "V", "<", ">"])
	var queue: Array[Vector2i] = []
	var seen := {}
	for cy in range(top, bottom + 1):
		if open.call(wx + pass_dir, cy):
			queue.append(Vector2i(wx + pass_dir, cy))
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	while not queue.is_empty() and seen.size() < 400:
		var c: Vector2i = queue.pop_back()
		if seen.has(c):
			continue
		seen[c] = true
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if not seen.has(n) and open.call(n.x, n.y):
				queue.append(n)
	if seen.size() >= 400:
		push_error("Hidden pocket at column %d is not closed: it leaks into the room" % wx)
	elif lo.x <= 0 or lo.y <= 0 or hi.y >= layout.size() - 1 or hi.x >= (layout[hi.y] as String).length() - 1:
		push_error("Rule D violated: the hidden pocket at column %d reaches the layout edge (open void)" % wx)
	if seen.is_empty():
		return Rect2()
	return Rect2((lo.x + ox) * TS, lo.y * TS, (hi.x - lo.x + 1) * TS, (hi.y - lo.y + 1) * TS)


## Arena node: trigger area across the given columns, a gate over the room's
## doorway, and one Node2D per wave holding the spawn markers.
func _build_arena(root: Node, objects: Node, layout: Array, def: Dictionary, wave_nodes: Array) -> Node2D:
	var arena := Node2D.new()
	arena.name = "Arena"
	arena.set_script(load("res://world/objects/arena_encounter.gd"))
	arena.set("arena_id", def.arena_id)
	var cols: Array = def.trigger_cols
	arena.set("trigger_rect", Rect2(cols[0] * TS, TS, (cols[1] - cols[0] + 1) * TS, (layout.size() - 3) * TS))
	var gates: Array[Rect2] = []
	for y in layout.size(): # Seal every doorway cell on the room border.
		var row: String = layout[y]
		for x in [0, row.length() - 1]:
			if not row[x] in ["#", "Z", "z"]: # The secret wall gets no gate (no tell).
				gates.append(Rect2(x * TS, y * TS, TS, TS))
	arena.set("gate_rects", gates)
	_add(root, arena, objects)
	var waves := Node2D.new()
	waves.name = "Waves"
	_add(root, waves, arena)
	for i in (def.waves as Array).size():
		var w := Node2D.new()
		w.name = "Wave%d" % (i + 1)
		_add(root, w, waves)
		wave_nodes.append(w)
	return arena


# ---------- Helpers ----------

func _add_object(root: Node, parent: Node, counts: Dictionary, scene_path: String, base_name: String, pos: Vector2, props: Dictionary) -> void:
	counts[base_name] = counts.get(base_name, 0) + 1
	var node: Node2D = load(scene_path).instantiate()
	node.name = "%s%d" % [base_name, counts[base_name]]
	node.position = pos
	for key in props:
		node.set(key, props[key])
	_add(root, node, parent)


func _save_scene(root: Node, path: String) -> void:
	var packed := PackedScene.new()
	_check(packed.pack(root), path)
	_check(ResourceSaver.save(packed, path), path)
	root.free()


func _check(err: Error, what: String) -> void:
	if err != OK:
		push_error("build_assets: failed on %s (%s)" % [what, error_string(err)])
	else:
		print("build_assets: wrote ", what)
