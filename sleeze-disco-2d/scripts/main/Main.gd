extends Node2D
# SLEEZE DISCO — Main (Godot 3.5 / GDScript, 2D).
#
# Port of web v7.6 (PORT_SPEC.md §4, §7, §10, §13.2). Owns: screens
# (title / mode / intro / story / fight / end / hub / how-to / pause),
# fight orchestration (spawn queues, waves, endless, dance break),
# score / style / fans, shop + file saves (user://, no localStorage on
# Vita), the stage (gradient + club backdrops + StageLayer), the HUD,
# shake and banners. "Idol" is gone — never use that name.
#
# VITA DEVIATIONS (recorded, see README):
# - Endless keeps the track's native BPM all run (no BPM ramp): the
#   pre-rendered 60 s loops can't re-tempo without pitch artifacts.
#   Waves still ramp enemy speed (speedMul) and wave size.
# - No MP3 import / auto-BPM on Vita (web-only by design).

const PlayerScript := preload("res://scripts/player/Player.gd")
const EnemyScript := preload("res://scripts/enemies/Enemy.gd")
const FXScript := preload("res://scripts/fx/FXManager.gd")
const StageLayerScript := preload("res://scripts/fx/StageLayer.gd")
const BeatData := preload("res://scripts/util/BeatData.gd")
const SAVE_PATH := "user://sleeze_disco_save.json"

const WORLD_W := 960.0
const WORLD_H := 544.0
const PLAYER_SPAWN := Vector2(240, 410)

# Chapter data (PORT_SPEC.md §4.1, §10).
const BOSS_INFO := {
	1: {"name": "DR. CLIPBOARD", "title": "HEAD OF DOOR SCIENCE",
		"track": "myluva", "genre": "FUNK", "bpm": 100,
		"flavour": "Clipboards at the door. Lab coats under the jackets. He checks names. He checks vitals.",
		"sig": "ROPE SWEEP", "unlock": "DASH STRIKE",
		"queue": ["stan", "stan", "charger", "stan", "stan", "boss1"]},
	2: {"name": "SUBJECT SEVEN", "title": "ESCAPED TEST SUBJECT",
		"track": "dceased", "genre": "HOUSE", "bpm": 120,
		"flavour": "He got out of the tank. He did not get out of the club.",
		"sig": "TRIPLE TAP", "unlock": "SPINBACK KICK",
		"queue": ["charger", "stan", "bruiser", "charger", "bruiser", "boss2"]},
	3: {"name": "VEX", "title": "RUNS THE LAB",
		"track": "shittalkin", "genre": "DARK DISCO", "bpm": 140,
		"flavour": "She set the whole night up. Now she wants the last dance.",
		"sig": "SPOTLIGHT BLAST", "unlock": null,
		"queue": ["stan", "charger", "vex"]},
}
# VEX story exchange, verbatim (PORT_SPEC.md §9).
const STORY_LINES := [
	["VEX", "Jay. You actually came. Cute.", Color(1.0, 0.2, 0.8)],
	["JAY", "Vex. Whole club got clipboards and lab coats. What is this?", Color(1.0, 0.78, 0.24)],
	["VEX", "It's a lab, baby. You the next experiment. Them other dudes? They didn't make it past the door.", Color(1.0, 0.2, 0.8)],
	["JAY", "So all them dates was test runs. Aight. Bet.", Color(1.0, 0.78, 0.24)],
]
const SHOP := [
	{"id": "hp", "name": "+25 MAX HP", "cost": 50,
		"desc": "Max HP 100 + 25 x bought. Fights start at full HP."},
	{"id": "tokens", "name": "+1 TAKEDOWN TOKEN SLOT", "cost": 80,
		"desc": "Token cap 3 -> 4 -> 5. Earn rule unchanged (1 per 12 combo)."},
	{"id": "fever", "name": "FASTER FEVER GAIN", "cost": 60,
		"desc": "All Fever gains x1.5, rounded. One-time.", "once": true},
	{"id": "combo", "name": "NEW COMBO STRING", "cost": 100,
		"desc": "Punch, punch, kick — kick is a finisher-grade ender. One-time.", "once": true},
	{"id": "fit_gold", "name": "FIT — GOLD JACKET", "cost": 40,
		"desc": "Gold jacket tint. Buying never auto-equips.", "once": true},
	{"id": "fit_red", "name": "FIT — RED JACKET", "cost": 40,
		"desc": "Red jacket tint. Buying never auto-equips.", "once": true},
	{"id": "fit_cyan", "name": "FIT — CYAN JACKET", "cost": 40,
		"desc": "Cyan jacket tint. Buying never auto-equips.", "once": true},
]
const FIT_TINTS := {
	"none": Color(1, 1, 1),
	"gold": Color(1.0, 0.85, 0.55),
	"red": Color(1.0, 0.6, 0.6),
	"cyan": Color(0.6, 0.95, 1.0),
}
const CREDITS_TEXT := "Soundtrack: SleezeTeamJason — My Luva, DCeased, Shit Talkin, Big Screen, Fool Me Once (synth rebuilds of his own tracks, no licensed recordings). 3D credits (CC BY 4.0, via Sketchfab): \"PSX Graphics | Low Poly Woman\" by murilo.kleine • \"Enemy1\" by bumstrum • \"Raised dead\" by Pjotr Heinkens (CC BY-NC) • \"PSXprop - Male Character 02\" by WardsterSAW (Free Standard) • Motion: Adobe Mixamo • \"Night Dance Club Lowpoly\" by 00amza (CC BY 4.0)"

# Shop / unlock state the Player reads directly (same names as the web).
var shop_faster_fever := false
var shop_combo := false
var unlock_dash_strike := false
var unlock_spin_kick := false

# Persistent state (single JSON file, user://).
var fans := 0
var shop_hp := 0
var shop_tokens := 0
var fits_owned := {"gold": false, "red": false, "cyan": false}
var fit_equipped := "none"
var high_score := 0
var cal_ms := 0

# Run state.
var player = null
var fx = null
var world: Node2D = null
var enemies_root: Node2D = null
var stage_layer = null
var bg_lights: Sprite = null
var screen := "title"
var hub_origin := "title"
var mode := "story"
var chapter := 1
var track_key := "myluva"
var wave := 1
var speed_mul := 1.0
var spawn_queue := []
var spawn_timer := 0.0
var dance_break_t := 0.0
var score := 0
var _shake := 0.0
var _banner_t := 0.0
var _fight_over := false
var _fight_won := false
var _cal_taps := []
var _cal_active := false
var _last_fans_earned := 0
var _last_unlock := ""

# Auto-test (headless/editor smoke only — gated on the --auto-test CLI arg).
# Drives chapter 1's fight with scripted movement + attacks, prints status
# every 5 s, saves screenshots, then quits. Normal runs never touch it.
var _at_active := false
var _at_started := false
var _at_t := 0.0
var _at_dur := 45.0
var _at_next_atk := 0.0
var _at_next_status := 0.0
var _at_shot := false
var _at_beat_stall_warned := false

