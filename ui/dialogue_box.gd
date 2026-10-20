class_name DialogueBox
extends CanvasLayer
## Bottom-of-screen dialogue window with a typewriter effect.
## While it is open the game simulation is paused (see core/game.gd).
## Advance with Interact, Jump or Attack: the first press reveals the whole
## page, the next press turns the page; after the last page it closes.

const CHARS_PER_SECOND := 55.0
const ADVANCE_ACTIONS: Array[StringName] = [&"interact", &"jump", &"attack"]

var panel: PanelContainer
var speaker_label: Label
var text_label: Label
var hint_label: Label
var pages := PackedStringArray()
var page := 0
var _shown := 0.0


func _ready() -> void:
	_build()
	panel.visible = false


func is_open() -> bool:
	return panel.visible


func open(data: DialogueData) -> void:
	open_lines(data.speaker, data.pages)


func open_lines(speaker: String, lines: PackedStringArray) -> void:
	if lines.is_empty():
		return
	pages = lines
	page = 0
	speaker_label.text = speaker
	speaker_label.visible = speaker != ""
	_show_page()
	panel.visible = true
	Events.dialogue_opened.emit()


## Called by Game once per physics frame while open.
func step(delta: float, input: InputState) -> void:
	_shown += delta * CHARS_PER_SECOND
	var total := text_label.get_total_character_count()
	text_label.visible_characters = mini(int(_shown), total)
	hint_label.visible = text_label.visible_characters >= total
	for action in ADVANCE_ACTIONS:
		if input.was_pressed(action):
			advance()
			return


func advance() -> void:
	var total := text_label.get_total_character_count()
	if text_label.visible_characters < total:
		_shown = total # First press: reveal the full page.
		text_label.visible_characters = total
		return
	page += 1
	if page >= pages.size():
		close()
	else:
		_show_page()


func close() -> void:
	panel.visible = false
	Events.dialogue_closed.emit()


func _show_page() -> void:
	text_label.text = pages[page]
	_shown = 0.0
	text_label.visible_characters = 0
	hint_label.text = "▼ next" if page < pages.size() - 1 else "▼ close"


func _build() -> void:
	panel = PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -400.0
	panel.offset_right = 400.0
	panel.offset_top = -150.0
	panel.offset_bottom = -26.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.layout_direction = Control.LAYOUT_DIRECTION_LTR
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.08, 0.94)
	style.border_color = Color("#6f7fb8")
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	speaker_label = Label.new()
	speaker_label.text_direction = Control.TEXT_DIRECTION_LTR
	speaker_label.add_theme_color_override("font_color", Color("#ffd36b"))
	speaker_label.add_theme_font_size_override("font_size", 14)
	box.add_child(speaker_label)
	text_label = Label.new()
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Strict left-to-right text. The layout is computed for the whole page
	# up front, so the typewriter only reveals characters and lines never
	# shift or re-wrap while typing.
	text_label.text_direction = Control.TEXT_DIRECTION_LTR
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	text_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	text_label.custom_minimum_size = Vector2(0, 58)
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_label.add_theme_font_size_override("font_size", 14)
	box.add_child(text_label)
	hint_label = Label.new()
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	hint_label.add_theme_font_size_override("font_size", 11)
	box.add_child(hint_label)
