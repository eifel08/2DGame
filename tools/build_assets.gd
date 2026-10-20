extends SceneTree
## Generates the placeholder content of the project with Godot's own API, so
## every scene and resource is guaranteed valid:
##   - Input Map actions (keyboard + gamepad) in project.godot
##   - Tile atlas texture, TileSet (collision, one-way, hazard data)
##   - Test room scene (from the ASCII layout below)
##   - Player and enemy placeholder rigs ("skeletons") and their AnimationLibraries
##
## The generated files are already committed. You only need this tool to
## rebuild them, e.g. after editing ROOM_LAYOUT:
##   godot --headless --path . --script res://tools/build_assets.gd -- --force
## The first run on a fresh checkout creates tiles.png; run
##   godot --headless --path . --import
## (or open the editor once), then run this tool again.
## Without --force, existing files are left untouched.

const TS := 32

## '#' solid  '=' one-way  '^' spikes  'E' ground dummy  'F' flying dummy
## 'S' start checkpoint (+ player spawn)  'C' checkpoint  '$' shard (currency)
## 'N' guide NPC  'W' / 'K' / 'U' lore tablets (see LORE)
## Two spike pits (rows 21-22): touching them deals damage and respawns the
## player on the last safe ground. The flying dummy above the right pit is for pogo chains.
const ROOM_LAYOUT := [
	"################################################################",
	"#..............................................................#",
	"#..............................................................#",
	"#..............................................................#",
	"#..$..........................##...............................#",
	"#=====..................#####.##.......................$.......#",
	"#.....##......................##....................########...#",
	"#.....##......................##..........................##...#",
	"#.....##.....$................##..............$...........##...#",
	"#.....##...======.............##............======........##...#",
	"#.....##..................F...##..........................##...#",
	"#.....##................$.....##..........................##...#",
	"#.....##..............=====...##.....$....................##...#",
	"#.....##......................##...####...................##...#",
	"#.....##..........$...........##..........................##...#",
	"#.....##........=====.........##..........................##...#",
	"#.....##......................##..........................##...#",
	"#.....##....$.................##.................F........##...#",
	"#.....##..=====...........................K...............##...#",
	"#.....##................................####...................#",
	"#.......................................####...................#",
	"#..W......S....N...........U..$$..E....C####............E...C..#",
	"##################^^^^########################^^^^^^^###########",
	"################################################################",
]

## Dialogue per object letter.
const LORE := {
	"N": "res://dialogue/guide.tres",
	"W": "res://dialogue/lore_wall_jump.tres",
	"K": "res://dialogue/lore_spikes.tres",
	"U": "res://dialogue/lore_ultimates.tres",
}
const CHECKPOINT_SCENE := "res://world/objects/checkpoint.tscn"
const LORE_SCENE := "res://world/objects/lore_stone.tscn"
const NPC_SCENE := "res://world/objects/npc.tscn"
const COIN_SCENE := "res://world/objects/coin.tscn"

const TILES_PNG := "res://world/tiles/tiles.png"
const TILESET := "res://world/tiles/tileset.tres"
const ROOM_SCENE := "res://world/test_room.tscn"

# Atlas coordinates.
const SOLID_TOP := Vector2i(0, 0)
const SOLID := Vector2i(1, 0)
const ONE_WAY := Vector2i(2, 0)
const SPIKES := Vector2i(3, 0)

## Player clips: frames/fps give the length; sx/sy squash, bob, lean (skew),
## body color, and an optional arm sweep [from, to] for attacks.
const PLAYER_ANIMS := {
	"idle": {"frames": 4, "fps": 5, "loop": true, "color": "#7fd1ff", "sx": 1.0, "sy": 1.0, "bob": 1.5},
	"run": {"frames": 8, "fps": 14, "loop": true, "color": "#7fd1ff", "sx": 1.02, "sy": 0.98, "bob": 3.0, "lean": 0.12, "events": {2: "footstep", 6: "footstep"}},
	"jump": {"frames": 2, "fps": 10, "loop": false, "color": "#9fe0ff", "sx": 0.82, "sy": 1.14},
	"fall": {"frames": 2, "fps": 8, "loop": true, "color": "#9fe0ff", "sx": 0.92, "sy": 1.06, "bob": 1.0},
	"dash": {"frames": 3, "fps": 20, "loop": false, "color": "#ffffff", "sx": 1.45, "sy": 0.72, "lean": 0.25},
	"attack_side": {"frames": 4, "fps": 18, "loop": false, "color": "#ffe08a", "sx": 1.12, "sy": 0.94, "lean": 0.18, "arm": [-1.6, 0.9], "events": {1: "swing"}},
	"attack_up": {"frames": 4, "fps": 18, "loop": false, "color": "#ffe08a", "sx": 0.88, "sy": 1.12, "arm": [-0.3, -2.8], "events": {1: "swing"}},
	"attack_down": {"frames": 4, "fps": 18, "loop": false, "color": "#ffe08a", "sx": 1.08, "sy": 0.9, "arm": [0.3, 2.8], "events": {1: "swing"}},
	"heal": {"frames": 4, "fps": 8, "loop": true, "color": "#8dffb0", "sx": 1.06, "sy": 0.9, "bob": 2.0},
	"cast": {"frames": 5, "fps": 12, "loop": false, "color": "#d6a8ff", "sx": 0.9, "sy": 1.15, "bob": 2.0},
	"hurt": {"frames": 2, "fps": 12, "loop": false, "color": "#ff6b6b", "sx": 1.1, "sy": 0.9, "lean": -0.2},
}