# UI refs.
var _screens := {}
var _screen_boxes := {}  # screen name -> VBoxContainer (runtime-created nodes
# get auto names like @@3, so get_node("CenterContainer/VBoxContainer")
# can never find them — keep the reference directly)
var _hud := {}
var _hud_root: Control = null
var _ui_layer: CanvasLayer = null
var _hub_shop_box: VBoxContainer = null
var _hub_balance: Label = null
var _end_tag: Label = null
var _end_title: Label = null
var _end_results: Label = null
var _end_unlock: Label = null
var _end_next_btn: Button = null
var _intro_tag: Label = null
var _intro_name: Label = null
var _intro_title: Label = null
var _intro_track: Label = null
var _intro_flavour: Label = null
var _intro_sig: Label = null
var _howto_moves: Label = null
var _cal_value: Label = null
var _cal_status: Label = null
var _cal_slider: HSlider = null
var _font_data = null  # DynamicFontData (DejaVuSans-Bold), loaded once
var _fonts := {}  # size -> DynamicFont

# Godot 3.5 has no add_font_size_override (that's Godot 4): font size comes
# from a DynamicFont resource. One DynamicFont per size, cached.
func _font(size: int) -> DynamicFont:
	if _fonts.has(size):
		return _fonts[size]
	if _font_data == null:
		_font_data = load("res://assets/fonts/DejaVuSans-Bold.ttf")
	var f := DynamicFont.new()
	f.font_data = _font_data
	f.size = size
	_fonts[size] = f
	return f

# Godot 3.5 has no Control.PRESET_FULL_RECT constant: a full-rect Control
# is anchor_right = anchor_bottom = 1 with zero offsets.
func _full_rect(c: Control) -> void:
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0

func _ready() -> void:
	randomize()
	_setup_input()
	_load_save()
	RhythmManager.calibration_ms = float(cal_ms)
	_build_world()
	_build_ui()
	_build_hud()
	show_screen("title")
	# Auto-test: --auto-test [--auto-test-secs=N]. No effect otherwise.
	var _at_args := OS.get_cmdline_args()
	if "--auto-test" in _at_args:
		_at_active = true
		for a in _at_args:
			if a.begins_with("--auto-test-secs="):
				_at_dur = float(a.replace("--auto-test-secs=", ""))
		print("AUTOTEST enabled, dur=", _at_dur, "s")

# --- input -----------------------------------------------------------------------
# Runtime InputMap (the v1 project.godot only defined ps_vita_* + move_* +
# pause). Joypad indices follow the v1 project's comment for this fork:
# 0 Cross, 1 Circle, 2 Square, 3 Triangle, 4 L1, 5 R1, 6 Select, 7 Start;
# D-pad 12-15 per the standard Godot layout. If Start/Select don't
# respond on the Vita, the fork's indices differ — fix here, one place.

