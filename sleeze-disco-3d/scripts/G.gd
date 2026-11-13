extends Node
# Global game state + rules shared with the HTML master (v7.7):
# judge windows, Fever table, style rank, damage numbers, hit-stop.

const L_WORLD = 1
const L_PLAYER = 2
const L_ENEMY = 4
const L_HITBOX = 8
const L_HURTBOX = 16

const PERFECT_WIN = 0.065
const GOOD_WIN = 0.13
const FEVER = {"PERFECT": 12, "GOOD": 7, "HIT": 0, "COUNTER": 10, "PARRY": 15, "PARRY_OFF": 3, "KO": 6}
const DMG = {"punch": 11, "kick": 16, "counter": 20, "finisher": 65}
const COL = {
	"gold": Color(1.0, 0.82, 0.25), "cyan": Color(0.2, 0.95, 1.0), "pink": Color(1.0, 0.25, 0.75),
	"purple": Color(0.62, 0.3, 1.0), "red": Color(1.0, 0.2, 0.2), "white": Color(1, 1, 1), "grey": Color(0.55, 0.58, 0.65)
}

var meta = {}            # clip metadata per character (data/clipmeta.json)
var bot = false          # scripted-input test mode (--bot)
var shots = false        # write screenshots in bot mode
var test_frames = 3000
var cli_profile = ""      # --profile=A..G skips the boot menu

# fight state
var score = 0
var combo = 0
var max_combo = 0
var perfects = 0
var kos = 0
var style = 0.0
var style_moves = {}
var fever = 0.0
var rush_beats = 0.0     # >0 while FEVER RUSH runs (counts down in beats)
var stars = 0
var star_cap = 3
var hp = 100.0
var max_hp = 100.0
var wave = 0
var game_over = false
var stats = {"hits": 0, "parries": 0, "counters": 0, "finishers": 0, "player_hits_taken": 0, "kos": 0, "ragdolls": 0}

# hit-stop / time-dip (real-time, so it survives Engine.time_scale)
var _stop_until = 0
var _dip_until = 0
var _dip_scale = 1.0

signal judged(text, color, pos3d)
signal flash(strength)

# ------------------------------------------------------------------ boot profiles + log
# v0.1.1 diagnostic build: Boot.tscn picks a profile before the arena loads.
# v0.1.2: glow post-FX is OFF in every profile. It haloed the fighters
# (bloom around their emissive materials) and cost a full-screen post pass
# on the Vita GPU. Emission is also zeroed on all character materials, so
# there is nothing left to bloom. C keeps DOF, D keeps fog + DOF + crowd.
# v0.2 PSX: EVERY profile renders at 480x272 internal (viewport stretch,
# integer 2x up to the 960x544 screen) — the Vita's PVR is fill-rate bound,
# and a quarter of the pixels is the cheapest win in the whole game. The
# v0.1.2 test ran 1-5 FPS at 26 draws / 18k verts, so the GPU was doing
# almost nothing; the bottleneck is per-frame CPU/driver cost, and the
# 480x272 cut + 30 Hz physics + no AnimationTree/IK/ragdoll is the attack.
const PROFILES = {
	"A": {"label": "SAFE  (480x272 PSX v0.2, no FX, no crowd, 2 thugs)", "fog": false, "glow": false, "dof": false, "crowd": false, "max_alive": 2},
	"B": {"label": "SAFE + FOG  (480x272 PSX v0.2)", "fog": true, "glow": false, "dof": false, "crowd": false, "max_alive": 2},
	"C": {"label": "SAFE + DOF  (480x272 PSX v0.2)", "fog": false, "glow": false, "dof": true, "crowd": false, "max_alive": 2},
	"D": {"label": "FULL  (480x272 PSX v0.2, fog, DOF, crowd)", "fog": true, "glow": false, "dof": true, "crowd": true, "max_alive": 4},
	# v0.2.1 bisect (issues #1/#2). Each is A plus ONE change, so the A-vs-X
	# fps and crash difference isolates one cost. Hypothesis under test: the
	# per-frame cost is skeleton pose updates -> skinning (CPU software skin +
	# vertex re-upload, or bone-texture re-upload) going through the PVR
	# driver every frame, which would also explain the uncached-heap overrun.
	"E": {"label": "A + FROZEN ANIM  (skeletons never re-pose)", "fog": false, "glow": false, "dof": false, "crowd": false, "max_alive": 2, "freeze_anim": true},
	"F": {"label": "A + HIDDEN FIGHTERS  (gameplay runs, no skinned draws)", "fog": false, "glow": false, "dof": false, "crowd": false, "max_alive": 2, "hide_fighters": true},
	"G": {"label": "A + NO HUD  (no 2D canvas / text redraw)", "fog": false, "glow": false, "dof": false, "crowd": false, "max_alive": 2, "no_hud": true},
}