const DUMMY_ANIMS := {
	"idle": {"frames": 2, "fps": 3, "loop": true, "color": "#c96b4a", "sx": 1.0, "sy": 1.0, "bob": 1.0},
	"move": {"frames": 4, "fps": 6, "loop": true, "color": "#c96b4a", "sx": 1.03, "sy": 0.97, "bob": 2.0},
	"hurt": {"frames": 2, "fps": 16, "loop": false, "color": "#ffffff", "sx": 1.15, "sy": 0.85},
	"dead": {"frames": 1, "fps": 1, "loop": false, "color": "#4a2f28", "sx": 1.3, "sy": 0.25},
}

const FLYER_ANIMS := {
	"idle": {"frames": 4, "fps": 8, "loop": true, "color": "#b85c9e", "sx": 1.0, "sy": 1.0, "bob": 2.0},
	"move": {"frames": 4, "fps": 10, "loop": true, "color": "#b85c9e", "sx": 1.05, "sy": 0.95, "bob": 2.0},
	"hurt": {"frames": 2, "fps": 16, "loop": false, "color": "#ffffff", "sx": 1.2, "sy": 0.8},
	"dead": {"frames": 1, "fps": 1, "loop": false, "color": "#3d2336", "sx": 0.6, "sy": 0.6},
}

var force := false