func _add_action_events(action: String, joy_buttons: Array, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for b in joy_buttons:
		var ev := InputEventJoypadButton.new()
		ev.button_index = int(b)
		InputMap.action_add_event(action, ev)
	for k in keys:
		var kev := InputEventKey.new()
		kev.scancode = int(k)
		InputMap.action_add_event(action, kev)

func _setup_input() -> void:
	_add_action_events("punch", [2], [KEY_J])
	_add_action_events("kick", [3], [KEY_K])
	_add_action_events("throw", [1], [KEY_L])
	_add_action_events("dodge", [0], [KEY_SPACE])
	_add_action_events("parry", [4], [KEY_S])
	_add_action_events("finisher", [5], [KEY_E])
	_add_action_events("dance", [6], [KEY_F])
	# D-pad on the move actions (left stick is already in project.godot).
	_add_action_events("move_left", [14], [])
	_add_action_events("move_right", [15], [])
	_add_action_events("move_up", [12], [])
	_add_action_events("move_down", [13], [])
	# Menu navigation on the pad: Cross = accept, Circle = cancel.
	_add_action_events("ui_accept", [0], [])
	_add_action_events("ui_cancel", [1], [])
	_add_action_events("ui_up", [12], [])
	_add_action_events("ui_down", [13], [])
	_add_action_events("ui_left", [14], [])
	_add_action_events("ui_right", [15], [])

# --- saves -------------------------------------------------------------------------

func _load_save() -> void:
	var f := File.new()
	if not f.file_exists(SAVE_PATH):
		return
	if f.open(SAVE_PATH, File.READ) != OK:
		return
	var data = parse_json(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return
	fans = int(data.get("fans", 0))
	shop_hp = int(data.get("shop_hp", 0))
	shop_tokens = int(data.get("shop_tokens", 0))
	shop_faster_fever = bool(data.get("fever", false))
	shop_combo = bool(data.get("combo", false))
	var fits: Dictionary = data.get("fits", {})
	for k in fits_owned.keys():
		fits_owned[k] = bool(fits.get(k, false))
	fit_equipped = String(data.get("fit", "none"))
	unlock_dash_strike = bool(data.get("dash", false))
	unlock_spin_kick = bool(data.get("spinKick", false))
	high_score = int(data.get("high", 0))
	cal_ms = int(data.get("calMs", 0))

func _save() -> void:
	var data := {
		"fans": fans, "shop_hp": shop_hp, "shop_tokens": shop_tokens,
		"fever": shop_faster_fever, "combo": shop_combo,
		"fits": fits_owned, "fit": fit_equipped,
		"dash": unlock_dash_strike, "spinKick": unlock_spin_kick,
		"high": high_score, "calMs": cal_ms,
	}
	var f := File.new()
	if f.open(SAVE_PATH, File.WRITE) == OK:
		f.store_string(to_json(data))
		f.close()

# --- Main-facing helpers the Player / Enemy call -------------------------------------

func token_cap() -> int:
	return int(min(5, 3 + shop_tokens))

func max_hp_for() -> int:
	return 100 + 25 * shop_hp

func gain_score(n: int) -> void:
	if player == null:
		return
	score += int(round(float(n) * _rank_mult()))

func _rank_mult() -> float:
	if player == null:
		return 1.0
	match player.style_rank():
		"C":
			return 1.1
		"B":
			return 1.2
		"A":
			return 1.3
		"S":
			return 1.4
		"SLEEZE":
			return 1.5
	return 1.0

func banner(text: String, dur: float) -> void:
	var lab: Label = _hud["banner"]
	lab.text = text
	lab.visible = true
	_banner_t = dur

func add_float(text: String, pos: Vector2, col: Color) -> void:
	if fx != null:
		fx.add_float(text, pos, col)

func add_shake(n: int) -> void:
	_shake = max(_shake, float(n))

func add_ring(pos: Vector2, max_r: float, dur: float, dmg: int, owner) -> void:
	if fx != null:
		fx.add_ring(pos, max_r, dur, dmg, owner)

func pulse() -> float:
	if not RhythmManager.playing:
		return 0.0
	var ph := RhythmManager.beat_phase01()
	return 1.0 - min(ph, 1.0 - ph)

func is_rushing() -> bool:
	return player != null and player.rush_beats_left > 0

# --- world ---------------------------------------------------------------------------

func _build_world() -> void:
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	var far_tex = load("res://assets/backgrounds/bg_club_far.png")
	if far_tex != null:
		var far := Sprite.new()
		far.texture = far_tex
		far.position = Vector2(WORLD_W / 2.0, WORLD_H / 2.0)
		world.add_child(far)
	var lights_tex = load("res://assets/backgrounds/bg_club_lights.png")
	if lights_tex != null:
		bg_lights = Sprite.new()
		bg_lights.texture = lights_tex
		bg_lights.position = Vector2(WORLD_W / 2.0, WORLD_H / 2.0)
		bg_lights.modulate.a = 0.75
		world.add_child(bg_lights)
	stage_layer = StageLayerScript.new()
	stage_layer.setup(self)
	world.add_child(stage_layer)
	var fighters := YSort.new()
	fighters.name = "Fighters"
	world.add_child(fighters)
	enemies_root = fighters
	player = PlayerScript.new()
	fighters.add_child(player)
	player.setup(self, PLAYER_SPAWN, max_hp_for())
	player.fit_tint = FIT_TINTS.get(fit_equipped, Color(1, 1, 1))
	player.connect("player_died", self, "_on_player_died")
	player.connect("judgement_popup", self, "_on_judgement_popup")
	fx = FXScript.new()
	fx.setup(self)
	world.add_child(fx)

# --- UI construction -------------------------------------------------------------------

func _mk_label(text: String, size: int, color: Color, align: int = Label.ALIGN_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_font_override("font", _font(size))
	l.add_color_override("font_color", color)
	l.align = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _mk_button(text: String, size: int = 20) -> Button:
	var b := Button.new()
	b.text = text
	b.add_font_override("font", _font(size))
	b.rect_min_size = Vector2(460, 46)
	return b

func _mk_screen(name: String) -> VBoxContainer:
	var root := Control.new()
	root.name = name
	_full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.72)
	_full_rect(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var center := CenterContainer.new()
	_full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var box := VBoxContainer.new()
	box.add_constant_override("separation", 10)
	box.alignment = 1
	center.add_child(box)
	root.visible = false
	_ui_layer.add_child(root)
	_screens[name] = root
	_screen_boxes[name] = box
	return box

func _screen_first_button(box: VBoxContainer) -> void:
	for c in box.get_children():
		if c is Button:
			(c as Button).call_deferred("grab_focus")
			return

func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UI"
	add_child(_ui_layer)
	# --- title ---
	var box := _mk_screen("title")
	box.add_child(_mk_label("Harmony Corp Took The Stage", 18, Color(1.0, 0.78, 0.24), Label.ALIGN_CENTER))
	box.add_child(_mk_label("SLEEZE DISCO", 48, Color(1, 1, 1), Label.ALIGN_CENTER))
	var desc := _mk_label("Strike, dodge, and parry on the beat. PERFECT (±65ms) deals +50% damage and builds FEVER — fill it for FEVER RUSH. Off-beat swings snap to the next beat and still land — only getting hit breaks your combo. Dance [F] builds Fever too; every 12 combo earns a ★, and [E] spends one on a finisher.", 16, Color(1, 1, 1), Label.ALIGN_CENTER)
	desc.autowrap = true
	desc.rect_min_size = Vector2(720, 0)
	box.add_child(desc)
	var b_enter := _mk_button("▶ ENTER THE CLUB")
	b_enter.connect("pressed", self, "_on_enter_club")
	box.add_child(b_enter)
	var b_hub := _mk_button("GREEN ROOM")
	b_hub.connect("pressed", self, "_on_green_room")
	box.add_child(b_hub)
	var b_how := _mk_button("CONTROLS")
	b_how.connect("pressed", self, "_on_controls")
	box.add_child(b_how)
	var cal_row := HBoxContainer.new()
	cal_row.add_constant_override("separation", 10)
	cal_row.alignment = 1
	cal_row.add_child(_mk_label("AUDIO DELAY (ms)", 16, Color(1, 1, 1)))
	_cal_slider = HSlider.new()
	_cal_slider.min_value = -150
	_cal_slider.max_value = 150
	_cal_slider.step = 5
	_cal_slider.value = cal_ms
	_cal_slider.rect_min_size = Vector2(300, 24)
	_cal_slider.connect("value_changed", self, "_on_cal_slider")
	cal_row.add_child(_cal_slider)
	_cal_value = _mk_label(_cal_text(), 16, Color(1.0, 0.78, 0.24))
	cal_row.add_child(_cal_value)
	box.add_child(cal_row)
	box.add_child(_mk_label("PHONE AUDIO RUNS LATE — NUDGE IT UNTIL PERFECT LANDS ON THE BEAT", 13, Color(0.55, 0.58, 0.65), Label.ALIGN_CENTER))
	var b_tap := _mk_button("♪ TAP ALONG")
	b_tap.connect("pressed", self, "_on_tap_along")
	box.add_child(b_tap)
	_cal_status = _mk_label("TAP 8 TIMES ON THE CLICK TO TUNE THE DELAY", 13, Color(0.55, 0.58, 0.65), Label.ALIGN_CENTER)
	box.add_child(_cal_status)
	# --- mode ---
	box = _mk_screen("mode")
	box.add_child(_mk_label("Select Track", 18, Color(1.0, 0.78, 0.24), Label.ALIGN_CENTER))
	box.add_child(_mk_label("PICK YOUR NIGHT", 36, Color(1, 1, 1), Label.ALIGN_CENTER))
	box.add_child(_mk_label("STORY CHAPTERS RUN ON SLEEZE'S OWN TRACKS — SYNTH REBUILDS, STREAMER-SAFE.", 14, Color(1, 1, 1), Label.ALIGN_CENTER))
	for ch in [1, 2, 3]:
		var info: Dictionary = BOSS_INFO[ch]
		var b := _mk_button("CH.%d %s — %s · %s %d BPM" % [ch, info["name"], String(BeatData.TRACKS[info["track"]]["name"]), info["genre"], int(info["bpm"])])
		b.connect("pressed", self, "_on_mode_story", [ch])
		box.add_child(b)
	for key in ["myluva", "bigscreen", "dceased", "foolmeonce", "shittalkin"]:
		var t: Dictionary = BeatData.TRACKS[key]
		var b2 := _mk_button("∞ %s — %s %d BPM" % [String(t["name"]), String(t["genre"]), int(t["bpm"])])
		b2.connect("pressed", self, "_on_mode_endless", [key])
		box.add_child(b2)
	var imp := _mk_label("♪ IMPORT MP3 / WAV — ON THE VITA, ENDLESS USES THE PRESET TRACK BPMS ABOVE. (MP3 IMPORT IS WEB-ONLY.)", 13, Color(0.55, 0.58, 0.65), Label.ALIGN_CENTER)
	imp.autowrap = true
	imp.rect_min_size = Vector2(700, 0)
	box.add_child(imp)
	var b_back := _mk_button("← BACK")
	b_back.connect("pressed", self, "_on_back_to_title")
	box.add_child(b_back)
	# --- intro ---
	box = _mk_screen("intro")
	_intro_tag = _mk_label("", 18, Color(1.0, 0.78, 0.24), Label.ALIGN_CENTER)
	box.add_child(_intro_tag)
	_intro_name = _mk_label("", 36, Color(1, 1, 1), Label.ALIGN_CENTER)
	box.add_child(_intro_name)
	_intro_title = _mk_label("", 20, Color(0.0, 0.94, 1.0), Label.ALIGN_CENTER)
	box.add_child(_intro_title)
	_intro_track = _mk_label("", 16, Color(1, 1, 1), Label.ALIGN_CENTER)
	box.add_child(_intro_track)
	_intro_flavour = _mk_label("", 16, Color(1, 1, 1), Label.ALIGN_CENTER)
	_intro_flavour.autowrap = true
	_intro_flavour.rect_min_size = Vector2(700, 0)
	box.add_child(_intro_flavour)
	_intro_sig = _mk_label("", 16, Color(1.0, 0.2, 0.8), Label.ALIGN_CENTER)
	box.add_child(_intro_sig)
	var b_fight := _mk_button("▶ FIGHT")
	b_fight.connect("pressed", self, "_on_intro_fight")
	box.add_child(b_fight)
	var b_iback := _mk_button("BACK")
	b_iback.connect("pressed", self, "_on_back_to_mode")
	box.add_child(b_iback)
	# --- story ---
	box = _mk_screen("story")
	box.add_child(_mk_label("CH.3 — VEX", 18, Color(1.0, 0.2, 0.8), Label.ALIGN_CENTER))
	box.add_child(_mk_label("LAST DANCE", 36, Color(1, 1, 1), Label.ALIGN_CENTER))
	for line in STORY_LINES:
		var sl := _mk_label("%s: \"%s\"" % [line[0], line[1]], 17, line[2], Label.ALIGN_CENTER)
		sl.autowrap = true
		sl.rect_min_size = Vector2(700, 0)
		box.add_child(sl)
	var b_sfight := _mk_button("▶ FIGHT")
	b_sfight.connect("pressed", self, "_on_story_fight")
	box.add_child(b_sfight)
	# --- end ---
	box = _mk_screen("end")
	var end_tag := _mk_label("", 18, Color(1.0, 0.78, 0.24), Label.ALIGN_CENTER)
	_end_tag = end_tag
	box.add_child(end_tag)
	var end_title := _mk_label("", 36, Color(1, 1, 1), Label.ALIGN_CENTER)
	_end_title = end_title
	box.add_child(end_title)
	_end_results = _mk_label("", 18, Color(1, 1, 1), Label.ALIGN_CENTER)
	_end_results.autowrap = true
	_end_results.rect_min_size = Vector2(700, 0)
	box.add_child(_end_results)
	_end_unlock = _mk_label("", 20, Color(1.0, 0.78, 0.24), Label.ALIGN_CENTER)
	box.add_child(_end_unlock)
	_end_next_btn = _mk_button("NEXT CHAPTER →")
	_end_next_btn.connect("pressed", self, "_on_next_chapter")
	box.add_child(_end_next_btn)
	var b_retry := _mk_button("↻ PLAY AGAIN")
	b_retry.connect("pressed", self, "_on_retry")
	box.add_child(b_retry)
	var b_ehub := _mk_button("HUB")
	b_ehub.connect("pressed", self, "_on_end_hub")
	box.add_child(b_ehub)
	var b_etitle := _mk_button("TITLE")
	b_etitle.connect("pressed", self, "_on_back_to_title")
	box.add_child(b_etitle)
	# --- hub ---
	box = _mk_screen("hub")
	box.add_child(_mk_label("Green Room — Lab Break Room", 18, Color(1.0, 0.78, 0.24), Label.ALIGN_CENTER))
	box.add_child(_mk_label("THE HUB", 36, Color(1, 1, 1), Label.ALIGN_CENTER))
	_hub_balance = _mk_label("", 18, Color(1, 1, 1), Label.ALIGN_CENTER)
	box.add_child(_hub_balance)
	_hub_shop_box = VBoxContainer.new()
	_hub_shop_box.add_constant_override("separation", 8)
	_hub_shop_box.alignment = 1
	box.add_child(_hub_shop_box)
	var b_cont := _mk_button("CONTINUE →")
	b_cont.connect("pressed", self, "_on_hub_continue")
	box.add_child(b_cont)
	var b_htitle := _mk_button("TITLE")
	b_htitle.connect("pressed", self, "_on_back_to_title")
	box.add_child(b_htitle)
	# --- how-to ---
	box = _mk_screen("howto")
	box.add_child(_mk_label("Combat Manual", 18, Color(1.0, 0.78, 0.24), Label.ALIGN_CENTER))
	box.add_child(_mk_label("BEAT KUNE DO", 36, Color(1, 1, 1), Label.ALIGN_CENTER))
	var manual := _mk_label("ARROWS / D-PAD: Move across the dancefloor\n[J] / □ PUNCH: Fast beat jab | [K] / △ KICK: Heavy knockback\n[L] / ○ THROW: Ranged neon drumstick\n[SPACE] / ✕ DODGE: Dash through red attacks\n[S] / L1 PARRY: Deflect & stun attackers\n[F] / ♪ DANCE: Pure dance move — no damage, builds Fever + style variety\n[E] / R1 TAKEDOWN: Spend 1 ★ token (earned every 12 combo — buy more slots in the Green Room) for a cinematic finisher\nBOSS MOVES: beat a chapter boss to take its move — Ch.1 unlocks DASH STRIKE (the dash itself hits), Ch.2 unlocks SPINBACK KICK (wider, harder kicks)\nFEVER: on-beat hits + dance fill it — at 100% FEVER RUSH starts on its own: faster attacks, denser drums, wild lights\nGOLD COUNTER: parry while the gold COUNTER prompt is up to stun & smash\nOFF-BEAT: swings snap to the next beat and still land — only getting hit breaks your combo", 15, Color(1, 1, 1), Label.ALIGN_CENTER)
	manual.autowrap = true
	manual.rect_min_size = Vector2(760, 0)
	box.add_child(manual)
	_howto_moves = _mk_label("", 15, Color(1.0, 0.78, 0.24), Label.ALIGN_CENTER)
	_howto_moves.autowrap = true
	_howto_moves.rect_min_size = Vector2(760, 0)
	box.add_child(_howto_moves)
	var cred := _mk_label(CREDITS_TEXT, 12, Color(0.55, 0.58, 0.65), Label.ALIGN_CENTER)
	cred.autowrap = true
	cred.rect_min_size = Vector2(760, 0)
	box.add_child(cred)
	var b_gotit := _mk_button("GOT IT")
	b_gotit.connect("pressed", self, "_on_back_to_title")
	box.add_child(b_gotit)
	# --- pause (works while the tree is paused) ---
	box = _mk_screen("pause")
	(_screens["pause"] as Control).pause_mode = Node.PAUSE_MODE_PROCESS
	box.add_child(_mk_label("PAUSED", 18, Color(1.0, 0.78, 0.24), Label.ALIGN_CENTER))
	box.add_child(_mk_label("TAKE A BREATH", 36, Color(1, 1, 1), Label.ALIGN_CENTER))
	box.add_child(_mk_label("THE BEAT IS WAITING. TAP TO JUMP BACK IN.", 16, Color(1, 1, 1), Label.ALIGN_CENTER))
	var b_resume := _mk_button("▶ RESUME")
	b_resume.connect("pressed", self, "_on_resume")
	box.add_child(b_resume)

func _cal_text() -> String:
	return ("+" if cal_ms >= 0 else "") + str(cal_ms) + " ms"

func show_screen(name: String) -> void:
	screen = name
	for k in _screens.keys():
		(_screens[k] as Control).visible = (k == name)
	_hud_root.visible = (name == "fight" or name == "pause")
	if name == "hub":
		_refresh_hub()
	if name == "howto":
		_refresh_howto()
	if name == "end":
		pass
	if _screen_boxes.has(name):
		_screen_first_button(_screen_boxes[name])

# --- HUD ---------------------------------------------------------------------------

func _build_hud() -> void:
	_hud_root = Control.new()
	_hud_root.name = "HUD"
	_full_rect(_hud_root)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.visible = false
	_ui_layer.add_child(_hud_root)
	# HP box (14,14,270x56).
	var hp_panel := ColorRect.new()
	hp_panel.color = Color(0, 0, 0, 0.6)
	hp_panel.rect_position = Vector2(14, 14)
	hp_panel.rect_size = Vector2(270, 56)
	hp_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(hp_panel)
	var hp_lab := _mk_label("JAY SLEEZE HP", 14, Color(1, 1, 1))
	hp_lab.rect_position = Vector2(20, 18)
	_hud_root.add_child(hp_lab)
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0.15, 0.05, 0.1)
	hp_bg.rect_position = Vector2(20, 40)
	hp_bg.rect_size = Vector2(250, 14)
	hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(hp_bg)
	var hp_fg := ColorRect.new()
	hp_fg.color = Color(0.2, 0.85, 0.35)
	hp_fg.rect_position = Vector2(20, 40)
	hp_fg.rect_size = Vector2(250, 14)
	hp_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(hp_fg)
	_hud["hp_fg"] = hp_fg
	# Style box (14,78,270x40).
	var st_panel := ColorRect.new()
	st_panel.color = Color(0, 0, 0, 0.6)
	st_panel.rect_position = Vector2(14, 78)
	st_panel.rect_size = Vector2(270, 40)
	st_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(st_panel)
	var st_lab := _mk_label("STYLE D  0/8 MOVES", 14, Color(1, 1, 1))
	st_lab.rect_position = Vector2(20, 82)
	_hud_root.add_child(st_lab)
	_hud["style_label"] = st_lab
	var st_bg := ColorRect.new()
	st_bg.color = Color(0.15, 0.05, 0.1)
	st_bg.rect_position = Vector2(20, 102)
	st_bg.rect_size = Vector2(250, 6)
	st_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(st_bg)
	var st_fg := ColorRect.new()
	st_fg.color = Color(1.0, 0.78, 0.24)
	st_fg.rect_position = Vector2(20, 102)
	st_fg.rect_size = Vector2(6, 6)
	st_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(st_fg)
	_hud["style_fg"] = st_fg
	# Score / combo, top right.
	var score_lab := _mk_label("SCORE 0", 20, Color(1, 1, 1), Label.ALIGN_RIGHT)
	score_lab.rect_position = Vector2(640, 14)
	score_lab.rect_size = Vector2(306, 24)
	_hud_root.add_child(score_lab)
	_hud["score"] = score_lab
	var combo_lab := _mk_label("", 20, Color(1.0, 0.78, 0.24), Label.ALIGN_RIGHT)
	combo_lab.rect_position = Vector2(640, 40)
	combo_lab.rect_size = Vector2(306, 24)
	_hud_root.add_child(combo_lab)
	_hud["combo"] = combo_lab
	# Beat bar (y 496-544).
	var beat_bg := ColorRect.new()
	beat_bg.color = Color(0, 0, 0, 0.55)
	beat_bg.rect_position = Vector2(0, 496)
	beat_bg.rect_size = Vector2(960, 48)
	beat_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(beat_bg)
	var beat_lab := _mk_label("", 16, Color(1, 1, 1))
	beat_lab.rect_position = Vector2(20, 502)
	beat_lab.rect_size = Vector2(420, 20)
	_hud_root.add_child(beat_lab)
	_hud["beat"] = beat_lab
	var parry_lab := _mk_label("", 14, Color(1, 1, 1))
	parry_lab.rect_position = Vector2(20, 524)
	parry_lab.rect_size = Vector2(200, 16)
	_hud_root.add_child(parry_lab)
	_hud["parry"] = parry_lab
	var dash_lab := _mk_label("", 14, Color(1, 1, 1))
	dash_lab.rect_position = Vector2(230, 524)
	dash_lab.rect_size = Vector2(200, 16)
	_hud_root.add_child(dash_lab)
	_hud["dash"] = dash_lab
	var sync_lab := _mk_label("BEAT SYNC", 16, Color(1.0, 0.78, 0.24), Label.ALIGN_RIGHT)
	sync_lab.rect_position = Vector2(700, 502)
	sync_lab.rect_size = Vector2(240, 20)
	_hud_root.add_child(sync_lab)
	_hud["sync"] = sync_lab
	var high_lab := _mk_label("HIGH 0", 14, Color(1, 1, 1), Label.ALIGN_RIGHT)
	high_lab.rect_position = Vector2(700, 524)
	high_lab.rect_size = Vector2(240, 16)
	_hud_root.add_child(high_lab)
	_hud["high"] = high_lab
	# Banner pill (y 120-162) + judgement popup.
	var banner_lab := _mk_label("", 28, Color(1.0, 0.78, 0.24), Label.ALIGN_CENTER)
	banner_lab.rect_position = Vector2(0, 120)
	banner_lab.rect_size = Vector2(960, 42)
	banner_lab.add_color_override("font_shadow_color", Color(0, 0, 0))
	banner_lab.add_constant_override("shadow_offset_x", 2)
	banner_lab.add_constant_override("shadow_offset_y", 2)
	banner_lab.visible = false
	_hud_root.add_child(banner_lab)
	_hud["banner"] = banner_lab
	var judge_lab := _mk_label("", 24, Color(1.0, 0.78, 0.24), Label.ALIGN_CENTER)
	judge_lab.rect_position = Vector2(0, 200)
	judge_lab.rect_size = Vector2(960, 36)
	judge_lab.add_color_override("font_shadow_color", Color(0, 0, 0))
	judge_lab.add_constant_override("shadow_offset_x", 2)
	judge_lab.add_constant_override("shadow_offset_y", 2)
	judge_lab.visible = false
	_hud_root.add_child(judge_lab)
	_hud["judge"] = judge_lab
	_hud["judge_t"] = 0.0

# --- fight flow -----------------------------------------------------------------------

func _on_enter_club() -> void:
	show_screen("mode")

func _on_green_room() -> void:
	hub_origin = "title"
	show_screen("hub")

func _on_controls() -> void:
	show_screen("howto")

func _on_back_to_title() -> void:
	RhythmManager.stop_song()
	_cal_active = false
	_cal_taps.clear()
	show_screen("title")

func _on_back_to_mode() -> void:
	show_screen("mode")

func _on_mode_story(ch: int) -> void:
	chapter = ch
	mode = "story"
	track_key = String(BOSS_INFO[ch]["track"])
	var info: Dictionary = BOSS_INFO[ch]
	_intro_tag.text = "CHAPTER %d — %s · %d BPM" % [ch, info["genre"], int(info["bpm"])]
	_intro_name.text = String(info["name"])
	_intro_title.text = String(info["title"])
	_intro_track.text = "TRACK: %s · %d BPM · %s" % [String(BeatData.TRACKS[track_key]["name"]), int(info["bpm"]), info["genre"]]
	_intro_flavour.text = String(info["flavour"])
	_intro_sig.text = "SIGNATURE: %s." % String(info["sig"])
	show_screen("intro")

func _on_mode_endless(key: String) -> void:
	mode = "endless"
	track_key = key
	wave = 1
	begin_fight()

func _on_intro_fight() -> void:
	if chapter == 3:
		show_screen("story")
	else:
		begin_fight()

func _on_story_fight() -> void:
	begin_fight()

func _fight_title() -> String:
	if mode == "endless":
		var t: Dictionary = BeatData.TRACKS[track_key]
		return "ENDLESS DISCO — %s · %d BPM" % [String(t["name"]), int(t["bpm"])]
	if chapter == 3:
		return "VEX — THE FINAL TEST"
	return "CHAPTER %d" % chapter

func begin_fight() -> void:
	# Clear the last fight's enemies (corpses included).
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			e.queue_free()
	player.fit_tint = FIT_TINTS.get(fit_equipped, Color(1, 1, 1))
	player.reset_fight(PLAYER_SPAWN, max_hp_for())
	score = 0
	_fight_over = false
	_fight_won = false
	_last_fans_earned = 0
	_last_unlock = ""
	speed_mul = 1.0
	dance_break_t = 0.0
	if mode == "story":
		spawn_queue = (BOSS_INFO[chapter]["queue"] as Array).duplicate()
	else:
		spawn_queue = ["stan", "stan", "charger", "bruiser"]
	spawn_timer = 0.5
	RhythmManager.calibration_ms = float(cal_ms)
	RhythmManager.load_track(track_key)
	banner(_fight_title(), 2.2)
	show_screen("fight")

func _on_retry() -> void:
	if mode == "story":
		_on_mode_story(chapter)
	else:
		_on_mode_endless(track_key)

func _on_next_chapter() -> void:
	if mode == "story" and chapter < 3:
		_on_mode_story(chapter + 1)

func _on_end_hub() -> void:
	hub_origin = "end"
	show_screen("hub")

func _on_hub_continue() -> void:
	show_screen(hub_origin)

func _on_resume() -> void:
	get_tree().paused = false
	RhythmManager.pause_song(false)
	show_screen("fight")

func _toggle_pause() -> void:
	if get_tree().paused:
		_on_resume()
	else:
		get_tree().paused = true
		RhythmManager.pause_song(true)
		show_screen("pause")

func spawn_enemy(kind_str: String) -> void:
	var kind_map := {"stan": EnemyScript.Kind.STAN, "charger": EnemyScript.Kind.CHARGER,
		"bruiser": EnemyScript.Kind.BRUISER, "boss1": EnemyScript.Kind.BOSS1,
		"boss2": EnemyScript.Kind.BOSS2, "vex": EnemyScript.Kind.VEX}
	if not kind_map.has(kind_str):
		push_error("Main: unknown enemy kind " + kind_str)
		return
	var e = EnemyScript.new()
	enemies_root.add_child(e)
	e.setup(self, int(kind_map[kind_str]), Vector2(920, 360 + randf() * 90.0), speed_mul)
	e.connect("enemy_died", self, "_on_enemy_died")
	e.connect("boss_phase_changed", self, "_on_boss_phase")

func _on_enemy_died(_enemy) -> void:
	pass  # wave clear is checked in _process (queue empty + no living enemies)

func _on_boss_phase(phase: int) -> void:
	banner("VEX — PHASE %d" % phase, 2.0)

func _on_player_died() -> void:
	if _fight_over:
		return
	end_fight(false)

func _on_judgement_popup(judgement: int, _offset_ms: float, text: String) -> void:
	var lab: Label = _hud["judge"]
	lab.text = text
	match judgement:
		BeatData.Judgement.PERFECT:
			lab.add_color_override("font_color", Color(1.0, 0.78, 0.24))
		BeatData.Judgement.GOOD:
			lab.add_color_override("font_color", Color(0.0, 0.94, 1.0))
		_:
			lab.add_color_override("font_color", Color(1, 1, 1))
	lab.visible = true
	_hud["judge_t"] = 0.5

func end_fight(won: bool) -> void:
	_fight_over = true
	_fight_won = won
	RhythmManager.stop_song()
	_cal_active = false
	if won:
		player.play_pose("hiphop")
	else:
		player.play_pose("knock")
	# Fans: floor(score/100) + 2 per KO (PORT_SPEC.md §7.1).
	_last_fans_earned = int(score / 100) + 2 * player.kos
	fans += _last_fans_earned
	if score > high_score:
		high_score = score
	# Boss unlocks (story wins only).
	_last_unlock = ""
	if won and mode == "story":
		if chapter == 1 and not unlock_dash_strike:
			unlock_dash_strike = true
			_last_unlock = "DASH STRIKE"
		elif chapter == 2 and not unlock_spin_kick:
			unlock_spin_kick = true
			_last_unlock = "SPINBACK KICK"
	_save()
	var end_tag: Label = _end_tag
	var end_title: Label = _end_title
	if won:
		end_tag.text = "STAGE CLEARED"
		end_title.text = "CROWD CONQUERED"
		_end_results.text = "SCORE: %d | MAX COMBO: %dx | PERFECT HITS: %d\nSTYLE: %s (%.0f PTS · %d/8 MOVES)\nFANS EARNED: +%d | FAN BALANCE: %d" % [score, player.max_combo, player.perfects, player.style_rank(), player.style_eff(), player.style_moves.size(), _last_fans_earned, fans]
	else:
		end_tag.text = "BEAT DROPPED"
		end_title.text = "KNOCKED OUT"
		_end_results.text = "FINAL SCORE: %d | MAX COMBO: %dx\nSTYLE: %s (%.0f PTS · %d/8 MOVES)\nFANS EARNED: +%d | FAN BALANCE: %d" % [score, player.max_combo, player.style_rank(), player.style_eff(), player.style_moves.size(), _last_fans_earned, fans]
	_end_unlock.text = ("★ UNLOCKED: %s ★" % _last_unlock) if _last_unlock != "" else ""
	_end_next_btn.visible = won and mode == "story" and chapter < 3
	show_screen("end")

func _living_enemies() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.state != e.State.DEAD:
			n += 1
	return n

func _start_dance_break() -> void:
	dance_break_t = RhythmManager.beat_dur_sec() * 8.0
	player.play_pose("hiphop")
	banner("WAVE CLEAR — DANCE BREAK", 1.6)

func _next_wave() -> void:
	wave += 1
	player.hp = int(min(player.max_hp, player.hp + 15))
	# Vita: no BPM ramp (loops are pre-rendered at the track BPM) — ramp
	# enemy speed and wave size instead (see header note).
	speed_mul = min(1.5, 1.0 + float(wave - 1) * 0.05)
	var qn := int(min(8, 3 + wave))
	var pool := ["stan", "charger", "bruiser", "stan", "charger", "bruiser", "stan", "charger"]
	spawn_queue = []
	for i in range(qn):
		spawn_queue.append(pool[i % pool.size()])
	spawn_timer = 0.5
	player.clear_pose()
	var t: Dictionary = BeatData.TRACKS[track_key]
	banner("WAVE %d — %d BPM" % [wave, int(t["bpm"])], 2.0)

func _separate_enemies() -> void:
	var list := get_tree().get_nodes_in_group("enemies")
	for i in range(list.size()):
		var a = list[i]
		if not is_instance_valid(a) or a.state == a.State.DEAD:
			continue
		for j in range(i + 1, list.size()):
			var b = list[j]
			if not is_instance_valid(b) or b.state == b.State.DEAD:
				continue
			var d: float = a.position.distance_to(b.position)
			if d < 70.0 and d > 0.01:
				var push := min((70.0 - d) / 2.0, 2.0)
				var axis: Vector2 = (b.position - a.position) / d
				a.position -= axis * push
				b.position += axis * push

# --- per-frame -----------------------------------------------------------------------

func _process(delta: float) -> void:
	if _at_active:
		_at_tick(delta)
	if screen == "fight" and not _fight_over:
		if Input.is_action_just_pressed("pause"):
			_toggle_pause()
			return
		# Shake decay + world offset (28 px/s decay, web §1.5).
		_shake = max(0.0, _shake - delta * 28.0)
		if _shake > 0.0:
			world.position = Vector2(rand_range(-1.0, 1.0), rand_range(-1.0, 1.0)) * _shake
		else:
			world.position = Vector2.ZERO
		# Lights layer pulse.
		if bg_lights != null:
			var p := pulse()
			bg_lights.modulate.a = min(1.0, 0.85 + p * 0.35) if is_rushing() else 0.75 + p * 0.25
		# Dance break counts down in seconds; the sim otherwise runs.
		if dance_break_t > 0.0:
			dance_break_t -= delta
			if dance_break_t <= 0.0:
				_next_wave()
		else:
			# Spawning: first 0.5 s, then one per 1.3 s.
			if not spawn_queue.empty():
				spawn_timer -= delta
				if spawn_timer <= 0.0:
					spawn_timer = 1.3
					spawn_enemy(String(spawn_queue.pop_front()))
			# Wave clear: queue empty + no living enemies.
			if spawn_queue.empty() and _living_enemies() == 0:
				if mode == "story":
					end_fight(true)
				else:
					_start_dance_break()
		_separate_enemies()
		_refresh_hud(delta)
	elif screen == "pause":
		if Input.is_action_just_pressed("pause"):
			_on_resume()

func _refresh_hud(delta: float) -> void:
	if player == null:
		return
	var hp_fg: ColorRect = _hud["hp_fg"]
	hp_fg.rect_size.x = 250.0 * clamp(float(player.hp) / float(max(player.max_hp, 1)), 0.0, 1.0)
	var st_lab: Label = _hud["style_label"]
	st_lab.text = "STYLE %s  %d/8 MOVES" % [player.style_rank(), player.style_moves.size()]
	var st_fg: ColorRect = _hud["style_fg"]
	var eff: float = player.style_eff()
	st_fg.rect_size.x = max(6.0, 250.0 * clamp(eff / 160.0, 0.0, 1.0)) if eff > 0.0 else 0.0
	(_hud["score"] as Label).text = "SCORE %d" % score
	var combo_lab: Label = _hud["combo"]
	if player.combo_count > 1:
		combo_lab.text = "%dx COMBO" % player.combo_count
		combo_lab.visible = true
	else:
		combo_lab.visible = false
	var t: Dictionary = BeatData.TRACKS[track_key]
	(_hud["beat"] as Label).text = "%d BPM · %s" % [RhythmManager.bpm, String(t["name"])]
	(_hud["parry"] as Label).text = "PARRY OK" if player._parry_cd <= 0.0 else "PARRY %.1fs" % player._parry_cd
	(_hud["dash"] as Label).text = "DASH OK" if player._dodge_cd <= 0.0 else "DASH %.1fs" % player._dodge_cd
	var sync_lab: Label = _hud["sync"]
	if RhythmManager.playing and abs(RhythmManager._press_offset_ms()) <= 65.0:
		sync_lab.text = "★ PERFECT WINDOW ★"
	else:
		sync_lab.text = "BEAT SYNC"
	(_hud["high"] as Label).text = "HIGH %d" % high_score
	if _banner_t > 0.0:
		_banner_t -= delta
		if _banner_t <= 0.0:
			(_hud["banner"] as Label).visible = false
	var jt: float = float(_hud["judge_t"])
	if jt > 0.0:
		jt -= delta
		_hud["judge_t"] = jt
		if jt <= 0.0:
			(_hud["judge"] as Label).visible = false

# --- stage backdrop ---------------------------------------------------------------------

func _draw() -> void:
	# Vertical gradient #090318 -> #170836 -> #06020D (PORT_SPEC.md §13.2).
	var top := Color(0.035, 0.012, 0.094)
	var mid := Color(0.09, 0.03, 0.21)
	var bot := Color(0.024, 0.008, 0.051)
	for i in range(16):
		var t := float(i) / 15.0
		var c: Color
		if t < 0.5:
			c = top.linear_interpolate(mid, t * 2.0)
		else:
			c = mid.linear_interpolate(bot, (t - 0.5) * 2.0)
		draw_rect(Rect2(0, i * 34, WORLD_W, 34), c)

# --- shop / hub ----------------------------------------------------------------------------

func _refresh_howto() -> void:
	var owned := []
	if unlock_dash_strike:
		owned.append("DASH STRIKE — dash through an enemy to hit them (Ch.1 boss)")
	if unlock_spin_kick:
		owned.append("SPINBACK KICK — kicks hit wider and harder (Ch.2 boss)")
	if owned.empty():
		_howto_moves.text = "NO BOSS MOVES YET — BEAT A CHAPTER BOSS TO TAKE ITS MOVE."
	else:
		_howto_moves.text = "BOSS MOVES OWNED: " + " · ".join(PoolStringArray(owned))

func _refresh_hub() -> void:
	_hub_balance.text = "FANS: %d · MAX HP %d · TOKEN SLOTS %d" % [fans, max_hp_for(), token_cap()]
	for c in _hub_shop_box.get_children():
		c.queue_free()
	for idx in range(SHOP.size()):
		var item: Dictionary = SHOP[idx]
		var row := HBoxContainer.new()
		row.add_constant_override("separation", 10)
		row.alignment = 1
		var lab := _mk_label("%s — %s" % [String(item["name"]), String(item["desc"])], 14, Color(1, 1, 1))
		lab.autowrap = true
		lab.rect_min_size = Vector2(560, 0)
		row.add_child(lab)
		var btn := Button.new()
		btn.add_font_override("font", _font(16))
		btn.rect_min_size = Vector2(130, 40)
		var state := _shop_button_state(item)
		btn.text = state[0]
		btn.disabled = bool(state[1])
		btn.connect("pressed", self, "_on_shop_buy", [idx])
		row.add_child(btn)
		_hub_shop_box.add_child(row)

# Returns [button text, disabled].
func _shop_button_state(item: Dictionary) -> Array:
	var id := String(item["id"])
	match id:
		"hp":
			return ["BUY 50", fans < 50]
		"tokens":
			if shop_tokens >= 2:
				return ["MAXED", true]
			return ["BUY 80", fans < 80]
		"fever":
			if shop_faster_fever:
				return ["OWNED", true]
			return ["BUY 60", fans < 60]
		"combo":
			if shop_combo:
				return ["OWNED", true]
			return ["BUY 100", fans < 100]
		_:
			var fit: String = id.substr(4)
			if not bool(fits_owned.get(fit, false)):
				return ["BUY 40", fans < 40]
			if fit_equipped == fit:
				return ["EQUIPPED", true]
			return ["EQUIP", false]

func _on_shop_buy(idx: int) -> void:
	var item: Dictionary = SHOP[idx]
	var id := String(item["id"])
	match id:
		"hp":
			if fans < 50:
				return
			fans -= 50
			shop_hp += 1
		"tokens":
			if fans < 80 or shop_tokens >= 2:
				return
			fans -= 80
			shop_tokens += 1
		"fever":
			if fans < 60 or shop_faster_fever:
				return
			fans -= 60
			shop_faster_fever = true
		"combo":
			if fans < 100 or shop_combo:
				return
			fans -= 100
			shop_combo = true
		_:
			var fit: String = id.substr(4)
			if not bool(fits_owned.get(fit, false)):
				if fans < 40:
					return
				fans -= 40
				fits_owned[fit] = true
			fit_equipped = fit
	_save()
	_refresh_hub()

# --- calibration ------------------------------------------------------------------------------

func _on_cal_slider(value: float) -> void:
	cal_ms = int(value)
	RhythmManager.calibration_ms = float(cal_ms)
	_cal_value.text = _cal_text()
	_save()

func _on_tap_along() -> void:
	if not _cal_active:
		# Start: 120 BPM click track (dceased), 8 taps.
		_cal_taps.clear()
		_cal_active = true
		RhythmManager.calibration_ms = float(cal_ms)
		if not RhythmManager.load_track("dceased"):
			_cal_status.text = "MUSIC DIDN'T START — TRY AGAIN"
			_cal_active = false
			return
		_cal_status.text = "TAP 8 TIMES ON THE CLICK — %d/8" % _cal_taps.size()
		return
	# A tap: signed offset to the nearest beat on the RAW audio clock
	# (song_position_ms subtracts calMs, so add it back).
	var off: float = RhythmManager._press_offset_ms() + RhythmManager.calibration_ms
	if abs(off) > 900.0:
		_cal_status.text = "WAIT FOR THE BEAT, THEN TAP"
		return
	_cal_taps.append(off)
	if _cal_taps.size() >= 8:
		var avg := 0.0
		for o in _cal_taps:
			avg += float(o)
		avg /= float(_cal_taps.size())
		cal_ms = int(clamp(round(avg), -150, 150))
		RhythmManager.calibration_ms = float(cal_ms)
		_cal_slider.value = cal_ms
		_cal_value.text = _cal_text()
		_save()
		_cal_active = false
		_cal_taps.clear()
		RhythmManager.stop_song()
		_cal_status.text = "CALIBRATION SET: %s" % _cal_text()
	else:
		_cal_status.text = "TAP 8 TIMES ON THE CLICK — %d/8" % _cal_taps.size()

# --- auto-test -----------------------------------------------------------------------
# Scripted smoke run. Jumps straight into chapter 1 (MY LUVA, 100 BPM), walks
# the player at the nearest living enemy and queues punch/kick on a timer.
# The beat clock depends on the real audio clock: under a dummy audio driver
# (headless) get_playback_position() may not advance, so no beat fires and
# queued attacks would sit pending forever — if that happens we log it once
# and force-fire the queue so combat still gets exercised. The log line
# tells you which case you are in; it does not hide it.

func _at_tick(delta: float) -> void:
	_at_t += delta
	if not _at_started:
		_at_started = true
		_on_mode_story(1)
		_on_intro_fight()
		print("AUTOTEST fight started: chapter=1 track=", track_key, " bpm=", RhythmManager.bpm, " playing=", RhythmManager.playing)
		return
	if screen == "fight" and not _fight_over and player != null:
		# Walk at the nearest living enemy.
		var target = null
		var best_d := 1.0e9
		for e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e) or e.state == e.State.DEAD:
				continue
			var d: float = abs(e.position.x - player.position.x)
			if d < best_d:
				best_d = d
				target = e
		if target != null:
			if target.position.x > player.position.x + 20.0:
				Input.action_press("move_right")
				Input.action_release("move_left")
			elif target.position.x < player.position.x - 20.0:
				Input.action_press("move_left")
				Input.action_release("move_right")
			else:
				Input.action_release("move_left")
				Input.action_release("move_right")
		# Queue an attack every 0.55 s, alternating punch/kick.
		if _at_t >= _at_next_atk:
			_at_next_atk = _at_t + 0.55
			player._queue_attack(0 if int(_at_t * 2.0) % 2 == 0 else 1)
			# Dummy-audio fallback: no beat fired in the first 3 s of the
			# fight, so the queue would never fire on its own. Force it.
			if RhythmManager.playing and RhythmManager.beat_index < 0 and _at_t > 3.0:
				if not _at_beat_stall_warned:
					_at_beat_stall_warned = true
					print("AUTOTEST beat clock STALLED (dummy audio?): beat_index=", RhythmManager.beat_index, " — force-firing queued attacks")
				player._fire_queued()
		if _at_t >= _at_next_status:
			_at_next_status = _at_t + 5.0
			print("AUTOTEST t=%.1f beat=%d score=%d combo=%d hp=%d/%d enemies=%d pos=(%.0f,%.0f) playing=%s" % [_at_t, RhythmManager.beat_index, score, player.combo_count, player.hp, player.max_hp, _living_enemies(), player.position.x, player.position.y, str(RhythmManager.playing)])
		if not _at_shot and _at_t > 8.0:
			_at_shot = true
			_at_shot_png("user://autotest_fight.png")
	if _at_t >= _at_dur or screen == "end":
		print("AUTOTEST DONE t=%.1f screen=%s score=%d high=%d fight_won=%s beats=%d" % [_at_t, screen, score, high_score, str(_fight_won), RhythmManager.beat_index])
		_at_shot_png("user://autotest_end.png")
		get_tree().quit()

func _at_shot_png(path: String) -> void:
	# Godot 3.5: ViewportTexture has get_data(), not get_image(). The data
	# comes back vertically flipped (GL origin is bottom-left) — flip it.
	var img: Image = get_viewport().get_texture().get_data()
	img.flip_y()
	if img == null:
		print("AUTOTEST shot FAILED (no image): ", path)
		return
	var err := img.save_png(path)
	print("AUTOTEST shot ", path, " err=", err, " size=", img.get_size())
