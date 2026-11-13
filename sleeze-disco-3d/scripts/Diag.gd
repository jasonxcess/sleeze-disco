extends CanvasLayer
# Always-on FPS + stage overlay. While loading it also shows a big stage name.

var small : Label
var big : Label
var font : DynamicFont
var _t = 0.0
var stage = ""
var done = false

func _ready():
	layer = 100
	pause_mode = Node.PAUSE_MODE_PROCESS
	font = DynamicFont.new()
	font.font_data = load("res://assets/fonts/DejaVuSans-Bold.ttf")
	font.size = 16
	small = Label.new()
	small.add_font_override("font", font)
	small.rect_position = Vector2(6, 4)
	small.add_color_override("font_color", Color(0.4, 1, 0.9))
	add_child(small)
	var bf = DynamicFont.new()
	bf.font_data = font.font_data
	bf.size = 28
	big = Label.new()
	big.add_font_override("font", bf)
	big.rect_position = Vector2(40, 220)
	big.add_color_override("font_color", Color(1, 0.3, 0.8))
	add_child(big)

func set_stage(s):
	stage = s
	if big:
		big.text = ("LOADING: " + s) if s != "" else ""
	_refresh()

func loaded():
	done = true
	big.text = ""

func _refresh():
	if small:
		small.text = "%d fps  [%s]  %s" % [Engine.get_frames_per_second(), G.profile, stage]

func _process(delta):
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		_refresh()