func flag(name):
	return PROFILES[profile].get(name, false)
var profile = "A"
var log_path = ""

func cfg():
	return PROFILES[profile]

func apply_profile(p):
	profile = p
	var c = PROFILES[p]
	blog("profile " + p + ": " + c.label)
	# PSX v0.2: always 480x272 internal, upscaled 2x to the 960x544 screen.
	get_tree().set_screen_stretch(SceneTree.STRETCH_MODE_VIEWPORT, SceneTree.STRETCH_ASPECT_KEEP, Vector2(480, 272))

func _open_log():
	# try the Vita data folder first, fall back to user://
	var d = Directory.new()
	for base in ["ux0:data/SLZD00002", "user:/"]:
		if base != "user:/":
			d.make_dir_recursive(base)
		var path = base + "/boot.log"
		var f = File.new()
		if f.open(path, File.WRITE) == OK:
			f.store_line("SLEEZE DISCO 3D v0.2.1 DIAG boot log")
			f.close()
			log_path = path
			return

func blog(msg):
	# line-flushed: reopen + append + close every call so a hang keeps the last line
	var line = "[%6d ms] %s" % [OS.get_ticks_msec(), msg]
	print(line)
	if log_path == "":
		return
	var f = File.new()
	if f.open(log_path, File.READ_WRITE) == OK:
		f.seek_end()
		f.store_line(line)
		f.close()

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	_open_log()
	blog("G ready, log=" + log_path)
	var f = File.new()
	if f.open("res://data/clipmeta.json", File.READ) == OK:
		meta = parse_json(f.get_as_text())
		f.close()
	var args = OS.get_cmdline_args()
	for a in args:
		if a == "--bot":
			bot = true
		elif a == "--shots":
			shots = true
		elif a.begins_with("--profile="):
			cli_profile = a.split("=")[1].to_upper()
		elif a.begins_with("--frames="):
			test_frames = int(a.split("=")[1])
	_setup_input()

func reset_fight():
	score = 0; combo = 0; max_combo = 0; perfects = 0; kos = 0; style = 0.0; style_moves = {}
	fever = 0.0; rush_beats = 0.0; stars = 0; hp = max_hp; wave = 0; game_over = false

# ------------------------------------------------------------------ input
func _add_action(name, keys, buttons, axis = -1, axis_sign = 0):
	if not InputMap.has_action(name):
		InputMap.add_action(name, 0.25)
	for k in keys:
		var e = InputEventKey.new(); e.scancode = k
		InputMap.action_add_event(name, e)
	for b in buttons:
		var j = InputEventJoypadButton.new(); j.button_index = b
		InputMap.action_add_event(name, j)
	if axis >= 0:
		var m = InputEventJoypadMotion.new(); m.axis = axis; m.axis_value = axis_sign
		InputMap.action_add_event(name, m)

func _setup_input():
	# Vita pad through Godot's SDL-style mapping: 0=✕ 1=○ 2=□ 3=△ 4=L 5=R 10=SELECT 11=START
	_add_action("move_left", [KEY_A], [JOY_DPAD_LEFT], JOY_AXIS_0, -1)
	_add_action("move_right", [KEY_D], [JOY_DPAD_RIGHT], JOY_AXIS_0, 1)
	_add_action("move_up", [KEY_W], [JOY_DPAD_UP], JOY_AXIS_1, -1)
	_add_action("move_down", [KEY_S], [JOY_DPAD_DOWN], JOY_AXIS_1, 1)
	_add_action("cam_left", [KEY_LEFT], [], JOY_AXIS_2, -1)
	_add_action("cam_right", [KEY_RIGHT], [], JOY_AXIS_2, 1)
	_add_action("cam_up", [KEY_UP], [], JOY_AXIS_3, -1)
	_add_action("cam_down", [KEY_DOWN], [], JOY_AXIS_3, 1)
	_add_action("punch", [KEY_J], [JOY_SONY_SQUARE])
	_add_action("kick", [KEY_K], [JOY_SONY_TRIANGLE])
	_add_action("parry", [KEY_L], [JOY_SONY_CIRCLE])
	_add_action("dash", [KEY_SPACE], [JOY_SONY_X])
	_add_action("lock", [KEY_Q], [JOY_L])
	_add_action("finisher", [KEY_E], [JOY_R])
	_add_action("pause", [KEY_ESCAPE, KEY_ENTER], [JOY_START])
	_add_action("ui_select_alt", [KEY_TAB], [JOY_SELECT])