func _initialize() -> void:
	force = "--force" in OS.get_cmdline_user_args()
	_build_input_map()
	_build_rig("res://player/player_rig.tscn", Vector2(22, 40), true)
	_build_rig("res://enemies/dummy_rig.tscn", Vector2(34, 44), false)
	_build_rig("res://enemies/flyer_rig.tscn", Vector2(36, 30), false)
	_save_library("res://player/player_animations.tres", PLAYER_ANIMS, 40.0, true)
	_save_library("res://enemies/dummy_animations.tres", DUMMY_ANIMS, 44.0, false)
	_save_library("res://enemies/flyer_animations.tres", FLYER_ANIMS, 30.0, false)
	_save_checkpoint_library("res://world/objects/checkpoint_animations.tres")

	if not FileAccess.file_exists(TILES_PNG) or force:
		_build_tile_png()
	var texture := load(TILES_PNG) as Texture2D
	if texture == null:
		print("tiles.png is not imported yet. Run: godot --headless --path . --import  then run this tool again.")
		quit(1)
		return
	_build_tileset(texture)
	_build_room()
	print("build_assets: done")
	quit()


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
		"move_left": [_key(KEY_LEFT), _key(KEY_A), _joy_button(JOY_BUTTON_DPAD_LEFT), _joy_axis(JOY_AXIS_LEFT_X, -1.0)],
		"move_right": [_key(KEY_RIGHT), _key(KEY_D), _joy_button(JOY_BUTTON_DPAD_RIGHT), _joy_axis(JOY_AXIS_LEFT_X, 1.0)],
		"move_up": [_key(KEY_UP), _key(KEY_W), _joy_button(JOY_BUTTON_DPAD_UP), _joy_axis(JOY_AXIS_LEFT_Y, -1.0)],
		"move_down": [_key(KEY_DOWN), _key(KEY_S), _joy_button(JOY_BUTTON_DPAD_DOWN), _joy_axis(JOY_AXIS_LEFT_Y, 1.0)],
		"jump": [_key(KEY_SPACE), _key(KEY_Z), _joy_button(JOY_BUTTON_A)],
		"attack": [_key(KEY_J), _key(KEY_X), _joy_button(JOY_BUTTON_X)],
		"dash": [_key(KEY_K), _key(KEY_C), _key(KEY_SHIFT), _joy_button(JOY_BUTTON_RIGHT_SHOULDER)],
		"heal": [_key(KEY_L), _key(KEY_V), _joy_button(JOY_BUTTON_LEFT_SHOULDER)],
		"ult_1": [_key(KEY_1), _joy_button(JOY_BUTTON_Y)],
		"ult_2": [_key(KEY_2), _joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)],
		"ult_3": [_key(KEY_3), _joy_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)],
		"ult_4": [_key(KEY_4), _joy_button(JOY_BUTTON_RIGHT_STICK)],
		"interact": [_key(KEY_E), _key(KEY_F), _joy_button(JOY_BUTTON_B)],
		"inventory": [_key(KEY_I), _key(KEY_TAB), _key(KEY_ESCAPE), _joy_button(JOY_BUTTON_BACK)],
		"toggle_debug": [_key(KEY_F1), _key(KEY_QUOTELEFT), _joy_button(JOY_BUTTON_START)],
		"reset_room": [_key(KEY_R)],
	}
	for obsolete in ["ultimate", "cycle_ultimate"]:
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

	t = _value_track(anim, "Flip/Rig:skew")
	anim.track_insert_key(t, 0.0, -float(def.get("lean", 0.0)))

	t = _value_track(anim, "Flip/Rig/Body:color", true)
	anim.track_insert_key(t, 0.0, Color(def.color))

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
	var img := Image.create(TS * 4, TS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 2: # Solid (with and without a lit top edge).
		var ox := i * TS
		img.fill_rect(Rect2i(ox, 0, TS, TS), Color("#2a3150"))
		img.fill_rect(Rect2i(ox + 2, 2, TS - 4, TS - 4), Color("#323a5e"))
		if i == 0:
			img.fill_rect(Rect2i(ox, 0, TS, 3), Color("#6f7fb8"))
	# One-way plank.
	var px := TS * 2
	img.fill_rect(Rect2i(px, 0, TS, 6), Color("#8a6a4a"))
	img.fill_rect(Rect2i(px, 0, TS, 2), Color("#c49a6c"))
	img.fill_rect(Rect2i(px + 4, 6, 3, 8), Color(0.54, 0.42, 0.29, 0.5))
	img.fill_rect(Rect2i(px + TS - 7, 6, 3, 8), Color(0.54, 0.42, 0.29, 0.5))
	# Spikes: four triangles in the lower 60% of the tile.
	var sx := TS * 3
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
	for coords in [SOLID_TOP, SOLID, ONE_WAY, SPIKES]:
		src.create_tile(coords)

	var h := TS / 2.0
	var full := PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
	for coords in [SOLID_TOP, SOLID]:
		var d := src.get_tile_data(coords, 0)
		d.add_collision_polygon(0)
		d.set_collision_polygon_points(0, 0, full)
	var plank := src.get_tile_data(ONE_WAY, 0)
	plank.add_collision_polygon(1)
	plank.set_collision_polygon_points(1, 0, PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, -h + 8), Vector2(-h, -h + 8)]))
	plank.set_collision_polygon_one_way(1, 0, true)
	plank.set_custom_data("one_way", true)
	src.get_tile_data(SPIKES, 0).set_custom_data("hazard", true)
	_check(ResourceSaver.save(ts, TILESET), TILESET)


func _build_room() -> void:
	if not _should_write(ROOM_SCENE):
		return
	var root := Node2D.new()
	root.name = "TestRoom"
	root.set_script(load("res://world/room.gd"))

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

	var enemy_count := 0
	for y in ROOM_LAYOUT.size():
		var row: String = ROOM_LAYOUT[y]
		for x in row.length():
			var ch := row[x]
			var cell := Vector2i(x, y)
			var feet := Vector2(x * TS + TS / 2.0, (y + 1) * TS)
			match ch:
				"#":
					var above: String = ROOM_LAYOUT[y - 1][x] if y > 0 else "#"
					tiles.set_cell(cell, 0, SOLID if above == "#" else SOLID_TOP)
				"=":
					tiles.set_cell(cell, 0, ONE_WAY)
				"^":
					tiles.set_cell(cell, 0, SPIKES)
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
				"N":
					_add_object(root, objects, counts, NPC_SCENE, "Npc", feet, {"dialogue": load(LORE[ch])})
				"W", "K", "U":
					_add_object(root, objects, counts, LORE_SCENE, "Lore", feet, {"dialogue": load(LORE[ch])})
				"E", "F":
					enemy_count += 1
					var m := Marker2D.new()
					m.name = "%s%d" % ["Flyer" if ch == "F" else "Dummy", enemy_count]
					m.position = feet
					m.set_meta("flying", ch == "F")
					_add(root, m, spawns)
	_save_scene(root, ROOM_SCENE)


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
