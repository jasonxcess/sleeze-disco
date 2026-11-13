extends Control
# Light 2D boot menu. Draws on the first frame (no 3D, no big loads) so we
# can tell "renderer alive" from "arena hangs". D-pad up/down + X to pick a
# profile, then it hands over to Main.tscn (the arena, which loads in stages).

const ORDER = ["A", "B", "C", "D"]
var sel = 0
var labels = []
var started = false
var title : Label
var hint : Label

func _make_label(text, size, col, pos):
	var f = DynamicFont.new()
	f.font_data = load("res://assets/fonts/DejaVuSans-Bold.ttf")
	f.size = size
	var l = Label.new()
	l.add_font_override("font", f)
	l.add_color_override("font_color", col)
	l.text = text
	l.rect_position = pos
	add_child(l)
	return l

func _ready():
	G.blog("Boot._ready")
	var bg = ColorRect.new()
	bg.color = Color(0.02, 0, 0.05)
	bg.rect_size = Vector2(960, 544)
	add_child(bg)
	title = _make_label("SLEEZE DISCO 3D  v0.2 PSX", 30, Color(1, 0.3, 0.8), Vector2(40, 40))
	_make_label("Pick a render mode. Start with A.", 18, Color(0.7, 0.7, 0.85), Vector2(40, 90))
	for i in range(ORDER.size()):
		var k = ORDER[i]
		labels.append(_make_label("", 22, Color(1, 1, 1), Vector2(60, 150 + i * 56)))
	hint = _make_label("D-pad up/down + X to start", 18, Color(0.4, 1, 0.9), Vector2(40, 470))
	_make_label("log: " + G.log_path, 14, Color(0.5, 0.5, 0.6), Vector2(40, 504))
	_refresh()
	if G.cli_profile in G.PROFILES:
		_start(G.cli_profile)
	G.blog("Boot drawn")

func _refresh():
	for i in range(ORDER.size()):
		var k = ORDER[i]
		labels[i].text = ("> " if i == sel else "  ") + k + ")  " + G.PROFILES[k].label
		labels[i].add_color_override("font_color", Color(1, 0.85, 0.25) if i == sel else Color(0.85, 0.85, 0.95))

func _start(p):
	if started:
		return
	started = true
	hint.text = "loading " + p + " ..."
	G.apply_profile(p)
	# one frame so "loading" is visible before the arena scene swaps in
	yield(VisualServer, "frame_post_draw")
	get_tree().change_scene("res://scenes/Main.tscn")

func _input(e):
	if started or e.is_echo():
		return
	var up = false
	var down = false
	var ok = false
	if e is InputEventJoypadButton and e.pressed:
		up = e.button_index == JOY_DPAD_UP
		down = e.button_index == JOY_DPAD_DOWN
		ok = e.button_index == JOY_SONY_X
	elif e is InputEventKey and e.pressed:
		up = e.scancode == KEY_UP
		down = e.scancode == KEY_DOWN
		ok = e.scancode == KEY_ENTER or e.scancode == KEY_SPACE
	if up:
		sel = (sel + ORDER.size() - 1) % ORDER.size()
		_refresh()
	elif down:
		sel = (sel + 1) % ORDER.size()
		_refresh()
	elif ok:
		_start(ORDER[sel])