# ------------------------------------------------------------------ judge
func judge_offset(off):
	if off <= PERFECT_WIN:
		return {"name": "PERFECT!", "mult": 1.5, "color": COL.gold}
	if off <= GOOD_WIN:
		return {"name": "GOOD", "mult": 1.1, "color": COL.cyan}
	return {"name": "HIT", "mult": 1.0, "color": COL.white}

func judge_parry(off):
	if off <= PERFECT_WIN:
		return {"name": "PERFECT!", "mult": 1.5, "color": COL.gold}
	if off <= GOOD_WIN:
		return {"name": "GOOD", "mult": 1.1, "color": COL.cyan}
	return {"name": "MISS", "mult": 0.6, "color": COL.grey}

# ------------------------------------------------------------------ fever / style / score
func add_fever(n):
	if rush_beats > 0:
		return
	fever = min(100.0, fever + n)
	if fever >= 100.0:
		rush_beats = 8.0
		emit_signal("judged", "FEVER RUSH!", COL.pink, null)
		emit_signal("flash", 1.4)

func on_beat_tick():
	if rush_beats > 0:
		rush_beats -= 1.0
		fever = 100.0 * rush_beats / 8.0
		if rush_beats <= 0:
			rush_beats = 0; fever = 0

func rushing():
	return rush_beats > 0

func style_eff():
	return style * (1.0 + 0.1 * style_moves.size())

func style_rank():
	var s = style_eff()
	if s >= 160: return "SLEEZE"
	if s >= 110: return "S"
	if s >= 70: return "A"
	if s >= 40: return "B"
	if s >= 20: return "C"
	return "D"

func rank_mult():
	return {"D": 1.0, "C": 1.1, "B": 1.2, "A": 1.3, "S": 1.4, "SLEEZE": 1.5}[style_rank()]

func gain_score(n):
	var g = int(round(n * rank_mult()))
	score += g
	return g

func landed(j, move, fever_ok = true):
	combo += 1
	max_combo = max(max_combo, combo)
	style_moves[move] = true
	if j.name == "PERFECT!":
		perfects += 1; style += 3
	elif j.name == "GOOD":
		style += 1
	if fever_ok:
		if j.name == "PERFECT!": add_fever(FEVER.PERFECT)
		elif j.name == "GOOD": add_fever(FEVER.GOOD)
		elif j.name == "COUNTER": add_fever(FEVER.COUNTER)
	if combo % 12 == 0 and stars < star_cap:
		stars += 1
		emit_signal("judged", "★ FINISHER READY", COL.gold, null)
	gain_score(10 + (5 if j.name == "PERFECT!" else 0))

func player_hurt(dmg):
	hp = max(0.0, hp - dmg)
	combo = 0
	style *= 0.75
	stats.player_hits_taken += 1

# ------------------------------------------------------------------ hit-stop + time dip
func hit_stop(ms):
	_stop_until = max(_stop_until, OS.get_ticks_msec() + int(ms))

func time_dip(ms, scale):
	_dip_until = OS.get_ticks_msec() + int(ms)
	_dip_scale = scale

func _process(_d):
	var now = OS.get_ticks_msec()
	var ts = 1.0
	if now < _dip_until:
		ts = _dip_scale
	if now < _stop_until:
		ts = 0.03
	if get_tree().paused:
		ts = 1.0
	Engine.time_scale = ts

func real_delta(delta):
	return delta / max(Engine.time_scale, 0.001)
